import AppKit
import ApplicationServices

/// Ego's hands outside the notch: other apps, their windows, their menus.
///
/// Every Accessibility call here is `nonisolated` and meant to be run off the
/// main actor. AX is synchronous IPC into another process, and a beachballed
/// app will hold the caller for as long as it likes — on the main actor that
/// is the whole notch frozen. `MediaPrimer` documents the same hazard for
/// AppleScript; this is that lesson applied to AX.
nonisolated enum SystemControl {

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        // The constant itself is a mutable global as far as Swift 6 is
        // concerned, so its string value is used directly.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    // MARK: - Apps

    /// The app a command means, matched loosely: "chrome" should find "Google
    /// Chrome", and a spoken name arrives lowercase and sometimes mangled.
    static func runningApp(named name: String) -> NSRunningApplication? {
        let needle = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return nil }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        return apps.first { $0.localizedName?.lowercased() == needle }
            ?? apps.first { ($0.localizedName?.lowercased()).map { $0.contains(needle) } ?? false }
            ?? apps.first { needle.contains(($0.localizedName ?? "").lowercased()) && !needle.isEmpty }
    }

    /// Where an app lives on disk, whether or not it is running.
    static func installedApp(named name: String) -> URL? {
        if let running = runningApp(named: name)?.bundleURL { return running }
        let needle = name.lowercased()
        for directory in ["/Applications", "/System/Applications", "/System/Applications/Utilities"] {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory)
            else { continue }
            if let match = entries.first(where: {
                let base = ($0 as NSString).deletingPathExtension.lowercased()
                return base == needle || base.contains(needle)
            }) {
                return URL(fileURLWithPath: "\(directory)/\(match)")
            }
        }
        return nil
    }

    // MARK: - Windows

    enum WindowPlace: String, CaseIterable {
        case left, right, top, bottom, maximise, centre

        /// The rect this place occupies on a screen of the given size.
        func frame(in visible: CGRect) -> CGRect {
            switch self {
            case .left:   CGRect(x: visible.minX, y: visible.minY,
                                 width: visible.width / 2, height: visible.height)
            case .right:  CGRect(x: visible.midX, y: visible.minY,
                                 width: visible.width / 2, height: visible.height)
            case .top:    CGRect(x: visible.minX, y: visible.minY,
                                 width: visible.width, height: visible.height / 2)
            case .bottom: CGRect(x: visible.minX, y: visible.midY,
                                 width: visible.width, height: visible.height / 2)
            case .maximise: visible
            case .centre: CGRect(x: visible.minX + visible.width * 0.15,
                                 y: visible.minY + visible.height * 0.1,
                                 width: visible.width * 0.7, height: visible.height * 0.8)
            }
        }
    }

    /// Moves the frontmost window of an app. Returns false when there is no
    /// window, or when Accessibility hasn't been granted.
    static func place(_ place: WindowPlace, ofApp app: NSRunningApplication) -> Bool {
        guard isTrusted else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString,
                                            &windowRef) == .success,
              let window = windowRef, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return false }
        let axWindow = window as! AXUIElement

        // Screen coordinates for AX have their origin at the TOP left, while
        // NSScreen measures from the bottom — getting this backwards puts
        // windows off the bottom of the display.
        guard let screen = NSScreen.main else { return false }
        let full = screen.frame
        let visible = screen.visibleFrame
        let flipped = CGRect(x: visible.minX,
                             y: full.height - visible.maxY,
                             width: visible.width, height: visible.height)
        let target = place.frame(in: flipped)

        var origin = CGPoint(x: target.minX, y: target.minY)
        var size = CGSize(width: target.width, height: target.height)
        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }

        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeValue)
        return true
    }

    // MARK: - Menus

    /// Finds a menu item by name anywhere in an app's menu bar and clicks it.
    ///
    /// This is the highest-leverage thing Ego can do outside the notch: it
    /// works in apps nobody has integrated with, because every Mac app already
    /// describes its commands here. Returns the item's real title, so Ego can
    /// say what it actually pressed rather than what it was asked for.
    static func pressMenuItem(matching wanted: String,
                              inApp app: NSRunningApplication) -> String? {
        guard isTrusted else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var barRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString,
                                            &barRef) == .success,
              let bar = barRef, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }

        let needle = wanted.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return nil }
        guard let match = search(bar as! AXUIElement, for: needle, depth: 0) else { return nil }
        guard AXUIElementPerformAction(match.item, kAXPressAction as CFString) == .success
        else { return nil }
        return match.title
    }

    private static func search(_ element: AXUIElement, for needle: String,
                               depth: Int) -> (item: AXUIElement, title: String)? {
        // Menus are shallow. A depth limit keeps a pathological app from
        // walking us into a loop.
        guard depth < 5 else { return nil }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString,
                                            &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        for child in children {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleRef as? String) ?? ""
            let lowered = title.lowercased()

            // An exact-ish match on a leaf item wins; submenus are followed.
            if !title.isEmpty, lowered == needle || lowered.hasPrefix(needle)
                || (needle.count >= 4 && lowered.contains(needle)) {
                var enabled: CFTypeRef?
                AXUIElementCopyAttributeValue(child, kAXEnabledAttribute as CFString, &enabled)
                if (enabled as? Bool) ?? true, isLeaf(child) {
                    return (child, title)
                }
            }
            if let found = search(child, for: needle, depth: depth + 1) { return found }
        }
        return nil
    }

    /// A submenu has children of its own; a command doesn't.
    private static func isLeaf(_ element: AXUIElement) -> Bool {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString,
                                            &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return true }
        return children.isEmpty
    }

    // MARK: - Shortcuts

    /// The user's own Shortcuts, which is how Ego reaches anything Apple
    /// hasn't given an API for — Focus modes, Wi-Fi, home automation.
    static func shortcutNames() -> [String] {
        run("/usr/bin/shortcuts", ["list"], seconds: 5)?
            .split(separator: "\n").map(String.init) ?? []
    }

    static func runShortcut(named name: String) -> Bool {
        let names = shortcutNames()
        let needle = name.lowercased()
        let match = names.first { $0.lowercased() == needle }
            ?? names.first { $0.lowercased().contains(needle) }
        guard let match else { return false }
        return run("/usr/bin/shortcuts", ["run", match], seconds: 20) != nil
    }

    /// A subprocess with a deadline. Nothing Ego runs may hang the assistant.
    @discardableResult
    private static func run(_ path: String, _ arguments: [String], seconds: Double) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning, Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
