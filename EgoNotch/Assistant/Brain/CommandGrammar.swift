import Foundation

/// The fast path: phrasings you actually use, matched deterministically.
///
/// This exists so the common commands are instant and work even when Apple
/// Intelligence is unavailable. Anything it doesn't recognise falls through to
/// the language model, which is slower but understands arbitrary phrasing.
@MainActor
enum CommandGrammar {

    /// nil = "I don't recognise this", NOT "this failed" — the caller escalates
    /// to the model rather than telling the user no.
    static func match(_ raw: String) -> ActionResult? {
        let text = normalise(raw)
        guard !text.isEmpty else { return nil }

        // Questions the shortlist genuinely answers come first.
        if let answer = queryRules(text) { return answer }

        // Then the gate: a question is not an order. The rules below match on
        // substrings, so "what was the next song we played?" contains "next
        // song" and would cheerfully skip the track. Anything still
        // interrogative at this point belongs to the model, which can tell a
        // question from an instruction.
        if isQuestion(text) { return nil }

        // Before the normalised rules, because the shell needs the raw words.
        if let terminal = terminalCommand(in: raw) { return terminal }

        for rule in rules {
            if let result = rule(text) { return result }
        }
        return nil
    }

    /// Read-only phrasings, matched before the question gate closes.
    private static let queryRules: Rule = { text in
        if text.hasAny("whats playing", "what is playing", "what song is this",
                       "who sings this", "what am i listening to", "current song") {
            return EgoActions.nowPlaying()
        }
        if text.hasAny("whats the volume", "how loud", "volume level") {
            return EgoActions.volumeReport()
        }
        // The shell already reports its directory, so this is a read — not a
        // reason to ask permission to run `pwd`.
        if text.hasAny("what directory", "which directory", "where am i",
                       "what folder am i in", "whats the current directory") {
            return EgoActions.terminalDirectory()
        }
        return nil
    }

