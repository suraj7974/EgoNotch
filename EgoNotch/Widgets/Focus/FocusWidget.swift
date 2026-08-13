import SwiftUI

/// Phase 4 — Pomodoro timer with presets, menu-bar countdown, and a
/// completion notification carrying the day streak.
final class FocusWidget: NotchWidget {
    let id = "focus"
    let displayName = "Focus Timer"
    let icon = "timer"
    let tileSize: WidgetTileSize = .wide
    let tab: NotchTab = .focus

    let timer = FocusTimer()

    /// Disabling the widget must stop the session, the tick task, and the
    /// menu-bar countdown — a disabled widget costs nothing.
    func deactivate() { timer.reset() }

    func makeExpandedView() -> AnyView {
        AnyView(FocusTileView(timer: timer))
    }

    func makeClosedAccessory(for edge: NotchEdge) -> AnyView? {
        guard edge == .leading else { return nil }
        return AnyView(FocusCountdownChip(timer: timer))
    }
}

/// Slim countdown beside the notch while a session runs.
private struct FocusCountdownChip: View {
    var timer: FocusTimer

    var body: some View {
        if timer.isRunning {
            Text(timer.display)
                .font(Ego.font(10, .semibold))
                .egoDigits()
                .foregroundStyle(Ego.win)
        }
    }
}

struct FocusTileView: View {
    var timer: FocusTimer

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(FocusTimer.Mode.allCases) { mode in
                    Button {
                        timer.select(mode)
                    } label: {
                        Text("\(mode.title) \(mode.minutes)")
                            .font(Ego.font(11, .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                timer.mode == mode ? Color.white.opacity(0.16) : Ego.surface2,
                                in: Capsule()
                            )
                            .foregroundStyle(timer.mode == mode ? Ego.text : Ego.textMute)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if timer.streakDays > 0 {
                    Chip(text: "🔥 \(timer.streakDays)d · \(timer.sessionsToday) today",
                         variant: .win)
                }
            }

            Text(timer.display)
                .font(.system(size: 44, weight: .bold))
                .egoDigits()
                .foregroundStyle(Ego.text)

            HStack(spacing: 8) {
                Button(timer.isRunning ? "Pause" : "Start") { timer.startPause() }
                    .buttonStyle(.egoPrimary)
                Button("Reset") { timer.reset() }
                    .buttonStyle(.egoSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
