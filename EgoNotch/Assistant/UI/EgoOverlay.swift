import SwiftUI

/// Ego's face: what it heard, what it did, and — when something risky is on
/// the table — a confirmation it will not act without.
///
/// Deliberately a strip rather than a panel. Ego interrupts whatever you were
/// doing, so it has to read in one glance and then get out of the way.
struct EgoOverlay: View {
    var assistant: EgoAssistant

    var body: some View {
        HStack(spacing: 14) {
            orb
            VStack(alignment: .leading, spacing: 3) {
                heardLine
                replyLine
                if let detail = assistant.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10, design: assistant.pending != nil ? .monospaced : .default))
                        .foregroundStyle(Ego.textMute)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            if assistant.pending != nil { confirmButtons }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Pieces

    /// Pulses while listening, settles while speaking — the one moving part,
    /// so the state is readable without reading any words.
    private var orb: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.16))
                .frame(width: 42, height: 42)
                .scaleEffect(assistant.phase == .listening ? 1 + assistant.level * 0.35 : 1)
            Circle()
                .strokeBorder(tint.opacity(0.5), lineWidth: 1)
                .frame(width: 42, height: 42)
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
        }
        .animation(.easeOut(duration: 0.12), value: assistant.level)
        .animation(Ego.Motion.spring(response: 0.28), value: assistant.phase)
    }

    private var heardLine: some View {
        Text(assistant.heard.isEmpty ? "Listening…" : assistant.heard)
            .font(Ego.font(11))
            .foregroundStyle(Ego.textMute)
            .lineLimit(1)
            .truncationMode(.head)
    }

    private var replyLine: some View {
        Text(assistant.reply)
            .font(Ego.font(15, .semibold))
            .foregroundStyle(assistant.pending != nil ? Ego.text : Ego.text)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var confirmButtons: some View {
        HStack(spacing: 8) {
            Button("Cancel") { assistant.cancelFromUI() }
                .buttonStyle(.egoSecondary)
            Button("Confirm") { assistant.confirmFromUI() }
                .buttonStyle(.egoPrimary)
        }
        .font(Ego.font(11, .medium))
    }

    private var tint: Color {
        switch assistant.phase {
        case .confirming: Ego.loss
        case .listening: Ego.accentSoft
        default: Ego.win
        }
    }

    private var symbol: String {
        switch assistant.phase {
        case .idle, .speaking: "waveform"
        case .listening: "mic.fill"
        case .thinking: "ellipsis"
        case .confirming: "exclamationmark.triangle.fill"
        }
    }
}
