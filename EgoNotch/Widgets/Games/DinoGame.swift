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

        // Ground line, dashed like the original.
        var line = Path()
        line.move(to: CGPoint(x: 0, y: ground))
        line.addLine(to: CGPoint(x: size.width, y: ground))
        context.stroke(line, with: .color(Ego.textMute.opacity(0.6)),
                       style: StrokeStyle(lineWidth: 1, dash: [6, 5],
                                          dashPhase: -distance.truncatingRemainder(dividingBy: 11)))

        // Runner.
        context.fillRect(CGRect(x: 42, y: ground - runnerSize.height - runnerY,
                                width: runnerSize.width, height: runnerSize.height),
                         Ego.text, radius: 4)

        for obstacle in obstacles {
            context.fillRect(CGRect(x: obstacle.x,
                                    y: ground - obstacle.height - obstacle.offGround,
                                    width: obstacle.width, height: obstacle.height),
                             obstacle.offGround > 0 ? Ego.accentSoft : Ego.text,
                             radius: 3)
        }
    }
}
