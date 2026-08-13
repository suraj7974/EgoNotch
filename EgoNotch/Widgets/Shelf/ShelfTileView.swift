import SwiftUI
import UniformTypeIdentifiers

/// Expanded shelf tray: horizontal strip of staged files (draggable out to
/// any app) + AirDrop / Copy / Reveal / Clear actions.
struct ShelfTileView: View {
    let widget: ShelfWidget
    @State private var dropTargeted = false

    var body: some View {
        let store = widget.store
        VStack(alignment: .leading, spacing: 10) {
            if store.items.isEmpty {
                emptyState
            } else {
                itemsRow(store)
                actions(store)
            }
        }
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            FileDropHandler.load(providers) { urls in
                widget.store.add(urls: urls)
            }
            return true
        }
        .overlay(
            RoundedRectangle(cornerRadius: Ego.cardRadius)
                .strokeBorder(Color.white.opacity(dropTargeted ? 0.35 : 0),
                              style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .padding(-6)
        )
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 18))
                .foregroundStyle(Ego.textMute)
            Text("Drop files on the notch to stage them here")
                .font(Ego.font(11))
                .foregroundStyle(Ego.textMute)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 52)
    }

    private func itemsRow(_ store: ShelfStore) -> some View {
        // No-scroll rule: first few items visible, the rest summarized.
        HStack(spacing: 10) {
            ForEach(store.items.prefix(5)) { item in
                ShelfItemCell(item: item, store: store)
            }
            if store.items.count > 5 {
                Text("+\(store.items.count - 5)")
                    .font(Ego.font(11, .semibold))
                    .egoDigits()
                    .foregroundStyle(Ego.textMute)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 60)
    }

    private func actions(_ store: ShelfStore) -> some View {
        HStack(spacing: 8) {
            shelfButton("AirDrop", symbol: "square.and.arrow.up") {
                let urls = store.items.map(\.url)
                NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
            }
            shelfButton("Copy", symbol: "doc.on.doc") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects(store.items.map { $0.url as NSURL })
            }
            shelfButton("Reveal", symbol: "magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting(store.items.map(\.url))
            }
            Spacer()
            shelfButton("Clear", symbol: "trash") {
                store.clear()
            }
        }
    }

    private func shelfButton(_ title: String, symbol: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(Ego.font(11, .medium))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.egoSecondary)
    }
}

private struct ShelfItemCell: View {
    let item: ShelfItem
    let store: ShelfStore
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 34, height: 34)
            Text(item.name)
                .font(Ego.font(9))
                .foregroundStyle(Ego.textMute)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: 64)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovered ? Ego.surface2 : .clear)
        )
        .onHover { hovered = $0 }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Button("Copy") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects([item.url as NSURL])
            }
            Divider()
            Button("Remove from Shelf") { store.remove(item) }
        }
        .help(item.url.path)
    }
}
