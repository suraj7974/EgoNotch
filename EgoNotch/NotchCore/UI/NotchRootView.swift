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
            shape.stroke(Color.white.opacity(state == .expanded ? 0.10 : 0), lineWidth: 1)
        )
        // No glow: any halo makes the collapsed notch read as not-quite-black.
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
            if geometry.isPhysicalNotch {
                // Reclaim the camera-housing strip: the bar flanks the notch
                // instead of leaving a dead black band above the content.
                // layoutPriority pins it — content that outgrows the panel
                // must clip at the bottom, never shove the bar off-screen.
                PanelTopBar(notchGap: geometry.notchRect.width)
                    .frame(height: geometry.notchRect.height)
                    .padding(.horizontal, 14)
                    .layoutPriority(1)
            }
            ZStack(alignment: .top) {
                Color.black
                VStack(spacing: 10) {
                    if !geometry.isPhysicalNotch {
                        PanelTopBar(notchGap: nil)
                    }
                    PanelContent()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.top, geometry.isPhysicalNotch ? 10 : 12)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }
}

/// NotchNest-style top bar: icon-only tab circles on the left; widget
/// accessories (battery pill), settings gear, and close on the right.
/// When `notchGap` is set the bar straddles the physical camera housing —
/// left group, gap, right group — so that strip isn't wasted.
struct PanelTopBar: View {
    var notchGap: CGFloat?
    private var ui = PanelUIState.shared

    init(notchGap: CGFloat? = nil) {
        self.notchGap = notchGap
    }

    private var compact: Bool { notchGap != nil }
    private var circle: CGFloat { compact ? 26 : 30 }

    var body: some View {
        let tabs = ui.availableTabs
        HStack(spacing: 0) {
            HStack(spacing: compact ? 3 : 6) {
                ForEach(tabs) { tab in
                    Button {
                        withAnimation(Ego.Motion.spring()) { ui.selectedTab = tab }
                    } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: compact ? 11 : 12, weight: .semibold))
                            .foregroundStyle(ui.selectedTab == tab ? Ego.text : Ego.textMute)
                            .frame(width: circle, height: circle)
                            .background(
                                ui.selectedTab == tab ? Color.white.opacity(0.14) : .clear,
                                in: Circle()
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(tab.title)
                }
                if !compact { Spacer(minLength: 0) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let notchGap {
                Color.clear.frame(width: notchGap)   // the camera housing
            }

            HStack(spacing: compact ? 4 : 6) {
                if !compact { Spacer(minLength: 0) }
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
            .frame(maxWidth: .infinity, alignment: .trailing)
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
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .foregroundStyle(Ego.textMute)
                .frame(width: compact ? 24 : 28, height: compact ? 24 : 28)
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
/// Each column carries a small header so the strip never reads empty.
struct HomeStripView: View {
    private struct Column: Identifiable {
        let id: String
        let title: String
        let minWidth: CGFloat?
        let view: AnyView
    }

    var body: some View {
        let columns: [Column] = WidgetRegistry.enabled
            .filter { $0.tab == .home }
            .compactMap { w in
                w.makeCompactView().map {
                    Column(id: w.id, title: w.displayName,
                           minWidth: w.compactMinWidth, view: $0)
                }
            }

        if columns.isEmpty {
            EmptyGridView()
        } else {
            HStack(spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 1)
                            .padding(.vertical, 10)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(column.title)
                            .font(Ego.font(11, .semibold))
                            .foregroundStyle(Ego.textMute)
                        column.view
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .padding(.horizontal, 12)
                    .frame(minWidth: column.minWidth, maxWidth: .infinity,
                           maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }
}
