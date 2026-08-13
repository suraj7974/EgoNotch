import SwiftUI

/// EgoLock design tokens — the single source of truth for the app's look.
/// Tokens are nonisolated so nonisolated Shape/drawing code can read them.
nonisolated enum Ego {
    // MARK: Palette
    static let bg        = Color(hex: "050B14")   // near-black navy — panel base
    static let surface   = Color(hex: "0A1622")   // card/tile background
    static let surface2  = Color(hex: "0E1E2E")   // hover / elevated tile
    static let border    = Color(hex: "1E3A5F")   // 1px card borders
    static let cyan      = Color(hex: "38BDF8")   // PRIMARY accent — actions, active tab, glow
    static let cyanSoft  = Color(hex: "7DD3FC")   // secondary accent, highlights
    static let text      = Color(hex: "E2E8F0")   // primary text
    static let textMute  = Color(hex: "64748B")   // labels, captions
    static let win       = Color(hex: "4ADE80")   // positive: timer done, battery ok, WIN
    static let loss      = Color(hex: "F87171")   // negative: LOSS, errors, low battery

    // MARK: Typography — .monospaced resolves to SF Mono on macOS
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static let headerTracking: CGFloat = 3.5
    static let labelTracking: CGFloat = 2

    // MARK: Metrics
    static let cut: CGFloat = 8          // cut-corner depth
    static let cardRadius: CGFloat = 8
    static let tilePadding: CGFloat = 12
    static let gridSpacing: CGFloat = 12

    // MARK: Glow — deliberately restrained (user preference: subtle).
    // These are the ONLY glow knobs; never hardcode glow values elsewhere.
    static let glowOpacity: Double = 0.18
    static let glowRadius: CGFloat = 5

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
    /// Monospaced UPPERCASE wide-tracked header.
    func egoHeader(size: CGFloat = 11) -> some View {
        self.font(Ego.mono(size, .semibold))
            .textCase(.uppercase)
            .tracking(Ego.headerTracking)
            .foregroundStyle(Ego.text)
    }

    /// All numeric content uses tabular figures.
    func egoDigits() -> some View { self.monospacedDigit() }
}
