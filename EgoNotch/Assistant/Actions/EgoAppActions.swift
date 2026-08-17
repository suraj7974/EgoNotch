import AppKit

/// The rest of the notch: timers, notes, todos, clipboard, shelf, camera,
/// games, links, calendar and the machine's own numbers.
///
/// Same contract as the rest of `EgoActions` — one implementation per verb,
/// called by both the grammar and the model, returning what Ego should say.
/// Reads never guess: every number here comes from the live widget, and when
/// a module is switched off Ego says so rather than inventing an answer.
@MainActor
extension EgoActions {

    // MARK: - Reaching the widgets

    private static func focus() -> FocusWidget? {
        WidgetRegistry.widget(id: "focus") as? FocusWidget
    }
    private static func notes() -> NotesStore? {
        (WidgetRegistry.widget(id: "notes") as? NotesWidget)?.store
    }
    private static func todo() -> TodoStore? {
        (WidgetRegistry.widget(id: "todo") as? TodoWidget)?.store
    }
    private static func clipboard() -> ClipboardStore? {
        (WidgetRegistry.widget(id: "clipboard") as? ClipboardWidget)?.store
    }
    private static func shelf() -> ShelfStore? {
        (WidgetRegistry.widget(id: "shelf") as? ShelfWidget)?.store
    }
    private static func recorder() -> RecorderCamera? {
        (WidgetRegistry.widget(id: "recorder") as? RecorderWidget)?.camera
    }
    private static func games() -> GamesState? {
        (WidgetRegistry.widget(id: "games") as? GamesWidget)?.state
    }
    private static func links() -> QuickLinksStore? {
        (WidgetRegistry.widget(id: "quicklinks") as? QuickLinksWidget)?.store
    }
    private static func calendar() -> CalendarStore? {
        (WidgetRegistry.widget(id: "calendar") as? CalendarWidget)?.store
    }
    private static func stats() -> SystemSampler? {
        (WidgetRegistry.widget(id: "stats") as? SystemStatsWidget)?.sampler
    }

    // MARK: - Focus, timers, stopwatch

    static func startFocus(_ mode: FocusTimer.Mode) -> ActionResult {
        guard let focus = focus() else { return .notAvailable }
        focus.timer.select(mode)
        if !focus.timer.isRunning { focus.timer.startPause() }
        return ActionResult("\(mode.title) started.",
                            detail: FocusTimer.format(focus.timer.remaining))
    }

    static func pauseFocus() -> ActionResult {
        guard let focus = focus() else { return .notAvailable }
        guard focus.timer.isRunning else { return ActionResult("Not running.") }
        focus.timer.startPause()
        return ActionResult("Paused.", detail: FocusTimer.format(focus.timer.remaining))
    }

    static func resetFocus() -> ActionResult {
        guard let focus = focus() else { return .notAvailable }
        focus.timer.reset()
        return ActionResult("Reset.")
    }

    /// There is no absolute setter on the timer engine — it is built out of
    /// "add a chunk" buttons — so a spoken duration is composed the same way.
    static func startTimer(minutes: Int) -> ActionResult {
        guard let focus = focus() else { return .notAvailable }
        let clamped = max(1, min(minutes, 180))
        focus.custom.clear()
        focus.custom.add(TimeInterval(clamped) * 60)
        if !focus.custom.isRunning { focus.custom.startPause() }
        PanelUIState.shared.selectedTab = .focus
        return ActionResult("\(clamped) minute\(clamped == 1 ? "" : "s").",
                            detail: TimerEngine.format(focus.custom.remaining))
    }

    static func stopwatch(_ action: String) -> ActionResult {
        guard let focus = focus() else { return .notAvailable }
        switch action {
        case "reset":
            focus.stopwatch.reset()
            return ActionResult("Reset.")
        default:
            let wasRunning = focus.stopwatch.isRunning
            focus.stopwatch.startPause()
            return ActionResult(wasRunning ? "Stopped." : "Started.",
                                detail: Stopwatch.format(focus.stopwatch.elapsed))
        }
    }

