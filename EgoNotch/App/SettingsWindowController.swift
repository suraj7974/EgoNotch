import AppKit
import SwiftUI

/// Manually managed settings window (no SwiftUI Settings scene — in an
/// LSUIElement app it opens behind the frontmost app and hijacks Cmd+,).
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "EgoNotch Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.titlebarAppearsTransparent = true
            w.appearance = NSAppearance(named: .darkAqua)   // EgoLock is dark-only
            w.backgroundColor = NSColor(Ego.bg)
            w.isReleasedWhenClosed = false                  // reuse one instance
            w.center()
            window = w
        }
        NSApp.activate()   // required in LSUIElement apps or the window opens behind
        window?.makeKeyAndOrderFront(nil)
    }
}
