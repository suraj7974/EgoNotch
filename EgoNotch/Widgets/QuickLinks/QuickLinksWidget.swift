import SwiftUI
import Observation

/// Home-strip quick links (NotchNest's ChatGPT shortcut, generalized):
/// circular site buttons that open in the DEFAULT browser, plus an inline
/// add-a-site form. ChatGPT is seeded by default; right-click removes.
final class QuickLinksWidget: NotchWidget {
    let id = "quicklinks"
    let displayName = "Quick Links"
    let icon = "link"
    let tab: NotchTab = .home

    let store = QuickLinksStore()

    func makeCompactView() -> AnyView? {
        AnyView(QuickLinksCompactView(store: store))
    }
}

struct QuickLink: Identifiable, Equatable, Codable {
    var id = UUID()
    var name: String
    var urlString: String

    var url: URL? { URL(string: urlString) }
    var monogram: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
}

@Observable
final class QuickLinksStore {
    private(set) var links: [QuickLink] = []

    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let key = "quicklinks.sites"

    init() {
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([QuickLink].self, from: data) {
            links = decoded
        } else {
            links = [QuickLink(name: "ChatGPT", urlString: "https://chatgpt.com")]
            save()
        }
    }

    func add(name: String, urlString: String) {
        var raw = urlString.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        if !raw.contains("://") { raw = "https://" + raw }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: raw), url.host() != nil else { return }
        links.append(QuickLink(name: trimmedName.isEmpty ? (url.host() ?? raw) : trimmedName,
                               urlString: raw))
        save()
    }

    func remove(_ link: QuickLink) {
        links.removeAll { $0.id == link.id }
        save()
    }

    func open(_ link: QuickLink) {
        guard let url = link.url else { return }
        NSWorkspace.shared.open(url)   // default browser
    }

    private func save() {
        if let data = try? JSONEncoder().encode(links) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

struct QuickLinksCompactView: View {
    var store: QuickLinksStore
    @State private var adding = false
    @State private var draftName = ""
    @State private var draftURL = ""

    private let columns = [GridItem(.adaptive(minimum: 40, maximum: 44), spacing: 8)]

    var body: some View {
        if adding {
            addForm
        } else {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(store.links) { link in
                        LinkButton(link: link, store: store)
                    }
                    Button {
                        adding = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Ego.textMute)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.08), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Add a site")
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            field("Name (optional)", text: $draftName)
            field("example.com", text: $draftURL)
            HStack(spacing: 6) {
                Button("Add") {
                    store.add(name: draftName, urlString: draftURL)
                    draftName = ""
                    draftURL = ""
                    adding = false
                }
                .buttonStyle(.egoPrimary)
                Button("Cancel") {
                    adding = false
                }
                .buttonStyle(.egoSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(Ego.font(12))
            .foregroundStyle(Ego.text)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LinkButton: View {
    let link: QuickLink
    let store: QuickLinksStore
    @State private var hovered = false

    var body: some View {
        Button {
            store.open(link)
        } label: {
            Text(link.monogram)
                .font(Ego.font(15, .bold))
                .foregroundStyle(Ego.text)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(hovered ? 0.2 : 0.1), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Remove") { store.remove(link) }
        }
        .help(link.name)
    }
}
