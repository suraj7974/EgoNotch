import SwiftUI

/// The ONLY file that names concrete widget types. Deleting a widget folder
/// breaks exactly one line here, and the compiler points at it.
enum WidgetRegistry {
    /// Instantiated once, in display order. A widget's position here is its
    /// permanent FILE // index (stable even when other widgets are disabled).
    static let all: [any NotchWidget] = [
        DemoWidget(),
        // Phase 2+: MediaWidget(), ShelfWidget(), CalendarWidget(), ...
    ]

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
