import AppKit
import AVFoundation
import CoreAudio
import CoreMedia

/// Notices when you're in a call or sharing your screen, so the notch can get
/// out of the picture — literally: on a shared screen it sits right where the
/// other participants are looking.
///
/// macOS publishes no "screen is being shared" flag, so this reads the two
/// signals it does publish, both event-driven:
///   • the microphone is live (`kAudioDevicePropertyDeviceIsRunningSomewhere`)
///   • the camera is live (`AVCaptureDevice.isInUseByAnotherApplication`)
///
/// Every meeting and screen-share flow turns at least one of them on — you
/// can't present in Meet, Zoom or Teams without joining the call first — while
/// ordinary app use turns on neither.
final class MeetingObserver {
    /// True while a call / capture appears to be in progress.
    var onChange: ((Bool) -> Void)?

    private var isActive = false
    private var micListener: AudioObjectPropertyListenerBlock?
    private var micDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var cameraObservations: [NSKeyValueObservation] = []
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?

    private var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private var runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    // MARK: - Lifecycle

    func start() {
        observeDefaultInputChanges()
        attachMicListener()
        attachCameraObservers()
        evaluate()
    }

    func stop() {
        detachMicListener()
        cameraObservations.forEach { $0.invalidate() }
        cameraObservations = []
        if let block = defaultDeviceListener {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, .main, block)
            defaultDeviceListener = nil
        }
    }

    // MARK: - Microphone

    /// Switching headsets mid-call swaps the default input device, so the
    /// "is it running" listener has to follow it.
    private func observeDefaultInputChanges() {
        guard defaultDeviceListener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.detachMicListener()
            self.attachMicListener()
            self.evaluate()
        }
        defaultDeviceListener = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, .main, block)
    }

    private func attachMicListener() {
        micDeviceID = Self.defaultInputDevice()
        guard micDeviceID != kAudioObjectUnknown else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.evaluate()
        }
        micListener = block
        AudioObjectAddPropertyListenerBlock(micDeviceID, &runningAddress, .main, block)
    }

    private func detachMicListener() {
        guard let block = micListener, micDeviceID != kAudioObjectUnknown else { return }
        AudioObjectRemovePropertyListenerBlock(micDeviceID, &runningAddress, .main, block)
        micListener = nil
    }

    private static func defaultInputDevice() -> AudioObjectID {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : kAudioObjectUnknown
    }

    private var microphoneIsLive: Bool {
        guard micDeviceID != kAudioObjectUnknown else { return false }
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = runningAddress
        let status = AudioObjectGetPropertyData(micDeviceID, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
    }

    // MARK: - Camera

    /// KVO on every video device — `isInUseByAnotherApplication` flips as soon
    /// as a meeting app opens the camera, and needs no camera permission of
    /// our own.
    private func attachCameraObservers() {
        guard cameraObservations.isEmpty else { return }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified)
        cameraObservations = discovery.devices.map { device in
            device.observe(\.isInUseByAnotherApplication, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.evaluate() }
            }
        }
    }

    private var cameraIsLive: Bool {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified)
        return discovery.devices.contains { $0.isInUseByAnotherApplication }
    }

    // MARK: - Decision

    private func evaluate() {
        // Our own Recorder tab holds the camera — that must not hide the
        // notch the recorder lives in.
        let ours = (WidgetRegistry.widget(id: "recorder") as? RecorderWidget)?
            .camera.session?.isRunning ?? false

        // `kAudioDevicePropertyDeviceIsRunningSomewhere` is DEVICE-global, so
        // once Ego opens the microphone it reads true forever — simply
        // excluding ourselves the way the recorder does would make the app
        // permanently blind to real calls. Ask per process instead, and keep
        // the device flag only as the cheap trigger that something changed.
        let micBusy = Self.otherProcessUsingInput() ?? (!egoIsListening && microphoneIsLive)

        let active = !ours && (micBusy || cameraIsLive)
        guard active != isActive else { return }
        isActive = active
        onChange?(active)
    }

    private var egoIsListening: Bool {
        (WidgetRegistry.widget(id: "ego") as? EgoWidget)?.assistant.ears.isMicLive ?? false
    }

    /// True when some process OTHER than us is running audio input; nil when
    /// the process list can't be read, so the caller can fall back.
    private static func otherProcessUsingInput() -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)

        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
            size > 0 else { return nil }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var processes = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &processes) == noErr
        else { return nil }

        let ourPID = ProcessInfo.processInfo.processIdentifier
        for process in processes {
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyIsRunningInput,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(process, &runningAddress, 0, nil,
                                             &runningSize, &running) == noErr,
                  running != 0 else { continue }

            var pidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioProcessPropertyPID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var pid: pid_t = -1
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(process, &pidAddress, 0, nil,
                                             &pidSize, &pid) == noErr, pid != ourPID
            else { continue }

            // Only *launched apps* count. macOS keeps daemons like
            // `historicalaudiod` on the input device permanently, and counting
            // those would mean "you are always in a meeting" — which is
            // exactly the false positive this whole check exists to avoid.
            guard NSRunningApplication(processIdentifier: pid) != nil else { continue }
            return true
        }
        return false
    }
}
