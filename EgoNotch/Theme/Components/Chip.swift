import SwiftUI

/// Bordered mono status pill: `[ WIN +1% ]` / `[ LOSS -1% ]`.
struct Chip: View {
    enum Variant {
        case win, loss, neutral, accent

        var color: Color {
            switch self {
            case .win: Ego.win
            case .loss: Ego.loss
            case .neutral: Ego.textMute
            case .accent: Ego.cyan
            }
        }
    }

    let text: String
    var variant: Variant = .neutral

    var body: some View {
        Text("[ \(text.uppercased()) ]")
            .font(Ego.mono(10, .medium))
            .tracking(1)
            .monospacedDigit()
            .foregroundStyle(variant.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(variant.color.opacity(0.45), lineWidth: 1)
            )
    }
}

#Preview("Chips") {
    HStack(spacing: 10) {
        Chip(text: "WIN +1%", variant: .win)
        Chip(text: "LOSS -1%", variant: .loss)
        Chip(text: "IDLE", variant: .neutral)
        Chip(text: "LIVE", variant: .accent)
    }
    .padding(24)
    .background(Ego.bg)
}
