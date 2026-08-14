import AppKit
import Observation

/// Discovers terminals that are already running so the notch can pick one up.
///
/// macOS gives no way to move another app's window — or its shell — into our
/// process, so "use the terminal I already have" means one of two things:
///   • it runs inside tmux → we attach to the *same* session, live-shared with
///     Ghostty (both views drive one shell);
///   • it doesn't → we open a new shell in that window's directory.
@MainActor
@Observable
final class TerminalSessions {
    struct TmuxSession: Identifiable {
        let name: String
        let windows: Int
        let attached: Bool
        var id: String { name }
    }

    struct RunningShell: Identifiable {
        let pid: pid_t
        let app: String
        let directory: URL
        var id: pid_t { pid }
        var displayName: String {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let path = directory.path
            return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        }
    }

    private(set) var tmuxSessions: [TmuxSession] = []
    private(set) var runningShells: [RunningShell] = []

    /// Terminal emulators worth scanning for live shells.
    private static let emulators = ["ghostty", "Ghostty", "iTerm2", "Terminal", "kitty", "alacritty", "WezTerm"]

    static let tmuxPath: String? = {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// Cheap enough to run when the tab appears; never on a timer.
    func refresh() {
        tmuxSessions = Self.loadTmuxSessions()
        runningShells = Self.loadRunningShells()
    }

    // MARK: - tmux

    private static func loadTmuxSessions() -> [TmuxSession] {
        guard let tmux = tmuxPath,
              let output = run(tmux, ["list-sessions", "-F", "#{session_name}\t#{session_windows}\t#{session_attached}"])
        else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t")
            guard parts.count == 3 else { return nil }
            return TmuxSession(name: String(parts[0]),
                               windows: Int(parts[1]) ?? 1,
                               attached: parts[2] != "0")
        }
    }

    // MARK: - Live shells in other terminal apps

    /// Every shell whose parent chain starts at a terminal emulator, with the
    /// directory it is sitting in (`lsof -d cwd`, one call for all of them).
    private static func loadRunningShells() -> [RunningShell] {
        guard let table = run("/bin/ps", ["-axo", "pid=,ppid=,comm="]) else { return [] }

        var command: [pid_t: String] = [:]
        var parent: [pid_t: pid_t] = [:]
        for line in table.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3, let pid = pid_t(fields[0]), let ppid = pid_t(fields[1])
            else { continue }
            parent[pid] = ppid
            command[pid] = fields[2...].joined(separator: " ")
        }

        // Leaf shells: a shell process whose ancestry reaches a known emulator.
        var found: [(pid_t, String)] = []
        for (pid, comm) in command {
            let name = (comm as NSString).lastPathComponent
            guard ["zsh", "-zsh", "bash", "-bash", "fish", "-fish"].contains(name) else { continue }
            if let app = emulatorAncestor(of: pid, parent: parent, command: command) {
                found.append((pid, app))
            }
        }
        guard !found.isEmpty else { return [] }

        let directories = cwds(of: found.map(\.0))
        return found.compactMap { pid, app in
            guard let dir = directories[pid] else { return nil }
            return RunningShell(pid: pid, app: app, directory: dir)
        }
        .sorted { $0.pid > $1.pid }          // newest window first
    }

    private static func emulatorAncestor(of pid: pid_t,
                                         parent: [pid_t: pid_t],
                                         command: [pid_t: String]) -> String? {
        var current = pid
        for _ in 0..<12 {                     // depth guard, never loop on cycles
            guard let next = parent[current], next > 1 else { return nil }
            let name = ((command[next] ?? "") as NSString).lastPathComponent
            if let match = emulators.first(where: { name.caseInsensitiveCompare($0) == .orderedSame }) {
                return match == "ghostty" ? "Ghostty" : match
            }
            current = next
        }
        return nil
    }

    /// `lsof -a -d cwd -p 1,2,3 -Fn` — one process, all pids.
    private static func cwds(of pids: [pid_t]) -> [pid_t: URL] {
        let list = pids.map(String.init).joined(separator: ",")
        guard let output = run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-p", list, "-Fn"])
        else { return [:] }

        var result: [pid_t: URL] = [:]
        var current: pid_t?
        for line in output.split(separator: "\n") {
            switch line.first {
            case "p": current = pid_t(line.dropFirst())
            case "n":
                if let current { result[current] = URL(fileURLWithPath: String(line.dropFirst())) }
            default: break
            }
        }
        return result
    }

    // MARK: - Process helper

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
