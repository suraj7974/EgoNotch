import SwiftUI

/// Design tokens — the single source of truth for the app's look.
/// Neutral, native-dark style (NotchNest-like): black panel, iOS-gray tiles,
/// SF Pro, white/gray text, sparing blue accent, near-zero glow.
/// Tokens are nonisolated so nonisolated Shape/drawing code can read them.
nonisolated enum Ego {
    // MARK: Palette — ABSOLUTE black. No gradients, no grey washes; things
    // are separated by hairlines and borders, never by background shade.
    static let bg         = Color.black              // panel base
    static let surface    = Color.black              // card/tile background
    /// Rows, fields and controls. Black like everything else — separation is
    /// a hairline's job, never a lighter fill.
    static let surface2   = Color.black
    static let border     = Color.white.opacity(0.12)
    static let accent     = Color(hex: "0A84FF")     // interactive accent — use sparingly
    static let accentSoft = Color(hex: "64D2FF")
    static let text       = Color.white.opacity(0.95)
    static let textMute   = Color.white.opacity(0.55)
    static let win        = Color(hex: "30D158")     // positive
    static let loss       = Color(hex: "FF453A")     // negative

    // MARK: Typography — system SF Pro
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    // MARK: Metrics
    static let cardRadius: CGFloat = 12
    static let tilePadding: CGFloat = 12
    static let gridSpacing: CGFloat = 12

    // Glow is deliberately absent app-wide: pure black surfaces separated by
    // hairlines only. Do not reintroduce shadows/halos on the chrome.

    // MARK: Motion — every animation goes through here so the user's
    // animation-speed setting applies app-wide. (MainActor: reads SettingsStore.)
    @MainActor
    enum Motion {
        static var speed: Double { SettingsStore.shared.animationSpeed }

        static func spring(response: Double = 0.32, damping: Double = 0.82) -> Animation {
            .spring(response: response / speed, dampingFraction: damping)
        }

        /// The notch open/close spring from the spec.
        static var notch: Animation {
            .interactiveSpring(response: 0.35 / speed, dampingFraction: 0.75)
        }
    }
}

nonisolated extension Color {
    /// Accepts "38BDF8", "#38BDF8", or "38BDF8CC" (RRGGBBAA).
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xFF) / 255; g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255;  a = Double(v & 0xFF) / 255
        } else {
            r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255;         a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

extension View {
    /// Standard section/title text.
    func egoHeader(size: CGFloat = 12) -> some View {
        self.font(Ego.font(size, .semibold))
            .foregroundStyle(Ego.text)
    }

    /// All numeric content uses tabular figures.
    func egoDigits() -> some View { self.monospacedDigit() }
}
