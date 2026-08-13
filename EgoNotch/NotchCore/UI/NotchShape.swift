import SwiftUI

/// The notch chrome outline: square top edge (it meets the screen edge /
/// menu bar), rounded bottom corners. The radius animates between states.
nonisolated struct NotchShape: Shape {
    var bottomRadius: CGFloat = 10

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(bottomRadius, min(rect.width, rect.height) / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

#Preview("NotchShape") {
    VStack(spacing: 12) {
        NotchShape(bottomRadius: 10).fill(.black).frame(width: 280, height: 38)
        NotchShape(bottomRadius: 20).fill(.black).frame(width: 320, height: 160)
    }
    .padding(24)
    .background(Color.gray.opacity(0.3))
}
