import SwiftUI

/// Phase 3 — file shelf. Drag files onto the notch to stage them; drag them
/// out to any app, or AirDrop / copy / reveal / clear from the tile.
final class ShelfWidget: NotchWidget {
    let id = "shelf"
    let displayName = "Shelf"
    let icon = "tray.full"
    let tileSize: WidgetTileSize = .wide
    let tab: NotchTab = .shelf
    let acceptsDroppedFiles = true

    let store = ShelfStore()

    func activate() {
        // Debug: EGO_DEBUG_SHELF_ADD=/path/a:/path/b seeds the shelf.
        if let paths = ProcessInfo.processInfo.environment["EGO_DEBUG_SHELF_ADD"] {
            store.add(urls: paths.split(separator: ":").map {
                URL(fileURLWithPath: String($0))
            })
        }
    }

    func handleDroppedFiles(_ urls: [URL]) -> Bool {
        store.add(urls: urls)
    }

    func makeClosedAccessory(for edge: NotchEdge) -> AnyView? {
        guard edge == .trailing else { return nil }
        return AnyView(ShelfCountBadge(store: store))
    }

    func makeExpandedView() -> AnyView {
        AnyView(ShelfTileView(widget: self))
    }
}

/// Slim closed-state indicator: tray + count, only when the shelf holds items.
private struct ShelfCountBadge: View {
    var store: ShelfStore

    var body: some View {
        if !store.items.isEmpty {
            HStack(spacing: 3) {
                Image(systemName: "tray.fill")
                    .font(.system(size: 8))
                Text("\(store.items.count)")
                    .font(Ego.font(9, .medium))
                    .egoDigits()
            }
            .foregroundStyle(Ego.textMute)
        }
    }
}
