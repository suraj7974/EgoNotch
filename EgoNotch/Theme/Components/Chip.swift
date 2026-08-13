import SwiftUI

/// Small status badge — subtle tinted capsule, native style.
struct Chip: View {
    enum Variant {
        case win, loss, neutral, accent

        var color: Color {
            switch self {
            case .win: Ego.win
            case .loss: Ego.loss
            case .neutral: Ego.textMute
            case .accent: Ego.accentSoft
            }
        }
    }

    let text: String
    var variant: Variant = .neutral

    var body: some View {
        Text(text)
            .font(Ego.font(10, .medium))
            .monospacedDigit()
            .foregroundStyle(variant.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(variant.color.opacity(0.12), in: Capsule())
    }
}

#Preview("Chips") {
    HStack(spacing: 10) {
        Chip(text: "82%", variant: .win)
        Chip(text: "Low", variant: .loss)
        Chip(text: "Idle", variant: .neutral)
        Chip(text: "Spotify", variant: .accent)
    }
    .padding(24)
    .background(Ego.bg)
}
