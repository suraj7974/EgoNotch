import SwiftUI
import AVFoundation
import Observation

/// Recorder tab: live camera preview (mirrored), photo capture, and video
/// recording — files are saved to the Desktop. The session runs ONLY while
/// the tab is visible; permission is requested lazily on first appearance.
final class RecorderWidget: NotchWidget {
    let id = "recorder"
    let displayName = "Recorder"
    let icon = "video.fill"
    let tileSize: WidgetTileSize = .wide
    let tab: NotchTab = .recorder

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

@Observable
final class RecorderCamera: NSObject {
    enum Access { case unknown, granted, denied }

    private(set) var access: Access = .unknown
    private(set) var isRecording = false
    private(set) var recordingStarted: Date?
    private(set) var lastSavedName: String?
    private(set) var saveFailed = false

    @ObservationIgnored private(set) var session: AVCaptureSession?
    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private let movieOutput = AVCaptureMovieFileOutput()
    // Written on sessionQueue (attach) / read+cleared on main (detach) —
    // strictly serialized by the recording lifecycle.
    @ObservationIgnored nonisolated(unsafe) private var micInput: AVCaptureDeviceInput?
    @ObservationIgnored private let sessionQueue = DispatchQueue(
        label: "EgoNotch.recorder.session", qos: .userInitiated)
    @ObservationIgnored private var visible = 0

    // MARK: - Lifecycle
    // visible tracks ACTUAL tile visibility (appear/disappear), independent
    // of the permission dance — otherwise a first-run grant double-counts
    // and the camera never turns off.

    func appear() {
        visible += 1
        requestAndStart()
    }

    func disappear() {
        visible = max(0, visible - 1)
        applyDesiredState()
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
            if s.canAddOutput(photoOutput) { s.addOutput(photoOutput) }
            if s.canAddOutput(movieOutput) { s.addOutput(movieOutput) }
            session = s
        }
        applyDesiredState()
    }

    /// Force-stop (widget disabled / app quit) — also ends any recording.
    func shutdown() {
        if isRecording { movieOutput.stopRecording() }
        visible = 0
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

    // MARK: - Capture

    func capturePhoto() {
        guard access == .granted, session?.isRunning == true else { return }
        saveFailed = false
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func toggleRecording() {
        guard access == .granted else { return }
        if isRecording {
            movieOutput.stopRecording()
            // isRecording flips in the delegate when the file is finished.
            return
        }
        guard session?.isRunning == true else { return }
        saveFailed = false
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
        let url = Self.desktopURL(prefix: "EgoNotch Recording", ext: "mov")
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

    /// Collision-proof Desktop filename (Screenshot.app style " (2)" suffix).
    nonisolated static func desktopURL(prefix: String, ext: String) -> URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory,
                                               in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "\(prefix) \(formatter.string(from: Date()))"
        var url = desktop.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = desktop.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return url
    }
}

extension RecorderCamera: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            Task { @MainActor [weak self] in self?.saveFailed = true }
            return
        }
        let url = Self.desktopURL(prefix: "EgoNotch Photo", ext: "jpg")
        let wrote = (try? data.write(to: url)) != nil
        Task { @MainActor [weak self] in
            if wrote {
                self?.lastSavedName = url.lastPathComponent
            } else {
                self?.saveFailed = true   // e.g. Desktop access denied
            }
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
            if ok {
                self.lastSavedName = outputFileURL.lastPathComponent
            } else {
                self.saveFailed = true
            }
            self.detachMic()
            self.applyDesiredState()
        }
    }
}

struct RecorderTileView: View {
    var camera: RecorderCamera

    var body: some View {
        Group {
            switch camera.access {
            case .denied:
                HStack(spacing: 10) {
                    Chip(text: "No camera", variant: .loss)
                    Text("Enable Camera for EgoNotch in System Settings")
                        .font(Ego.font(11))
                        .foregroundStyle(Ego.textMute)
                    Spacer()
                }
            case .unknown:
                Text("Requesting camera…")
                    .font(Ego.font(11))
                    .foregroundStyle(Ego.textMute)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .granted:
                HStack(spacing: 24) {
                    Spacer(minLength: 0)
                    preview
                    controls
                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear { camera.appear() }
        .onDisappear { camera.disappear() }
    }

    private var preview: some View {
        // Circular bubble: aspect-fill keeps the whole face in frame even in
        // the short panel.
        Group {
            if let session = camera.session {
                CameraPreview(session: session)
                    .scaleEffect(x: -1)   // mirror like a real mirror
            } else {
                Ego.surface2
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 148, maxHeight: 148)   // shrinks with the panel height
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            RoundControlButton(symbol: "camera.fill", size: 13, diameter: 40) {
                camera.capturePhoto()
            }
            Button {
                camera.toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 2)
                        .frame(width: 40, height: 40)
                    if camera.isRecording {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Ego.loss)
                            .frame(width: 16, height: 16)
                    } else {
                        Circle()
                            .fill(Ego.loss)
                            .frame(width: 28, height: 28)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(camera.isRecording ? "Stop recording" : "Record video")

            if camera.isRecording, let started = camera.recordingStarted {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.duration(from: started, to: context.date))
                        .font(Ego.font(10, .semibold))
                        .egoDigits()
                        .foregroundStyle(Ego.loss)
                }
            } else if camera.saveFailed {
                Text("Save failed")
                    .font(Ego.font(9))
                    .foregroundStyle(Ego.loss)
                    .help("Check Desktop folder access in System Settings > Privacy")
            } else if let saved = camera.lastSavedName {
                Text("Saved to Desktop")
                    .font(Ego.font(9))
                    .foregroundStyle(Ego.win)
                    .help(saved)
            }
        }
        .frame(width: 96)
    }

    private static func duration(from start: Date, to now: Date) -> String {
        let s = max(Int(now.timeIntervalSince(start)), 0)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
