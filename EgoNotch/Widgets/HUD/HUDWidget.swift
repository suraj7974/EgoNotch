import SwiftUI
import Observation

/// Phase 5 — replaces the macOS volume/brightness overlay with a notch HUD.
/// OFF by default: enabling it in Settings triggers the Accessibility prompt
/// (the event tap needs trust); denial degrades to a hint tile, never a crash.
final class HUDWidget: NotchWidget {
    let id = "hud"
    let displayName = "Volume & Brightness HUD"
    let icon = "slider.horizontal.3"
    let tileSize: WidgetTileSize = .small
    let tab: NotchTab = .home
    let defaultEnabled = false

    let controller = HUDController()

    func activate() { controller.start() }
    func deactivate() { controller.stop() }

    func makeExpandedView() -> AnyView {
        AnyView(HUDStatusTile(controller: controller))
    }
}

@Observable
final class HUDController {
    enum Status: Equatable {
        case inactive
        case active(brightness: Bool)
        case needsAccessibility
        case unsupported
    }

    private(set) var status: Status = .inactive

    @ObservationIgnored private let tap = MediaKeyTap()
    @ObservationIgnored private let hud = HUDPanelController()

    private static let step: Float = 1.0 / 16.0
    private static let promptedKey = "ego.widget.hud.axPrompted"

    func start() {
        if case .active = status { return }
        // Prompt at most once per user enable; unrelated widget toggles and
        // relaunches re-check silently (and auto-recover once trust appears).
        let defaults = UserDefaults.standard
        let shouldPrompt = !defaults.bool(forKey: Self.promptedKey)
        guard MediaKeyTap.checkAccessibility(prompt: shouldPrompt) else {
            if shouldPrompt { defaults.set(true, forKey: Self.promptedKey) }
            status = .needsAccessibility
            return
        }
        defaults.removeObject(forKey: Self.promptedKey)

        // Live gates: never consume a key we cannot act on.
        tap.consumesVolume = { SystemVolume.isControllable }
        tap.consumesMute = { SystemVolume.hasMuteControl }
        tap.consumesBrightness = { SystemBrightness.controllable }
        tap.onKey = { [weak self] key in self?.handle(key) }
        status = tap.start() ? .active(brightness: SystemBrightness.controllable)
                             : .unsupported
    }

    func stop() {
        UserDefaults.standard.removeObject(forKey: Self.promptedKey)
        tap.stop()
        hud.teardown()
        status = .inactive
    }

    private func handle(_ key: MediaKeyTap.Key) {
        switch key {
        case .volumeUp, .volumeDown:
            let current = SystemVolume.volume() ?? 0
            let next = max(0, min(1, current + (key == .volumeUp ? Self.step : -Self.step)))
            SystemVolume.setVolume(next)
            if key == .volumeUp, SystemVolume.isMuted() {
                SystemVolume.setMuted(false)
            }
            hud.show(icon: next == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                     fraction: Double(next))

        case .mute:
            let muted = !SystemVolume.isMuted()
            SystemVolume.setMuted(muted)
            let volume = Double(SystemVolume.volume() ?? 0)
            hud.show(icon: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                     fraction: muted ? 0 : volume)

        case .brightnessUp, .brightnessDown:
            guard let current = SystemBrightness.brightness() else { return }
            let next = max(0, min(1, current + (key == .brightnessUp ? Self.step : -Self.step)))
            SystemBrightness.setBrightness(next)
            hud.show(icon: "sun.max.fill", fraction: Double(next))
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct HUDStatusTile: View {
    var controller: HUDController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch controller.status {
            case .active(let brightness):
                Chip(text: "HUD active", variant: .win)
                Text(brightness ? "Volume, mute & brightness keys"
                                : "Volume & mute keys (brightness unavailable)")
                    .font(Ego.font(10))
                    .foregroundStyle(Ego.textMute)
            case .needsAccessibility:
                Chip(text: "Needs Accessibility", variant: .loss)
                Text("Grant access, then toggle this module off and on")
                    .font(Ego.font(10))
                    .foregroundStyle(Ego.textMute)
                Button("Open Settings") { controller.openAccessibilitySettings() }
                    .buttonStyle(.egoSecondary)
            case .unsupported:
                Chip(text: "Unavailable", variant: .loss)
                Text("Media-key tap could not start")
                    .font(Ego.font(10))
                    .foregroundStyle(Ego.textMute)
            case .inactive:
                Chip(text: "Inactive", variant: .neutral)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
