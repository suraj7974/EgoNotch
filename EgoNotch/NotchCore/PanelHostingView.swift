import AppKit
import SwiftUI

/// Hosts the SwiftUI notch content. The panel's frame is owned exclusively by
/// NotchGeometry — `sizingOptions = []` stops SwiftUI from fighting setFrame.
final class PanelHostingView<Content: View>: NSHostingView<Content> {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onEscape: (() -> Void)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        // .activeAlways: the agent app is never the active app.
        // .inVisibleRect: AppKit re-syncs the rect on every window resize.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { onMouseEntered?() }
    override func mouseExited(with event: NSEvent) { onMouseExited?() }

    /// First click works even while another app is active — the panel never
    /// activates us (that's the point of .nonactivatingPanel).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Esc collapses the expanded panel.
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
