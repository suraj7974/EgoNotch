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
    @ObservationIgnored private var thinkCount = 0
    @ObservationIgnored private var idleTask: Task<Void, Never>?

    /// True from the first wake until dismissed. While it holds, Ego keeps
    /// the floor: no wake word is needed for the next command or answer.
    private(set) var isConversing = false

    /// A conversation ends when you end it — "stop", Esc, or reaching for the
    /// notch. This is only a backstop against Ego being left open by accident
    /// (a false wake while you're out of the room), which is why it is long
    /// rather than tidy.
    private static let conversationIdle: Double = 600

    /// Ways of saying "I didn't mean to summon you". Matched only as the WHOLE
    /// utterance: "stop" dismisses Ego, while "stop the music" is a command,
    /// and telling them apart is the difference between a good assistant and
    /// one you stop talking to.
    private static let dismissals: Set<String> = [
        "dismiss", "dismissed", "stop", "cancel", "nothing", "no", "never mind",
        "nevermind", "forget it", "sorry", "shut up", "be quiet", "quiet",
        "go away", "leave it", "not you", "thats all", "that is all", "done",
        "thank you", "thanks", "goodbye", "bye",
        "chup", "ruko", "kuch nahi", "nahi", "rehne do", "jao", "bas", "khatam",
    ]

    static func isDismissal(_ text: String) -> Bool {
        dismissals.contains(WakePhrase.normalise(text))
    }

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
            Task { @MainActor in self?.finishedSpeaking() }
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

    /// Teaching Ego a voice. Opens the microphone if it isn't already, since
    /// enrolment is useless without it.
    func beginVoiceEnrolment() {
        VoicePrintStore.shared.beginEnrolment()
        Task { await ears.beginVoiceEnrolment() }
    }

    /// Said out loud, because a silent success and a silent failure look
    /// exactly the same from the outside.
    func voiceEnrolmentFinished() {
        say("I know your voice now.")
    }

    func cancelVoiceEnrolment() { ears.cancelVoiceEnrolment() }

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
        openConversation()
        if !isConversing { scheduleDismiss(after: 15) }
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
                    if !self.ears.partial.isEmpty {
                        self.heard = self.ears.partial
                        // Show it as soon as words arrive. In a conversation
                        // there is no wake to open the HUD, so without this
                        // Ego looks asleep for as long as you are talking.
                        self.show()
                    }
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
        if pending != nil {
            if let decision = ConfirmWords.decide(command) {
                decision ? confirmPending() : cancelPending()
                return
            }
            // A question is outstanding, and the microphone is open to hear
            // the answer — so everything else arriving now is the room talking,
            // not an instruction. Keep waiting rather than running it.
            EgoLog.trace("waiting for an answer, ignoring: \(command)")
            heard = ""
            Task { [weak self] in await self?.ears.beginFollowUp() }
            return
        }

        // "Stop" — you didn't mean to summon it. A false wake has to cost one
        // word to undo, and that word must not be interpreted as anything
        // else: this is checked before the grammar, so "stop" here never
        // reaches the media rules.
        if Self.isDismissal(command) {
            EgoLog.trace("dismissed by voice")
            voice.stop()                    // cut it off mid-sentence if it's talking
            dismiss()
            return
        }
        // "Yes" while Ego is still working out what to ask is an answer to a
        // question that hasn't been asked yet. Dropping it is the safe move:
        // sending it to the model would turn a confirmation into a command,
        // and auto-applying it would run something the user never heard read
        // back — which is the entire point of the gate.
        if thinkTask != nil, ConfirmWords.decide(command) != nil {
            EgoLog.trace("ignoring “\(command)” — nothing to answer yet")
            return
        }

        // Any command opens the floor, typed or spoken, so the two paths
        // behave identically. A no-op unless the setting is on.
        openConversation()

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
        thinkCount += 1
        let turn = thinkCount
        thinkTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.planner.think(command)
            guard !Task.isCancelled else { return }
            // Only the newest turn may clear the flag; an older one finishing
            // late must not make Ego look idle while it is still thinking.
            if self.thinkCount == turn { self.thinkTask = nil }
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
            if !SettingsStore.shared.egoSpeakReplies { finishedSpeaking() }
            return
        }

        phase = .speaking
        say(result.spoken)
        if isConversing {
            // Stay up: the conversation closes when you say so, or when it
            // has heard nothing for a while.
            openConversation()
            // With spoken replies off there is no "finished speaking" moment
            // to reopen the ears from, so do it here instead.
            if !SettingsStore.shared.egoSpeakReplies { finishedSpeaking() }
        } else {
            scheduleDismiss(after: 2.6)
        }
    }

    /// Speaks a sample in the currently chosen voice, regardless of whether
    /// spoken replies are switched on — it's a preview, not a reply.
    func speakSample() {
        let name = SettingsStore.shared.egoWakeName
        voice.speak("\(name.prefix(1).uppercased() + name.dropFirst()) here. Volume thirty, terminal open.",
                    voiceIdentifier: SettingsStore.shared.egoVoiceIdentifier,
                    rate: SettingsStore.shared.egoSpeechRate)
    }

    /// Ego has stopped talking. The microphone reopens — and if the
    /// conversation is still open, so does the floor: the next thing said is
    /// taken as a command or an answer, with no wake word in front of it.
    ///
    /// This is what makes a held confirmation answerable at all. Before it,
    /// the ears went straight back to waiting for "hey ego", so "confirm" was
    /// never heard and every question timed out unanswered.
    private func finishedSpeaking() {
        ears.resumeAfterSpeaking()
        guard isActive, holdsFloor else { return }
        Task { [weak self] in
            // After the tap unmutes, or the follow-up captures the tail of
            // Ego's own reply still in the analyser.
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, self.holdsFloor, self.isActive else { return }
            await self.ears.beginFollowUp()
        }
    }

    /// A question Ego has asked must be answerable without saying its name
    /// again — that is not a mode, it's the difference between a working
    /// confirmation and one that always times out.
    private var holdsFloor: Bool { pending != nil || isConversing }

    /// Ego stays up until you dismiss it, rather than closing after every
    /// reply. Opt-in: one "hey ego" starting a whole conversation is lovely
    /// when you want it and an open microphone when you don't.
    private func openConversation() {
        guard SettingsStore.shared.egoConversation else { return }
        isConversing = true
        // No idle timer: in this mode Ego stays until dismissed, by design.
        idleTask?.cancel(); idleTask = nil
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
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled, let self, self.pending != nil else { return }
            self.pending = nil
            self.deliver(ActionResult("Cancelled."))
        }
    }

    // MARK: - HUD

    private func show() {
        dismissTask?.cancel()
        // With the panel already open you can see everything; replacing it
        // with Ego's strip would take away what you were looking at. The
        // waveform along the panel's top edge is enough, and the answer comes
        // by voice.
        guard NotchPanelController.current?.stateController.state != .expanded else {
            EgoLog.trace("panel is open — showing the inline wave instead")
            return
        }
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
        openConversation()
        // Single-command mode has no natural end while nothing is said, so it
        // keeps the old safety net.
        if !isConversing { scheduleDismiss(after: 15) }
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
        idleTask?.cancel(); idleTask = nil
        isConversing = false
        pending = nil
        phase = .idle
        heard = ""
        EgoLog.trace("hud: user took the panel back")
    }

    /// A wake phrase with nothing after it. Retire promptly instead of sitting
    /// on the 15-second safety net — a half-heard "hey ego" shouldn't park a
    /// panel over the user's screen.
    private func captureEndedEmpty() {
        guard phase == .listening || pending != nil else { return }
        // Inside an open conversation, silence is just silence: hold the floor
        // and let the idle timer decide when it's over.
        if holdsFloor, isActive {
            show()          // also refreshes the panel's watchdog
            Task { [weak self] in await self?.ears.beginFollowUp() }
            return
        }
        guard pending == nil else { return }
        scheduleDismiss(after: 0.5)
    }

    /// Close the HUD immediately (Esc, or the user clicking away).
    func dismiss() {
        dismissTask?.cancel()
        confirmTask?.cancel()
        idleTask?.cancel(); idleTask = nil
        isConversing = false
        // The HUD closing is not the same as Ego letting go: an armed
        // follow-up would carry on taking everything said in the room as a
        // command. This is what "dismiss" has to mean.
        ears.endCapture()
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
    /// Answers arrive as a transcript of a person talking, not as button
    /// presses, so the lists are generous — and cover the Hindi the user
    /// actually speaks, because "nahi" meaning "no" and being heard as nothing
    /// would run the command.
    private static let yes = [
        "confirm", "confirmed", "yes", "yeah", "yep", "yup", "sure", "correct",
        "do it", "go ahead", "go on", "run it", "run", "okay", "ok", "affirmative",
        "please do", "yes please", "haan", "haa", "ha", "theek hai", "thik hai",
        "kar do", "karo", "chalao", "bilkul",
    ]
    /// Deliberately longer than the yes list: when Ego is unsure, not doing it
    /// is always the cheaper mistake.
    private static let no = [
        "cancel", "cancelled", "no", "nope", "nah", "stop", "dont", "do not",
        "never mind", "nevermind", "forget it", "leave it", "skip it", "abort",
        "decline", "declined", "negative", "no thanks", "no thank you", "wait",
        "hold on", "not now", "nahi", "nahin", "mat karo", "rehne do", "ruko",
        "band karo", "chodo",
    ]

    /// true = go, false = cancel, nil = not an answer at all.
    static func decide(_ text: String) -> Bool? {
        // Apostrophes are stripped rather than spaced, so "don't" reads as
        // "dont" and matches the list.
        let normalised = WakePhrase.normalise(text)
        // "no" is checked first: "no, go ahead" is a refusal with a stray verb
        // in it, and the opposite reading is the expensive one.
        if no.contains(where: { normalised == $0 || normalised.hasPrefix($0 + " ") }) { return false }
        if yes.contains(where: { normalised == $0 || normalised.hasPrefix($0 + " ") }) { return true }
        return nil
    }
}

