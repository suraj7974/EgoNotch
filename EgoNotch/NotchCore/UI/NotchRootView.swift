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
        let size = geometry.chromeSize(for: state, config: config)
        let shape = NotchShape(topRadius: config.topFlareRadius,
                               bottomRadius: state == .expanded ? 24 : 14)

        ZStack(alignment: .top) {
            // Pure black chrome base: the wings and top strip must read as an
            // extension of the physical bezel over any wallpaper.
            shape.fill(Color.black)

            if state == .expanded {
                expandedContent(geometry: geometry, config: config)
                    .transition(.opacity)
            } else {
                ClosedAccessoryStrip(notchWidth: geometry.notchRect.width)
                    .frame(height: geometry.notchRect.height)
                    .padding(.horizontal, config.topFlareRadius)
                    .transition(.opacity)
            }
        }
        .compositingGroup()
        .clipShape(shape)
        .overlay(                       // crisp hairline on the expanded panel
            shape.stroke(Color.white.opacity(state == .expanded ? 0.07 : 0), lineWidth: 1)
        )
        .shadow(color: Ego.glowColor.opacity(state == .hover ? Ego.glowOpacity : 0),
                radius: Ego.glowRadius)
        .shadow(color: .black.opacity(state == .expanded ? 0.55 : 0),
                radius: 18, y: 8)       // premium depth under the open panel
        .frame(width: size.width, height: size.height)
        .contentShape(shape)
        .onTapGesture { controller.clicked() }
    }

    private func expandedContent(geometry: NotchGeometry, config: NotchConfiguration) -> some View {
        VStack(spacing: 0) {
            // Dead zone behind the physical camera housing.
            Color.clear.frame(height: geometry.notchRect.height)
            ZStack {
                Ego.panelGradient
                WidgetGridView()
            }
        }
    }
}
