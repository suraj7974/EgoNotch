import AppKit

/// Click-outside detection while the panel is expanded. The tracking area
/// can't see clicks landing in other apps, so a global monitor covers those
/// and a local monitor covers our own windows. Installed ONLY while expanded
/// and torn down on collapse — the idle app has zero monitors.
///
/// Mouse monitors do not require the Accessibility permission.
final class ClickOutsideMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(onClick: @escaping (NSPoint) -> Void) {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { _ in
            onClick(NSEvent.mouseLocation)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { event in
            onClick(NSEvent.mouseLocation)
            return event
        }
    }

    func invalidate() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
