import AppKit

/// Menu bar presence: template icon + Open / Settings… / Quit.
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(openNotch: Selector, openSettings: Selector, target: AnyObject) {
        item.button?.image = NSImage(systemSymbolName: "sparkles.rectangle.stack",
                                     accessibilityDescription: "EgoNotch")
        item.button?.image?.isTemplate = true   // adapts to menu bar appearance

        let menu = NSMenu()
        let open = NSMenuItem(title: "Open EgoNotch", action: openNotch, keyEquivalent: "o")
        open.target = target
        menu.addItem(open)
        let settings = NSMenuItem(title: "Settings…", action: openSettings, keyEquivalent: ",")
        settings.target = target
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit EgoNotch",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
    }
}
