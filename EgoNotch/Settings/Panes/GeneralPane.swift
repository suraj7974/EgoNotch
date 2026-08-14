import SwiftUI

struct GeneralPane: View {
    @Bindable private var settings = SettingsStore.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        SettingsPane(title: "General", subtitle: "How the notch starts up and opens.") {
            SettingsCard(title: "Startup") {
                SettingsRow(label: "Launch at login",
                            hint: startupHint,
                            icon: "power") {
                    Toggle("", isOn: Binding(
                        get: { launchAtLogin },
                        set: { launchAtLogin = LaunchAtLogin.set($0) }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: Ego.accent))
                    .labelsHidden()
                }
                if LaunchAtLogin.requiresApproval {
                    SettingsDivider()
                    SettingsRow(label: "Approval needed",
                                hint: "macOS is holding the login item until you allow it.",
                                icon: "exclamationmark.triangle") {
                        SettingsActionButton(title: "Open Login Items") {
                            LaunchAtLogin.openSystemSettings()
                        }
                    }
                }
            }

            SettingsCard(title: "Opening") {
                SettingsRow(label: "Open the panel on",
                            hint: settings.expandOnHover
                                ? "Point at the notch and wait."
                                : "Only a click opens it — hovering does nothing.",
                            icon: "cursorarrow.rays") {
                    Picker("", selection: $settings.expandOnHover) {
                        Text("Hover").tag(true)
                        Text("Click").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 140)
                }
                if settings.expandOnHover {
                    SettingsDivider()
                    SettingsSliderRow(label: "Hover delay",
                                      hint: "How long to point before it opens.",
                                      value: $settings.hoverDwell,
                                      range: 0.1...1.0, step: 0.05) {
                        String(format: "%.2f s", $0)
                    }
                }
            }

            SettingsCard(title: "Visibility") {
                SettingsRow(label: "Hide during fullscreen",
                            hint: "Gets out of the way of fullscreen video, presentations and games.",
                            icon: "rectangle.inset.filled.and.person.filled") {
                    Toggle("", isOn: $settings.hideInFullScreen)
                        .toggleStyle(SwitchToggleStyle(tint: Ego.accent))
                        .labelsHidden()
                }
                SettingsDivider()
                SettingsRow(label: "Invisible on shared screens",
                            hint: "While a call is live — Meet, Zoom, Teams — the notch keeps working for you but is left out of screen shares, recordings and screenshots.",
                            icon: "video.badge.waveform") {
                    Toggle("", isOn: $settings.hideInMeetings)
                        .toggleStyle(SwitchToggleStyle(tint: Ego.accent))
                        .labelsHidden()
                }
            }

            SettingsCard(title: "Motion") {
                SettingsSliderRow(label: "Animation speed",
                                  hint: "Applies to every spring in the app.",
                                  value: $settings.animationSpeed,
                                  range: 0.5...2.0, step: 0.1) {
                    String(format: "%.1f×", $0)
                }
            }
        }
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private var startupHint: String? {
        LaunchAtLogin.runningOutsideApplications
            ? "Running from a build folder — install to /Applications first."
            : nil
    }
}
