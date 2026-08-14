import SwiftUI

/// Text field whose placeholder is guaranteed white: SwiftUI's built-in
/// `prompt:` styling ignores foregroundStyle on macOS and always renders the
/// system's grey, so the placeholder is drawn manually underneath instead.
struct EgoTextField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    /// White by default (the notch's rule); settings rows dim it so a
    /// placeholder never reads as a real value.
    var placeholderColor: Color = .white

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(Ego.font(13))
                    .foregroundStyle(placeholderColor)
                    .allowsHitTesting(false)
            }
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(Ego.font(13))
                .foregroundStyle(.white)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
