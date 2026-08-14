import SwiftUI

/// NotchNest-style compact Now Playing column for the Home strip: artwork
/// with the source app's icon badged on it, title/artist, a SEEKABLE
/// progress bar, and round transport controls.
struct MediaCompactView: View {
    let widget: MediaWidget

    private static let artSize: CGFloat = 100

    /// Big artwork on the left; title, artist, seek bar and transport stacked
    /// on the right. The bar and the button row are siblings in one column,
    /// so they always span exactly the same width. Every slot is fixed, so a
    /// missing cover can never shift the layout.
    var body: some View {
        let model = widget.controller.model
        HStack(alignment: .center, spacing: 14) {
            artwork(model, size: Self.artSize)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.track?.title ?? "Nothing playing")
                    .font(Ego.font(15, .bold))
                    .foregroundStyle(model.hasSession ? .white : Ego.textMute)
                    .lineLimit(1)
                Text(model.hasSession
                     ? (model.track?.artist ?? "")
                     : "Play something to see it here")
                    .font(Ego.font(12))
                    .foregroundStyle(Ego.textMute)
                    .lineLimit(1)

                HStack(spacing: 3) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 8))
                    Text(widget.audioOutput.deviceName)
                        .font(Ego.font(9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(Ego.textMute.opacity(0.75))

                Spacer(minLength: 2)

                if model.hasSession {
                    SeekableProgressBar(model: model) { target in
                        widget.controller.seek(to: target)
                    }
                }

                HStack(spacing: 8) {
                    RoundControlButton(symbol: "backward.fill", size: 11, diameter: 30) {
                        widget.controller.send(.previousTrack)
                    }
                    RoundControlButton(symbol: model.isPlaying ? "pause.fill" : "play.fill",
                                       size: 13, diameter: 34) {
                        widget.controller.send(.togglePlayPause)
                    }
                    RoundControlButton(symbol: "forward.fill", size: 11, diameter: 30) {
                        widget.controller.send(.nextTrack)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .opacity(model.hasSession ? 1 : 0.45)
            }
            .frame(height: Self.artSize)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // Opening the panel with no known session re-asks the player.
        .onAppear { widget.controller.primeIfNeeded() }
    }

    private func artwork(_ model: NowPlayingModel, size: CGFloat = 84) -> some View {
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

            // Source badge sits INSIDE the artwork, never beside the tile.
            if let icon = Self.appIcon(named: model.appName) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .shadow(color: .black.opacity(0.6), radius: 3)
                    .padding(7)
            }
        }
        .frame(width: size, height: size)
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
