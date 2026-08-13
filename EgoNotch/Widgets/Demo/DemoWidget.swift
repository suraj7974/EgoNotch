import SwiftUI

/// Phase 1 placeholder — a minimal shell-status tile with quick actions.
/// Replaced by real widgets as later phases land.
final class DemoWidget: NotchWidget {
    let id = "demo"
    let displayName = "Shell Status"
    let icon = "sparkles.rectangle.stack"
    let tileSize: WidgetTileSize = .wide
    let defaultEnabled = false   // placeholder — real widgets ship now

    func makeExpandedView() -> AnyView {
        AnyView(DemoWidgetView())
    }

    func makeClosedAccessory(for edge: NotchEdge) -> AnyView? {
        guard edge == .trailing else { return nil }
        return AnyView(
            Circle()
                .fill(Ego.text)
                .frame(width: 5, height: 5)
        )
    }
}

private struct DemoWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(Ego.win).frame(width: 6, height: 6)
                Text("Shell online")
                    .font(Ego.font(12, .medium))
                    .foregroundStyle(Ego.text)
                Text("v0.1.0")
                    .font(Ego.font(10))
                    .egoDigits()
                    .foregroundStyle(Ego.textMute)
                Spacer()
            }

            HStack(spacing: 8) {
                Button("Open Settings") {
                    NotificationCenter.default.post(name: .egoOpenSettings, object: nil)
                }
                .buttonStyle(.egoPrimary)
                Button("Collapse") {
                    NotificationCenter.default.post(name: .egoCollapseNotch, object: nil)
                }
                .buttonStyle(.egoSecondary)
                Spacer()
            }
        }
    }
}
