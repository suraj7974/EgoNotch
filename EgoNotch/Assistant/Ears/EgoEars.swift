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

    /// How long a pause means "they've finished talking".
    private let silenceWindow: Double = 1.0
    private let hardCap: Double = 12

    // MARK: - Lifecycle

    func start() async {
        guard case .off = status else { return }
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
        guard status == .listening || status == .capturing else { return }
        wakeCooldown = .distantPast
        lastCommandText = ""
        partial = ""
        capturingWithoutWake = true
        transcriptFloor = latestTranscript
        status = .capturing
        EgoLog.trace("push-to-talk armed")
        armEndpoint()
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
        }
    }

    // MARK: - Transcript

    private func ingest(_ update: EgoTranscriber.Update) {
        // Audio captured before Ego spoke is stale by definition.
        guard update.generation >= acceptedGeneration else { return }

        switch status {
        case .listening:
            latestTranscript = WakePhrase.normalise(update.text)
            guard Date() > wakeCooldown,
                  let hit = WakePhrase.match(in: update.text,
                                             allowBareName: SettingsStore.shared.egoBareWakeWord)
            else { return }
            wakeCooldown = Date().addingTimeInterval(1.5)
            status = .capturing
            lastCommandText = hit.command
            partial = hit.command
            EgoLog.trace("wake heard, command so far: \(hit.command)")
            armEndpoint()

        case .capturing:
            let command: String
            if capturingWithoutWake {
                // Everything said since the key was pressed.
                let whole = WakePhrase.normalise(update.text)
                command = whole.hasPrefix(transcriptFloor) && !transcriptFloor.isEmpty
                    ? String(whole.dropFirst(transcriptFloor.count)).trimmingCharacters(in: .whitespaces)
                    : whole
            } else if let hit = WakePhrase.match(in: update.text,
                                                 allowBareName: SettingsStore.shared.egoBareWakeWord) {
                command = hit.command
            } else {
                return
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
    private func armEndpoint() {
        endpoint?.cancel()
        let deadline = Date().addingTimeInterval(hardCap)
        endpoint = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard let self, self.status == .capturing else { return }
                if Date() > deadline { self.finishUtterance(); return }
                // Silence is measured from the last *change* in the command.
                if self.tap.level() < 0.06 { break }
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(self?.silenceWindow ?? 1))
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
            return
        }
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
