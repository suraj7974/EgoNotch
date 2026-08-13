import SwiftUI

/// Native-style buttons: filled light primary, gray secondary.
struct EgoButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary }
    var variant: Variant = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Ego.font(12, .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                variant == .primary ? Color.white.opacity(0.9) : Ego.surface2,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .foregroundStyle(variant == .primary ? Color.black : Ego.text)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == EgoButtonStyle {
    static var egoPrimary: EgoButtonStyle { .init(variant: .primary) }
    static var egoSecondary: EgoButtonStyle { .init(variant: .secondary) }
}

#Preview("Buttons") {
    HStack(spacing: 12) {
        Button("Open Settings") {}.buttonStyle(.egoPrimary)
        Button("Collapse") {}.buttonStyle(.egoSecondary)
    }
    .padding(24)
    .background(Ego.bg)
}
