import AVFoundation
import CoreImage
import AppKit

/// Live frames off the camera, filtered and handed to the UI.
///
/// The recorder used to show an `AVCaptureVideoPreviewLayer`, which gives you
/// pixels you can never touch — no filters, no boomerang, no GIF. This taps
/// the same session with a data output instead and renders the frames itself.
///
/// `nonisolated` is load-bearing: AVFoundation delivers on its own queue, and
/// this module defaults to MainActor isolation, so an implicitly-isolated
/// delegate would trap the process on the first frame.
nonisolated final class CameraFrames: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Newest frame, already filtered and mirrored, for the preview.
    private let lock = NSLock()
    private var latest: CGImage?
    private var latestFull: CGImage?
    private var recorded: [CGImage] = []

    private var filter: CaptureFilter = .none
    private var mirrored = true
    private var collecting = false
    private var collectStride = 2          // keep every other frame → ~15fps
    private var frameIndex = 0
    private var maxFrames = 45

    let output = AVCaptureVideoDataOutput()
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private let queue = DispatchQueue(label: "EgoNotch.recorder.frames", qos: .userInitiated)

    override init() {
        super.init()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                    kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
    }

    // MARK: - Settings

    func set(filter: CaptureFilter) {
        lock.lock(); self.filter = filter; lock.unlock()
    }

    func set(mirrored: Bool) {
        lock.lock(); self.mirrored = mirrored; lock.unlock()
    }

    // MARK: - Reading

    /// Small, for the circular preview and the filter chips.
    func currentPreview() -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }

    /// Full resolution, for anything being saved.
    func currentFull() -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        return latestFull
    }

    /// The same frame under a different look — used to draw the filter chips
    /// showing your own face rather than a swatch.
    func preview(with other: CaptureFilter, maxWidth: CGFloat = 96) -> CGImage? {
        lock.lock()
        let source = rawImage
        let flip = mirrored
        lock.unlock()
        guard let source else { return nil }
        return render(source, filter: other, mirrored: flip, maxWidth: maxWidth)
    }

    private var rawImage: CIImage?

    // MARK: - Frame collection (boomerang / GIF)

    func startCollecting(maxFrames: Int = 45, stride: Int = 2) {
        lock.lock()
        recorded.removeAll(keepingCapacity: true)
        self.maxFrames = maxFrames
        collectStride = max(1, stride)
        collecting = true
        lock.unlock()
    }

    func finishCollecting() -> [CGImage] {
        lock.lock(); defer { lock.unlock() }
        collecting = false
        let frames = recorded
        recorded.removeAll(keepingCapacity: false)
        return frames
    }

    var collectedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return recorded.count
    }

    // MARK: - Delegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let source = CIImage(cvPixelBuffer: buffer)

        lock.lock()
        let currentFilter = filter
        let flip = mirrored
        let isCollecting = collecting
        let stride = collectStride
        let cap = maxFrames
        rawImage = source
        lock.unlock()

        guard let preview = render(source, filter: currentFilter, mirrored: flip, maxWidth: 320)
        else { return }
        let full = render(source, filter: currentFilter, mirrored: flip, maxWidth: 1280)

        frameIndex &+= 1
        lock.lock()
        latest = preview
        if let full { latestFull = full }
        if isCollecting, frameIndex % stride == 0, recorded.count < cap,
           let frame = render(source, filter: currentFilter, mirrored: flip, maxWidth: 420) {
            recorded.append(frame)
        }
        lock.unlock()
    }

    private func render(_ image: CIImage, filter: CaptureFilter,
                        mirrored: Bool, maxWidth: CGFloat) -> CGImage? {
        var working = filter.apply(to: image)
        if mirrored {
            working = working
                .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
                .transformed(by: CGAffineTransform(translationX: working.extent.width, y: 0))
        }
        let scale = min(1, maxWidth / max(working.extent.width, 1))
        if scale < 1 {
            working = working.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return context.createCGImage(working, from: working.extent)
    }
}
