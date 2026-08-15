import Foundation
import Observation

/// Who Ego answers to.
///
/// Holds the enrolled fingerprints of the wake phrase and decides whether a
/// given utterance came from the same person. The threshold is not a number I
/// picked: it is derived from how much the user's *own* samples differ from
/// each other, so a consistent speaker gets a tight gate and a variable one
/// gets a loose one, automatically.
///
/// This is a filter, not a lock. It reliably turns away a clearly different
/// voice — someone else in the room, a podcast, the television — and it will
/// not stop a recording of you, or reliably separate you from a similar voice.
@MainActor
@Observable
final class VoicePrintStore {
    static let shared = VoicePrintStore()

    /// How many samples enrolment asks for. Five is enough to measure the
    /// user's own variation, which is what sets the threshold.
    static let required = 5

    private(set) var enrolledCount = 0
    private(set) var isEnrolling = false
    /// Samples taken so far in this enrolment run.
    private(set) var progress = 0
    /// Set when an enrolment sample was unusable, so Settings can say why.
    private(set) var lastProblem: String?

    var isEnrolled: Bool { enrolledCount >= 2 }

    @ObservationIgnored private var templates: [VoicePrint] = []
    @ObservationIgnored private var threshold: Float = 0
    @ObservationIgnored private var pending: [VoicePrint] = []

    private init() { load() }

    // MARK: - The gate

    /// True when this utterance is close enough to the enrolled voice. Open
    /// when nothing is enrolled: a gate with no key in it would lock the user
    /// out of their own assistant with no way back in by voice.
    func accepts(_ print: VoicePrint) -> Bool {
        guard isEnrolled else { return true }
        let best = templates.map { VoicePrint.distance($0, print) }.min() ?? .greatestFiniteMagnitude
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

    /// One spoken sample. Returns true when enrolment is complete.
    @discardableResult
    func addSample(_ print: VoicePrint?) -> Bool {
        guard isEnrolling else { return false }
        guard let print, print.isUsable else {
            lastProblem = "Didn't catch that — say it a little louder."
            EgoLog.trace("voice enrolment: sample rejected")
            return false
        }
        pending.append(print)
        progress = pending.count
        lastProblem = nil
        guard pending.count >= Self.required else { return false }

        templates = pending
        threshold = Self.calibrate(templates)
        enrolledCount = templates.count
        pending = []
        isEnrolling = false
        EgoAssistant.shared.endVoiceEnrolment()
        save()
        EgoLog.trace(String(format: "voice enrolment: done, threshold %.2f", threshold))
        return true
    }

    func forget() {
        templates = []
        threshold = 0
        enrolledCount = 0
        pending = []
        isEnrolling = false
        try? FileManager.default.removeItem(at: Self.url)
        EgoLog.trace("voice enrolment: forgotten")
    }

    /// The threshold comes from the user's own consistency: how far apart their
    /// five samples are from each other, plus room to spare. Someone who says
    /// it the same way every time gets a strict gate; someone who doesn't gets
    /// a forgiving one — without either of them having to tune a slider.
    private static func calibrate(_ templates: [VoicePrint]) -> Float {
        var distances: [Float] = []
        for i in 0..<templates.count {
            for j in (i + 1)..<templates.count {
                distances.append(VoicePrint.distance(templates[i], templates[j]))
            }
        }
        guard !distances.isEmpty else { return 8 }
        let mean = distances.reduce(0, +) / Float(distances.count)
        let spread = (distances.max() ?? mean) - mean
        // Deliberately generous. Measured against synthesised voices, a
        // different vocal tract sits five or six times further away than the
        // user's own day-to-day variation — so there is room to be forgiving
        // and still turn strangers away. Being turned away from your own
        // assistant is a far worse failure than a rare false accept.
        return min(max(max(mean * 2.2, mean + spread * 1.5), 4), 30)
    }

    // MARK: - Storage

    private struct Saved: Codable {
        let templates: [VoicePrint]
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
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        templates = saved.templates
        threshold = saved.threshold
        enrolledCount = saved.templates.count
    }
}
