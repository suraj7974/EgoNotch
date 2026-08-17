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
    /// What the tools reported during the current turn, in order. Reads are
    /// kept apart from changes: a tool that *did* something owns the reply,
    /// while a tool that merely *read* something is raw material for the
    /// model's own sentence.
    private static var changes: [ActionResult] = []
    private static var reads: [ActionResult] = []

    static func beginTurn() {
        changes = []
        reads = []
    }

    /// Runs an action on the main actor and returns what the model should see.
    /// `changing: false` marks a tool that only reports state.
    static func run(changing: Bool = true, _ body: @MainActor () -> ActionResult) -> String {
        let result = body()
        if changing { changes.append(result) } else { reads.append(result) }
        // The model gets the detail too: "how far through is this?" is
        // answerable only from the position hidden in there.
        return [result.spoken, result.detail].compactMap { $0 }.joined(separator: " ")
    }

    /// The same, for actions that have to wait on another process — reaching
    /// into other apps is synchronous IPC, and it runs off the main actor.
    static func runAsync(changing: Bool = true,
                         _ body: @MainActor () async -> ActionResult) async -> String {
        let result = await body()
        if changing { changes.append(result) } else { reads.append(result) }
        return [result.spoken, result.detail].compactMap { $0 }.joined(separator: " ")
    }

    /// The line Ego should say when something actually happened — the tools'
    /// own words, which cannot be wrong. nil when the turn only read state or
    /// did nothing, and the model's sentence is the better answer.
    static func spokenReceipt() -> ActionResult? {
        guard !changes.isEmpty else { return nil }
        // A held action outranks everything else in the turn: it has a question
        // attached, and merging it into a summary would lose the very thing the
        // user has to answer.
        if let held = changes.first(where: { $0.pending != nil }) { return held }
        // The model sometimes calls the same tool twice in one turn; saying it
        // twice would be a stutter.
        var spoken: [String] = []
        for change in changes where spoken.last != change.spoken {
            spoken.append(change.spoken)
        }
        if spoken.count == 1 {
            return ActionResult(spoken[0], detail: changes[0].detail)
        }
        return ActionResult(spoken.joined(separator: " "),
                            detail: changes.compactMap(\.detail).joined(separator: " · "))
    }

    /// What a read-only turn found, for the notch to show under the model's
    /// spoken answer.
    static func readDetail() -> String? {
        reads.compactMap { $0.detail ?? $0.spoken }.first
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
        await EgoToolBridge.run(changing: false) { EgoActions.nowPlaying() }
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
        let action = arguments.action.lowercased()
        return await EgoToolBridge.run(changing: action != "report") {
            switch action {
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

// MARK: - The shell

/// The one tool that cannot act on its own. `EgoActions.runTerminal` returns a
/// *held* action, so what this reports back to the model is a question, not a
/// result — and the model is told plainly not to pretend otherwise.
struct TerminalTool: Tool {
    let name = "run_terminal"
    let description = "Ask to run a shell command in the notch's terminal. "
        + "This does NOT run it: the user must confirm first. Pass the command exactly as it "
        + "should be typed, with no explanation and no surrounding quotes."

    @Generable
    struct Arguments {
        @Guide(description: "The shell command, exactly as it should be typed. For example: git status")
        var command: String
    }

    func call(arguments: Arguments) async throws -> String {
        await EgoToolBridge.run { EgoActions.runTerminal(arguments.command) }
    }
}

struct TerminalStateTool: Tool {
    let name = "terminal_state"
    let description = "Read the terminal's current directory, or stop whatever is running in it."

    @Generable
    struct Arguments {
        @Guide(description: "What to do.", .anyOf(["directory", "interrupt"]))
        var action: String
    }

    func call(arguments: Arguments) async throws -> String {
        let interrupt = arguments.action.lowercased() == "interrupt"
        return await EgoToolBridge.run(changing: interrupt) {
            interrupt ? EgoActions.interruptTerminal() : EgoActions.terminalDirectory()
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

// MARK: - Timers

struct TimerTool: Tool {
    let name = "control_timer"
    let description = "Start, pause or reset a pomodoro/focus session, start a countdown of N minutes, "
        + "run the stopwatch, or read how long is left."

    @Generable
    struct Arguments {
        @Guide(description: "What to do.",
               .anyOf(["focus", "break", "deep", "pause", "reset",
                       "countdown", "stopwatch", "stopwatch_reset", "remaining"]))
        var action: String
        @Guide(description: "Minutes, for the 'countdown' action.")
        var minutes: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let action = arguments.action.lowercased()
        let minutes = arguments.minutes
        return await EgoToolBridge.run(changing: action != "remaining") {
            switch action {
            case "focus": EgoActions.startFocus(.focus)
            case "break": EgoActions.startFocus(.shortBreak)
            case "deep": EgoActions.startFocus(.deep)
            case "pause": EgoActions.pauseFocus()
            case "reset": EgoActions.resetFocus()
            case "countdown": EgoActions.startTimer(minutes: minutes ?? 10)
            case "stopwatch": EgoActions.stopwatch("toggle")
            case "stopwatch_reset": EgoActions.stopwatch("reset")
            default: EgoActions.timeLeft()
            }
        }
    }
}

// MARK: - Notes, todos, clipboard, shelf

struct NoteTool: Tool {
    let name = "capture_note"
    let description = "Write a note, add something to the todo list, tick one off, "
        + "or read back the notes or the list."

    @Generable
    struct Arguments {
        @Guide(description: "What to do.",
               .anyOf(["note", "checkbox", "todo", "complete", "read_notes",
                       "read_todos", "clear_done"]))
        var action: String
        @Guide(description: "The text of the note or todo, or which item to complete.")
        var text: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let action = arguments.action.lowercased()
        let text = arguments.text ?? ""
        let reads = ["read_notes", "read_todos"]
        return await EgoToolBridge.run(changing: !reads.contains(action)) {
            switch action {
            case "note": EgoActions.addNote(text)
            case "checkbox": EgoActions.addNote(text, asCheckbox: true)
            case "todo": EgoActions.addTodo(text)
            case "complete": EgoActions.completeTodo(text)
            case "clear_done": EgoActions.clearDoneTodos()
            case "read_todos": EgoActions.readTodos()
            default: EgoActions.readNotes()
            }
        }
    }
}

struct StashTool: Tool {
    let name = "clipboard_and_shelf"
    let description = "Read or re-copy the last thing copied, and report or empty the notch's shelf."

    @Generable
    struct Arguments {
        @Guide(description: "What to do.",
               .anyOf(["read_clip", "copy_clip", "shelf", "clear_shelf"]))
        var action: String
    }

    func call(arguments: Arguments) async throws -> String {
        let action = arguments.action.lowercased()
        let reads = ["read_clip", "shelf"]
        return await EgoToolBridge.run(changing: !reads.contains(action)) {
            switch action {
            case "copy_clip": EgoActions.copyLastClip()
            case "shelf": EgoActions.shelfReport()
            case "clear_shelf": EgoActions.clearShelf()
            default: EgoActions.lastClip()
            }
        }
    }
}

// MARK: - Camera, games, links

struct CaptureTool: Tool {
    let name = "control_camera"
    let description = "Take a photo, selfie, boomerang, photo-booth strip, caption GIF or video "
        + "with the notch's camera, or change its live filter."

    @Generable
    struct Arguments {
        @Guide(description: "What to capture. 'filter' only changes the look without capturing.",
               .anyOf(["photo", "video", "boomerang", "gif", "booth", "daily", "filter"]))
        var mode: String
        @Guide(description: "The live filter to apply.",
               .anyOf(["none", "mono", "sepia", "vhs", "thermal", "pixel"]))
        var filter: String?
        @Guide(description: "Self-timer in seconds: 0, 3 or 10.")
        var selfTimer: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        let mode = arguments.mode.lowercased()
        let filter = arguments.filter.flatMap { CaptureFilter(rawValue: $0.lowercased()) }
        let timer = arguments.selfTimer
        return await EgoToolBridge.run {
            if mode == "filter" { return EgoActions.setFilter(filter ?? .none) }
            let capture = CaptureMode(rawValue: mode) ?? .photo
            return EgoActions.capture(mode: capture, filter: filter, selfTimer: timer)
        }
    }
}

struct PlayTool: Tool {
    let name = "play_notch_game"
    /// Narrow on purpose. When this also claimed to "open things by name" the
    /// model reached for it on "open Zed" and started the runner game instead.
    let description = "Start one of the notch's four built-in games, and nothing else. "
        + "The games are: runner, snake, pong, shooter. Never use this to open an application."

    @Generable
    struct Arguments {
        @Guide(description: "Which game.", .anyOf(["runner", "snake", "pong", "shooter"]))
        var game: String
    }

    func call(arguments: Arguments) async throws -> String {
        let name = arguments.game.lowercased()
        return await EgoToolBridge.run {
            let game = GameChoice.allCases.first { $0.title.lowercased() == name || $0.rawValue == name }
                ?? GameChoice.allCases.first {
                    name.contains($0.title.lowercased()) || name.contains($0.rawValue)
                }
            // No falling back to a default: starting the wrong game because the
            // name didn't match is worse than saying so.
            guard let game else { return ActionResult("I don't have a game called that.") }
            return EgoActions.playGame(game)
        }
    }
}

// MARK: - The machine

struct SystemTool: Tool {
    let name = "read_system"
    let description = "Read this Mac's battery, CPU, memory or free disk, or the next event in the "
        + "user's calendar today. Always call this instead of guessing any of them."

    @Generable
    struct Arguments {
        @Guide(description: "What to read.",
               .anyOf(["battery", "cpu", "ram", "disk", "calendar"]))
        var what: String
    }

    func call(arguments: Arguments) async throws -> String {
        let what = arguments.what.lowercased()
        return await EgoToolBridge.run(changing: false) {
            what == "calendar" ? EgoActions.nextEvent() : EgoActions.systemReport(what)
        }
    }
}


// MARK: - The rest of the Mac

struct AppTool: Tool {
    let name = "control_app"
    /// The tool for anything that is an *app*. Said explicitly, because the
    /// games tool used to answer "open Zed".
    let description = "Open, switch to or quit any application installed on this Mac — Spotify, "
        + "Zed, Safari, Xcode, anything — or move its front window to half the screen, maximise "
        + "it or centre it. Use this for every application by name."

    @Generable
    struct Arguments {
        @Guide(description: "What to do with the app.",
               .anyOf(["open", "quit", "left", "right", "top", "bottom", "maximise", "centre"]))
        var action: String
        @Guide(description: "The application's name. Omit for window moves to use whatever is in front.")
        var app: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let action = arguments.action.lowercased()
        let app = arguments.app
        return await EgoToolBridge.runAsync {
            switch action {
            case "open": EgoActions.openApp(named: app ?? "")
            case "quit": EgoActions.quitApp(named: app ?? "")
            default:
                await EgoActions.placeWindow(SystemControl.WindowPlace(rawValue: action) ?? .maximise,
                                             appNamed: app)
            }
        }
    }
}

struct MenuTool: Tool {
    let name = "menu_command"
    let description = "Press a menu command in the app that is in front — anything in its menu bar, "
        + "such as \"Export as PDF\", \"Save All\" or \"Zoom In\". Works in any Mac app."

    @Generable
    struct Arguments {
        @Guide(description: "The menu item's name, as it appears in the menu.")
        var command: String
        @Guide(description: "Which app's menu. Omit for whatever is in front.")
        var app: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let command = arguments.command
        let app = arguments.app
        return await EgoToolBridge.runAsync {
            await EgoActions.runMenuCommand(command, appNamed: app)
        }
    }
}

struct ShortcutTool: Tool {
    let name = "run_shortcut"
    let description = "Run one of the user's own Shortcuts by name, or list what they have. "
        + "This is how to reach Focus modes, Wi-Fi, home automation and anything else without an API."

    @Generable
    struct Arguments {
        @Guide(description: "What to do.", .anyOf(["run", "list"]))
        var action: String
        @Guide(description: "The shortcut's name, when running one.")
        var name: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let listing = arguments.action.lowercased() == "list"
        let name = arguments.name ?? ""
        return await EgoToolBridge.runAsync(changing: !listing) {
            listing ? await EgoActions.listShortcuts() : await EgoActions.runShortcut(named: name)
        }
    }
}

struct WebTool: Tool {
    let name = "open_web"
    let description = "Open a web address in the browser, search the web, or open one of the "
        + "user's saved quick links by name. For web pages only — not for applications."

    @Generable
    struct Arguments {
        @Guide(description: "What to do.", .anyOf(["open", "search", "link"]))
        var action: String
        @Guide(description: "The address, the words to search for, or the saved link's name.")
        var text: String
    }

    func call(arguments: Arguments) async throws -> String {
        let action = arguments.action.lowercased()
        let text = arguments.text
        return await EgoToolBridge.run {
            switch action {
            case "search": EgoActions.search(text)
            case "link": EgoActions.openLink(named: text)
            default: EgoActions.openURL(text)
            }
        }
    }
}


// MARK: - People

struct CallTool: Tool {
    let name = "call_or_message"
    let description = "Call someone by name or number, start a FaceTime video call, or open a "
        + "message to them with text ready to send. Calls always ask the user to confirm first, "
        + "and messages are never sent automatically."

    @Generable
    struct Arguments {
        @Guide(description: "What to do.", .anyOf(["call", "video", "message"]))
        var action: String
        @Guide(description: "The person's name as the user said it, or their phone number.")
        var who: String
        @Guide(description: "What the message should say, for the 'message' action.")
        var text: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let action = arguments.action.lowercased()
        let who = arguments.who
        let text = arguments.text ?? ""
        return await EgoToolBridge.run {
            switch action {
            case "video": EgoActions.call(who, video: true)
            case "message": EgoActions.message(who, saying: text)
            default: EgoActions.call(who)
            }
        }
    }
}
