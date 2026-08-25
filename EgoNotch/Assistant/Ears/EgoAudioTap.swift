import AVFoundation
import CoreAudio
import Accelerate
import Speech

/// The microphone, as a stream of buffers the transcriber can eat.
///
/// `nonisolated` + `@unchecked Sendable` + a lock is load-bearing, exactly as
/// in `EgoNotch/Widgets/Recorder/CameraFrames.swift`: an `AVAudioNodeTapBlock`
/// runs on a real-time audio thread, and this module defaults to MainActor
/// isolation — an implicitly-isolated tap traps the process on the first
/// buffer. Nothing here touches the main actor. The UI *polls* `level()`.
nonisolated final class EgoAudioTap: NSObject, @unchecked Sendable {
    private let lock = NSLock()
    private var muted = true
    private var meter: Double = 0
    private var generation: UInt64 = 0
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    private let engine = AVAudioEngine()
    private var running = false

    /// The last few seconds of audio, kept so the wake phrase can be
    /// fingerprinted *after* the recogniser has identified it. The transcript
    /// always arrives behind the sound, so without this there is nothing left
    /// to measure by the time we know it was the wake word.
    private var ring: [Float] = []
    private var ringWrite = 0
    private var ringFilled = 0
    private var ringRate: Double = 0

    /// Everything heard since enrolment began. Separate from the ring, which
    /// only ever holds the last few seconds.
    private var capture: [Float]?

    /// Yields `AnalyzerInput` rather than raw buffers: `AVAudioPCMBuffer` is
    /// not `Sendable`, so a stream of them cannot cross into the transcriber's
    /// actor. The stream keeps only the newest few — the audio thread must
    /// never block.
    func start(targetFormat: AVAudioFormat) throws -> AsyncStream<AnalyzerInput> {
        stop()

        preferBuiltInMicrophone()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "EgoAudioTap", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No input device."])
        }

        lock.lock()
        self.targetFormat = targetFormat
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        generation &+= 1
        // Four seconds is comfortably more than a wake phrase, and costs a
        // quarter of a megabyte.
        ringRate = targetFormat.sampleRate
        ring = [Float](repeating: 0, count: Int(targetFormat.sampleRate * 4))
        ringWrite = 0
        ringFilled = 0
        lock.unlock()

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .bufferingNewest(24))
        lock.lock()
        self.continuation = continuation
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.receive(buffer)
        }

        engine.prepare()
        try engine.start()
        running = true
        return stream
    }

    /// The input device that was selected before Ego moved it aside.
    private var borrowedInput: AudioDeviceID?

    /// Listen through the Mac's own microphone rather than a Bluetooth one.
    ///
    /// A Bluetooth headset has two modes: A2DP — stereo, full bandwidth, what
    /// you want for listening — and HFP, mono at 16 kHz, which it switches to
    /// the moment anything opens its microphone. Ego holds the microphone open
    /// all day for the wake word, so simply *being* connected dropped the
    /// user's earbuds to call quality: Ego's voice, their music, everything.
    ///
    /// Nothing system-wide is changed. This sets the device on our own input
    /// unit only, so the headset stays on A2DP and Ego listens through the
    /// built-in microphone a few inches further away — a trade worth making,
    /// since the wake word was tuned on that microphone anyway.
    private func preferBuiltInMicrophone() {
        guard let current = Self.defaultInputDevice(),
              Self.isBluetooth(current),
              let builtIn = Self.builtInInputDevice() else { return }

        var device = builtIn
        if let unit = engine.inputNode.audioUnit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &device,
                                 UInt32(MemoryLayout<AudioDeviceID>.size))
        }

        // Not enough on its own. macOS keeps the headset in HFP for as long as
        // it is the *selected* system input, whether or not anything is
        // recording — measured: 1 channel at 16 kHz while selected, 2 channels
        // at 44.1 kHz the moment it isn't. So the selection is borrowed for as
        // long as Ego listens, and handed straight back in `stop()`.
        borrowedInput = current
        Self.setDefaultInput(builtIn)
        EgoLog.trace("bluetooth headset kept in high quality — input moved to the built-in mic")
    }

    /// Gives the microphone selection back exactly as it was found.
    func returnBorrowedInput() {
        guard let borrowed = borrowedInput else { return }
        borrowedInput = nil
        // Only if nothing else has changed it since — the user may have picked
        // a different microphone while Ego was running, and that choice wins.
        guard let now = Self.defaultInputDevice(), Self.isBuiltIn(now) else {
            EgoLog.trace("input was changed elsewhere — leaving it alone")
            return
        }
        Self.setDefaultInput(borrowed)
        EgoLog.trace("microphone selection handed back")
    }

    private static func setDefaultInput(_ device: AudioDeviceID) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value = device
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                   UInt32(MemoryLayout<AudioDeviceID>.size), &value)
    }

    private static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &device) == noErr
        else { return nil }
        return device
    }

    private static func isBluetooth(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr
        else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth
    }

    private static func builtInInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return nil }
        var devices = [AudioDeviceID](repeating: 0,
                                      count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &devices) == noErr else { return nil }

        return devices.first { device in
            guard isBuiltIn(device) else { return false }
            var streams = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain)
            var streamSize = UInt32(0)
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { return false }
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(streamSize), alignment: 8)
            defer { buffer.deallocate() }
            guard AudioObjectGetPropertyData(device, &streams, 0, nil, &streamSize, buffer) == noErr
            else { return false }
            let list = UnsafeMutableAudioBufferListPointer(
                buffer.assumingMemoryBound(to: AudioBufferList.self))
            return list.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
        }
    }

    private static func isBuiltIn(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr
        else { return false }
        return transport == kAudioDeviceTransportTypeBuiltIn
    }

    func stop() {
        guard running else { return }
        running = false
        returnBorrowedInput()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        continuation?.finish()
        continuation = nil
        converter = nil
        meter = 0
        lock.unlock()
    }

    var isRunning: Bool { running }

    // MARK: - Muting
    //
    // Ego must never transcribe its own voice. Muting HERE — upstream of the
    // analyser — is airtight: no buffer is produced at all while it speaks.

    /// Returns the generation the caller should now accept results from, so
    /// audio already inside the analyser's pipeline can be discarded.
    @discardableResult
    func setMuted(_ muted: Bool) -> UInt64 {
        lock.lock()
        self.muted = muted
        if !muted { generation &+= 1 }
        let current = generation
        if muted { meter = 0 }
        lock.unlock()
        return current
    }

    var currentGeneration: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return generation
    }

    /// 0…1, polled by the HUD at ~20 Hz rather than pushed 100×/second.
    func level() -> Double {
        lock.lock(); defer { lock.unlock() }
        return meter
    }

    // MARK: - The audio thread

    private func receive(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let isMuted = muted
        let converter = converter
        let target = targetFormat
        lock.unlock()
        guard !isMuted, let converter, let target else { return }

        let loudness = Self.rms(of: buffer)

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, converted.frameLength > 0 else { return }

        lock.lock()
        meter = loudness
        let sink = continuation
        let mono = Self.samples(from: converted)
        appendToRing(mono)
        if capture != nil { capture?.append(contentsOf: mono) }
        lock.unlock()
        sink?.yield(AnalyzerInput(buffer: converted))
    }

    /// Called with the lock held, from the audio thread.
    private func appendToRing(_ samples: [Float]) {
        guard !ring.isEmpty else { return }
        for sample in samples {
            ring[ringWrite] = sample
            ringWrite = (ringWrite + 1) % ring.count
        }
        ringFilled = min(ringFilled + samples.count, ring.count)
    }

    /// The analyser asks for **Int16**, not Float32 — so `floatChannelData` on
    /// a converted buffer is nil, and reading it silently produced nothing at
    /// all. Everything downstream (the ring, enrolment, voice matching) was
    /// quietly being fed zero samples.
    private static func samples(from buffer: AVAudioPCMBuffer) -> [Float] {
        let count = Int(buffer.frameLength)
        guard count > 0 else { return [] }
        if let channel = buffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: channel, count: count))
        }
        guard let channel = buffer.int16ChannelData?[0] else { return [] }
        var out = [Float](repeating: 0, count: count)
        vDSP_vflt16(channel, 1, &out, 1, vDSP_Length(count))
        var scale = Float(1.0 / 32768.0)
        vDSP_vsmul(out, 1, &scale, &out, 1, vDSP_Length(count))
        return out
    }

    // MARK: - Enrolment capture

    func beginCapture() {
        lock.lock(); capture = []; lock.unlock()
    }

    /// How much speech-or-silence has been gathered so far.
    var capturedSeconds: Double {
        lock.lock(); defer { lock.unlock() }
        guard ringRate > 0, let capture else { return 0 }
        return Double(capture.count) / ringRate
    }

    func endCapture() -> (samples: [Float], sampleRate: Double)? {
        lock.lock(); defer { lock.unlock() }
        defer { capture = nil }
        guard let capture, ringRate > 0, !capture.isEmpty else { return nil }
        return (capture, ringRate)
    }

    /// The most recent `seconds` of audio, oldest first.
    func recentAudio(seconds: Double) -> (samples: [Float], sampleRate: Double)? {
        lock.lock(); defer { lock.unlock() }
        guard !ring.isEmpty, ringRate > 0 else { return nil }
        let wanted = min(Int(ringRate * seconds), ringFilled)
        guard wanted > Int(ringRate * 0.2) else { return nil }

        var out = [Float](repeating: 0, count: wanted)
        var read = (ringWrite - wanted + ring.count) % ring.count
        for index in 0..<wanted {
            out[index] = ring[read]
            read = (read + 1) % ring.count
        }
        return (out, ringRate)
    }

    /// Root-mean-square, mapped onto a rough 0…1 loudness for the HUD.
    private static func rms(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        var value: Float = 0
        vDSP_measqv(channel, 1, &value, vDSP_Length(buffer.frameLength))
        let db = 10 * log10(max(value, .leastNonzeroMagnitude))
        return min(max((Double(db) + 50) / 50, 0), 1)   // −50 dB → 0, 0 dB → 1
    }
}
