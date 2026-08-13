import SwiftUI
import AVFoundation
import Observation

/// Phase 5 — front-camera mirror tile. The capture session runs ONLY while
/// the tile is visible (expanded panel, Home tab); camera permission is
/// requested lazily on first appearance and degrades to a hint tile.
final class MirrorWidget: NotchWidget {
    let id = "mirror"
    let displayName = "Mirror"
    let icon = "web.camera"
    let tileSize: WidgetTileSize = .small
    let tab: NotchTab = .home
    let defaultEnabled = false    // opt-in: camera indicator light is intrusive

    let camera = MirrorCamera()

    /// Quit/disable while the tile is visible must release the camera.
    func deactivate() { camera.shutdown() }

    func makeExpandedView() -> AnyView {
        AnyView(MirrorTileView(camera: camera))
    }
}

@Observable
final class MirrorCamera {
    enum Access { case unknown, granted, denied }

    private(set) var access: Access = .unknown
    @ObservationIgnored private(set) var session: AVCaptureSession?
    /// All start/stop work funnels through one serial queue so a stale start
    /// can never race past a newer stop (visibility is a counter).
    @ObservationIgnored private let sessionQueue = DispatchQueue(
        label: "EgoNotch.mirror.session", qos: .userInitiated)
    @ObservationIgnored private var visible = 0

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
            s.sessionPreset = .medium
            // Built-in camera first — a mirror must not surprise the user
            // with an iPhone Continuity Camera or external webcam.
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
            session = s
        }
        visible += 1
        applyDesiredState()
    }

    func stopSession() {
        visible = max(0, visible - 1)
        applyDesiredState()
    }

    /// Force-stop regardless of visibility (widget disabled / app quit).
    func shutdown() {
        visible = 0
        applyDesiredState()
    }

    private func applyDesiredState() {
        guard let session else { return }
        let want = visible > 0
        // AVCaptureSession start/stop are thread-safe but blocking; the
        // serial queue preserves FIFO order between starts and stops.
        nonisolated(unsafe) let s = session
        sessionQueue.async {
            if want, !s.isRunning { s.startRunning() }
            if !want, s.isRunning { s.stopRunning() }
        }
    }
}

struct MirrorTileView: View {
    var camera: MirrorCamera

    var body: some View {
        Group {
            switch camera.access {
            case .denied:
                VStack(alignment: .leading, spacing: 6) {
                    Chip(text: "No camera", variant: .loss)
                    Text("Enable Camera for EgoNotch in System Settings")
                        .font(Ego.font(10))
                        .foregroundStyle(Ego.textMute)
                }
            case .unknown:
                Text("Requesting camera…")
                    .font(Ego.font(11))
                    .foregroundStyle(Ego.textMute)
            case .granted:
                if let session = camera.session {
                    CameraPreview(session: session)
                        .frame(height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .scaleEffect(x: -1)   // mirror like a real mirror
                } else {
                    Text("Camera unavailable")
                        .font(Ego.font(11))
                        .foregroundStyle(Ego.textMute)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if camera.access == .unknown {
                camera.requestAndStart()
            } else {
                camera.startSession()
            }
        }
        .onDisappear { camera.stopSession() }
    }
}

private struct CameraPreview: NSViewRepresentable {
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
