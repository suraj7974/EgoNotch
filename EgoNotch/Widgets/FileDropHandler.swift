import Foundation
import UniformTypeIdentifiers

/// Shared NSItemProvider → [URL] loader for file drops (providers complete on
/// arbitrary queues; results are delivered on the main actor). Lives at the
/// widget-infrastructure level — both the notch chrome and individual widget
/// tiles use it, so it must never sit inside a deletable widget folder.
enum FileDropHandler {
    static func load(_ providers: [NSItemProvider],
                     completion: @escaping ([URL]) -> Void) {
        Task {
            var urls: [URL] = []
            for provider in providers
            where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                let url: URL? = await withCheckedContinuation { cont in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        cont.resume(returning: url)
                    }
                }
                if let url { urls.append(url) }
            }
            if !urls.isEmpty { completion(urls) }
        }
    }
}
