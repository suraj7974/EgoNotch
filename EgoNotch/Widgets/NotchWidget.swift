import SwiftUI

/// Which side of the physical notch a closed accessory sits on.
enum NotchEdge { case leading, trailing }

/// Grid footprint in the expanded panel: half-width or full-width row.
enum WidgetTileSize { case small, wide }

/// A self-contained notch module. Widgets are instantiated once by
/// WidgetRegistry and own their long-lived observers; `activate()` /
/// `deactivate()` MUST be idempotent — they fire on launch, quit, and every
/// settings toggle, and a disabled widget must cost nothing.
@MainActor
protocol NotchWidget: AnyObject {
    /// Stable identifier ("media", "calendar"…). Used for settings keys and
    /// view identity — never rename after shipping.
    var id: String { get }
    var displayName: String { get }
    /// SF Symbol name for Settings rows and tile headers.
    var icon: String { get }
    /// On/off before the user ever touches Settings.
    var defaultEnabled: Bool { get }
    var tileSize: WidgetTileSize { get }
    /// Which expanded-panel tab this widget lives on.
    var tab: NotchTab { get }
    /// Advertise file-drop support WITHOUT side effects (gates the chrome's
    /// drop target so drags rubber-band back when nothing would take them).
    var acceptsDroppedFiles: Bool { get }

    /// Slim live indicator beside the notch when closed (max ~24pt wide).
    /// Called once per edge; return nil for edges this widget doesn't use.
    func makeClosedAccessory(for edge: NotchEdge) -> AnyView?
    /// Tile content for non-home tabs. nil = no tile (chrome-only widgets).
    func makeExpandedView() -> AnyView?
    /// Compact column for the Home strip (NotchNest-style). nil = not on it.
    func makeCompactView() -> AnyView?
    /// Tiny element for the panel's top bar (e.g. battery pill). nil = none.
    func makeTopBarAccessory() -> AnyView?

    func activate()
    func deactivate()

    /// Files dropped onto the notch are offered to enabled widgets in
    /// registry order; return true to consume them.
    func handleDroppedFiles(_ urls: [URL]) -> Bool
}

extension NotchWidget {
    var defaultEnabled: Bool { true }
    var tileSize: WidgetTileSize { .small }
    var tab: NotchTab { .home }
    var acceptsDroppedFiles: Bool { false }
    func makeClosedAccessory(for edge: NotchEdge) -> AnyView? { nil }
    func makeExpandedView() -> AnyView? { nil }
    func makeCompactView() -> AnyView? { nil }
    func makeTopBarAccessory() -> AnyView? { nil }
    func activate() {}
    func deactivate() {}
    func handleDroppedFiles(_ urls: [URL]) -> Bool { false }

    var isEnabled: Bool {
        SettingsStore.shared.isEnabled(id, defaultValue: defaultEnabled)
    }
}
