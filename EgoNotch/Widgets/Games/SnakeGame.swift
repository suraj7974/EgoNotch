import SwiftUI
import Observation

/// Snake on a wide grid — the strip gives roughly 60×9 cells, which turns the
/// usual square board into a long corridor and makes it its own game.
@MainActor
@Observable
final class SnakeGame: GameModel {
    private(set) var score = 0
    private(set) var isOver = false
    private(set) var hasStarted = false

    private var body: [Cell] = []
    private var direction = Cell(x: 1, y: 0)
    private var queued: Cell?
    private var food = Cell(x: 12, y: 4)
    private var sinceMove: Double = 0
    private var columns = 40
    private var rows = 8

    private struct Cell: Equatable {
        var x: Int
        var y: Int
    }

    private let cellSize: Double = 13
    /// Moves per second — climbs a little as the snake grows.
    private var tickInterval: Double { max(0.055, 0.13 - Double(body.count) * 0.0015) }

    func reset() {
        score = 0
        isOver = false
        hasStarted = false
        body = [Cell(x: 6, y: rows / 2), Cell(x: 5, y: rows / 2), Cell(x: 4, y: rows / 2)]
        direction = Cell(x: 1, y: 0)
        queued = nil
        sinceMove = 0
        placeFood()
    }

    func press(_ key: GameKey) {
        switch key {
        case .action:
            if !hasStarted || isOver {
                reset()
                hasStarted = true
            }
        // A 180° turn would eat your own neck — ignore it.
        case .up    where direction.y == 0: queued = Cell(x: 0, y: -1)
        case .down  where direction.y == 0: queued = Cell(x: 0, y: 1)
        case .left  where direction.x == 0: queued = Cell(x: -1, y: 0)
        case .right where direction.x == 0: queued = Cell(x: 1, y: 0)
        default: break
        }
    }

    func step(dt: Double, size: CGSize) {
        columns = max(12, Int(size.width / cellSize))
        rows = max(5, Int(size.height / cellSize))
        if body.isEmpty { reset() }
        guard hasStarted, !isOver else { return }

        sinceMove += dt
        guard sinceMove >= tickInterval else { return }
        sinceMove = 0

        if let queued { direction = queued; self.queued = nil }
        var head = body[0]
        head.x += direction.x
        head.y += direction.y

        // Walls are fatal — wrapping would make it far too easy on a strip
        // this wide.
        guard head.x >= 0, head.x < columns, head.y >= 0, head.y < rows,
              !body.dropLast().contains(head) else {
            isOver = true
            return
        }

        body.insert(head, at: 0)
        if head == food {
            score += 1
            placeFood()
        } else {
            body.removeLast()
        }
    }

    private func placeFood() {
        var candidate = food
        var attempts = 0
        repeat {
            candidate = Cell(x: Int.random(in: 0..<columns), y: Int.random(in: 0..<rows))
            attempts += 1
        } while body.contains(candidate) && attempts < 200
        food = candidate
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let originX = (size.width - Double(columns) * cellSize) / 2
        let originY = (size.height - Double(rows) * cellSize) / 2
        func rect(_ cell: Cell, inset: Double) -> CGRect {
            CGRect(x: originX + Double(cell.x) * cellSize + inset,
                   y: originY + Double(cell.y) * cellSize + inset,
                   width: cellSize - inset * 2, height: cellSize - inset * 2)
        }

        context.fillRect(rect(food, inset: 3), Ego.win, radius: 3)
        for (index, cell) in body.enumerated() {
            context.fillRect(rect(cell, inset: 1.5),
                             index == 0 ? Ego.text : Ego.text.opacity(0.55),
                             radius: 3)
        }
    }
}
