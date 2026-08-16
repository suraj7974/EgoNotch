import AppKit
import ApplicationServices

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
    private var poll: Timer?

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
        // The timer is not touched here: it holds a weak reference and Swift 6
        // will not let a nonisolated deinit reach main-actor state. Stopping
        // the observer is `stop()`'s job.
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    /// Stops watching. Called when the panel goes away.
    func stop() {
        poll?.invalidate()
        poll = nil
    }

    /// Tell the observer which display the notch lives on.
    func watch(displayID: CGDirectDisplayID?) {
        self.displayID = displayID
        recheck()
        startPolling()
    }

    /// Video going fullscreen *inside* a window — YouTube in a browser — often
    /// switches no Space and activates no app, so there is no notification to
    /// hang this on. The check is two Accessibility calls, so once a second
    /// costs nothing measurable and is the difference between the notch
    /// getting out of the way and sitting over the picture.
    private func startPolling() {
        poll?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    /// The Space switch lands before the new window is on screen, so sample a
    /// beat later — and coalesce the burst of notifications a switch fires.
    /// Sampled twice: some apps (browsers going fullscreen for a video) resize
    /// their window a good half-second after the Space appears.
    @objc private func recheck() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.evaluate() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.evaluate()
        }
    }

    private func evaluate() {
        guard let displayID else { return }
        // Three signals, because no single one is reliable:
        //
        //  • The window list needs Screen Recording permission, which this app
        //    does not ask for — without it the list comes back empty and the
        //    geometric checks below can never fire. That is why fullscreen was
        //    not being noticed at all.
        //  • The menu bar disappearing is a strong hint, but so is "hide the
        //    menu bar automatically".
        //  • Accessibility, which the user HAS granted, can read the front
        //    window's own frame — no Screen Recording needed.
        let menuBarGone = Self.menuBarHidden(on: displayID)
        let frontCovers = Self.frontWindowCoversDisplay(displayID)
        let covered = frontCovers
            || Self.hasFullScreenWindow(on: displayID)
            || (menuBarGone && Self.hasDisplayWideWindow(on: displayID))
        guard covered != isFullScreen else { return }
        isFullScreen = covered
        EgoLog.trace("fullscreen \(covered ? "began" : "ended") "
                     + "(front window \(frontCovers), menu bar gone \(menuBarGone))")
        onChange?(covered)
    }

    /// The frontmost app's window, measured through Accessibility.
    ///
    /// A truly fullscreen window starts at the very top of the display and is
    /// the size of it — a merely zoomed window begins below the menu bar, so
    /// the origin is what tells them apart.
    private static func frontWindowCoversDisplay(_ displayID: CGDirectDisplayID) -> Bool {
        guard AXIsProcessTrusted(),
              let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return false }

        let app = AXUIElementCreateApplication(front.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString,
                                            &windowRef) == .success,
              let value = windowRef, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return false }
        let window = value as! AXUIElement

        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString,
                                            &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString,
                                            &sizeRef) == .success
        else { return false }

        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)

        let bounds = CGDisplayBounds(displayID)
        return abs(origin.y - bounds.minY) <= 2
            && abs(origin.x - bounds.minX) <= 2
            && size.width >= bounds.width - 2
            && size.height >= bounds.height - 2
    }

    // MARK: - Signals

    /// In a fullscreen Space the menu bar is gone, so the screen's visible
    /// frame reaches the top of its frame. This is the signal that catches a
    /// browser going fullscreen for a video, whose window sits *below* the
    /// notch and therefore never matches the display's full height.
    ///
    /// (Someone running with "automatically hide the menu bar" always looks
    /// fullscreen by this test — that's what the geometric check below and the
    /// Settings toggle are for.)
    private static func menuBarHidden(on displayID: CGDirectDisplayID) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID })
        else { return false }
        // A notched display always keeps ≥ the notch height of inset in a
        // normal Space; in fullscreen the whole frame becomes visible.
        return screen.frame.maxY - screen.visibleFrame.maxY < 1
    }

    /// A borderless window covering the display edge to edge — a fullscreen
    /// game or player that never switches Spaces. Strict on purpose: a merely
    /// zoomed window starts below the menu bar and must not count.
    private static func hasFullScreenWindow(on displayID: CGDirectDisplayID) -> Bool {
        let bounds = CGDisplayBounds(displayID)
        return windows(on: displayID).contains { rect in
            abs(rect.minY - bounds.minY) <= 1
                && rect.width >= bounds.width - 1
                && rect.height >= bounds.height - 1
        }
    }

    /// Something as wide as the display is on screen — the corroborating half
    /// of the menu-bar signal.
    private static func hasDisplayWideWindow(on displayID: CGDirectDisplayID) -> Bool {
        let bounds = CGDisplayBounds(displayID)
        return windows(on: displayID).contains { $0.width >= bounds.width - 1 }
    }

    /// On-screen, normal-level windows belonging to other apps, on this display.
    private static func windows(on displayID: CGDirectDisplayID) -> [CGRect] {
        let bounds = CGDisplayBounds(displayID)
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        let ourPID = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { window in
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ourPID,
                  let frame = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: frame as CFDictionary),
                  rect.intersects(bounds)
            else { return nil }
            return rect
        }
    }
}
