import AppKit
import SwiftTerm

/// Reads the user's real Ghostty configuration so the notch terminal looks
/// like the terminal they already use: same theme palette, same font family.
/// Everything is best-effort — a missing config just yields the defaults.
struct GhosttyProfile {
    var background: NSColor
    var foreground: NSColor
    var cursor: NSColor
    var selectionBackground: NSColor?
    var palette: [SwiftTerm.Color]        // 16 ANSI colors
    var fontFamily: String?
    var themeName: String?
    /// `cursor-style` / `cursor-style-blink` from the config.
    var cursorStyle: CursorStyle = .steadyBar

    static let fallback = GhosttyProfile(
        background: NSColor.black,
        foreground: NSColor(white: 0.92, alpha: 1),
        cursor: NSColor(white: 0.92, alpha: 1),
        selectionBackground: nil,
        palette: SwiftTerm.Color.terminalAppColors,
        fontFamily: nil,
        themeName: nil
    )

    private static let configURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/ghostty/config")

    /// Parsed once per launch — re-reading on every render would stat the disk
    /// from `body`.
    static let current: GhosttyProfile = load()

    static func load() -> GhosttyProfile {
        guard let config = settings(at: configURL) else { return fallback }

        var profile = fallback
        profile.fontFamily = config["font-family"]
        profile.cursorStyle = cursorStyle(shape: config["cursor-style"],
                                          blink: config["cursor-style-blink"])

        if let theme = config["theme"].map(resolveThemeName),
           let themeURL = themeURL(for: theme),
           let colors = settings(at: themeURL) {
            profile.themeName = theme
            apply(colors, to: &profile)
        }
        // Colors set directly in the config win over the theme, as in Ghostty.
        apply(config, to: &profile)
        return profile
    }

    /// Ghostty's default cursor is a blinking bar; only an explicit setting
    /// changes it. Never invent a shape the user didn't ask for.
    private static func cursorStyle(shape: String?, blink: String?) -> CursorStyle {
        let blinks = blink.map { !["false", "no", "0"].contains($0.lowercased()) } ?? true
        switch shape?.lowercased() {
        case "block":     return blinks ? .blinkBlock : .steadyBlock
        case "underline": return blinks ? .blinkUnderline : .steadyUnderline
        default:          return blinks ? .blinkBar : .steadyBar     // "bar"
        }
    }

    // MARK: - Parsing

    /// Ghostty config syntax: `key = value`, `#` comments, repeated keys for
    /// `palette`. Only the last value of a plain key matters.
    private static func settings(at url: URL) -> [String: String]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var result: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"),
                  let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if key == "palette" {
                // `palette = 4=#89b4fa` — keep each index separately.
                let parts = value.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    result["palette.\(parts[0].trimmingCharacters(in: .whitespaces))"] =
                        parts[1].trimmingCharacters(in: .whitespaces)
                }
            } else {
                result[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return result
    }

    private static func apply(_ values: [String: String], to profile: inout GhosttyProfile) {
        if let c = values["background"].flatMap(color) { profile.background = c }
        if let c = values["foreground"].flatMap(color) { profile.foreground = c }
        if let c = values["cursor-color"].flatMap(color) { profile.cursor = c }
        if let c = values["selection-background"].flatMap(color) { profile.selectionBackground = c }
        for index in 0..<16 {
            if let c = values["palette.\(index)"].flatMap(terminalColor) {
                profile.palette[index] = c
            }
        }
    }

    /// `theme = catppuccin-mocha.conf`, or `theme = dark:x,light:y`.
    private static func resolveThemeName(_ raw: String) -> String {
        if raw.contains(":") {
            for part in raw.split(separator: ",") {
                let pieces = part.split(separator: ":", maxSplits: 1)
                if pieces.count == 2, pieces[0].trimmingCharacters(in: .whitespaces) == "dark" {
                    return pieces[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return raw
    }

    private static func themeURL(for name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bare = name.hasSuffix(".conf") ? String(name.dropLast(5)) : name
        let candidates = [
            home.appendingPathComponent(".config/ghostty/themes/\(name)"),
            home.appendingPathComponent(".config/ghostty/themes/\(bare)"),
            home.appendingPathComponent(".config/ghostty/themes/\(bare).conf"),
            URL(fileURLWithPath: "/Applications/Ghostty.app/Contents/Resources/ghostty/themes/\(bare)"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Colors

    /// Accepts `#rrggbb`, `rrggbb`, and `rgb:rr/gg/bb`.
    private static func components(_ raw: String) -> (Double, Double, Double)? {
        var hex = raw.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("rgb:") {
            hex = hex.dropFirst(4).replacingOccurrences(of: "/", with: "")
        }
        hex = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255)
    }

    private static func color(_ raw: String) -> NSColor? {
        guard let (r, g, b) = components(raw) else { return nil }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private static func terminalColor(_ raw: String) -> SwiftTerm.Color? {
        guard let (r, g, b) = components(raw) else { return nil }
        return SwiftTerm.Color(red: UInt16(r * 65535), green: UInt16(g * 65535), blue: UInt16(b * 65535))
    }

    // MARK: - Font

    /// The configured family at a notch-appropriate size, monospaced fallback.
    func font(size: CGFloat) -> NSFont {
        if let family = fontFamily,
           let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
