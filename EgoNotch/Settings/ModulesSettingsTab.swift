import SwiftUI

struct ModulesSettingsTab: View {
    private var settings = SettingsStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: Ego.gridSpacing) {
                SettingsSection(index: 4, title: "Modules") {
                    if WidgetRegistry.all.isEmpty {
                        Text("No modules registered")
                            .font(Ego.font(11))
                            .foregroundStyle(Ego.textMute)
                    } else {
                        ForEach(WidgetRegistry.all, id: \.id) { widget in
                            HStack(spacing: 10) {
                                Image(systemName: widget.icon)
                                    .foregroundStyle(Ego.text)
                                    .frame(width: 20)
                                Text(widget.displayName)
                                    .font(Ego.font(12))
                                    .foregroundStyle(Ego.text)
                                Spacer()
                                Toggle("", isOn: settings.enabledBinding(for: widget))
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Ego.bg)
    }
}
