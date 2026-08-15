import AVFoundation
import AppKit
import Observation
import Speech

/// Listening: microphone → transcript → "hey ego" → a finished command.
///
/// Owns the decision of when an utterance has *ended*, which is the part that
/// makes a voice assistant feel fast or broken. Three signals race: silence in
/// the transcript, a final result, and a hard cap.
@MainActor
@Observable
final class EgoEars {
    enum Status: Equatable {
        case off
        case preparing(String)
        case listening          // waiting for the wake phrase
        case capturing          // wake heard, taking the command
        case blocked(String)    // permission or model missing
    }

    private(set) var status: Status = .off
    /// The live partial, shown in the HUD while you talk.
    private(set) var partial = ""
    private(set) var level: Double = 0

    /// The newest transcript, kept so push-to-talk knows what was already said.
    @ObservationIgnored private var latestTranscript = ""

    /// A finished command, ready for the brain.
    var onCommand: ((String) -> Void)?
    /// The wake phrase landed — show the listening HUD immediately, rather
    /// than only once the whole sentence is finished.
    var onWake: (() -> Void)?
    /// Woken, but nothing followed.
    var onIdle: (() -> Void)?

    @ObservationIgnored private let tap = EgoAudioTap()
    @ObservationIgnored private let transcriber = EgoTranscriber()
    @ObservationIgnored private var meterPump: Task<Void, Never>?
    @ObservationIgnored private var endpoint: Task<Void, Never>?
    @ObservationIgnored private var lastCommandText = ""
    @ObservationIgnored private var acceptedGeneration: UInt64 = 0
    @ObservationIgnored private var wakeCooldown = Date.distantPast
    /// Push-to-talk skips the wake phrase, so the whole transcript is the
    /// command — there is no "hey ego" prefix to strip.
    @ObservationIgnored private var capturingWithoutWake = false
    /// Where the transcript stood when push-to-talk began, so earlier speech
    /// in the same session isn't swept into the command.
    @ObservationIgnored private var transcriptFloor = ""
    /// The last utterance actually handed on, so a re-emitted segment can be
    /// recognised as a repeat rather than obeyed twice.
    @ObservationIgnored private var lastDispatched = ""
    @ObservationIgnored private var lastDispatchedAt = Date.distantPast

    /// How long a pause means "they've finished talking".
    private let silenceWindow: Double = 1.3
    private let hardCap: Double = 12

    // MARK: - Lifecycle

    func start() async {
        guard case .off = status else { return }
        // The recogniser is primed with the name at start time, so this is
        // where a changed wake word takes effect.
        WakePhrase.setName(SettingsStore.shared.egoWakeName)
        status = .preparing("Checking microphone…")
        EgoLog.trace("ears: asking for permissions")

        guard await microphoneGranted() else {
            status = .blocked("Microphone access is off in System Settings.")
            EgoLog.trace("ears blocked: no microphone")
            return
        }
        // Speech Recognition must ALREADY be granted. Every Speech API —
        // even `supportedLocales` — blocks indefinitely without it rather
        // than failing, so there is no safe way to "try and see".
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            status = .blocked("Ego needs Speech Recognition. Grant it in Settings › Ego.")
            EgoLog.trace("ears blocked: speech not authorised "
                         + "(\(SFSpeechRecognizer.authorizationStatus().rawValue))")
            return
        }

        EgoLog.trace("ears: permissions ok, checking speech model")
        switch await transcriber.readiness() {
        case .unsupported(let why):
            status = .blocked(why)
            return
        case .needsDownload:
            status = .preparing("Downloading the speech model…")
            do { try await transcriber.installModel() }
            catch {
                status = .blocked("Couldn't download the speech model.")
                EgoLog.trace("ears blocked: model download failed")
                return
            }
        case .ready:
            break
        }

        EgoLog.trace("ears: model ready, resolving audio format")
        guard let format = await transcriber.preferredFormat() else {
            status = .blocked("No compatible audio format.")
            return
        }