    /// Whichever clock is actually running answers "how long is left" — asking
    /// the user which timer they meant would be worse than picking the one
    /// that is ticking.
    static func timeLeft() -> ActionResult {
        guard let focus = focus() else { return .notAvailable }
        if focus.timer.isRunning {
            return ActionResult("\(FocusTimer.format(focus.timer.remaining)) left.",
                                detail: "\(focus.timer.mode.title) timer")
        }
        if focus.custom.isRunning {
            return ActionResult("\(TimerEngine.format(focus.custom.remaining)) left.")
        }
        if focus.stopwatch.isRunning {
            return ActionResult(Stopwatch.format(focus.stopwatch.elapsed), detail: "Stopwatch")
        }
        return ActionResult("No timer is running.")
    }

    // MARK: - Notes and todos

    static func addNote(_ text: String, asCheckbox: Bool = false) -> ActionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ActionResult("Note what?") }
        guard let notes = notes() else { return .notAvailable }
        notes.append(trimmed, asCheckbox: asCheckbox)
        return ActionResult("Noted.", detail: trimmed)
    }

    static func readNotes() -> ActionResult {
        guard let notes = notes() else { return .notAvailable }
        let lines = notes.lines.map(\.text).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return ActionResult("Your notes are empty.") }
        // Spoken, not read off a screen: three is as many as anyone follows.
        let spoken = lines.suffix(3).joined(separator: ", ")
        return ActionResult(spoken, detail: lines.joined(separator: " · "))
    }

    static func addTodo(_ text: String) -> ActionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ActionResult("Add what?") }
        guard let todo = todo() else { return .notAvailable }
        todo.add(trimmed)
        return ActionResult("Added.", detail: trimmed)
    }

    static func readTodos() -> ActionResult {
        guard let todo = todo() else { return .notAvailable }
        let open = todo.items.filter { !$0.done }
        guard !open.isEmpty else { return ActionResult("Nothing left.") }
        let spoken = open.prefix(3).map(\.text).joined(separator: ", ")
        let more = open.count > 3 ? " and \(open.count - 3) more" : ""
        return ActionResult(spoken + more,
                            detail: open.map(\.text).joined(separator: " · "))
    }

    /// Matched loosely on purpose: you say "finish the milk", the list says
    /// "buy milk", and demanding the exact words would make this useless.
    static func completeTodo(_ text: String) -> ActionResult {
        guard let todo = todo() else { return .notAvailable }
        let needle = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return ActionResult("Which one?") }
        guard let match = todo.items.first(where: { item in
            !item.done && (item.text.lowercased().contains(needle)
                           || needle.contains(item.text.lowercased()))
        }) else {
            return ActionResult("I can't find that one.")
        }
        todo.toggle(match)
        return ActionResult("Done.", detail: match.text)
    }

    static func clearDoneTodos() -> ActionResult {
        guard let todo = todo() else { return .notAvailable }
        let count = todo.items.filter(\.done).count
        guard count > 0 else { return ActionResult("Nothing to clear.") }
        todo.clearDone()
        return ActionResult("Cleared \(count).")
    }

    // MARK: - Clipboard and shelf

    static func lastClip() -> ActionResult {
        guard let clipboard = clipboard() else { return .notAvailable }
        guard let latest = clipboard.items.first else { return ActionResult("Clipboard is empty.") }
        return ActionResult(describe(latest), detail: describe(latest))
    }

    static func copyLastClip() -> ActionResult {
        guard let clipboard = clipboard() else { return .notAvailable }
        guard let latest = clipboard.items.first else { return ActionResult("Clipboard is empty.") }
        clipboard.copy(latest)
        return ActionResult("Copied.", detail: describe(latest))
    }

    /// An image can't be read aloud, so say what it is rather than nothing.
    private static func describe(_ clip: ClipItem) -> String {
        switch clip.content {
        case .text(let text):
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n").joined(separator: " ")
            return clean.count > 90 ? String(clean.prefix(90)) + "…" : clean
        case .image:
            return "An image."
        }
    }

    static func shelfReport() -> ActionResult {
        guard let shelf = shelf() else { return .notAvailable }
        let count = shelf.items.count
        guard count > 0 else { return ActionResult("The shelf is empty.") }
        return ActionResult("\(count) item\(count == 1 ? "" : "s") on the shelf.",
                            detail: shelf.items.map(\.name).joined(separator: " · "))
    }

    /// Emptying the shelf throws away files the user parked there, so it is
    /// held for confirmation like anything else that can't be undone.
    static func clearShelf() -> ActionResult {
        guard let shelf = shelf() else { return .notAvailable }
        let count = shelf.items.count
        guard count > 0 else { return ActionResult("The shelf is already empty.") }
        return ActionResult("Clear \(count) from the shelf?",
                            detail: "Removes every item on the shelf",
                            pending: PendingAction(
                                question: "Clear \(count) from the shelf?",
                                detail: "Removes every item on the shelf",
                                perform: {
                                    shelf.clear()
                                    return ActionResult("Cleared.")
                                }))
    }

    // MARK: - Camera

    static func capture(mode: CaptureMode, filter: CaptureFilter? = nil,
                        selfTimer: Int? = nil) -> ActionResult {
        guard let recorder = recorder() else { return .notAvailable }
        PanelUIState.shared.selectedTab = .recorder
        panelController?.expand()
        recorder.mode = mode
        if let filter { recorder.filter = filter }
        if let selfTimer { recorder.selfTimer = selfTimer }
        recorder.trigger()
        let verb = recorder.isRecording ? "Stopped." : "\(mode.title)."
        return ActionResult(verb, detail: mode.hint)
    }

    static func setFilter(_ filter: CaptureFilter) -> ActionResult {
        guard let recorder = recorder() else { return .notAvailable }
        recorder.filter = filter
        return ActionResult(filter == .none ? "Filter off." : "\(filter.title).")
    }

    // MARK: - Games and links

    static func playGame(_ game: GameChoice) -> ActionResult {
        guard let games = games() else { return .notAvailable }
        games.selected = game
        PanelUIState.shared.selectedTab = .games
        panelController?.expand()
        return ActionResult("\(game.title).")
    }

    static func openLink(named name: String) -> ActionResult {
        guard let links = links() else { return .notAvailable }
        let needle = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard let match = links.links.first(where: {
            $0.name.lowercased().contains(needle) || needle.contains($0.name.lowercased())
        }) else {
            return ActionResult("I don't have a link called that.")
        }
        links.open(match)
        return ActionResult("Opening \(match.name).")
    }

    // MARK: - Calendar and the machine

    static func nextEvent() -> ActionResult {
        guard let calendar = calendar() else { return .notAvailable }
        let now = Date()
        guard let next = calendar.todaysEvents.first(where: { $0.end > now }) else {
            return ActionResult("Nothing else today.")
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let when = next.start > now ? "at \(formatter.string(from: next.start))" : "now"
        return ActionResult("\(next.title) \(when).",
                            detail: "\(formatter.string(from: next.start)) – \(formatter.string(from: next.end))")
    }

    /// CPU is a delta between two samples, so a single call would report
    /// whatever happened since the widget last looked — which could be hours.
    static func systemReport(_ what: String) -> ActionResult {
        guard let sampler = stats() else { return .notAvailable }
        _ = sampler.sample()
        let sample = sampler.sample()
        switch what {
        case "cpu":
            return ActionResult("CPU \(Int(sample.cpuPercent.rounded())) percent.")
        case "ram", "memory":
            return ActionResult("Memory \(Int(sample.ramPercent.rounded())) percent.")
        case "disk":
            return ActionResult(sample.diskFreeText.isEmpty
                                ? "Disk \(Int(sample.diskPercent.rounded())) percent full."
                                : "\(sample.diskFreeText) free.")
        default:
            guard let battery = sample.batteryPercent else { return ActionResult("No battery here.") }
            let charging = sample.charging ? ", charging" : ""
            return ActionResult("Battery \(Int(battery.rounded())) percent\(charging).")
        }
    }

    /// What Ego can actually do *right now* — read off the switches rather
    /// than from the model's memory of its own instructions, which understated
    /// it and went out of date the moment a feature was added.
    static func capabilities() -> ActionResult {
        var parts = ["music, volume and brightness", "the notch and its tabs",
                     "timers, notes and the camera"]
        if SettingsStore.shared.egoTerminalControl { parts.append("the terminal") }
        if SettingsStore.shared.egoControlApps { parts.append("other apps and their menus") }
        if SettingsStore.shared.egoRunShortcuts { parts.append("your shortcuts") }
        if SettingsStore.shared.egoCalling { parts.append("calls and messages") }

        // Spoken, so the list is short; the notch shows the whole thing.
        let spoken = parts.prefix(3).joined(separator: ", ")
        return ActionResult("I run \(spoken), and more.",
                            detail: "I run " + parts.joined(separator: ", ") + ".")
    }

    private static var panelController: NotchPanelController? { NotchPanelController.current }
}