/// EGO_DEBUG=1 writes a trace beside the app's other data. The developer
/// can't always test by talking to the machine, so the pipeline has to be
/// readable after the fact.
///
/// Two rules, because this file records what was said in a room:
///   • It is CAPPED. An uncapped log of everything a microphone heard is not
///     a debug aid, it's a recording.
///   • Raw transcripts — the only lines that contain speech that was never a
///     command — need EGO_DEBUG_TRANSCRIPT as well, so the ordinary trace can
///     be left on without keeping a record of the room.
enum EgoLog {
    nonisolated private static let limit = 256 * 1024

    nonisolated static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["EGO_DEBUG"] != nil
    }

    /// Everything heard, not just what was meant for Ego. Deliberately a
    /// second switch.
    nonisolated static var recordsTranscripts: Bool {
        isEnabled && ProcessInfo.processInfo.environment["EGO_DEBUG_TRANSCRIPT"] != nil
    }

    nonisolated static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EgoNotch/ego.log")
    }

    nonisolated static func trace(_ message: String) {
        guard isEnabled else { return }
        let line = "\(Date()) \(message)\n"
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? Data(line.utf8).write(to: url)
            return
        }
        handle.seekToEndOfFile()
        try? handle.write(contentsOf: Data(line.utf8))
        let size = handle.offsetInFile
        try? handle.close()
        if size > limit { truncate() }
    }

    /// Keeps the most recent half and throws the rest away — the old end of a
    /// debug log is never the interesting part.
    private nonisolated static func truncate() {
        guard let data = try? Data(contentsOf: url), data.count > limit else { return }
        let tail = data.suffix(limit / 2)
        // Start at a line boundary so the file never opens mid-sentence.
        let start = tail.firstIndex(of: UInt8(ascii: "\n")).map { tail.index(after: $0) } ?? tail.startIndex
        try? Data(tail[start...]).write(to: url)
    }

    /// Settings offers this: the log is the one place Ego keeps anything.
    nonisolated static func erase() {
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated static var sizeText: String? {
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int, size > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
