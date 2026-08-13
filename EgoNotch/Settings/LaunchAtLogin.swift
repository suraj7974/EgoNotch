import AppKit
import ServiceManagement

/// SMAppService.mainApp wrapper. The service's own status is the single
/// source of truth — never mirror it in UserDefaults.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// True when running from a build directory: registering would pin the
    /// login item to a path that goes stale on the next clean build.
    static var runningOutsideApplications: Bool {
        !Bundle.main.bundlePath.hasPrefix("/Applications")
    }

    /// Returns the EFFECTIVE state after the attempt — bind toggles to this
    /// result, not the wish (register can fail or land in .requiresApproval).
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LaunchAtLogin: \(error)")
        }
        return isEnabled
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
