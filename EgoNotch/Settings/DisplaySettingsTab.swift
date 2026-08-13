import SwiftUI

struct DisplaySettingsTab: View {
    @Bindable private var settings = SettingsStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: Ego.gridSpacing) {
                SettingsSection(index: 5, title: "Virtual Notch") {
                    Text("USED ON DISPLAYS WITHOUT A PHYSICAL NOTCH")
                        .font(Ego.mono(9))
                        .tracking(1)
                        .foregroundStyle(Ego.textMute)

                    HStack {
                        Text("WIDTH")
                            .font(Ego.mono(10))
                            .foregroundStyle(Ego.textMute)
                        Slider(
                            value: Binding(
                                get: { settings.virtualNotchSize.width },
                                set: { settings.virtualNotchSize.width = $0 }
                            ),
                            in: 120...320, step: 10
                        )
                        Text("\(Int(settings.virtualNotchSize.width))PT")
                            .font(Ego.mono(10))
                            .egoDigits()
                            .foregroundStyle(Ego.cyan)
                            .frame(width: 48, alignment: .trailing)
                    }

                    HStack {
                        Text("HEIGHT")
                            .font(Ego.mono(10))
                            .foregroundStyle(Ego.textMute)
                        Slider(
                            value: Binding(
                                get: { settings.virtualNotchSize.height },
                                set: { settings.virtualNotchSize.height = $0 }
                            ),
                            in: 24...48, step: 2
                        )
                        Text("\(Int(settings.virtualNotchSize.height))PT")
                            .font(Ego.mono(10))
                            .egoDigits()
                            .foregroundStyle(Ego.cyan)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
            .padding(16)
        }
        .background(Ego.bg)
    }
}
