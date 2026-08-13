import SwiftUI

/// Design tokens — the single source of truth for the app's look.
/// Neutral, native-dark style (NotchNest-like): black panel, iOS-gray tiles,
/// SF Pro, white/gray text, sparing blue accent, near-zero glow.
/// Tokens are nonisolated so nonisolated Shape/drawing code can read them.
nonisolated enum Ego {
    // MARK: Palette
    static let bg         = Color(hex: "131315")     // panel base
    static let surface    = Color(hex: "232326")     // card/tile background
    static let surface2   = Color(hex: "2E2E31")     // hover / elevated tile
    static let border     = Color.white.opacity(0.10)

    // Depth gradients — the "premium" panel/tile treatment.
    static var panelGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: "1E1E20"), Color(hex: "121214")],
                       startPoint: .top, endPoint: .bottom)
    }
    static var tileGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: "252528"), Color(hex: "1C1C1F")],
                       startPoint: .top, endPoint: .bottom)
    }
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

    // MARK: Glow — near-zero by design (user preference: minimal glow).
    // These are the ONLY glow knobs; never hardcode glow values elsewhere.
    static let glowColor = Color.white
    static let glowOpacity: Double = 0.10
    static let glowRadius: CGFloat = 6

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
