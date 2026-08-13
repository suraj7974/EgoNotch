import SwiftUI

struct GeneralSettingsTab: View {
    @Bindable private var settings = SettingsStore.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        ScrollView {
            VStack(spacing: Ego.gridSpacing) {
                SettingsSection(index: 1, title: "Startup") {
                    Toggle("LAUNCH AT LOGIN", isOn: Binding(
                        get: { launchAtLogin },
                        set: { launchAtLogin = LaunchAtLogin.set($0) }
                    ))
                    .font(Ego.mono(11))
                    .toggleStyle(.switch)

                    if LaunchAtLogin.requiresApproval {
                        HStack(spacing: 8) {
                            Chip(text: "NEEDS APPROVAL", variant: .loss)
                            Button("Open Login Items") { LaunchAtLogin.openSystemSettings() }
                                .buttonStyle(.egoSecondary)
                        }
                    } else if LaunchAtLogin.runningOutsideApplications {
                        Text("RUNNING FROM A BUILD DIR — INSTALL TO /APPLICATIONS BEFORE ENABLING")
                            .font(Ego.mono(9))
                            .tracking(1)
                            .foregroundStyle(Ego.textMute)
                    }
                }

                SettingsSection(index: 2, title: "Expansion") {
                    Picker("MODE", selection: $settings.expandOnHover) {
                        Text("HOVER").tag(true)
                        Text("CLICK").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .font(Ego.mono(11))

                    if settings.expandOnHover {
                        HStack {
                            Text("DWELL")
                                .font(Ego.mono(10))
                                .foregroundStyle(Ego.textMute)
                            Slider(value: $settings.hoverDwell, in: 0.1...1.0, step: 0.05)
                            Text(String(format: "%.2fS", settings.hoverDwell))
                                .font(Ego.mono(10))
                                .egoDigits()
                                .foregroundStyle(Ego.cyan)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }

                SettingsSection(index: 3, title: "Motion") {
                    HStack {
                        Text("SPEED")
                            .font(Ego.mono(10))
                            .foregroundStyle(Ego.textMute)
                        Slider(value: $settings.animationSpeed, in: 0.5...2.0, step: 0.1)
                        Text(String(format: "%.1fX", settings.animationSpeed))
                            .font(Ego.mono(10))
                            .egoDigits()
                            .foregroundStyle(Ego.cyan)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
            .padding(16)
        }
        .background(Ego.bg)
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}
