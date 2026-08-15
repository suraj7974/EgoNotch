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
    @ObservationIgnored private var wokeAt = Date.distantPast
    @ObservationIgnored private var capTask: Task<Void, Never>?
    /// When the microphone first heard speech, for measuring the lag.
    @ObservationIgnored private var speechHeardAt = Date.distantPast
    /// When the first word of this utterance arrived.
    @ObservationIgnored private var speechStartedAt = Date.distantPast

    /// How long a pause means "they've finished talking". Every command waits
    /// this long before anything happens, so it is the single biggest
    /// contributor to Ego feeling slow — kept just long enough to survive the
    /// gap between two words.
    private let silenceWindow: Double = 0.85
    /// The longest an utterance may take before Ego acts on what it has. With
    /// music in the room the transcript never stops changing, so this is what
    /// actually ends most commands — twelve seconds felt broken.
    private let hardCap: Double = 6

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
        speechStartedAt = .distantPast
        // Follow-ups have no wake of their own; without this the cap below
        // would measure from the *previous* wake and cut them off instantly.
        wokeAt = Date()
        EgoLog.trace("\(reason): listening without a wake word")
        armEndpoint(grace: grace)
    }

    /// Teaching the voice: record continuously while the passage is read.
    ///
    /// Nothing here depends on transcription or on detecting where one
    /// utterance ends. Both of those were tried and both failed — the first
    /// because it needed the wake word recognised, which is the very thing
    /// being worked around, and the second because a burst detector tuned by
    /// guesswork never fired at all. Recording plain audio cannot fail that
    /// way; the silences are dropped later, when the frames are measured.
    func beginVoiceEnrolment() async {
        if case .off = status { await start() }
        await captureWithoutWake(reason: "enrolment", grace: 12)
    }

    func cancelVoiceEnrolment() {
        VoicePrintStore.shared.cancelEnrolment()
        endCapture()
    }

    /// Stop taking commands and go back to waiting for the wake word.
    ///
    /// The microphone stays open, because "call me again" has to work — but
    /// nothing said counts as an instruction until the wake phrase lands.
    /// Without this, dismissing Ego closed the HUD while an armed follow-up
    /// carried on listening to the room.
    func endCapture() {
        endpoint?.cancel(); endpoint = nil
        guard status == .capturing else { return }
        capturingWithoutWake = false
        lastCommandText = ""
        partial = ""
        // Everything heard so far is history now, so the next capture doesn't
        // sweep it up.
        transcriptFloor = latestTranscript
        // Short: this only exists to stop the tail of the last utterance
        // re-triggering, and a full second of deafness right after "dismiss"
        // reads as Ego being slow to come back.
        wakeCooldown = Date().addingTimeInterval(0.4)
        status = .listening
        EgoLog.trace("done — back to waiting for the wake word")
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
            if EgoLog.recordsTranscripts { EgoLog.trace("raw: \(update.text)") }
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

            // While teaching, Ego must not act on what it hears — the samples
            // are taken by the enrolment pump, which listens for *speech*
            // rather than waiting for the recogniser to spell the name right.
            if VoicePrintStore.shared.isEnrolling { return }

            // The gate, on the wake phrase itself — the one thing said the
            // same way every time, which is what makes comparing it possible
            // at all. "Dismiss" is never gated: being unable to call Ego off
            // is worse than a stranger being able to shut it up.
            if SettingsStore.shared.egoVoiceMatch, VoicePrintStore.shared.isEnrolled,
               let heard = tap.recentAudio(seconds: VoicePrintStore.verifyWindow),
               !VoicePrintStore.shared.accepts(samples: heard.samples,
                                               sampleRate: heard.sampleRate) {
                wakeCooldown = Date().addingTimeInterval(1.0)
                return
            }

            wakeCooldown = Date().addingTimeInterval(1.5)
            status = .capturing
            wokeAt = Date()
            speechStartedAt = Date()
            lastCommandText = command
            partial = command
            let lag = Date().timeIntervalSince(speechHeardAt)
            EgoLog.trace(lag < 8
                         ? String(format: "wake heard %.0f ms after you started speaking, "
                                  + "command so far: %@", lag * 1000, command)
                         // With music playing the level never falls back to
                         // silence, so there is no onset to measure from.
                         : "wake heard (no quiet moment to measure from), command so far: \(command)")
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
                if lastCommandText.isEmpty, !command.isEmpty { speechStartedAt = Date() }
                lastCommandText = command
                partial = command
                // A finished-sounding command waits only long enough to be
                // sure nothing follows it. Acting on the very first match was
                // faster still, but "play" is also the start of "play snake" —
                // a quarter of a second is the difference between quick and
                // wrong.
                let settle = CommandGrammar.isComplete(command) ? 0.4 : nil
                armEndpoint(settle: settle)
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
    private func armEndpoint(grace: Double = 2.5, settle: Double? = nil) {
        endpoint?.cancel()
        // Nothing said yet means waiting for you to start; a command in
        // progress means waiting for you to finish.
        let wait = lastCommandText.isEmpty ? grace : (settle ?? silenceWindow)
        endpoint = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self, self.status == .capturing else { return }
            self.finishUtterance()
        }
        // A cap measured from the wake, not from this re-arm. Every new word
        // restarts the timer above, so with music playing — the recogniser
        // endlessly revising lyrics — the utterance never settled at all, and
        // commands took anywhere from four to thirty-six seconds to land.
        // Measured from the first WORD, not from when the capture opened. A
        // follow-up spends most of its life waiting in silence, so timing the
        // cap from the open truncated real commands — "dismiss" arrived as
        // "dism". Nothing said yet means nothing to cap; the grace above ends
        // an empty capture on its own.
        capTask?.cancel()
        guard speechStartedAt > .distantPast else { return }
        let remaining = hardCap - Date().timeIntervalSince(speechStartedAt)
        capTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(remaining, 0.5)))
            guard !Task.isCancelled, let self, self.status == .capturing else { return }
            EgoLog.trace("utterance capped — taking what there is")
            self.finishUtterance()
        }
    }

    private func finishUtterance() {
        endpoint?.cancel(); endpoint = nil
        capTask?.cancel(); capTask = nil

        // Teaching: the utterance that just ended is one repetition of the
        // phrase. Taken here rather than from the wake matcher, because this
        // is the path that reliably fires — the transcript can say anything.
        if VoicePrintStore.shared.isEnrolling {
            capturingWithoutWake = false
            let audio = tap.recentAudio(seconds: VoicePrintStore.verifyWindow)
            let done = audio.map {
                VoicePrintStore.shared.addSample(samples: $0.samples, sampleRate: $0.sampleRate)
            } ?? false
            partial = ""
            lastCommandText = ""
            status = .listening
            if done {
                EgoAssistant.shared.voiceEnrolmentFinished()
            } else {
                // Straight back to listening for the next repetition.
                Task { [weak self] in await self?.beginVoiceEnrolment() }
            }
            return
        }
        capturingWithoutWake = false
        var command = lastCommandText.trimmingCharacters(in: .whitespaces)
        // A stray wake phrase can still be sitting in front of the command
        // when the recogniser revises a segment it had already finished.
        // Stripping it here means "heygo pause" and "hey ego pause" — the same
        // words, transcribed twice — both reduce to "pause", so the repeat
        // guard below recognises the second one for what it is.
        if let hit = WakePhrase.match(in: command), !hit.command.isEmpty {
            command = hit.command
        }
        lastCommandText = ""
        partial = ""
        status = .listening

        guard !command.isEmpty else {
            EgoLog.trace("wake with no command")
            onIdle?()
            return
        }
        // One sentence, one command. The recogniser keeps a whole segment
        // alive and revises it, so acting on "play" and then seeing "play the
        // song" arrive is the SAME sentence growing — not a second order. That
        // is how "hey zoro play the song" ran play, then play again, then
        // pause. Either text containing the other means it is the same
        // utterance still being written down.
        if !lastDispatched.isEmpty, Date().timeIntervalSince(lastDispatchedAt) < 12,
           command.hasPrefix(lastDispatched) || lastDispatched.hasPrefix(command) {
            EgoLog.trace("still the same sentence, ignoring: \(command)")
            onIdle?()
            return
        }
        lastDispatched = command
        lastDispatchedAt = Date()
        // The gate, judged on everything just said rather than on the wake
        // word alone. A second of "hey zoro" is too small a sample to tell two
        // people apart; wake word plus command is three times the evidence.
        EgoLog.trace(String(format: "utterance: %@  (%.0f ms after waking)",
                            command, Date().timeIntervalSince(wokeAt) * 1000))
        onCommand?(command)
    }

    // MARK: - Meter

    private func startMeter() {
        meterPump?.cancel()
        meterPump = Task { [weak self] in
            var quiet = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self else { return }
                let level = self.tap.level()
                self.level = level
                // When speech starts, so the gap until the wake fires can be
                // measured rather than guessed at. That gap is the speech
                // recogniser's own lag, and it is the only part of "slow to
                // activate" left that isn't ours.
                if quiet, level > 0.25 {
                    self.speechHeardAt = Date()
                    quiet = false
                } else if level < 0.12 {
                    quiet = true
                }
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
