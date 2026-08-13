import AppKit
import CoreGraphics

/// CGEvent tap for the hardware media keys (NSSystemDefined subtype 8).
/// Requires Accessibility trust; created on the main run loop so the callback
/// runs on the main thread. Consumed keys never reach the system HUD.
final class MediaKeyTap {
    enum Key {
        case volumeUp, volumeDown, mute, brightnessUp, brightnessDown
    }

    /// Fired on key-down (including repeats).
    var onKey: ((Key) -> Void)?
    /// Live consume gates, evaluated per keypress (the default output device
    /// and display set change at runtime). A key we cannot act on must pass
    /// through so macOS handles it — never consume and do nothing.
    var consumesVolume: () -> Bool = { true }
    var consumesMute: () -> Bool = { true }
    var consumesBrightness: () -> Bool = { false }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retainedSelf: UnsafeMutableRawPointer?

    private static let nxSoundUp = 0, nxSoundDown = 1
    private static let nxBrightnessUp = 2, nxBrightnessDown = 3
    private static let nxMute = 7

    static func checkAccessibility(prompt: Bool) -> Bool {
        // kAXTrustedCheckOptionPrompt is a non-Sendable global; the literal
        // key is documented and stable.
        let options = ["AXTrustedCheckOptionPrompt": prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Returns false when the tap could not be created (no Accessibility).
    func start() -> Bool {
        guard tap == nil else { return true }
        let userInfo = Unmanaged.passRetained(self).toOpaque()
        let mask = CGEventMask(1 << 14)   // NSEvent.EventType.systemDefined
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: egoMediaKeyTapCallback,
            userInfo: userInfo
        ) else {
            Unmanaged<MediaKeyTap>.fromOpaque(userInfo).release()
            return false
        }
        self.tap = tap
        retainedSelf = userInfo
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let retainedSelf {
            Unmanaged<MediaKeyTap>.fromOpaque(retainedSelf).release()
        }
        tap = nil
        source = nil
        retainedSelf = nil
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Returns true to CONSUME the event. data1 is the NSSystemDefined
    /// payload, already extracted on the callback side.
    fileprivate func handle(data1: Int) -> Bool {
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0xFFFF
        let isDown = ((keyFlags & 0xFF00) >> 8) == 0x0A

        let key: Key
        switch keyCode {
        case Self.nxSoundUp:
            guard consumesVolume() else { return false }
            key = .volumeUp
        case Self.nxSoundDown:
            guard consumesVolume() else { return false }
            key = .volumeDown
        case Self.nxMute:
            guard consumesMute() else { return false }
            key = .mute
        case Self.nxBrightnessUp:
            guard consumesBrightness() else { return false }
            key = .brightnessUp
        case Self.nxBrightnessDown:
            guard consumesBrightness() else { return false }
            key = .brightnessDown
        default:
            return false
        }

        if isDown { onKey?(key) }
        return true   // consume both down and up so the system HUD never shows
    }
}

/// C callback — the tap lives on the main run loop, so this runs on main.
/// CGEvent is non-Sendable, so the payload is extracted HERE and only plain
/// values cross into the MainActor region.
private nonisolated func egoMediaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 else {
        return Unmanaged.passUnretained(event)
    }
    let data1 = ns.data1
    let consume = MainActor.assumeIsolated { tap.handle(data1: data1) }
    return consume ? nil : Unmanaged.passUnretained(event)
}
