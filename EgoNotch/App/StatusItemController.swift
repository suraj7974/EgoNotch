import AppKit

/// Menu bar presence: template icon + Open / Settings… / Quit.
final class StatusItemController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    /// Optional countdown text beside the icon (Focus timer).
    func setText(_ text: String?) {
        item.button?.title = text.map { " \($0)" } ?? ""
        item.button?.imagePosition = .imageLeading
        item.length = text == nil ? NSStatusItem.squareLength : NSStatusItem.variableLength
    }

    init(openNotch: Selector, openSettings: Selector, target: AnyObject) {
        item.button?.image = NSImage(systemSymbolName: "sparkles.rectangle.stack",
                                     accessibilityDescription: "EgoNotch")
        item.button?.image?.isTemplate = true   // adapts to menu bar appearance
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

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
