import SwiftUI

/// Phase 1 placeholder — doubles as a living showcase of the EgoLock design
/// system. Replaced by real widgets from Phase 2 on.
final class DemoWidget: NotchWidget {
    let id = "demo"
    let displayName = "Shell Status"
    let icon = "sparkles.rectangle.stack"
    let tileSize: WidgetTileSize = .wide

    func makeExpandedView() -> AnyView {
        AnyView(DemoWidgetView())
    }

    func makeClosedAccessory(for edge: NotchEdge) -> AnyView? {
        guard edge == .trailing else { return nil }
        return AnyView(
            Circle()
                .fill(Ego.cyan)
                .frame(width: 5, height: 5)
                .shadow(color: Ego.cyan.opacity(0.35), radius: 3)
        )
    }
}

private struct DemoWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Chip(text: "SHELL ONLINE", variant: .win)
                Chip(text: "0 MODULES LIVE", variant: .neutral)
                Chip(text: "V0.1.0", variant: .accent)
                Spacer()
            }

            HStack(spacing: 12) {
                Text("EGONOTCH // PHASE 1")
                    .font(Ego.mono(14, .semibold))
                    .tracking(Ego.headerTracking)
                    .foregroundStyle(Ego.text)
                Spacer()
                Text("240 × 640")
                    .font(Ego.mono(12))
                    .egoDigits()
                    .foregroundStyle(Ego.textMute)
            }
            .padding(10)
            .background(Ego.surface2, in: RoundedRectangle(cornerRadius: Ego.cardRadius))
            .egoActive()

            HStack(spacing: 10) {
                Button("Open Settings") {
                    NotificationCenter.default.post(name: .egoOpenSettings, object: nil)
                }
                .buttonStyle(.egoPrimary)
                Button("Collapse — ESC") {
                    NotificationCenter.default.post(name: .egoCollapseNotch, object: nil)
                }
                .buttonStyle(.egoSecondary)
                Spacer()
            }
        }
    }
}
