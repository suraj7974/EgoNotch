import SwiftUI
import Observation

/// The Games tab: a row of game pills at the top, the board underneath.
///
/// Every game is picked for the panel's shape — a ~900×140 letterbox, which
/// suits side-scrollers and paddle games and would ruin anything square.
final class GamesWidget: NotchWidget {
    let id = "games"
    let displayName = "Games"
    let icon = "gamecontroller.fill"
    let tileSize: WidgetTileSize = .wide
    let tab: NotchTab = .games
    /// The board owns the tile; the picker is its own header.
    let wantsTileChrome = false

    let state = GamesState()

    func makeExpandedView() -> AnyView? {
        AnyView(GamesTileView(widget: self))
    }
}

/// Which game is showing, and the four models, kept alive across tab switches
/// so a run survives a glance at the terminal.
@MainActor
@Observable
final class GamesState {
    var selected: GameChoice = .dino

    @ObservationIgnored let dino = DinoGame()
    @ObservationIgnored let snake = SnakeGame()
    @ObservationIgnored let pong = PongGame()
    @ObservationIgnored let shooter = ShooterGame()

    func score(for choice: GameChoice) -> Int {
        switch choice {
        case .dino: dino.score
        case .snake: snake.score
        case .pong: pong.score
        case .shooter: shooter.score
        }
    }
}

enum GameChoice: String, CaseIterable, Identifiable {
    case dino, snake, pong, shooter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dino: "Runner"
        case .snake: "Snake"
        case .pong: "Pong"
        case .shooter: "Shooter"
        }
    }

    var icon: String {
        switch self {
        case .dino: "hare.fill"
        case .snake: "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .pong: "circle.circle"
        case .shooter: "scope"
        }
    }

    /// How you play it, shown beside the score.
    var controls: String {
        switch self {
        case .dino: "Space to jump · birds fly high"
        case .snake: "Arrows to steer"
        case .pong: "↑ ↓ to move"
        case .shooter: "↑ ↓ lane · Space to fire"
        }
    }
}

struct GamesTileView: View {
    let widget: GamesWidget

    var body: some View {
        let state = widget.state
        VStack(spacing: 6) {
            header(state)
            board(state)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Ego.border, lineWidth: 1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(_ state: GamesState) -> some View {
        HStack(spacing: 6) {
            ForEach(GameChoice.allCases) { choice in
                GamePill(choice: choice, selected: state.selected == choice) {
                    state.selected = choice
                }
            }
            Spacer(minLength: 8)
            Text(state.selected.controls)
                .font(Ego.font(9.5))
                .foregroundStyle(Ego.textMute.opacity(0.8))
            Text("\(state.score(for: state.selected))")
                .font(Ego.font(12, .semibold))
                .egoDigits()
                .foregroundStyle(Ego.text)
            Text("best \(GameScores.best(state.selected.rawValue))")
                .font(Ego.font(9.5))
                .egoDigits()
                .foregroundStyle(Ego.textMute)
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func board(_ state: GamesState) -> some View {
        switch state.selected {
        case .dino:     GameSurface(model: state.dino, gameID: "dino")
        case .snake:    GameSurface(model: state.snake, gameID: "snake")
        case .pong:     GameSurface(model: state.pong, gameID: "pong")
        case .shooter:  GameSurface(model: state.shooter, gameID: "shooter")
        }
    }
}

/// Same shape as the panel's own tab circles, one level down.
private struct GamePill: View {
    let choice: GameChoice
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: choice.icon)
                    .font(.system(size: 9.5, weight: .semibold))
                Text(choice.title)
                    .font(Ego.font(10.5, selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? Ego.text : Ego.textMute)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.white.opacity(selected ? 0.14 : (hovering ? 0.06 : 0)),
                        in: Capsule())
            .overlay(Capsule().strokeBorder(Ego.border, lineWidth: selected ? 0 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
