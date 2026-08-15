import Accelerate
import Foundation

/// One recording of the wake phrase, as a fingerprint.
///
/// Text-*dependent*: it only ever compares the same words against each other,
/// which is a far easier problem than "whose voice is this" in general — and
/// it is the approach behind "Hey Siri" personalisation. Describing the voice
/// independently of the words was tried first; on a one-second phrase the
/// speaker's own readings varied as much as a stranger's did, and the gate
/// could not separate them.
nonisolated struct WakeTemplate: Codable, Sendable {
    /// Frames × coefficients, silence trimmed and channel effects removed.
    let frames: [[Float]]

    var isUsable: Bool { frames.count >= 20 }

    static func make(samples: [Float], sampleRate: Double) -> WakeTemplate? {
        guard let raw = MFCC.frames(samples: samples, sampleRate: sampleRate, keepSilence: true),
              raw.count >= 20 else { return nil }
        let speech = trimToSpeech(raw)
        guard speech.count >= 20 else { return nil }
        return WakeTemplate(frames: normalise(speech))
    }

    /// The window is a rolling few seconds, so most of it is room tone. Keep
    /// the loud middle — otherwise two fingerprints are largely a comparison
    /// of silence, and everybody's silence matches.
    private static func trimToSpeech(_ frames: [[Float]]) -> [[Float]] {
        let energies = frames.map { frame in frame.reduce(0) { $0 + abs($1) } }
        guard let peak = energies.max(), let floor = energies.min(), peak > floor else { return frames }
        let cutoff = floor + (peak - floor) * 0.35
        guard let first = energies.firstIndex(where: { $0 >= cutoff }),
              let last = energies.lastIndex(where: { $0 >= cutoff }), last > first else { return frames }
        return Array(frames[max(0, first - 3)...min(frames.count - 1, last + 3)])
    }

    /// Subtracts each coefficient's own mean. This is what lets the match
    /// survive a different distance from the microphone, a different room, or
    /// music playing behind you — all of which shift the coefficients bodily
    /// without changing the shape of the phrase.
    private static func normalise(_ frames: [[Float]]) -> [[Float]] {
        guard let width = frames.first?.count, width > 0 else { return frames }
        var means = [Float](repeating: 0, count: width)
        for frame in frames { for index in 0..<width { means[index] += frame[index] } }
        for index in 0..<width { means[index] /= Float(frames.count) }
        return frames.map { frame in (0..<width).map { frame[$0] - means[$0] } }
    }

    /// Dynamic time warping: the same words said faster or slower still line
    /// up, because the path is allowed to stretch. The result is per frame, so
    /// utterances of different lengths stay comparable.
    static func distance(_ lhs: WakeTemplate, _ rhs: WakeTemplate) -> Float {
        let a = lhs.frames, b = rhs.frames
        guard !a.isEmpty, !b.isEmpty else { return .greatestFiniteMagnitude }

        let band = max(15, Int(Double(max(a.count, b.count)) * 0.3))
        var previous = [Float](repeating: .greatestFiniteMagnitude, count: b.count + 1)
        var current = previous
        previous[0] = 0

        for i in 1...a.count {
            current = [Float](repeating: .greatestFiniteMagnitude, count: b.count + 1)
            let from = max(1, i - band), to = min(b.count, i + band)
            guard from <= to else { continue }
            for j in from...to {
                let best = min(previous[j], min(current[j - 1], previous[j - 1]))
                guard best < .greatestFiniteMagnitude else { continue }
                current[j] = frameDistance(a[i - 1], b[j - 1]) + best
            }
            previous = current
        }
        let total = previous[b.count]
        guard total < .greatestFiniteMagnitude else { return .greatestFiniteMagnitude }
        return total / Float(max(a.count, b.count))
    }

    private static func frameDistance(_ a: [Float], _ b: [Float]) -> Float {
        var sum: Float = 0
        for index in 0..<min(a.count, b.count) {
            let delta = a[index] - b[index]
            sum += delta * delta
        }
        return sqrt(sum)
    }
}

