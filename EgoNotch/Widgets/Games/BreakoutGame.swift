import SwiftUI
import Observation

/// Breakout, laid out for the strip: three long rows of bricks across the top,
/// paddle along the bottom, three lives. The paddle follows the mouse, which
/// is the only sane control at this width.
@MainActor
@Observable
final class BreakoutGame: GameModel {
    private(set) var score = 0
    private(set) var isOver = false
    private(set) var hasStarted = false
    private(set) var lives = 3

    private var bricks: [Brick] = []
    private var ball = CGPoint(x: 200, y: 90)
    private var velocity = CGVector(dx: 250, dy: -260)
    private var paddleX: Double = 200
    private var boardSize: CGSize = .zero

    private struct Brick {
        var rect: CGRect
        var alive = true
        var row: Int
    }

    private let paddle = CGSize(width: 76, height: 8)
    private let ballRadius: Double = 4.5

    func reset() {
        score = 0
        lives = 3
        isOver = false
        hasStarted = false
        bricks = []
        velocity = CGVector(dx: 250, dy: -260)
    }

    func press(_ key: GameKey) {
        switch key {
        case .action:
            if !hasStarted || isOver {
                reset()
                hasStarted = true
                layout(size: boardSize)
                serve()
            }
        case .left:  paddleX -= 26
        case .right: paddleX += 26
        default: break
        }
    }

    func pointerMoved(to x: Double, size: CGSize) {
        paddleX = x
    }

    func step(dt: Double, size: CGSize) {
        boardSize = size
        if bricks.isEmpty { layout(size: size) }
        guard hasStarted, !isOver else { return }

        paddleX = min(max(paddleX, paddle.width / 2), size.width - paddle.width / 2)

        ball.x += velocity.dx * dt
        ball.y += velocity.dy * dt

        if ball.x - ballRadius < 0 { ball.x = ballRadius; velocity.dx = abs(velocity.dx) }
        if ball.x + ballRadius > size.width {
            ball.x = size.width - ballRadius
            velocity.dx = -abs(velocity.dx)
        }
        if ball.y - ballRadius < 0 { ball.y = ballRadius; velocity.dy = abs(velocity.dy) }

        let paddleRect = CGRect(x: paddleX - paddle.width / 2, y: size.height - 16,
                                width: paddle.width, height: paddle.height)
        if velocity.dy > 0, ballRect.intersects(paddleRect) {
            velocity.dy = -abs(velocity.dy)
            let offset = (ball.x - paddleRect.midX) / (paddle.width / 2)
            velocity.dx = max(-360, min(360, velocity.dx + offset * 210))
        }

        for index in bricks.indices where bricks[index].alive {
            guard ballRect.intersects(bricks[index].rect) else { continue }
            bricks[index].alive = false
            score += 3 - bricks[index].row        // top rows are worth more
            // Bounce off whichever side was hit shallower.
            let brick = bricks[index].rect
            let overlapX = min(ballRect.maxX - brick.minX, brick.maxX - ballRect.minX)
            let overlapY = min(ballRect.maxY - brick.minY, brick.maxY - ballRect.minY)
            if overlapX < overlapY { velocity.dx = -velocity.dx } else { velocity.dy = -velocity.dy }
            break
        }

        if bricks.allSatisfy({ !$0.alive }) {     // cleared → next, faster wall
            layout(size: size)
            velocity.dx *= 1.1
            velocity.dy *= 1.1
            serve()
        }

        if ball.y - ballRadius > size.height {
            lives -= 1
            if lives <= 0 { isOver = true } else { serve() }
        }
    }

    private var ballRect: CGRect {
        CGRect(x: ball.x - ballRadius, y: ball.y - ballRadius,
               width: ballRadius * 2, height: ballRadius * 2)
    }

    private func layout(size: CGSize) {
        guard size.width > 0 else { return }
        let rows = 3
        let columns = max(8, Int(size.width / 62))
        let gap: Double = 4
        let brickWidth = (size.width - gap * Double(columns + 1)) / Double(columns)
        let brickHeight: Double = 11
        bricks = (0..<rows).flatMap { row in
            (0..<columns).map { column in
                Brick(rect: CGRect(x: gap + Double(column) * (brickWidth + gap),
                                   y: 10 + Double(row) * (brickHeight + gap),
                                   width: brickWidth, height: brickHeight),
                      row: row)
            }
        }
    }

    private func serve() {
        guard boardSize.width > 0 else { return }
        ball = CGPoint(x: paddleX, y: boardSize.height - 30)
        velocity = CGVector(dx: Bool.random() ? 240 : -240, dy: -270)
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        for brick in bricks where brick.alive {
            let shade = [Ego.text, Ego.accentSoft, Ego.textMute][brick.row % 3]
            context.fillRect(brick.rect, shade, radius: 3)
        }
        context.fillRect(CGRect(x: paddleX - paddle.width / 2, y: size.height - 16,
                                width: paddle.width, height: paddle.height),
                         Ego.text, radius: 4)
        context.fill(Path(ellipseIn: ballRect), with: .color(Ego.text))

        for life in 0..<max(lives, 0) {
            context.fill(Path(ellipseIn: CGRect(x: size.width - 14 - Double(life) * 11,
                                                y: size.height - 12, width: 5, height: 5)),
                         with: .color(Ego.textMute))
        }
    }
}
