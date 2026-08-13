import AppKit
import SwiftUI
import Observation

/// The little volume/brightness readout that replaces the macOS overlay:
/// a slim black pill just below the notch, fading out after 1.4s.
@Observable
final class HUDState {
    var icon = "speaker.wave.2.fill"
    var fraction: Double = 0
    var visible = false
}

final class HUDPanelController {
    private let state = HUDState()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    private static let size = CGSize(width: 210, height: 44)

    func show(icon: String, fraction: Double) {
        ensurePanel()
        state.icon = icon
        state.fraction = max(0, min(1, fraction))
        withAnimation(.easeOut(duration: 0.15)) { state.visible = true }
        panel?.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeIn(duration: 0.25)) { self.state.visible = false }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
        }
    }

    func teardown() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func ensurePanel() {
        guard panel == nil else {
            positionPanel()
            return
        }
        let p = NSPanel(contentRect: CGRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: HUDView(state: state))
        hosting.sizingOptions = []
        p.contentView = hosting
        panel = p
        positionPanel()
    }

    private func positionPanel() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let f = screen.frame
        let topInset = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top
            : (f.maxY - screen.visibleFrame.maxY)
        let origin = CGPoint(x: f.midX - Self.size.width / 2,
                             y: f.maxY - topInset - 10 - Self.size.height)
        panel?.setFrame(CGRect(origin: origin, size: Self.size), display: true)
    }
}

private struct HUDView: View {
    var state: HUDState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(Color.white)
                        .frame(width: max(geo.size.width * state.fraction, 3))
                }
            }
            .frame(height: 5)
            .animation(.easeOut(duration: 0.12), value: state.fraction)
        }
        .padding(.horizontal, 14)
        .frame(width: 210, height: 36)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 13))
        .opacity(state.visible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
