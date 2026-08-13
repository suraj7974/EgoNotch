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

    /// Every state's frame shares the same top edge and center X, so an
    /// instant window resize never moves a visible pixel (the SwiftUI content
    /// is anchored top-center).
    func panelFrame(for state: NotchState, config: NotchConfiguration) -> CGRect {
        let top = screenFrame.maxY
        let cx = notchRect.midX
        switch state {
        case .closed:
            let w = notchRect.width + 2 * config.wingWidth
            return CGRect(x: cx - w / 2, y: top - notchRect.height,
                          width: w, height: notchRect.height)
        case .hover:
            // Glow margin: extra transparent window on the sides/bottom so
            // the 8pt cyan shadow isn't clipped (top edge stays put).
            let w = notchRect.width + 2 * config.wingWidth
                + 2 * (config.hoverOutset + config.hoverGlowMargin)
            let h = notchRect.height + config.hoverDrop + config.hoverGlowMargin
            return CGRect(x: cx - w / 2, y: top - h, width: w, height: h)
        case .expanded:
            let w = max(config.expandedSize.width, notchRect.width + 2 * config.wingWidth)
            let h = notchRect.height + config.expandedSize.height
            return CGRect(x: cx - w / 2, y: top - h, width: w, height: h)
                .intersection(screenFrame)   // clamp on small external displays
        }
    }
}
