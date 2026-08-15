import AppKit
import Carbon.HIToolbox
import Observation

/// Whether the registration actually took. Another app can already own a
/// combination, and a shortcut that quietly does nothing is worse than none.
@Observable
final class HotKeyStatus {
    static let shared = HotKeyStatus()
    var terminalTaken = false
    var homeTaken = false
}

/// A system-wide keyboard shortcut, via Carbon's `RegisterEventHotKey`.
///
/// Deliberately not an `NSEvent` global monitor: those need Accessibility
/// permission and see every keystroke you type all day. This registers one
/// combination with the window server and is told only when that fires.
final class GlobalHotKey {
    struct Combination: Equatable {
        var keyCode: UInt32
        /// NSEvent modifier flags (device-independent).
        var modifiers: UInt

        /// ⌘⌥T. Free system-wide; note it shadows AppKit's "Hide Toolbar"
        /// in apps that have one, since a registered hot key wins over an
        /// app's own menu shortcut.
        static let terminalDefault = Combination(
            keyCode: UInt32(kVK_ANSI_T),
            modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue)

        /// ⌘⌥H — the Home tab.
        static let homeDefault = Combination(
            keyCode: UInt32(kVK_ANSI_H),
            modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue)

        /// A shortcut without modifiers would swallow that key system-wide.
        var isValid: Bool { carbonModifiers != 0 }

        /// Carbon wants its own modifier bits.
        var carbonModifiers: UInt32 {
            let flags = NSEvent.ModifierFlags(rawValue: modifiers)
            var carbon: UInt32 = 0
            if flags.contains(.command) { carbon |= UInt32(cmdKey) }
            if flags.contains(.option)  { carbon |= UInt32(optionKey) }
            if flags.contains(.control) { carbon |= UInt32(controlKey) }
            if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
            return carbon
        }

        /// "⌃⌥T" for display.
        var displayName: String {
            let flags = NSEvent.ModifierFlags(rawValue: modifiers)
            var text = ""
            if flags.contains(.control) { text += "⌃" }
            if flags.contains(.option)  { text += "⌥" }
            if flags.contains(.shift)   { text += "⇧" }
            if flags.contains(.command) { text += "⌘" }
            return text + Self.keyName(keyCode)
        }

        static func keyName(_ keyCode: UInt32) -> String {
            if let special = specialKeys[Int(keyCode)] { return special }
            guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
                  let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            else { return "?" }
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = data.withUnsafeBytes { raw -> OSStatus in
                guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
                else { return -1 }
                return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                      UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                      &deadKeys, characters.count, &length, &characters)
            }
            guard status == noErr, length > 0 else { return "?" }
            return String(utf16CodeUnits: characters, count: length).uppercased()
        }

        private static let specialKeys: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
            kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
            kVK_F11: "F11", kVK_F12: "F12",
        ]
    }

    var action: (() -> Void)?

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let identifier: UInt32

    init(identifier: UInt32 = 1) {
        self.identifier = identifier
    }

    /// Replaces any previous registration. Returns false when the combination
    /// is already taken by another app — the caller can say so.
    @discardableResult
    func register(_ combination: Combination) -> Bool {
        unregister()
        guard combination.isValid else { return false }   // bare keys are not ours to take

        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x45474F4E), id: identifier)  // 'EGON'
        let status = RegisterEventHotKey(combination.keyCode,
                                         combination.carbonModifiers,
                                         hotKeyID,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &reference)
        return status == noErr
    }

    func unregister() {
        if let reference {
            UnregisterEventHotKey(reference)
            self.reference = nil
        }
    }

    /// ONE handler for the whole app, dispatching by hot key id.
    ///
    /// Per-instance handlers looked fine and broke everything: Carbon calls
    /// them newest-first, and a handler returning `noErr` means "handled", so
    /// the second shortcut registered silently swallowed the first one's key
    /// presses.
    nonisolated(unsafe) private static var actions: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) private static var sharedHandler: EventHandlerRef?

    private func installHandlerIfNeeded() {
        Self.actions[identifier] = { [weak self] in self?.action?() }
        guard Self.sharedHandler == nil else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var firedID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &firedID)
            guard let action = GlobalHotKey.actions[firedID.id] else {
                return OSStatus(eventNotHandledErr)     // let others have it
            }
            DispatchQueue.main.async { action() }
            return noErr
        }, 1, &spec, nil, &Self.sharedHandler)
    }
}
