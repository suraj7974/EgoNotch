import SwiftUI
import AVFoundation
import Observation

/// Recorder tab: a camera bubble on the left, everything you can do with it on
/// the right. Photos, video, boomerangs, caption GIFs, a four-shot photo booth
/// and a daily selfie streak — all rendered from live frames, so the filter you
/// see is the filter that gets saved.
final class RecorderWidget: NotchWidget {
    let id = "recorder"
    let displayName = "Recorder"
    let icon = "video.fill"
    let tileSize: WidgetTileSize = .wide
    let tab: NotchTab = .recorder
    /// The tab is one composed layout, not a card with a title on top.
    let wantsTileChrome = false

    let camera = RecorderCamera()

    /// Quit/disable must stop any recording and release the camera.
    func deactivate() { camera.shutdown() }

    func makeExpandedView() -> AnyView? {
        AnyView(RecorderTileView(camera: camera))
    }

    func makeClosedAccessory(for edge: NotchEdge) -> AnyView? {
        guard edge == .trailing else { return nil }
        return AnyView(RecordingDot(camera: camera))
    }
}

/// Red dot beside the notch while recording.
private struct RecordingDot: View {
    var camera: RecorderCamera

    var body: some View {
        if camera.isRecording {
            Circle()
                .fill(Ego.loss)
                .frame(width: 6, height: 6)
        }
    }
}

// MARK: - Modes

enum CaptureMode: String, CaseIterable, Identifiable {
    case photo, video, boomerang, gif, booth, daily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: "Photo"
        case .video: "Video"
        case .boomerang: "Boom"
        case .gif: "GIF"
        case .booth: "Booth"
        case .daily: "Daily"
        }
    }

    var icon: String {
        switch self {
        case .photo: "camera.fill"
        case .video: "video.fill"
        case .boomerang: "arrow.trianglehead.2.clockwise"
        case .gif: "text.bubble.fill"
        case .booth: "square.grid.3x1.folder.badge.plus"
        case .daily: "flame.fill"
        }
    }

    var hint: String {
        switch self {
        case .photo: "Saved to Pictures › EgoNotch"
        case .video: "Records with your mic"
        case .boomerang: "1.5s loop, copied for pasting"
        case .gif: "2s clip with your caption"
        case .booth: "Four shots, one strip"
        case .daily: "One a day builds the streak"
        }
    }
}

// MARK: - Camera

@Observable
final class RecorderCamera: NSObject {
    enum Access { case unknown, granted, denied }

    private(set) var access: Access = .unknown
    private(set) var isRecording = false
    private(set) var recordingStarted: Date?
    private(set) var lastSavedName: String?
    private(set) var saveFailed = false
    private(set) var busy = false

    /// Live, filtered frame for the bubble.
    private(set) var preview: CGImage?
    /// The same frame under each look, for the filter chips.
    private(set) var chips: [String: CGImage] = [:]

    var mode: CaptureMode = .photo
    var filter: CaptureFilter = .none {
        didSet { frames.set(filter: filter) }
    }
    var mirrored = true {
        didSet { frames.set(mirrored: mirrored) }
    }
    var selfTimer = 0                      // 0, 3 or 10 seconds
    var gifCaption = ""

    /// Countdown and flash drive the booth's on-screen drama.
    private(set) var countdown: Int?
    private(set) var flash: Double = 0
    private(set) var prompt: String?

    let library = CaptureLibrary()
    let streak = SelfieStreak()

    @ObservationIgnored private(set) var session: AVCaptureSession?
    @ObservationIgnored private let frames = CameraFrames()
    @ObservationIgnored private let movieOutput = AVCaptureMovieFileOutput()
    @ObservationIgnored nonisolated(unsafe) private var micInput: AVCaptureDeviceInput?
    @ObservationIgnored private let sessionQueue = DispatchQueue(
        label: "EgoNotch.recorder.session", qos: .userInitiated)
    @ObservationIgnored private var visible = 0
    @ObservationIgnored private var pump: Task<Void, Never>?
    @ObservationIgnored private var sequence: Task<Void, Never>?

    private static let prompts = ["Look up", "Big smile", "Silly one", "Peace ✌︎"]

    // MARK: - Lifecycle

    func appear() {
        visible += 1
        requestAndStart()
        library.refresh()
        streak.refresh()
        startPump()
    }

