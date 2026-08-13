import Foundation
import IOKit

struct AirPodsBatteryInfo: Equatable {
    var name: String
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var single: Int?      // one-cell headsets

    var isEmpty: Bool { left == nil && right == nil && single == nil }
}

/// Best-effort AirPods/headset battery from the IORegistry. Read on demand
/// (tile appearing, output-device change) — never polled. Returns nil when
/// nothing readable is connected; the UI simply hides the chips.
enum AirPodsBattery {
    static func read() -> AirPodsBatteryInfo? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleDeviceManagementHIDEventService")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }

            func intProp(_ key: String) -> Int? {
                guard let ref = IORegistryEntryCreateCFProperty(
                    entry, key as CFString, kCFAllocatorDefault, 0) else { return nil }
                return (ref.takeRetainedValue() as? NSNumber)?.intValue
            }
            func stringProp(_ key: String) -> String? {
                guard let ref = IORegistryEntryCreateCFProperty(
                    entry, key as CFString, kCFAllocatorDefault, 0) else { return nil }
                return ref.takeRetainedValue() as? String
            }

            let info = AirPodsBatteryInfo(
                name: stringProp("Product") ?? "Headphones",
                left: intProp("BatteryPercentLeft"),
                right: intProp("BatteryPercentRight"),
                caseLevel: intProp("BatteryPercentCase"),
                single: intProp("BatteryPercent"))
            if !info.isEmpty { return info }
        }
        return nil
    }
}
