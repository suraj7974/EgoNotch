import SwiftUI
import Observation

/// Phase 5 — clipboard history (Clips tab). Last 25 items, text + images,
/// click to copy back. History is IN-MEMORY ONLY — clipboard contents are
/// never written to disk (privacy). NSPasteboard has no change notification,
/// so a lightweight changeCount poll (1.5s, integer compare) runs while the
/// widget is enabled — the one sanctioned poll in the app.
final class ClipboardWidget: NotchWidget {
    let id = "clipboard"
    let displayName = "Clips"
    let icon = "doc.on.clipboard"
    let tileSize: WidgetTileSize = .small
    let tab: NotchTab = .shelf

    let store = ClipboardStore()
    private var active = false

    func activate() {
        guard !active else { return }
        active = true
        store.start()
    }

    func deactivate() {
        guard active else { return }
        active = false
        store.stop()
        store.clear()   // a disabled widget must not retain clipboard data
    }

    func makeExpandedView() -> AnyView? {
        AnyView(ClipboardTileView(store: store))
    }
}

struct ClipItem: Identifiable, Equatable {
    enum Content: Equatable {
        case text(String)
        /// Small thumbnail for display + the original compressed bytes for
        /// copy-back — never 25 decoded full-res images in memory.
        case image(thumbnail: NSImage, data: Data, type: NSPasteboard.PasteboardType)
    }

    let id = UUID()
    let content: Content
    let date: Date
}

@Observable
final class ClipboardStore {
    private(set) var items: [ClipItem] = []

    static let maxItems = 25

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastChangeCount = NSPasteboard.general.changeCount

    func start() {
        guard pollTask == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5), tolerance: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.checkPasteboard()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func clear() {
        items.removeAll()
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
    }

    /// Copy an item back. Bumps lastChangeCount past our own write so the
    /// poll doesn't re-capture it as a new entry.
    func copy(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.content {
        case .text(let string):
            pb.setString(string, forType: .string)
        case .image(_, let data, let type):
            pb.setData(data, forType: type)
        }
        lastChangeCount = pb.changeCount
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // Skip transient/concealed items (password managers mark these).
        if pb.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true {
            return
        }

        let content: ClipItem.Content?
        if let string = pb.string(forType: .string),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content = .text(string)
        } else if let type = pb.availableType(from: [.png, .tiff]),
                  let raw = pb.data(forType: type),
                  let image = NSImage(data: raw),
                  let (data, storedType) = Self.cappedImageData(raw, type: type, image: image) {
            // In-band image data only (screenshots, editor copies) — never
            // dereference file-URL pasteboards (Finder/Shelf copies).
            content = .image(thumbnail: Self.thumbnail(from: image),
                             data: data, type: storedType)
        } else {
            content = nil
        }
        guard let content else { return }

        if case .text(let new) = content,
           case .text(let last)? = items.first?.content, new == last {
            return   // unchanged repeat
        }
        items.insert(ClipItem(content: content, date: Date()), at: 0)
        if items.count > Self.maxItems {
            items.removeLast(items.count - Self.maxItems)
        }
    }

    /// Uncompressed TIFF copies can be 30–80MB each; 25 of them would wreck
    /// the RAM budget. Cap stored bytes: re-encode as PNG, downscaling first
    /// when PNG alone isn't enough.
    private static let maxStoredImageBytes = 2 * 1024 * 1024

    private static func cappedImageData(
        _ raw: Data, type: NSPasteboard.PasteboardType, image: NSImage
    ) -> (Data, NSPasteboard.PasteboardType)? {
        guard raw.count > maxStoredImageBytes else { return (raw, type) }
        if let rep = NSBitmapImageRep(data: raw),
           let png = rep.representation(using: .png, properties: [:]),
           png.count <= maxStoredImageBytes {
            return (png, .png)
        }
        let scaled = thumbnail(from: image, maxDimension: 2048)
        guard let tiff = scaled.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return (png, .png)
    }

    private static func thumbnail(from image: NSImage, maxDimension: CGFloat = 320) -> NSImage {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height, 1))
        guard scale < 1 else { return image }
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let thumb = NSImage(size: newSize)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: .zero, operation: .copy, fraction: 1)
        thumb.unlockFocus()
        return thumb
    }
}

struct ClipboardTileView: View {
    var store: ClipboardStore
    @State private var copiedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 16))
                        .foregroundStyle(Ego.textMute)
                    Text("Copy something — it shows up here")
                        .font(Ego.font(11))
                        .foregroundStyle(Ego.textMute)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 48)
            } else {
                // One click on any row copies THAT item — no selection step.
                HStack {
                    Text("\(store.items.count) item\(store.items.count == 1 ? "" : "s") — click to copy")
                        .font(Ego.font(10))
                        .egoDigits()
                        .foregroundStyle(Ego.textMute)
                    Spacer()
                    Button("Clear") { store.clear() }
                        .buttonStyle(.plain)
                        .font(Ego.font(10))
                        .foregroundStyle(Ego.textMute)
                }
                VStack(spacing: 4) {
                    // No-scroll rule: newest few visible; count above tells the rest.
                    ForEach(store.items.prefix(3)) { item in
                        ClipRow(item: item, copied: copiedID == item.id) {
                            store.copy(item)
                            copiedID = item.id
                            Task {
                                try? await Task.sleep(for: .seconds(1.2))
                                if copiedID == item.id { copiedID = nil }
                            }
                        } onRemove: {
                            store.remove(item)
                        }
                    }
                }
            }
        }
    }
}

private struct ClipRow: View {
    let item: ClipItem
    let copied: Bool
    let action: () -> Void
    let onRemove: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                switch item.content {
                case .text(let string):
                    Text(string.replacingOccurrences(of: "\n", with: " "))
                        .font(Ego.font(11))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                case .image(let thumbnail, _, _):
                    // Hovering opens the image up so you can see what it is.
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: hovered ? .fit : .fill)
                        .frame(width: hovered ? 74 : 40,
                               height: hovered ? 44 : 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .animation(Ego.Motion.spring(), value: hovered)
                    Text("Image")
                        .font(Ego.font(11))
                        .foregroundStyle(Ego.textMute)
                }
                Spacer(minLength: 0)
                if copied {
                    Chip(text: "Copied", variant: .win)
                } else {
                    Text(item.date, format: .dateTime.hour().minute())
                        .font(Ego.font(9))
                        .egoDigits()
                        .foregroundStyle(Ego.textMute.opacity(0.7))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(hovered ? Ego.surface2 : Ego.surface2.opacity(0.5),
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Remove") { onRemove() }
        }
        .help("Click to copy")
    }
}
