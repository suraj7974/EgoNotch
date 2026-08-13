import SwiftUI
import UniformTypeIdentifiers

/// Expanded shelf tray: horizontal strip of staged files (draggable out to
/// any app) + AirDrop / Copy / Reveal / Clear actions.
struct ShelfTileView: View {
    let widget: ShelfWidget
    @State private var dropTargeted = false
    @State private var selectedID: UUID?

    var body: some View {
        let store = widget.store
        VStack(alignment: .leading, spacing: 10) {
            if store.items.isEmpty {
                emptyState
            } else if let selected = selectedItem {
                // Selection swaps the row for a big preview of that file.
                previewRow(selected)
                actions(store)
            } else {
                itemsRow(store)
                actions(store)
            }
        }
        .onChange(of: store.items.count) {
            if let selectedID, !store.items.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
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

    private var selectedItem: ShelfItem? {
        widget.store.items.first { $0.id == selectedID }
    }

    private func itemsRow(_ store: ShelfStore) -> some View {
        // No-scroll rule: first few items visible, the rest summarized.
        HStack(spacing: 10) {
            ForEach(store.items.prefix(5)) { item in
                ShelfItemCell(item: item, store: store,
                              selected: selectedID == item.id) {
                    selectedID = selectedID == item.id ? nil : item.id
                }
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

    /// Actions apply to the SELECTED file, or to everything when nothing is
    /// selected — click a file to target just that one.
    /// Large QuickLook preview of the selected file + a way back to the row.
    private func previewRow(_ item: ShelfItem) -> some View {
        HStack(spacing: 12) {
            Group {
                if let preview = ThumbnailProvider.shared.thumbnail(for: item.url, size: 120) {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(Ego.font(12, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Self.fileSize(item.url))
                    .font(Ego.font(10))
                    .egoDigits()
                    .foregroundStyle(Ego.textMute)
            }
            Spacer(minLength: 0)
            Button {
                selectedID = nil
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ego.textMute)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Back to files")
        }
        .frame(height: 60)
    }

    private static func fileSize(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func actions(_ store: ShelfStore) -> some View {
        let targets = selectedItem.map { [$0.url] } ?? store.items.map(\.url)
        return HStack(spacing: 8) {
            shelfButton("AirDrop", symbol: "square.and.arrow.up") {
                NSSharingService(named: .sendViaAirDrop)?.perform(withItems: targets)
            }
            shelfButton("Copy", symbol: "doc.on.doc") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects(targets.map { $0 as NSURL })
            }
            shelfButton("Reveal", symbol: "magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting(targets)
            }
            Spacer()
            if let selected = selectedItem {
                shelfButton("Remove", symbol: "minus.circle") {
                    store.remove(selected)
                    selectedID = nil
                }
            } else {
                shelfButton("Clear", symbol: "trash") {
                    store.clear()
                }
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
    let selected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(spacing: 4) {
            // Real content preview for images/PDFs/videos; icon otherwise.
            Group {
                if let thumb = ThumbnailProvider.shared.thumbnail(for: item.url, size: 40) {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(item.name)
                .font(Ego.font(9))
                .foregroundStyle(selected ? .white : Ego.textMute)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: 64)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.white.opacity(0.16)
                      : (hovered ? Ego.surface2 : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Ego.accentSoft.opacity(selected ? 0.7 : 0), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onTap)
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
