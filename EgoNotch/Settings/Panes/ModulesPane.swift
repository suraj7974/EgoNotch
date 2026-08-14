import SwiftUI

/// Every widget, grouped by the tab it appears on, so turning something off
/// tells you what will disappear and from where.
struct ModulesPane: View {
    private var settings = SettingsStore.shared

    var body: some View {
        SettingsPane(title: "Modules",
                     subtitle: "\(WidgetRegistry.enabled.count) of \(WidgetRegistry.all.count) enabled. A tab disappears when all of its modules are off.") {
            ForEach(NotchTab.allCases) { tab in
                let widgets = WidgetRegistry.all.filter { $0.tab == tab }
                if !widgets.isEmpty {
                    SettingsCard(title: tab.title) {
                        ForEach(Array(widgets.enumerated()), id: \.element.id) { index, widget in
                            if index > 0 { SettingsDivider() }
                            row(widget)
                        }
                    }
                }
            }
        }
    }

    private func row(_ widget: any NotchWidget) -> some View {
        SettingsRow(label: widget.displayName,
                    hint: hint(for: widget),
                    icon: widget.icon) {
            Toggle("", isOn: settings.enabledBinding(for: widget))
                .toggleStyle(SwitchToggleStyle(tint: Ego.accent))
                .labelsHidden()
        }
    }

    private func hint(for widget: any NotchWidget) -> String? {
        var notes: [String] = []
        if widget.makeClosedAccessory(for: .leading) != nil
            || widget.makeClosedAccessory(for: .trailing) != nil {
            notes.append("shows on the closed notch")
        }
        if widget.makeTopBarAccessory() != nil { notes.append("shows in the top bar") }
        if widget.acceptsDroppedFiles { notes.append("accepts drops") }
        return notes.isEmpty ? nil : notes.joined(separator: " · ")
    }
}
