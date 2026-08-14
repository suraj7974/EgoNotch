import AppKit
import SwiftUI

/// Owns the panel window, applies per-state frames, and wires mouse tracking,
/// click-outside monitoring, and display changes into the state controller.
final class NotchPanelController: NSObject {
    let stateController = NotchStateController()

    private let panel = NotchPanel()
    private var hostingView: PanelHostingView<NotchRootView>!
    private var displayObserver: DisplayObserver?
    private var fullScreenObserver: FullScreenObserver?
    private var hiddenForFullScreen = false
    private var clickMonitor: ClickOutsideMonitor?
    private var currentDisplayID: CGDirectDisplayID?
    private var previouslyActiveApp: NSRunningApplication?
    private var previousState: NotchState = .closed

    override init() {
        super.init()

        hostingView = PanelHostingView(rootView: NotchRootView(controller: stateController))
        hostingView.onMouseEntered = { [weak self] in self?.stateController.mouseEntered() }
        hostingView.onMouseExited = { [weak self] in self?.stateController.mouseExited() }
        hostingView.onEscape = { [weak self] in self?.stateController.collapse() }
        panel.contentView = hostingView

        stateController.applyPanelFrame = { [weak self] frame in
            self?.panel.setFrame(frame, display: true)
        }
        stateController.isPanelKey = { [weak self] in
            self?.panel.isKeyWindow ?? false
        }
        stateController.onStateChange = { [weak self] state in
            self?.stateDidChange(state)
        }

        displayObserver = DisplayObserver { [weak self] in self?.reposition(force: false) }
        fullScreenObserver = FullScreenObserver()
        fullScreenObserver?.onChange = { [weak self] fullScreen in
            self?.setHiddenForFullScreen(fullScreen)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(repositionFromNotification),
            name: SettingsStore.geometryDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(songChanged(_:)),
            name: .egoSongChanged,
            object: nil
        )

        reposition(force: true)
    }

    func expand() { stateController.expand() }

    // MARK: - Fullscreen

    /// A fullscreen window on the notch's display gets the screen to itself:
    /// the panel is ordered out entirely (collapsing first, so it doesn't come
    /// back mid-animation) and restored when that window leaves.
    private func setHiddenForFullScreen(_ hidden: Bool) {
        guard SettingsStore.shared.hideInFullScreen else {
            if hiddenForFullScreen { hiddenForFullScreen = false; panel.orderFrontRegardless() }
            return
        }
        guard hidden != hiddenForFullScreen else { return }
        hiddenForFullScreen = hidden
        if hidden {
            stateController.collapse()
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    // MARK: - State side effects

    private func stateDidChange(_ state: NotchState) {
        // Trackpad haptic on open/close (silent; no-op without a Force Touch pad).
        if state == .expanded || previousState == .expanded {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
        previousState = state
        if state == .expanded {
            // Esc needs key status. Take it only for click/menu expansion so
            // a hover-dwell expand never steals the user's keyboard focus.
            if stateController.expandedInteractively, !panel.isKeyWindow {
                previouslyActiveApp = NSWorkspace.shared.frontmostApplication
                panel.makeKey()
            }
            guard clickMonitor == nil else { return }
            clickMonitor = ClickOutsideMonitor { [weak self] point in
                guard let self else { return }
                if !self.panel.frame.contains(point) {
                    self.stateController.collapse()
                }
            }
        } else {
            if panel.isKeyWindow {
                previouslyActiveApp?.activate()   // hand the keyboard back
            }
            previouslyActiveApp = nil
            clickMonitor?.invalidate()
            clickMonitor = nil
        }
    }

    // MARK: - Screen selection & positioning

    @objc private func repositionFromNotification() { reposition(force: true) }

    @objc private func songChanged(_ note: Notification) {
        guard let title = note.userInfo?["title"] as? String else { return }
        stateController.showBanner(title: title,
                                   subtitle: note.userInfo?["artist"] as? String)
    }

    /// Re-derive everything from fresh screen data — never relative to the
    /// panel's previous frame. This is what makes drift impossible.
    ///
    /// System dialogs (TCC prompts etc.) fire spurious screen-parameter
    /// notifications with IDENTICAL geometry — those must not slam an open
    /// panel shut, so the non-forced path skips when nothing really changed.
    private func reposition(force: Bool) {
        guard let screen = Self.preferredScreen() else {
            panel.orderOut(nil)
            currentDisplayID = nil
            fullScreenObserver?.watch(displayID: nil)
            return
        }
        let geometry = NotchGeometry.resolve(for: screen, config: .current())
        if !force, geometry == stateController.geometry,
           screen.displayID == currentDisplayID {
            if !hiddenForFullScreen { panel.orderFrontRegardless() }
            return
        }
        currentDisplayID = screen.displayID
        stateController.displayChanged(geometry: geometry)
        if !hiddenForFullScreen { panel.orderFrontRegardless() }
        fullScreenObserver?.watch(displayID: screen.displayID)
    }

    /// Priority: a screen with a real notch → the built-in display → main.
    private static func preferredScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if let notched = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notched
        }
        if let builtIn = screens.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 }) {
            return builtIn
        }
        return NSScreen.main ?? screens.first
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
