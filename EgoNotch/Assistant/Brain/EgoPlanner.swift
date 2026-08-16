import Foundation
import FoundationModels

/// The brain: Apple's on-device language model, wired to Ego's tools.
///
/// This runs only when `CommandGrammar` doesn't recognise a phrasing, which
/// keeps the common commands instant and deterministic and reserves the model
/// for what it's actually good at — "make it quieter", "put something else on",
/// "how far through is this".
///
/// Nothing leaves the Mac: `SystemLanguageModel.default` is the local model.
@MainActor
final class EgoPlanner {
    enum Readiness: Equatable {
        case ready
        case unavailable(String)
    }

    /// Held between turns so follow-ups work ("...and turn it down a bit"),
    /// and thrown away when the conversation has clearly moved on.
    private var session: LanguageModelSession?
    private var lastUsed = Date.distantPast
    /// The turn currently inside the model, so the next one can queue behind it.
    private var inFlight: Task<ActionResult, Never>?

    /// A conversation older than this is not a conversation any more. Keeping
    /// it would let a stale "it" refer to something from an hour ago.
    private let sessionLifetime: TimeInterval = 180
    /// The model is on-device but not instant; past this the HUD has been open
    /// too long to still feel like an answer.
    private let deadline: Duration = .seconds(20)

