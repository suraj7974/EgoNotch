import AppKit

/// Instant "what's playing right now" via the player's own AppleScript API.
///
/// MediaRemote only pushes NOTIFICATIONS, so a session that started before
/// EgoNotch launched stays invisible until the next play/pause/track change.
/// Priming asks the running player directly, so opening the app (or the
/// panel) mid-song shows the track immediately.
///
/// Never launches anything: the app must already be running.
enum MediaPrimer {
    struct Snapshot: Sendable {
        var app: String
        var title: String
        var artist: String
        var album: String
        var duration: TimeInterval
        var position: TimeInterval
        var isPlaying: Bool
    }

    /// Set when macOS refused the Apple event (-1743): the user denied the
    /// Automation prompt. Nothing else can recover the title of a song that
    /// started before we launched, so this is worth surfacing.
    ///
    /// Note: permission is NOT probed up front. `AEDeterminePermissionToAutomateTarget`
    /// pings the target app and blocks when it's slow to answer — even with
    /// prompting disabled — which hung priming forever. The event itself,
    /// inside a killable subprocess, is the check.
    nonisolated(unsafe) private(set) static var automationDenied = false

    /// EGO_DEBUG_MEDIA=1 writes a trace next to the app's other data — the
    /// only practical way to see what a background agent's Apple events did.
    nonisolated static func trace(_ message: String) {
        guard ProcessInfo.processInfo.environment["EGO_DEBUG_MEDIA"] != nil else { return }
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EgoNotch/media.log")
        let line = "\(Date()) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    /// Whatever is really playing wins.
    ///
    /// Both players are often open at once, and MediaRemote happily names an
    /// idle one as "now playing" — a paused Music library while Spotify is
    /// actually singing. So: ask every running player, and prefer the one
    /// that says it's playing over the one that merely has a track loaded.
    nonisolated static func snapshot(preferring preferred: String? = nil) -> Snapshot? {
        trace("snapshot(preferring: \(preferred ?? "-")) spotify=\(isRunning("com.spotify.client")) music=\(isRunning("com.apple.Music"))")
        var found: [Snapshot] = []
        if isRunning("com.spotify.client"),
           let s = query(app: "Spotify", durationInMilliseconds: true) {
            if s.isPlaying { return s }        // settled — don't wait on the other
            found.append(s)
        }
        if isRunning("com.apple.Music"),
           let s = query(app: "Music", durationInMilliseconds: false) {
            if s.isPlaying { return s }
            found.append(s)
        }
        return found.first(where: \.isPlaying)
            ?? found.first { $0.app == preferred }
            ?? found.first
    }

    nonisolated private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// One round-trip for the whole state; returns nil when nothing is
    /// loaded, or when Automation permission is denied (graceful).
    nonisolated private static func query(app: String,
                                          durationInMilliseconds: Bool) -> Snapshot? {
        // Two things this script has to get right, both of which it used to
        // get wrong — silently, because the failure never surfaced:
        //   • separator is `linefeed`; AppleScript has no "\\n" escape;
        //   • no variable may be named `st`, which AppleScript reads as the
        //     ordinal suffix in "1st" and rejects as a syntax error.
        let source = """
        tell application "\(app)"
            set playState to player state as string
            set theTrack to current track
            set theTitle to name of theTrack
            set theArtist to artist of theTrack
            set theAlbum to album of theTrack
            set theDuration to duration of theTrack
            set thePosition to player position
            return playState & linefeed & theTitle & linefeed & theArtist & linefeed ¬
                & theAlbum & linefeed & theDuration & linefeed & thePosition
        end tell
        """
        // Run through `osascript` rather than NSAppleScript: NSAppleScript is
        // main-thread-only in practice (it fails quietly on a background
        // queue, which is exactly where priming runs), and a subprocess can be
        // killed if the player stops answering — an Apple event otherwise
        // blocks for the full 60s timeout.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        guard (try? process.run()) != nil else { return nil }

        let deadline = Date().addingTimeInterval(2.5)
        while process.isRunning, Date() < deadline { usleep(50_000) }
        if process.isRunning {
            process.terminate()
            trace("osascript(\(app)) timed out — consent dialog pending?")
            NSLog("EgoNotch: \(app) did not answer the now-playing query in time")
            return nil
        }

        let outputData = out.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: err.fileHandleForReading.readDataToEndOfFile(),
                               encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            trace("osascript(\(app)) failed status=\(process.terminationStatus) err=\(errorText ?? "?")")
            NSLog("EgoNotch: could not read \(app)'s now playing: \(errorText ?? "?")")
            automationDenied = (errorText?.contains("-1743") ?? false)
                || (errorText?.localizedCaseInsensitiveContains("not allowed") ?? false)
            return nil
        }
        guard let output = String(data: outputData, encoding: .utf8) else { return nil }

        trace("osascript(\(app)) ok: \(output.replacingOccurrences(of: "\n", with: " | "))")
        let parts = output.components(separatedBy: "\n")
        guard parts.count >= 6 else { return nil }
        let title = parts[1].trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        let rawDuration = Double(parts[4].trimmingCharacters(in: .whitespaces)) ?? 0
        return Snapshot(
            app: app,
            title: title,
            artist: parts[2].trimmingCharacters(in: .whitespaces),
            album: parts[3].trimmingCharacters(in: .whitespaces),
            duration: durationInMilliseconds ? rawDuration / 1000 : rawDuration,
            position: Double(parts[5].trimmingCharacters(in: .whitespaces)) ?? 0,
            isPlaying: parts[0].trimmingCharacters(in: .whitespaces)
                .caseInsensitiveCompare("playing") == .orderedSame
        )
    }
}
