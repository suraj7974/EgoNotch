import CoreGraphics

/// Geometry tunables for the notch panel. User-configurable values are pulled
/// from SettingsStore at resolve time via `current()`.
struct NotchConfiguration: Equatable {
    // Closed chrome hugs the physical notch (user: stock size when collapsed).
    var wingWidth: CGFloat = 44          // closed-state strip on each side of the notch
    var closedExtraHeight: CGFloat = 0
    var topFlareRadius: CGFloat = 8      // outward top curves blending into the bezel
    var closedBottomRadius: CGFloat = 11
    var expandedBottomRadius: CGFloat = 34   // big NotchNest-style curves when open
    var hoverOutset: CGFloat = 8         // extra width per side while hovering
    var hoverDrop: CGFloat = 6           // extra height while hovering
    var hoverGlowMargin: CGFloat = 12    // transparent slack so the glow isn't clipped
    var expandedSize = CGSize(width: 700, height: 400)   // chrome area below the notch
    var expandedShadowMargin: CGFloat = 28   // transparent slack for the drop shadow
    var virtualNotchWidth: CGFloat = 190
    var virtualNotchHeight: CGFloat = 32

    static func current() -> NotchConfiguration {
        var c = NotchConfiguration()
        let settings = SettingsStore.shared
        c.virtualNotchWidth = settings.virtualNotchSize.width
        c.virtualNotchHeight = settings.virtualNotchSize.height
        c.expandedSize = CGSize(width: settings.panelWidth, height: settings.panelHeight)
        return c
    }
}
