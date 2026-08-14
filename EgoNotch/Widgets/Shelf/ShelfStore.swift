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
        sweepOrphanedCopies()
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
        discardStagedCopy(item.url)
        persist()
    }

    func clear() {
        items.forEach { discardStagedCopy($0.url) }
        items.removeAll()
        persist()
    }

    /// Removing a shelf entry deletes the file ONLY when it's a copy the app
    /// made for itself (a dropped screenshot staged into Application Support).
    /// Files dragged in from Finder are referenced where they live, so the
    /// shelf must never delete them — losing a real document because a tray
    /// was tidied is unforgivable.
    private func discardStagedCopy(_ url: URL) {
        guard FileDropHandler.isStaged(url) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Copies whose shelf entry no longer exists — a crash between staging the
    /// file and writing the bookmarks leaves those behind forever otherwise.
    func sweepOrphanedCopies() {
        let kept = Set(items.map(\.url.standardizedFileURL.path))
        for file in FileDropHandler.stagedFiles()
        where !kept.contains(file.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: file)
        }
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