    func disappear() {
        visible = max(0, visible - 1)
        if visible == 0 {
            pump?.cancel()
            pump = nil
            sequence?.cancel()
            sequence = nil
            countdown = nil
            prompt = nil
        }
        applyDesiredState()
    }

    /// One loop drives both the bubble and the chips — chips refresh far more
    /// slowly, because six extra filter passes per frame is a waste of a fan.
    private func startPump() {
        guard pump == nil else { return }
        pump = Task { @MainActor [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self else { return }
                self.preview = self.frames.currentPreview()
                tick += 1
                if tick % 15 == 0 {
                    // Six filter passes is real work — never on the main actor,
                    // where it would stutter every animation in the panel.
                    let source = self.frames
                    self.chips = await Task.detached(priority: .utility) {
                        var built: [String: CGImage] = [:]
                        for option in CaptureFilter.allCases {
                            built[option.rawValue] = source.preview(with: option, maxWidth: 96)
                        }
                        return built
                    }.value
                }
            }
        }
    }

    private func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = .granted
            startSession()
        case .denied, .restricted:
            access = .denied
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    self?.access = granted ? .granted : .denied
                    if granted { self?.startSession() }
                }
            }
        @unknown default:
            access = .denied
        }
    }

    private func startSession() {
        guard access == .granted else { return }
        if session == nil {
            let s = AVCaptureSession()
            s.sessionPreset = .high
            let builtIn = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: .unspecified
            ).devices.first
            guard let device = builtIn ?? AVCaptureDevice.userPreferredCamera
                    ?? AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  s.canAddInput(input) else {
                access = .denied
                return
            }
            s.addInput(input)
            // NO mic here: the preview must never prompt for (or hold) the
            // microphone — it attaches lazily when a recording starts.
            if s.canAddOutput(frames.output) { s.addOutput(frames.output) }
            if s.canAddOutput(movieOutput) { s.addOutput(movieOutput) }
            session = s
            frames.set(filter: filter)
            frames.set(mirrored: mirrored)
        }
        applyDesiredState()
    }

    /// Force-stop (widget disabled / app quit) — also ends any recording.
    func shutdown() {
        if isRecording { movieOutput.stopRecording() }
        visible = 0
        pump?.cancel()
        pump = nil
        sequence?.cancel()
        sequence = nil
        applyDesiredState()
    }

    private func applyDesiredState() {
        guard let session else { return }
        // Keep running while recording even if the panel closes.
        let want = visible > 0 || isRecording
        nonisolated(unsafe) let s = session
        sessionQueue.async {
            if want, !s.isRunning { s.startRunning() }
            if !want, s.isRunning { s.stopRunning() }
        }
    }

    // MARK: - The shutter

    /// One button, six behaviours — whatever the selected mode means.
    func trigger() {
        guard access == .granted else { return }
        if isRecording { movieOutput.stopRecording(); return }
        guard session?.isRunning == true, sequence == nil, !busy else { return }
        saveFailed = false

        switch mode {
        case .photo:   run { await self.shootPhoto() }
        case .video:   startVideo()
        case .boomerang: run { await self.shootLoop(seconds: 1.5, boomerang: true) }
        case .gif:     run { await self.shootLoop(seconds: 2.0, boomerang: false) }
        case .booth:   run { await self.runBooth() }
        case .daily:   run { await self.shootDaily() }
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        sequence = Task { @MainActor [weak self] in
            await work()
            self?.sequence = nil
        }
    }

    // MARK: - Stills

    private func shootPhoto() async {
        await countIn(seconds: selfTimer)
        await flashNow()
        guard let frame = frames.currentFull() else { saveFailed = true; return }
        let url = CaptureExport.url(prefix: "EgoNotch Photo", ext: "png")
        let ok = CaptureExport.writePNG(CaptureExport.squareCrop(frame), to: url)
        finish(ok: ok, name: url.lastPathComponent)
    }

    private func shootDaily() async {
        await countIn(seconds: selfTimer)
        await flashNow()
        guard let frame = frames.currentFull() else { saveFailed = true; return }
        streak.save(frame)
        lastSavedName = "Day \(streak.total) · streak \(streak.streak)"
        library.refresh()
    }

    // MARK: - Loops (boomerang + caption GIF)

    private func shootLoop(seconds: Double, boomerang: Bool) async {
        await countIn(seconds: selfTimer)
        busy = true
        prompt = boomerang ? "Move!" : "Rolling…"
        frames.startCollecting(maxFrames: Int(seconds * 15) + 4, stride: 2)
        try? await Task.sleep(for: .seconds(seconds))
        let collected = frames.finishCollecting()
        prompt = nil
        guard !collected.isEmpty else {
            busy = false
            saveFailed = true
            return
        }

        let caption = boomerang ? "" : gifCaption
        let url = CaptureExport.url(prefix: boomerang ? "EgoNotch Boomerang" : "EgoNotch GIF",
                                    ext: "gif")
        // Encoding 40-odd frames is heavy; do it off the main actor so the
        // panel keeps animating.
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            let stamped = caption.isEmpty
                ? collected
                : collected.compactMap { CaptureExport.caption(caption, on: $0) }
            return CaptureExport.writeGIF(stamped, to: url,
                                          frameDuration: boomerang ? 0.06 : 0.08,
                                          loopBackwards: boomerang)
        }.value

        if ok { CaptureExport.copyToPasteboard(fileAt: url) }
        busy = false
        finish(ok: ok, name: ok ? "\(url.lastPathComponent) · copied" : nil)
    }

    // MARK: - Photo booth

    private func runBooth() async {
        busy = true
        var shots: [CGImage] = []
        for index in 0..<4 {
            prompt = Self.prompts[index]
            await countIn(seconds: 3, showPrompt: true)
            await flashNow()
            if let frame = frames.currentFull() {
                shots.append(CaptureExport.squareCrop(frame))
            }
            try? await Task.sleep(for: .milliseconds(450))
        }
        prompt = nil

        let url = CaptureExport.url(prefix: "EgoNotch Booth", ext: "png")
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            guard let strip = CaptureExport.photoStrip(shots) else { return false }
            return CaptureExport.writePNG(strip, to: url)
        }.value
        busy = false
        finish(ok: ok, name: url.lastPathComponent)
    }

    // MARK: - Video

    private func startVideo() {
        // Mic permission is requested ONLY here — first actual record.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor [weak self] in self?.beginRecording() }
            }
        } else {
            beginRecording()   // denied → silent video (graceful)
        }
    }

    private func beginRecording() {
        guard let session, session.isRunning, !isRecording else { return }
        isRecording = true
        recordingStarted = Date()
        applyDesiredState()
        let url = CaptureExport.url(prefix: "EgoNotch Recording", ext: "mov")
        let micAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        nonisolated(unsafe) let s = session
        nonisolated(unsafe) let movie = movieOutput
        sessionQueue.async { [weak self] in
            if micAuthorized,
               let mic = AVCaptureDevice.default(for: .audio),
               let input = try? AVCaptureDeviceInput(device: mic) {
                s.beginConfiguration()
                if s.canAddInput(input) {
                    s.addInput(input)
                    self?.micInput = input
                }
                s.commitConfiguration()
            }
            guard let self else { return }
            movie.startRecording(to: url, recordingDelegate: self)
        }
    }

    /// Detach the mic as soon as the recording ends — no lingering hot mic.
    private func detachMic() {
        guard let session, let micInput else { return }
        self.micInput = nil
        nonisolated(unsafe) let s = session
        nonisolated(unsafe) let input = micInput
        sessionQueue.async {
            s.beginConfiguration()
            s.removeInput(input)
            s.commitConfiguration()
        }
    }

    // MARK: - Shared bits

    private func countIn(seconds: Int, showPrompt: Bool = false) async {
        guard seconds > 0 else { return }
        for remaining in stride(from: seconds, through: 1, by: -1) {
            countdown = remaining
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { break }
        }
        countdown = nil
    }

    private func flashNow() async {
        flash = 1
        try? await Task.sleep(for: .milliseconds(90))
        flash = 0
    }

    private func finish(ok: Bool, name: String?) {
        if ok {
            lastSavedName = name
            saveFailed = false
            library.refresh()
        } else {
            saveFailed = true
        }
    }
}

extension RecorderCamera: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        // AVFoundation can report an error alongside a successfully finished
        // partial file — trust the success flag + the file's existence.
        let finishedOK = (error as NSError?)
            .map { ($0.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) == true }
            ?? true
        let ok = finishedOK && FileManager.default.fileExists(atPath: outputFileURL.path)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRecording = false
            self.recordingStarted = nil
            self.finish(ok: ok, name: outputFileURL.lastPathComponent)
            self.detachMic()
            self.applyDesiredState()
        }
    }
}
