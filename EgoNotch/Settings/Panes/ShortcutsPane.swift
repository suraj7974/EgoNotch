import SwiftUI

/// Every keyboard shortcut the app owns, in one place. Two kinds live here:
/// system-wide ones (registered with the window server, work from any app) and
/// in-notch ones (only while the panel is open).
struct ShortcutsPane: View {
    @Bindable private var settings = SettingsStore.shared

    var body: some View {
        SettingsPane(title: "Shortcuts",
                     subtitle: "Keys that reach the notch from anywhere, and keys that work inside it.") {
            SettingsCard(title: "System-wide") {
                SettingsRow(label: "Open the Terminal tab",
                            hint: HotKeyStatus.shared.terminalTaken
                                ? "Another app already owns that combination — pick a different one."
                                : "Works from any app. Press it again to put the notch away.",
                            icon: "terminal") {
                    HStack(spacing: 8) {
                        if settings.terminalHotKeyEnabled {
                            HotKeyRecorder(combination: $settings.terminalHotKey)
                        }
                        Toggle("", isOn: $settings.terminalHotKeyEnabled)
                            .toggleStyle(SwitchToggleStyle(tint: Ego.accent))
                            .labelsHidden()
                    }
                }
            }

            SettingsCard(title: "Inside the notch") {
                ForEach(Array(inNotchShortcuts.enumerated()), id: \.offset) { index, shortcut in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(label: shortcut.label, icon: shortcut.icon) {
                        KeyCapLabel(text: shortcut.keys)
                    }
                }
            }
        }
    }

    private struct InNotchShortcut {
        let label: String
        let icon: String
        let keys: String
    }

    /// Fixed keys the panel handles itself while it's open.
    private var inNotchShortcuts: [InNotchShortcut] {
        [
            .init(label: "Close the panel", icon: "escape", keys: "⎋"),
            .init(label: "Copy / paste in the terminal", icon: "doc.on.doc", keys: "⌘C ⌘V"),
            .init(label: "Clear the terminal", icon: "eraser", keys: "⌘K"),
            .init(label: "Terminal font size", icon: "textformat.size", keys: "⌘+ ⌘− ⌘0"),
            .init(label: "Wipe the current line", icon: "delete.left", keys: "⌘⌫"),
        ]
    }
}

/// Static keycap for shortcuts that aren't configurable.
struct KeyCapLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Ego.font(11.5, .medium))
            .foregroundStyle(Ego.textMute)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Ego.border, lineWidth: 1))
    }
}
