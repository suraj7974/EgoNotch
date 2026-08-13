import AppKit
import SwiftUI

/// Shown once on first launch (flag in UserDefaults); reachable again from
/// Settings if the user wants the tour back.
final class OnboardingWindowController {
    private static let doneKey = "onboarding.done"
    private var window: NSWindow?

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: doneKey)
    }

    func showIfNeeded() {
        guard !Self.hasCompleted else { return }
        show()
    }

    func show() {
        if window == nil {
            let view = OnboardingView { [weak self] in
                UserDefaults.standard.set(true, forKey: Self.doneKey)
                self?.window?.close()
            }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "Welcome"
            w.styleMask = [.titled, .closable]
            w.titlebarAppearsTransparent = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(Ego.bg)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()   // visible even if activation is denied
    }
}
