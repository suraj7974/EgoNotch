import SwiftUI
import Observation

/// Pong against the machine. A long thin court is the shape Pong was designed
/// for, so this is the best fit of the four. Move with the mouse or ↑/↓.
@MainActor
@Observable
final class PongGame: GameModel {
    private(set) var score = 0          // your points
    private(set) var opponent = 0
    private(set) var isOver = false
    private(set) var hasStarted = false

    private var ball = CGPoint(x: 200, y: 70)
    private var velocity = CGVector(dx: 320, dy: 150)
    private var playerY: Double = 60
    private var cpuY: Double = 60
    private var playerInput: Double = 0

    private let paddle = CGSize(width: 7, height: 44)
    private let ballRadius: Double = 5
    private let target = 7              // first to seven

    func reset() {
        score = 0
        opponent = 0
        isOver = false
        hasStarted = false
        velocity = CGVector(dx: 320, dy: 150)
    }

    func press(_ key: GameKey) {
        switch key {
        case .action:
            if !hasStarted || isOver {
                reset()
                hasStarted = true
            }
        case .up:   playerInput = -1
        case .down: playerInput = 1
        default:    break
        }
    }

    func pointerMoved(to x: Double, size: CGSize) {}

    /// Vertical pointer tracking reads better than x here, so the surface's
    /// x-only hook is ignored and the paddle follows the keys; ↑/↓ nudge it.
    func step(dt: Double, size: CGSize) {
        guard hasStarted, !isOver else { return }

        playerY = clamp(playerY + playerInput * 420 * dt, size: size)
        playerInput *= 0.82                      // key taps decay into a glide

        // The CPU tracks the ball with a deliberate lag, which is the whole
        // difficulty knob: perfect tracking would be unbeatable.
        let cpuCenter = cpuY + paddle.height / 2
        let chase = (ball.y - cpuCenter)
        cpuY = clamp(cpuY + max(-1, min(1, chase / 40)) * 250 * dt, size: size)

        ball.x += velocity.dx * dt
        ball.y += velocity.dy * dt

        if ball.y - ballRadius < 0 {
            ball.y = ballRadius
            velocity.dy = abs(velocity.dy)
        }
        if ball.y + ballRadius > size.height {
            ball.y = size.height - ballRadius
            velocity.dy = -abs(velocity.dy)
        }

        bounce(against: CGRect(x: 18, y: playerY, width: paddle.width, height: paddle.height),
               movingLeft: true)
        bounce(against: CGRect(x: size.width - 18 - paddle.width, y: cpuY,
                               width: paddle.width, height: paddle.height),
               movingLeft: false)

        if ball.x < -20 { opponent += 1; serve(size: size, toPlayer: false) }
        if ball.x > size.width + 20 { score += 1; serve(size: size, toPlayer: true) }
        if score >= target || opponent >= target { isOver = true }
    }

    private func bounce(against rect: CGRect, movingLeft: Bool) {
        let hit = CGRect(x: ball.x - ballRadius, y: ball.y - ballRadius,
                         width: ballRadius * 2, height: ballRadius * 2).intersects(rect)
        guard hit, movingLeft ? velocity.dx < 0 : velocity.dx > 0 else { return }
        velocity.dx = movingLeft ? abs(velocity.dx) : -abs(velocity.dx)
        // Where it lands on the paddle sets the angle — the one bit of skill.
        let offset = (ball.y - rect.midY) / (paddle.height / 2)
        velocity.dy = max(-380, min(380, velocity.dy + offset * 180))
        velocity.dx *= 1.04                       // every rally gets faster
    }

    private func serve(size: CGSize, toPlayer: Bool) {
        ball = CGPoint(x: size.width / 2, y: size.height / 2)
        velocity = CGVector(dx: toPlayer ? -320 : 320,
                            dy: Double.random(in: -160...160))
    }

    private func clamp(_ y: Double, size: CGSize) -> Double {
        min(max(y, 0), size.height - paddle.height)
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        // Centre net.
        var net = Path()
        net.move(to: CGPoint(x: size.width / 2, y: 0))
        net.addLine(to: CGPoint(x: size.width / 2, y: size.height))
        context.stroke(net, with: .color(Ego.textMute.opacity(0.35)),
                       style: StrokeStyle(lineWidth: 1, dash: [5, 6]))

        context.text("\(score)", at: CGPoint(x: size.width / 2 - 26, y: 14), size: 13, color: Ego.text)
        context.text("\(opponent)", at: CGPoint(x: size.width / 2 + 26, y: 14), size: 13, color: Ego.textMute)

        context.fillRect(CGRect(x: 18, y: playerY, width: paddle.width, height: paddle.height),
                         Ego.text, radius: 3)
        context.fillRect(CGRect(x: size.width - 18 - paddle.width, y: cpuY,
                                width: paddle.width, height: paddle.height),
                         Ego.textMute, radius: 3)
        context.fill(Path(ellipseIn: CGRect(x: ball.x - ballRadius, y: ball.y - ballRadius,
                                            width: ballRadius * 2, height: ballRadius * 2)),
                     with: .color(Ego.text))
    }
}
