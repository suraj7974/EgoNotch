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
    var accessoryEdge: NotchEdge { get }

    /// Slim live indicator beside the notch when closed (max ~20pt wide).
    /// nil = this widget shows nothing while closed.
    func makeClosedAccessory() -> AnyView?
    /// Tile content for the expanded panel. Card chrome (surface, border,
    /// section header) is applied by the grid — render content only.
    func makeExpandedView() -> AnyView

    func activate()
    func deactivate()
}

extension NotchWidget {
    var defaultEnabled: Bool { true }
    var tileSize: WidgetTileSize { .small }
    var accessoryEdge: NotchEdge { .trailing }
    func makeClosedAccessory() -> AnyView? { nil }
    func activate() {}
    func deactivate() {}

    var isEnabled: Bool {
        SettingsStore.shared.isEnabled(id, defaultValue: defaultEnabled)
    }
}
