import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        app.mainMenu = makeMainMenu()   // invisible in LSUIElement apps, but it
                                        // routes ⌘W/⌘Q/⌘C… like a normal Mac app
        let delegate = AppDelegate()
        app.delegate = delegate   // NSApplication holds delegates weakly; the
        app.run()                 // local survives because run() never returns
    }

    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit EgoNotch",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window",
                         action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        return main
    }

    private var statusItem: StatusItemController?
    private var notchPanel: NotchPanelController?
    private let settingsWindow = SettingsWindowController()
    private let onboarding = OnboardingWindowController()

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
        nc.addObserver(self, selector: #selector(menuBarTextChanged(_:)),
                       name: .egoMenuBarText, object: nil)
        nc.addObserver(self, selector: #selector(showOnboarding),
                       name: .egoShowOnboarding, object: nil)

        onboarding.showIfNeeded()

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
    @objc private func menuBarTextChanged(_ note: Notification) {
        statusItem?.setText(note.userInfo?["text"] as? String)
    }
    @objc private func showOnboarding() { onboarding.show() }
}
