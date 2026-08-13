import AppKit

/// Watches screen configuration changes (lid close/open, external displays,
/// resolution, menu-bar height) and calls back once per debounced burst —
/// the notification arrives 2–5 times during one reconfiguration, with
/// transitional frames mid-burst.
final class DisplayObserver: NSObject {
    private let onChange: () -> Void
    private var debounceTask: Task<Void, Never>?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screensChanged() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
