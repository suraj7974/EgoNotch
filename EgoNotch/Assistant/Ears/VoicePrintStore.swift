import Foundation
import Observation

/// Who Ego answers to.
///
/// Enrolment is the wake phrase, said a few times. Two earlier designs are in
/// this file's history and both are worth remembering:
///
///   • Describing the *voice* rather than the phrase let enrolment be any
///     words at all, but on a one-second command the speaker's own readings
///     varied as much as a stranger's — measured at 0.50 to 0.99 against a
///     gate of 0.60. No threshold both let them in and kept others out.
///   • Triggering enrolment from the wake matcher, or from a hand-tuned burst
///     detector, never fired at all — the first because it needed the name
///     recognised, the second because it was reading an audio buffer that
///     turned out to be empty.
///
/// So samples now come from the machinery that demonstrably works: the same
/// endpoint detector that ends every ordinary command.
@MainActor
@Observable
final class VoicePrintStore {
    static let shared = VoicePrintStore()

    /// Enough repetitions to measure how much the speaker varies, which is
    /// what sets the threshold. More than this and teaching becomes a chore.
    static let required = 4

    /// How much audio the gate looks at — the wake phrase and a little either
    /// side. Deliberately short: the point of matching a fixed phrase is that
    /// only the phrase is compared.
    static let verifyWindow: Double = 1.8

    private(set) var isEnrolling = false
    private(set) var progress = 0
    private(set) var lastProblem: String?
    private(set) var isEnrolled = false

    @ObservationIgnored private var templates: [WakeTemplate] = []
    @ObservationIgnored private var threshold: Float = 0
    @ObservationIgnored private var pending: [WakeTemplate] = []

    private init() { load() }

    // MARK: - The gate

    /// True when this sounds like the enrolled voice saying the enrolled
    /// phrase. Open when nothing is taught: a gate with no key would lock the
    /// user out of their own assistant with no way back in by voice.
    func accepts(samples: [Float], sampleRate: Double) -> Bool {
        guard isEnrolled else { return true }
        guard let heard = WakeTemplate.make(samples: samples, sampleRate: sampleRate) else {
            EgoLog.trace("voice match: nothing to measure — allowing")
            return true
        }
        let best = templates.map { WakeTemplate.distance($0, heard) }.min() ?? .greatestFiniteMagnitude
        let verdict = best <= threshold
        EgoLog.trace(String(format: "voice match: %.2f vs %.2f — %@",
                            best, threshold, verdict ? "you" : "someone else"))
        return verdict
    }

    // MARK: - Enrolment

    func beginEnrolment() {
        pending = []
        progress = 0
        lastProblem = nil
        isEnrolling = true
        EgoLog.trace("voice enrolment: started")
    }

    func cancelEnrolment() {
        pending = []
        progress = 0
        isEnrolling = false
    }

    /// One spoken repetition. Returns true when there are enough.
    @discardableResult
    func addSample(samples: [Float], sampleRate: Double) -> Bool {
        guard isEnrolling else { return false }
        guard let template = WakeTemplate.make(samples: samples, sampleRate: sampleRate),
              template.isUsable else {
            lastProblem = "Didn't catch that one — say it again, a bit louder."
            EgoLog.trace("voice enrolment: sample unusable")
            return false
        }
        pending.append(template)
        progress = pending.count
        lastProblem = nil
        EgoLog.trace("voice enrolment: sample \(progress) of \(Self.required), "
                     + "\(template.frames.count) frames")
        guard pending.count >= Self.required else { return false }

        templates = pending
        threshold = Self.calibrate(templates)
        pending = []
        isEnrolling = false
        isEnrolled = true
        save()
        EgoLog.trace(String(format: "voice enrolment: done — gate %.2f", threshold))
        return true
    }

    func forget() {
        templates = []
        threshold = 0
        isEnrolled = false
        isEnrolling = false
        pending = []
        try? FileManager.default.removeItem(at: Self.url)
        EgoLog.trace("voice enrolment: forgotten")
    }

    var summary: String? {
        guard isEnrolled else { return nil }
        return String(format: "%d recordings, gate at %.1f", templates.count, threshold)
    }

    /// From how far apart the speaker's own repetitions land. A wide margin on
    /// top, because enrolment happens in whatever quiet the user found while
    /// commands get given over music — which shifts every measurement.
    private static func calibrate(_ templates: [WakeTemplate]) -> Float {
        var distances: [Float] = []
        for i in 0..<templates.count {
            for j in (i + 1)..<templates.count {
                distances.append(WakeTemplate.distance(templates[i], templates[j]))
            }
        }
        guard !distances.isEmpty else { return 8 }
        let worst = distances.max() ?? 0
        return min(max(worst * 1.6, 4), 26)
    }

    // MARK: - Storage

    private struct Saved: Codable {
        let templates: [WakeTemplate]
        let threshold: Float
    }

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EgoNotch/voiceprint.json")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Saved(templates: templates, threshold: threshold))
        else { return }
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: Self.url)
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.url),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              saved.templates.count >= 2 else { return }
        templates = saved.templates
        threshold = saved.threshold
        isEnrolled = true
    }
}
