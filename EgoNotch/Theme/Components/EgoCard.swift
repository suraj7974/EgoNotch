import SwiftUI

/// Standard tile chrome: surface background + 1px border, elevated on hover.
struct EgoCardModifier: ViewModifier {
    var hovered = false

    func body(content: Content) -> some View {
        content
            .padding(Ego.tilePadding)
            .background(
                hovered ? Ego.surface2 : Ego.surface,
                in: RoundedRectangle(cornerRadius: Ego.cardRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Ego.cardRadius)
                    .strokeBorder(Ego.border, lineWidth: 1)
            )
    }
}

/// The "active element" motif: thin cyan border + soft outer glow.
struct EgoActiveModifier: ViewModifier {
    var isActive = true

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: Ego.cardRadius)
                    .strokeBorder(Ego.cyan.opacity(isActive ? 0.6 : 0), lineWidth: 1)
            )
            .shadow(color: Ego.cyan.opacity(isActive ? Ego.glowOpacity : 0),
                    radius: Ego.glowRadius)
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
        Text("SURFACE").egoHeader(size: 10).egoCard()
        Text("HOVERED").egoHeader(size: 10).egoCard(hovered: true)
        Text("ACTIVE").egoHeader(size: 10).egoCard().egoActive()
    }
    .padding(24)
    .background(Ego.bg)
}
