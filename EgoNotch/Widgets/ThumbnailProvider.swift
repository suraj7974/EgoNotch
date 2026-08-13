import AppKit
import QuickLookThumbnailing
import Observation

/// Real content previews for files (images, PDFs, videos…) via QuickLook,
/// generated once per (path, size) and cached in memory. Views call
/// `thumbnail(for:size:)` during body evaluation: a miss returns nil now and
/// re-renders when the generated image lands (@Observable cache).
@MainActor
@Observable
final class ThumbnailProvider {
    static let shared = ThumbnailProvider()

    private var cache: [String: NSImage] = [:]
    @ObservationIgnored private var pending: Set<String> = []
    @ObservationIgnored private var order: [String] = []

    private static let maxEntries = 64

    func thumbnail(for url: URL, size: CGFloat) -> NSImage? {
        let key = "\(url.path)|\(Int(size))"
        if let image = cache[key] { return image }
        guard !pending.contains(key) else { return nil }
        pending.insert(key)

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: 2,
            representationTypes: .all)   // falls back to the file icon
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let rep else {
                Task { @MainActor [weak self] in self?.pending.remove(key) }
                return
            }
            nonisolated(unsafe) let image = rep.nsImage
            Task { @MainActor [weak self] in
                self?.store(image, for: key)
            }
        }
        return nil
    }

    private func store(_ image: NSImage, for key: String) {
        pending.remove(key)
        cache[key] = image
        order.append(key)
        if order.count > Self.maxEntries, let oldest = order.first {
            order.removeFirst()
            cache.removeValue(forKey: oldest)
        }
    }
}
