import SwiftUI

/// Plain tile/section title.
struct SectionHeader: View {
    /// Kept for call-site stability; not rendered in the neutral theme.
    let index: Int
    let title: String

    var body: some View {
        Text(title)
            .font(Ego.font(11, .semibold))
            .foregroundStyle(Ego.textMute)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("SectionHeader") {
    VStack(alignment: .leading, spacing: 12) {
        SectionHeader(index: 1, title: "Now Playing")
        SectionHeader(index: 2, title: "Shelf")
    }
    .padding(24)
    .background(Ego.bg)
}
