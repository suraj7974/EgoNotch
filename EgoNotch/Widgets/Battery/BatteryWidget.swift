import SwiftUI
import Observation
import IOKit.ps

/// Battery lives in the panel's TOP BAR (NotchNest style): an accurate
/// custom glyph that fills to the real percentage, green + bolt while
/// charging. A transient ⚡ pill still appears beside the notch when the
/// charger connects. IOKit notifications only — no polling.
final class BatteryWidget: NotchWidget {
    let id = "battery"
    let displayName = "Battery"
    let icon = "battery.100percent"
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

    func makeTopBarAccessory() -> AnyView? {
        AnyView(BatteryTopBarPill(monitor: monitor))
    }

    func makeClosedAccessory(for edge: NotchEdge) -> AnyView? {
        guard edge == .trailing else { return nil }
        return AnyView(ChargePill(monitor: monitor))
    }
}

@Observable
final class BatteryMonitor {
    private(set) var percent: Int?
    /// Actively pushing charge in. macOS stops charging at 100%, so this goes
    /// FALSE while the charger is still connected — never use it to answer
    /// "is it plugged in".
    private(set) var isCharging = false
    /// Running on the adapter, charging or already full.
    private(set) var isPluggedIn = false
    private(set) var timeRemaining: String?
    /// True briefly after the charger connects — drives the live pill.
    private(set) var showChargePulse = false

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var pulseTask: Task<Void, Never>?

    func start() {
        guard runLoopSource == nil else { return }
        refresh(pulseOnChargeBegin: false)
        let context = Unmanaged.passRetained(self).toOpaque()
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
        let wasPluggedIn = isPluggedIn
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
            // The adapter is what "plugged in" means — a full battery reports
            // IsCharging = false while still sitting on AC power.
            isPluggedIn = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let minutes = (info[isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey]
                as? NSNumber)?.intValue ?? -1
            timeRemaining = minutes > 0 ? String(format: "%d:%02d", minutes / 60, minutes % 60) : nil
            break
        }
        if pulseOnChargeBegin, isPluggedIn, !wasPluggedIn {
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

/// NotchNest-style top-bar battery: accurate fill, green + bolt on power.
struct BatteryTopBarPill: View {
    var monitor: BatteryMonitor

    var body: some View {
        if let percent = monitor.percent {
            HStack(spacing: 5) {
                BatteryGlyph(percent: percent, pluggedIn: monitor.isPluggedIn)
                Text("\(percent)%")
                    .font(Ego.font(11, .semibold))
                    .egoDigits()
                    .foregroundStyle(monitor.isPluggedIn ? Ego.win : Ego.text)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.07), in: Capsule())
            .help(helpText)
        }
    }

    private var helpText: String {
        if monitor.isCharging {
            return monitor.timeRemaining.map { "\($0) to full" } ?? "Charging"
        }
        if monitor.isPluggedIn { return "Charged — running on power adapter" }
        return monitor.timeRemaining.map { "\($0) left" } ?? "On battery"
    }
}

/// Custom battery outline whose inner fill matches the REAL percentage
/// (100% renders completely full — no SF-symbol approximation).
struct BatteryGlyph: View {
    let percent: Int
    var pluggedIn: Bool = false

    private var fillColor: Color {
        if pluggedIn { return Ego.win }        // green while on the adapter,
        return percent <= 20 ? Ego.loss : Ego.text   // charging or already full
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                    .frame(width: 22, height: 11)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(fillColor)
                    .frame(width: max(CGFloat(percent) / 100 * 18, 1.5), height: 7)
                    .padding(.leading, 2)
                if pluggedIn {
                    // The bolt stays for the whole time it's on the adapter —
                    // a full battery on power is still "plugged in".
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 22, alignment: .center)
                }
            }
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.5))
                .frame(width: 1.5, height: 4)
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
