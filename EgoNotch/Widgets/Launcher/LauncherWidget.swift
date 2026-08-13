import SwiftUI
import Observation
import UniformTypeIdentifiers

/// Phase 5 — pinned-app launcher row (Home tab). Configure by clicking +
/// (app picker) or dropping .app bundles onto the tile; right-click removes.
final class LauncherWidget: NotchWidget {
    let id = "launcher"
    let displayName = "Launcher"
    let icon = "square.grid.3x1.below.line.grid.1x2"
    let tileSize: WidgetTileSize = .wide
    let tab: NotchTab = .home

    let store = LauncherStore()

    func makeExpandedView() -> AnyView {
        AnyView(LauncherTileView(store: store))
    }
}

@Observable
final class LauncherStore {
    private(set) var appPaths: [String] = []

    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let key = "launcher.apps"

    init() {
        appPaths = defaults.stringArray(forKey: Self.key) ?? []
    }

    func add(_ path: String) {
        let standardized = (path as NSString).standardizingPath
        guard standardized.hasSuffix(".app"),
              FileManager.default.fileExists(atPath: standardized),
              !appPaths.contains(standardized) else { return }
        appPaths.append(standardized)
        defaults.set(appPaths, forKey: Self.key)
    }

    func remove(_ path: String) {
        appPaths.removeAll { $0 == path }
        defaults.set(appPaths, forKey: Self.key)
    }

    func launch(_ path: String) {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path),
            configuration: NSWorkspace.OpenConfiguration())
    }

    func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        NSApp.activate()
        if panel.runModal() == .OK {
            for url in panel.urls { add(url.path) }
        }
    }
}

struct LauncherTileView: View {
    var store: LauncherStore
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            ForEach(store.appPaths, id: \.self) { path in
                LauncherIcon(path: path, store: store)
            }
            addButton
            Spacer(minLength: 0)
        }
        .frame(minHeight: 46)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            FileDropHandler.load(providers) { urls in
                for url in urls where url.pathExtension == "app" {
                    store.add(url.path)
                }
                // Non-app files must not vanish — route them like the chrome.
                let rest = urls.filter { $0.pathExtension != "app" }
                if !rest.isEmpty, let consumer = WidgetRegistry.handleDroppedFiles(rest) {
                    PanelUIState.shared.selectedTab = consumer.tab
                }
            }
            return true
        }
        .overlay(
            RoundedRectangle(cornerRadius: Ego.cardRadius)
                .strokeBorder(Color.white.opacity(dropTargeted ? 0.3 : 0),
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .padding(-6)
        )
    }

    private var addButton: some View {
        Button {
            store.pickApp()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ego.textMute)
                .frame(width: 40, height: 40)
                .background(Ego.surface2, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("Pin an app")
    }
}

private struct LauncherIcon: View {
    let path: String
    let store: LauncherStore
    @State private var hovered = false

    var body: some View {
        Button {
            store.launch(path)
        } label: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 40, height: 40)
                .scaleEffect(hovered ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .onHover { over in
            withAnimation(Ego.Motion.spring()) { hovered = over }
        }
        .contextMenu {
            Button("Unpin") { store.remove(path) }
        }
        .help((path as NSString).lastPathComponent)
    }
}
