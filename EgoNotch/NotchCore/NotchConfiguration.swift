import CoreGraphics

/// Geometry tunables for the notch panel. User-configurable values are pulled
/// from SettingsStore at resolve time via `current()`.
struct NotchConfiguration: Equatable {
    var wingWidth: CGFloat = 56          // closed-state strip on each side of the notch
    var closedExtraHeight: CGFloat = 4   // chrome dips below the physical notch (bigger look)
    var topFlareRadius: CGFloat = 8      // outward top curves blending into the bezel
    var hoverOutset: CGFloat = 8         // extra width per side while hovering
    var hoverDrop: CGFloat = 6           // extra height while hovering
    var hoverGlowMargin: CGFloat = 12    // transparent slack so the glow isn't clipped
    var expandedSize = CGSize(width: 640, height: 330)   // chrome area below the notch
    var expandedShadowMargin: CGFloat = 28   // transparent slack for the drop shadow
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
