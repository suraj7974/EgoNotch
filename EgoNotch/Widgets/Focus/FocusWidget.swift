import SwiftUI

/// Focus tab: Pomodoro + custom ringing Timer + Stopwatch, one segmented tile.
final class FocusWidget: NotchWidget {
    let id = "focus"
    let displayName = "Focus"
    let icon = "timer"
    let tileSize: WidgetTileSize = .wide
    let tab: NotchTab = .focus

    let timer = FocusTimer()
    let custom = TimerEngine()
    let stopwatch = Stopwatch()

    /// Disabling the widget must stop every engine and the menu-bar text.
    func deactivate() {
        timer.reset()
        custom.reset()
        stopwatch.reset()
    }

    func makeExpandedView() -> AnyView? {
        AnyView(FocusTileView(widget: self))
    }

    func makeClosedAccessory(for edge: NotchEdge) -> AnyView? {
        guard edge == .leading else { return nil }
        return AnyView(FocusCountdownChip(widget: self))
    }
}

/// Slim countdown beside the notch while any countdown runs.
private struct FocusCountdownChip: View {
    var widget: FocusWidget

    var body: some View {
        if widget.timer.isRunning {
            chip(widget.timer.display)
        } else if widget.custom.isRunning {
            chip(TimerEngine.format(widget.custom.remaining))
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(Ego.font(10, .semibold))
            .egoDigits()
            .foregroundStyle(Ego.win)
    }
}

struct FocusTileView: View {
    var widget: FocusWidget

    private enum Mode: String, CaseIterable, Identifiable {
        case focus = "Focus"
        case timer = "Timer"
        case stopwatch = "Stopwatch"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .focus

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Mode.allCases) { m in
                    Button {
                        withAnimation(Ego.Motion.spring()) { mode = m }
                    } label: {
                        Text(m.rawValue)
                            .font(Ego.font(11, .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(mode == m ? Color.white.opacity(0.14) : .clear,
                                        in: Capsule())
                            .foregroundStyle(mode == m ? Ego.text : Ego.textMute)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if mode == .focus, widget.timer.streakDays > 0 {
                    Chip(text: "🔥 \(widget.timer.streakDays)d · \(widget.timer.sessionsToday) today",
                         variant: .win)
                }
            }

            switch mode {
            case .focus: pomodoro
            case .timer: customTimer
            case .stopwatch: stopwatchView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Pomodoro

    private var pomodoro: some View {
        let timer = widget.timer
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(FocusTimer.Mode.allCases) { m in
                    Button {
                        timer.select(m)
                    } label: {
                        Text("\(m.title) \(m.minutes)")
                            .font(Ego.font(10, .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(timer.mode == m ? Color.white.opacity(0.14) : Ego.surface2,
                                        in: Capsule())
                            .foregroundStyle(timer.mode == m ? Ego.text : Ego.textMute)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(timer.display)
                .font(.system(size: 34, weight: .bold))
                .egoDigits()
                .foregroundStyle(Ego.text)
            HStack(spacing: 8) {
                Button(timer.isRunning ? "Pause" : "Start") { timer.startPause() }
                    .buttonStyle(.egoPrimary)
                Button("Reset") { timer.reset() }
                    .buttonStyle(.egoSecondary)
            }
        }
    }

    // MARK: - Custom timer (rings on completion)

    private var customTimer: some View {
        let custom = widget.custom
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach([("+1m", 60.0), ("+5m", 300.0), ("+10m", 600.0)], id: \.0) { label, secs in
                    Button {
                        custom.add(secs)
                    } label: {
                        Text(label)
                            .font(Ego.font(10, .medium))
                            .egoDigits()
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Ego.surface2, in: Capsule())
                            .foregroundStyle(custom.isRunning ? Ego.textMute.opacity(0.4) : Ego.text)
                    }
                    .buttonStyle(.plain)
                    .disabled(custom.isRunning)
                }
                Button("Clear") { custom.clear() }
                    .buttonStyle(.plain)
                    .font(Ego.font(10))
                    .foregroundStyle(custom.isRunning ? Ego.textMute.opacity(0.4) : Ego.textMute)
                    .disabled(custom.isRunning)
            }
            Text(TimerEngine.format(custom.remaining))
                .font(.system(size: 34, weight: .bold))
                .egoDigits()
                .foregroundStyle(Ego.text)
            HStack(spacing: 8) {
                Button(custom.isRunning ? "Pause" : "Start") { custom.startPause() }
                    .buttonStyle(.egoPrimary)
                Button("Reset") { custom.reset() }
                    .buttonStyle(.egoSecondary)
            }
        }
    }

    // MARK: - Stopwatch

    private var stopwatchView: some View {
        let stopwatch = widget.stopwatch
        return VStack(spacing: 6) {
            Group {
                if stopwatch.isRunning {
                    TimelineView(.periodic(from: .now, by: 0.05)) { _ in
                        Text(Stopwatch.format(stopwatch.elapsed))
                    }
                } else {
                    let _ = stopwatch.generation   // re-read on start/pause/reset
                    Text(Stopwatch.format(stopwatch.elapsed))
                }
            }
            .font(.system(size: 34, weight: .bold))
            .egoDigits()
            .foregroundStyle(Ego.text)
            .padding(.top, 10)

            HStack(spacing: 8) {
                Button(stopwatch.isRunning ? "Pause" : "Start") { stopwatch.startPause() }
                    .buttonStyle(.egoPrimary)
                Button("Reset") { stopwatch.reset() }
                    .buttonStyle(.egoSecondary)
            }
        }
    }
}
