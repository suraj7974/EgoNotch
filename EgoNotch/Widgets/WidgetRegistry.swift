import SwiftUI

/// The ONLY file that names concrete widget types. Deleting a widget folder
/// breaks exactly one line here, and the compiler points at it.
enum WidgetRegistry {
    /// Instantiated once, in display order. A widget's position here is its
    /// permanent FILE // index (stable even when other widgets are disabled).
    static let all: [any NotchWidget] = [
        MediaWidget(),
        QuickLinksWidget(),
        CalendarWidget(),
        SystemStatsWidget(),
        BatteryWidget(),
        HUDWidget(),
        ShelfWidget(),
        ClipboardWidget(),
        FocusWidget(),
        NotesWidget(),
        TodoWidget(),
        TerminalWidget(),
        RecorderWidget(),
        DemoWidget(),
    ]

    /// True while at least one enabled widget can take file drops.
    static var canAcceptDroppedFiles: Bool {
        enabled.contains { $0.acceptsDroppedFiles }
    }

    /// Offers the drop to the tab you're currently looking at first (drop a
    /// folder while the Terminal is open and it cds there), then to everyone
    /// else in display order. nil when nothing took it.
    @discardableResult
    static func handleDroppedFiles(_ urls: [URL]) -> (any NotchWidget)? {
        let onScreen = PanelUIState.shared.selectedTab
        let ordered = enabled.filter { $0.tab == onScreen } + enabled.filter { $0.tab != onScreen }
        for widget in ordered where widget.handleDroppedFiles(urls) {
            return widget
        }
        return nil
    }

    static var enabled: [any NotchWidget] { all.filter(\.isEnabled) }

    static func widget(id: String) -> (any NotchWidget)? {
        all.first { $0.id == id }
    }

    /// Call on launch and whenever an enabled toggle flips.
    static func syncActivation() {
        for w in all {
            w.isEnabled ? w.activate() : w.deactivate()
        }
    }
}
