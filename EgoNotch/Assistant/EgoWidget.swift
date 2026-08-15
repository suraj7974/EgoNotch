import SwiftUI

/// Ego's adapter into the widget system.
///
/// Ego isn't a widget in spirit — it *drives* the other widgets rather than
/// sitting beside them — but registering as one buys three things the
/// assistant genuinely needs: the Settings module toggle, an idempotent
/// activate/deactivate lifecycle, and global reachability through
/// `WidgetRegistry.widget(id: "ego")`, which is exactly how `MeetingObserver`
/// already finds the recorder to exclude its camera.
final class EgoWidget: NotchWidget {
    let id = "ego"
    let displayName = "Ego (voice)"
    let icon = "waveform.circle.fill"
    /// Off until asked for: enabling it is what grants the microphone, and the
    /// app's standing policy is to never hold the mic uninvited.
    let defaultEnabled = false

    let assistant = EgoAssistant.shared

    func activate() { assistant.activate() }
    func deactivate() { assistant.deactivate() }

    /// No tile: Ego's whole interface is the listening strip and the voice.
    func makeExpandedView() -> AnyView? { nil }
}
