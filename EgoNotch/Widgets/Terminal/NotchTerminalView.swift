import AppKit
import SwiftTerm

/// The terminal view with the ⌘ shortcuts a Mac terminal is expected to have.
///
/// EgoNotch is an LSUIElement agent with no Edit menu, so nothing in the
/// responder chain claims ⌘C / ⌘V — without this the Command key does nothing
/// at all inside the notch terminal.
final class NotchTerminalView: LocalProcessTerminalView {
    /// Called when a shortcut changes the look (font size), so the owner can
    /// re-apply the theme — SwiftUI isn't watching that setting from here.
    var onAppearanceChange: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == [.command, .shift] else {
            return super.performKeyEquivalent(with: event)
        }

        // Line editing the way macOS text fields do it — the shell's own
        // control codes, sent on the keys muscle memory reaches for.
        switch event.keyCode {
        case 51:                                    // ⌘⌫ — wipe the line
            send(txt: "\u{15}")                     // ^U
            return true
        case 123:                                   // ⌘← — start of line
            send(txt: "\u{1}")                      // ^A
            return true
        case 124:                                   // ⌘→ — end of line
            send(txt: "\u{5}")                      // ^E
            return true
        default:
            break
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            copy(self)
        case "v":
            paste(self)
        case "a":
            selectAll(nil)
        case "k":
            // Ghostty's clear: wipe the screen and the scrollback, then let
            // the shell redraw its prompt.
            getTerminal().clearScrollback()
            getTerminal().resetToInitialState()
            send(txt: "\u{c}")                      // ^L
        case "+", "=":
            adjustFontSize(by: 1)
        case "-":
            adjustFontSize(by: -1)
        case "0":
            SettingsStore.shared.terminalFontSize = 12
            onAppearanceChange?()
        default:
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    private func adjustFontSize(by delta: Double) {
        let settings = SettingsStore.shared
        settings.terminalFontSize = min(18, max(9, settings.terminalFontSize + delta))
        onAppearanceChange?()
    }
}
