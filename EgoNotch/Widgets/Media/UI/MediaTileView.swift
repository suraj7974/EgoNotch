import SwiftUI

/// Expanded Now Playing tile: artwork, track info, progress, transport,
/// output device + AirPods battery footer.
struct MediaTileView: View {
    let widget: MediaWidget
    @State private var battery: AirPodsBatteryInfo?

    var body: some View {
        let model = widget.controller.model
        VStack(alignment: .leading, spacing: 10) {
            if model.hasSession {
                sessionRow(model)
            } else {
                noSignal(model)
            }
            footer(model)
        }
        .onAppear { battery = AirPodsBattery.read() }
        .onChange(of: widget.audioOutput.deviceName) {
            battery = AirPodsBattery.read()
        }
    }

    // MARK: - Now playing

    private func sessionRow(_ model: NowPlayingModel) -> some View {
        HStack(spacing: 12) {
            artwork(model)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.track?.title ?? "")
                    .font(Ego.font(13, .semibold))
                    .foregroundStyle(Ego.text)
                    .lineLimit(1)
                Text(model.track?.artist ?? "")
                    .font(Ego.font(11))
                    .foregroundStyle(Ego.textMute)
                    .lineLimit(1)
                ProgressRow(model: model)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            transport
        }
    }

    private func artwork(_ model: NowPlayingModel) -> some View {
        Group {
            if let artwork = model.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Ego.surface2
                    Image(systemName: "music.note")
                        .font(.system(size: 18))
                        .foregroundStyle(Ego.textMute)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Ego.border, lineWidth: 1))
    }

    private var transport: some View {
        HStack(spacing: 12) {
            transportButton("backward.fill", size: 12) {
                widget.controller.send(.previousTrack)
            }
            transportButton(widget.controller.model.isPlaying ? "pause.fill" : "play.fill",
                            size: 18) {
                widget.controller.send(.togglePlayPause)
            }
            transportButton("forward.fill", size: 12) {
                widget.controller.send(.nextTrack)
            }
        }
        .opacity(widget.controller.model.controlsDenied ? 0.4 : 1)
    }

    private func transportButton(_ symbol: String, size: CGFloat,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Ego.text)
                .frame(width: max(size + 12, 26), height: max(size + 12, 26))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty / footer

    private func noSignal(_ model: NowPlayingModel) -> some View {
        HStack(spacing: 10) {
            Chip(text: "Nothing playing", variant: .neutral)
            Text(model.mode == .fallback
                 ? "Play something in Spotify or Music"
                 : "Play something — Spotify, Music, or a browser")
                .font(Ego.font(11))
                .foregroundStyle(Ego.textMute)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
    }

    private func footer(_ model: NowPlayingModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2")
                .font(.system(size: 9))
                .foregroundStyle(Ego.textMute)
            Text(widget.audioOutput.deviceName)
                .font(Ego.font(10))
                .foregroundStyle(Ego.textMute)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let battery {
                batteryChips(battery)
            }
            if let app = model.appName {
                Chip(text: app, variant: .accent)
            }
            if model.mode == .fallback {
                Chip(text: "Fallback", variant: .loss)
            }
            if model.controlsDenied {
                Chip(text: "No automation", variant: .loss)
                    .help("Enable EgoNotch under System Settings > Privacy & Security > Automation")
            }
        }
    }

    @ViewBuilder
    private func batteryChips(_ info: AirPodsBatteryInfo) -> some View {
        if let single = info.single {
            Chip(text: "\(single)%", variant: single <= 20 ? .loss : .win)
        }
        if let left = info.left {
            Chip(text: "L \(left)%", variant: left <= 20 ? .loss : .win)
        }
        if let right = info.right {
            Chip(text: "R \(right)%", variant: right <= 20 ? .loss : .win)
        }
        if let c = info.caseLevel {
            Chip(text: "Case \(c)%", variant: .neutral)
        }
    }
}

/// Thin progress bar + mono times. The 1s tick exists ONLY while this view is
/// on screen (expanded) and playback is running — the low-power rule.
private struct ProgressRow: View {
    var model: NowPlayingModel

    var body: some View {
        if model.isPlaying {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                bar
            }
        } else {
            bar
        }
    }

    private var bar: some View {
        let duration = model.track?.duration ?? 0
        let elapsed = model.currentElapsed
        let fraction = duration > 0 ? min(elapsed / duration, 1) : 0
        return VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(Ego.text)
                        .frame(width: max(geo.size.width * fraction, 2))
                }
            }
            .frame(height: 3)
            HStack {
                Text(Self.format(elapsed))
                Spacer()
                Text(duration > 0 ? Self.format(duration) : "--:--")
            }
            .font(Ego.font(9))
            .monospacedDigit()
            .foregroundStyle(Ego.textMute)
        }
    }

    private static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
