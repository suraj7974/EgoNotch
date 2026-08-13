import SwiftUI

/// NotchNest-style compact Now Playing column for the Home strip: artwork
/// with the source app's icon badged on it, title/artist, a SEEKABLE
/// progress bar, and round transport controls.
struct MediaCompactView: View {
    let widget: MediaWidget

    var body: some View {
        let model = widget.controller.model
        if model.hasSession {
            // Adaptive: full → no device label → no artwork, so the column
            // never clips at narrow panel widths.
            ViewThatFits(in: .horizontal) {
                sessionRow(model, artSize: 92, showDevice: true)
                sessionRow(model, artSize: 72, showDevice: false)
                sessionRow(model, artSize: nil, showDevice: false)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .foregroundStyle(Ego.textMute)
                Text("Nothing playing")
                    .font(Ego.font(11))
                    .foregroundStyle(Ego.textMute)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Opening the panel with no known session re-asks the player.
            .onAppear { widget.controller.primeIfNeeded() }
        }
    }

    private func sessionRow(_ model: NowPlayingModel, artSize: CGFloat?,
                            showDevice: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if let artSize {
                artwork(model, size: artSize)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.track?.title ?? "")
                    .font(Ego.font(13, .bold))
                    .foregroundStyle(Ego.text)
                    .lineLimit(1)
                Text(model.track?.artist ?? "")
                    .font(Ego.font(11))
                    .foregroundStyle(Ego.textMute)
                    .lineLimit(1)
                SeekableProgressBar(model: model) { target in
                    widget.controller.seek(to: target)
                }
                .padding(.top, 2)
                HStack(spacing: 6) {
                    RoundControlButton(symbol: "backward.fill", size: 10, diameter: 28) {
                        widget.controller.send(.previousTrack)
                    }
                    RoundControlButton(symbol: model.isPlaying ? "pause.fill" : "play.fill",
                                       size: 12, diameter: 32) {
                        widget.controller.send(.togglePlayPause)
                    }
                    RoundControlButton(symbol: "forward.fill", size: 10, diameter: 28) {
                        widget.controller.send(.nextTrack)
                    }
                    Spacer(minLength: 0)
                    if showDevice {
                        Text(widget.audioOutput.deviceName)
                            .font(Ego.font(9))
                            .foregroundStyle(Ego.textMute.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 90, alignment: .trailing)
                    }
                }
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func artwork(_ model: NowPlayingModel, size: CGFloat = 92) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let artwork = model.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Ego.surface2
                        Image(systemName: "music.note")
                            .font(.system(size: 22))
                            .foregroundStyle(Ego.textMute)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.4), radius: 8, y: 3)

            if let icon = Self.appIcon(named: model.appName) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .offset(x: 5, y: 5)
                    .shadow(color: .black.opacity(0.5), radius: 3)
            }
        }
    }

    /// Icon of the source player (Spotify, Music, browser…).
    static func appIcon(named appName: String?) -> NSImage? {
        guard let appName, !appName.isEmpty else { return nil }
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.caseInsensitiveCompare(appName) == .orderedSame
        }), let url = running.bundleURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        for path in ["/Applications/\(appName).app", "/System/Applications/\(appName).app"]
        where FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return nil
    }
}

/// Round translucent control button (NotchNest style).
struct RoundControlButton: View {
    let symbol: String
    let size: CGFloat
    var diameter: CGFloat = 32
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Ego.text)
                .frame(width: diameter, height: diameter)
                .background(Color.white.opacity(hovered ? 0.22 : 0.10), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// Progress bar + mono times. Click or drag anywhere on it to seek; while
/// scrubbing the bar previews the target. The 1s tick exists only while the
/// view is on screen and playback is running.
struct SeekableProgressBar: View {
    var model: NowPlayingModel
    var onSeek: (TimeInterval) -> Void
    @State private var scrubFraction: Double?

    var body: some View {
        // ONE stable view identity: switching between TimelineView and a
        // plain bar mid-gesture cancels the drag (first scrub froze). The
        // schedule just pauses when ticks aren't needed.
        TimelineView(.animation(minimumInterval: 1,
                                paused: !model.isPlaying || scrubFraction != nil)) { _ in
            bar
        }
    }

    private var bar: some View {
        let duration = model.track?.duration ?? 0
        let liveFraction = duration > 0 ? min(model.currentElapsed / duration, 1) : 0
        let fraction = scrubFraction ?? liveFraction
        let shownElapsed = scrubFraction.map { $0 * duration } ?? model.currentElapsed

        return VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(Ego.text)
                        .frame(width: max(geo.size.width * fraction, 2))
                }
                .frame(height: 3)                          // thin visual bar…
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())                 // …generous hit area
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            scrubFraction = min(max(value.location.x / geo.size.width, 0), 1)
                        }
                        .onEnded { value in
                            guard duration > 0 else { scrubFraction = nil; return }
                            let f = min(max(value.location.x / geo.size.width, 0), 1)
                            onSeek(f * duration)
                            scrubFraction = nil
                        }
                )
            }
            .frame(height: 14)   // hit target; the capsule itself draws 3pt
            HStack {
                Text(Self.format(shownElapsed))
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
