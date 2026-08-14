import SwiftUI

/// Slim live indicators on either side of the physical notch while closed.
/// Widgets contribute via makeClosedAccessory(); nil accessories are skipped.
struct ClosedAccessoryStrip: View {
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(accessories(on: .leading), id: \.id) { item in
                    item.view
                }
            }
            // Sit against the outer edge (with a small inset), not against the
            // camera housing — that's what keeps the wings narrow.
            .frame(maxWidth: .infinity, alignment: .leading)

            Color.clear.frame(width: notchWidth)   // the camera housing itself

            HStack(spacing: 6) {
                ForEach(accessories(on: .trailing), id: \.id) { item in
                    item.view
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 9)
    }

    private struct Accessory: Identifiable {
        let id: String
        let view: AnyView
    }

    private func accessories(on edge: NotchEdge) -> [Accessory] {
        // An exclusive claimant (media with an active session) silences every
        // other widget's accessories so the wings never look crowded.
        let widgets: [any NotchWidget]
        if let exclusive = WidgetRegistry.enabled.first(where: \.wantsExclusiveClosedStrip) {
            widgets = [exclusive]
        } else {
            widgets = WidgetRegistry.enabled
        }
        return widgets.compactMap { w in
            w.makeClosedAccessory(for: edge).map { Accessory(id: w.id, view: $0) }
        }
    }
}