        do {
            EgoLog.trace("ears: opening the microphone")
            let audio = try tap.start(targetFormat: format)
            tap.setMuted(false)
            acceptedGeneration = tap.currentGeneration
            try await transcriber.start(
                audio: audio,
                wakeName: SettingsStore.shared.egoWakeName,
                generation: { [tap] in tap.currentGeneration },
                onUpdate: { [weak self] update in
                    Task { @MainActor in self?.ingest(update) }
                })
            status = .listening
            startMeter()
            EgoLog.trace("ears: listening")
        } catch {
            tap.stop()
            status = .blocked("Couldn't open the microphone.")
            EgoLog.trace("ears failed: \(error.localizedDescription)")
        }
    }

    func stop() async {
        meterPump?.cancel(); meterPump = nil
        endpoint?.cancel(); endpoint = nil
        tap.stop()
        await transcriber.stop()
        partial = ""
        level = 0
        status = .off
        EgoLog.trace("ears: stopped")
    }

    /// True while the microphone is genuinely open — `MeetingObserver` asks,
    /// so it can tell our own listening apart from a real call.
    var isMicLive: Bool { tap.isRunning }

    /// Push-to-talk: capture one command with no wake phrase. Opens the mic
    /// first if wake-word listening is switched off, which is what makes
    /// "mic only while I'm actually talking to it" a usable mode.
    func beginPushToTalk() async {
        if case .off = status { await start() }
        await captureWithoutWake(reason: "push-to-talk", grace: 6)
    }

    /// Take the next thing said with no wake phrase in front of it — the
    /// answer to a question Ego just asked, or the next command in a
    /// conversation that is already open. Without this, "confirm" is simply
    /// never heard: the ears fall back to waiting for "hey ego" the moment a
    /// reply ends, and the confirmation times out unanswered.
    func beginFollowUp() async {
        if case .off = status { await start() }
        await captureWithoutWake(reason: "follow-up", grace: 9)
    }

    private func captureWithoutWake(reason: String, grace: Double) async {
        guard status == .listening || status == .capturing else { return }
        wakeCooldown = .distantPast
        lastCommandText = ""
        partial = ""
        capturingWithoutWake = true
        transcriptFloor = latestTranscript
        status = .capturing
        EgoLog.trace("\(reason): listening without a wake word")
        armEndpoint(grace: grace)
    }

    // MARK: - Speaking without hearing yourself

    /// Mutes at the tap, upstream of the analyser, so Ego's own voice never
    /// becomes audio at all. Anything already in flight is discarded by
    /// generation when listening resumes.
    func muteWhileSpeaking() {
        tap.setMuted(true)
    }

    func resumeAfterSpeaking() {
        guard tap.isRunning else { return }
        // A beat for the speakers to fall silent before the mic reopens.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self else { return }
            self.acceptedGeneration = self.tap.setMuted(false)
            self.partial = ""
            self.lastCommandText = ""
            EgoLog.trace("ears: unmuted, accepting generation \(self.acceptedGeneration)")
        }
    }

    // MARK: - Transcript

    private func ingest(_ update: EgoTranscriber.Update) {
        // Audio captured before Ego spoke is stale by definition.
        guard update.generation >= acceptedGeneration else { return }

        // Tracked on EVERY update, not just while listening. A follow-up marks
        // where the transcript stood when it began, and a floor left over from
        // before the last command makes the whole segment look new — which is
        // why Ego kept carrying out the same command over and over with
        // nothing said in between.
        latestTranscript = WakePhrase.normalise(update.text)

        switch status {
        case .listening:
            EgoLog.trace("raw: \(update.text)")
            guard Date() > wakeCooldown else { return }

            let command: String
            if let hit = WakePhrase.match(in: update.text,
                                          allowBareName: SettingsStore.shared.egoBareWakeWord) {
                command = hit.command
            } else if let tail = WakePhrase.afterGreetingAndName(update.text),
                      CommandGrammar.looksLikeCommand(tail) {
                // The name was mangled beyond any variant list, but a greeting
                // followed by a plain order is unambiguous. This is what saves
                // "Hey, Ele, next song" and "Hey, Pen, volume 30".
                EgoLog.trace("wake by command shape")
                command = tail
            } else {
                return
            }

            wakeCooldown = Date().addingTimeInterval(1.5)
            status = .capturing
            lastCommandText = command
            partial = command
            EgoLog.trace("wake heard, command so far: \(command)")
            onWake?()
            armEndpoint()

        case .capturing:
            let command: String
            if capturingWithoutWake {
                var whole = WakePhrase.normalise(update.text)
                // A wake phrase inside a follow-up means the recogniser has
                // handed back a segment that reaches further into the past
                // than we asked for. Whatever came after it is the newest
                // thing said, and the only part that is a command.
                if let hit = WakePhrase.match(in: whole, allowBareName: false) {
                    whole = hit.command
                }
                // `range(of:)` rather than `hasPrefix`: segments get revised,
                // so what we already consumed can end up in the middle of the
                // text rather than at the front. Missing it is what made Ego
                // carry out the previous command a second time.
                if !transcriptFloor.isEmpty, let seen = whole.range(of: transcriptFloor) {
                    whole = String(whole[seen.upperBound...])
                }
                command = whole.trimmingCharacters(in: .whitespaces)
            } else if let hit = WakePhrase.match(in: update.text,
                                                 allowBareName: SettingsStore.shared.egoBareWakeWord) {
                command = hit.command
            } else {
                // The recogniser ends a segment after the wake phrase and
                // starts the command in a fresh one, so the text arriving now
                // has no "hey ego" in it at all. Everything in this new segment
                // IS the command — discarding it (as this branch used to) is
                // why "hey ego, pause" woke Ego and then did nothing.
                command = WakePhrase.normalise(update.text)
            }

            if command != lastCommandText {
                lastCommandText = command
                partial = command
                armEndpoint()          // still talking — restart the silence clock
            }
            if update.isFinal, !command.isEmpty {
                finishUtterance()
            }

        default:
            break
        }
    }

    /// Restarted on every new word; whichever fires first wins.
    ///
    /// `grace` is how long to wait for the user to START talking. Without it,
    /// a capture armed into a silent room ends about a second later with
    /// nothing — which is exactly what happens when Ego asks a question and
    /// waits for an answer a person needs a moment to give.
    /// End-of-speech is measured on the TRANSCRIPT, not the microphone level.
    ///
    /// `ingest` re-arms this on every new word, so a timer that simply expires
    /// *is* the silence detector. The level meter was the obvious choice and
    /// the wrong one: with music playing out of the speakers the level never
    /// drops, so every command sat until the hard cap — twelve seconds to
    /// answer "pause".
    private func armEndpoint(grace: Double = 2.5) {
        endpoint?.cancel()
        // Nothing said yet means waiting for you to start; a command in
        // progress means waiting for you to finish.
        let wait = lastCommandText.isEmpty ? grace : silenceWindow
        endpoint = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self, self.status == .capturing else { return }
            self.finishUtterance()
        }
    }

    private func finishUtterance() {
        endpoint?.cancel(); endpoint = nil
        capturingWithoutWake = false
        let command = lastCommandText.trimmingCharacters(in: .whitespaces)
        lastCommandText = ""
        partial = ""
        status = .listening

        guard !command.isEmpty else {
            EgoLog.trace("wake with no command")
            onIdle?()
            return
        }
        // Belt and braces against the recogniser re-emitting a finished
        // segment: the same words, with nothing said in between, are the same
        // utterance — not a second instruction.
        if command == lastDispatched, Date().timeIntervalSince(lastDispatchedAt) < 12 {
            EgoLog.trace("same utterance again, ignoring: \(command)")
            onIdle?()
            return
        }
        lastDispatched = command
        lastDispatchedAt = Date()
        EgoLog.trace("utterance: \(command)")
        onCommand?(command)
    }

    // MARK: - Meter

    private func startMeter() {
        meterPump?.cancel()
        meterPump = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self else { return }
                self.level = self.tap.level()
            }
        }
    }

    // MARK: - Permissions

    /// Asking for Speech Recognition is a deliberate, user-initiated act from
    /// Settings — never automatic.
    ///
    /// `requestAuthorization` shows nothing at all while the app is a
    /// menu-bar agent: the alert has no application to attach to, so the
    /// callback never fires. Promoting to a regular app for the duration is
    /// what makes the prompt appear; the race guarantees the UI can't hang
    /// waiting for an answer that will never come.
    static func requestSpeechAccess() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }

        let previous = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(previous) }

        let granted = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { status in
                        continuation.resume(returning: status == .authorized)
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(45))
                return SFSpeechRecognizer.authorizationStatus() == .authorized
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        EgoLog.trace("speech access granted=\(granted)")
        return granted
    }

    private func microphoneGranted() async -> Bool {
        EgoLog.trace("mic status=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) "
                     + "speech status=\(SFSpeechRecognizer.authorizationStatus().rawValue)")
        let mic = await withCheckedContinuation { continuation in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: continuation.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            default: continuation.resume(returning: false)
            }
        }
        EgoLog.trace("mic granted=\(mic)")
        return mic
    }
}
