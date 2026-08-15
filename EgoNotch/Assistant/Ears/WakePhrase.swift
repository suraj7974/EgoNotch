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
    /// The name Ego currently answers to, and every way the recogniser is
    /// known to write it. Set from Settings; read on the audio path, so it is
    /// a plain stored value rather than a lookup.
    nonisolated(unsafe) private static var names = variants(for: "ego")

    static func setName(_ name: String) {
        names = variants(for: name)
    }

    /// The observed misrecognitions, per name. Everything here was seen coming
    /// out of the recogniser for a clearly-spoken wake phrase — "eagle" and
    /// "you go" for Ego, "series" and "sorry" for Siri.
    private static func variants(for name: String) -> [String] {
        switch name.lowercased() {
        case "siri":
            return ["siri", "siree", "sirri", "syria", "series", "sorry", "sari", "cherry", "seri"]
        case "notch":
            return ["notch", "nach", "knotch", "nacho", "not", "notche", "gnocchi"]
        case "nova":
            return ["nova", "nover", "novo", "no va", "nava"]
        case "ego":
            return ["ego", "eggo", "eco", "echo", "igo", "iago", "egos",
                    "aygo", "ago", "eagle", "igloo", "yugo", "ika", "hego",
                    "ele", "elo", "you", "ergo", "igor"]
        default:
            // A name nobody planned for: the word itself, and the fuzzy
            // matcher below still allows a one-character slip.
            return [name.lowercased()]
        }
    }

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
            // "heygo", "heyego" — said quickly, the recogniser writes the
            // greeting and the name as a single word. Peel the greeting off.
            if let glued = splitGreeting(words[index]), isName(glued) {
                return Hit(command: words[(index + 1)...].joined(separator: " "))
            }
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

    /// "heygo" → "go". Only for greetings long enough to be unambiguous, so
    /// an ordinary word starting with "a" isn't torn in half.
    private static func splitGreeting(_ word: String) -> String? {
        for greeting in ["hey", "hay", "okay"] where word.hasPrefix(greeting) && word.count > greeting.count {
            return String(word.dropFirst(greeting.count))
        }
        return nil
    }

    /// True when a greeting sits directly in front of `index` — used by the
    /// caller's command-shaped fallback as well as by the name match.
    static func startsWithGreeting(_ transcript: String) -> Bool {
        guard let first = normalise(transcript).split(separator: " ").first else { return false }
        return greetings.contains(String(first))
    }

    /// Everything after a leading greeting: "hey pen next song" → "next song"
    /// once the second word is dropped as the misheard name.
    static func afterGreetingAndName(_ transcript: String) -> String? {
        let words = normalise(transcript).split(separator: " ").map(String.init)
        guard words.count >= 3, greetings.contains(words[0]) else { return nil }
        return words[2...].joined(separator: " ")
    }

    /// Without a greeting in front, the loose variants are far too eager —
    /// "you go" and "eagle" turn ordinary conversation into a wake. Bare-name
    /// mode accepts only the name itself, which is always the first variant.
    private static func isStrictName(_ word: String) -> Bool {
        word == names.first
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
