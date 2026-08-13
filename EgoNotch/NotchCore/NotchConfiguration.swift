import CoreGraphics

/// Geometry tunables for the notch panel. User-configurable values are pulled
/// from SettingsStore at resolve time via `current()`.
struct NotchConfiguration: Equatable {
    var wingWidth: CGFloat = 44          // closed-state strip on each side of the notch
    var hoverOutset: CGFloat = 8         // extra width per side while hovering
    var hoverDrop: CGFloat = 6           // extra height while hovering
    var hoverGlowMargin: CGFloat = 12    // transparent slack so the glow isn't clipped
    var expandedSize = CGSize(width: 640, height: 240)   // content area below the notch
    var virtualNotchWidth: CGFloat = 190
    var virtualNotchHeight: CGFloat = 32

    static func current() -> NotchConfiguration {
        var c = NotchConfiguration()
        let settings = SettingsStore.shared
        c.virtualNotchWidth = settings.virtualNotchSize.width
        c.virtualNotchHeight = settings.virtualNotchSize.height
        return c
    }
}
