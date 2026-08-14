import AppKit

/// The borderless, non-activating panel that sits over the physical notch and
/// floats above everything, including other apps' fullscreen Spaces.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false                 // avoids stale shadow-shape artifacts mid-spring
        hidesOnDeactivate = false         // critical: an LSUIElement agent is almost never active
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }    // future text input in the expanded panel
    override var canBecomeMain: Bool { false }

    /// Excluded from screen capture — the window still draws on this Mac, but
    /// screenshots, recordings and screen shares see straight through it. This
    /// is the same mechanism macOS uses for password fields, and it applies to
    /// every capture path (ScreenCaptureKit, display capture, `screencapture`).
    var isHiddenFromCapture: Bool {
        get { sharingType == .none }
        set { sharingType = newValue ? .none : .readOnly }
    }
}
