import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ModulesSettingsTab()
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
            DisplaySettingsTab()
                .tabItem { Label("Display", systemImage: "display") }
        }
        .frame(width: 460, height: 420)
        .background(Ego.bg)
        .preferredColorScheme(.dark)
        .tint(Ego.cyan)
    }
}

/// Shared row chrome for settings sections.
struct SettingsSection<Content: View>: View {
    let index: Int
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(index: index, title: title)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .egoCard()
    }
}

#Preview("Settings") {
    SettingsView()
}
