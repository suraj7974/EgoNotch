import SwiftUI

/// The notch chrome outline, NotchNest-style: the top corners flare OUTWARD
/// (blending the shape into the screen bezel), the side walls are inset by
/// that flare, and the bottom corners are deeply rounded.
///
/// Every corner is a true circular arc (`addArc(tangent:)`) — quadratic
/// curves look visibly angular once the radius gets large.
nonisolated struct NotchShape: Shape {
    var topRadius: CGFloat = 10
    var bottomRadius: CGFloat = 42

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = max(min(topRadius, min(rect.width / 4, rect.height / 2)), 0)
        let b = max(min(bottomRadius,
                        min((rect.width - 2 * t) / 2, rect.height - t)), 0)

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        if t > 0 {
            // Top-left flare: top edge → left wall.
            p.addArc(tangent1End: CGPoint(x: rect.minX + t, y: rect.minY),
                     tangent2End: CGPoint(x: rect.minX + t, y: rect.minY + t),
                     radius: t)
        }
        // Left wall → bottom edge.
        p.addArc(tangent1End: CGPoint(x: rect.minX + t, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                 radius: b)
        // Bottom edge → right wall.
        p.addArc(tangent1End: CGPoint(x: rect.maxX - t, y: rect.maxY),
                 tangent2End: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                 radius: b)
        // Right wall → top-right flare.
        if t > 0 {
            p.addArc(tangent1End: CGPoint(x: rect.maxX - t, y: rect.minY),
                     tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
                     radius: t)
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

#Preview("NotchShape") {
    VStack(spacing: 12) {
        NotchShape(topRadius: 10, bottomRadius: 13)
            .fill(.black)
            .frame(width: 300, height: 34)
        NotchShape(topRadius: 10, bottomRadius: 42)
            .fill(.black)
            .frame(width: 420, height: 200)
    }
    .padding(24)
    .background(Color.gray.opacity(0.3))
}
