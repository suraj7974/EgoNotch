import AppKit
import Observation

/// tmux sessions the notch can attach to.
///
/// macOS gives no way to move another app's shell into our process, so this is
/// the one honest form of "use the terminal I already have": a tmux session
/// isn't bound to any terminal, so Ghostty and the notch can hold the same one
/// at the same time.
@MainActor
@Observable
final class TerminalSessions {
    struct TmuxSession: Identifiable {
        let name: String
        let windows: Int
        let attached: Bool
        var id: String { name }
    }

    private(set) var tmuxSessions: [TmuxSession] = []

    static let tmuxPath: String? = {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// Cheap enough to run when the tab appears; never on a timer.
    func refresh() {
        tmuxSessions = Self.loadTmuxSessions()
    }

    private static func loadTmuxSessions() -> [TmuxSession] {
        guard let tmux = tmuxPath,
              let output = run(tmux, ["list-sessions",
                                      "-F", "#{session_name}\t#{session_windows}\t#{session_attached}"])
        else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t")
            guard parts.count == 3 else { return nil }
            return TmuxSession(name: String(parts[0]),
                               windows: Int(parts[1]) ?? 1,
                               attached: parts[2] != "0")
        }
    }

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
