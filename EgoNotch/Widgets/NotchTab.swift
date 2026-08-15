import SwiftUI
import Observation

/// Tabs of the expanded panel. Widgets declare which tab they live on; a tab
/// is shown only while at least one of its widgets is enabled. Order here is
/// display order.
enum NotchTab: String, CaseIterable, Identifiable {
    case home
    case shelf
    case focus
    case notes
    case terminal
    case recorder
    case games

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .shelf: "Shelf"
        case .focus: "Focus"
        case .notes: "Notes"
        case .terminal: "Terminal"
        case .recorder: "Recorder"
        case .games: "Games"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .shelf: "tray.full.fill"
        case .focus: "timer"
        case .notes: "note.text"
        case .terminal: "terminal.fill"
        case .recorder: "video.fill"
        case .games: "gamecontroller.fill"
        }
    }
}

/// Session UI state of the expanded panel (selected tab). Kept out of
/// NotchStateController so the core stays widget-agnostic.
@Observable
final class PanelUIState {
    static let shared = PanelUIState()

    var selectedTab: NotchTab = .home

    /// Tabs that currently have at least one enabled widget with content.
    var availableTabs: [NotchTab] {
        let populated = Set(WidgetRegistry.enabled
            .filter { $0.makeExpandedView() != nil || $0.makeCompactView() != nil }
            .map(\.tab))
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
