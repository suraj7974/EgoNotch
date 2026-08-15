import Foundation
import Observation

/// Who Ego answers to.
///
/// Enrolment is a passage read aloud, not a phrase repeated five times. Two
/// reasons, both learned the hard way: waiting for the recogniser to spell the
/// wake word correctly made the *fix* depend on the bug it fixes, and a burst
/// detector tuned to catch one short phrase never fired at all. Reading gives
/// ten times the data and needs nothing to be recognised.
///
/// This is a filter, not a lock. It turns away a clearly different voice —
/// someone else in the room, a podcast, the television — and it will not stop
/// a recording of you.
@MainActor
@Observable
final class VoicePrintStore {
    static let shared = VoicePrintStore()

    /// Enough speech to describe a voice. Around three sentences read aloud.
    static let secondsWanted: Double = 12

    private(set) var isEnrolling = false
    /// Seconds gathered so far, for the progress the user watches.
    private(set) var captured: Double = 0
    private(set) var lastProblem: String?
    private(set) var isEnrolled = false

    /// What to read. Chosen for phonetic spread rather than meaning — the more
    /// different sounds a voice makes, the better it is described.
    static let passage = """
        The quick brown fox jumps over the lazy dog while five wizards make \
        toxic brew. She sells sea shells by the shore, and the rain in Spain \
        stays mainly on the plain.
        """

    @ObservationIgnored private var profile: VoiceProfile?

    private init() { load() }

    // MARK: - The gate

    /// True when this utterance came from the enrolled voice. Open when
    /// nothing is enrolled: a gate with no key would lock the user out of
    /// their own assistant, with no way back in by voice.
    func accepts(samples: [Float], sampleRate: Double) -> Bool {
        guard let profile else { return true }
        guard let heard = VoiceProfile.make(samples: samples, sampleRate: sampleRate) else {
            // Unmeasurable audio is not evidence of an impostor.
            EgoLog.trace("voice match: nothing to measure — allowing")
            return true
        }
        let distance = profile.distance(to: heard)
        let verdict = distance <= profile.threshold
        EgoLog.trace(String(format: "voice match: %.3f vs %.3f — %@",
                            distance, profile.threshold, verdict ? "you" : "someone else"))
        return verdict
    }

    // MARK: - Enrolment

    func beginEnrolment() {
        captured = 0
        lastProblem = nil
        isEnrolling = true
        EgoLog.trace("voice enrolment: reading started")
    }

    func noteProgress(_ seconds: Double) {
        guard isEnrolling else { return }
        captured = min(seconds, Self.secondsWanted)
    }

    func cancelEnrolment() {
        isEnrolling = false
        captured = 0
    }

    /// Turns the recording into a profile. Returns false when there wasn't
    /// enough actual speech in it, which is the one failure worth reporting.
    @discardableResult
    func finishEnrolment(samples: [Float], sampleRate: Double) -> Bool {
        isEnrolling = false
        captured = 0
        guard let built = VoiceProfile.make(samples: samples, sampleRate: sampleRate),
              built.frameCount >= 200 else {
            lastProblem = "I didn't hear enough — read it again, a bit closer to the Mac."
            EgoLog.trace("voice enrolment: too little speech")
            return false
        }
        profile = built
        isEnrolled = true
        lastProblem = nil
        save()
        EgoLog.trace(String(format: "voice enrolment: done — %d frames, threshold %.3f",
                            built.frameCount, built.threshold))
        return true
    }

    func forget() {
        profile = nil
        isEnrolled = false
        isEnrolling = false
        captured = 0
        try? FileManager.default.removeItem(at: Self.url)
        EgoLog.trace("voice enrolment: forgotten")
    }

    /// For Settings, so it can say how well it knows the voice.
    var summary: String? {
        guard let profile else { return nil }
        return String(format: "about %.0f seconds of speech, gate at %.2f",
                      Double(profile.frameCount) / 100, profile.threshold)
    }

    // MARK: - Storage

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EgoNotch/voiceprint.json")
    }

    private func save() {
        guard let profile, let data = try? JSONEncoder().encode(profile) else { return }
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: Self.url)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.url),
              let saved = try? JSONDecoder().decode(VoiceProfile.self, from: data) else { return }
        profile = saved
        isEnrolled = true
    }
}
