import SwiftUI
import Observation

/// Whack-a-mole, which is the game a long thin strip is *actually* good at:
/// a row of holes across the full width, 30 seconds, click them before they
/// drop. Replaces Breakout, which needed vertical room the notch doesn't have.
@MainActor
@Observable
final class WhackGame: GameModel {
    private(set) var score = 0
    private(set) var isOver = false
    private(set) var hasStarted = false
    private(set) var timeLeft: Double = 30

    private var holes: [Hole] = []
    private var nextPop: Double = 0.5
    private var combo = 0

    private struct Hole {
        let center: CGPoint
        let radius: Double
        /// 0 = down the hole, 1 = fully up.
        var raise: Double = 0
        var rising = false
        var remaining: Double = 0
        var struck = false
        var flash: Double = 0
    }

    private let round: Double = 30

    func reset() {
        score = 0
        combo = 0
        isOver = false
        hasStarted = false
        timeLeft = round
        nextPop = 0.5
        for index in holes.indices {
            holes[index].raise = 0
            holes[index].rising = false
            holes[index].remaining = 0
            holes[index].struck = false
        }
    }

    func press(_ key: GameKey) {
        guard case .action = key else { return }
        if !hasStarted || isOver {
            reset()
            hasStarted = true
        }
    }

    func tap(at point: CGPoint, size: CGSize) {
        guard hasStarted, !isOver else {
            press(.action)
            return
        }
        for index in holes.indices where holes[index].raise > 0.35 && !holes[index].struck {
            let hole = holes[index]
            let target = CGPoint(x: hole.center.x, y: hole.center.y - hole.radius * hole.raise)
            if hypot(point.x - target.x, point.y - target.y) < hole.radius * 1.05 {
                holes[index].struck = true
                holes[index].rising = false
                holes[index].flash = 0.25
                combo += 1
                score += 1 + combo / 5          // a streak is worth more
                return
            }
        }
        combo = 0                                // missed swing breaks the streak
    }

    func step(dt: Double, size: CGSize) {
        layoutIfNeeded(size: size)
        guard hasStarted, !isOver else { return }

        timeLeft -= dt
        if timeLeft <= 0 {
            timeLeft = 0
            isOver = true
            return
        }

        // They come faster as the round runs down.
        nextPop -= dt
        if nextPop <= 0 {
            pop()
            let progress = 1 - timeLeft / round
            nextPop = Double.random(in: 0.28...0.75) * (1 - progress * 0.45)
        }

        for index in holes.indices {
            holes[index].flash = max(0, holes[index].flash - dt)
            if holes[index].rising {
                holes[index].raise = min(1, holes[index].raise + dt * 7)
                holes[index].remaining -= dt
                if holes[index].remaining <= 0 {
                    holes[index].rising = false
                    combo = 0                    // one got away
                }
            } else if holes[index].raise > 0 {
                holes[index].raise = max(0, holes[index].raise - dt * 6)
                if holes[index].raise == 0 { holes[index].struck = false }
            }
        }
    }

    private func pop() {
        let idle = holes.indices.filter { holes[$0].raise == 0 && !holes[$0].rising }
        guard let index = idle.randomElement() else { return }
        holes[index].rising = true
        holes[index].struck = false
        holes[index].remaining = Double.random(in: 0.55...1.0)
    }

    private func layoutIfNeeded(size: CGSize) {
        let rows = size.height > 110 ? 2 : 1
        let radius = min(26.0, (size.height / Double(rows)) * 0.32)
        let columns = max(5, Int((size.width - 20) / (radius * 2.9)))
        guard holes.count != columns * rows else { return }

        let spacingX = (size.width - 24) / Double(columns)
        let spacingY = size.height / Double(rows + 1)
        holes = (0..<rows).flatMap { row in
            (0..<columns).map { column in
                Hole(center: CGPoint(x: 12 + spacingX * (Double(column) + 0.5),
                                     y: spacingY * Double(row + 1)),
                     radius: radius)
            }
        }
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        for hole in holes {
            // The hole: a flat ellipse, so the mole reads as coming out of it.
            let mouth = CGRect(x: hole.center.x - hole.radius,
                               y: hole.center.y - hole.radius * 0.34,
                               width: hole.radius * 2, height: hole.radius * 0.68)
            context.fill(Path(ellipseIn: mouth), with: .color(Color.white.opacity(0.07)))
            context.stroke(Path(ellipseIn: mouth), with: .color(Ego.border), lineWidth: 1)

            guard hole.raise > 0.01 else { continue }
            let lift = hole.radius * hole.raise
            let body = CGRect(x: hole.center.x - hole.radius * 0.62,
                              y: hole.center.y - lift - hole.radius * 0.15,
                              width: hole.radius * 1.24, height: hole.radius * 1.15)

            var clipped = context
            clipped.clip(to: Path(CGRect(x: mouth.minX - 4, y: 0,
                                         width: mouth.width + 8, height: mouth.midY)))
            let tint = hole.struck ? Ego.win : (hole.remaining < 0.25 ? Ego.loss : Ego.text)
            clipped.fill(Path(roundedRect: body, cornerRadius: hole.radius * 0.55),
                         with: .color(tint))
            // Eyes.
            let eyeY = body.minY + body.height * 0.34
            for dx in [-0.22, 0.22] {
                clipped.fill(Path(ellipseIn: CGRect(x: body.midX + body.width * dx - 2,
                                                    y: eyeY, width: 3.4, height: 3.4)),
                             with: .color(.black))
            }
            if hole.flash > 0 {
                clipped.stroke(Path(roundedRect: body.insetBy(dx: -3, dy: -3),
                                    cornerRadius: hole.radius * 0.6),
                               with: .color(Ego.win.opacity(hole.flash * 4)), lineWidth: 1.5)
            }
        }

        // Clock and streak.
        context.text(String(format: "%.0fs", timeLeft),
                     at: CGPoint(x: 26, y: 12), size: 11,
                     color: timeLeft < 6 ? Ego.loss : Ego.textMute)
        if combo >= 3 {
            context.text("×\(combo)", at: CGPoint(x: size.width - 26, y: 12),
                         size: 11, color: Ego.win)
        }
    }
}
