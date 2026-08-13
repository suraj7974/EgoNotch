import SwiftUI

struct GeneralSettingsTab: View {
    @Bindable private var settings = SettingsStore.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var updateChecker = UpdateChecker()

    var body: some View {
        ScrollView {
            VStack(spacing: Ego.gridSpacing) {
                SettingsSection(index: 1, title: "Startup") {
                    Toggle("Launch at login", isOn: Binding(
                        get: { launchAtLogin },
                        set: { launchAtLogin = LaunchAtLogin.set($0) }
                    ))
                    .font(Ego.font(12))
                    .toggleStyle(.switch)

                    if LaunchAtLogin.requiresApproval {
                        HStack(spacing: 8) {
                            Chip(text: "Needs approval", variant: .loss)
                            Button("Open Login Items") { LaunchAtLogin.openSystemSettings() }
                                .buttonStyle(.egoSecondary)
                        }
                    } else if LaunchAtLogin.runningOutsideApplications {
                        Text("Running from a build directory — install to /Applications before enabling.")
                            .font(Ego.font(10))
                            .foregroundStyle(Ego.textMute)
                    }
                }

                SettingsSection(index: 2, title: "Expansion") {
                    Picker("Mode", selection: $settings.expandOnHover) {
                        Text("Hover").tag(true)
                        Text("Click").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .font(Ego.font(12))

                    if settings.expandOnHover {
                        HStack {
                            Text("Dwell")
                                .font(Ego.font(11))
                                .foregroundStyle(Ego.textMute)
                            Slider(value: $settings.hoverDwell, in: 0.1...1.0, step: 0.05)
                            Text(String(format: "%.2f s", settings.hoverDwell))
                                .font(Ego.font(11))
                                .egoDigits()
                                .foregroundStyle(Ego.text)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }

                SettingsSection(index: 5, title: "Focus Timer") {
                    Stepper("Focus: \(settings.focusMinutes) min",
                            value: $settings.focusMinutes, in: 5...120, step: 5)
                        .font(Ego.font(12))
                    Stepper("Break: \(settings.breakMinutes) min",
                            value: $settings.breakMinutes, in: 1...30, step: 1)
                        .font(Ego.font(12))
                    Stepper("Deep: \(settings.deepMinutes) min",
                            value: $settings.deepMinutes, in: 10...180, step: 5)
                        .font(Ego.font(12))
                }

                SettingsSection(index: 4, title: "Weather") {
                    HStack {
                        Text("City")
                            .font(Ego.font(11))
                            .foregroundStyle(Ego.textMute)
                        TextField("Automatic (location)", text: $settings.weatherCity)
                            .textFieldStyle(.plain)
                            .font(Ego.font(12))
                            .foregroundStyle(Ego.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Ego.surface2, in: RoundedRectangle(cornerRadius: 8))
                    }
                    Text("Leave empty to use your location.")
                        .font(Ego.font(10))
                        .foregroundStyle(Ego.textMute)
                }

                SettingsSection(index: 3, title: "Motion") {
                    HStack {
                        Text("Speed")
                            .font(Ego.font(11))
                            .foregroundStyle(Ego.textMute)
                        Slider(value: $settings.animationSpeed, in: 0.5...2.0, step: 0.1)
                        Text(String(format: "%.1f×", settings.animationSpeed))
                            .font(Ego.font(11))
                            .egoDigits()
                            .foregroundStyle(Ego.text)
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                SettingsSection(index: 7, title: "About") {
                    HStack {
                        Text("EgoNotch v\(UpdateChecker.currentVersion)")
                            .font(Ego.font(11))
                            .egoDigits()
                            .foregroundStyle(Ego.textMute)
                        Spacer()
                        Button("Show Welcome Tour") {
                            NotificationCenter.default.post(name: .egoShowOnboarding, object: nil)
                        }
                        .buttonStyle(.egoSecondary)
                    }
                    HStack {
                        Text("GitHub repo")
                            .font(Ego.font(11))
                            .foregroundStyle(Ego.textMute)
                        TextField("owner/name (optional)", text: $settings.updateRepo)
                            .textFieldStyle(.plain)
                            .font(Ego.font(12))
                            .foregroundStyle(Ego.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Ego.surface2, in: RoundedRectangle(cornerRadius: 8))
                        if !settings.updateRepo.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Check") {
                                updateChecker.check(repo: settings.updateRepo)
                            }
                            .buttonStyle(.egoSecondary)
                        }
                    }
                    switch updateChecker.status {
                    case .idle:
                        EmptyView()
                    case .checking:
                        Text("Checking…")
                            .font(Ego.font(10))
                            .foregroundStyle(Ego.textMute)
                    case .upToDate:
                        Chip(text: "Up to date", variant: .win)
                    case .available(let version, _):
                        HStack(spacing: 8) {
                            Chip(text: "v\(version) available", variant: .accent)
                            Button("View Release") { updateChecker.openRelease() }
                                .buttonStyle(.egoSecondary)
                        }
                    case .failed:
                        Chip(text: "Check failed", variant: .loss)
                    }
                }
            }
            .padding(16)
        }
        .background(Ego.bg)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}
