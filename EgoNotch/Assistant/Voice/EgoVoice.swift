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

    /// Prefers a premium/enhanced voice — the compact default sounds like a
    /// 2005 GPS, which undercuts everything else about the assistant.
    private static func voice(for identifier: String?) -> AVSpeechSynthesisVoice? {
        if let identifier, !identifier.isEmpty,
           let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            return chosen
        }
        let english = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        return english.first { $0.quality == .premium }
            ?? english.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private func finish() {
        lock.lock()
        let wasSpeaking = speaking
        speaking = false
        lock.unlock()
        if wasSpeaking { onFinish?() }
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
