import SwiftUI
import Observation

/// Tabs of the expanded panel (Nucleus-style). Widgets declare which tab they
/// live on; a tab is shown only while at least one of its widgets is enabled,
/// so future cases are free to pre-declare — Focus/Clips/Today populate in
/// Phases 4–5. Order here is display order.
enum NotchTab: String, CaseIterable, Identifiable {
    case home
    case shelf
    case focus
    case notes
    case clips
    case today

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .shelf: "Shelf"
        case .focus: "Focus"
        case .notes: "Notes"
        case .clips: "Clips"
        case .today: "Today"
        }
    }

    var icon: String {
        switch self {
        case .home: "waveform"
        case .shelf: "tray.full"
        case .focus: "timer"
        case .notes: "note.text"
        case .clips: "doc.on.clipboard"
        case .today: "calendar"
        }
    }
}

/// Session UI state of the expanded panel (selected tab). Kept out of
/// NotchStateController so the core stays widget-agnostic.
@Observable
final class PanelUIState {
    static let shared = PanelUIState()

    var selectedTab: NotchTab = .home

    /// Tabs that currently have at least one enabled widget.
    var availableTabs: [NotchTab] {
        let populated = Set(WidgetRegistry.enabled.map(\.tab))
        return NotchTab.allCases.filter { populated.contains($0) }
    }

    /// Clamp the selection to something visible.
    func normalize() {
        let tabs = availableTabs
        if !tabs.contains(selectedTab) {
            selectedTab = tabs.first ?? .home
        }
    }
}
