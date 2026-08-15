import SwiftUI
import Observation

/// Flappy: tap to flap, thread the gaps. A long horizontal corridor is exactly
/// the shape this needs — you see four pipes ahead, which is what makes it
/// readable rather than luck.
@MainActor
@Observable
final class FlappyGame: GameModel {
    private(set) var score = 0
    private(set) var isOver = false
    private(set) var hasStarted = false

    private var birdY: Double = 60
    private var velocity: Double = 0
    private var pipes: [Pipe] = []
    private var sinceSpawn: Double = 0
    private var speed: Double = 165

    private struct Pipe {
        var x: Double
        /// Top of the gap, in points from the ceiling.
        var gapTop: Double
        var gapHeight: Double
        var scored = false
    }

    private let gravity: Double = 1250
    private let flapVelocity: Double = -330
    private let birdX: Double = 68
    private let birdRadius: Double = 7
    private let pipeWidth: Double = 22

    func reset() {
        score = 0
        isOver = false
        hasStarted = false
        birdY = 0
        velocity = 0
        pipes = []
        sinceSpawn = 0
        speed = 165
    }

    func press(_ key: GameKey) {
        switch key {
        case .action, .up:
            if isOver || !hasStarted {
                reset()
                hasStarted = true
                return
            }
            velocity = flapVelocity
        default:
            break
        }
    }

    func step(dt: Double, size: CGSize) {
        if birdY == 0 { birdY = size.height / 2 }
        guard hasStarted, !isOver else { return }

        // Everything scales off the board height, so the game plays the same
        // whether the panel is short or the user made it taller in Settings.
        let gap = max(46, size.height * 0.42 - Double(score) * 0.35)
        speed = min(165 + Double(score) * 4, 320)

        velocity += gravity * dt
        birdY += velocity * dt

        sinceSpawn += dt
        let interval = (size.width / 2.6) / speed        // ~2.6 pipes on screen
        if sinceSpawn >= interval {
            sinceSpawn = 0
            let margin = 14.0
            let top = Double.random(in: margin...(size.height - gap - margin))
            pipes.append(Pipe(x: size.width + pipeWidth, gapTop: top, gapHeight: gap))
        }

        for index in pipes.indices {
            pipes[index].x -= speed * dt
            if !pipes[index].scored, pipes[index].x + pipeWidth < birdX {
                pipes[index].scored = true
                score += 1
            }
        }
        pipes.removeAll { $0.x + pipeWidth < -10 }

        // Ceiling and floor are fatal, same as the pipes.
        if birdY - birdRadius < 0 || birdY + birdRadius > size.height {
            isOver = true
            return
        }
        let bird = CGRect(x: birdX - birdRadius, y: birdY - birdRadius,
                          width: birdRadius * 2, height: birdRadius * 2).insetBy(dx: 1, dy: 1)
        for pipe in pipes {
            let top = CGRect(x: pipe.x, y: 0, width: pipeWidth, height: pipe.gapTop)
            let bottom = CGRect(x: pipe.x, y: pipe.gapTop + pipe.gapHeight,
                                width: pipeWidth, height: size.height - pipe.gapTop - pipe.gapHeight)
            if bird.intersects(top) || bird.intersects(bottom) {
                isOver = true
                return
            }
        }
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        for pipe in pipes {
            let top = CGRect(x: pipe.x, y: 0, width: pipeWidth, height: pipe.gapTop)
            let bottom = CGRect(x: pipe.x, y: pipe.gapTop + pipe.gapHeight,
                                width: pipeWidth, height: size.height - pipe.gapTop - pipe.gapHeight)
            context.fillRect(top, Ego.win, radius: 3)
            context.fillRect(bottom, Ego.win, radius: 3)
            // Lips, so a pipe reads as a pipe and the gap edge is obvious.
            context.fillRect(CGRect(x: pipe.x - 3, y: max(0, pipe.gapTop - 6),
                                    width: pipeWidth + 6, height: 6),
                             Ego.win.opacity(0.85), radius: 2)
            context.fillRect(CGRect(x: pipe.x - 3, y: pipe.gapTop + pipe.gapHeight,
                                    width: pipeWidth + 6, height: 6),
                             Ego.win.opacity(0.85), radius: 2)
        }

        // Bird: body, wing that beats with the flap, beak and eye.
        let tilt = max(-0.5, min(0.9, velocity / 520))
        let body = CGRect(x: birdX - birdRadius, y: birdY - birdRadius,
                          width: birdRadius * 2, height: birdRadius * 2)
        context.fill(Path(ellipseIn: body), with: .color(Ego.text))
        let wingUp = velocity < -40
        context.fill(Path(roundedRect: CGRect(x: birdX - birdRadius - 1,
                                              y: birdY + (wingUp ? -6 : 1),
                                              width: 9, height: 4),
                          cornerRadius: 2),
                     with: .color(Ego.textMute))
        context.fill(Path(roundedRect: CGRect(x: birdX + birdRadius - 2,
                                              y: birdY - 1 + tilt * 3, width: 6, height: 3),
                          cornerRadius: 1),
                     with: .color(Ego.accentSoft))
        context.fill(Path(ellipseIn: CGRect(x: birdX + 1, y: birdY - 4, width: 2.6, height: 2.6)),
                     with: .color(.black))
    }
}
