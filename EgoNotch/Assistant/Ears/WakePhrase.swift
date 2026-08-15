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

    /// No "a" or "ay": they're one letter of noise away from ordinary speech,
    /// and turn "I need a Jarvis reference" into a wake.
    private static let greetings = ["hey", "hay", "hi", "he", "ok", "okay"]

    /// The name Ego currently answers to, and every way the recogniser is
    /// known to write it. Set from Settings; read on the audio path, so it is
    /// a plain stored value rather than a lookup.
    nonisolated(unsafe) private static var names = variants(for: "ego")
    /// The names exactly as chosen, for bare-name mode — the generated
    /// variants are far too loose to fire without a greeting in front.
    nonisolated(unsafe) private static var chosen: Set<String> = ["ego"]

    /// Every word Ego answers to: the one picked in Settings plus any the user
    /// has added themselves. All of them are live at once, so when the
    /// recogniser keeps writing your name a particular way you add that
    /// spelling and it works — no build, no new variant table from me.
    static func setNames(_ requested: [String]) {
        let cleaned = requested
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let primary = cleaned.isEmpty ? ["ego"] : cleaned
        chosen = Set(primary)
        names = primary.flatMap { variants(for: $0) }
    }

    /// The observed misrecognitions, per name. Everything here was seen coming
    /// out of the recogniser for a clearly-spoken wake phrase — "eagle" and
    /// "you go" for Ego, "series" and "sorry" for Siri.
    private static func variants(for name: String) -> [String] {
        switch name.lowercased() {
        case "zoro":
            // The recogniser knows "Zorro" far better than "Zoro", and turns a
            // soft second syllable into "zero" constantly — both have to count.
            return ["zoro", "zorro", "zero", "zora", "sora", "soro", "sorrow",
                    "toro", "zaro", "zuro", "xoro", "zorow", "zorros", "tsoro"]
        case "siri":
            return ["siri", "siree", "sirri", "syria", "series", "sorry", "sari", "cherry", "seri"]
        case "notch":
            return ["notch", "nach", "knotch", "nacho", "notche", "gnocchi", "naach"]
        case "jarvis":
            return ["jarvis", "jervis", "javis", "jarvice", "jarvish", "charvis",
                    "harvis", "starvis", "service", "jarvi", "chavez", "javez",
                    "shavez", "charvez"]
        case "edith":
            return ["edith", "edit", "edits", "eadith", "adith", "aditi",
                    "eddie", "edie", "ediths", "edif"]
        case "friday":
            return ["friday", "fryday", "freeday", "frida", "fridays",
                    "friyay", "priday", "freeda"]
        case "ego":
            return ["ego", "eggo", "eco", "echo", "igo", "iago", "egos",
                    "aygo", "ago", "eagle", "igloo", "yugo", "ika", "hego",
                    "ele", "elo", "you", "ergo", "igor"]
        default:
            return generated(for: name.lowercased())
        }
    }

    /// A name nobody wrote a table for. The recogniser's mistakes are not
    /// random — it swaps letters that sound alike and adds or drops a trailing
    /// one — so these cover the common slips, and `close` below still allows a
    /// character of drift on top.
    private static func generated(for name: String) -> [String] {
        var out: Set<String> = [name, name + "s", name + "e"]
        if name.count > 3 { out.insert(String(name.dropLast())) }

        // Letters the recogniser trades for one another.
        let swaps = [("c", "k"), ("k", "c"), ("s", "z"), ("z", "s"), ("ph", "f"),
                     ("f", "ph"), ("qu", "kw"), ("kw", "qu"), ("i", "y"), ("y", "i"),
                     ("ee", "i"), ("oo", "u")]
        for (from, to) in swaps where name.contains(from) {
            out.insert(name.replacingOccurrences(of: from, with: to))
        }
        return Array(out)
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
        chosen.contains(word)
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

    /// Exact, or a slip away — "eho", "ega", "heyy" all still count.
    ///
    /// Long names get two characters of tolerance rather than one: there is
    /// more of them to get wrong, and less chance that a two-edit neighbour is
    /// a real English word someone might say.
    private static func close(_ candidate: String, _ word: String) -> Bool {
        if candidate == word { return true }
        let allowed = candidate.count >= 6 ? 2 : 1
        guard abs(candidate.count - word.count) <= allowed else { return false }
        return editDistance(candidate, word) <= allowed
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
