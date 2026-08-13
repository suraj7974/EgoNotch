import AppKit

/// Spotify's official desktop integration for macOS: the app broadcasts every
/// playback change over DistributedNotificationCenter and exposes AppleScript
/// control + artwork URLs (both documented by Spotify). This channel runs
/// permanently alongside the MediaRemote adapter and is treated as the
/// AUTHORITATIVE source whenever Spotify is what's playing — its push events
/// arrive instantly, which fixes pause/stop states MediaRemote can miss.
///
/// Artwork: MediaRemote artwork wins when present; otherwise the official
/// `artwork url` is fetched once per track (user-approved network exception)
/// via AppleScript — denied Automation permission just means no artwork.
final class SpotifyDirectChannel: NSObject {
    private let model: NowPlayingModel
    private var artworkTask: Task<Void, Never>?
    private var artworkTrackKey: String?

    init(model: NowPlayingModel) {
        self.model = model
        super.init()
    }

    func start() {
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(playbackChanged(_:)),
            name: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil)
    }

    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
        artworkTask?.cancel()
        artworkTask = nil
        artworkTrackKey = nil
    }

    @objc private func playbackChanged(_ note: Notification) {
        guard let info = note.userInfo else { return }
        let state = info["Player State"] as? String

        if state == "Stopped" {
            if model.appName == "Spotify" || model.appName == nil {
                model.clear()
            }
            return
        }

        var track = NowPlayingTrack()
        track.title = info["Name"] as? String ?? ""
        track.artist = info["Artist"] as? String ?? ""
        track.album = info["Album"] as? String ?? ""
        track.duration = ((info["Duration"] as? NSNumber)?.doubleValue ?? 0) / 1000

        let trackChanged = model.track != track
        if trackChanged {
            model.track = track
            model.artwork = nil
        }
        if let position = (info["Playback Position"] as? NSNumber)?.doubleValue,
           !model.elapsedSuppressed {
            model.anchoredElapsed = position
            model.anchorDate = Date()
        }
        model.rate = 1
        model.isPlaying = state == "Playing"
        model.appName = "Spotify"

        if trackChanged || model.artwork == nil {
            fetchArtworkIfNeeded(for: track)
        }
    }

    /// Official seek: `set player position` (instant, authoritative).
    func seek(to seconds: TimeInterval) {
        let source = "tell application \"Spotify\" to set player position to \(Int(seconds))"
        Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }

    // MARK: - Artwork (official `artwork url`, cached per track)

    /// Public entry point for priming (MediaController) — same cache rules.
    func fetchArtwork(for track: NowPlayingTrack) {
        fetchArtworkIfNeeded(for: track)
    }

    private func fetchArtworkIfNeeded(for track: NowPlayingTrack) {
        let key = "\(track.title)|\(track.artist)"
        guard key != artworkTrackKey else { return }
        artworkTrackKey = key

        // Give MediaRemote a moment to supply artwork first; only then fetch.
        artworkTask?.cancel()
        artworkTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self,
                  self.model.artwork == nil,
                  self.model.track?.title == track.title else { return }

            // AppleScript off the main actor — the first-use Automation
            // prompt blocks inside executeAndReturnError.
            let urlString = await Task.detached(priority: .utility) {
                Self.artworkURLViaAppleScript()
            }.value
            guard let urlString,
                  let url = URL(string: urlString), url.scheme == "https" else { return }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            guard !Task.isCancelled,
                  self.model.track?.title == track.title,
                  self.model.artwork == nil else { return }
            self.model.artwork = image
        }
    }

    nonisolated private static func artworkURLViaAppleScript() -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(
            source: "tell application \"Spotify\" to artwork url of current track")?
            .executeAndReturnError(&error)
        if error != nil { return nil }   // automation denied / Spotify gone — degrade
        return result?.stringValue
    }
}
