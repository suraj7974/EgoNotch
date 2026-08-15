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
    private var priming = false

    func start() {
        guard active == nil else { return }
        let a = MediaRemoteAdapterProvider(model: model) { [weak self] healthy in
            if !healthy { self?.switchToFallback() }
        }
        // "Something is playing but I don't know what" → ask the player.
        a.onSessionWithoutTrack = { [weak self] in self?.primeIfNeeded() }
        adapter = a
        active = a
        model.mode = .mediaRemote
        a.start()
        // Spotify's official desktop connector runs permanently alongside —
        // its push events are authoritative whenever Spotify is the source.
        let s = SpotifyDirectChannel(model: model)
        spotify = s
        s.start()
        primeIfNeeded()   // a song already playing shows up immediately
    }

    /// Ask the running player directly when we have no session yet — called
    /// at launch, whenever the panel opens, and whenever MediaRemote tells us
    /// something is playing but won't say what.
    ///
    /// MediaRemote is notification-only: for a song that started before we
    /// launched it reports the app and the play state, but its info dictionary
    /// stays empty until the next track change. The player's own AppleScript
    /// is the only way to recover the title, so a failed attempt is retried
    /// rather than left as "Nothing playing".
    func primeIfNeeded(retries: Int = 3) {
        MediaPrimer.trace("primeIfNeeded(retries:\(retries)) hasSession=\(model.hasSession) priming=\(priming) active=\(active != nil)")
        guard !model.hasSession, !priming, active != nil else { return }
        priming = true
        Task { [weak self] in
            let preferred = self?.model.appName
            let snapshot = await Task.detached(priority: .userInitiated) {
                MediaPrimer.snapshot(preferring: preferred)
            }.value
            guard let self else { return }
            self.priming = false
            guard let snapshot, !self.model.hasSession else {
                // Spotify can be slow to answer right after launch; try again
                // before giving up on a session we know exists.
                if snapshot == nil, retries > 0, !self.model.hasSession {
                    try? await Task.sleep(for: .seconds(1.5))
                    self.primeIfNeeded(retries: retries - 1)
                }
                return
            }

            var track = NowPlayingTrack()
            track.title = snapshot.title
            track.artist = snapshot.artist
            track.album = snapshot.album
            track.duration = snapshot.duration
            self.model.track = track
            self.model.anchoredElapsed = snapshot.position
            self.model.anchorDate = Date()
            self.model.rate = 1
            self.model.isPlaying = snapshot.isPlaying
            self.model.appName = snapshot.app
            if snapshot.app == "Spotify" {
                self.spotify?.fetchArtwork(for: track)
            }
        }
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

    /// Commands go to the app we're SHOWING, not to whatever macOS considers
    /// the now-playing app — with Spotify and Music both open those differ,
    /// and the buttons appeared dead because they drove the other player.
    func send(_ command: MediaCommand) {
        if model.appName == "Spotify", let spotify {
            spotify.send(command)
            // Spotify's push notification confirms the real state moments
            // later; this just keeps the button from feeling laggy.
            if command == .togglePlayPause { model.isPlaying.toggle() }
        } else {
            active?.send(command)
        }
    }

    /// Seek to an absolute position. Spotify gets its official channel
    /// (instant); everything else goes through the active provider.
    func seek(to seconds: TimeInterval) {
        // Optimistic local update so the bar doesn't snap back while the
        // command round-trips; stale snapshots are suppressed briefly so
        // rapid scrubs stick.
        model.anchoredElapsed = seconds
        model.anchorDate = Date()
        model.suppressElapsedUntil = Date().addingTimeInterval(1.5)
        if model.appName == "Spotify", let spotify {
            spotify.seek(to: seconds)
        } else {
            active?.seek(to: seconds)
        }
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
