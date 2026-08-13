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
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 6)

            Color.clear.frame(width: notchWidth)   // the camera housing itself

            HStack(spacing: 6) {
                ForEach(accessories(on: .trailing), id: \.id) { item in
                    item.view
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
        }
        .padding(.horizontal, 4)
    }

    private struct Accessory: Identifiable {
        let id: String
        let view: AnyView
    }

    private func accessories(on edge: NotchEdge) -> [Accessory] {
        WidgetRegistry.enabled
            .filter { $0.accessoryEdge == edge }
            .compactMap { w in
                w.makeClosedAccessory().map { Accessory(id: w.id, view: $0) }
            }
    }
}
