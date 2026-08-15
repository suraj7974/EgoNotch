import Foundation

/// Geometry tunables for the notch panel. User-configurable values are pulled
/// from SettingsStore at resolve time via `current()`.
struct NotchConfiguration: Equatable {
    // Closed chrome: wider than the notch (horizontal presence), exactly the
    // physical notch's height — any shorter and the hardware cutout peeks
    // below the chrome, reading as a "double notch".
    // Just wide enough for a 22pt artwork/visualiser plus a small edge inset —
    // the accessories sit near the outer edge, not floating in dead space.
    var wingWidth: CGFloat = 40          // closed-state strip on each side of the notch
    var closedExtraHeight: CGFloat = 0
    var topFlareRadius: CGFloat = 18     // outward top curves blending into the bezel
    var closedTopFlareRadius: CGFloat = 6    // subtle, like the stock macOS notch
    var closedBottomRadius: CGFloat = 14
    var expandedBottomRadius: CGFloat = 46   // deep NotchNest-style curves when open
    /// Live-activity peek: ~1 cm taller (72 pt/inch → 28.35 pt) and a little
    /// wider so a track title fits under the notch.
    var peekExtraHeight: CGFloat = 28
    var peekExtraWidth: CGFloat = 60
    var peekDuration: TimeInterval = 2.0
    var hoverOutset: CGFloat = 8         // extra width per side while hovering
    var hoverDrop: CGFloat = 6           // extra height while hovering
    var hoverGlowMargin: CGFloat = 12    // transparent slack so the glow isn't clipped
    var expandedSize = CGSize(width: 960, height: 205)   // wide-ish, short — NotchNest-like
    var expandedShadowMargin: CGFloat = 0    // no drop shadow → no slack needed
    /// Ego's HUD grows downward out of the collapsed notch, exactly like the
    /// song-change peek — same gesture, slightly taller because it holds a
    /// waveform rather than one line of text.
    var assistantExtraWidth: CGFloat = 130
    var assistantExtraHeight: CGFloat = 52
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
