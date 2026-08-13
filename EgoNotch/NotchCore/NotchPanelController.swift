import AppKit
import SwiftUI

/// Owns the panel window, applies per-state frames, and wires mouse tracking,
/// click-outside monitoring, and display changes into the state controller.
final class NotchPanelController: NSObject {
    let stateController = NotchStateController()

    private let panel = NotchPanel()
    private var hostingView: PanelHostingView<NotchRootView>!
    private var displayObserver: DisplayObserver?
    private var clickMonitor: ClickOutsideMonitor?
    private var currentDisplayID: CGDirectDisplayID?
    private var previouslyActiveApp: NSRunningApplication?

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(repositionFromNotification),
            name: SettingsStore.geometryDidChange,
            object: nil
        )

        reposition(force: true)
    }

    func expand() { stateController.expand() }

    // MARK: - State side effects

    private func stateDidChange(_ state: NotchState) {
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
            return
        }
        let geometry = NotchGeometry.resolve(for: screen, config: .current())
        if !force, geometry == stateController.geometry,
           screen.displayID == currentDisplayID {
            panel.orderFrontRegardless()
            return
        }
        currentDisplayID = screen.displayID
        stateController.displayChanged(geometry: geometry)
        panel.orderFrontRegardless()
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
