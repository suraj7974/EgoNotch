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
