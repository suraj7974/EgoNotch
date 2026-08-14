import AppKit
import UniformTypeIdentifiers

/// Turns dropped NSItemProviders into real file URLs.
///
/// Three shapes have to work, not just the easy one:
///  1. a real file being dragged from Finder      → its URL
///  2. macOS's floating screenshot thumbnail      → a PROMISED file that
///     hasn't been written to disk yet
///  3. an image dragged out of an app/browser     → raw data, no file at all
///
/// (2) and (3) are staged into Application Support so the shelf has
/// something permanent to bookmark.
enum FileDropHandler {
    /// Everything the notch will accept as a drop.
    static let acceptedTypes: [UTType] = [.fileURL, .image, .png, .tiff, .jpeg, .pdf]

    static func load(_ providers: [NSItemProvider],
                     completion: @escaping ([URL]) -> Void) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await fileURL(from: provider) {
                    urls.append(url)
                } else if let url = await staged(from: provider) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty { completion(urls) }
        }
    }

    // MARK: - Real files

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        else { return nil }
        let url: URL? = await withCheckedContinuation { cont in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                cont.resume(returning: url)
            }
        }
        guard let url, url.isFileURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    // MARK: - Promised / in-memory content

    /// Promised files (the screenshot thumbnail) and raw image data both land
    /// here and are copied into our own staging folder.
    private static func staged(from provider: NSItemProvider) async -> URL? {
        for type in [UTType.png, .jpeg, .tiff, .pdf, .image] {
            guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { continue }

            // A promised file gives a temp URL that is deleted the moment the
            // completion handler returns — copy inside the callback.
            if let url: URL = await withCheckedContinuation({ cont in
                _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                    guard let url else { cont.resume(returning: nil); return }
                    let dest = stagingURL(named: url.lastPathComponent)
                    try? FileManager.default.copyItem(at: url, to: dest)
                    cont.resume(returning: FileManager.default.fileExists(atPath: dest.path)
                                ? dest : nil)
                }
            }) {
                return url
            }

            // Otherwise take the bytes and write them ourselves.
            let data: Data? = await withCheckedContinuation { cont in
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    cont.resume(returning: data)
                }
            }
            if let data, !data.isEmpty {
                let ext = type.preferredFilenameExtension ?? "png"
                let dest = stagingURL(named: "Dropped Image.\(ext)")
                if (try? data.write(to: dest)) != nil { return dest }
            }
        }
        return nil
    }

    // MARK: - Staging

    /// Files we copied in ourselves, and therefore own: deleting one is safe,
    /// because nothing else on the Mac points at it. Anything dragged in from
    /// Finder lives outside this folder and is never touched.
    static func isStaged(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(stagingDirectory.standardizedFileURL.path)
    }

    /// Everything currently staged — for sweeping copies whose shelf entry is
    /// gone (a crash between the copy and the shelf write orphans a file).
    static func stagedFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: stagingDirectory, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
    }

    private static let stagingDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
            .appendingPathComponent("EgoNotch/Dropped", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Timestamped and de-duplicated, so two drops never overwrite.
    private static func stagingURL(named name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension.isEmpty
            ? "png" : (name as NSString).pathExtension
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stamp = formatter.string(from: Date())

        var url = stagingDirectory.appendingPathComponent("\(base) \(stamp).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = stagingDirectory.appendingPathComponent("\(base) \(stamp) (\(n)).\(ext)")
            n += 1
        }
        return url
    }
}
