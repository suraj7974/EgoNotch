import CoreAudio
import Observation

/// Tracks the name of the current default audio output device via a CoreAudio
/// property listener — purely event-driven.
@Observable
final class AudioOutputMonitor {
    private(set) var deviceName = ""

    @ObservationIgnored private var listenerBlock: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard listenerBlock == nil else { return }
        refresh()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // Registered on the main queue, so we're already on MainActor.
            self?.refresh()
        }
        listenerBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
    }

    func stop() {
        if let block = listenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
            listenerBlock = nil
        }
        deviceName = ""
    }

    private func refresh() {
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = address
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            deviceName = ""
            return
        }

        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfName: CFString?
        var nameSize = UInt32(MemoryLayout<CFString?>.size)
        let nameStatus = withUnsafeMutablePointer(to: &cfName) { ptr in
            AudioObjectGetPropertyData(deviceID, &nameAddr, 0, nil, &nameSize, ptr)
        }
        deviceName = nameStatus == noErr ? (cfName as String? ?? "") : ""
    }
}
