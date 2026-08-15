import AVFoundation
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

    /// Yields `AnalyzerInput` rather than raw buffers: `AVAudioPCMBuffer` is
    /// not `Sendable`, so a stream of them cannot cross into the transcriber's
    /// actor. The stream keeps only the newest few — the audio thread must
    /// never block.
    func start(targetFormat: AVAudioFormat) throws -> AsyncStream<AnalyzerInput> {
        stop()

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

    func stop() {
        guard running else { return }
        running = false
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
        lock.unlock()
        sink?.yield(AnalyzerInput(buffer: converted))
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
