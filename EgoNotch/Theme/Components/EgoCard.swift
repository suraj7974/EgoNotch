import SwiftUI

/// Standard tile chrome: surface background + hairline border, elevated on hover.
struct EgoCardModifier: ViewModifier {
    var hovered = false

    func body(content: Content) -> some View {
        content
            .padding(Ego.tilePadding)
            .background(Ego.surface, in: RoundedRectangle(cornerRadius: Ego.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Ego.cardRadius)
                    .strokeBorder(Ego.border, lineWidth: 1)
            )
    }
}

/// Active element: a brighter hairline. No glow — separation is by line only.
struct EgoActiveModifier: ViewModifier {
    var isActive = true

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: Ego.cardRadius)
                    .strokeBorder(Color.white.opacity(isActive ? 0.28 : 0), lineWidth: 1)
            )
    }
}

extension View {
    func egoCard(hovered: Bool = false) -> some View {
        modifier(EgoCardModifier(hovered: hovered))
    }

    func egoActive(_ on: Bool = true) -> some View {
        modifier(EgoActiveModifier(isActive: on))
    }
}

#Preview("Cards") {
    HStack(spacing: 16) {
        Text("Surface").egoHeader(size: 11).egoCard()
        Text("Hovered").egoHeader(size: 11).egoCard(hovered: true)
        Text("Active").egoHeader(size: 11).egoCard().egoActive()
    }
    .padding(24)
    .background(Ego.bg)
}
