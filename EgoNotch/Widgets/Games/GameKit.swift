import SwiftUI
import Observation

/// Shared plumbing for the Games tab.
///
/// The panel is a ~900×140 letterbox, so every game here is chosen to suit a
/// wide, short strip. Each one owns an `@Observable` model with a `step(dt:)`;
/// `GameSurface` runs the loop, draws with a `Canvas`, and — this is the part
/// that matters for a notch — the loop exists ONLY while the tab is on screen.

// MARK: - Model contract

@MainActor
protocol GameModel: AnyObject, Observable {
    var score: Int { get }
    var isOver: Bool { get }
    var hasStarted: Bool { get }
    /// Advance by `dt` seconds inside a board of `size`.
    func step(dt: Double, size: CGSize)
    /// Space / click, and the four arrows.
    func press(_ key: GameKey)
    /// Pointer position inside the board, for paddle games.
    func pointerMoved(to x: Double, size: CGSize)
    func draw(in context: inout GraphicsContext, size: CGSize)
    func reset()
}

extension GameModel {
    func pointerMoved(to x: Double, size: CGSize) {}
}

enum GameKey { case action, up, down, left, right }

// MARK: - High scores

/// Best score per game, kept in UserDefaults — small enough not to deserve a
/// store of its own.
enum GameScores {
    static func best(_ id: String) -> Int {
        UserDefaults.standard.integer(forKey: "game.best.\(id)")
    }

    static func record(_ score: Int, for id: String) {
        guard score > best(id) else { return }
        UserDefaults.standard.set(score, forKey: "game.best.\(id)")
    }
}

// MARK: - Surface

/// Canvas + fixed-step loop + keyboard focus, wrapped around any `GameModel`.
struct GameSurface<Model: GameModel>: View {
    let model: Model
    let gameID: String

    @State private var loop: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            // TimelineView is the redraw pump. A Canvas reads the model
            // inside its render closure, which Observation does NOT track, so
            // without a per-frame invalidation the board would simply freeze.
            TimelineView(.animation(minimumInterval: 1 / 60)) { _ in
                Canvas { context, size in
                    var ctx = context
                    model.draw(in: &ctx, size: size)
                }
            }
            .background(Color.black)
            .overlay(alignment: .center) { banner }
            .contentShape(Rectangle())
            .onTapGesture { model.press(.action) }
            .onContinuousHover { phase in
                if case .active(let point) = phase {
                    model.pointerMoved(to: point.x, size: geo.size)
                }
            }
            .onAppear { start(size: geo.size) }
            .onDisappear { stop() }
            .onChange(of: geo.size) { _, size in restart(size: size) }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focusedField, equals: true)
        .onKeyPress { keyPress in
            switch keyPress.key {
            case .space, .return:    model.press(.action)
            case .upArrow:           model.press(.up)
            case .downArrow:         model.press(.down)
            case .leftArrow:         model.press(.left)
            case .rightArrow:        model.press(.right)
            default:
                guard let scalar = keyPress.characters.first else { return .ignored }
                switch scalar {
                case "w", "W": model.press(.up)
                case "s", "S": model.press(.down)
                case "a", "A": model.press(.left)
                case "d", "D": model.press(.right)
                default: return .ignored
                }
            }
            return .handled
        }
    }

    @FocusState private var focusedField: Bool

    @ViewBuilder
    private var banner: some View {
        if !model.hasStarted || model.isOver {
            VStack(spacing: 3) {
                Text(model.isOver ? "Game over — \(model.score)" : "Press Space to play")
                    .font(Ego.font(12, .semibold))
                    .foregroundStyle(Ego.text)
                if model.isOver {
                    Text("Space to try again")
                        .font(Ego.font(10))
                        .foregroundStyle(Ego.textMute)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ego.border, lineWidth: 1))
            .allowsHitTesting(false)
        }
    }

    // MARK: - Loop

    /// Fixed 60 Hz step. Cancelled the moment the tab goes away, so a closed
    /// notch costs nothing — the same rule the rest of the app follows.
    private func start(size: CGSize) {
        focusedField = true
        claimKeyboard()
        guard loop == nil else { return }
        loop = Task { @MainActor in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let now = ContinuousClock.now
                let dt = min(Double(last.duration(to: now).components.attoseconds) / 1e18
                             + Double(last.duration(to: now).components.seconds), 0.05)
                last = now
                model.step(dt: dt, size: size)
                if model.isOver { GameScores.record(model.score, for: gameID) }
            }
        }
    }

    private func stop() {
        loop?.cancel()
        loop = nil
    }

    private func restart(size: CGSize) {
        stop()
        start(size: size)
    }

    /// Games are keyboard-driven, so the panel has to be key — same trick the
    /// terminal uses, and equally harmless because opening the tab is a
    /// deliberate act.
    private func claimKeyboard() {
        DispatchQueue.main.async {
            guard let panel = NSApp.windows.first(where: { $0 is NotchPanel }),
                  !panel.isKeyWindow else { return }
            panel.makeKey()
        }
    }
}

// MARK: - Drawing helpers

extension GraphicsContext {
    mutating func fillRect(_ rect: CGRect, _ color: Color, radius: CGFloat = 0) {
        fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color))
    }

    mutating func text(_ string: String, at point: CGPoint, size: CGFloat = 11,
                       color: Color = Ego.textMute) {
        draw(Text(string).font(Ego.font(size, .medium)).foregroundStyle(color), at: point)
    }
}
