import AppKit

/// Notices when another app owns the whole display — a fullscreen video, a
/// presentation, a game — so the notch can get out of the way instead of
/// floating a black bar over the picture.
///
/// Event-driven: entering or leaving fullscreen switches Spaces, which is the
/// signal we listen for. Nothing polls, so an idle notch still costs nothing.
final class FullScreenObserver {
    /// Called with true while a fullscreen window covers the notch's display.
    var onChange: ((Bool) -> Void)?

    private var displayID: CGDirectDisplayID?
    private var isFullScreen = false
    private var pending: DispatchWorkItem?

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didDeactivateApplicationNotification] {
            workspace.addObserver(self, selector: #selector(recheck),
                                  name: name, object: nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(recheck),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    /// Tell the observer which display the notch lives on.
    func watch(displayID: CGDirectDisplayID?) {
        self.displayID = displayID
        recheck()
    }

    /// The Space switch lands before the new window is on screen, so sample a
    /// beat later — and coalesce the burst of notifications a switch fires.
    @objc private func recheck() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluate() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func evaluate() {
        let covered = Self.hasFullScreenWindow(on: displayID)
        guard covered != isFullScreen else { return }
        isFullScreen = covered
        onChange?(covered)
    }

    /// True when some other app has an on-screen, normal-level window as big
    /// as the display. Fullscreen windows have no title bar and match the
    /// display bounds exactly; ordinary maximised windows stop at the menu bar.
    private static func hasFullScreenWindow(on displayID: CGDirectDisplayID?) -> Bool {
        guard let displayID else { return false }
        let bounds = CGDisplayBounds(displayID)
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        let ourPID = ProcessInfo.processInfo.processIdentifier
        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ourPID,
                  let frame = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: frame as CFDictionary)
            else { continue }
            // Same display, and covering it edge to edge (1pt of slack for
            // rounding on scaled resolutions).
            if abs(rect.minX - bounds.minX) <= 1, abs(rect.minY - bounds.minY) <= 1,
               rect.width >= bounds.width - 1, rect.height >= bounds.height - 1 {
                return true
            }
        }
        return false
    }
}
