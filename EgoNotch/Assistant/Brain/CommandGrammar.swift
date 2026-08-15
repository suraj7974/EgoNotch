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
        if text.hasAny("how long left", "how much time is left", "how long is left",
                       "how much longer", "time left on the timer") {
            return EgoActions.timeLeft()
        }
        if text.hasAny("whats next", "whats on my calendar", "next meeting",
                       "next event", "whats my next") {
            return EgoActions.nextEvent()
        }
        if text.hasAny("hows my battery", "whats my battery", "battery level", "how much battery") {
            return EgoActions.systemReport("battery")
        }
        if text.hasAny("hows my cpu", "cpu usage", "how busy") { return EgoActions.systemReport("cpu") }
        if text.hasAny("hows my memory", "how much ram", "memory usage") {
            return EgoActions.systemReport("ram")
        }
        if text.hasAny("how much disk", "disk space", "hows my disk", "storage left") {
            return EgoActions.systemReport("disk")
        }
        if text.hasAny("whats on my list", "read my list", "my todos", "whats left to do") {
            return EgoActions.readTodos()
        }
        if text.hasAny("read my notes", "whats in my notes") { return EgoActions.readNotes() }
        if text.hasAny("what did i copy", "whats in my clipboard") { return EgoActions.lastClip() }
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

    /// A command that is unmistakably finished, so Ego can act on it the
    /// instant it is heard rather than waiting to see whether more is coming.
    ///
    /// That wait — long enough to be sure you had stopped talking — was most
    /// of what made Ego feel slow. These phrasings have nothing that can
    /// sensibly follow them, so there is nothing to wait for.
    static func isComplete(_ raw: String) -> Bool {
        let text = normalise(raw)
        if finished.contains(text) { return true }
        // "volume 40", "brightness 60" — a number ends the sentence.
        if text.matches("^(volume|brightness) (to )?[0-9]{1,3}( percent)?$") { return true }
        return false
    }

    /// Plainly the middle of a sentence. Ending here would act on half a
    /// command — which is how "play the song" became "play the", and then
    /// "song" a second later as though it were a new instruction.
    static func looksUnfinished(_ raw: String) -> Bool {
        let text = normalise(raw)
        guard let last = text.split(separator: " ").last.map(String.init) else { return false }
        if dangling.contains(last) { return true }
        // A lone verb is a request for something that hasn't arrived yet.
        return text.split(separator: " ").count == 1 && needsObject.contains(text)
    }

    /// Words no English sentence ends on.
    private static let dangling: Set<String> = [
        "the", "a", "an", "to", "my", "of", "for", "and", "or", "in", "on",
        "with", "at", "is", "it", "this", "that", "some", "go", "turn", "set",
    ]

    private static let needsObject: Set<String> = [
        "open", "switch", "show", "jump", "play", "run", "take", "add", "note",
        "set", "start", "complete", "read", "record", "execute", "type",
    ]

    private static let finished: Set<String> = [
        "pause", "resume", "stop the music", "stop music", "next", "next song",
        "next track", "skip", "skip this", "previous", "previous song", "previous track",
        "back a track", "mute", "unmute", "louder", "quieter", "turn it up", "turn it down",
        "volume up", "volume down", "brighter", "dimmer", "whats playing", "what is playing",
        "whats the volume", "close the notch", "close notch", "open the notch",
        "hows my battery", "whats next", "take a photo", "take a selfie", "boomerang",
        "start the stopwatch", "start a pomodoro", "take a break", "read my notes",
        "whats on my list", "gaana roko", "gaana chalu karo",
        // Answers to a question Ego asked, and ways of calling it off. Nothing
        // can follow these, and waiting on them is the most annoying wait.
        "yes", "yeah", "yep", "confirm", "no", "nope", "cancel", "dismiss",
        "stop it", "haan", "nahi", "theek hai", "kar do",
    ]

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
        "switch", "whats", "what is", "how loud", "how bright", "go to", "jump to",
        "hows", "how much", "take a", "start", "set a", "run", "read", "add",
        "note", "todo", "complete", "record", "gaana", "volume ko",
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
        terminalRules, focusRules, listRules, captureRules,
        mediaRules, volumeRules, brightnessRules, panelRules,
    ]

    /// Timers, before the media rules: "start a timer" must not be heard as
    /// "start" the music.
    private static let focusRules: Rule = { text in
        if text.hasAny("start a pomodoro", "start pomodoro", "start a focus", "focus session",
                       "start focusing", "pomodoro") {
            let mode: FocusTimer.Mode = text.contains("deep") ? .deep : .focus
            return EgoActions.startFocus(mode)
        }
        if text.hasAny("take a break", "start a break", "break time", "short break") {
            return EgoActions.startFocus(.shortBreak)
        }
        if text.hasAny("pause the timer", "pause the pomodoro", "pause focus") {
            return EgoActions.pauseFocus()
        }
        if text.hasAny("reset the timer", "reset the pomodoro", "reset focus") {
            return EgoActions.resetFocus()
        }
        if text.hasAny("start the stopwatch", "start a stopwatch", "stop the stopwatch") {
            return EgoActions.stopwatch("toggle")
        }
        if text.hasAny("reset the stopwatch") { return EgoActions.stopwatch("reset") }
        // "set a timer for 10 minutes" / "timer 25 minutes"
        if text.contains("timer"), let minutes = text.firstNumber {
            return EgoActions.startTimer(minutes: Int(minutes))
        }
        return nil
    }

    /// Notes, todos, clipboard and the shelf.
    private static let listRules: Rule = { text in
        for verb in ["note that ", "make a note ", "note down ", "note "]
        where text.hasPrefix(verb) {
            return EgoActions.addNote(String(text.dropFirst(verb.count)))
        }
        for verb in ["add a todo ", "add todo ", "todo ", "remind me to ", "add to my list "]
        where text.hasPrefix(verb) {
            return EgoActions.addTodo(String(text.dropFirst(verb.count)))
        }
        if text.hasAny("read my notes", "read notes", "whats in my notes") {
            return EgoActions.readNotes()
        }
        if text.hasAny("whats on my list", "read my list", "my todos", "whats left to do") {
            return EgoActions.readTodos()
        }
        for verb in ["complete ", "tick off ", "check off ", "mark done "]
        where text.hasPrefix(verb) {
            return EgoActions.completeTodo(String(text.dropFirst(verb.count)))
        }
        if text.hasAny("clear completed", "clear the done ones", "clear finished") {
            return EgoActions.clearDoneTodos()
        }
        if text.hasAny("what did i copy", "whats in my clipboard", "last clip") {
            return EgoActions.lastClip()
        }
        if text.hasAny("copy that again", "copy the last clip", "paste the last") {
            return EgoActions.copyLastClip()
        }
        if text.hasAny("whats on the shelf", "whats in the shelf", "shelf") {
            return text.hasAny("clear", "empty") ? EgoActions.clearShelf() : EgoActions.shelfReport()
        }
        return nil
    }

    /// The camera, games and links.
    private static let captureRules: Rule = { text in
        if text.hasAny("take a photo", "take a picture", "take a selfie", "photo of me") {
            return EgoActions.capture(mode: .photo)
        }
        if text.hasAny("boomerang") { return EgoActions.capture(mode: .boomerang) }
        if text.hasAny("photo booth", "booth strip", "four shots") {
            return EgoActions.capture(mode: .booth)
        }
        if text.hasAny("daily selfie", "todays selfie", "streak selfie") {
            return EgoActions.capture(mode: .daily)
        }
        if text.hasAny("make a gif", "caption gif") { return EgoActions.capture(mode: .gif) }
        if text.hasAny("start recording", "stop recording", "record a video", "record video") {
            return EgoActions.capture(mode: .video)
        }
        for filter in CaptureFilter.allCases
        where text.contains(filter.rawValue) && text.hasAny("filter", "look") {
            return EgoActions.setFilter(filter)
        }
        if text.hasAny("no filter", "clear the filter", "remove the filter") {
            return EgoActions.setFilter(.none)
        }
        if text.hasPrefix("play ") || text.contains("play the ") {
            for game in GameChoice.allCases
            where text.contains(game.title.lowercased()) || text.contains(game.rawValue) {
                return EgoActions.playGame(game)
            }
        }
        for verb in ["open the link ", "open link "] where text.hasPrefix(verb) {
            return EgoActions.openLink(named: String(text.dropFirst(verb.count)))
        }
        return nil
    }

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
