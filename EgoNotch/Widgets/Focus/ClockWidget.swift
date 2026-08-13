import SwiftUI

/// Phase 4 — clock + date. The per-minute tick exists only while visible.
final class ClockWidget: NotchWidget {
    let id = "clock"
    let displayName = "Clock"
    let icon = "clock"
    let tileSize: WidgetTileSize = .small
    let tab: NotchTab = .focus

    func makeExpandedView() -> AnyView {
        AnyView(ClockTileView())
    }
}

private struct ClockTileView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 30, weight: .bold))
                    .egoDigits()
                    .foregroundStyle(Ego.text)
                Text(context.date, format: .dateTime.weekday(.wide).month().day())
                    .font(Ego.font(11))
                    .foregroundStyle(Ego.textMute)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
