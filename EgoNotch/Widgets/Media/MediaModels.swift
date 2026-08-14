import AppKit
import Observation

/// MRMediaRemoteSendCommand codes (private API, stable for years).
enum MediaCommand: Int {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}

enum MediaProviderMode: Equatable {
    case none
    case mediaRemote
    case fallback   // AppleScript + distributed notifications (Spotify/Music only)
}

struct NowPlayingTrack: Equatable {
    var title = ""
    var artist = ""
    var album = ""
    var duration: TimeInterval = 0
}

/// Single observable snapshot of playback state, fed by whichever provider is
/// active. Elapsed time is anchored (value + wall-clock date + rate) so the UI
/// can derive live progress without the provider ticking.
@Observable
final class NowPlayingModel {
    /// A genuine title change announces itself so the notch can show its
    /// transient "now playing" peek.
    var track: NowPlayingTrack? {
        didSet {
            guard let title = track?.title, !title.isEmpty,
                  title != oldValue?.title else { return }
            NotificationCenter.default.post(
                name: .egoSongChanged, object: nil,
                userInfo: ["title": title, "artist": track?.artist ?? ""])
        }
    }
    var artwork: NSImage?
    var isPlaying = false
    var appName: String?
    var mode: MediaProviderMode = .none
    /// Automation permission was denied — transport controls can't work.
    var controlsDenied = false

    var anchoredElapsed: TimeInterval = 0
    var anchorDate = Date()
    var rate: Double = 1
    /// After a user seek, incoming (stale) elapsed snapshots are ignored
    /// until this instant so fast scrubs never snap back.
    var suppressElapsedUntil: Date?

    var elapsedSuppressed: Bool {
        suppressElapsedUntil.map { Date() < $0 } ?? false
    }

    var hasSession: Bool {
        guard let track else { return false }
        return !(track.title.isEmpty && track.artist.isEmpty)
    }

    var currentElapsed: TimeInterval {
        guard let track else { return 0 }
        let raw = isPlaying
            ? anchoredElapsed + Date().timeIntervalSince(anchorDate) * rate
            : anchoredElapsed
        let clamped = max(raw, 0)
        return track.duration > 0 ? min(clamped, track.duration) : clamped
    }

    /// Freeze the advancing elapsed into the anchor (call before rate/pause changes).
    func reanchorElapsed() {
        anchoredElapsed = currentElapsed
        anchorDate = Date()
    }

    func clear() {
        track = nil
        artwork = nil
        isPlaying = false
        appName = nil
        anchoredElapsed = 0
        anchorDate = Date()
        rate = 1
        controlsDenied = false
    }
}