/// Mel-frequency cepstral coefficients: a compact description of vocal-tract
/// shape, which is what actually differs between two people speaking.
nonisolated enum MFCC {
    static let coefficients = 12
    private static let melBands = 26
    private static let preEmphasis: Float = 0.97

    /// Every frame that contains speech. Quiet frames are dropped rather than
    /// averaged in — otherwise a profile is mostly a description of the room,
    /// and every room matches every other.
    static func frames(samples: [Float], sampleRate: Double,
                       keepSilence: Bool = false) -> [[Float]]? {
        guard sampleRate > 0, samples.count > Int(sampleRate * 0.2) else { return nil }
        let windowLength = Int(sampleRate * 0.025)
        let hop = Int(sampleRate * 0.010)
        guard windowLength > 32, hop > 0 else { return nil }
        let fftSize = 1 << Int(ceil(log2(Double(windowLength))))

        var emphasised = [Float](repeating: 0, count: samples.count)
        emphasised[0] = samples[0]
        for index in 1..<samples.count {
            emphasised[index] = samples[index] - preEmphasis * samples[index - 1]
        }

        let window = vDSP.window(ofType: Float.self,
                                 usingSequence: .hanningDenormalized,
                                 count: windowLength, isHalfWindow: false)
        let filters = filterbank(fftSize: fftSize, sampleRate: sampleRate)
        guard let fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(fftSize))),
                                 radix: .radix2, ofType: DSPSplitComplex.self) else { return nil }

        var all: [[Float]] = []
        var energies: [Float] = []
        var start = 0
        while start + windowLength <= emphasised.count {
            var frame = Array(emphasised[start..<(start + windowLength)])
            vDSP.multiply(frame, window, result: &frame)
            let power = spectrum(frame, fftSize: fftSize, fft: fft)

            var bands = [Float](repeating: 0, count: melBands)
            for (index, filter) in filters.enumerated() {
                var sum: Float = 0
                vDSP_dotpr(power, 1, filter, 1, &sum, vDSP_Length(power.count))
                bands[index] = log(max(sum, 1e-10))
            }
            all.append(dct(bands))
            energies.append(bands.reduce(0, +) / Float(melBands))
            start += hop
        }
        guard !all.isEmpty, let peak = energies.max(), let floor = energies.min() else { return nil }

        // A template needs its silences kept in place — dropping frames from
        // the middle would break the timing that warping relies on.
        guard !keepSilence else { return all }
        let cutoff = floor + (peak - floor) * 0.28
        let speech = zip(all, energies).filter { $0.1 >= cutoff }.map(\.0)
        return speech.count >= 8 ? speech : all
    }

    private static func spectrum(_ frame: [Float], fftSize: Int,
                                 fft: vDSP.FFT<DSPSplitComplex>) -> [Float] {
        var padded = frame
        padded.append(contentsOf: [Float](repeating: 0, count: fftSize - frame.count))
        let half = fftSize / 2
        var realIn = [Float](repeating: 0, count: half)
        var imagIn = [Float](repeating: 0, count: half)
        var realOut = [Float](repeating: 0, count: half)
        var imagOut = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)

        realIn.withUnsafeMutableBufferPointer { realInPtr in
            imagIn.withUnsafeMutableBufferPointer { imagInPtr in
                realOut.withUnsafeMutableBufferPointer { realOutPtr in
                    imagOut.withUnsafeMutableBufferPointer { imagOutPtr in
                        var input = DSPSplitComplex(realp: realInPtr.baseAddress!,
                                                    imagp: imagInPtr.baseAddress!)
                        var output = DSPSplitComplex(realp: realOutPtr.baseAddress!,
                                                     imagp: imagOutPtr.baseAddress!)
                        padded.withUnsafeBytes { raw in
                            let complex = raw.bindMemory(to: DSPComplex.self)
                            vDSP_ctoz(complex.baseAddress!, 2, &input, 1, vDSP_Length(half))
                        }
                        fft.forward(input: input, output: &output)
                        vDSP_zvmags(&output, 1, &magnitudes, 1, vDSP_Length(half))
                    }
                }
            }
        }
        return magnitudes
    }

    private static func filterbank(fftSize: Int, sampleRate: Double) -> [[Float]] {
        let bins = fftSize / 2
        let high = min(8000.0, sampleRate / 2)
        func toMel(_ hz: Double) -> Double { 2595 * log10(1 + hz / 700) }
        func toHz(_ mel: Double) -> Double { 700 * (pow(10, mel / 2595) - 1) }
        let lowMel = toMel(80), highMel = toMel(high)
        let points = (0...(melBands + 1)).map {
            toHz(lowMel + (highMel - lowMel) * Double($0) / Double(melBands + 1))
        }
        let binOf = points.map { Int(floor(Double(fftSize) * $0 / sampleRate)) }

        return (0..<melBands).map { band in
            var filter = [Float](repeating: 0, count: bins)
            let left = binOf[band], centre = binOf[band + 1], right = binOf[band + 2]
            if centre > left {
                for bin in left..<min(centre, bins) { filter[bin] = Float(bin - left) / Float(centre - left) }
            }
            if right > centre {
                for bin in centre..<min(right, bins) { filter[bin] = Float(right - bin) / Float(right - centre) }
            }
            return filter
        }
    }

    /// DCT-II, dropping the zeroth coefficient — that one is loudness, and how
    /// loudly you happened to speak is not who you are.
    private static func dct(_ bands: [Float]) -> [Float] {
        let count = bands.count
        return (1...coefficients).map { k in
            var sum: Float = 0
            for n in 0..<count {
                sum += bands[n] * cos(Float.pi * Float(k) * (Float(n) + 0.5) / Float(count))
            }
            return sum
        }
    }
}
