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

    /// Every one of these was observed coming out of the recogniser for a
    /// clearly-spoken "ego". The name is rare, so the language model reaches
    /// for a common word instead — "eagle" and "you go" are the usual two.
    private static let names = [
        "ego", "eggo", "eco", "echo", "igo", "iago", "egos",
        "aygo", "ago", "eagle", "igloo", "yugo", "ika", "hego"
    ]

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
            // The name is often split in two — "you go", "e go", "a go" — so
            // the pair is tested before the single word, longest match first.
            if index + 1 < words.count, isName(words[index] + words[index + 1]),
               hasGreeting(before: index, in: words)
                   || (allowBareName && index == 0 && isStrictName(words[index] + words[index + 1])) {
                return Hit(command: words[(index + 2)...].joined(separator: " "))
            }
            if isName(words[index]),
               hasGreeting(before: index, in: words)
                   || (allowBareName && index == 0 && isStrictName(words[index])) {
                return Hit(command: words[(index + 1)...].joined(separator: " "))
            }
            index -= 1
        }
        return nil
    }

    private static func isName(_ word: String) -> Bool {
        names.contains { close($0, word) }
    }

    /// Without a greeting in front, the loose variants are far too eager —
    /// "you go" and "eagle" turn ordinary conversation into a wake. Bare-name
    /// mode accepts only the name itself.
    private static func isStrictName(_ word: String) -> Bool {
        word == "ego" || word == "eggo"
    }

    /// Exact, deliberately: greetings are everyday words the recogniser never
    /// gets wrong, and fuzzing them turns "the eagle has landed" into a wake.
    private static func hasGreeting(before index: Int, in words: [String]) -> Bool {
        index > 0 && greetings.contains(words[index - 1])
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
