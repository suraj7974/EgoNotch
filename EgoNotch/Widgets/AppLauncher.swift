import AppKit

/// Opens (or focuses) a companion app for a widget — never launches anything
/// that isn't installed.
enum AppLauncher {
    static func open(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    /// Falls back to a running app with a matching name (browsers, etc.).
    static func open(named name: String) {
        // `runningApplications(withBundleIdentifier: "")` — which this used to
        // ask — matches applications whose bundle id is the empty string, so it
        // never found anything and clicking a player's icon did nothing.
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
        }) {
            // Already open: bring it forward rather than asking to launch it
            // again, which leaves the window where it was.
            running.activate(options: [.activateAllWindows])
            return
        }
        for dir in ["/Applications", "/System/Applications"] {
            let path = "\(dir)/\(name).app"
            if FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path),
                                                   configuration: .init())
                return
            }
        }
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
