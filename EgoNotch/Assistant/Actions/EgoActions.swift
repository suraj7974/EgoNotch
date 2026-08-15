import AppKit
import Observation

/// What an action did, in Ego's own words.
///
/// `spoken` is deliberately terse — it gets read aloud, so "Paused." beats
/// "I have paused the music for you". `detail` is the longer version the notch
/// shows on screen, where reading is cheap.
struct ActionResult {
    var spoken: String
    var detail: String?
    /// Set when the action refuses to run until the user says so.
    var pending: PendingAction?

    init(_ spoken: String, detail: String? = nil, pending: PendingAction? = nil) {
        self.spoken = spoken
        self.detail = detail
        self.pending = pending
    }

    static let notAvailable = ActionResult("That module is off.")
}

/// An action held back for confirmation. `perform` is the real work, deferred.
struct PendingAction {
    /// What Ego asks: "Run npm install in notch?"
    let question: String
    /// The exact thing that will happen, shown verbatim on screen.
    let detail: String
    let perform: @MainActor () -> ActionResult
}

/// **The** implementation of every verb Ego knows.
///
/// The grammar layer, the language model's tools, and the debug harness all
/// call these same functions — so the fast path and the model can never drift
/// into doing different things for the same phrase.
@MainActor
enum EgoActions {

    // MARK: - Reaching the app

    private static func media() -> MediaController? {
        (WidgetRegistry.widget(id: "media") as? MediaWidget)?.controller
    }

    private static var panel: NotchPanelController? { NotchPanelController.current }

    // MARK: - Media

    static func mediaPlay() -> ActionResult {
        guard let media = media() else { return .notAvailable }
        media.send(.play)
        return ActionResult("Playing.", detail: nowPlayingLine())
    }

    static func mediaPause() -> ActionResult {
        guard let media = media() else { return .notAvailable }
        media.send(.pause)
        return ActionResult("Paused.")
    }

    static func mediaToggle() -> ActionResult {
        guard let media = media() else { return .notAvailable }
        let wasPlaying = media.model.isPlaying
        media.send(.togglePlayPause)
        return ActionResult(wasPlaying ? "Paused." : "Playing.",
                            detail: wasPlaying ? nil : nowPlayingLine())
    }

    static func mediaNext() -> ActionResult {
        guard let media = media() else { return .notAvailable }
        media.send(.nextTrack)
        return ActionResult("Skipped.")
    }

    static func mediaPrevious() -> ActionResult {
        guard let media = media() else { return .notAvailable }
        media.send(.previousTrack)
        return ActionResult("Back a track.")
    }

    static func mediaRestart() -> ActionResult {
        guard let media = media() else { return .notAvailable }
        media.seek(to: 0)
        return ActionResult("From the top.")
    }

    static func mediaSeek(seconds: Double, relative: Bool) -> ActionResult {
        guard let media = media(), media.model.hasSession else {
            return ActionResult("Nothing is playing.")
        }
        let target = relative ? media.model.currentElapsed + seconds : seconds
        let duration = media.model.track?.duration ?? 0
        let clamped = max(0, duration > 0 ? min(target, duration - 1) : target)
        media.seek(to: clamped)
        return ActionResult(relative
                            ? (seconds >= 0 ? "Forward \(Int(abs(seconds))) seconds."
                                            : "Back \(Int(abs(seconds))) seconds.")
                            : "Jumped to \(timeText(clamped)).")
    }

    /// Read-only. Every value comes from the live model — nothing is guessed.
    static func nowPlaying() -> ActionResult {
        guard let media = media(), media.model.hasSession, let track = media.model.track else {
            return ActionResult("Nothing is playing.")
        }
        let verb = media.model.isPlaying ? "Playing" : "Paused"
        let artist = track.artist.isEmpty ? "" : " by \(track.artist)"
        return ActionResult("\(verb) \(track.title)\(artist).",
                            detail: nowPlayingLine())
    }

    private static func nowPlayingLine() -> String? {
        guard let model = media()?.model, let track = model.track, model.hasSession else { return nil }
        let position = "\(timeText(model.currentElapsed)) / \(timeText(track.duration))"
        let source = model.appName.map { " · \($0)" } ?? ""
        return "\(track.title) — \(track.artist)  \(position)\(source)"
    }

    // MARK: - Volume & brightness

    static func setVolume(fraction: Double) -> ActionResult {
        guard SystemVolume.isControllable else { return ActionResult("I can't change this output's volume.") }
        let clamped = min(max(fraction, 0), 1)
        SystemVolume.setVolume(Float(clamped))
        if clamped > 0, SystemVolume.isMuted() { SystemVolume.setMuted(false) }
        return ActionResult("Volume \(Int((clamped * 100).rounded())).")
    }

