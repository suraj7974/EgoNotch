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
    /// host → favicon; observable so buttons refresh when a fetch lands.
    private(set) var favicons: [String: NSImage] = [:]

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var fetching: Set<String> = []
    private static let key = "quicklinks.sites"

    private static let faviconDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("EgoNotch/favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

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

    // MARK: - Favicons (fetched once per host, cached on disk)

    func favicon(for link: QuickLink) -> NSImage? {
        guard let host = link.url?.host() else { return nil }
        if let cached = favicons[host] { return cached }
        let file = Self.faviconDir.appendingPathComponent("\(host).png")
        if let image = NSImage(contentsOf: file) {
            favicons[host] = image
            return image
        }
        fetchFavicon(host: host, to: file)
        return nil
    }

    private func fetchFavicon(host: String, to file: URL) {
        guard !fetching.contains(host) else { return }
        fetching.insert(host)
        Task { [weak self] in
            guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64"),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data) else { return }
            try? data.write(to: file)
            self?.favicons[host] = image
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
            let visible = Array(store.links.prefix(11))
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(visible) { link in
                        LinkButton(link: link, store: store)
                    }
                    Button {
                        adding = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Ego.textMute)
                            .frame(width: 40, height: 40)
                            .background(Color.black, in: Circle())
                            .overlay(Circle().strokeBorder(Ego.border, lineWidth: 1))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Add a site")
                }
                if store.links.count > visible.count {
                    Text("+\(store.links.count - visible.count) more")
                        .font(Ego.font(10))
                        .egoDigits()
                        .foregroundStyle(Ego.textMute)
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
        EgoTextField(placeholder: placeholder, text: text)
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
            Group {
                if let icon = store.favicon(for: link) {
                    // Bare logo — no chrome around it (user preference).
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    Text(link.monogram)
                        .font(Ego.font(15, .bold))
                        .foregroundStyle(Ego.text)
                        .frame(width: 34, height: 34)
                        .background(Color.black, in: Circle())
                        .overlay(Circle().strokeBorder(Ego.border, lineWidth: 1))
                }
            }
            .frame(width: 40, height: 40)
            .scaleEffect(hovered ? 1.15 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over in
            withAnimation(Ego.Motion.spring()) { hovered = over }
        }
        .contextMenu {
            Button("Remove") { store.remove(link) }
        }
        .help(link.name)
    }
}
