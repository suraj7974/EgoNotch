import SwiftUI
import EventKit
import AVFoundation
import CoreLocation
import UserNotifications
import ApplicationServices

/// First-launch walkthrough: what the notch does + a live permissions
/// overview. Nothing is requested here — prompts fire lazily when a widget
/// first needs them; this page just explains what to expect.
struct OnboardingView: View {
    var onDone: () -> Void
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to EgoNotch")
                    .font(Ego.font(22, .bold))
                    .foregroundStyle(Ego.text)
                Text("Your notch is now a hub. Here's the one-minute tour.")
                    .font(Ego.font(13))
                    .foregroundStyle(Ego.textMute)
            }

            VStack(alignment: .leading, spacing: 10) {
                tip("cursorarrow.motionlines", "Hover the notch to open it — move away or press Esc to close.")
                tip("square.grid.2x2", "Tabs organize everything: Home, Shelf, Focus, Notes, Clips, Today.")
                tip("tray.and.arrow.down", "Drag files onto the notch to stage them on the Shelf, then drag them out anywhere or AirDrop.")
                tip("timer", "Start a Focus session and the countdown lives in your menu bar.")
                tip("gearshape", "Every module can be toggled in Settings — the menu bar icon is always there.")
            }
            .padding(14)
            .background(Ego.surface, in: RoundedRectangle(cornerRadius: Ego.cardRadius))

            VStack(alignment: .leading, spacing: 8) {
                Text("Permissions")
                    .font(Ego.font(13, .semibold))
                    .foregroundStyle(Ego.text)
                Text("EgoNotch never asks up front — each prompt appears the first time you use the feature.")
                    .font(Ego.font(11))
                    .foregroundStyle(Ego.textMute)

                permissionRow("calendar", "Calendar", "Today tab",
                              status: calendarStatus)
                permissionRow("location", "Location", "Weather (or set a city in Settings)",
                              status: locationStatus)
                permissionRow("web.camera", "Camera", "Mirror module (off by default)",
                              status: cameraStatus)
                permissionRow("accessibility", "Accessibility", "Volume/brightness HUD (off by default)",
                              status: AXIsProcessTrusted() ? .granted : .pending)
                permissionRow("bell.badge", "Notifications", "Focus timer completion",
                              status: notificationRowStatus)
            }
            .padding(14)
            .background(Ego.surface, in: RoundedRectangle(cornerRadius: Ego.cardRadius))

            HStack {
                Spacer()
                Button("Get Started") { onDone() }
                    .buttonStyle(.egoPrimary)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(Ego.bg)
        .preferredColorScheme(.dark)
        .task {
            notificationStatus = await UNUserNotificationCenter.current()
                .notificationSettings().authorizationStatus
        }
    }

    // MARK: - Rows

    private enum PermissionStatus { case granted, denied, pending }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(Ego.accentSoft)
                .frame(width: 20)
            Text(text)
                .font(Ego.font(12))
                .foregroundStyle(Ego.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionRow(_ symbol: String, _ name: String, _ usedBy: String,
                               status: PermissionStatus) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(Ego.text)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(Ego.font(12, .medium))
                    .foregroundStyle(Ego.text)
                Text(usedBy)
                    .font(Ego.font(10))
                    .foregroundStyle(Ego.textMute)
            }
            Spacer()
            switch status {
            case .granted: Chip(text: "Granted", variant: .win)
            case .denied: Chip(text: "Denied", variant: .loss)
            case .pending: Chip(text: "Asks later", variant: .neutral)
            }
        }
        .padding(.vertical, 2)
    }

    private var calendarStatus: PermissionStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .denied, .restricted, .writeOnly: .denied
        default: .pending
        }
    }

    private var cameraStatus: PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .denied, .restricted: .denied
        default: .pending
        }
    }

    private var locationStatus: PermissionStatus {
        switch CLLocationManager().authorizationStatus {
        case .authorized, .authorizedAlways: .granted
        case .denied, .restricted: .denied
        default: .pending
        }
    }

    private var notificationRowStatus: PermissionStatus {
        switch notificationStatus {
        case .authorized, .provisional: .granted
        case .denied: .denied
        default: .pending
        }
    }
}
