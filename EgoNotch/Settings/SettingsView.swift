import SwiftUI

/// Settings window: a sidebar of panes on the left, one pane on the right.
/// Deliberately not a TabView — the stock tab strip can't be themed, and the
/// sidebar leaves room for the panes to grow.
struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, ego, shortcuts, modules, panel, focus, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .ego: "Ego"
            case .shortcuts: "Shortcuts"
            case .modules: "Modules"
            case .panel:   "Panel"
            case .focus:   "Focus"
            case .about:   "About"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape.fill"
            case .ego: "waveform.circle.fill"
            case .shortcuts: "keyboard.fill"
            case .modules: "square.grid.2x2.fill"
            case .panel:   "macwindow"
            case .focus:   "timer"
            case .about:   "info.circle.fill"
            }
        }
    }

    @State private var selection: Pane = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Ego.border).frame(width: 1)
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 520)
        .background(Ego.bg)
        .preferredColorScheme(.dark)
        .tint(Ego.accent)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(AppInfo.name)
                        .font(Ego.font(13, .semibold))
                        .foregroundStyle(Ego.text)
                    Text("v\(AppInfo.version)")
                        .font(Ego.font(10))
                        .egoDigits()
                        .foregroundStyle(Ego.textMute)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)

            ForEach(Pane.allCases) { item in
                SidebarItem(pane: item, isSelected: selection == item) {
                    selection = item
                }
            }

            Spacer(minLength: 0)

            Button {
                NotificationCenter.default.post(name: .egoShowOnboarding, object: nil)
            } label: {
                Label("Welcome tour", systemImage: "sparkles")
                    .font(Ego.font(11))
                    .foregroundStyle(Ego.textMute)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.top, 22)          // clears the traffic lights
        .frame(width: 178)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.03))
    }

    @ViewBuilder
    private var pane: some View {
        switch selection {
        case .general: GeneralPane()
        case .ego: EgoSettingsPane()
        case .shortcuts: ShortcutsPane()
        case .modules: ModulesPane()
        case .panel:   PanelPane()
        case .focus:   FocusPane()
        case .about:   AboutPane()
        }
    }
}

private struct SidebarItem: View {
    let pane: SettingsView.Pane
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: pane.icon)
                    .font(.system(size: 11.5))
                    .foregroundStyle(isSelected ? Ego.accent : Ego.textMute)
                    .frame(width: 17)
                Text(pane.title)
                    .font(Ego.font(12.5, isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Ego.text : Ego.textMute)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isSelected ? 0.10 : (hovering ? 0.05 : 0)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering = $0 }
    }
}

#Preview("Settings") {
    SettingsView()
}
