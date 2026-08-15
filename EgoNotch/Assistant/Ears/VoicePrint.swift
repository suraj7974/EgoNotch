import Accelerate
import Foundation

/// A fingerprint of a spoken wake phrase.
///
/// macOS gives third-party apps no speaker identification at all — Speech has
/// no diarization and SoundAnalysis classifies sound *types*, not people — so
/// this is built from scratch. It works because the phrase is FIXED: comparing
/// the same words each time (text-dependent verification) is a far easier
/// problem than open-set "who is this", and it's the same trick behind "Hey
/// Siri" personalisation.
///
/// The features are MFCCs — a compact description of vocal-tract shape, which
/// is what actually differs between two people saying the same word. Loudness
/// and microphone colouring are normalised away on purpose; pitch and timbre
/// are what remain.
nonisolated struct VoicePrint: Codable, Sendable {
    /// Frames × coefficients. Around 100 frames for a one-second phrase.
    let frames: [[Float]]

    var isUsable: Bool { frames.count >= 12 }

    // MARK: - Making one

    private static let coefficients = 12
    private static let melBands = 26
    private static let preEmphasis: Float = 0.97

    /// Turns raw mono samples into a fingerprint, or nil when there isn't
    /// enough speech in them to be worth comparing.
    static func make(samples: [Float], sampleRate: Double) -> VoicePrint? {
        guard sampleRate > 0, samples.count > Int(sampleRate * 0.2) else { return nil }

        let windowLength = Int(sampleRate * 0.025)      // 25 ms
        let hop = Int(sampleRate * 0.010)               // 10 ms
        guard windowLength > 32, hop > 0 else { return nil }
        let fftSize = 1 << Int(ceil(log2(Double(windowLength))))

        // Pre-emphasis lifts the high frequencies, where the differences
        // between two voices mostly live.
        var emphasised = [Float](repeating: 0, count: samples.count)
        emphasised[0] = samples[0]
        for index in 1..<samples.count {
            emphasised[index] = samples[index] - preEmphasis * samples[index - 1]
        }

        let window = vDSP.window(ofType: Float.self,
                                 usingSequence: .hanningDenormalized,
                                 count: windowLength,
                                 isHalfWindow: false)
        let filters = melFilterbank(fftSize: fftSize, sampleRate: sampleRate)

        guard let fft = vDSP.FFT(log2n: vDSP_Length(log2(Double(fftSize))),
                                 radix: .radix2,
                                 ofType: DSPSplitComplex.self) else { return nil }

        var frames: [[Float]] = []
        var energies: [Float] = []
        var start = 0
        while start + windowLength <= emphasised.count {
            var frame = Array(emphasised[start..<(start + windowLength)])
            vDSP.multiply(frame, window, result: &frame)

            let power = powerSpectrum(frame, fftSize: fftSize, fft: fft)
            // Log-mel energies, then a DCT to decorrelate them.
            var bands = [Float](repeating: 0, count: melBands)
            for (index, filter) in filters.enumerated() {
                var sum: Float = 0
                vDSP_dotpr(power, 1, filter, 1, &sum, vDSP_Length(power.count))
                bands[index] = log(max(sum, 1e-10))
            }
            frames.append(dct(bands))
            energies.append(bands.reduce(0, +) / Float(melBands))
            start += hop
        }

        guard frames.count >= 12 else { return nil }
        let trimmed = trimToSpeech(frames: frames, energies: energies)
        return VoicePrint(frames: normalise(trimmed))
    }

    /// The recording is a rolling window, so most of it is room tone. Keep the
    /// loud part — otherwise two fingerprints are mostly a comparison of
    /// silence, and everybody's silence matches.
    private static func trimToSpeech(frames: [[Float]], energies: [Float]) -> [[Float]] {
        guard let peak = energies.max(), let floor = energies.min(), peak > floor else { return frames }
        let threshold = floor + (peak - floor) * 0.45
        guard let first = energies.firstIndex(where: { $0 >= threshold }),
              let last = energies.lastIndex(where: { $0 >= threshold }),
              last > first else { return frames }
        // A little padding so the start of the first consonant survives.
        let from = max(0, first - 3)
        let to = min(frames.count - 1, last + 3)
        return Array(frames[from...to])
    }

    /// Subtracts each coefficient's own mean across the utterance. This is what
    /// makes the match survive a different distance from the microphone, a
    /// different room, or a different input gain — all of which shift the
    /// coefficients bodily without changing the voice.
    private static func normalise(_ frames: [[Float]]) -> [[Float]] {
        guard let width = frames.first?.count, width > 0 else { return frames }
        var means = [Float](repeating: 0, count: width)
        for frame in frames {
            for index in 0..<width { means[index] += frame[index] }
        }
        for index in 0..<width { means[index] /= Float(frames.count) }
        return frames.map { frame in
            (0..<width).map { frame[$0] - means[$0] }
        }
    }

    // MARK: - Signal plumbing

    private static func powerSpectrum(_ frame: [Float], fftSize: Int,
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

    /// Triangular filters spaced evenly on the mel scale — closely packed at
    /// low frequencies, where hearing (and speech) has its detail.
    private static func melFilterbank(fftSize: Int, sampleRate: Double) -> [[Float]] {
        let bins = fftSize / 2
        let low = 80.0
        let high = min(8000.0, sampleRate / 2)
        func toMel(_ hz: Double) -> Double { 2595 * log10(1 + hz / 700) }
        func toHz(_ mel: Double) -> Double { 700 * (pow(10, mel / 2595) - 1) }

        let lowMel = toMel(low), highMel = toMel(high)
        let points = (0...(melBands + 1)).map { index -> Double in
            toHz(lowMel + (highMel - lowMel) * Double(index) / Double(melBands + 1))
        }
        let binOf = points.map { Int(floor(Double(fftSize) * $0 / sampleRate)) }

        return (0..<melBands).map { band in
            var filter = [Float](repeating: 0, count: bins)
            let left = binOf[band], centre = binOf[band + 1], right = binOf[band + 2]
            if centre > left {
                for bin in left..<min(centre, bins) {
                    filter[bin] = Float(bin - left) / Float(centre - left)
                }
            }
            if right > centre {
                for bin in centre..<min(right, bins) {
                    filter[bin] = Float(right - bin) / Float(right - centre)
                }
            }
            return filter
        }
    }

    /// DCT-II, keeping the low coefficients. Small enough that a hand-rolled
    /// loop beats setting up a transform.
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

    // MARK: - Comparing two

    /// Dynamic time warping: the same words said faster or slower still line
    /// up, because the path is allowed to stretch. Returned distance is per
    /// frame, so utterances of different lengths stay comparable.
    static func distance(_ lhs: VoicePrint, _ rhs: VoicePrint) -> Float {
        let a = lhs.frames, b = rhs.frames
        guard !a.isEmpty, !b.isEmpty else { return .greatestFiniteMagnitude }

        // A band around the diagonal: it halves the work and, more usefully,
        // refuses matches that would need a wild stretch to line up at all.
        let band = max(12, Int(Double(max(a.count, b.count)) * 0.25))
        var previous = [Float](repeating: .greatestFiniteMagnitude, count: b.count + 1)
        var current = previous
        previous[0] = 0

        for i in 1...a.count {
            current = [Float](repeating: .greatestFiniteMagnitude, count: b.count + 1)
            let from = max(1, i - band), to = min(b.count, i + band)
            guard from <= to else { continue }
            for j in from...to {
                let cost = frameDistance(a[i - 1], b[j - 1])
                let best = min(previous[j], min(current[j - 1], previous[j - 1]))
                current[j] = cost + (best == .greatestFiniteMagnitude ? 0 : best)
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
