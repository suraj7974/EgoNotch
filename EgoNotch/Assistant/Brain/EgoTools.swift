import FoundationModels

/// The model's hands.
///
/// Every tool is a thin wrapper over `EgoActions` — the same functions the
/// deterministic grammar calls — so the fast path and the model can never
/// drift into doing different things for the same phrase.
///
/// `Tool.call(arguments:)` is `@concurrent`: it runs OFF the main actor, while
/// every action touches AppKit. Each one therefore hops through
/// `EgoToolBridge`, which also records what the action *actually* said. Ego
/// speaks that receipt rather than the model's summary of it, so a reply can
/// never claim something the app didn't do.

// MARK: - The bridge

@MainActor
enum EgoToolBridge {
    /// What the tools reported during the current turn, in order.
    private static var receipts: [ActionResult] = []

    static func beginTurn() { receipts = [] }

    /// Runs an action on the main actor and returns what the model should see.
    static func run(_ body: @MainActor () -> ActionResult) -> String {
        let result = body()
        receipts.append(result)
        // The model gets the detail too, because a follow-up question ("how
        // long is left?") often depends on it.
        return [result.spoken, result.detail].compactMap { $0 }.joined(separator: " ")
    }

    /// The line Ego should say: the tools' own words, joined. nil when the
    /// model answered without doing anything, in which case its text is used.
    static func spokenReceipt() -> ActionResult? {
        guard !receipts.isEmpty else { return nil }
        if receipts.count == 1 { return receipts[0] }
        return ActionResult(receipts.map(\.spoken).joined(separator: " "),
                            detail: receipts.compactMap(\.detail).joined(separator: " · "))
    }
}

// MARK: - Music

struct PlaybackTool: Tool {
    let name = "control_playback"
    let description = "Play, pause, skip, go back or restart the music or video that is playing."

    @Generable
    struct Arguments {
        @Guide(description: "What to do with playback.",
               .anyOf(["play", "pause", "toggle", "next", "previous", "restart"]))
        var action: String
    }

    func call(arguments: Arguments) async throws -> String {
        await EgoToolBridge.run {
            switch arguments.action.lowercased() {
            case "play": EgoActions.mediaPlay()
            case "pause": EgoActions.mediaPause()
            case "next": EgoActions.mediaNext()
            case "previous": EgoActions.mediaPrevious()
            case "restart": EgoActions.mediaRestart()
            default: EgoActions.mediaToggle()
            }
        }
    }
}

struct SeekTool: Tool {
    let name = "seek_playback"
    let description = "Jump forwards or backwards within the current track, or to a position in it."

    @Generable
    struct Arguments {
        @Guide(description: "How many seconds. Negative means backwards.")
        var seconds: Int
        @Guide(description: "True to move relative to the current position, false to jump to that position from the start.")
        var relative: Bool
    }

    func call(arguments: Arguments) async throws -> String {
        await EgoToolBridge.run {
            EgoActions.mediaSeek(seconds: Double(arguments.seconds), relative: arguments.relative)
        }
    }
}

struct NowPlayingTool: Tool {
    let name = "now_playing"
    let description = "Read what is playing right now: title, artist and how far through it is. "
        + "Always call this instead of guessing what the user is listening to."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await EgoToolBridge.run { EgoActions.nowPlaying() }
    }
}

// MARK: - Volume and brightness

struct VolumeTool: Tool {
    let name = "control_volume"
    let description = "Set, raise, lower, mute or report the system output volume."

    @Generable
    struct Arguments {
        @Guide(description: "What to do with the volume.",
               .anyOf(["set", "up", "down", "mute", "unmute", "report"]))
        var action: String
        @Guide(description: "For 'set', the level from 0 to 100. For 'up' and 'down', how much to change it by; omit for a normal step.")
        var percent: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let percent = arguments.percent
        return await EgoToolBridge.run {
            switch arguments.action.lowercased() {
            case "set":
                EgoActions.setVolume(fraction: Double(percent ?? 50) / 100)
            case "up":
                EgoActions.nudgeVolume(by: Double(percent ?? 10) / 100)
            case "down":
                EgoActions.nudgeVolume(by: -Double(percent ?? 10) / 100)
            case "mute":
                EgoActions.setMuted(true)
            case "unmute":
                EgoActions.setMuted(false)
            default:
                EgoActions.volumeReport()
            }
        }
    }
}

struct BrightnessTool: Tool {
    let name = "control_brightness"
    let description = "Set, raise or lower the built-in display's brightness."

    @Generable
    struct Arguments {
        @Guide(description: "What to do with the brightness.", .anyOf(["set", "up", "down"]))
        var action: String
        @Guide(description: "For 'set', the level from 0 to 100. For 'up' and 'down', how much to change it by; omit for a normal step.")
        var percent: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let percent = arguments.percent
        return await EgoToolBridge.run {
            switch arguments.action.lowercased() {
            case "set": EgoActions.setBrightness(fraction: Double(percent ?? 50) / 100)
            case "down": EgoActions.nudgeBrightness(by: -Double(percent ?? 10) / 100)
            default: EgoActions.nudgeBrightness(by: Double(percent ?? 10) / 100)
            }
        }
    }
}

// MARK: - The notch itself

struct NotchTool: Tool {
    let name = "control_notch"
    let description = "Open or close the notch panel, switch to one of its tabs, or open its settings."

    @Generable
    struct Arguments {
        @Guide(description: "What to do with the notch panel.",
               .anyOf(["open", "close", "settings", "tab"]))
        var action: String
        @Guide(description: "Which tab to show, when the action is 'tab' or 'open'.",
               .anyOf(["home", "shelf", "focus", "notes", "terminal", "recorder", "games"]))
        var tab: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let tab = arguments.tab.flatMap { NotchTab(rawValue: $0.lowercased()) }
        return await EgoToolBridge.run {
            switch arguments.action.lowercased() {
            case "close": EgoActions.closeNotch()
            case "settings": EgoActions.openSettings()
            case "tab":
                if let tab { EgoActions.switchTab(tab) } else { EgoActions.openNotch() }
            default: EgoActions.openNotch(tab: tab)
            }
        }
    }
}
