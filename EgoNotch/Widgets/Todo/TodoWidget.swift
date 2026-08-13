import SwiftUI
import Observation

/// Phase 4 — simple local to-do quick list (add, check off, delete).
final class TodoWidget: NotchWidget {
    let id = "todo"
    let displayName = "To-Do"
    let icon = "checklist"
    let tileSize: WidgetTileSize = .small
    let tab: NotchTab = .notes

    let store = TodoStore()

    func makeExpandedView() -> AnyView? {
        AnyView(TodoTileView(store: store))
    }

    func makeClosedAccessory(for edge: NotchEdge) -> AnyView? {
        guard edge == .trailing else { return nil }
        return AnyView(TodoBadge(store: store))
    }
}

struct TodoItem: Identifiable, Equatable, Codable {
    var id = UUID()
    var text: String
    var done = false
}

@Observable
final class TodoStore {
    private(set) var items: [TodoItem] = []

    var openCount: Int { items.filter { !$0.done }.count }

    @ObservationIgnored private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("EgoNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("todo.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) {
            items = decoded
        }
    }

    func add(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        items.append(TodoItem(text: text))
        save()
    }

    func toggle(_ item: TodoItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].done.toggle()
        save()
    }

    func delete(_ item: TodoItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearDone() {
        items.removeAll { $0.done }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

/// Open-item count beside the notch while tasks remain.
private struct TodoBadge: View {
    var store: TodoStore

    var body: some View {
        if store.openCount > 0 {
            HStack(spacing: 3) {
                Image(systemName: "checklist")
                    .font(.system(size: 8))
                Text("\(store.openCount)")
                    .font(Ego.font(9, .medium))
                    .egoDigits()
            }
            .foregroundStyle(Ego.textMute)
        }
    }
}

struct TodoTileView: View {
    var store: TodoStore
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if store.openCount > 0 {
                    Chip(text: "\(store.openCount) open", variant: .accent)
                }
                Spacer()
                if store.items.contains(where: \.done) {
                    Button("Clear done") { store.clearDone() }
                        .buttonStyle(.plain)
                        .font(Ego.font(10))
                        .foregroundStyle(Ego.textMute)
                }
            }

            if store.items.isEmpty {
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    // No-scroll rule: open items first, few visible.
                    ForEach(store.items.sorted { !$0.done && $1.done }.prefix(4)) { item in
                        HStack(spacing: 8) {
                            Button {
                                withAnimation(Ego.Motion.spring()) { store.toggle(item) }
                            } label: {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(item.done ? Ego.win : Ego.textMute)
                            }
                            .buttonStyle(.plain)
                            Text(item.text)
                                .font(Ego.font(13))
                                .strikethrough(item.done, color: Ego.textMute)
                                .foregroundStyle(item.done ? Ego.textMute : .white)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Button {
                                store.delete(item)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Ego.textMute.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                            .help("Delete")
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Delete") { store.delete(item) }
                        }
                    }
                    if store.items.count > 4 {
                        Text("+\(store.items.count - 4) more")
                            .font(Ego.font(10))
                            .egoDigits()
                            .foregroundStyle(Ego.textMute)
                    }
                }
                Spacer(minLength: 0)
            }

            EgoTextField(placeholder: "Add a task…", text: $draft) {
                store.add(draft)
                draft = ""
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
