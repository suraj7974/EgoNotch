import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate   // NSApplication holds delegates weakly; the
        app.run()                 // local survives because run() never returns
    }

    private var statusItem: StatusItemController?
    private var notchPanel: NotchPanelController?
    private let settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = SettingsStore.shared
        WidgetRegistry.syncActivation()

        notchPanel = NotchPanelController()
        statusItem = StatusItemController(openNotch: #selector(openNotch),
                                          openSettings: #selector(openSettings),
                                          target: self)

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(openSettings),
                       name: .egoOpenSettings, object: nil)
        nc.addObserver(self, selector: #selector(collapseNotch),
                       name: .egoCollapseNotch, object: nil)

        // Debug: EGO_DEBUG_EXPAND=1 auto-expands the panel (headless testing).
        if ProcessInfo.processInfo.environment["EGO_DEBUG_EXPAND"] == "1" {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.notchPanel?.expand()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for widget in WidgetRegistry.all { widget.deactivate() }
    }

    @objc private func openNotch() { notchPanel?.expand() }
    @objc private func collapseNotch() { notchPanel?.stateController.collapse() }
    @objc private func openSettings() { settingsWindow.show() }
}
