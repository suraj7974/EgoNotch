import SwiftUI

struct GeneralSettingsTab: View {
    @Bindable private var settings = SettingsStore.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

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
            }
            .padding(16)
        }
        .background(Ego.bg)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}
