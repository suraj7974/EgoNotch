import SwiftUI
import Observation
import IOKit.ps

/// Phase 5 — battery live activity. IOKit power-source notifications
/// (event-driven) drive a transient charge pill beside the notch when the
/// charger connects, plus a compact battery tile on Home.
final class BatteryWidget: NotchWidget {
    let id = "battery"
    let displayName = "Battery"
    let icon = "battery.75percent"
    let tileSize: WidgetTileSize = .small
    let tab: NotchTab = .home

    let monitor = BatteryMonitor()
    private var active = false

    func activate() {
        guard !active else { return }
        active = true
        monitor.start()
    }

    func deactivate() {
        guard active else { return }
        active = false
        monitor.stop()
    }

    func makeClosedAccessory(for edge: NotchEdge) -> AnyView? {
        guard edge == .trailing else { return nil }
        return AnyView(ChargePill(monitor: monitor))
    }

    func makeExpandedView() -> AnyView {
        AnyView(BatteryTileView(monitor: monitor))
    }
}

@Observable
final class BatteryMonitor {
    private(set) var percent: Int?
    private(set) var isCharging = false
    private(set) var timeRemaining: String?
    /// True briefly after the charger connects — drives the live pill.
    private(set) var showChargePulse = false

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var pulseTask: Task<Void, Never>?

    func start() {
        guard runLoopSource == nil else { return }
        refresh(pulseOnChargeBegin: false)
        let context = Unmanaged.passRetained(self).toOpaque()
        // C callback → hop to the main actor; IOKit calls on the main run loop.
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.refresh(pulseOnChargeBegin: true)
            }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        } else {
            Unmanaged<BatteryMonitor>.fromOpaque(context).release()
        }
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            Unmanaged.passUnretained(self).release()   // balance passRetained in start()
        }
        runLoopSource = nil
        pulseTask?.cancel()
        pulseTask = nil
        showChargePulse = false
    }

    private func refresh(pulseOnChargeBegin: Bool) {
        let wasCharging = isCharging
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue()
                as? [CFTypeRef] else { return }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
                  let capacity = (info[kIOPSCurrentCapacityKey] as? NSNumber)?.intValue,
                  let max = (info[kIOPSMaxCapacityKey] as? NSNumber)?.intValue, max > 0
            else { continue }
            percent = capacity * 100 / max
            isCharging = (info[kIOPSIsChargingKey] as? Bool) ?? false
            let minutes = (info[isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey]
                as? NSNumber)?.intValue ?? -1
            timeRemaining = minutes > 0 ? String(format: "%d:%02d", minutes / 60, minutes % 60) : nil
            break
        }
        if pulseOnChargeBegin, isCharging, !wasCharging {
            pulse()
        }
    }

    private func pulse() {
        showChargePulse = true
        pulseTask?.cancel()
        pulseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.showChargePulse = false
        }
    }
}

/// Transient green ⚡ pill beside the notch when the charger connects.
private struct ChargePill: View {
    var monitor: BatteryMonitor

    var body: some View {
        if monitor.showChargePulse, let percent = monitor.percent {
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("\(percent)%")
                    .font(Ego.font(10, .semibold))
                    .egoDigits()
            }
            .foregroundStyle(Ego.win)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

struct BatteryTileView: View {
    var monitor: BatteryMonitor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: monitor.isCharging
                  ? "battery.100percent.bolt" : "battery.75percent")
                .font(.system(size: 20))
                .foregroundStyle((monitor.percent ?? 100) <= 20 && !monitor.isCharging
                                 ? Ego.loss : Ego.win)
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.percent.map { "\($0)%" } ?? "—")
                    .font(Ego.font(18, .bold))
                    .egoDigits()
                    .foregroundStyle(Ego.text)
                Text(monitor.isCharging
                     ? (monitor.timeRemaining.map { "\($0) to full" } ?? "Charging")
                     : (monitor.timeRemaining.map { "\($0) left" } ?? "On battery"))
                    .font(Ego.font(10))
                    .egoDigits()
                    .foregroundStyle(Ego.textMute)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
