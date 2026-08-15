import Accelerate
import Foundation

/// A voice, described independently of the words spoken.
///
/// The first attempt matched the wake phrase against recorded copies of the
/// same phrase. That is more accurate, but it makes enrolment depend on the
/// recogniser spelling your name correctly — the exact thing this feature
/// exists to work around — and it asks you to repeat one phrase five times.
///
/// This models the *voice* instead: read a passage, and what is kept is the
/// distribution of your MFCCs — where your vocal tract puts its energy, and
/// how much it moves around. Because it describes the speaker rather than the
/// sentence, enrolment and the wake word need not share a single word.
nonisolated struct VoiceProfile: Codable, Sendable {
    /// Average of each coefficient across every frame of speech.
    let means: [Float]
    /// How much each coefficient moves — a voice is its range as well as its
    /// centre.
    let deviations: [Float]
    let frameCount: Int
    /// Distance beyond which this stops being the same person. Measured from
    /// the enrolment itself, never guessed.
    var threshold: Float

    // MARK: - Building one

    static func make(samples: [Float], sampleRate: Double) -> VoiceProfile? {
        guard let frames = MFCC.frames(samples: samples, sampleRate: sampleRate),
              frames.count >= 8 else { return nil }
        var profile = summarise(frames)
        profile.threshold = threshold(from: chunkDistances(of: frames, against: profile))
        return profile
    }

    /// Sets the gate by replaying the verification path against the enrolment
    /// audio: slice it into windows the length of a real command, build a
    /// profile from each exactly as a live utterance would be, and see how far
    /// they land.
    ///
    /// The first attempt calibrated on silence-stripped chunks of the whole
    /// reading, which is a different shape of input entirely — it produced a
    /// gate of 0.67 while the speaker's own commands measured 0.71 and 1.07,
    /// and locked them out of their own assistant.
    static func calibrate(from samples: [Float], sampleRate: Double,
                          against profile: VoiceProfile, window: Double) -> Float {
        let size = Int(sampleRate * window)
        let hop = max(Int(sampleRate * window * 0.5), 1)
        guard samples.count > size else { return profile.threshold }

        var distances: [Float] = []
        var start = 0
        while start + size <= samples.count {
            let slice = Array(samples[start..<(start + size)])
            if let piece = VoiceProfile.make(samples: slice, sampleRate: sampleRate) {
                distances.append(profile.distance(to: piece))
            }
            start += hop
        }
        guard !distances.isEmpty else { return profile.threshold }
        distances.sort()
        // The worst honest window, plus a margin. Every one of these came from
        // the user, so anything below the top of that range must be let in.
        let worst = distances[distances.count - 1]
        // A wide margin, and not an arbitrary one: enrolment is read in a
        // quiet room, while commands are given over whatever is playing. The
        // speaker's own utterances were measured at up to twice their
        // enrolment spread once music was in the room, so the gate has to
        // clear that or it only works in silence.
        return min(max(worst * 2.2, 0.9), 3.5)
    }

    private static func summarise(_ frames: [[Float]]) -> VoiceProfile {
        let width = frames[0].count
        var means = [Float](repeating: 0, count: width)
        var deviations = [Float](repeating: 0, count: width)

        for frame in frames {
            for index in 0..<width { means[index] += frame[index] }
        }
        for index in 0..<width { means[index] /= Float(frames.count) }

        for frame in frames {
            for index in 0..<width {
                let delta = frame[index] - means[index]
                deviations[index] += delta * delta
            }
        }
        for index in 0..<width {
            deviations[index] = max(sqrt(deviations[index] / Float(frames.count)), 1e-3)
        }
        return VoiceProfile(means: means, deviations: deviations,
                            frameCount: frames.count, threshold: 1)
    }

    /// Splits the enrolment into chunks the length of a wake phrase and asks
    /// how far each one lands from the whole. That spread *is* the natural
    /// variation of this speaker reading aloud, so the threshold sits just
    /// beyond it — strict for a steady voice, forgiving for a variable one,
    /// with no number for anyone to tune.
    private static func chunkDistances(of frames: [[Float]], against profile: VoiceProfile) -> [Float] {
        let chunk = 90                       // ≈ 0.9 s, about one wake phrase
        guard frames.count >= chunk * 2 else { return [] }
        var out: [Float] = []
        var index = 0
        while index + chunk <= frames.count {
            out.append(profile.distance(to: summarise(Array(frames[index..<(index + chunk)]))))
            index += chunk / 2               // overlapping, for more samples
        }
        return out.sorted()
    }

    /// The median chunk, not the worst: a passage read aloud always contains
    /// one odd stretch, and letting the strangest half-second set the gate
    /// makes it useless. Measured against synthesised voices, this lands with
    /// the speaker two to three times inside it and every other voice out.
    private static func threshold(from chunks: [Float]) -> Float {
        guard !chunks.isEmpty else { return 1.6 }
        let median = chunks[chunks.count / 2]
        return min(max(median * 1.6, 0.25), 2.0)
    }

    // MARK: - Comparing

    /// How far another voice sits from this one, measured in this speaker's
    /// own units: each coefficient's difference is divided by how much *this*
    /// voice naturally moves that coefficient, so a coefficient the speaker
    /// holds steady counts for much more than one they throw around.
    func distance(to other: VoiceProfile) -> Float {
        guard means.count == other.means.count, !means.isEmpty else {
            return .greatestFiniteMagnitude
        }
        var sum: Float = 0
        for index in 0..<means.count {
            let scale = max(deviations[index], other.deviations[index])
            let centre = (means[index] - other.means[index]) / scale
            // Two voices can share an average and still differ in how much
            // they move, so the spread is compared as well as the centre.
            let spread = log(max(deviations[index], 1e-3) / max(other.deviations[index], 1e-3))
            sum += centre * centre + spread * spread * 0.5
        }
        return sqrt(sum / Float(means.count))
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
    static func frames(samples: [Float], sampleRate: Double) -> [[Float]]? {
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

        // Speech, not the gaps in it — but not so strict that a quietly read
        // passage is thrown away as silence.
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
