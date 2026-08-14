import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Click, then press a combination. A LOCAL event monitor is enough — the
/// settings window is key while you're recording — so capturing a shortcut
/// needs no Accessibility permission.
struct HotKeyRecorder: View {
    @Binding var combination: GlobalHotKey.Combination

    @State private var recording = false
    @State private var monitor: Any?
    @State private var hovering = false

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press keys…" : combination.displayName)
                .font(Ego.font(11.5, .medium))
                .foregroundStyle(recording ? Ego.accent : Ego.text)
                .frame(minWidth: 74)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Color.white.opacity(hovering || recording ? 0.14 : 0.08))
                )
                .overlay(
                    Capsule().strokeBorder(recording ? Ego.accent : Ego.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return nil }   // swallow modifier-only events
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let modifiers = event.modifierFlags
                .intersection([.command, .option, .control, .shift]).rawValue
            let candidate = GlobalHotKey.Combination(keyCode: UInt32(event.keyCode),
                                                     modifiers: modifiers)
            // A shortcut with no modifier would swallow that key system-wide.
            guard candidate.isValid else { return nil }
            combination = candidate
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
