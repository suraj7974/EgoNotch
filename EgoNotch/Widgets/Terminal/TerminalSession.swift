import Foundation
import Observation
import Darwin

/// A real login shell behind a pseudo-terminal, so `cd`, exports, aliases and
/// long-running commands behave exactly as they would in Terminal — this is
/// one session that persists for as long as the widget is enabled, not a
/// series of one-shot `Process` calls.
///
/// Output is event-driven (the PTY's readability handler); nothing polls.
@MainActor
@Observable
final class TerminalSession {
    private(set) var lines: [String] = ["Type a command, or drop a folder on the notch to cd there."]
    private(set) var isLive = false
    private(set) var workingDirectory: URL

    /// Keeps memory bounded — a terminal can emit a lot.
    private static let maxLines = 300

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var master: FileHandle?
    @ObservationIgnored private var pending = ""

    init() {
        workingDirectory = FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Lifecycle

    func start() {
        guard process == nil else { return }

        var masterFD: Int32 = 0
        var slaveFD: Int32 = 0
        var size = winsize(ws_row: 40, ws_col: 100, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&masterFD, &slaveFD, nil, nil, &size) == 0 else {
            append("Could not open a pseudo-terminal.")
            return
        }

        // Turn OFF the tty's own echo: we render the command ourselves, so
        // the shell echoing it back would double every keystroke.
        var attributes = termios()
        if tcgetattr(slaveFD, &attributes) == 0 {
            attributes.c_lflag &= ~tcflag_t(ECHO)
            tcsetattr(slaveFD, TCSANOW, &attributes)
        }

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        // Login shell (real PATH from .zprofile) reading commands from the pty.
        // `+i` is load-bearing: a shell whose stdin is a terminal turns
        // interactive on its own, which brings back the line editor and the
        // prompt (starship) — both of which would garble the transcript.
        p.arguments = ["-l", "+i", "-s"]
        p.currentDirectoryURL = workingDirectory
        var env = ProcessInfo.processInfo.environment
        // A real TERM keeps prompts like starship happy; the escapes they
        // emit are stripped before display.
        env["TERM"] = "xterm-256color"
        env["CLICOLOR"] = "0"
        env["PAGER"] = "cat"                 // nothing interactive to drive
        p.environment = env

        let slave = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        p.standardInput = slave
        p.standardOutput = slave
        p.standardError = slave
        p.terminationHandler = { _ in
            Task { @MainActor [weak self] in
                self?.process = nil
                self?.isLive = false
                self?.append("[shell exited]")
            }
        }

        do {
            try p.run()
        } catch {
            append("Failed to start \(shell): \(error.localizedDescription)")
            return
        }
        process = p

        let handle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        master = handle
        handle.readabilityHandler = { fh in
            let data = fh.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in self?.ingest(text) }
        }
        isLive = true
    }

    func stop() {
        master?.readabilityHandler = nil
        master = nil
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        isLive = false
    }

    // MARK: - Input

    func send(_ command: String) {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        start()                                  // lazily spin the shell up
        append("❯ \(text)")                      // our own clean echo
        write(text + "\n")
        probeDirectoryIfNeeded(after: text)
    }

    /// Ctrl-C for whatever is running.
    func interrupt() {
        write(String(UnicodeScalar(3)))
    }

    func clear() {
        lines = []
    }

    /// Used by drops: run the session in that folder.
    func changeDirectory(to url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        else { return }
        let target = isDirectory.boolValue ? url : url.deletingLastPathComponent()
        workingDirectory = target
        start()
        append("❯ cd \(displayPath(target))")
        write("cd \(shellQuoted(target.path))\n")
    }

    func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    private func write(_ text: String) {
        guard let master, let data = text.data(using: .utf8) else { return }
        try? master.write(contentsOf: data)
    }

    private func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Asks the shell itself where it ended up — parsing `cd` out of a command
    /// line is hopeless once `&&`, subshells or dir-jumpers are involved. The
    /// reply is tagged and swallowed before it reaches the transcript.
    ///
    /// Only sent after commands that plausibly move the shell: anything else
    /// might still be running (an editor, a REPL) and would swallow the probe
    /// as literal input.
    private func probeDirectoryIfNeeded(after command: String) {
        let movers: Set<String> = ["cd", "pushd", "popd", "z", "j", "-"]
        let tokens = command.split(whereSeparator: { " \t;|&()".contains($0) }).map(String.init)
        guard tokens.contains(where: movers.contains) else { return }
        write("printf '\(Self.cwdSentinel)%s\\n' \"$PWD\"\n")
    }

    private static let cwdSentinel = "\u{1}EGO_CWD:"

    // MARK: - Output

    private func ingest(_ text: String) {
        pending += Self.stripControlSequences(text)
        var parts = pending.components(separatedBy: "\n")
        pending = parts.removeLast()              // keep the partial line
        for part in parts { append(part) }
        // A prompt with no trailing newline still deserves to be visible.
        if !pending.isEmpty, pending.count > 160 {
            append(pending)
            pending = ""
        }
    }

    private func append(_ line: String) {
        let cleaned = line.replacingOccurrences(of: "\r", with: "")
        if let range = cleaned.range(of: Self.cwdSentinel) {
            let path = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !path.isEmpty { workingDirectory = URL(fileURLWithPath: path) }
            return                                   // never shown
        }
        guard !cleaned.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        lines.append(cleaned)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
    }

    /// Strips ANSI/VT escapes so the output renders as plain text.
    nonisolated private static func stripControlSequences(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var iterator = text.makeIterator()
        var buffered: Character?

        while let ch = buffered ?? iterator.next() {
            buffered = nil
            guard ch == "\u{1B}" else {
                if ch != "\u{07}" { out.append(ch) }   // drop BEL
                continue
            }
            // ESC [ ... final-byte   |   ESC ] ... BEL/ST   |   ESC <one char>
            guard let next = iterator.next() else { break }
            if next == "[" {
                while let c = iterator.next() {
                    if c.isLetter || c == "@" || c == "~" { break }
                }
            } else if next == "]" {
                while let c = iterator.next() {
                    if c == "\u{07}" { break }
                    if c == "\u{1B}" { _ = iterator.next(); break }
                }
            }
        }
        return out
    }
}
