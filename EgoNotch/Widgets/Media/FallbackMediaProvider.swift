import AppKit

/// Fallback when MediaRemote is unavailable. Spotify and Apple Music
/// broadcast every playback change over DistributedNotificationCenter
/// (event-driven, no polling); transport controls go through AppleScript.
/// First control use triggers the macOS Automation prompt — if denied,
/// metadata keeps working and controls become no-ops (graceful degrade).
///
/// Limitations vs MediaRemote: only Spotify/Music (no browsers), no artwork,
/// state appears on the first playback event after activation.
final class FallbackMediaProvider: NSObject, MediaProvider {
    private let model: NowPlayingModel
    private var sourceApp: String?

    init(model: NowPlayingModel) {
        self.model = model
        super.init()
    }

    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(spotifyChanged(_:)),
                        name: Notification.Name("com.spotify.client.PlaybackStateChanged"),
                        object: nil)
        dnc.addObserver(self, selector: #selector(musicChanged(_:)),
                        name: Notification.Name("com.apple.Music.playerInfo"),
                        object: nil)
        model.mode = .fallback
    }

    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func seek(to seconds: TimeInterval) {
        guard let app = sourceApp else { return }
        let source = "tell application \"\(app)\" to set player position to \(Int(seconds))"
        Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }

    func send(_ command: MediaCommand) {
        guard let app = sourceApp else { return }
        let verb: String
        switch command {
        case .play, .pause, .togglePlayPause: verb = "playpause"
        case .nextTrack: verb = "next track"
        case .previousTrack: verb = "previous track"
        }
        let source = "tell application \"\(app)\" to \(verb)"
        // Off the main actor: the first-use Automation prompt (and target-app
        // launch) block inside executeAndReturnError and would freeze the UI.
        Task.detached(priority: .userInitiated) { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if error != nil {
                NSLog("EgoNotch: AppleScript control failed: \(String(describing: error))")
            }
            let errNum = error?[NSAppleScript.errorNumber] as? Int
            await MainActor.run {
                guard let self else { return }
                if errNum == -1743 {                   // errAEEventNotPermitted
                    self.model.controlsDenied = true
                } else if errNum == nil {
                    self.model.controlsDenied = false  // self-heal on re-grant
                }
            }
        }
    }

    // MARK: - Notifications

    @objc private func spotifyChanged(_ note: Notification) {
        guard let info = note.userInfo else { return }
        sourceApp = "Spotify"
        apply(app: "Spotify",
              state: info["Player State"] as? String,
              title: info["Name"] as? String,
              artist: info["Artist"] as? String,
              album: info["Album"] as? String,
              durationMS: (info["Duration"] as? NSNumber)?.doubleValue,
              positionSec: (info["Playback Position"] as? NSNumber)?.doubleValue
                  ?? (info["Playback Position"] as? String).flatMap(Double.init))
    }

    @objc private func musicChanged(_ note: Notification) {
        guard let info = note.userInfo else { return }
        sourceApp = "Music"
        apply(app: "Music",
              state: info["Player State"] as? String,
              title: info["Name"] as? String,
              artist: info["Artist"] as? String,
              album: info["Album"] as? String,
              durationMS: (info["Total Time"] as? NSNumber)?.doubleValue,
              positionSec: nil)
    }

    private func apply(app: String, state: String?, title: String?, artist: String?,
                       album: String?, durationMS: Double?, positionSec: Double?) {
        if state == "Stopped" {
            model.clear()
            model.mode = .fallback
            return
        }
        var track = NowPlayingTrack()
        track.title = title ?? ""
        track.artist = artist ?? ""
        track.album = album ?? ""
        track.duration = (durationMS ?? 0) / 1000
        // Never rebase the anchor without also fixing anchoredElapsed — Music
        // sends no position, so a bare anchorDate reset would zero progress
        // on every pause/resume.
        if model.track != track {
            model.track = track
            model.artwork = nil        // no artwork channel in fallback mode
            model.anchoredElapsed = positionSec ?? 0
            model.anchorDate = Date()
        } else if let positionSec {
            model.anchoredElapsed = positionSec
            model.anchorDate = Date()
        } else {
            model.reanchorElapsed()    // freeze live elapsed under the OLD playing state
        }
        model.rate = 1
        model.isPlaying = state == "Playing"
        model.appName = app
        model.mode = .fallback
    }
}
