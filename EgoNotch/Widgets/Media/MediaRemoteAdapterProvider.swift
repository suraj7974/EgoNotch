import AppKit

/// Primary provider. Spawns the embedded adapter dylib inside /usr/bin/perl
/// (an Apple platform binary, which passes the macOS 15.4+ MediaRemote
/// entitlement gate) and consumes its JSON-lines stream. One long-lived child
/// process; commands run as short-lived one-shots. No polling anywhere.
final class MediaRemoteAdapterProvider: MediaProvider {
    private let model: NowPlayingModel
    /// Reports provider health; MediaController switches to the fallback on false.
    private let onHealthChange: (Bool) -> Void
    /// MediaRemote knows an app is playing but has no track info for it —
    /// the cold-start case, where only the player's own API can tell us.
    var onSessionWithoutTrack: (() -> Void)?
    /// The app MediaRemote currently calls "now playing".
    private var adapterApp: String?

    /// With two players open, MediaRemote often names the idle one — a paused
    /// Music library while Spotify is actually singing — and its stale info
    /// would replace the live session and send transport commands to the wrong
    /// app. While a DIFFERENT source is playing, its updates are ignored.
    private var describesAnIdleOtherApp: Bool {
        guard let adapterApp, let showing = model.appName, showing != adapterApp else { return false }
        return model.isPlaying
    }

    private var process: Process?
    private var readTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var restartCount = 0
    private var receivedReady = false
    private var stopped = true
    /// True when the model's elapsed anchor is an adapter timestamp captured
    /// during live playback — such an anchor already encodes (now − T) drift
    /// and must survive the next false→true isPlaying flip un-reanchored.
    private var anchorTracksLivePlayback = false

    private static let maxRestarts = 3

    private static var dylibURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("EgoNotchMediaAdapter.dylib")
    }

    private static let perlBootstrap =
        #"use DynaLoader; DynaLoader::dl_load_file($ENV{EGO_MRA_LIB}) or die "load failed"; sleep;"#

    init(model: NowPlayingModel, onHealthChange: @escaping (Bool) -> Void) {
        self.model = model
        self.onHealthChange = onHealthChange
    }

    func start() {
        guard stopped else { return }
        stopped = false
        restartCount = 0
        launch()
    }

    func stop() {
        stopped = true
        readTask?.cancel()
        readTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        process?.terminate()
        process = nil
    }

    func send(_ command: MediaCommand) {
        runOneShot(["EGO_MRA_CMD": String(command.rawValue)])
    }

    func seek(to seconds: TimeInterval) {
        runOneShot(["EGO_MRA_SEEK": String(seconds)])
    }

    private func runOneShot(_ extraEnv: [String: String]) {
        guard let lib = Self.dylibURL?.path else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.perlBootstrap]
        var env = ["EGO_MRA_MODE": "command", "EGO_MRA_LIB": lib]
        env.merge(extraEnv) { _, new in new }
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    // MARK: - Stream child

    private func launch() {
        guard !stopped else { return }
        guard let lib = Self.dylibURL?.path, FileManager.default.fileExists(atPath: lib) else {
            NSLog("EgoNotch: media adapter dylib missing")
            onHealthChange(false)
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.perlBootstrap]
        p.environment = ["EGO_MRA_MODE": "stream", "EGO_MRA_LIB": lib]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            NSLog("EgoNotch: failed to spawn media adapter: \(error)")
            onHealthChange(false)
            return
        }
        process = p
        receivedReady = false

        let handle = pipe.fileHandleForReading
        readTask = Task { [weak self] in
            do {
                for try await line in handle.bytes.lines {
                    guard !Task.isCancelled else { return }
                    self?.handle(line: line)
                }
            } catch {}
            self?.streamEnded()
        }

        // Watchdog: a healthy adapter prints "ready" within moments of launch.
        // Cancel the previous launch's watchdog first — a stale one would kill
        // the healthy restarted child and force permanent fallback.
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, !self.stopped else { return }
            if !self.receivedReady {
                NSLog("EgoNotch: media adapter never became ready")
                self.stop()
                self.stopped = false   // stopped by us, not by deactivate
                self.onHealthChange(false)
            }
        }
    }

    private func streamEnded() {
        guard !stopped else { return }
        process = nil
        restartCount += 1
        if restartCount > Self.maxRestarts {
            NSLog("EgoNotch: media adapter crashed \(restartCount - 1) times — giving up")
            onHealthChange(false)
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !self.stopped else { return }
            self.launch()
        }
    }

    // MARK: - Message handling

    private func handle(line: String) {
        guard let data = line.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = msg["type"] as? String else { return }

        switch type {
        case "ready":
            receivedReady = true
            restartCount = 0
            onHealthChange(true)

        case "now_playing":
            if describesAnIdleOtherApp { return }
            let hasInfo = (msg["hasInfo"] as? Bool) ?? ((msg["hasInfo"] as? NSNumber)?.boolValue ?? false)
            guard hasInfo else {
                model.clear()
                return
            }
            var track = NowPlayingTrack()
            track.title = msg["title"] as? String ?? ""
            track.artist = msg["artist"] as? String ?? ""
            track.album = msg["album"] as? String ?? ""
            track.duration = (msg["duration"] as? NSNumber)?.doubleValue ?? 0
            if model.track != track { model.track = track }

            if let elapsed = (msg["elapsed"] as? NSNumber)?.doubleValue,
               !model.elapsedSuppressed {
                model.anchoredElapsed = elapsed
                let ts = (msg["timestamp"] as? NSNumber)?.doubleValue
                model.anchorDate = ts.map { Date(timeIntervalSince1970: $0) } ?? Date()
                // Raw rate BEFORE the 0→1 mapping: a paused snapshot's frozen
                // elapsed must not be extrapolated across the next resume.
                let rawRate = (msg["rate"] as? NSNumber)?.doubleValue ?? 0
                anchorTracksLivePlayback = ts != nil && rawRate > 0
            }
            if let rate = (msg["rate"] as? NSNumber)?.doubleValue {
                model.rate = rate == 0 ? 1 : rate
            }
            if let b64 = msg["artworkB64"] as? String,
               let artData = Data(base64Encoded: b64),
               let image = NSImage(data: artData) {
                model.artwork = image
            } else if msg["artworkUnchanged"] == nil {
                model.artwork = nil        // artless track — drop the stale art
            }
            model.mode = .mediaRemote

        case "playing":
            let playing = (msg["playing"] as? NSNumber)?.boolValue ?? false
            if !playing, describesAnIdleOtherApp { return }
            if playing != model.isPlaying {
                if playing && anchorTracksLivePlayback {
                    // Anchor means "elapsed was E at time T while playing" —
                    // keep it so currentElapsed applies the (now − T) drift
                    // (cold start / adapter restart mid-playback).
                } else {
                    model.reanchorElapsed()
                }
                model.isPlaying = playing
                anchorTracksLivePlayback = false
            }
            if playing, model.track == nil { onSessionWithoutTrack?() }

        case "app":
            let app = msg["app"] as? String ?? ""
            adapterApp = app.isEmpty ? nil : app
            if describesAnIdleOtherApp { return }
            model.appName = adapterApp
            if !app.isEmpty, model.track == nil { onSessionWithoutTrack?() }

        case "error":
            NSLog("EgoNotch: media adapter error: \(msg["message"] as? String ?? "?")")
            onHealthChange(false)

        default:
            break
        }
    }
}
