import CoreAudio
import Foundation

/// Default-output volume/mute via CoreAudio.
enum SystemVolume {
    /// 'vmvc' — virtual main volume (the constant lives in a deprecated
    /// AudioToolbox header, so we use the four-char code directly).
    private static let virtualMainVolume = AudioObjectPropertySelector(0x766D_7663)

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: virtualMainVolume,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    static var isControllable: Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = volumeAddress
        return AudioObjectHasProperty(device, &address)
    }

    static var hasMuteControl: Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = muteAddress
        return AudioObjectHasProperty(device, &address)
    }

    static func volume() -> Float? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = volumeAddress
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return nil }
        return value
    }

    static func setVolume(_ value: Float) {
        guard let device = defaultOutputDevice() else { return }
        var address = volumeAddress
        var clamped = max(0, min(1, value))
        AudioObjectSetPropertyData(device, &address, 0, nil,
                                   UInt32(MemoryLayout<Float32>.size), &clamped)
    }

    static func isMuted() -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = muteAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return false }
        return value == 1
    }

    static func setMuted(_ muted: Bool) {
        guard let device = defaultOutputDevice() else { return }
        var address = muteAddress
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &address, 0, nil,
                                   UInt32(MemoryLayout<UInt32>.size), &value)
    }
}
