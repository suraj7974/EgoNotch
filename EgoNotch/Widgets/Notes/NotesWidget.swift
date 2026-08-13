import SwiftUI
import Observation

/// Phase 4 — "What's on your mind?" scratchpad. Line-based: checkbox lines
/// ("[ ] " / "[x] ") render with a toggle and strikethrough; everything else
/// is plain text. Persisted to Application Support as markdown-ish plain text.
final class NotesWidget: NotchWidget {
    let id = "notes"
    let displayName = "Quick Notes"
    let icon = "note.text"
    let tileSize: WidgetTileSize = .small
    let tab: NotchTab = .notes

    let store = NotesStore()

    /// Quit/disable must flush the pending debounced save — no data loss.
    func deactivate() { store.flush() }

    func makeExpandedView() -> AnyView? {
        AnyView(NotesTileView(store: store))
    }
}

struct NoteLine: Identifiable, Equatable {
    let id: UUID
    var text: String
    var isCheckbox: Bool
    var checked: Bool
}

@Observable
final class NotesStore {
    private(set) var lines: [NoteLine] = []

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("EgoNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("notes.md")
    }()

    init() {
        load()
    }

    func append(_ raw: String, asCheckbox: Bool) {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        lines.append(NoteLine(id: UUID(), text: text, isCheckbox: asCheckbox, checked: false))
        scheduleSave()
    }

    func toggle(_ line: NoteLine) {
        guard let i = lines.firstIndex(where: { $0.id == line.id }) else { return }
        lines[i].checked.toggle()
        scheduleSave()
    }

    func delete(_ line: NoteLine) {
        lines.removeAll { $0.id == line.id }
        scheduleSave()
    }

    func update(_ line: NoteLine, text: String) {
        guard let i = lines.firstIndex(where: { $0.id == line.id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            lines.remove(at: i)
        } else {
            lines[i].text = trimmed
        }
        scheduleSave()
    }

    // MARK: - Persistence

    private func load() {
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        lines = raw.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            let s = String(line)
            if s.hasPrefix("[x] ") {
                return NoteLine(id: UUID(), text: String(s.dropFirst(4)),
                                isCheckbox: true, checked: true)
            }
            if s.hasPrefix("[ ] ") {
                return NoteLine(id: UUID(), text: String(s.dropFirst(4)),
                                isCheckbox: true, checked: false)
            }
            return NoteLine(id: UUID(), text: s, isCheckbox: false, checked: false)
        }
    }

    /// Synchronously write anything the debounce is still holding.
    func flush() {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        saveNow()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
            self?.saveTask = nil
        }
    }

    private func saveNow() {
        let raw = lines.map { line in
            line.isCheckbox ? "[\(line.checked ? "x" : " ")] \(line.text)" : line.text
        }.joined(separator: "\n")
        try? raw.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

struct NotesTileView: View {
    var store: NotesStore
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.lines.isEmpty {
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    // No-scroll rule: latest lines visible, rest summarized.
                    ForEach(store.lines.suffix(4)) { line in
                        NoteLineRow(line: line, store: store)
                    }
                    if store.lines.count > 4 {
                        Text("+\(store.lines.count - 4) earlier")
                            .font(Ego.font(10))
                            .egoDigits()
                            .foregroundStyle(Ego.textMute)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                TextField("What's on your mind?", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Ego.font(13))
                    .foregroundStyle(Ego.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit { submit(asCheckbox: false) }
                Button {
                    submit(asCheckbox: true)
                } label: {
                    Image(systemName: "checklist")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Ego.text)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Add as checkbox")
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func submit(asCheckbox: Bool) {
        store.append(draft, asCheckbox: asCheckbox)
        draft = ""
    }
}

private struct NoteLineRow: View {
    let line: NoteLine
    let store: NotesStore

    var body: some View {
        HStack(spacing: 8) {
            if line.isCheckbox {
                Button {
                    withAnimation(Ego.Motion.spring()) { store.toggle(line) }
                } label: {
                    Image(systemName: line.checked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundStyle(line.checked ? Ego.win : Ego.textMute)
                }
                .buttonStyle(.plain)
            }
            Text(line.text)
                .font(Ego.font(13))
                .strikethrough(line.checked, color: Ego.textMute)
                .foregroundStyle(line.checked ? Ego.textMute : Ego.text)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .contextMenu {
            Button("Delete") { store.delete(line) }
        }
    }
}
