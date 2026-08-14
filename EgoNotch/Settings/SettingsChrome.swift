import SwiftUI

/// Shared chrome for the settings window: a pane is a titled column of cards,
/// a card is a hairline-bordered stack of rows, a row is `label (hint) …
/// control`. Everything here exists so the panes read as data, not layout.

// MARK: - Pane

struct SettingsPane<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Ego.font(19, .semibold))
                        .foregroundStyle(Ego.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(Ego.font(11))
                            .foregroundStyle(Ego.textMute)
                    }
                }
                .padding(.bottom, 2)

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 22)
        }
        .scrollIndicators(.never)
    }
}

// MARK: - Card

/// A group of rows. Pass rows separated by `SettingsDivider()`.
struct SettingsCard<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title.uppercased())
                    .font(Ego.font(10, .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Ego.textMute)
                    .padding(.leading, 3)
            }
            VStack(spacing: 0) { content }
                .background(Ego.surface2.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: Ego.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Ego.cardRadius)
                        .strokeBorder(Ego.border, lineWidth: 1)
                )
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Ego.border)
            .frame(height: 1)
            .padding(.leading, 14)
    }
}

// MARK: - Rows

struct SettingsRow<Control: View>: View {
    let label: String
    var hint: String?
    var icon: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Ego.textMute)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Ego.font(12.5))
                    .foregroundStyle(Ego.text)
                if let hint {
                    Text(hint)
                        .font(Ego.font(10.5))
                        .foregroundStyle(Ego.textMute)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Label + slider + right-aligned value, all on one line.
struct SettingsSliderRow: View {
    let label: String
    var hint: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(label)
                    .font(Ego.font(12.5))
                    .foregroundStyle(Ego.text)
                Spacer(minLength: 8)
                Text(format(value))
                    .font(Ego.font(11.5, .medium))
                    .egoDigits()
                    .foregroundStyle(Ego.text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.07), in: Capsule())
            }
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
            if let hint {
                Text(hint)
                    .font(Ego.font(10.5))
                    .foregroundStyle(Ego.textMute)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// A −/+ pill instead of AppKit's tiny double-arrow stepper.
struct SettingsStepperRow: View {
    let label: String
    var hint: String?
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var suffix: String = ""

    var body: some View {
        SettingsRow(label: label, hint: hint) {
            HStack(spacing: 0) {
                stepButton("minus") { value = max(range.lowerBound, value - step) }
                Text("\(value)\(suffix)")
                    .font(Ego.font(12, .medium))
                    .egoDigits()
                    .foregroundStyle(Ego.text)
                    .frame(width: 58)
                stepButton("plus") { value = min(range.upperBound, value + step) }
            }
            .background(Color.white.opacity(0.07), in: Capsule())
            .overlay(Capsule().strokeBorder(Ego.border, lineWidth: 1))
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Ego.text)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Small controls

/// Text-only button used for secondary actions inside rows.
struct SettingsActionButton: View {
    let title: String
    var prominent = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Ego.font(11.5, .medium))
                .foregroundStyle(prominent ? Color.black : Ego.text)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(prominent
                                   ? AnyShapeStyle(Ego.accent)
                                   : AnyShapeStyle(Color.white.opacity(hovering ? 0.14 : 0.08)))
                )
                .overlay(Capsule().strokeBorder(Ego.border, lineWidth: prominent ? 0 : 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Compact status pill (replaces the EgoLock-era Chip in settings).
struct SettingsBadge: View {
    let text: String
    var tint: Color = Ego.textMute

    var body: some View {
        Text(text)
            .font(Ego.font(10, .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.14), in: Capsule())
    }
}
