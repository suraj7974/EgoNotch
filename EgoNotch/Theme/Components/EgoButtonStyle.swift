import SwiftUI

/// Native-style buttons: filled light primary, black-with-hairline secondary.
struct EgoButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary }
    var variant: Variant = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Ego.font(12, .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                variant == .primary ? Color.white.opacity(0.9) : Color.black,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(Ego.border, lineWidth: variant == .primary ? 0 : 1)
            )
            .foregroundStyle(variant == .primary ? Color.black : Ego.text)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7),
                       value: configuration.isPressed)
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
