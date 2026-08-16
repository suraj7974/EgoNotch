import AppKit
import LocalAuthentication

/// Proving it's you, before changing who Ego listens to.
///
/// The voice gate is only as good as the switch that controls it: leaving
/// "Only my voice" one click away from anyone at an unlocked Mac would make
/// the whole feature decorative. `deviceOwnerAuthentication` means Touch ID
/// where there is one, and the login password everywhere else — so there is
/// no separate passcode for the user to invent and forget.
enum EgoAuth {
    /// True when the user proved who they are. False on cancel, on failure,
    /// and on a Mac with no authentication configured at all — the safe
    /// direction, since the caller is always about to *weaken* something.
    static func confirm(_ reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var problem: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &problem) else {
            EgoLog.trace("auth unavailable: \(problem?.localizedDescription ?? "unknown")")
            return false
        }
        // Whichever window asked, so it can be handed back afterwards: macOS
        // returns focus to the app that was frontmost *before* the panel
        // appeared, which is how a click in Settings ends up leaving the
        // terminal in front.
        let asker = NSApp.keyWindow
        defer {
            Task { @MainActor in
                NSApp.activate(ignoringOtherApps: true)
                asker?.makeKeyAndOrderFront(nil)
            }
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                    localizedReason: reason)
        } catch {
            EgoLog.trace("auth refused: \(error.localizedDescription)")
            return false
        }
    }
}
