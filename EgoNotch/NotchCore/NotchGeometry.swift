import AppKit

/// Pure geometry: where the notch is and what the panel frame should be for
/// each state. All rects are in AppKit global screen coordinates (origin at
/// the bottom-left of the primary display, +y up) — the same space that
/// `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` report in.
struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let notchRect: CGRect
    let isPhysicalNotch: Bool

    static func resolve(for screen: NSScreen, config: NotchConfiguration) -> NotchGeometry {
        let f = screen.frame
        // Gate on safeAreaInsets: a scaled display mode can hide the notch
        // even on the built-in panel, and then the auxiliary areas lie fallow.
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let h = screen.safeAreaInsets.top
            let rect = CGRect(x: left.maxX,
                              y: f.maxY - h,
                              width: right.minX - left.maxX,
                              height: h)
            return NotchGeometry(screenFrame: f, notchRect: rect, isPhysicalNotch: true)
        }
        // Virtual notch: external display, or a mode without the physical notch.
        var h = f.maxY - screen.visibleFrame.maxY   // menu bar height
        if h <= 1 { h = config.virtualNotchHeight } // menu-bar auto-hide reports 0
        let w = config.virtualNotchWidth
        return NotchGeometry(
            screenFrame: f,
            notchRect: CGRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h),
            isPhysicalNotch: false
        )
    }

    /// The size of the VISIBLE chrome for a state (what NotchRootView draws).
    func chromeSize(for state: NotchState, config: NotchConfiguration) -> CGSize {
        switch state {
        case .closed:
            return CGSize(width: notchRect.width + 2 * config.wingWidth,
                          height: notchRect.height + config.closedExtraHeight)
        case .peek:
            let closed = chromeSize(for: .closed, config: config)
            return CGSize(width: closed.width + config.peekExtraWidth,
                          height: closed.height + config.peekExtraHeight)
        case .hover:
            let closed = chromeSize(for: .closed, config: config)
            return CGSize(width: closed.width + 2 * config.hoverOutset,
                          height: closed.height + config.hoverDrop)
        case .expanded:
            let closed = chromeSize(for: .closed, config: config)
            return CGSize(width: max(config.expandedSize.width, closed.width),
                          height: notchRect.height + config.expandedSize.height)
        case .assistant:
            let closed = chromeSize(for: .closed, config: config)
            return CGSize(width: closed.width + config.assistantExtraWidth,
                          height: closed.height + config.assistantExtraHeight)
        }
    }

    /// The window frame: chrome plus transparent margins (glow / drop shadow).
    /// Every state's frame shares the same top edge and center X, so an
    /// instant window resize never moves a visible pixel (the SwiftUI content
    /// is anchored top-center).
    func panelFrame(for state: NotchState, config: NotchConfiguration) -> CGRect {
        let top = screenFrame.maxY
        let cx = notchRect.midX
        let chrome = chromeSize(for: state, config: config)
        let margin: CGFloat = switch state {
        case .closed, .peek: 0
        case .hover: config.hoverGlowMargin
        case .expanded: config.expandedShadowMargin
        case .assistant: 0
        }
        let w = chrome.width + 2 * margin
        let h = chrome.height + margin        // margin on sides/bottom; top edge stays put
        let frame = CGRect(x: cx - w / 2, y: top - h, width: w, height: h)
        return state == .expanded ? frame.intersection(screenFrame) : frame
    }
}
