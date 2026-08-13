import SwiftUI

/// Faint grid + scanline backdrop for the expanded panel. Static — drawn once
/// per size change, never animated, never hit-tested.
struct GridTexture: View {
    var gridSpacing: CGFloat = 24
    var scanlineSpacing: CGFloat = 3

    var body: some View {
        Canvas(opaque: false) { ctx, size in
            var grid = Path()
            for x in stride(from: CGFloat(0), through: size.width, by: gridSpacing) {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: CGFloat(0), through: size.height, by: gridSpacing) {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(grid, with: .color(Ego.cyan.opacity(0.03)), lineWidth: 1)

            var scan = Path()
            for y in stride(from: CGFloat(0), through: size.height, by: scanlineSpacing) {
                scan.move(to: CGPoint(x: 0, y: y))
                scan.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(scan, with: .color(.white.opacity(0.015)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

#Preview("GridTexture") {
    ZStack {
        Ego.bg
        GridTexture()
        Text("Backdrop").egoHeader()
    }
    .frame(width: 320, height: 180)
}
