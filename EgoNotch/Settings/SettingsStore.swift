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
    /// Posted whenever a setting that affects panel geometry changes.
    static let geometryDidChange = Notification.Name("EgoNotch.geometryDidChange")
    /// Posted when a rule about *when the notch is shown* changes.
    static let visibilityRulesDidChange = Notification.Name("EgoNotch.visibilityRulesDidChange")
    /// Posted when a global shortcut is enabled, disabled or re-recorded.
    static let hotKeysDidChange = Notification.Name("EgoNotch.hotKeysDidChange")

    @ObservationIgnored private let defaults = UserDefaults.standard

    enum Key {
        static let expandOnHover  = "expandOnHover"        // Bool, default true
        static let hoverDwell     = "hoverDwell"           // seconds, default 0.25
        static let animationSpeed = "animationSpeed"       // 0.5…2.0, default 1.0 (higher = faster)
        static let virtualNotchW  = "virtualNotch.width"
        static let virtualNotchH  = "virtualNotch.height"
        static let panelWidth     = "panel.width"          // pt, default 1180
        static let panelHeight    = "panel.height"         // pt, default 235
        static let focusMinutes   = "focus.minutes"        // default 25
        static let breakMinutes   = "focus.breakMinutes"   // default 5
        static let deepMinutes    = "focus.deepMinutes"    // default 50
        static let terminalFont   = "terminal.fontSize"    // pt, default 12
        static let hideFullScreen = "hideInFullScreen"     // Bool, default true
        static let hideMeetings   = "hideInMeetings"       // Bool, default false
        static let termHotKeyOn   = "hotkey.terminal.enabled"  // Bool, default true
        static let termHotKeyCode = "hotkey.terminal.keyCode"
        static let termHotKeyMods = "hotkey.terminal.modifiers"
        static let homeHotKeyOn   = "hotkey.home.enabled"      // Bool, default true
        static let homeHotKeyCode = "hotkey.home.keyCode"
        static let homeHotKeyMods = "hotkey.home.modifiers"
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
            NotificationCenter.default.post(name: Self.geometryDidChange, object: nil)
        }
    }
    var panelWidth: Double {
        didSet {
            defaults.set(panelWidth, forKey: Key.panelWidth)
            NotificationCenter.default.post(name: Self.geometryDidChange, object: nil)
        }
    }
    var panelHeight: Double {
        didSet {
            defaults.set(panelHeight, forKey: Key.panelHeight)
            NotificationCenter.default.post(name: Self.geometryDidChange, object: nil)
        }
    }
    var focusMinutes: Int {
        didSet { defaults.set(focusMinutes, forKey: Key.focusMinutes) }
    }
    var breakMinutes: Int {
        didSet { defaults.set(breakMinutes, forKey: Key.breakMinutes) }
    }
    var deepMinutes: Int {
        didSet { defaults.set(deepMinutes, forKey: Key.deepMinutes) }
    }
    /// Ghostty's own size is tuned for a full window; the notch needs smaller.
    var terminalFontSize: Double {
        didSet { defaults.set(terminalFontSize, forKey: Key.terminalFont) }
    }
    /// Get out of the way of fullscreen video / presentations.
    var hideInFullScreen: Bool {
        didSet {
            defaults.set(hideInFullScreen, forKey: Key.hideFullScreen)
            NotificationCenter.default.post(name: Self.visibilityRulesDidChange, object: nil)
        }
    }
    /// System-wide shortcut that opens the notch straight on the Terminal tab.
    var terminalHotKeyEnabled: Bool {
        didSet {
            defaults.set(terminalHotKeyEnabled, forKey: Key.termHotKeyOn)
            NotificationCenter.default.post(name: Self.hotKeysDidChange, object: nil)
        }
    }
    var terminalHotKey: GlobalHotKey.Combination {
        didSet {
            defaults.set(Int(terminalHotKey.keyCode), forKey: Key.termHotKeyCode)
            defaults.set(Int(terminalHotKey.modifiers), forKey: Key.termHotKeyMods)
            NotificationCenter.default.post(name: Self.hotKeysDidChange, object: nil)
        }
    }

    var homeHotKeyEnabled: Bool {
        didSet {
            defaults.set(homeHotKeyEnabled, forKey: Key.homeHotKeyOn)
            NotificationCenter.default.post(name: Self.hotKeysDidChange, object: nil)
        }
    }
    var homeHotKey: GlobalHotKey.Combination {
        didSet {
            defaults.set(Int(homeHotKey.keyCode), forKey: Key.homeHotKeyCode)
            defaults.set(Int(homeHotKey.modifiers), forKey: Key.homeHotKeyMods)
            NotificationCenter.default.post(name: Self.hotKeysDidChange, object: nil)
        }
    }

    /// Disappear while you're on a call or sharing your screen.
    var hideInMeetings: Bool {
        didSet {
            defaults.set(hideInMeetings, forKey: Key.hideMeetings)
            NotificationCenter.default.post(name: Self.visibilityRulesDidChange, object: nil)
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

    /// Wipe every stored preference — including per-widget toggles — and fall
    /// back to the registered defaults. Deleting the keys (rather than
    /// assigning literals) means the defaults live in exactly one place.
    func resetAll() {
        let keys = [Key.expandOnHover, Key.hoverDwell, Key.animationSpeed,
                    Key.virtualNotchW, Key.virtualNotchH, Key.panelWidth,
                    Key.panelHeight, Key.focusMinutes, Key.breakMinutes,
                    Key.deepMinutes, Key.terminalFont, Key.hideFullScreen, Key.hideMeetings,
                    Key.termHotKeyOn, Key.termHotKeyCode, Key.termHotKeyMods,
                    Key.homeHotKeyOn, Key.homeHotKeyCode, Key.homeHotKeyMods]
            + WidgetRegistry.all.map { Key.widgetEnabled($0.id) }
        for key in keys { defaults.removeObject(forKey: key) }

        widgetEnabledMirror.removeAll()
        expandOnHover = defaults.bool(forKey: Key.expandOnHover)
        hoverDwell = defaults.double(forKey: Key.hoverDwell)
        animationSpeed = defaults.double(forKey: Key.animationSpeed)
        virtualNotchSize = CGSize(width: defaults.double(forKey: Key.virtualNotchW),
                                  height: defaults.double(forKey: Key.virtualNotchH))
        panelWidth = defaults.double(forKey: Key.panelWidth)
        panelHeight = defaults.double(forKey: Key.panelHeight)
        focusMinutes = defaults.integer(forKey: Key.focusMinutes)
        breakMinutes = defaults.integer(forKey: Key.breakMinutes)
        deepMinutes = defaults.integer(forKey: Key.deepMinutes)
        terminalFontSize = defaults.double(forKey: Key.terminalFont)
        hideInFullScreen = defaults.bool(forKey: Key.hideFullScreen)
        hideInMeetings = defaults.bool(forKey: Key.hideMeetings)
        terminalHotKeyEnabled = defaults.bool(forKey: Key.termHotKeyOn)
        terminalHotKey = GlobalHotKey.Combination(
            keyCode: UInt32(defaults.integer(forKey: Key.termHotKeyCode)),
            modifiers: UInt(defaults.integer(forKey: Key.termHotKeyMods)))
        homeHotKeyEnabled = defaults.bool(forKey: Key.homeHotKeyOn)
        homeHotKey = GlobalHotKey.Combination(
            keyCode: UInt32(defaults.integer(forKey: Key.homeHotKeyCode)),
            modifiers: UInt(defaults.integer(forKey: Key.homeHotKeyMods)))

        WidgetRegistry.syncActivation()
        NotificationCenter.default.post(name: Self.geometryDidChange, object: nil)
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
            Key.panelWidth: 960.0,
            Key.panelHeight: 205.0,
            Key.focusMinutes: 25,
            Key.breakMinutes: 5,
            Key.deepMinutes: 50,
            Key.terminalFont: 12.0,
            Key.hideFullScreen: true,
            Key.hideMeetings: false,  // visible by default; opt in per call
            Key.termHotKeyOn: true,
            Key.termHotKeyCode: Int(GlobalHotKey.Combination.terminalDefault.keyCode),
            Key.termHotKeyMods: Int(GlobalHotKey.Combination.terminalDefault.modifiers),
            Key.homeHotKeyOn: true,
            Key.homeHotKeyCode: Int(GlobalHotKey.Combination.homeDefault.keyCode),
            Key.homeHotKeyMods: Int(GlobalHotKey.Combination.homeDefault.modifiers),
        ])
        expandOnHover = defaults.bool(forKey: Key.expandOnHover)
        hoverDwell = defaults.double(forKey: Key.hoverDwell)
        animationSpeed = defaults.double(forKey: Key.animationSpeed)
        virtualNotchSize = CGSize(width: defaults.double(forKey: Key.virtualNotchW),
                                  height: defaults.double(forKey: Key.virtualNotchH))
        panelWidth = defaults.double(forKey: Key.panelWidth)
        panelHeight = defaults.double(forKey: Key.panelHeight)
        focusMinutes = defaults.integer(forKey: Key.focusMinutes)
        breakMinutes = defaults.integer(forKey: Key.breakMinutes)
        deepMinutes = defaults.integer(forKey: Key.deepMinutes)
        terminalFontSize = defaults.double(forKey: Key.terminalFont)
        hideInFullScreen = defaults.bool(forKey: Key.hideFullScreen)
        hideInMeetings = defaults.bool(forKey: Key.hideMeetings)
        terminalHotKeyEnabled = defaults.bool(forKey: Key.termHotKeyOn)
        terminalHotKey = GlobalHotKey.Combination(
            keyCode: UInt32(defaults.integer(forKey: Key.termHotKeyCode)),
            modifiers: UInt(defaults.integer(forKey: Key.termHotKeyMods)))
        homeHotKeyEnabled = defaults.bool(forKey: Key.homeHotKeyOn)
        homeHotKey = GlobalHotKey.Combination(
            keyCode: UInt32(defaults.integer(forKey: Key.homeHotKeyCode)),
            modifiers: UInt(defaults.integer(forKey: Key.homeHotKeyMods)))
    }
}
