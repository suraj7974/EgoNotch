import SwiftUI
import Observation

/// The Chrome offline runner, which is what a notch-shaped screen was born
/// for: one line of ground, one jump button, obstacles that come faster.
///
/// Difficulty is the whole design here — speed climbs the entire run, cacti
/// start arriving in clusters, and birds join in at two heights: low ones you
/// jump, high ones you duck under (↓).
@MainActor
@Observable
final class DinoGame: GameModel {
    private(set) var score = 0
    private(set) var isOver = false
    private(set) var hasStarted = false

    private var runnerY: Double = 0          // height above the ground
    private var velocity: Double = 0
    private var duckTimer: Double = 0
    private var obstacles: [Obstacle] = []
    private var speed: Double = 280
    private var distance: Double = 0
    private var nextSpawn: Double = 1.2

    private struct Obstacle {
        var x: Double
        var width: Double
        var height: Double
        /// Cacti sit on the ground; birds fly this far above it.
        var offGround: Double
        var isBird: Bool { offGround > 0 }
    }

    private let gravity: Double = 2200
    private let jumpVelocity: Double = 640
    private let standingSize = CGSize(width: 18, height: 24)
    private let duckingSize = CGSize(width: 24, height: 13)

    private var isDucking: Bool { duckTimer > 0 && runnerY <= 0.01 }
    private var runnerSize: CGSize { isDucking ? duckingSize : standingSize }

    func reset() {
        score = 0
        isOver = false
        hasStarted = false
        runnerY = 0
        velocity = 0
        duckTimer = 0
        obstacles = []
        speed = 280
        distance = 0
        nextSpawn = 1.2
    }

    func press(_ key: GameKey) {
        switch key {
        case .action, .up:
            if isOver || !hasStarted {
                reset()
                hasStarted = true
                return
            }
            if runnerY <= 0.01 {
                duckTimer = 0
                velocity = jumpVelocity
            }
        case .down:
            guard hasStarted, !isOver else { return }
            if runnerY > 0.01 {
                velocity = min(velocity, -520)   // slam back down out of a jump
            } else {
                duckTimer = 0.65                 // stays down while you keep pressing
            }
        default:
            break
        }
    }

    func step(dt: Double, size: CGSize) {
        guard hasStarted, !isOver else { return }

        // The difficulty curve: speed climbs the whole run instead of settling.
        distance += speed * dt
        speed = min(280 + distance / 55, 900)
        score = Int(distance / 10)

        duckTimer = max(0, duckTimer - dt)

        velocity -= gravity * dt
        runnerY = max(runnerY + velocity * dt, 0)
        if runnerY == 0 { velocity = 0 }

        nextSpawn -= dt
        if nextSpawn <= 0 {
            spawn(size: size)
            // Gaps shrink with speed, but never below what's clearable: the
            // jump arc takes ~0.58s, so leave that plus a margin.
            let travel = Double.random(in: 0.85...1.7) * (320 / speed)
            nextSpawn = max(0.62, travel)
        }

        for index in obstacles.indices { obstacles[index].x -= speed * dt }
        obstacles.removeAll { $0.x + $0.width < -30 }

        if collides(size: size) { isOver = true }
    }

    private func spawn(size: CGSize) {
        let ground = groundY(size)
        // Birds arrive once you're moving, and get more common with speed.
        let birdChance = speed > 360 ? min(0.42, (speed - 360) / 1000) : 0
        if Double.random(in: 0...1) < birdChance, canSpawnBird(size: size) {
            // Birds fly THROUGH the jump arc: stay on the ground and they sail
            // over you, jump into one and you're done. That inverts the reflex
            // the cacti train, which is what makes them dangerous.
            let clearance = standingSize.height + 3
            obstacles.append(Obstacle(x: size.width + 20, width: 26, height: 13,
                                      offGround: Double.random(in: clearance...(clearance + 14))))
            return
        }

        // Cacti come in clusters more often the faster it gets.
        let clusterChance = min(0.5, max(0, (speed - 330) / 900))
        let count = Double.random(in: 0...1) < clusterChance ? Int.random(in: 2...3) : 1
        var x = size.width + 20
        for _ in 0..<count {
            let width = Double.random(in: 9...15)
            let height = Double.random(in: 20...32)
            obstacles.append(Obstacle(x: x, width: width, height: height, offGround: 0))
            x += width + Double.random(in: 3...7)
        }
    }

    /// Never put a bird over a cactus: that combination demands a jump and
    /// punishes it at the same time, which is unwinnable rather than hard.
    private func canSpawnBird(size: CGSize) -> Bool {
        let safeGap = 240.0
        return !obstacles.contains { !$0.isBird && $0.x > size.width - safeGap }
    }

    private func collides(size: CGSize) -> Bool {
        let runner = CGRect(x: 42, y: runnerY,
                            width: runnerSize.width, height: runnerSize.height)
            .insetBy(dx: 3, dy: 2)
        return obstacles.contains { obstacle in
            runner.intersects(CGRect(x: obstacle.x, y: obstacle.offGround,
                                     width: obstacle.width, height: obstacle.height))
        }
    }

