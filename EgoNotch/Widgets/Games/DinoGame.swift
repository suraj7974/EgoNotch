import SwiftUI
import Observation

/// The Chrome offline runner, which is what a notch-shaped screen was born
/// for: one line of ground, one jump button, obstacles that come faster.
@MainActor
@Observable
final class DinoGame: GameModel {
    private(set) var score = 0
    private(set) var isOver = false
    private(set) var hasStarted = false

    private var runnerY: Double = 0          // height above the ground
    private var velocity: Double = 0
    private var obstacles: [Obstacle] = []
    private var speed: Double = 260
    private var distance: Double = 0
    private var nextSpawn: Double = 1.2

    private struct Obstacle {
        var x: Double
        var width: Double
        var height: Double
        /// Birds fly; cacti sit on the ground.
        var offGround: Double
    }

    private let gravity: Double = 2200
    private let jumpVelocity: Double = 620
    private let runnerSize = CGSize(width: 18, height: 22)

    func reset() {
        score = 0
        isOver = false
        hasStarted = false
        runnerY = 0
        velocity = 0
        obstacles = []
        speed = 260
        distance = 0
        nextSpawn = 1.2
    }

    func press(_ key: GameKey) {
        switch key {
        case .action, .up:
            if isOver || !hasStarted {
                let restarting = isOver
                reset()
                hasStarted = true
                if restarting { return }        // don't jump straight into a cactus
                return
            }
            if runnerY <= 0.01 { velocity = jumpVelocity }
        default:
            break
        }
    }

    func step(dt: Double, size: CGSize) {
        guard hasStarted, !isOver else { return }

        // Speed climbs with distance — the whole difficulty curve.
        distance += speed * dt
        speed = min(260 + distance / 90, 620)
        score = Int(distance / 10)

        velocity -= gravity * dt
        runnerY = max(runnerY + velocity * dt, 0)
        if runnerY == 0 { velocity = 0 }

        nextSpawn -= dt
        if nextSpawn <= 0 {
            spawn(size: size)
            // Gap shrinks as it speeds up, but never below what's jumpable.
            nextSpawn = Double.random(in: 0.75...1.5) * (300 / speed) + 0.35
        }

        for index in obstacles.indices { obstacles[index].x -= speed * dt }
        obstacles.removeAll { $0.x + $0.width < 0 }

        if collides(size: size) { isOver = true }
    }

    private func spawn(size: CGSize) {
        let ground = groundY(size)
        let flying = Bool.random() && speed > 380
        obstacles.append(Obstacle(
            x: size.width + 20,
            width: flying ? 22 : Double.random(in: 10...18),
            height: flying ? 12 : Double.random(in: 18...30),
            offGround: flying ? min(34, ground * 0.45) : 0))
    }

    private func collides(size: CGSize) -> Bool {
        let runner = CGRect(x: 42, y: runnerY, width: runnerSize.width, height: runnerSize.height)
        return obstacles.contains { obstacle in
            let box = CGRect(x: obstacle.x, y: obstacle.offGround,
                             width: obstacle.width, height: obstacle.height)
            return runner.insetBy(dx: 2, dy: 2).intersects(box)
        }
    }

    private func groundY(_ size: CGSize) -> Double { size.height - 26 }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let ground = groundY(size)

        drawSky(&context, size: size, ground: ground)
        drawGround(&context, size: size, ground: ground)
        drawRunner(&context, ground: ground)

        for obstacle in obstacles {
            if obstacle.offGround > 0 {
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
            context.fill(Path(roundedRect: CGRect(x: x, y: y, width: Double(3 + index % 3), height: 1.5),
                              cornerRadius: 0.75),
                         with: .color(Ego.textMute.opacity(0.45)))
        }
    }

    private func drawRunner(_ context: inout GraphicsContext, ground: Double) {
        let x: Double = 42
        let feet = ground - runnerY
        let scale = runnerSize.height / 22

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

        // Eye.
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

        // Little arm, so the profile isn't just a blob.
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
        // Arms, scaled so small cacti stay bare and tall ones sprout.
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

    private func drawBird(_ context: inout GraphicsContext, obstacle: Obstacle, ground: Double) {
        let y = ground - obstacle.height - obstacle.offGround
        let flap = sin(distance / 9) > 0
        var bird = Path()
        bird.addRoundedRect(in: CGRect(x: obstacle.x, y: y + 3,
                                       width: obstacle.width, height: obstacle.height - 3),
                            cornerSize: CGSize(width: 3, height: 3))
        // Wing swaps above/below the body, which is the whole animation.
        bird.addRoundedRect(in: CGRect(x: obstacle.x + 4, y: flap ? y - 4 : y + 8,
                                       width: obstacle.width - 6, height: 5),
                            cornerSize: CGSize(width: 2, height: 2))
        context.fill(bird, with: .color(Ego.accentSoft))
        context.fill(Path(ellipseIn: CGRect(x: obstacle.x + obstacle.width - 5,
                                            y: y + 5, width: 2, height: 2)),
                     with: .color(.black))
    }
}
