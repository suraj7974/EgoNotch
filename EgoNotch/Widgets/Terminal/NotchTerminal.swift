import AppKit
import SwiftUI
import Observation
import SwiftTerm

/// Owns the one long-lived terminal view. It is created once and reused for
/// the app's lifetime (same reason the camera preview layer is persistent:
/// tearing an AppKit view down while SwiftUI re-renders it is how you get a
/// frozen notch), so switching tabs never kills your shell.
@MainActor
@Observable
final class NotchTerminal: NSObject, LocalProcessTerminalViewDelegate {
    /// What the shell is currently doing, for the tile header.
    private(set) var title = ""
    private(set) var directory: URL?
    /// Non-nil while this terminal is attached to a shared tmux session.
    private(set) var attachedSession: String?
    private(set) var isRunning = false

    @ObservationIgnored let view = NotchTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 200))
    @ObservationIgnored private var styledFontSize: CGFloat = 0

    override init() {
        super.init()
        view.processDelegate = self
        view.allowMouseReporting = true
        // Matches `macos-option-as-alt = true` in their Ghostty config, so
        // ⌥⌫ deletes a word and ⌥←/→ jump one.
        view.optionAsMetaKey = true
        view.onAppearanceChange = { [weak self] in
            self?.styledFontSize = 0            // force the guard to re-apply
            self?.applyTheme()
        }
        applyTheme()
    }

    // MARK: - Theme

    /// Ghostty's palette and font, so the notch terminal matches the real one.
    func applyTheme() {
        let profile = GhosttyProfile.current
        let size = SettingsStore.shared.terminalFontSize
        guard size != styledFontSize else { return }
        styledFontSize = size

        view.font = profile.font(size: size)
        view.getTerminal().setCursorStyle(profile.cursorStyle)
        view.installColors(profile.palette)
        view.nativeBackgroundColor = profile.background
        view.nativeForegroundColor = profile.foreground
        view.caretColor = profile.cursor
        if let selection = profile.selectionBackground {
            view.selectedTextBackgroundColor = selection
        }
        view.layer?.backgroundColor = profile.background.cgColor
    }

    var backgroundColor: SwiftUI.Color { SwiftUI.Color(nsColor: GhosttyProfile.current.background) }

    // MARK: - Lifecycle

    /// The user's real login shell, interactive (a shell whose stdin is a tty
    /// turns interactive by itself), so .zshrc, aliases, prompt and shell
    /// integration all behave exactly as they do in Ghostty.
    func startIfNeeded() {
        guard !isRunning else { return }
        run(arguments: ["-l"], session: nil)
    }

    /// Attach to a tmux session — the one honest way to have *the same*
    /// running terminal in two places: Ghostty and the notch share the pane.
    func attach(tmuxSession name: String) {
        guard let tmux = TerminalSessions.tmuxPath else { return }
        restart(arguments: ["-l", "-c", "\(shellQuoted(tmux)) attach -t \(shellQuoted(name))"],
                session: name)
    }

    /// Put the caret in the shell so the very first keystroke lands.
    ///
    /// Retries briefly: on the frame the tab appears the view isn't in a
    /// window yet, and the panel may still be taking key status, so a single
    /// attempt silently does nothing and typing goes nowhere.
    func focus(attempt: Int = 0) {
        guard let window = view.window else {
            retryFocus(attempt: attempt)
            return
        }
        if !window.isKeyWindow { window.makeKey() }
        if window.firstResponder !== view { window.makeFirstResponder(view) }
        if window.firstResponder !== view { retryFocus(attempt: attempt) }
    }

    private func retryFocus(attempt: Int) {
        guard attempt < 8 else { return }              // ~0.4s, then give up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.focus(attempt: attempt + 1)
        }
    }

    private func restart(arguments: [String], session: String?, cwd: URL? = nil) {
        if isRunning {
            view.getTerminal().resetToInitialState()
            kill(view.process.shellPid, SIGKILL)
            isRunning = false
        }
        run(arguments: arguments, session: session, cwd: cwd)
    }

    private func run(arguments: [String], session: String?, cwd: URL? = nil) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let name = (shell as NSString).lastPathComponent
        let start = cwd ?? directory ?? FileManager.default.homeDirectoryForCurrentUser
        view.startProcess(executable: shell,
                          args: arguments,
                          environment: Terminal.getEnvironmentVariables(termName: "xterm-256color"),
                          execName: "-\(name)",           // login shell, as Ghostty does
                          currentDirectory: start.path)
        attachedSession = session
        directory = cwd ?? directory
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        kill(view.process.shellPid, SIGKILL)
        isRunning = false
    }

    /// Send a signal the way a keystroke would.
    func interrupt() { view.send(txt: "\u{3}") }

    /// Control keys, sent as the control characters a terminal expects rather
    /// than typed out as words. "Control C" has to *be* ⌃C — typing the letters
    /// into a running process does nothing at all.
    func sendControl(_ letter: Character) {
        guard let ascii = letter.uppercased().first?.asciiValue,
              ascii >= 65, ascii <= 90 else { return }
        // ⌃A is 1, ⌃B is 2 … ⌃Z is 26.
        view.send(txt: String(UnicodeScalar(ascii - 64)))
    }

    /// Type a command and press return, exactly as if you had.
    ///
    /// Ego's only way into the shell. It goes through the same PTY as your
    /// keystrokes, so the command lands in history and its output is visible
    /// on screen — there is no hidden execution channel, which is what makes
    /// the confirmation gate meaningful rather than decorative.
    ///
    /// A leading space keeps it out of `HISTFILE` for nobody: it is left in
    /// deliberately, because a command you didn't type is exactly the one you
    /// want to find afterwards.
    func run(_ command: String) {
        startIfNeeded()
        // ⌃U first: if the prompt already has half a line on it, appending
        // would run something neither of us meant.
        view.send(txt: "\u{15}")
        view.send(txt: command + "\n")
    }

    // MARK: - LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor in self.title = title }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, let url = URL(string: directory) ?? URL(string: "file://" + directory)
        else { return }
        Task { @MainActor in self.directory = URL(fileURLWithPath: url.path) }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            self.isRunning = false
            self.attachedSession = nil
        }
    }

    private func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
