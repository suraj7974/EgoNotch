import SwiftUI

/// The SwiftUI root inside the notch panel. Anchored top-center — combined
/// with every window frame sharing the same top edge and center X, instant
/// window resizes never move a visible pixel; only the spring does.
struct NotchRootView: View {
    var controller: NotchStateController
    @State private var dragTargeted = false

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
        let shape = NotchShape(
            topRadius: config.topFlareRadius,
            bottomRadius: state == .expanded ? config.expandedBottomRadius
                                             : config.closedBottomRadius)
        let acceptsDrops = WidgetRegistry.canAcceptDroppedFiles

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
        .onDrop(of: acceptsDrops ? [.fileURL] : [], isTargeted: $dragTargeted) { providers in
            guard WidgetRegistry.canAcceptDroppedFiles else { return false }
            FileDropHandler.load(providers) { urls in
                if let consumer = WidgetRegistry.handleDroppedFiles(urls) {
                    PanelUIState.shared.selectedTab = consumer.tab
                }
            }
            return true
        }
        .onChange(of: dragTargeted) { _, targeted in
            if targeted {
                controller.dragEntered()
            } else {
                controller.dragExited()
            }
        }
    }

    private func expandedContent(geometry: NotchGeometry, config: NotchConfiguration) -> some View {
        VStack(spacing: 0) {
            // Dead zone behind the physical camera housing.
            Color.clear.frame(height: geometry.notchRect.height)
            ZStack(alignment: .top) {
                Ego.panelGradient
                VStack(spacing: 10) {
                    PanelTabBar()
                    ScrollView(.vertical, showsIndicators: false) {
                        WidgetGridView()
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.top, 12)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }
}

/// Nucleus-style segmented tab bar; hidden while only one tab is populated.
struct PanelTabBar: View {
    private var ui = PanelUIState.shared

    var body: some View {
        let tabs = ui.availableTabs
        if tabs.count > 1 {
            HStack(spacing: 4) {
                ForEach(tabs) { tab in
                    Button {
                        withAnimation(Ego.Motion.spring()) { ui.selectedTab = tab }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 10, weight: .semibold))
                            Text(tab.title)
                                .font(Ego.font(11.5, .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            ui.selectedTab == tab ? Color.white.opacity(0.14) : .clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .foregroundStyle(ui.selectedTab == tab ? Ego.text : Ego.textMute)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
            .onAppear { ui.normalize() }
        }
    }
}
