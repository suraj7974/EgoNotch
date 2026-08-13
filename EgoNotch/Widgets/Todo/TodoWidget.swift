import SwiftUI
import Observation

/// Phase 4 — simple local to-do quick list (add, check off, delete).
final class TodoWidget: NotchWidget {
    let id = "todo"
    let displayName = "To-Do"
    let icon = "checklist"
    let tileSize: WidgetTileSize = .wide
    let tab: NotchTab = .notes

    let store = TodoStore()

    func makeExpandedView() -> AnyView {
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
                Text("Nothing to do — add a task below")
                    .font(Ego.font(12))
                    .foregroundStyle(Ego.textMute.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.items) { item in
                        HStack(spacing: 8) {
                            Button {
                                withAnimation(Ego.Motion.spring()) { store.toggle(item) }
                            } label: {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(item.done ? Ego.win : Ego.textMute)
                            }
                            .buttonStyle(.plain)
                            Text(item.text)
                                .font(Ego.font(12))
                                .strikethrough(item.done, color: Ego.textMute)
                                .foregroundStyle(item.done ? Ego.textMute : Ego.text)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contextMenu {
                            Button("Delete") { store.delete(item) }
                        }
                    }
                }
            }

            TextField("Add a task…", text: $draft)
                .textFieldStyle(.plain)
                .font(Ego.font(12))
                .foregroundStyle(Ego.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Ego.surface2, in: RoundedRectangle(cornerRadius: 8))
                .onSubmit {
                    store.add(draft)
                    draft = ""
                }
        }
    }
}
