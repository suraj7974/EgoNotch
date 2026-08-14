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
        // Collapsed keeps just a hint of flare (like the stock macOS notch);
        // the deep bezel blend belongs to the open panel.
        let bottomRadius: CGFloat = switch state {
        case .expanded: config.expandedBottomRadius
        case .peek: 20              // the taller pill wants more curve
        default: config.closedBottomRadius
        }
        let shape = NotchShape(
            topRadius: state == .expanded ? config.topFlareRadius
                                          : config.closedTopFlareRadius,
            bottomRadius: bottomRadius)
        let acceptsDrops = WidgetRegistry.canAcceptDroppedFiles

        ZStack(alignment: .top) {
            // Pure black chrome base: the wings and top strip must read as an
            // extension of the physical bezel over any wallpaper.
            shape.fill(Color.black)

            if state == .expanded {
                expandedContent(geometry: geometry, config: config, size: size)
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    ClosedAccessoryStrip(notchWidth: geometry.notchRect.width)
                        .frame(height: geometry.chromeSize(for: .closed, config: config).height)
                        .padding(.horizontal, 8)
                    if state == .peek, let banner = controller.bannerText {
                        // Live activity strip under the notch.
                        VStack(spacing: 0) {
                            Text(banner)
                                .font(Ego.font(11, .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if let subtitle = controller.bannerSubtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(Ego.font(9))
                                    .foregroundStyle(Ego.textMute)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                    }
                }
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
        // Panel-wide: a drop anywhere (any tab, or the collapsed notch)
        // lands on the shelf and switches to it.
        .onDrop(of: acceptsDrops ? FileDropHandler.acceptedTypes : [],
                isTargeted: $dragTargeted) { providers in
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

    private func expandedContent(geometry: NotchGeometry, config: NotchConfiguration,
                                 size: CGSize) -> some View {
        let stripHeight = geometry.isPhysicalNotch ? geometry.notchRect.height : 0
        // HARD-clamped: a ZStack sizes to its largest child, so without an
        // exact height the content could grow and shove the strip off-screen.
        let contentHeight = max(size.height - stripHeight, 0)

        return VStack(spacing: 0) {
            if geometry.isPhysicalNotch {
                // Reclaim the camera-housing strip: the bar flanks the notch
                // instead of leaving a dead black band above the content.
                PanelTopBar(notchGap: geometry.notchRect.width)
                    .frame(height: stripHeight)
                    // + the flare inset the outer shape clips away, so the
                    // buttons sit inside the visible edge, not on it.
                    .padding(.horizontal, config.topFlareRadius + 14)
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
                .padding(.top, geometry.isPhysicalNotch ? 12 : 16)
                // + the flare inset, which the outer shape clips away.
                .padding(.horizontal, 22 + config.topFlareRadius)
                .padding(.bottom, 18)
            }
            .frame(width: size.width, height: contentHeight)
            // Contain overflow without touching the panel's silhouette:
            // square at the top (flush with the strip), round at the bottom.
            .clipShape(UnevenRoundedRectangle(
                bottomLeadingRadius: config.expandedBottomRadius,
                bottomTrailingRadius: config.expandedBottomRadius))
        }
        .frame(width: size.width, height: size.height, alignment: .top)
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

/// Section title that doubles as "open the app this stands in for" — the
/// whole header is the hit target, so it never competes with the controls
/// inside the column.
struct ColumnHeader: View {
    let title: String
    let appName: String?
    let openApp: () -> Void
    @State private var hovered = false

    var body: some View {
        if let appName {
            Button(action: openApp) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(Ego.font(11, .semibold))
                        .foregroundStyle(hovered ? .white : Ego.textMute)
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Ego.textMute)
                        .opacity(hovered ? 1 : 0)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { over in
                withAnimation(Ego.Motion.spring()) { hovered = over }
            }
            .help("Open \(appName)")
        } else {
            Text(title)
                .font(Ego.font(11, .semibold))
                .foregroundStyle(Ego.textMute)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        let maxWidth: CGFloat?
        let appName: String?
        let openApp: () -> Void
        let view: AnyView
    }

    var body: some View {
        let columns: [Column] = WidgetRegistry.enabled
            .filter { $0.tab == .home }
            .compactMap { w in
                w.makeCompactView().map {
                    Column(id: w.id, title: w.displayName,
                           minWidth: w.compactMinWidth,
                           maxWidth: w.compactMaxWidth,
                           appName: w.companionAppName,
                           openApp: { w.openCompanionApp() },
                           view: $0)
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
                        ColumnHeader(title: column.title, appName: column.appName,
                                     openApp: column.openApp)
                        column.view
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .padding(.horizontal, 12)
                    .frame(minWidth: column.minWidth,
                           maxWidth: column.maxWidth ?? .infinity,
                           maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }
}