    private func groundY(_ size: CGSize) -> Double { size.height - 26 }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let ground = groundY(size)

        drawSky(&context, size: size, ground: ground)
        drawGround(&context, size: size, ground: ground)
        drawRunner(&context, ground: ground)

        for obstacle in obstacles {
            if obstacle.isBird {
                drawBird(&context, obstacle: obstacle, ground: ground)
            } else {
                drawCactus(&context, obstacle: obstacle, ground: ground)
            }
        }
    }

    // MARK: - Sprites
    //
    // Drawn as shapes rather than boxes: a runner reads as a runner only when
    // it has a head, a tail and legs that alternate.

    /// Clouds drift at a fraction of the ground speed — cheap parallax that
    /// sells the sense of movement more than anything else here.
    private func drawSky(_ context: inout GraphicsContext, size: CGSize, ground: Double) {
        let drift = distance * 0.18
        for index in 0..<3 {
            let spacing = size.width / 2.2
            let x = size.width - (drift + Double(index) * spacing)
                .truncatingRemainder(dividingBy: size.width + 120) + 60
            let y = 14 + Double((index * 13) % 22)
            let cloud = CGRect(x: x, y: y, width: 34, height: 9)
            context.fill(Path(roundedRect: cloud, cornerRadius: 4.5),
                         with: .color(Ego.textMute.opacity(0.22)))
            context.fill(Path(roundedRect: CGRect(x: x + 9, y: y - 4, width: 17, height: 9),
                              cornerRadius: 4.5),
                         with: .color(Ego.textMute.opacity(0.22)))
        }
    }

    private func drawGround(_ context: inout GraphicsContext, size: CGSize, ground: Double) {
        var line = Path()
        line.move(to: CGPoint(x: 0, y: ground))
        line.addLine(to: CGPoint(x: size.width, y: ground))
        context.stroke(line, with: .color(Ego.textMute.opacity(0.75)), lineWidth: 1.5)

        // Pebbles scrolling under the line: the speedometer of the game.
        for index in 0..<14 {
            let spacing = size.width / 14
            let x = (Double(index) * spacing - distance.truncatingRemainder(dividingBy: spacing))
            let y = ground + 5 + Double((index * 7) % 3) * 2.5
            context.fill(Path(roundedRect: CGRect(x: x, y: y,
                                                  width: Double(3 + index % 3), height: 1.5),
                              cornerRadius: 0.75),
                         with: .color(Ego.textMute.opacity(0.45)))
        }
    }

    private func drawRunner(_ context: inout GraphicsContext, ground: Double) {
        let x: Double = 42
        let feet = ground - runnerY
        let scale = standingSize.height / 24

        if isDucking {
            // Crouched: long and low, head forward.
            var crouch = Path()
            crouch.addRoundedRect(in: CGRect(x: x - 6 * scale, y: feet - 11 * scale,
                                             width: 20 * scale, height: 8 * scale),
                                  cornerSize: CGSize(width: 3, height: 3))
            crouch.addRoundedRect(in: CGRect(x: x + 11 * scale, y: feet - 13 * scale,
                                             width: 10 * scale, height: 8 * scale),
                                  cornerSize: CGSize(width: 3, height: 3))
            crouch.addRoundedRect(in: CGRect(x: x - 12 * scale, y: feet - 10 * scale,
                                             width: 8 * scale, height: 4 * scale),
                                  cornerSize: CGSize(width: 2, height: 2))
            context.fill(crouch, with: .color(Ego.text))
            context.fill(Path(ellipseIn: CGRect(x: x + 16 * scale, y: feet - 11 * scale,
                                                width: 2.2, height: 2.2)),
                         with: .color(.black))
            let stride = sin(distance / 12) > 0
            var legs = Path()
            legs.addRoundedRect(in: CGRect(x: x + (stride ? 0 : 5) * scale, y: feet - 4 * scale,
                                           width: 3.5 * scale, height: 4 * scale),
                                cornerSize: CGSize(width: 1.5, height: 1.5))
            legs.addRoundedRect(in: CGRect(x: x + (stride ? 8 : 12) * scale, y: feet - 4 * scale,
                                           width: 3.5 * scale, height: 4 * scale),
                                cornerSize: CGSize(width: 1.5, height: 1.5))
            context.fill(legs, with: .color(Ego.text))
            return
        }

        var dino = Path()
        // Tail, body, neck and head as one silhouette.
        dino.addRoundedRect(in: CGRect(x: x - 7 * scale, y: feet - 15 * scale,
                                       width: 9 * scale, height: 5 * scale),
                            cornerSize: CGSize(width: 2, height: 2))
        dino.addRoundedRect(in: CGRect(x: x - 2 * scale, y: feet - 17 * scale,
                                       width: 13 * scale, height: 10 * scale),
                            cornerSize: CGSize(width: 3, height: 3))
        dino.addRoundedRect(in: CGRect(x: x + 6 * scale, y: feet - 24 * scale,
                                       width: 10 * scale, height: 9 * scale),
                            cornerSize: CGSize(width: 3, height: 3))
        dino.addRoundedRect(in: CGRect(x: x + 13 * scale, y: feet - 20 * scale,
                                       width: 6 * scale, height: 4 * scale),
                            cornerSize: CGSize(width: 1.5, height: 1.5))
        context.fill(dino, with: .color(Ego.text))

        context.fill(Path(ellipseIn: CGRect(x: x + 12 * scale, y: feet - 22 * scale,
                                            width: 2.2, height: 2.2)),
                     with: .color(.black))

        // Legs: mid-stride while running, both tucked while airborne.
        let airborne = runnerY > 0.5
        let stride = sin(distance / 14)
        let front = airborne ? -3.0 : (stride > 0 ? 0 : -2.5)
        let back = airborne ? -3.0 : (stride > 0 ? -2.5 : 0)
        var legs = Path()
        legs.addRoundedRect(in: CGRect(x: x + 1 * scale, y: feet - 7 * scale,
                                       width: 3.5 * scale, height: (7 + back) * scale),
                            cornerSize: CGSize(width: 1.5, height: 1.5))
        legs.addRoundedRect(in: CGRect(x: x + 7 * scale, y: feet - 7 * scale,
                                       width: 3.5 * scale, height: (7 + front) * scale),
                            cornerSize: CGSize(width: 1.5, height: 1.5))
        context.fill(legs, with: .color(Ego.text))

        context.fill(Path(roundedRect: CGRect(x: x + 8 * scale, y: feet - 14 * scale,
                                              width: 4 * scale, height: 2.4 * scale),
                          cornerRadius: 1),
                     with: .color(.black.opacity(0.55)))
    }

    private func drawCactus(_ context: inout GraphicsContext, obstacle: Obstacle, ground: Double) {
        let width = obstacle.width
        let height = obstacle.height
        let x = obstacle.x
        var cactus = Path()
        cactus.addRoundedRect(in: CGRect(x: x, y: ground - height, width: width, height: height),
                              cornerSize: CGSize(width: width / 2.4, height: width / 2.4))
        if height > 22 {
            cactus.addRoundedRect(in: CGRect(x: x - width * 0.55, y: ground - height * 0.72,
                                             width: width * 0.5, height: height * 0.34),
                                  cornerSize: CGSize(width: 2, height: 2))
            cactus.addRoundedRect(in: CGRect(x: x - width * 0.55, y: ground - height * 0.72,
                                             width: width * 1.1, height: width * 0.45),
                                  cornerSize: CGSize(width: 2, height: 2))
        }
        if height > 26 {
            cactus.addRoundedRect(in: CGRect(x: x + width * 1.05, y: ground - height * 0.86,
                                             width: width * 0.5, height: height * 0.4),
                                  cornerSize: CGSize(width: 2, height: 2))
            cactus.addRoundedRect(in: CGRect(x: x + width * 0.5, y: ground - height * 0.58,
                                             width: width * 1.05, height: width * 0.45),
                                  cornerSize: CGSize(width: 2, height: 2))
        }
        context.fill(cactus, with: .color(Ego.win))
    }

    /// A pterodactyl in profile, flying left: beak, swept body, forked tail and
    /// a wing that beats above and below. Boxes read as debris; this reads as
    /// something coming at you.
    private func drawBird(_ context: inout GraphicsContext, obstacle: Obstacle, ground: Double) {
        let width = obstacle.width
        let midY = ground - obstacle.offGround - obstacle.height / 2
        let x = obstacle.x
        let up = sin(distance / 7) > 0

        var body = Path()
        body.move(to: CGPoint(x: x, y: midY + 1))                     // beak tip
        body.addLine(to: CGPoint(x: x + width * 0.26, y: midY - 5))   // brow
        body.addLine(to: CGPoint(x: x + width * 0.62, y: midY - 4))
        body.addLine(to: CGPoint(x: x + width, y: midY - 6))          // tail top
        body.addLine(to: CGPoint(x: x + width * 0.78, y: midY + 1))
        body.addLine(to: CGPoint(x: x + width, y: midY + 6))          // tail bottom
        body.addLine(to: CGPoint(x: x + width * 0.5, y: midY + 5))
        body.addLine(to: CGPoint(x: x + width * 0.2, y: midY + 3))
        body.closeSubpath()
        context.fill(body, with: .color(Ego.accentSoft))

        var wing = Path()
        if up {
            wing.move(to: CGPoint(x: x + width * 0.34, y: midY - 3))
            wing.addLine(to: CGPoint(x: x + width * 0.60, y: midY - 15))
            wing.addLine(to: CGPoint(x: x + width * 0.86, y: midY - 3))
        } else {
            wing.move(to: CGPoint(x: x + width * 0.34, y: midY + 2))
            wing.addLine(to: CGPoint(x: x + width * 0.60, y: midY + 13))
            wing.addLine(to: CGPoint(x: x + width * 0.86, y: midY + 2))
        }
        wing.closeSubpath()
        context.fill(wing, with: .color(Ego.accentSoft.opacity(0.9)))

        context.fill(Path(ellipseIn: CGRect(x: x + width * 0.26, y: midY - 3.4,
                                            width: 2.4, height: 2.4)),
                     with: .color(.black))
    }
}
