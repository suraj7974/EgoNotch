import SwiftUI

struct FocusPane: View {
    @Bindable private var settings = SettingsStore.shared

    var body: some View {
        SettingsPane(title: "Focus", subtitle: "Preset lengths for the Pomodoro buttons on the Focus tab.") {
            SettingsCard(title: "Session lengths") {
                SettingsStepperRow(label: "Focus", value: $settings.focusMinutes,
                                   range: 5...120, step: 5, suffix: " min")
                SettingsDivider()
                SettingsStepperRow(label: "Break", value: $settings.breakMinutes,
                                   range: 1...30, step: 1, suffix: " min")
                SettingsDivider()
                SettingsStepperRow(label: "Deep work", value: $settings.deepMinutes,
                                   range: 10...180, step: 5, suffix: " min")
            }
        }
    }
}
