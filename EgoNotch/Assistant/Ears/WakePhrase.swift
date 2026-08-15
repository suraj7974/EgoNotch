import Foundation

/// Finding "hey ego" in a live transcript.
///
/// Speech recognisers mangle the name relentlessly — "hey eco", "hey eggo",
/// "hey igo", "a ego" — because "Ego" isn't in their vocabulary as a name. The
/// variant list isn't padding; without it the assistant simply never wakes.
nonisolated enum WakePhrase {
    struct Hit: Sendable {
        /// Everything said after the wake phrase, which is usually the command
        /// itself: "hey ego pause the music" → "pause the music".
        let command: String
    }

    private static let greetings = ["hey", "hay", "hi", "he", "ok", "okay", "a", "ay"]
    private static let names = ["ego", "eggo", "eco", "echo", "igo", "iago", "ego's", "egos", "aygo", "ago"]

    /// Whether a bare "ego" (no greeting) counts. Off by default: "ego" is an
    /// ordinary English word and the app is called EgoNotch, so on its own it
    /// false-fires constantly.
    static func match(in transcript: String, allowBareName: Bool = false) -> Hit? {
        let words = normalise(transcript).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }

        // Scan from the end: in a long running transcript the most recent wake
        // is the one being spoken now.
        var index = words.count - 1
        while index >= 0 {
            let word = words[index]
            if names.contains(where: { close($0, word) }) {
                let hasGreeting = index > 0 && greetings.contains(where: { close($0, words[index - 1]) })
                if hasGreeting || (allowBareName && index == 0) {
                    let rest = words[(index + 1)...].joined(separator: " ")
                    return Hit(command: rest)
                }
            }
            index -= 1
        }
        return nil
    }

    static func normalise(_ raw: String) -> String {
        raw.lowercased()
            .folding(options: [.diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "[’'`]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
    }

    /// Exact, or one edit away — "eho", "ega", "heyy" all still count.
    private static func close(_ candidate: String, _ word: String) -> Bool {
        if candidate == word { return true }
        guard abs(candidate.count - word.count) <= 1 else { return false }
        return editDistance(candidate, word) <= 1
    }

    private static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
