import AppKit

/// Ego outside the notch: other apps, their windows, their menus, and the
/// user's own Shortcuts.
///
/// The Accessibility work runs off the main actor with a deadline. AX is
/// synchronous IPC into another process, and one beachballed app would
/// otherwise freeze the notch — the same hazard `MediaPrimer` documents for
/// AppleScript.
@MainActor
extension EgoActions {

    /// Anything here needs both the setting and the system permission. Said
    /// plainly rather than failing silently, because "nothing happened" is the
    /// worst possible answer to a spoken command.
    private static func deviceReady() -> String? {
        guard SettingsStore.shared.egoControlApps else { return "App control is switched off." }
        guard SystemControl.isTrusted else { return "I need Accessibility access in Settings › Ego." }
        return nil
    }

    // MARK: - Apps

    static func openApp(named name: String) -> ActionResult {
        guard SettingsStore.shared.egoControlApps else {
            return ActionResult("App control is switched off.")
        }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return ActionResult("Open what?") }

        if let running = SystemControl.runningApp(named: cleaned) {
            running.activate(options: [.activateAllWindows])
            return ActionResult("\(running.localizedName ?? cleaned).")
        }
        guard let url = SystemControl.installedApp(named: cleaned) else {
            return ActionResult("I can't find \(cleaned).")
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        return ActionResult("\(url.deletingPathExtension().lastPathComponent).")
    }

    /// Quitting is held for confirmation: an app may be holding work you
    /// haven't saved, and a misheard app name is one word away.
    static func quitApp(named name: String) -> ActionResult {
        guard SettingsStore.shared.egoControlApps else {
            return ActionResult("App control is switched off.")
        }
        guard let app = SystemControl.runningApp(named: name),
              let title = app.localizedName else {
            return ActionResult("\(name) isn't running.")
        }
        return ActionResult("Quit \(title)?",
                            detail: "Quits \(title) and anything unsaved in it",
                            pending: PendingAction(
                                question: "Quit \(title)?",
                                detail: "Quits \(title)",
                                perform: {
                                    app.terminate()
                                    return ActionResult("Quit \(title).")
                                }))
    }

    // MARK: - Windows

    static func placeWindow(_ place: SystemControl.WindowPlace,
                            appNamed name: String?) async -> ActionResult {
        if let problem = deviceReady() { return ActionResult(problem) }
        let app = name.flatMap { SystemControl.runningApp(named: $0) }
            ?? NSWorkspace.shared.frontmostApplication
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return ActionResult("Nothing is in front.")
        }
        let title = app.localizedName ?? "it"
        let moved = await offMainActor { SystemControl.place(place, ofApp: app) } ?? false
        guard moved else { return ActionResult("\(title) has no window I can move.") }
        return ActionResult("\(place.spoken).", detail: title)
    }

    // MARK: - Menus

    /// The highest-leverage verb Ego has outside the notch: every Mac app
    /// already lists its commands in the menu bar, so this works in apps
    /// nobody integrated with.
    static func runMenuCommand(_ wanted: String, appNamed name: String?) async -> ActionResult {
        if let problem = deviceReady() { return ActionResult(problem) }
        let app = name.flatMap { SystemControl.runningApp(named: $0) }
            ?? NSWorkspace.shared.frontmostApplication
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return ActionResult("Nothing is in front.")
        }
        let title = app.localizedName ?? "that app"

        // Menu items that throw work away are read back first. The rest run.
        if Self.destructiveMenuWords.contains(where: { wanted.lowercased().contains($0) }) {
            return ActionResult("\(wanted) in \(title)?",
                                detail: "Menu command in \(title)",
                                pending: PendingAction(
                                    question: "\(wanted) in \(title)?",
                                    detail: "\(wanted) — \(title)",
                                    perform: { pressMenu(wanted, in: app, title: title) }))
        }
        return await pressMenuAsync(wanted, in: app, title: title)
    }

    private static let destructiveMenuWords = [
        "delete", "remove", "erase", "clear", "reset", "discard", "revert",
        "close all", "quit", "empty", "move to trash",
    ]

    private static func pressMenuAsync(_ wanted: String, in app: NSRunningApplication,
                                       title: String) async -> ActionResult {
        let found = await offMainActor { SystemControl.pressMenuItem(matching: wanted, inApp: app) }
        guard let pressed = found ?? nil else {
            return ActionResult("No \(wanted) in \(title).")
        }
        return ActionResult("\(pressed).", detail: "\(title) › \(pressed)")
    }

    /// Confirmation resumes on the main actor, so this one blocks briefly —
    /// it happens only after the user has said yes, and only for one item.
    private static func pressMenu(_ wanted: String, in app: NSRunningApplication,
                                  title: String) -> ActionResult {
        guard let pressed = SystemControl.pressMenuItem(matching: wanted, inApp: app) else {
            return ActionResult("No \(wanted) in \(title).")
        }
        return ActionResult("\(pressed).", detail: "\(title) › \(pressed)")
    }

    // MARK: - Shortcuts

    static func runShortcut(named name: String) async -> ActionResult {
        guard SettingsStore.shared.egoRunShortcuts else {
            return ActionResult("Shortcuts are switched off.")
        }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return ActionResult("Run which shortcut?") }
        let ran = await offMainActor { SystemControl.runShortcut(named: cleaned) } ?? false
        return ran ? ActionResult("Done.", detail: "Shortcut: \(cleaned)")
                   : ActionResult("I don't have a shortcut called \(cleaned).")
    }

    static func listShortcuts() async -> ActionResult {
        guard SettingsStore.shared.egoRunShortcuts else {
            return ActionResult("Shortcuts are switched off.")
        }
        let names = await offMainActor { SystemControl.shortcutNames() } ?? []
        guard !names.isEmpty else { return ActionResult("You have no shortcuts.") }
        return ActionResult(names.prefix(3).joined(separator: ", "),
                            detail: names.joined(separator: " · "))
    }

    // MARK: - The web

    static func openURL(_ raw: String) -> ActionResult {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ActionResult("Open what?") }
        if !text.contains("://") { text = "https://\(text)" }
        guard let url = URL(string: text), url.host != nil else {
            return ActionResult("That isn't a web address.")
        }
        NSWorkspace.shared.open(url)
        return ActionResult("Opening \(url.host ?? "it").")
    }

    static func search(_ terms: String) -> ActionResult {
        let cleaned = terms.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              let encoded = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)")
        else { return ActionResult("Search for what?") }
        NSWorkspace.shared.open(url)
        return ActionResult("Searching.", detail: cleaned)
    }

    /// Runs blocking work off the main actor with a deadline, so a hung app
    /// costs Ego a few seconds rather than freezing the whole notch. nil means
    /// it took too long.
    private static func offMainActor<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await Task.detached(priority: .userInitiated) { work() }.value }
            group.addTask {
                try? await Task.sleep(for: .seconds(6))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

extension SystemControl.WindowPlace {
    /// The word a person says for this place.
    var spokenTrigger: String {
        switch self {
        case .left: "left"
        case .right: "right"
        case .top: "top"
        case .bottom: "bottom"
        case .maximise: "maxim"
        case .centre: "cent"
        }
    }

    var spoken: String {
        switch self {
        case .left: "Left half"
        case .right: "Right half"
        case .top: "Top half"
        case .bottom: "Bottom half"
        case .maximise: "Maximised"
        case .centre: "Centred"
        }
    }
}
