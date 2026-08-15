import AppKit
import Observation

/// The recent-captures strip's model: what you've shot, newest first.
///
/// Reads the notch's own Pictures folder rather than keeping an index — the
/// folder IS the truth, so deleting a file in Finder can't leave a ghost tile.
@MainActor
@Observable
final class CaptureLibrary {
    private(set) var items: [URL] = []
    var selected: URL?

    private static let maxShown = 12

    func refresh() {
        let directory = CaptureExport.libraryDirectory
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []

        items = contents
            .filter { ["png", "jpg", "jpeg", "gif", "mov", "mp4"].contains($0.pathExtension.lowercased()) }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                return left > right
            }
            .prefix(Self.maxShown)
            .map { $0 }

        if let selected, !items.contains(selected) { self.selected = nil }
    }

    // MARK: - Actions on the selection

    func reveal() {
        guard let url = selected ?? items.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copy() {
        guard let url = selected ?? items.first else { return }
        CaptureExport.copyToPasteboard(fileAt: url)
    }

    func airDrop() {
        guard let url = selected ?? items.first else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [url])
    }

    /// Hand it to the Shelf, so it can be dragged into any app later.
    func sendToShelf() {
        guard let url = selected ?? items.first,
              let shelf = WidgetRegistry.widget(id: "shelf") as? ShelfWidget else { return }
        shelf.store.add(urls: [url])
        PanelUIState.shared.selectedTab = .shelf
    }

    func delete() {
        guard let url = selected ?? items.first else { return }
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        selected = nil
        refresh()
    }
}
