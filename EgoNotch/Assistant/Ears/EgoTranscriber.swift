import AVFoundation
import AppKit
import Speech

/// Live on-device transcription, wrapped so the rest of Ego sees plain text.
///
/// Uses `SpeechAnalyzer` + `SpeechTranscriber` (macOS 26) rather than the old
/// `SFSpeechRecognizer`: the legacy API is built for short dictation bursts and
/// stops after about a minute, which is useless for a wake-word listener that
/// has to run all day.
///
/// An `actor` rather than a locked class: the results loop is a long-lived
/// async sequence, and under this module's MainActor-by-default isolation it
/// would otherwise be dragged onto the main actor.
actor EgoTranscriber {
    /// Built by hand rather than from `.progressiveTranscription`, for one
    /// option that preset leaves out: **fastResults**. The measured delay
    /// between the last word arriving and Ego acting was only 365 ms — the
    /// wait a person actually feels is the recogniser deciding it is ready to
    /// speak, and this is the switch that asks it to hurry.
    private static func module(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale,
                          transcriptionOptions: [],
                          reportingOptions: [.volatileResults, .fastResults],
                          attributeOptions: [])
    }

    struct Update: Sendable {
        let text: String
        let isFinal: Bool
        /// Which listening generation produced this — anything stamped before
        /// Ego spoke is discarded, so it can't hear its own voice.
        let generation: UInt64
    }

    enum Readiness: Sendable, Equatable {
        case ready
        case needsDownload
        case unsupported(String)
    }

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var results: Task<Void, Never>?
    private var generation: UInt64 = 0

    private let locale: Locale

    /// Words to weight up: the wake phrase, then the vocabulary of the
    /// commands themselves — "boomerang" and "pomodoro" are misheard for the
    /// same reason a rare name is. The name is injected at `start`, since the
    /// user can change it.
    private static func vocabulary(name: String) -> [String] {
        // Weighting up the one active name, hard. Telling the recogniser about
        // names that aren't in use would only dilute the bias that makes the
        // real one land.
        let capitalised = name.prefix(1).uppercased() + name.dropFirst()
        return ["\(capitalised)", "Hey \(capitalised)", "hey \(capitalised)",
                "\(capitalised) pause", "\(capitalised) play"]
            + ["notch", "boomerang", "pomodoro", "shelf", "clipboard", "visualiser"]
            + installedApps + Self.jargon
    }

    /// The names of the applications actually on this Mac.
    ///
    /// Every misrecognition worth complaining about has been a proper noun the
    /// recogniser was never told existed — "github" as "geit", "chatgpt" as
    /// "chat", "zed" as "z" and "ed". It is the same problem as "Hey Ego"
    /// arriving as "Hey, Eagle", and it has the same one-line answer: say the
    /// word out loud to the recogniser before asking it to hear the word.
    private static let installedApps: [String] = {
        func apps(in directory: String) -> [String] {
            (try? FileManager.default.contentsOfDirectory(atPath: directory))?
                .filter { $0.hasSuffix(".app") }
                .map { ($0 as NSString).deletingPathExtension }
                .filter { $0.count >= 2 } ?? []
        }

        // Ordered by how likely you are to say it, NOT alphabetically: the
        // list is capped, and sorting by name meant the cap fell at "G" —
        // teaching the recogniser about Calculator while cutting Zed, Spotify,
        // Safari and Xcode, which are the ones that were being misheard.
        var ordered: [String] = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName)
        ordered += apps(in: "/Applications")
        ordered += apps(in: "/Applications/Utilities")
        ordered += apps(in: "/System/Applications")
        ordered += apps(in: "/System/Applications/Utilities")

        var seen: Set<String> = []
        // Bounded: a vocabulary of everything is a vocabulary of nothing,
        // because every hint dilutes the others.
        return ordered.filter { seen.insert($0).inserted }.prefix(70).map { $0 }
    }()

    /// Names that aren't apps on this Mac but come up constantly in commands.
    private static let jargon = [
        "GitHub", "ChatGPT", "YouTube", "Gmail", "Google", "Stack Overflow",
        "localhost", "npm", "git", "Docker", "Xcode", "Swift", "Python",
    ]

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    // MARK: - Model assets

    /// The speech model is a downloadable asset; on a fresh Mac it isn't there
    /// yet. Report that plainly instead of failing to hear anything.
    func readiness() async -> Readiness {
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            return .unsupported("Speech isn't available for \(locale.identifier).")
        }
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) })
            ? .ready : .needsDownload
    }

    func installModel() async throws {
        let module = Self.module(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }

    // MARK: - Running

    /// The audio format the analyser wants; the tap converts into it.
    func preferredFormat() async -> AVAudioFormat? {
        let module = Self.module(locale: locale)
        return await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
    }

    func start(audio: AsyncStream<AnalyzerInput>,
               wakeName: String,
               generation: @escaping @Sendable () -> UInt64,
               onUpdate: @escaping @Sendable (Update) -> Void) async throws {
        await stop()

        // Volatile partials feed the live text in the HUD and the wake
        // matcher; fast results ask for them sooner.
        let module = Self.module(locale: locale)
        transcriber = module
        _ = try? await AssetInventory.reserve(locale: locale)

        // Bias the recogniser toward the words Ego actually cares about.
        // Untold, it renders "hey ego" as "Hey, Eagle" or "Hey you go" — the
        // name is rare enough that the language model always prefers a common
        // word, and the wake phrase then never matches.
        let context = AnalysisContext()
        context.contextualStrings[.general] = Self.vocabulary(name: wakeName)

        let analyzer = SpeechAnalyzer(modules: [module])
        try? await analyzer.setContext(context)
        self.analyzer = analyzer

        results = Task {
            do {
                for try await result in module.results {
                    let text = String(result.text.characters)
                    guard !text.isEmpty else { continue }
                    onUpdate(Update(text: text,
                                    isFinal: result.isFinal,
                                    generation: generation()))
                }
            } catch {
                EgoLog.trace("transcriber ended: \(error.localizedDescription)")
            }
        }

        // The tap's stream feeds the analyser directly — no relay task.
        try await analyzer.start(inputSequence: audio)
    }

    func stop() async {
        results?.cancel(); results = nil
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        analyzer = nil
        transcriber = nil
        _ = await AssetInventory.release(reservedLocale: locale)
    }
}
