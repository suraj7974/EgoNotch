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

    @ObservationIgnored private(set) var session: AVCaptureSession?
    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private let movieOutput = AVCaptureMovieFileOutput()
    @ObservationIgnored private let sessionQueue = DispatchQueue(
        label: "EgoNotch.recorder.session", qos: .userInitiated)
    @ObservationIgnored private var visible = 0

    // MARK: - Lifecycle

    func requestAndStart() {
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

    func startSession() {
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
            if let mic = AVCaptureDevice.default(for: .audio),
               let micInput = try? AVCaptureDeviceInput(device: mic),
               s.canAddInput(micInput) {
                s.addInput(micInput)   // videos with sound; fails gracefully
            }
            if s.canAddOutput(photoOutput) { s.addOutput(photoOutput) }
            if s.canAddOutput(movieOutput) { s.addOutput(movieOutput) }
            session = s
        }
        visible += 1
        applyDesiredState()
    }

    func stopSession() {
        visible = max(0, visible - 1)
        applyDesiredState()
    }

    /// Force-stop (widget disabled / app quit) — also ends any recording.
    func shutdown() {
        if isRecording { toggleRecording() }
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
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func toggleRecording() {
        guard access == .granted else { return }
        if isRecording {
            movieOutput.stopRecording()
            // isRecording flips in the delegate when the file is finished.
        } else {
            guard session?.isRunning == true else { return }
            let url = Self.desktopURL(prefix: "EgoNotch Recording", ext: "mov")
            movieOutput.startRecording(to: url, recordingDelegate: self)
            isRecording = true
            recordingStarted = Date()
        }
        applyDesiredState()
    }

    nonisolated static func desktopURL(prefix: String, ext: String) -> URL {
        let desktop = FileManager.default.urls(for: .desktopDirectory,
                                               in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return desktop.appendingPathComponent(
            "\(prefix) \(formatter.string(from: Date())).\(ext)")
    }
}

extension RecorderCamera: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        let url = Self.desktopURL(prefix: "EgoNotch Photo", ext: "jpg")
        try? data.write(to: url)
        Task { @MainActor [weak self] in
            self?.lastSavedName = url.lastPathComponent
        }
    }
}

extension RecorderCamera: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRecording = false
            self.recordingStarted = nil
            self.lastSavedName = outputFileURL.lastPathComponent
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
                HStack(spacing: 14) {
                    preview
                    controls
                }
            }
        }
        .onAppear {
            if camera.access == .unknown {
                camera.requestAndStart()
            } else {
                camera.startSession()
            }
        }
        .onDisappear { camera.stopSession() }
    }

    private var preview: some View {
        Group {
            if let session = camera.session {
                CameraPreview(session: session)
                    .scaleEffect(x: -1)   // mirror like a real mirror
            } else {
                Ego.surface2
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
