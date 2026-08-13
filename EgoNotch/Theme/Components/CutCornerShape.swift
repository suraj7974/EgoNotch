import SwiftUI

/// Angular sci-fi HUD shape: a rectangle with one corner cut at 45°.
/// InsettableShape so strokeBorder stays crisp at 1px.
nonisolated struct CutCornerShape: InsettableShape {
    enum Corner { case topLeading, topTrailing, bottomLeading, bottomTrailing }

    var cut: CGFloat = Ego.cut
    var corner: Corner = .bottomTrailing
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> CutCornerShape {
        var s = self
        s.insetAmount += amount
        return s
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let c = min(cut, min(r.width, r.height) / 2)
        var p = Path()
        switch corner {
        case .topLeading:
            p.move(to: CGPoint(x: r.minX + c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        case .topTrailing:
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        case .bottomLeading:
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
        case .bottomTrailing:
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
            p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}

#Preview("CutCornerShape") {
    HStack(spacing: 16) {
        ForEach([CutCornerShape.Corner.topLeading, .topTrailing, .bottomLeading, .bottomTrailing], id: \.self) { corner in
            CutCornerShape(corner: corner)
                .strokeBorder(Ego.cyan, lineWidth: 1)
                .frame(width: 72, height: 32)
        }
    }
    .padding(24)
    .background(Ego.bg)
}