    /// "press control c", "ctrl d", "control see" — the recogniser writes the
    /// letter as a word about as often as it writes the letter.
    private static func controlKey(in text: String) -> Character? {
        let spoken = ["see": "c", "sea": "c", "si": "c", "dee": "d", "de": "d",
                      "zed": "z", "zee": "z", "el": "l", "you": "u", "yu": "u"]
        for prefix in ["control ", "ctrl ", "control", "ctrl"] {
            guard let range = text.range(of: prefix) else { continue }
            let rest = text[range.upperBound...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " +-"))
            guard let word = rest.split(separator: " ").first.map(String.init) else { continue }
            let letter = spoken[word] ?? word
            guard letter.count == 1, let character = letter.first,
                  character.isLetter else { continue }
            return character
        }
        return nil
    }

    private static func isQuestion(_ text: String) -> Bool {
        text.hasSuffix("?")
            || text.matches("^(what|whats|which|who|whos|when|where|why|how|is|are|was|were"
                            + "|can|could|do|does|did|should|shall|will|would|tell me)\\b")
    }

    /// Does this read like an order, without carrying it out? The wake matcher
    /// asks: when the recogniser mangles the name past recognition ("Hey, Pen,
    /// next song"), a greeting followed by an unmistakable command is still
    /// clearly aimed at Ego. Deliberately strict — the text must *begin* with
    /// a command verb and be short — because song lyrics are full of "hey".
    static func looksLikeCommand(_ raw: String) -> Bool {
        let text = normalise(raw)
        guard !text.isEmpty, text.split(separator: " ").count <= 5 else { return false }
        return verbs.contains { text == $0 || text.hasPrefix($0 + " ") }
    }

    private static let verbs = [
        "pause", "play", "resume", "stop", "next", "previous", "skip", "back",
        "volume", "mute", "unmute", "louder", "quieter", "turn it", "turn the",
        "brightness", "brighter", "dimmer", "open", "close", "show", "hide",
        "switch", "whats", "what is", "how loud", "how bright",
    ]

    /// Lowercase, strip punctuation, collapse whitespace. Speech transcripts
    /// arrive with commas and stray capitals that would break naive matching.
    static func normalise(_ raw: String) -> String {
        // Apostrophes are DELETED, not replaced with a space: "what's playing"
        // has to become "whats playing", not "what s playing", or every
        // contraction in the rule table misses.
        let stripped = raw.lowercased()
            .replacingOccurrences(of: "[’'`]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9%\\s.:+-]", with: " ", options: .regularExpression)
        return stripped.split(separator: " ").joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Rules, in priority order

    private typealias Rule = (String) -> ActionResult?

    private static let rules: [Rule] = [
        terminalRules, mediaRules, volumeRules, brightnessRules, panelRules,
    ]

    /// First in the list on purpose: "run npm start" must never be read as
    /// "start" the music.
    private static let terminalRules: Rule = { text in
        // Spoken control keys, before anything else: "control c" must never be
        // typed out as words into a running process.
        if let letter = controlKey(in: text) {
            return EgoActions.terminalControlKey(letter)
        }
        if text.hasAny("stop the command", "cancel the command",
                       "interrupt it", "kill it", "kill the command") {
            return EgoActions.interruptTerminal()
        }
        if text.hasAny("what directory", "which directory", "where am i",
                       "what folder am i in") {
            return EgoActions.terminalDirectory()
        }
        return nil
    }

    /// Reads the command out of the RAW utterance, never the normalised one:
    /// `normalise` lowercases and strips slashes, and both are load-bearing in
    /// a shell. "run npm install in the terminal" → "npm install".
    private static func terminalCommand(in raw: String) -> ActionResult? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard let verb = ["run ", "execute ", "type "].first(where: { lower.hasPrefix($0) })
        else { return nil }

        var command = String(trimmed.dropFirst(verb.count))
        for tail in [" in the terminal", " in terminal", " in the shell", " for me", "."]
        where command.lowercased().hasSuffix(tail) {
            command = String(command.dropLast(tail.count))
        }
        return EgoActions.runTerminal(command.trimmingCharacters(in: .whitespaces))
    }

    private static let mediaRules: Rule = { text in
        if text.hasAny("pause", "stop the music", "stop music", "shut up the music") {
            return EgoActions.mediaPause()
        }
        if text.hasAny("resume", "unpause", "continue playing", "keep playing") {
            return EgoActions.mediaPlay()
        }
        if text.matches("^(play|start)( the)?( music| song| it)?$") {
            return EgoActions.mediaPlay()
        }
        if text.hasAny("play pause", "toggle music", "toggle playback") {
            return EgoActions.mediaToggle()
        }
        if text.hasAny("next track", "next song", "skip this", "skip song", "skip track")
            || text.matches("^(next|skip)$") {
            return EgoActions.mediaNext()
        }
        if text.hasAny("previous track", "previous song", "go back a song", "last song")
            || text.matches("^(previous|back)$") {
            return EgoActions.mediaPrevious()
        }
        if text.hasAny("restart the song", "start the song over", "from the beginning",
                       "restart track", "play it again") {
            return EgoActions.mediaRestart()
        }
        if text.hasAny("whats playing", "what is playing", "what song is this",
                       "who sings this", "what am i listening to", "current song") {
            return EgoActions.nowPlaying()
        }
        // "skip forward 30 seconds" / "back 10 seconds"
        if let seconds = text.firstNumber,
           text.hasAny("forward", "ahead", "skip ahead"), text.contains("second") {
            return EgoActions.mediaSeek(seconds: seconds, relative: true)
        }
        if let seconds = text.firstNumber,
           text.hasAny("rewind", "back", "backward"), text.contains("second") {
            return EgoActions.mediaSeek(seconds: -seconds, relative: true)
        }
        return nil
    }

    private static let volumeRules: Rule = { text in
        // "loud" rather than "louder" so "how loud is it" reaches the report
        // rule below instead of being turned away at the door.
        // The guard has to admit every phrasing the rules below answer —
        // "turn it down" names neither "volume" nor "loud".
        guard text.contains("volume")
                || text.hasAny("mute", "unmute", "loud", "quieter",
                               "turn it up", "turn it down") else {
            return nil
        }
        if text.hasAny("unmute", "sound on") { return EgoActions.setMuted(false) }
        if text.hasAny("mute", "silence", "sound off") { return EgoActions.setMuted(true) }
        if text.hasAny("whats the volume", "how loud", "volume level") {
            return EgoActions.volumeReport()
        }
        if let percent = text.firstPercentOrNumber, text.contains("volume") {
            return EgoActions.setVolume(fraction: percent / 100)
        }
        if text.hasAny("louder", "volume up", "turn it up", "turn up the volume") {
            return EgoActions.nudgeVolume(by: 0.1)
        }
        if text.hasAny("quieter", "volume down", "turn it down", "turn down the volume",
                       "lower the volume") {
            return EgoActions.nudgeVolume(by: -0.1)
        }
        return nil
    }

    private static let brightnessRules: Rule = { text in
        guard text.contains("bright") || text.contains("dim") else { return nil }
        if let percent = text.firstPercentOrNumber, text.contains("bright") {
            return EgoActions.setBrightness(fraction: percent / 100)
        }
        if text.hasAny("brighter", "brightness up", "turn up the brightness") {
            return EgoActions.nudgeBrightness(by: 0.1)
        }
        if text.hasAny("dimmer", "dim the screen", "brightness down", "turn down the brightness") {
            return EgoActions.nudgeBrightness(by: -0.1)
        }
        return nil
    }

    private static let panelRules: Rule = { text in
        if text.hasAny("close the notch", "close notch", "hide the notch", "dismiss",
                       "never mind", "nevermind", "forget it") {
            return EgoActions.closeNotch()
        }
        if text.hasAny("open settings", "show settings", "preferences") {
            return EgoActions.openSettings()
        }
        // "open the terminal" / "switch to notes" / "show me the shelf"
        for tab in NotchTab.allCases {
            let name = tab.title.lowercased()
            if text.matches("(open|show|switch to|go to|jump to)( the| me)? \(name)( tab)?$") {
                return EgoActions.switchTab(tab)
            }
        }
        if text.matches("^(open|show)( the)? notch$") {
            return EgoActions.openNotch()
        }
        return nil
    }
}

// MARK: - Small text helpers

private extension String {
    func hasAny(_ needles: String...) -> Bool {
        needles.contains { contains($0) }
    }

    func matches(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }

    /// First plain number in the string ("skip 30 seconds" → 30).
    var firstNumber: Double? {
        guard let range = range(of: "[0-9]+(\\.[0-9]+)?", options: .regularExpression) else { return nil }
        return Double(self[range])
    }

    /// Handles "volume 30", "volume 30%", "volume to 0.3".
    var firstPercentOrNumber: Double? {
        guard let value = firstNumber else { return nil }
        return value <= 1 && contains(".") ? value * 100 : value
    }
}
