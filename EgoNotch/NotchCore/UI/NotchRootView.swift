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
                    .frame(height: geometry.chromeSize(for: .closed, config: config).height)
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
                VStack(spacing: 8) {
                    PanelTopBar()
                    PanelContent()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.top, 8)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
    }
}

/// NotchNest-style top bar: icon-only tab circles on the left; widget
/// accessories (battery pill), settings gear, and close on the right.
struct PanelTopBar: View {
    private var ui = PanelUIState.shared

    var body: some View {
        let tabs = ui.availableTabs
        HStack(spacing: 6) {
            ForEach(tabs) { tab in
                Button {
                    withAnimation(Ego.Motion.spring()) { ui.selectedTab = tab }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ui.selectedTab == tab ? Ego.text : Ego.textMute)
                        .frame(width: 30, height: 30)
                        .background(
                            ui.selectedTab == tab ? Color.white.opacity(0.14) : .clear,
                            in: Circle()
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }

            Spacer(minLength: 0)

            ForEach(topBarAccessories, id: \.id) { accessory in
                accessory.view
            }

            barButton("gearshape.fill") {
                NotificationCenter.default.post(name: .egoOpenSettings, object: nil)
            }
            barButton("xmark") {
                NotificationCenter.default.post(name: .egoCollapseNotch, object: nil)
            }
        }
        .onAppear { ui.normalize() }
        .onChange(of: tabs) { ui.normalize() }
    }

    private struct Accessory: Identifiable {
        let id: String
        let view: AnyView
    }

    private var topBarAccessories: [Accessory] {
        WidgetRegistry.enabled.compactMap { w in
            w.makeTopBarAccessory().map { Accessory(id: w.id, view: $0) }
        }
    }

    private func barButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ego.textMute)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Per-tab content. Home is a NotchNest-style strip of divided columns;
/// other tabs lay their tiles out in fixed (non-scrolling) rows.
struct PanelContent: View {
    private var ui = PanelUIState.shared

    var body: some View {
        if ui.selectedTab == .home {
            HomeStripView()
        } else {
            WidgetGridView()
        }
    }
}

/// Divided columns of compact widget views — everything visible, no scroll.
struct HomeStripView: View {
    var body: some View {
        let columns = WidgetRegistry.enabled
            .filter { $0.tab == .home }
            .compactMap { w in w.makeCompactView().map { (w.id, $0) } }

        if columns.isEmpty {
            EmptyGridView()
        } else {
            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.element.0) { index, column in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 1)
                            .padding(.vertical, 10)
                    }
                    column.1
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }
}
