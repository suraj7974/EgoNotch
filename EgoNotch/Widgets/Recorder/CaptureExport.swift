import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Turning frames into files: stills, animated GIFs, boomerangs, photo strips.
/// Everything here is `nonisolated` because it runs off the main actor —
/// encoding a 45-frame GIF on the main thread would stutter the whole panel.
nonisolated enum CaptureExport {

    // MARK: - Destinations

    /// Where the notch keeps what you shoot. Its own folder, so the captures
    /// strip can list them without trawling the Desktop.
    static var libraryDirectory: URL {
        let base = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EgoNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func url(prefix: String, ext: String, in directory: URL? = nil) -> URL {
        let folder = directory ?? libraryDirectory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "\(prefix) \(formatter.string(from: Date()))"
        var url = folder.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return url
    }

    // MARK: - Stills

    @discardableResult
    static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }

    /// Straight onto the clipboard, for pasting into a chat without a detour
    /// through Finder.
    static func copyToPasteboard(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([NSImage(cgImage: image,
                                         size: NSSize(width: image.width, height: image.height))])
    }

    static func copyToPasteboard(fileAt url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    // MARK: - Animated GIF

    /// `loopBackwards` is what makes a boomerang: the frames are replayed in
    /// reverse so the clip has no visible seam.
    @discardableResult
    static func writeGIF(_ frames: [CGImage], to url: URL,
                         frameDuration: Double = 0.07,
                         loopBackwards: Bool = false) -> Bool {
        guard !frames.isEmpty else { return false }
        var sequence = frames
        if loopBackwards, frames.count > 2 {
            sequence += frames.dropFirst().dropLast().reversed()
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, sequence.count, nil)
        else { return false }

        let fileProperties = [kCGImagePropertyGIFDictionary as String:
                                [kCGImagePropertyGIFLoopCount as String: 0]]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary as String:
                                [kCGImagePropertyGIFDelayTime as String: frameDuration]]
        for frame in sequence {
            CGImageDestinationAddImage(destination, frame, frameProperties as CFDictionary)
        }
        return CGImageDestinationFinalize(destination)
    }

    // MARK: - Captions

    /// Meme-style caption across the bottom: white, heavy, outlined so it
    /// survives whatever is behind it.
    static func caption(_ text: String, on image: CGImage) -> CGImage? {
        guard !text.isEmpty else { return image }
        let size = NSSize(width: image.width, height: image.height)
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        NSImage(cgImage: image, size: size).draw(in: NSRect(origin: .zero, size: size))

        let fontSize = size.height * 0.13
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black,
            .strokeWidth: -4.0,
            .paragraphStyle: style,
        ]
        let bounds = NSRect(x: 8, y: size.height * 0.04,
                            width: size.width - 16, height: fontSize * 1.5)
        (text as NSString).draw(in: bounds, withAttributes: attributes)
        canvas.unlockFocus()

        var rect = CGRect(origin: .zero, size: size)
        return canvas.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    // MARK: - Photo strip

    /// Four shots composited into one strip, with a date stamp — the thing you
    /// actually keep from a photo booth.
    static func photoStrip(_ shots: [CGImage]) -> CGImage? {
        guard !shots.isEmpty else { return nil }
        let cell = CGSize(width: 320, height: 240)
        let border: CGFloat = 14
        let gap: CGFloat = 8
        let footer: CGFloat = 44
        let size = NSSize(width: border * 2 + cell.width,
                          height: border * 2 + footer + (cell.height + gap) * CGFloat(shots.count) - gap)

        let canvas = NSImage(size: size)
        canvas.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        for (index, shot) in shots.enumerated() {
            let y = size.height - border - cell.height - CGFloat(index) * (cell.height + gap)
            let frame = NSRect(x: border, y: y, width: cell.width, height: cell.height)
            NSImage(cgImage: shot, size: cell).draw(in: frame,
                                                    from: .zero,
                                                    operation: .copy,
                                                    fraction: 1,
                                                    respectFlipped: true,
                                                    hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        (formatter.string(from: Date()) as NSString).draw(
            in: NSRect(x: border, y: 12, width: cell.width, height: 22),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: NSColor.black.withAlphaComponent(0.65),
                .paragraphStyle: style,
            ])
        canvas.unlockFocus()

        var rect = CGRect(origin: .zero, size: size)
        return canvas.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// Square crop of the middle — the circular preview implies a square, so
    /// what you save should match what you framed.
    static func squareCrop(_ image: CGImage) -> CGImage {
        let side = min(image.width, image.height)
        let rect = CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2,
                          width: side, height: side)
        return image.cropping(to: rect) ?? image
    }
}
