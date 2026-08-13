import SwiftUI

/// The SwiftUI root inside the notch panel. Anchored top-center — combined
/// with every window frame sharing the same top edge and center X, instant
/// window resizes never move a visible pixel; only the spring does.
struct NotchRootView: View {
    var controller: NotchStateController

    var body: some View {
        ZStack(alignment: .top) {
            if let geometry = controller.geometry {
                chrome(geometry: geometry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func chrome(geometry: NotchGeometry) -> some View {
        let state = controller.state
        let config = controller.config
        let notch = geometry.notchRect

        let width: CGFloat = switch state {
        case .closed: notch.width + 2 * config.wingWidth
        case .hover: notch.width + 2 * config.wingWidth + 2 * config.hoverOutset
        case .expanded: max(config.expandedSize.width, notch.width + 2 * config.wingWidth)
        }
        let height: CGFloat = switch state {
        case .closed: notch.height
        case .hover: notch.height + config.hoverDrop
        case .expanded: notch.height + config.expandedSize.height
        }
        let bottomRadius: CGFloat = state == .expanded ? 20 : 10

        ZStack(alignment: .top) {
            // Pure black chrome: over Tahoe's transparent menu bar the wings
            // must read as an extension of the physical bezel.
            NotchShape(bottomRadius: bottomRadius)
                .fill(Color.black)

            if state == .expanded {
                expandedContent(notchHeight: notch.height)
                    .transition(.opacity)
            } else {
                ClosedAccessoryStrip(notchWidth: notch.width)
                    .frame(height: notch.height)
                    .transition(.opacity)
            }
        }
        .compositingGroup()
        .clipShape(NotchShape(bottomRadius: bottomRadius))
        .shadow(color: Ego.cyan.opacity(state == .hover ? 0.35 : 0), radius: 8)
        .frame(width: width, height: height)
        .contentShape(NotchShape(bottomRadius: bottomRadius))
        .onTapGesture { controller.clicked() }
    }

    private func expandedContent(notchHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Dead zone behind the physical camera housing.
            Color.clear.frame(height: notchHeight)
            ZStack {
                Ego.bg
                GridTexture()
                WidgetGridView()
            }
        }
    }
}
