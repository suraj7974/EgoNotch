import FoundationModels

/// Which of Ego's tools an utterance could possibly need.
///
/// Eighteen tools in front of the model at once is too many: asked to "open
/// Zed" it reached for the games tool and started the runner. Narrowing the
/// choice to the handful a sentence could plausibly mean removes most of that
/// class of mistake, and it costs a dictionary lookup.
///
/// Deliberately generous — a scope that might apply is included, because
/// offering one tool too many is a small cost and withholding the right one is
/// a total failure.
nonisolated enum EgoScope: CaseIterable {
    case media, sound, terminal, notch, time, notes, camera, games, machine, apps, shortcuts, web

    /// Words that mean this scope is in play.
    var cues: [String] {
        switch self {
        case .media:
            ["play", "pause", "song", "music", "track", "skip", "next", "previous", "resume",
             "playing", "listen", "artist", "album", "seek", "rewind", "forward", "gaana"]
        case .sound:
            ["volume", "loud", "quiet", "mute", "unmute", "sound", "bright", "dim", "screen"]
        case .terminal:
            ["terminal", "shell", "run", "execute", "type", "command", "npm", "git", "python",
             "pwd", "directory", "folder", "control", "ctrl", "interrupt", "kill"]
        case .notch:
            ["notch", "tab", "panel", "settings", "home", "shelf", "close", "collapse", "expand"]
        case .time:
            // NOT a bare "left": that word is directional far more often than
            // it is "how long is left", and it was pulling the timer into
            // "put chrome on the left".
            ["timer", "pomodoro", "stopwatch", "minute", "minutes", "break", "focus", "countdown",
             "how long", "time left", "long left", "much left"]
        case .notes:
            ["note", "notes", "todo", "list", "remind", "reminder", "clipboard", "copy", "copied",
             "shelf", "complete", "tick", "checkbox"]
        case .camera:
            ["photo", "picture", "selfie", "camera", "video", "record", "boomerang", "gif",
             "booth", "filter", "snap"]
        case .games:
            ["game", "games", "snake", "runner", "dino", "pong", "shooter", "play a game"]
        case .machine:
            ["battery", "cpu", "memory", "ram", "disk", "storage", "space", "calendar",
             "meeting", "event", "schedule", "charge"]
        case .apps:
            ["open", "quit", "switch", "launch", "window", "maximise", "maximize", "left",
             "right", "centre", "center", "half", "menu", "export", "save", "print", "app"]
        case .shortcuts:
            ["shortcut", "shortcuts", "automation", "focus mode", "wifi", "wi-fi"]
        case .web:
            ["search", "google", "website", "web", "browser", "url", ".com", ".dev", "link"]
        }
    }

    @MainActor
    var tools: [any Tool] {
        switch self {
        case .media: [PlaybackTool(), SeekTool(), NowPlayingTool()]
        case .sound: [VolumeTool(), BrightnessTool()]
        case .terminal: [TerminalTool(), TerminalStateTool()]
        case .notch: [NotchTool()]
        case .time: [TimerTool()]
        case .notes: [NoteTool(), StashTool()]
        case .camera: [CaptureTool()]
        case .games: [PlayTool()]
        case .machine: [SystemTool()]
        case .apps: [AppTool(), MenuTool()]
        case .shortcuts: [ShortcutTool()]
        case .web: [WebTool()]
        }
    }

    /// The scopes a sentence could mean, most likely first.
    static func matching(_ raw: String) -> [EgoScope] {
        let text = " " + raw.lowercased() + " "
        let scored = allCases.compactMap { scope -> (EgoScope, Int)? in
            let hits = scope.cues.reduce(into: 0) { total, cue in
                if text.contains(cue.contains(" ") ? cue : " \(cue)") { total += 1 }
                else if text.contains(cue) { total += 1 }
            }
            return hits > 0 ? (scope, hits) : nil
        }
        guard !scored.isEmpty else {
            // Nothing recognisable: offer what most requests turn out to be,
            // rather than everything.
            return [.media, .apps, .notch, .machine]
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(4).map(\.0)
    }
}