    static func nudgeVolume(by delta: Double) -> ActionResult {
        guard SystemVolume.isControllable, let current = SystemVolume.volume() else {
            return ActionResult("I can't change this output's volume.")
        }
        return setVolume(fraction: Double(current) + delta)
    }

    static func setMuted(_ muted: Bool) -> ActionResult {
        guard SystemVolume.hasMuteControl else { return ActionResult("This output has no mute.") }
        SystemVolume.setMuted(muted)
        return ActionResult(muted ? "Muted." : "Unmuted.")
    }

    static func volumeReport() -> ActionResult {
        guard let level = SystemVolume.volume() else { return ActionResult("I can't read the volume.") }
        if SystemVolume.isMuted() { return ActionResult("Muted.") }
        return ActionResult("Volume \(Int((level * 100).rounded())).")
    }

    static func setBrightness(fraction: Double) -> ActionResult {
        guard SystemBrightness.controllable else {
            return ActionResult("I can only set the built-in display's brightness.")
        }
        let clamped = min(max(fraction, 0), 1)
        SystemBrightness.setBrightness(Float(clamped))
        return ActionResult("Brightness \(Int((clamped * 100).rounded())).")
    }

    static func nudgeBrightness(by delta: Double) -> ActionResult {
        guard SystemBrightness.controllable, let current = SystemBrightness.brightness() else {
            return ActionResult("I can only set the built-in display's brightness.")
        }
        return setBrightness(fraction: Double(current) + delta)
    }

    // MARK: - The notch itself

    static func openNotch(tab: NotchTab? = nil) -> ActionResult {
        if let tab { PanelUIState.shared.selectedTab = tab }
        panel?.expand()
        return ActionResult(tab.map { "\($0.title)." } ?? "Open.")
    }

    static func closeNotch() -> ActionResult {
        panel?.stateController.collapse()
        return ActionResult("Closed.")
    }

    static func switchTab(_ tab: NotchTab) -> ActionResult {
        guard PanelUIState.shared.availableTabs.contains(tab) else {
            return ActionResult("\(tab.title) is turned off.")
        }
        PanelUIState.shared.selectedTab = tab
        panel?.expand()
        return ActionResult("\(tab.title).")
    }

    static func openSettings() -> ActionResult {
        NotificationCenter.default.post(name: .egoOpenSettings, object: nil)
        return ActionResult("Settings.")
    }

    // MARK: - The terminal

    private static func terminal() -> NotchTerminal? {
        (WidgetRegistry.widget(id: "terminal") as? TerminalWidget)?.terminal
    }

    /// Never runs anything on its own: this returns a *held* action, and the
    /// caller has to get a yes first. The one exception is a command the
    /// guardrails refuse outright, which is reported and dropped.
    static func runTerminal(_ command: String) -> ActionResult {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ActionResult("Run what?") }
        guard SettingsStore.shared.egoTerminalControl else {
            return ActionResult("Terminal control is switched off.")
        }
        guard terminal() != nil else { return ActionResult("The terminal is turned off.") }

        if case .blocked(let why) = Guardrails.judge(command: trimmed) {
            EgoLog.trace("terminal refused: \(trimmed) — \(why)")
            return ActionResult("No — \(why).", detail: trimmed)
        }
        // Read the command back rather than paraphrasing it. The whole point of
        // the gate is that you hear the exact thing that will run.
        return ActionResult("Run \(trimmed)?",
                            detail: trimmed,
                            pending: PendingAction(
                                question: "Run \(trimmed)?",
                                detail: trimmed,
                                perform: { performTerminal(trimmed) }))
    }

    private static func performTerminal(_ command: String) -> ActionResult {
        // Checked again HERE, not just at the gate: the password field may
        // have appeared during the seconds the question was on screen.
        guard !Guardrails.secureInputActive else {
            return ActionResult("Not while a password field is open.")
        }
        guard let terminal = terminal() else { return ActionResult("The terminal is turned off.") }
        PanelUIState.shared.selectedTab = .terminal
        panel?.expand()
        terminal.run(command)
        EgoLog.trace("terminal ran: \(command)")
        return ActionResult("Running.", detail: command)
    }

    static func interruptTerminal() -> ActionResult {
        guard let terminal = terminal(), terminal.isRunning else {
            return ActionResult("Nothing to stop.")
        }
        terminal.interrupt()
        return ActionResult("Stopped.")
    }

    static func terminalDirectory() -> ActionResult {
        guard let terminal = terminal() else { return ActionResult("The terminal is turned off.") }
        // The shell reports its own directory as it changes; before it has
        // started there is nothing to report, and guessing would be worse.
        guard terminal.isRunning else { return ActionResult("The terminal isn't running yet.") }
        guard let directory = terminal.directory else { return ActionResult("I can't tell yet.") }
        return ActionResult(directory.lastPathComponent, detail: directory.path)
    }

    // MARK: - Helpers

    static func timeText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
