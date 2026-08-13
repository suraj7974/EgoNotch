import Foundation

/// Owns the model and picks the provider: MediaRemote adapter first; if it
/// can't run on this OS build, switch to the Spotify/Music fallback once and
/// say so in the log (master rule: never silently ship a broken widget —
/// the UI also shows a FALLBACK chip via model.mode).
final class MediaController {
    let model = NowPlayingModel()

    private var adapter: MediaRemoteAdapterProvider?
    private var fallback: FallbackMediaProvider?
    private var spotify: SpotifyDirectChannel?
    private var active: (any MediaProvider)?

    func start() {
        guard active == nil else { return }
        let a = MediaRemoteAdapterProvider(model: model) { [weak self] healthy in
            if !healthy { self?.switchToFallback() }
        }
        adapter = a
        active = a
        model.mode = .mediaRemote
        a.start()
        // Spotify's official desktop connector runs permanently alongside —
        // its push events are authoritative whenever Spotify is the source.
        let s = SpotifyDirectChannel(model: model)
        spotify = s
        s.start()
    }

    func stop() {
        adapter?.stop()
        fallback?.stop()
        spotify?.stop()
        adapter = nil
        fallback = nil
        spotify = nil
        active = nil
        model.clear()
        model.mode = .none
    }

    func send(_ command: MediaCommand) {
        active?.send(command)
    }

    private func switchToFallback() {
        guard fallback == nil, active != nil else { return }   // once, and only while started
        adapter?.stop()
        adapter = nil
        // Drop the dead adapter's session — fallback events (Spotify/Music
        // only) could never update or clear it, leaving a ghost track.
        model.clear()
        NSLog("EgoNotch: MediaRemote unavailable on this macOS — using Spotify/Music fallback")
        let f = FallbackMediaProvider(model: model)
        fallback = f
        active = f
        f.start()
    }
}
