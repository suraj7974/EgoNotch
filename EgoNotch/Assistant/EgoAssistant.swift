import AppKit
import Observation

/// Ego: the notch's voice assistant.
///
/// This type is the whole public surface — ears, brain and voice hang off it,
/// and everything else in the app talks to Ego through `handle(_:)`. In P0 it
/// runs on typed commands so the entire loop can be proven without a
/// microphone; speech is layered on top without changing this state machine.
@MainActor
@Observable
final class EgoAssistant {
    static let shared = EgoAssistant()

    enum Phase: Equatable {
        case idle
        /// Listening for the rest of a command after the wake phrase.
        case listening
        case thinking
        /// Holding a risky action until the user says yes.
        case confirming
        case speaking
    }

    private(set) var phase: Phase = .idle
    /// What Ego heard (or was typed), shown live in the HUD.
    private(set) var heard = ""
    /// Ego's last reply — the short spoken line.
    private(set) var reply = ""
    /// The longer, on-screen version.
    private(set) var detail: String?
    private(set) var pending: PendingAction?
    /// 0…1 mic level, for the HUD's waveform. Stays 0 until P1 wires audio.
    private(set) var level: Double = 0

    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private var confirmTask: Task<Void, Never>?
    @ObservationIgnored let ears = EgoEars()
    @ObservationIgnored private let voice = EgoVoice()
    @ObservationIgnored private var levelPump: Task<Void, Never>?
    @ObservationIgnored private var appliedWakeName = SettingsStore.shared.egoWakeName
    @ObservationIgnored let planner = EgoPlanner()
    @ObservationIgnored private var thinkTask: Task<Void, Never>?

    /// Why the model isn't answering, shown on screen rather than spoken.
    private static var plannerHint: String {
        if case .unavailable(let why) = EgoPlanner.readiness { return why }
        return "Nothing in the command grammar matched."
    }

    private(set) var isActive = false

    private init() {}

    // MARK: - Lifecycle

    /// Idempotent: `syncActivation()` fires these on launch, on quit, and on
    /// every unrelated module toggle.
    func activate() {
        guard !isActive else { return }
        isActive = true
        EgoLog.trace("activated")

        ears.onCommand = { [weak self] command in self?.handle(command) }
        ears.onWake = { [weak self] in self?.beganCapturing() }
        ears.onIdle = { [weak self] in self?.captureEndedEmpty() }
        voice.onFinish = { [weak self] in
            Task { @MainActor in self?.ears.resumeAfterSpeaking() }
        }
        startListeningIfWanted()
        startLevelPump()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        thinkTask?.cancel(); thinkTask = nil
        planner.reset()
        levelPump?.cancel(); levelPump = nil
        voice.stop()
        Task { await ears.stop() }
        dismiss()
        EgoLog.trace("deactivated")
    }

    /// Another app took the microphone (a real call). Stand down, then come
    /// back when they're done — unless the user turned that behaviour off.
    func meetingStateChanged(_ inMeeting: Bool) {
        guard isActive, SettingsStore.shared.egoPauseInMeetings else { return }
        if inMeeting {
            EgoLog.trace("standing down: another app has the mic")
            stopListening()
        } else {
            EgoLog.trace("mic free again")
            startListeningIfWanted()
        }
    }

    /// The name in the wake phrase primes the recogniser when the microphone
    /// opens, so changing it has to reopen the ears — otherwise the new word
    /// is matched by the text matcher but never actually heard.
    func wakeNameChanged() {
        let name = SettingsStore.shared.egoWakeName
        guard name != appliedWakeName else { return }
        appliedWakeName = name
        guard isActive else { return }
        EgoLog.trace("wake name is now “\(name)” — reopening the microphone")
        Task { await ears.stop(); self.startListeningIfWanted() }
    }

    /// Wake-word listening is a setting; with it off, Ego only opens the mic
    /// for a push-to-talk utterance.
    func startListeningIfWanted() {
        guard isActive, SettingsStore.shared.egoWakeWord else { return }
        Task { await ears.start() }
    }

    func stopListening() {
        Task { await ears.stop() }
    }

    /// ⌘⌥E: talk without the wake phrase. Press again to cancel.
    func pushToTalk() {
        guard isActive else { return }
        if case .capturing = ears.status {
            Task { await ears.stop(); self.startListeningIfWanted() }
            dismiss()
            return
        }
        phase = .listening
        heard = ""
        reply = "Listening…"
        show()
        // Without this the HUD stays open forever when no command follows —
        // the listening state has no natural end of its own.
        scheduleDismiss(after: 15)
        Task { await ears.beginPushToTalk() }
    }

