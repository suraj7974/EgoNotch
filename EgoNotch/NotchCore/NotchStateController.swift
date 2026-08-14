import AppKit
import SwiftUI
import Observation

/// Single source of truth for the panel's UI state. Every transition flows
/// through here, which keeps the AppKit window frame and the SwiftUI spring
/// permanently in sync: the window is instantly sized to the union of what is
/// on screen and the target (so an interrupted shrink can never clip content),
/// then trimmed to the exact target after the spring settles. `state` is the
/// only animated value.
@Observable
final class NotchStateController {
    private(set) var state: NotchState = .closed
    private(set) var geometry: NotchGeometry?

    /// Injected by NotchPanelController.
    @ObservationIgnored var applyPanelFrame: ((CGRect) -> Void)?
    @ObservationIgnored var onStateChange: ((NotchState) -> Void)?
    /// True while the panel is the key window (user is typing in it).
    @ObservationIgnored var isPanelKey: (() -> Bool)?

    /// True when the current expansion came from a click / menu item — only
    /// then may the panel take key focus. Hover-dwell expansion must never
    /// steal the user's keyboard.
    @ObservationIgnored private(set) var expandedInteractively = false

    /// Text shown by the transient peek strip (e.g. a new track's title).
    private(set) var bannerText: String?
    private(set) var bannerSubtitle: String?

    @ObservationIgnored private var dwellTask: Task<Void, Never>?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private(set) var config = NotchConfiguration.current()

    /// The frame most recently handed to the panel (window truth, which lags
    /// the logical state during a deferred shrink).
    @ObservationIgnored private var appliedFrame: CGRect = .null
    /// Bumped by every transition and display change; in-flight spring
    /// completions captured against an older epoch must not touch the window.
    @ObservationIgnored private var epoch = 0

    private var behavior: ExpansionBehavior {
        let settings = SettingsStore.shared
        return settings.expandOnHover ? .hoverWithDwell(settings.hoverDwell) : .clickToExpand
    }

    // MARK: - Inputs

    /// Announce something briefly on the collapsed notch (song changed…).
    /// Never interrupts a panel the user has open or is hovering.
    func showBanner(title: String, subtitle: String?) {
        guard state == .closed || state == .peek else { return }
        bannerText = title
        bannerSubtitle = subtitle
        bannerTask?.cancel()
        if state == .closed { transition(to: .peek) }
        bannerTask = Task { [weak self] in
            let hold = self?.config.peekDuration ?? 2
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled, let self, self.state == .peek else { return }
            self.transition(to: .closed)
            self.bannerText = nil
            self.bannerSubtitle = nil
        }
    }

    private func dismissBanner() {
        bannerTask?.cancel()
        bannerTask = nil
        bannerText = nil
        bannerSubtitle = nil
    }

    func mouseEntered() {
        collapseTask?.cancel()
        collapseTask = nil
        // A peek in progress gives way to the user's intent.
        if state == .peek {
            dismissBanner()
            transition(to: .hover)
            scheduleDwellIfNeeded()
            return
        }
        guard state == .closed, let geometry else { return }
        // During a deferred shrink the tracking rect is still the old, larger
        // frame — accept the enter only if the pointer is really on the
        // closed chrome. (Both rects are in global screen coordinates.)
        let closedRect = geometry.panelFrame(for: .closed, config: config).insetBy(dx: -4, dy: -4)
        guard closedRect.contains(NSEvent.mouseLocation) else { return }
        transition(to: .hover)
        scheduleDwellIfNeeded()
    }

    private func scheduleDwellIfNeeded() {
        guard case .hoverWithDwell(let dwell) = behavior else { return }
        dwellTask?.cancel()
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(dwell))
            guard !Task.isCancelled else { return }
            self?.dwellFired()
        }
    }

    func mouseExited() {
        dwellTask?.cancel()
        dwellTask = nil
        switch state {
        case .hover:
            transition(to: .closed)
        case .expanded:
            scheduleCollapseIfPointerOutside()
        case .closed, .peek:
            break   // the peek retires on its own timer
        }
    }

    /// Click on the notch chrome (any mode expands immediately).
    func clicked() {
        guard state != .expanded else { return }
        dismissBanner()
        expandedInteractively = true
        transition(to: .expanded)
    }

    func expand() {
        expandedInteractively = true
        transition(to: .expanded)
    }

    /// Files being dragged over the notch: open up so the user sees the tray,
    /// but never take key focus mid-drag.
    func dragEntered() {
        guard state != .expanded else { return }
        expandedInteractively = false
        transition(to: .expanded)
    }

    /// Drag left without dropping: no mouseExited will arrive (tracking is
    /// suppressed during drag sessions), so arm the pointer-outside poll.
    func dragExited() {
        guard state == .expanded, !expandedInteractively else { return }
        scheduleCollapseIfPointerOutside()
    }

    func collapse() { transition(to: .closed) }

    /// Forced-closed policy on reconfiguration: rebuild from fresh geometry,
    /// no animation — this is what makes drift impossible.
    func displayChanged(geometry: NotchGeometry) {
        dwellTask?.cancel()
        collapseTask?.cancel()
        dismissBanner()
        epoch += 1                       // stale spring completions must not fire
        config = NotchConfiguration.current()
        self.geometry = geometry
        state = .closed
        expandedInteractively = false
        apply(geometry.panelFrame(for: .closed, config: config))
        onStateChange?(.closed)
    }

    // MARK: - Internals

    private func dwellFired() {
        guard state == .hover else { return }
        expandedInteractively = false
        transition(to: .expanded)
    }

    /// Re-check while the pointer lingers in the exit halo (edge jitter
    /// produces spurious exits, and no further mouseExited will fire once the
    /// pointer has left the window). The loop exists only in this transient
    /// expanded-with-pointer-nearby sub-state; it ends on collapse, re-entry
    /// (cancellation), or the pointer leaving the halo.
    private func scheduleCollapseIfPointerOutside() {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, let self, self.state == .expanded,
                      let geometry = self.geometry else { return }
                let halo = geometry.panelFrame(for: .expanded, config: self.config)
                    .insetBy(dx: -8, dy: -8)
                if !halo.contains(NSEvent.mouseLocation) {
                    // Never yank the panel away mid-typing (unsaved drafts);
                    // Esc / click-outside still close it deliberately.
                    if self.isPanelKey?() == true { continue }
                    self.transition(to: .closed)
                    return
                }
            }
        }
    }

    private func apply(_ frame: CGRect) {
        appliedFrame = frame
        applyPanelFrame?(frame)
    }

    private func transition(to new: NotchState) {
        guard new != state, let geometry else { return }
        let target = geometry.panelFrame(for: new, config: config)
        // Union of window truth and target: grows instantly (the new area is
        // transparent), never shrinks mid-spring, handles mixed grow/shrink
        // per axis. All frames share the same top edge and centerX, so the
        // instant resize moves no visible pixel.
        let interim = appliedFrame.union(target)
        if interim != appliedFrame { apply(interim) }

        epoch += 1
        let myEpoch = epoch
        withAnimation(Ego.Motion.notch, completionCriteria: .logicallyComplete) {
            state = new
        } completion: { [weak self] in
            guard let self, self.epoch == myEpoch, self.state == new else { return }
            if self.appliedFrame != target { self.apply(target) }   // trim the excess
        }
        onStateChange?(new)
        if new != .expanded { expandedInteractively = false }
    }
}
