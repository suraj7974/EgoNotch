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
    private var meetingObserver: MeetingObserver?
    private var fullScreenActive = false
    private var meetingActive = false
    private var panelHidden = false
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
        panel.onTabShortcut = { [weak self] index in
            self?.selectTab(at: index)
        }

        displayObserver = DisplayObserver { [weak self] in self?.reposition(force: false) }
        fullScreenObserver = FullScreenObserver()
        fullScreenObserver?.onChange = { [weak self] fullScreen in
            self?.fullScreenActive = fullScreen
            self?.updateVisibility()
        }
        meetingObserver = MeetingObserver()
        meetingObserver?.onChange = { [weak self] inMeeting in
            self?.meetingActive = inMeeting
            self?.updateVisibility()
        }
        meetingObserver?.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(visibilityRulesChanged),
            name: SettingsStore.visibilityRulesDidChange,
            object: nil
        )
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
        updateVisibility()      // apply the rules once, before anything changes
    }

    func expand() { stateController.expand() }

    // MARK: - When to disappear

    /// Two different answers to "get out of the way", and they are not the
    /// same thing:
    ///
    /// • fullscreen → actually hide the window (nothing should sit over a
    ///   fullscreen video on your own screen);
    /// • call / screen share → keep it fully usable here, but make it
    ///   invisible to capture, so the people watching never see it.
    private func updateVisibility() {
        let settings = SettingsStore.shared

        // EGO_HIDE_FROM_CAPTURE=1 forces it on, for testing without a call.
        panel.isHiddenFromCapture = (meetingActive && settings.hideInMeetings)
            || ProcessInfo.processInfo.environment["EGO_HIDE_FROM_CAPTURE"] != nil

        let shouldHide = fullScreenActive && settings.hideInFullScreen
        guard shouldHide != panelHidden else { return }
        panelHidden = shouldHide
        if shouldHide {
            stateController.collapse()      // collapse first, then vanish
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    @objc private func visibilityRulesChanged() { updateVisibility() }

    /// ⌥N picks the Nth tab as drawn — the position you see, not the enum
    /// order, so a disabled module never leaves a hole in the numbering.
    private func selectTab(at index: Int) {
        guard stateController.state == .expanded else { return }
        let tabs = PanelUIState.shared.availableTabs
        guard index >= 1, index <= tabs.count else { return }
        PanelUIState.shared.selectedTab = tabs[index - 1]
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
            if !panelHidden { panel.orderFrontRegardless() }
            return
        }
        currentDisplayID = screen.displayID
        stateController.displayChanged(geometry: geometry)
        if !panelHidden { panel.orderFrontRegardless() }
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
