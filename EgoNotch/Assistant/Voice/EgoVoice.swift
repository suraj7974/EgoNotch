import AVFoundation

/// Ego speaking.
///
/// `nonisolated` because `AVSpeechSynthesizerDelegate` callbacks arrive off the
/// main actor — the same isolation rule the audio tap and camera frames follow.
/// The owner is told when speech ends so it can un-mute the microphone.
nonisolated final class EgoVoice: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var speaking = false

    /// Called when the last utterance finishes (or is cancelled).
    var onFinish: (@Sendable () -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool {
        lock.lock(); defer { lock.unlock() }
        return speaking
    }

    func speak(_ text: String, voiceIdentifier: String?, rate: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lock.lock(); speaking = true; lock.unlock()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = Float(min(max(rate, 0.3), 0.7))
        utterance.postUtteranceDelay = 0
        utterance.voice = Self.voice(for: voiceIdentifier)
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finish()
    }

    /// The voices Siri itself is built from. Apple never exposes Siri as a
    /// selectable voice to third-party apps, but these are the same recordings
    /// behind a different name — so "as close to Siri as an app can get" means
    /// picking one of these, at the best quality installed.
    private static let siriFamily: Set<String> =
        ["ava", "zoe", "evan", "nathan", "samantha", "serena", "daniel", "karen", "moira", "rishi"]

    /// Ranked: Siri's own voices first, then quality — the compact defaults
    /// sound like a 2005 GPS, which undercuts everything else about Ego.
    static func bestAvailable() -> AVSpeechSynthesisVoice? {
        let english = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        return english.max { first, second in rank(first) < rank(second) }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// Quality dominates — a compact Ava still sounds robotic — and among
    /// equals a Siri voice wins.
    private static func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
        let quality = switch voice.quality {
        case .premium: 4
        case .enhanced: 2
        default: 0
        }
        let siri = siriFamily.contains(voice.name.lowercased()) ? 1 : 0
        return quality + siri
    }

    private static func voice(for identifier: String?) -> AVSpeechSynthesisVoice? {
        if let identifier, !identifier.isEmpty,
           let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            return chosen
        }
        return bestAvailable()
    }

    private func finish() {
        lock.lock()
        let wasSpeaking = speaking
        speaking = false
        lock.unlock()
        if wasSpeaking { onFinish?() }
        EgoLog.trace("voice: finished (wasSpeaking=\(wasSpeaking))")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didStart utterance: AVSpeechUtterance) {
        EgoLog.trace("voice: started")
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        finish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        finish()
    }
}
