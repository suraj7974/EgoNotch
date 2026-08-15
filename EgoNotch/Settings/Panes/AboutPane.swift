import SwiftUI

struct AboutPane: View {
    @State private var confirmingReset = false

    var body: some View {
        SettingsPane(title: "About") {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(AppInfo.name)
                        .font(Ego.font(17, .semibold))
                        .foregroundStyle(Ego.text)
                    Text("Version \(AppInfo.version)")
                        .font(Ego.font(11))
                        .egoDigits()
                        .foregroundStyle(Ego.textMute)
                    HStack(spacing: 5) {
                        Text("by \(AppInfo.owner)")
                            .font(Ego.font(11))
                            .foregroundStyle(Ego.textMute)
                        Link(AppInfo.portfolio, destination: AppInfo.portfolioURL)
                            .font(Ego.font(11, .medium))
                            .foregroundStyle(Ego.accent)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 4)

            SettingsCard(title: "Help") {
                SettingsRow(label: "Welcome tour", hint: "Replay the first-run walkthrough.") {
                    SettingsActionButton(title: "Show") {
                        NotificationCenter.default.post(name: .egoShowOnboarding, object: nil)
                    }
                }
                SettingsDivider()
                SettingsRow(label: "Reset all settings",
                            hint: confirmingReset
                                ? "This puts every option — modules included — back to its default."
                                : "Restore every option to its default.") {
                    if confirmingReset {
                        HStack(spacing: 6) {
                            SettingsActionButton(title: "Cancel") { confirmingReset = false }
                            SettingsActionButton(title: "Reset", prominent: true) {
                                SettingsStore.shared.resetAll()
                                confirmingReset = false
                            }
                        }
                    } else {
                        SettingsActionButton(title: "Reset…") { confirmingReset = true }
                    }
                }
                SettingsDivider()
                SettingsRow(label: "Quit EgoNotch") {
                    SettingsActionButton(title: "Quit") { NSApp.terminate(nil) }
                }
            }
        }
    }
}
