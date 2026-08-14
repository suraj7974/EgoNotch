import SwiftUI

struct PanelPane: View {
    @Bindable private var settings = SettingsStore.shared

    private static let defaultSize = CGSize(width: 960, height: 205)

    var body: some View {
        SettingsPane(title: "Panel", subtitle: "Size of the opened notch, and the fake notch used on other displays.") {
            SizePreview(width: settings.panelWidth, height: settings.panelHeight)

            SettingsCard(title: "Opened size") {
                SettingsSliderRow(label: "Width",
                                  value: $settings.panelWidth,
                                  range: 760...1300, step: 20) { "\(Int($0)) pt" }
                SettingsDivider()
                SettingsSliderRow(label: "Height",
                                  value: $settings.panelHeight,
                                  range: 170...300, step: 5) { "\(Int($0)) pt" }
                SettingsDivider()
                SettingsRow(label: "Reset to default",
                            hint: "\(Int(Self.defaultSize.width)) × \(Int(Self.defaultSize.height)) pt") {
                    SettingsActionButton(title: "Reset") {
                        settings.panelWidth = Self.defaultSize.width
                        settings.panelHeight = Self.defaultSize.height
                    }
                }
            }

            SettingsCard(title: "Virtual notch") {
                SettingsSliderRow(label: "Width",
                                  hint: "Used on displays that have no physical notch.",
                                  value: Binding(get: { settings.virtualNotchSize.width },
                                                 set: { settings.virtualNotchSize.width = $0 }),
                                  range: 120...320, step: 10) { "\(Int($0)) pt" }
                SettingsDivider()
                SettingsSliderRow(label: "Height",
                                  value: Binding(get: { settings.virtualNotchSize.height },
                                                 set: { settings.virtualNotchSize.height = $0 }),
                                  range: 24...48, step: 2) { "\(Int($0)) pt" }
            }
        }
    }
}

/// Scaled silhouette of the screen with the panel drawn on it, so the sliders
/// mean something before you close the window and look.
private struct SizePreview: View {
    let width: Double
    let height: Double

    var body: some View {
        GeometryReader { proxy in
            let screen = NSScreen.main?.frame.size ?? CGSize(width: 1512, height: 982)
            // Fit the whole screen silhouette inside the box, never crop it.
            let scale = min(proxy.size.width / screen.width, proxy.size.height / screen.height)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Ego.border, lineWidth: 1)
                UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9)
                    .fill(Color.white.opacity(0.2))
                    .frame(width: width * scale, height: height * scale)
                    .overlay(alignment: .bottom) {
                        Text("\(Int(width)) × \(Int(height))")
                            .font(Ego.font(8.5, .medium))
                            .egoDigits()
                            .foregroundStyle(Ego.text)
                            .padding(.bottom, 2)
                    }
            }
            .frame(width: screen.width * scale, height: screen.height * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 150)
        .padding(.bottom, 2)
    }
}
