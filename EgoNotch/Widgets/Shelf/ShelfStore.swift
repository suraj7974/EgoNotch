import Foundation
import Observation

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let url: URL

    var name: String { url.lastPathComponent }
}

/// The shelf's contents, persisted as file BOOKMARKS (not copies) so items
/// survive restarts and follow moved/renamed files. Stale/unresolvable
/// bookmarks are silently dropped on restore.
@Observable
final class ShelfStore {
    private(set) var items: [ShelfItem] = []

    static let maxItems = 24

    @ObservationIgnored private let persistURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("EgoNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("shelf.bookmarks")
    }()

    init() {
        restore()
    }

    /// Returns true if anything new landed on the shelf.
    @discardableResult
    func add(urls: [URL]) -> Bool {
        var added = false
        for url in urls {
            let standardized = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardized.path) else { continue }
            guard !items.contains(where: { $0.url.standardizedFileURL == standardized }) else { continue }
            items.insert(ShelfItem(id: UUID(), url: standardized), at: 0)
            added = true
        }
        if items.count > Self.maxItems {
            items.removeLast(items.count - Self.maxItems)
        }
        if added { persist() }
        return added
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    // MARK: - Persistence (bookmarks, not copies)

    private func persist() {
        let bookmarks = items.compactMap { try? $0.url.bookmarkData(options: .minimalBookmark) }
        let data = try? NSKeyedArchiver.archivedData(withRootObject: bookmarks,
                                                     requiringSecureCoding: true)
        try? data?.write(to: persistURL)
    }

    private func restore() {
        guard let data = try? Data(contentsOf: persistURL),
              let bookmarks = try? NSKeyedUnarchiver.unarchivedObject(
                  ofClasses: [NSArray.self, NSData.self], from: data) as? [Data]
        else { return }
        // .withoutUI/.withoutMounting: resolution runs on the main actor at
        // launch — an unplugged network volume must not stall or show dialogs.
        var needsRewrite = false
        items = bookmarks.compactMap { bookmark in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark,
                                     options: [.withoutUI, .withoutMounting],
                                     bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path) else {
                needsRewrite = true      // drop dead entries from disk too
                return nil
            }
            if stale { needsRewrite = true }   // refresh both bookmark identity legs
            return ShelfItem(id: UUID(), url: url)
        }
        if needsRewrite { persist() }
    }
}
