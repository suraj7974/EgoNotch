import SwiftUI

/// Mini album-art thumbnail on the left of the notch while closed.
struct MediaArtThumb: View {
    var model: NowPlayingModel

    var body: some View {
        if model.hasSession {
            Group {
                if let artwork = model.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Ego.surface2
                        Image(systemName: "music.note")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Ego.textMute)
                    }
                }
            }
            .frame(width: 22, height: 22)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }
}

/// Animated cyan audio bars on the right of the notch — animate only while
/// something is actually playing (Core Animation-driven, cheap).
struct AudioBars: View {
    var model: NowPlayingModel

    var body: some View {
        if model.hasSession {
            HStack(spacing: 2.5) {
                AudioBar(delay: 0.00, playing: model.isPlaying)
                AudioBar(delay: 0.15, playing: model.isPlaying)
                AudioBar(delay: 0.30, playing: model.isPlaying)
            }
            .frame(height: 14, alignment: .center)
        }
    }
}

/// One bar, driven by the clock rather than by a `repeatForever` animation.
///
/// The old version started its animation in `onAppear`. When a track is
/// already playing at launch the bars are built before the panel window is on
/// screen, Core Animation drops that implicit animation, and nothing ever
/// restarts it — the bars sat frozen until a hover rebuilt the view. A
/// TimelineView has no start to miss: it just reads the current time, and
/// pauses outright when nothing is playing, so idle cost stays zero.
private struct AudioBar: View {
    let delay: Double
    var playing: Bool

    private static let period: Double = 0.8
    private static let minHeight: Double = 4
    private static let maxHeight: Double = 13

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !playing)) { context in
            Capsule()
                .fill(Ego.text)
                .frame(width: 2.5, height: height(at: context.date))
                .opacity(playing ? 1 : 0.4)
        }
    }

    private func height(at date: Date) -> Double {
        guard playing else { return Self.minHeight }
        let phase = (date.timeIntervalSinceReferenceDate / Self.period) + delay
        let wave = 0.5 + 0.5 * sin(phase * 2 * .pi)      // 0…1
        return Self.minHeight + (Self.maxHeight - Self.minHeight) * wave
    }
}
