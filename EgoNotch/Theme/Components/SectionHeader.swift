import SwiftUI

/// The EgoLock "file" motif: `— FILE // 02 — NOW PLAYING`.
struct SectionHeader: View {
    let index: Int
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Ego.textMute.opacity(0.6))
                .frame(width: 16, height: 1)
            Text("FILE // \(String(format: "%02d", index)) — \(title.uppercased())")
                .font(Ego.mono(10, .medium))
                .tracking(Ego.headerTracking)
                .foregroundStyle(Ego.textMute)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

#Preview("SectionHeader") {
    VStack(alignment: .leading, spacing: 12) {
        SectionHeader(index: 2, title: "Now Playing")
        SectionHeader(index: 4, title: "Shelf")
    }
    .padding(24)
    .background(Ego.bg)
}
