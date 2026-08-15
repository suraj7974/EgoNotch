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

    private(set) var isActive = false

    private init() {}

    // MARK: - Lifecycle

    /// Idempotent: `syncActivation()` fires these on launch, on quit, and on
    /// every unrelated module toggle.
    func activate() {
        guard !isActive else { return }
        isActive = true
        EgoLog.trace("activated")
        // P1 starts the microphone here. P0 answers typed commands only.
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        dismiss()
        EgoLog.trace("deactivated")
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

        // P2 replaces this with the on-device model.
        EgoLog.trace("no grammar match")
        deliver(ActionResult("I don't know that one yet.",
                             detail: "Nothing in the command grammar matched “\(command)”."))
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
            return
        }

        phase = .speaking
        scheduleDismiss(after: 2.6)
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
        NotchPanelController.current?.stateController.beginAssistant()
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.pending == nil else { return }
            self.phase = .idle
            self.heard = ""
            NotchPanelController.current?.stateController.endAssistant()
        }
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
