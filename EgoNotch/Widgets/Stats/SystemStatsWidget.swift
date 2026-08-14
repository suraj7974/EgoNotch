import SwiftUI
import Observation
import IOKit.ps

/// Home-tab extra (Nucleus-inspired): CPU / RAM / battery rings.
/// Samples ONLY while the tile is visible (TimelineView-driven, 2s cadence);
/// zero cost while closed.
final class SystemStatsWidget: NotchWidget {
    let id = "stats"
    let displayName = "System"
    let icon = "gauge.with.dots.needle.50percent"
    let tileSize: WidgetTileSize = .small
    let tab: NotchTab = .home

    let sampler = SystemSampler()

    /// Compact rows don't need a full quarter of the strip — cap the column
    /// so the slack goes to the widgets that can use it.
    var compactMaxWidth: CGFloat? { 146 }

    var companionAppName: String? { "Activity Monitor" }
    func openCompanionApp() { AppLauncher.open(bundleID: "com.apple.ActivityMonitor") }

    func makeCompactView() -> AnyView? {
        AnyView(SystemStatsTileView(widget: self))
    }
}

struct SystemSample {
    var cpuPercent = 0.0
    var ramPercent = 0.0
    var batteryPercent: Double?
    var charging = false
    var diskPercent = 0.0
    var diskFreeText = ""
}

final class SystemSampler {
    private var previousTicks: (idle: UInt64, total: UInt64)?

    func sample() -> SystemSample {
        var out = SystemSample()
        out.cpuPercent = sampleCPU()
        out.ramPercent = sampleRAM()
        let battery = sampleBattery()
        out.batteryPercent = battery.0
        out.charging = battery.1
        let disk = sampleDisk()
        out.diskPercent = disk.0
        out.diskFreeText = disk.1
        return out
    }

    /// Boot volume usage — cheap enough for the 2s cadence.
    private func sampleDisk() -> (Double, String) {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(
            forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity, total > 0 else { return (0, "") }
        let free = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        let used = Double(Int64(total) - free) / Double(total) * 100
        return (min(max(used, 0), 100),
                ByteCountFormatter.string(fromByteCount: free, countStyle: .file) + " free")
    }

    private func sampleCPU() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size
            / MemoryLayout<integer_t>.size)
        var load = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let user = UInt64(load.cpu_ticks.0), system = UInt64(load.cpu_ticks.1)
        let idle = UInt64(load.cpu_ticks.2), nice = UInt64(load.cpu_ticks.3)
        let total = user + system + idle + nice
        defer { previousTicks = (idle, total) }
        guard let prev = previousTicks, total > prev.total else { return 0 }
        let dTotal = Double(total - prev.total)
        let dIdle = Double(idle - prev.idle)
        return dTotal > 0 ? max(0, min(100, (1 - dIdle / dTotal) * 100)) : 0
    }

    private func sampleRAM() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
            / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        var pageSizeOut: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSizeOut)
        let pageSize = Double(pageSizeOut)
        let used = Double(stats.active_count &+ stats.wire_count &+ stats.compressor_page_count)
            * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        return total > 0 ? min(100, used / total * 100) : 0
    }

    private func sampleBattery() -> (Double?, Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue()
                as? [CFTypeRef] else { return (nil, false) }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
                  let capacity = info[kIOPSCurrentCapacityKey] as? Double,
                  let max = info[kIOPSMaxCapacityKey] as? Double, max > 0 else { continue }
            let charging = (info[kIOPSIsChargingKey] as? Bool) ?? false
            return (capacity / max * 100, charging)
        }
        return (nil, false)
    }
}

struct SystemStatsTileView: View {
    let widget: SystemStatsWidget
    @State private var sample = SystemSample()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { context in
            // Vertical rows: ring on the left, name and detail to its right.
            VStack(alignment: .leading, spacing: 7) {
                StatRow(label: "CPU", percent: sample.cpuPercent,
                        detail: "\(Int(sample.cpuPercent.rounded()))% used",
                        color: Ego.accentSoft)
                StatRow(label: "RAM", percent: sample.ramPercent,
                        detail: "\(Int(sample.ramPercent.rounded()))% used",
                        color: Color(hex: "BF5AF2"))
                StatRow(label: "Disk", percent: sample.diskPercent,
                        detail: sample.diskFreeText,
                        color: Color(hex: "FF9F0A"))
                if let battery = sample.batteryPercent {
                    StatRow(label: sample.charging ? "Charging" : "Battery",
                            percent: battery,
                            detail: "\(Int(battery.rounded()))%",
                            color: battery <= 20 && !sample.charging ? Ego.loss : Ego.win)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onChange(of: context.date, initial: true) {
                sample = widget.sampler.sample()
            }
        }
    }
}

private struct StatRow: View {
    let label: String
    let percent: Double
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.02, percent / 100))
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(percent.rounded()))")
                    .font(Ego.font(10, .bold))
                    .egoDigits()
                    .foregroundStyle(Ego.text)
            }
            .frame(width: 28, height: 28)
            .animation(Ego.Motion.spring(), value: percent)

            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(Ego.font(11.5, .semibold))
                    .foregroundStyle(.white)
                if !detail.isEmpty {
                    Text(detail)
                        .font(Ego.font(9.5))
                        .egoDigits()
                        .foregroundStyle(Ego.textMute)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
