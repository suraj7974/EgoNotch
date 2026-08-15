import AppKit
import Carbon.HIToolbox

/// What Ego is allowed to type into your shell.
///
/// A voice assistant runs on a transcript, and a transcript is a guess. The
/// gap between "delete the branch" and "delete the drive" is one misheard
/// word, so the terminal is the one place where being wrong is unrecoverable.
/// Three tiers, in order of severity:
///
///   • **blocked** — never runs, and no confirmation is offered. Saying yes to
///     a misheard `sudo rm -rf /` must not be *possible*.
///   • **confirm** — the default for anything typed into a shell. Ego reads it
///     back and waits for a spoken "confirm" or a click.
///   • **auto** — reads that change nothing.
enum Guardrails {
    enum Verdict: Equatable {
        case auto
        case confirm
        case blocked(String)
    }

    /// Commands that are refused outright. Matched on the normalised text, so
    /// spacing and quoting tricks don't slip past.
    private static let forbidden: [(pattern: String, why: String)] = [
        ("rm -rf /", "that erases the whole disk"),
        ("rm -rf /*", "that erases the whole disk"),
        ("rm -rf ~", "that erases your home folder"),
        ("mkfs", "that formats a disk"),
        ("diskutil erase", "that erases a disk"),
        ("dd if=", "that writes raw blocks over a device"),
        ("> /dev/disk", "that writes over a disk device"),
        ("of=/dev/disk", "that writes over a disk device"),
        (":(){:|:&};:", "that's a fork bomb"),
        ("chmod -r 777 /", "that strips permissions from the whole disk"),
        ("chown -r / ", "that reassigns the whole disk"),
        ("killall -9 kernel", "that would take the machine down"),
        ("shutdown", "I don't do shutdowns"),
        ("reboot", "I don't do reboots"),
    ]

    /// `sudo` is special: it isn't one dangerous command, it's the removal of
    /// every safety net at once — and the shell will sit there waiting for a
    /// password Ego can't see you type.
    private static let requiresSudo = ["sudo ", "sudo\t", "doas "]

    /// Piping the internet into a shell is the single most common way a Mac
    /// gets owned, and no misheard sentence should be able to do it.
    private static let pipedToShell = ["| sh", "| bash", "| zsh", "|sh", "|bash", "|zsh"]

    static func judge(command raw: String) -> Verdict {
        let text = raw.lowercased().split(separator: " ").joined(separator: " ")
        let squashed = text.replacingOccurrences(of: " ", with: "")

        for entry in forbidden {
            let needle = entry.pattern.replacingOccurrences(of: " ", with: "")
            if squashed.contains(needle) { return .blocked(entry.why) }
        }
        if requiresSudo.contains(where: { text.hasPrefix($0) || text.contains(" \($0)") }) {
            return .blocked("I won't run anything as root")
        }
        if pipedToShell.contains(where: { text.contains($0) }),
           text.contains("curl") || text.contains("wget") {
            return .blocked("that pipes the internet straight into a shell")
        }
        return .confirm
    }

    /// True while a password field somewhere has taken the keyboard. Typing
    /// into it would send the keystrokes into that field — and into whatever
    /// the terminal does with them afterwards.
    static var secureInputActive: Bool { IsSecureEventInputEnabled() }
}
