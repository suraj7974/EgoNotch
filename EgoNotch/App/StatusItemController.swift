import AppKit

/// Menu bar presence: template icon + Open / Settings… / Quit, plus the one
/// switch worth reaching for mid-call.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let hideFromSharing = NSMenuItem(title: "Hide from screen sharing",
                                             action: #selector(toggleHideFromSharing),
                                             keyEquivalent: "")

    /// Optional countdown text beside the icon (Focus timer).
    func setText(_ text: String?) {
        item.button?.title = text.map { " \($0)" } ?? ""
        item.button?.imagePosition = .imageLeading
        item.length = text == nil ? NSStatusItem.squareLength : NSStatusItem.variableLength
    }

    init(openNotch: Selector, openSettings: Selector, target: AnyObject) {
        super.init()

        item.button?.image = NSImage(systemSymbolName: "sparkles.rectangle.stack",
                                     accessibilityDescription: "EgoNotch")
        item.button?.image?.isTemplate = true   // adapts to menu bar appearance
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        let menu = NSMenu()
        menu.delegate = self                    // refreshes the checkmark on open

        let open = NSMenuItem(title: "Open EgoNotch", action: openNotch, keyEquivalent: "o")
        open.target = target
        menu.addItem(open)

        hideFromSharing.target = self
        hideFromSharing.toolTip = "While you're on a call, keep the notch off screen shares and recordings — you still see it."
        menu.addItem(hideFromSharing)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: openSettings, keyEquivalent: ",")
        settings.target = target
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit EgoNotch",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        item.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        hideFromSharing.state = SettingsStore.shared.hideInMeetings ? .on : .off
    }

    @objc private func toggleHideFromSharing() {
        SettingsStore.shared.hideInMeetings.toggle()
    }
}
