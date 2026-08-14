import SwiftUI

/// Phase 2 — Now Playing. MediaRemote adapter primary, Spotify/Music
/// fallback; closed accessories on both notch edges; transport controls,
/// progress, output device and AirPods battery in the expanded tile.
final class MediaWidget: NotchWidget {
    let id = "media"
    let displayName = "Now Playing"
    let icon = "waveform"
    let tileSize: WidgetTileSize = .wide

    let controller = MediaController()
    let audioOutput = AudioOutputMonitor()
    private var active = false

    /// Music owns the closed wings whenever a session exists — art on the
    /// left, visualizer on the right, nothing else competing.
    var wantsExclusiveClosedStrip: Bool { controller.model.hasSession }

    /// Big artwork + title/seek/transport needs more room than a plain tile.
    var compactMinWidth: CGFloat? { 300 }

    func activate() {
        guard !active else { return }
        active = true
        controller.start()
        audioOutput.start()
    }

    func deactivate() {
        guard active else { return }
        active = false
        controller.stop()
        audioOutput.stop()
    }

    func makeClosedAccessory(for edge: NotchEdge) -> AnyView? {
        switch edge {
        case .leading: AnyView(MediaArtThumb(model: controller.model))
        case .trailing: AnyView(AudioBars(model: controller.model))
        }
    }

    func makeCompactView() -> AnyView? {
        AnyView(MediaCompactView(widget: self))
    }
}
