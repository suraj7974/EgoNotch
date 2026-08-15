import SwiftUI
import Observation

/// Side-scrolling shooter — the one arcade shape that is purely horizontal.
/// Your ship holds the left edge, waves fly in from the right down three
/// lanes, and the whole game is read-the-lane-and-fire. Nothing depends on
/// vertical room beyond three rows, which is all the notch has to give.
@MainActor
@Observable
final class ShooterGame: GameModel {
    private(set) var score = 0
    private(set) var isOver = false
    private(set) var hasStarted = false
    private(set) var lives = 3

    private var lane = 1
    private var enemies: [Enemy] = []
    private var bullets: [Bullet] = []
    private var sinceSpawn: Double = 0
    private var cooldown: Double = 0
    private var elapsed: Double = 0
    private var hitFlash: Double = 0

    private struct Enemy {
        var x: Double
        var lane: Int
        var speed: Double
        /// Bigger ones take two hits and are worth more.
        var armour: Int
        var wobble: Double
    }

    private struct Bullet {
        var x: Double
        var lane: Int
    }

    private let laneCount = 3
    private let shipX: Double = 34
    private let bulletSpeed: Double = 620
    private let fireInterval: Double = 0.17

    func reset() {
        score = 0
        lives = 3
        lane = 1
        enemies = []
        bullets = []
        sinceSpawn = 0
        cooldown = 0
        elapsed = 0
        hitFlash = 0
        isOver = false
        hasStarted = false
    }

    func press(_ key: GameKey) {
        switch key {
        case .action:
            if !hasStarted || isOver {
                reset()
                hasStarted = true
                return
            }
            guard cooldown <= 0 else { return }
            cooldown = fireInterval
            bullets.append(Bullet(x: shipX + 16, lane: lane))
        case .up:    lane = max(0, lane - 1)
        case .down:  lane = min(laneCount - 1, lane + 1)
        default:     break
        }
    }

    func step(dt: Double, size: CGSize) {
        guard hasStarted, !isOver else { return }
        elapsed += dt
        cooldown -= dt
        hitFlash = max(0, hitFlash - dt)

        // Waves get faster and thicker the longer you survive.
        let intensity = min(1, elapsed / 75)
        sinceSpawn -= dt
        if sinceSpawn <= 0 {
            spawn(size: size, intensity: intensity)
            sinceSpawn = Double.random(in: 0.45...1.0) * (1 - intensity * 0.55)
        }

        for index in bullets.indices { bullets[index].x += bulletSpeed * dt }
        bullets.removeAll { $0.x > size.width + 10 }

        for index in enemies.indices {
            enemies[index].x -= enemies[index].speed * dt
            enemies[index].wobble += dt
        }

        resolveHits()

        // Anything that reaches your edge costs a life.
        let breached = enemies.filter { $0.x < shipX - 6 }
        if !breached.isEmpty {
            enemies.removeAll { $0.x < shipX - 6 }
            lives -= breached.count
            hitFlash = 0.35
            if lives <= 0 {
                lives = 0
                isOver = true
            }
        }
    }

    private func spawn(size: CGSize, intensity: Double) {
        let armoured = Double.random(in: 0...1) < intensity * 0.45
        enemies.append(Enemy(x: size.width + 20,
                             lane: Int.random(in: 0..<laneCount),
                             speed: Double.random(in: 110...170) + intensity * 190,
                             armour: armoured ? 2 : 1,
                             wobble: Double.random(in: 0...3)))
    }

    private func resolveHits() {
        var survivingBullets: [Bullet] = []
        for bullet in bullets {
            if let index = enemies.firstIndex(where: {
                $0.lane == bullet.lane && abs($0.x - bullet.x) < 14
            }) {
                enemies[index].armour -= 1
                if enemies[index].armour <= 0 {
                    score += enemies[index].speed > 240 ? 3 : 1
                    enemies.remove(at: index)
                }
                continue                      // bullet is spent
            }
            survivingBullets.append(bullet)
        }
        bullets = survivingBullets
    }

    private func laneY(_ index: Int, size: CGSize) -> Double {
        let usable = size.height - 16
        return 8 + usable * (Double(index) + 0.5) / Double(laneCount)
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        // Lane rails — faint, just enough to read which row you're in.
        for index in 0..<laneCount {
            var rail = Path()
            let y = laneY(index, size: size)
            rail.move(to: CGPoint(x: shipX + 20, y: y))
            rail.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(rail, with: .color(Ego.textMute.opacity(index == lane ? 0.22 : 0.08)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 9],
                                              dashPhase: -elapsed * 90))
        }

        drawShip(&context, y: laneY(lane, size: size))

        for bullet in bullets {
            let y = laneY(bullet.lane, size: size)
            context.fillRect(CGRect(x: bullet.x, y: y - 1.2, width: 9, height: 2.4),
                             Ego.accentSoft, radius: 1.2)
        }

        for enemy in enemies {
            drawEnemy(&context, enemy: enemy, y: laneY(enemy.lane, size: size))
        }

        for life in 0..<lives {
            context.fill(Path(ellipseIn: CGRect(x: 10 + Double(life) * 9, y: size.height - 12,
                                                width: 5, height: 5)),
                         with: .color(hitFlash > 0 ? Ego.loss : Ego.textMute))
        }
    }

    /// An arrowhead with a thruster — reads as "mine, pointing right".
    private func drawShip(_ context: inout GraphicsContext, y: Double) {
        var ship = Path()
        ship.move(to: CGPoint(x: shipX + 18, y: y))
        ship.addLine(to: CGPoint(x: shipX - 8, y: y - 9))
        ship.addLine(to: CGPoint(x: shipX - 3, y: y))
        ship.addLine(to: CGPoint(x: shipX - 8, y: y + 9))
        ship.closeSubpath()
        context.fill(ship, with: .color(hitFlash > 0 ? Ego.loss : Ego.text))

        let flame = 5 + sin(elapsed * 26) * 2.5
        context.fill(Path(roundedRect: CGRect(x: shipX - 8 - flame, y: y - 1.6,
                                              width: flame, height: 3.2),
                          cornerRadius: 1.6),
                     with: .color(Ego.accentSoft.opacity(0.85)))
    }

    /// Enemies point left, at you. Armoured ones get a second ring.
    private func drawEnemy(_ context: inout GraphicsContext, enemy: Enemy, y: Double) {
        let bob = sin(enemy.wobble * 4) * 1.6
        let cy = y + bob
        var hull = Path()
        hull.move(to: CGPoint(x: enemy.x - 11, y: cy))
        hull.addLine(to: CGPoint(x: enemy.x + 6, y: cy - 8))
        hull.addLine(to: CGPoint(x: enemy.x + 2, y: cy))
        hull.addLine(to: CGPoint(x: enemy.x + 6, y: cy + 8))
        hull.closeSubpath()
        context.fill(hull, with: .color(enemy.armour > 1 ? Ego.loss : Ego.win))

        if enemy.armour > 1 {
            context.stroke(Path(ellipseIn: CGRect(x: enemy.x - 8, y: cy - 6,
                                                  width: 13, height: 12)),
                           with: .color(Ego.loss.opacity(0.55)), lineWidth: 1)
        }
        context.fill(Path(ellipseIn: CGRect(x: enemy.x - 6, y: cy - 1.4,
                                            width: 2.8, height: 2.8)),
                     with: .color(.black))
    }
}
