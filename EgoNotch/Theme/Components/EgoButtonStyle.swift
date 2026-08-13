import SwiftUI

/// EgoLock buttons: angular cut-corner shape, filled-cyan primary ("OPEN THE
/// MARKET" style) or outlined secondary.
struct EgoButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary }
    var variant: Variant = .primary

    func makeBody(configuration: Configuration) -> some View {
        let shape = CutCornerShape()
        configuration.label
            .font(Ego.mono(11, .semibold))
            .textCase(.uppercase)
            .tracking(Ego.labelTracking)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(variant == .primary ? Ego.cyan : .clear, in: shape)
            .overlay(shape.strokeBorder(Ego.cyan, lineWidth: 1))
            .foregroundStyle(variant == .primary ? Ego.bg : Ego.cyan)
            .brightness(configuration.isPressed ? -0.12 : 0)
            .contentShape(shape)
    }
}

extension ButtonStyle where Self == EgoButtonStyle {
    static var egoPrimary: EgoButtonStyle { .init(variant: .primary) }
    static var egoSecondary: EgoButtonStyle { .init(variant: .secondary) }
}

#Preview("Buttons") {
    HStack(spacing: 12) {
        Button("Open the market") {}.buttonStyle(.egoPrimary)
        Button("Portfolio") {}.buttonStyle(.egoSecondary)
    }
    .padding(24)
    .background(Ego.bg)
}
