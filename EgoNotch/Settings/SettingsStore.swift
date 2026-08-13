import SwiftUI
import Observation

/// UserDefaults-backed app settings. @Observable (not @AppStorage — that only
/// works inside views and can't do dynamic per-widget keys); every stored
/// property persists in didSet. Widget toggles live in an observable mirror
/// dictionary keyed by widget id, so settings survive for widgets that don't
/// exist yet and SwiftUI invalidates on toggle.
@Observable
final class SettingsStore {
    static let shared = SettingsStore()
    static let virtualNotchDidChange = Notification.Name("EgoNotch.virtualNotchDidChange")

    @ObservationIgnored private let defaults = UserDefaults.standard

    enum Key {
        static let expandOnHover  = "expandOnHover"        // Bool, default true
        static let hoverDwell     = "hoverDwell"           // seconds, default 0.25
        static let animationSpeed = "animationSpeed"       // 0.5…2.0, default 1.0 (higher = faster)
        static let virtualNotchW  = "virtualNotch.width"
        static let virtualNotchH  = "virtualNotch.height"
        static func widgetEnabled(_ id: String) -> String { "widget.enabled.\(id)" }
    }

    var expandOnHover: Bool {
        didSet { defaults.set(expandOnHover, forKey: Key.expandOnHover) }
    }
    var hoverDwell: Double {
        didSet { defaults.set(hoverDwell, forKey: Key.hoverDwell) }
    }
    var animationSpeed: Double {
        didSet { defaults.set(animationSpeed, forKey: Key.animationSpeed) }
    }
    var virtualNotchSize: CGSize {
        didSet {
            defaults.set(virtualNotchSize.width, forKey: Key.virtualNotchW)
            defaults.set(virtualNotchSize.height, forKey: Key.virtualNotchH)
            NotificationCenter.default.post(name: Self.virtualNotchDidChange, object: nil)
        }
    }

    // MARK: - Per-widget enabled (dynamic keys)

    private var widgetEnabledMirror: [String: Bool] = [:]

    func isEnabled(_ id: String, defaultValue: Bool = true) -> Bool {
        if let cached = widgetEnabledMirror[id] { return cached }
        let stored = defaults.object(forKey: Key.widgetEnabled(id)) as? Bool ?? defaultValue
        widgetEnabledMirror[id] = stored
        return stored
    }

    func setEnabled(_ enabled: Bool, id: String) {
        widgetEnabledMirror[id] = enabled
        defaults.set(enabled, forKey: Key.widgetEnabled(id))
        WidgetRegistry.syncActivation()
    }

    func enabledBinding(for widget: any NotchWidget) -> Binding<Bool> {
        Binding(
            get: { self.isEnabled(widget.id, defaultValue: widget.defaultEnabled) },
            set: { self.setEnabled($0, id: widget.id) }
        )
    }

    private init() {
        defaults.register(defaults: [
            Key.expandOnHover: true,
            Key.hoverDwell: 0.25,
            Key.animationSpeed: 1.0,
            Key.virtualNotchW: 190.0,
            Key.virtualNotchH: 32.0,
        ])
        expandOnHover = defaults.bool(forKey: Key.expandOnHover)
        hoverDwell = defaults.double(forKey: Key.hoverDwell)
        animationSpeed = defaults.double(forKey: Key.animationSpeed)
        virtualNotchSize = CGSize(width: defaults.double(forKey: Key.virtualNotchW),
                                  height: defaults.double(forKey: Key.virtualNotchH))
    }
}
