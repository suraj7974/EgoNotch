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
                SettingsRow(label: "Switch tabs",
                            hint: "By position in the tab bar, so disabled modules never leave a gap.",
                            icon: "square.grid.2x2") {
                    KeyCapLabel(text: "⌥1…⌥\(min(PanelUIState.shared.availableTabs.count, 9))")
                }
                ForEach(Array(PanelUIState.shared.availableTabs.prefix(9).enumerated()),
                        id: \.element.id) { index, tab in
                    SettingsDivider()
                    SettingsRow(label: tab.title, icon: tab.icon) {
                        KeyCapLabel(text: "⌥\(index + 1)")
                    }
                }
            }
        }
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
