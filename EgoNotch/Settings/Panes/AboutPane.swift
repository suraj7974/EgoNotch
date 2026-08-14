import SwiftUI

struct AboutPane: View {
    @Bindable private var settings = SettingsStore.shared
    @State private var updateChecker = UpdateChecker()

    var body: some View {
        SettingsPane(title: "About") {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("EgoNotch")
                        .font(Ego.font(17, .semibold))
                        .foregroundStyle(Ego.text)
                    Text("Version \(UpdateChecker.currentVersion)")
                        .font(Ego.font(11))
                        .egoDigits()
                        .foregroundStyle(Ego.textMute)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 4)

            SettingsCard(title: "Updates") {
                SettingsRow(label: "GitHub repository",
                            hint: "Optional. With no repo set, the app never touches the network.") {
                    EgoTextField(placeholder: "owner/name",
                                 text: $settings.updateRepo,
                                 placeholderColor: Ego.textMute)
                        .frame(width: 190)
                }
                SettingsDivider()
                SettingsRow(label: "Latest release", hint: statusHint) {
                    HStack(spacing: 8) {
                        statusBadge
                        if case .available = updateChecker.status {
                            SettingsActionButton(title: "View", prominent: true) {
                                updateChecker.openRelease()
                            }
                        }
                        SettingsActionButton(title: "Check") {
                            updateChecker.check(repo: settings.updateRepo)
                        }
                        .disabled(settings.updateRepo.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }

            SettingsCard(title: "Help") {
                SettingsRow(label: "Welcome tour", hint: "Replay the first-run walkthrough.") {
                    SettingsActionButton(title: "Show") {
                        NotificationCenter.default.post(name: .egoShowOnboarding, object: nil)
                    }
                }
                SettingsDivider()
                SettingsRow(label: "Quit EgoNotch") {
                    SettingsActionButton(title: "Quit") { NSApp.terminate(nil) }
                }
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch updateChecker.status {
        case .idle:      EmptyView()
        case .checking:  SettingsBadge(text: "Checking…")
        case .upToDate:  SettingsBadge(text: "Up to date", tint: Ego.win)
        case .available(let version, _): SettingsBadge(text: "v\(version)", tint: Ego.accent)
        case .failed:    SettingsBadge(text: "Check failed", tint: Ego.loss)
        }
    }

    private var statusHint: String? {
        if case .failed = updateChecker.status {
            return "Couldn't reach GitHub, or that repo has no releases."
        }
        return nil
    }
}