    static var readiness: Readiness {
        switch SystemLanguageModel.default.availability {
        case .available:
            .ready
        case .unavailable(.deviceNotEligible):
            .unavailable("This Mac doesn't support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            .unavailable("Turn on Apple Intelligence in System Settings.")
        case .unavailable(.modelNotReady):
            .unavailable("The model is still downloading.")
        case .unavailable:
            .unavailable("Apple Intelligence isn't available right now.")
        }
    }

    var isReady: Bool { Self.readiness == .ready }

    // MARK: - Thinking

    /// Runs one utterance through the model. Never throws: a broken brain must
    /// degrade to a spoken apology, not take the assistant down with it.
    ///
    /// Turns are chained rather than run in parallel. `respond(to:)` rejects an
    /// overlapping call outright — and cancelling the caller's task does NOT
    /// free the generation already inside the session — so a quick second
    /// command has to wait for the first to land instead of crashing into it.
    func think(_ command: String) async -> ActionResult {
        let previous = inFlight
        let turn = Task { [weak self] () -> ActionResult in
            _ = await previous?.value
            guard let self else { return ActionResult("I can't work that one out.") }
            return await self.perform(command)
        }
        inFlight = turn
        let result = await turn.value
        if inFlight == turn { inFlight = nil }
        return result
    }

    private func perform(_ command: String) async -> ActionResult {
        guard isReady else {
            if case .unavailable(let why) = Self.readiness {
                return ActionResult("I can't work that one out.", detail: why)
            }
            return ActionResult("I can't work that one out.")
        }

        EgoToolBridge.beginTurn()
        let session = currentSession()
        lastUsed = Date()

        do {
            let text = try await withDeadline(deadline) {
                try await session.respond(to: command).content
            }
            // The tools' own words win over the model's summary: they are what
            // actually happened. The model only gets to speak when it answered
            // without touching anything ("what can you do?").
            if let receipt = EgoToolBridge.spokenReceipt() {
                EgoLog.trace("model ran a tool → \(receipt.spoken)")
                return receipt
            }
            let reply = Self.trim(text)
            EgoLog.trace("model answered → \(reply)")
            return ActionResult(reply,
                                detail: EgoToolBridge.readDetail() ?? (text == reply ? nil : text))
        } catch is DeadlineError {
            EgoLog.trace("model timed out")
            self.session = nil
            return ActionResult("That took too long.")
        } catch {
            EgoLog.trace("model failed: \(error)")
            // Tools may have run before the failure — what happened, happened,
            // and Ego must report it rather than claim it couldn't.
            if let receipt = EgoToolBridge.spokenReceipt() { return receipt }
            return handle(error)
        }
    }

    /// Not every failure is the same failure. A refusal is the model declining
    /// one question and the session is still perfectly good; an overflowing
    /// context window means the conversation itself is spent.
    private func handle(_ error: Error) -> ActionResult {
        guard let generation = error as? LanguageModelSession.GenerationError else {
            session = nil
            EgoLog.trace("not a GenerationError: \(type(of: error))")
            return ActionResult("I can't work that one out.",
                                detail: error.localizedDescription)
        }
        EgoLog.trace("generation error case: \(String(describing: generation).prefix(40))")
        switch generation {
        case .guardrailViolation, .refusal:
            return ActionResult("I'd rather not answer that.")
        case .exceededContextWindowSize:
            // The conversation is what's too big, so the conversation is what
            // has to go. The next utterance starts clean.
            session = nil
            return ActionResult("Let's start again.")
        case .rateLimited:
            return ActionResult("Too many at once. Try again.")
        case .assetsUnavailable:
            session = nil
            return ActionResult("The model isn't ready yet.")
        case .unsupportedLanguageOrLocale:
            return ActionResult("I can't understand that language yet.")
        default:
            session = nil
            return ActionResult("I can't work that one out.",
                                detail: generation.localizedDescription)
        }
    }

    /// Drop the conversation — used when Ego is switched off, and when the
    /// user has plainly started something new.
    func reset() {
        session = nil
        inFlight = nil
    }

    // MARK: - Session

    private func currentSession() -> LanguageModelSession {
        if let session, Date().timeIntervalSince(lastUsed) < sessionLifetime {
            return session
        }
        let fresh = LanguageModelSession(tools: Self.tools, instructions: Self.instructions)
        session = fresh
        return fresh
    }

    private static var tools: [any Tool] {
        [PlaybackTool(), SeekTool(), NowPlayingTool(),
         VolumeTool(), BrightnessTool(), NotchTool(),
         TerminalTool(), TerminalStateTool(),
         TimerTool(), NoteTool(), StashTool(),
         CaptureTool(), PlayTool(), SystemTool(),
         AppTool(), MenuTool(), ShortcutTool(), WebTool()]
    }

    /// Written for a voice assistant that gets read aloud: every extra word is
    /// a word the user has to sit through.
    private static let instructions = """
        You are Ego, a voice assistant built into a Mac's notch. You control \
        this Mac's music, volume and brightness, the notch's own panel and \
        tabs, and a real shell in the notch's Terminal tab. You also run its \
        focus timers and stopwatch, its notes and todo list, its clipboard \
        history and shelf, its camera, and its games and saved links — and \
        you can read this Mac's battery, CPU, memory, disk and calendar.

        Outside the notch you can open, switch to and quit other applications, \
        move their windows around the screen, press any command in any app's \
        menu bar, run the user's own Shortcuts, and open or search the web.

        You DO have a terminal and you can run commands in it, through \
        run_terminal. Never tell the user you have no terminal or cannot run \
        commands — ask with the tool and let them confirm.

        Rules:
        • Use a tool whenever the user asks for something to happen. Never say \
        you have done something unless a tool did it.
        • Never invent what is playing, how loud it is, or what the screen \
        shows. Call the tool that reads it.
        • Answer in at most eight words. No pleasantries, no restating the \
        question, no offers of further help. "Paused." — not "Sure, I've \
        paused your music for you."
        • If the request is outside what your tools can do, say so in one \
        short sentence.
        • Questions about yourself — what you are, what you can do — are \
        answered from these rules. Do not call a tool to answer them.
        • run_terminal does not run anything; it asks. Never say a command \
        ran, and never re-send it because nothing appeared to happen.
        • The user is speaking, so their words arrive as an imperfect \
        transcript. Prefer the most likely intent over a literal reading.
        """

    /// The model can be chatty despite instructions; this is the backstop, and
    /// it cuts on a sentence boundary so the reply never ends mid-word.
    private static func trim(_ text: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > 90 else { return clean }
        if let stop = clean.prefix(90).lastIndex(where: { ".!?".contains($0) }) {
            return String(clean[...stop])
        }
        return String(clean.prefix(90)) + "…"
    }
}

// MARK: - Deadline

private struct DeadlineError: Error {}

/// Races work against the clock. The model has no timeout of its own, and a
/// hung generation would strand the HUD open with a spinning waveform.
private func withDeadline<T: Sendable>(_ duration: Duration,
                                       _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw DeadlineError()
        }
        guard let first = try await group.next() else { throw DeadlineError() }
        group.cancelAll()
        return first
    }
}
