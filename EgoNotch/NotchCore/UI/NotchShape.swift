import SwiftUI

/// The notch chrome outline, NotchNest-style: the top corners flare OUTWARD
/// (concave fillets that blend the shape into the screen bezel/menu bar), the
/// side walls are inset by that flare, and the bottom corners are convex
/// rounded. Both radii animate between states.
nonisolated struct NotchShape: Shape {
    var topRadius: CGFloat = 8
    var bottomRadius: CGFloat = 13

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.height / 2)
        let b = min(bottomRadius, min(rect.width / 2 - t, rect.height - t))
        var p = Path()

        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Top-left flare: bulges out to meet the bezel smoothly.
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        // Left wall (inset by the flare).
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        // Bottom-left corner.
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        // Bottom edge.
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        // Bottom-right corner.
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        // Right wall.
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        // Top-right flare.
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

#Preview("NotchShape") {
    VStack(spacing: 12) {
        NotchShape(topRadius: 8, bottomRadius: 13)
            .fill(.black)
            .frame(width: 320, height: 42)
        NotchShape(topRadius: 8, bottomRadius: 24)
            .fill(.black)
            .frame(width: 360, height: 180)
    }
    .padding(24)
    .background(Color.gray.opacity(0.3))
}
