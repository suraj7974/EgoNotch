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

    nonisolated static func snapshot() -> Snapshot? {
        if isRunning("com.spotify.client"),
           let s = query(app: "Spotify", durationInMilliseconds: true) {
            return s
        }
        if isRunning("com.apple.Music"),
           let s = query(app: "Music", durationInMilliseconds: false) {
            return s
        }
        return nil
    }

    nonisolated private static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// One round-trip for the whole state; returns nil when nothing is
    /// loaded, or when Automation permission is denied (graceful).
    nonisolated private static func query(app: String,
                                          durationInMilliseconds: Bool) -> Snapshot? {
        let source = """
        tell application "\(app)"
            set st to player state as string
            set tr to current track
            set t to name of tr
            set a to artist of tr
            set al to album of tr
            set d to duration of tr
            set p to player position
            return st & "\\n" & t & "\\n" & a & "\\n" & al & "\\n" & d & "\\n" & p
        end tell
        """
        var error: NSDictionary?
        guard let output = NSAppleScript(source: source)?
            .executeAndReturnError(&error).stringValue, error == nil else { return nil }

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
