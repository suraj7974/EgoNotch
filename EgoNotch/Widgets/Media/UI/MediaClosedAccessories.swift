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
            // Hard teardown on play/pause: retargeting a delayed repeatForever
            // animation is unreliable — fresh identity guarantees bars stop.
            .id(model.isPlaying)
        }
    }
}

private struct AudioBar: View {
    let delay: Double
    var playing: Bool
    @State private var up = false

    var body: some View {
        Capsule()
            .fill(Ego.text)
            .frame(width: 2.5, height: up ? 13 : 4)
            .opacity(playing ? 1 : 0.4)
            .onAppear { sync() }
            .onChange(of: playing) { sync() }
    }

    private func sync() {
        if playing {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true).delay(delay)) {
                up = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { up = false }
        }
    }
}
