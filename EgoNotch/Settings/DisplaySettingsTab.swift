import SwiftUI

struct DisplaySettingsTab: View {
    @Bindable private var settings = SettingsStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: Ego.gridSpacing) {
                SettingsSection(index: 6, title: "Panel Size") {
                    HStack {
                        Text("Width")
                            .font(Ego.font(11))
                            .foregroundStyle(Ego.textMute)
                        Slider(value: $settings.panelWidth, in: 560...920, step: 20)
                        Text("\(Int(settings.panelWidth)) pt")
                            .font(Ego.font(11))
                            .egoDigits()
                            .foregroundStyle(Ego.text)
                            .frame(width: 52, alignment: .trailing)
                    }
                    HStack {
                        Text("Height")
                            .font(Ego.font(11))
                            .foregroundStyle(Ego.textMute)
                        Slider(value: $settings.panelHeight, in: 300...560, step: 20)
                        Text("\(Int(settings.panelHeight)) pt")
                            .font(Ego.font(11))
                            .egoDigits()
                            .foregroundStyle(Ego.text)
                            .frame(width: 52, alignment: .trailing)
                    }
                }

                SettingsSection(index: 5, title: "Virtual Notch") {
                    Text("Used on displays without a physical notch.")
                        .font(Ego.font(10))
                        .foregroundStyle(Ego.textMute)

                    HStack {
                        Text("Width")
                            .font(Ego.font(11))
                            .foregroundStyle(Ego.textMute)
                        Slider(
                            value: Binding(
                                get: { settings.virtualNotchSize.width },
                                set: { settings.virtualNotchSize.width = $0 }
                            ),
                            in: 120...320, step: 10
                        )
                        Text("\(Int(settings.virtualNotchSize.width)) pt")
                            .font(Ego.font(11))
                            .egoDigits()
                            .foregroundStyle(Ego.text)
                            .frame(width: 48, alignment: .trailing)
                    }

                    HStack {
                        Text("Height")
                            .font(Ego.font(11))
                            .foregroundStyle(Ego.textMute)
                        Slider(
                            value: Binding(
                                get: { settings.virtualNotchSize.height },
                                set: { settings.virtualNotchSize.height = $0 }
                            ),
                            in: 24...48, step: 2
                        )
                        Text("\(Int(settings.virtualNotchSize.height)) pt")
                            .font(Ego.font(11))
                            .egoDigits()
                            .foregroundStyle(Ego.text)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
            .padding(16)
        }
        .background(Ego.bg)
    }
}
