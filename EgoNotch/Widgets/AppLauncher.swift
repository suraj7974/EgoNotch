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
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: "")
            .first(where: { $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame }),
           let url = running.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
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
