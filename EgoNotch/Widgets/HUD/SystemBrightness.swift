import CoreGraphics
import Foundation

/// Built-in display brightness via the private DisplayServices framework.
/// If the symbols are missing on this macOS build, `available` is false and
/// the HUD leaves brightness keys to the system (graceful fallback).
nonisolated enum SystemBrightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    nonisolated(unsafe) private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY)

    private static let getFn: GetFn? = handle.flatMap {
        dlsym($0, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) }
    }
    private static let setFn: SetFn? = handle.flatMap {
        dlsym($0, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) }
    }

    static var available: Bool { getFn != nil && setFn != nil }

    /// Brightness only applies to the BUILT-IN panel — never the primary
    /// external display (whose brightness DisplayServices cannot set).
    private static var builtinDisplayID: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// False in clamshell / when symbols are missing — keys then pass through.
    static var controllable: Bool { available && builtinDisplayID != nil }

    static func brightness() -> Float? {
        guard let getFn, let display = builtinDisplayID else { return nil }
        var value: Float = 0
        return getFn(display, &value) == 0 ? value : nil
    }

    static func setBrightness(_ value: Float) {
        guard let setFn, let display = builtinDisplayID else { return }
        _ = setFn(display, max(0, min(1, value)))
    }
}
