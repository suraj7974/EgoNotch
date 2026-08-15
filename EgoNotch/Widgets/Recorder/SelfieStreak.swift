import AppKit
import ImageIO
import Observation

/// One selfie a day, kept in its own folder, with the streak counted.
///
/// The point isn't the photo — it's that after a few months a single button
/// stitches the lot into a time-lapse of your year.
@MainActor
@Observable
final class SelfieStreak {
    private(set) var streak = 0
    private(set) var total = 0
    private(set) var takenToday = false
    private(set) var busy = false

    private static var directory: URL {
        let url = CaptureExport.libraryDirectory.appendingPathComponent("Daily", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func refresh() {
        let days = storedDays()
        total = days.count
        takenToday = days.contains(Self.formatter.string(from: Date()))
        streak = currentStreak(in: Set(days))
    }

    /// Today's photo. Re-shooting replaces it, so you can't inflate the count.
    func save(_ image: CGImage) {
        let url = Self.directory
            .appendingPathComponent("\(Self.formatter.string(from: Date())).png")
        try? FileManager.default.removeItem(at: url)
        CaptureExport.writePNG(CaptureExport.squareCrop(image), to: url)
        refresh()
    }

    /// Every daily shot, oldest first, as one looping GIF. Returns where it
    /// landed, or nil if there was nothing to stitch.
    @discardableResult
    func makeTimelapse() async -> URL? {
        guard !busy, total > 1 else { return nil }
        busy = true
        let files = storedDays().sorted().map {
            Self.directory.appendingPathComponent("\($0).png")
        }
        let destination = CaptureExport.url(prefix: "EgoNotch Year", ext: "gif")
        // Decoding and re-encoding months of stills has no business on the
        // main actor.
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            let frames = files.compactMap { url -> CGImage? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                return CGImageSourceCreateImageAtIndex(source, 0, nil)
            }
            return CaptureExport.writeGIF(frames, to: destination, frameDuration: 0.18)
        }.value
        busy = false
        return ok ? destination : nil
    }

    // MARK: - Counting

    private func storedDays() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.directory, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        return files.filter { $0.pathExtension == "png" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    /// Counts back from today — or from yesterday, so a streak isn't declared
    /// broken until the day is actually missed.
    private func currentStreak(in days: Set<String>) -> Int {
        let calendar = Calendar.current
        var cursor = Date()
        if !days.contains(Self.formatter.string(from: cursor)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor)
            else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(Self.formatter.string(from: cursor)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