    private func startLevelPump() {
        levelPump?.cancel()
        levelPump = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                guard let self else { return }
                self.level = self.ears.level
                if case .capturing = self.ears.status {
                    if self.phase != .listening { self.phase = .listening }
                    if !self.ears.partial.isEmpty { self.heard = self.ears.partial }
                }
            }
        }
    }

    // MARK: - Entry point

    /// Runs one command through the whole pipeline. Voice and the debug
    /// harness both land here, so there is exactly one path to test.
    func handle(_ text: String) {
        let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        EgoLog.trace("handle: \(command)")

        heard = command
        show()

        // A pending confirmation swallows the next utterance: "yes" means the
        // held action, never a fresh command.
        if pending != nil, let decision = ConfirmWords.decide(command) {
            decision ? confirmPending() : cancelPending()
            return
        }

        phase = .thinking
        if let result = CommandGrammar.match(command) {
            EgoLog.trace("grammar hit → \(result.spoken)")
            deliver(result)
            return
        }

        // Nothing deterministic matched, so hand it to the model. The HUD is
        // already open and showing the waveform, which is what makes the
        // second or two of thinking read as listening rather than as a hang.
        guard planner.isReady else {
            EgoLog.trace("no grammar match, and no model")
            deliver(ActionResult("I don't know that one yet.",
                                 detail: Self.plannerHint))
            return
        }
        EgoLog.trace("no grammar match → asking the model")
        thinkTask?.cancel()
        thinkTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.planner.think(command)
            guard !Task.isCancelled else { return }
            self.deliver(result)
        }
    }

    // MARK: - Results

    private func deliver(_ result: ActionResult) {
        reply = result.spoken
        detail = result.detail

        if let pending = result.pending {
            self.pending = pending
            phase = .confirming
            reply = pending.question
            detail = pending.detail
            armConfirmTimeout()
            say(pending.question)
            return
        }

        phase = .speaking
        say(result.spoken)
        scheduleDismiss(after: 2.6)
    }

    /// Speaks a sample in the currently chosen voice, regardless of whether
    /// spoken replies are switched on — it's a preview, not a reply.
    func speakSample() {
        voice.speak("Ego here. Volume thirty, terminal open.",
                    voiceIdentifier: SettingsStore.shared.egoVoiceIdentifier,
                    rate: SettingsStore.shared.egoSpeechRate)
    }

    private func say(_ text: String) {
        guard SettingsStore.shared.egoSpeakReplies, isActive else { return }
        // Mute BEFORE speaking: the tap stops producing audio entirely, so the
        // transcriber can never hear the reply and treat it as a command.
        EgoLog.trace("speaking: \(text)")
        ears.muteWhileSpeaking()
        voice.speak(text,
                    voiceIdentifier: SettingsStore.shared.egoVoiceIdentifier,
                    rate: SettingsStore.shared.egoSpeechRate)
    }

    private func confirmPending() {
        guard let pending else { return }
        self.pending = nil
        confirmTask?.cancel()
        EgoLog.trace("confirmed: \(pending.detail)")
        deliver(pending.perform())
    }

    private func cancelPending() {
        guard pending != nil else { return }
        pending = nil
        confirmTask?.cancel()
        EgoLog.trace("cancelled")
        deliver(ActionResult("Cancelled."))
    }

    /// An unanswered confirmation must never linger — silence means no.
    private func armConfirmTimeout() {
        confirmTask?.cancel()
        confirmTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.pending != nil else { return }
            self.pending = nil
            self.deliver(ActionResult("Cancelled."))
        }
    }

    // MARK: - HUD

    private func show() {
        dismissTask?.cancel()
        EgoLog.trace("hud: open")
        NotchPanelController.current?.stateController.beginAssistant()
    }

    /// Ego heard the wake phrase and is taking a command. Shows the HUD with a
    /// long safety net so a half-heard "hey ego" can't strand it open.
    func beganCapturing() {
        guard isActive, phase != .confirming else { return }
        phase = .listening
        reply = ""
        show()
        scheduleDismiss(after: 15)
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.pending == nil else { return }
            self.phase = .idle
            self.heard = ""
            EgoLog.trace("hud: retired")
            NotchPanelController.current?.stateController.endAssistant()
        }
    }

    /// The user hovered or clicked the notch while Ego's HUD was up. Let go
    /// quietly: drop a held question — reaching for the mouse is not an answer
    /// — and reset, without touching the panel. The state controller is
    /// already moving it, and fighting it here would flicker.
    func userReclaimedPanel() {
        dismissTask?.cancel(); dismissTask = nil
        confirmTask?.cancel(); confirmTask = nil
        pending = nil
        phase = .idle
        heard = ""
        EgoLog.trace("hud: user took the panel back")
    }

    /// A wake phrase with nothing after it. Retire promptly instead of sitting
    /// on the 15-second safety net — a half-heard "hey ego" shouldn't park a
    /// panel over the user's screen.
    private func captureEndedEmpty() {
        guard phase == .listening, pending == nil else { return }
        scheduleDismiss(after: 0.5)
    }

    /// Close the HUD immediately (Esc, or the user clicking away).
    func dismiss() {
        dismissTask?.cancel()
        confirmTask?.cancel()
        pending = nil
        phase = .idle
        heard = ""
        NotchPanelController.current?.stateController.endAssistant()
    }

    func confirmFromUI() { confirmPending() }
    func cancelFromUI() { cancelPending() }
}

/// Words that answer a held question. Deliberately matched here and never by
/// the language model — a confirmation must be mechanical.
enum ConfirmWords {
    private static let yes = ["confirm", "yes", "yeah", "yep", "do it", "go ahead", "run it", "okay", "ok"]
    private static let no = ["cancel", "no", "nope", "stop", "don't", "dont", "never mind", "nevermind"]

    /// true = go, false = cancel, nil = not an answer at all.
    static func decide(_ text: String) -> Bool? {
        let normalised = text.lowercased().trimmingCharacters(in: .whitespaces)
        if yes.contains(where: { normalised == $0 || normalised.hasPrefix($0 + " ") }) { return true }
        if no.contains(where: { normalised == $0 || normalised.hasPrefix($0 + " ") }) { return false }
        return nil
    }
}

/// EGO_DEBUG=1 writes a trace beside the app's other data. The developer can't
/// always test by talking to the machine, so the pipeline has to be readable
/// after the fact.
enum EgoLog {
    nonisolated static func trace(_ message: String) {
        guard ProcessInfo.processInfo.environment["EGO_DEBUG"] != nil else { return }
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EgoNotch/ego.log")
        let line = "\(Date()) \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            try? handle.write(contentsOf: Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
