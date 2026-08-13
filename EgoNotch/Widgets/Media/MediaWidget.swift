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

    func makeExpandedView() -> AnyView {
        AnyView(MediaTileView(widget: self))
    }
}
