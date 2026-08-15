import SwiftUI

/// Ego's face: a waveform where the song title goes, and one line of text.
///
/// Strictly black and white. The notch's whole look is absolute black with
/// hairlines, and a coloured assistant would be the one thing on screen
/// shouting for attention.
struct EgoOverlay: View {
    var assistant: EgoAssistant

    var body: some View {
        VStack(spacing: 4) {
            EgoWaveform(level: assistant.level, mode: mode)
                .frame(height: 22)
            Text(caption)
                .font(Ego.font(10.5, assistant.phase == .confirming ? .semibold : .regular))
                .foregroundStyle(assistant.phase == .confirming ? Ego.text : Ego.textMute)
                .lineLimit(1)
                .truncationMode(.middle)
            if assistant.pending != nil {
                HStack(spacing: 6) {
                    miniButton("Cancel") { assistant.cancelFromUI() }
                    miniButton("Confirm") { assistant.confirmFromUI() }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// What the waveform is doing right now.
    private var mode: EgoWaveform.Mode {
        switch assistant.phase {
        case .listening: .listening
        case .speaking, .thinking: .speaking
        case .confirming: .waiting
        case .idle: .idle
        }
    }

    /// One line: what you said, or what Ego said back.
    private var caption: String {
        if assistant.phase == .confirming { return assistant.reply }
        if !assistant.reply.isEmpty, assistant.phase == .speaking { return assistant.reply }
        if !assistant.heard.isEmpty { return assistant.heard }
        return "Listening…"
    }

    private func miniButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Ego.font(9.5, .semibold))
                .foregroundStyle(Ego.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The wavy line. Driven by a clock rather than by animations started on
/// appear — the same lesson the music visualiser taught: an implicit animation
/// begun before the view is on screen never runs at all.
struct EgoWaveform: View {
    enum Mode { case idle, listening, speaking, waiting }

    let level: Double
    let mode: Mode

    private static let bars = 27

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: mode == .idle)) { context in
            Canvas { drawing, size in
                let time = context.date.timeIntervalSinceReferenceDate
                let width = size.width / Double(Self.bars)
                let barWidth = max(1.5, width * 0.42)

                for index in 0..<Self.bars {
                    let x = width * (Double(index) + 0.5)
                    let height = barHeight(index: index, time: time, maxHeight: size.height)
                    let rect = CGRect(x: x - barWidth / 2,
                                      y: (size.height - height) / 2,
                                      width: barWidth, height: height)
                    // Centre bars are brightest, so the shape reads as a voice
                    // rather than a bar chart.
                    let distance = abs(Double(index) - Double(Self.bars - 1) / 2)
                    let fade = 1 - (distance / Double(Self.bars)) * 1.1
                    drawing.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                                 with: .color(.white.opacity(0.25 + 0.6 * fade)))
                }
            }
        }
    }

    private func barHeight(index: Int, time: Double, maxHeight: Double) -> Double {
        let centre = Double(Self.bars - 1) / 2
        // A bell across the row: tall in the middle, quiet at the edges.
        let envelope = exp(-pow((Double(index) - centre) / (centre * 0.62), 2))
        let floor = 2.0

        switch mode {
        case .idle:
            return floor
        case .waiting:
            // A slow, patient breath while it waits for a yes or no.
            let breath = 0.5 + 0.5 * sin(time * 1.6)
            return floor + maxHeight * 0.18 * envelope * breath
        case .listening:
            // Your voice drives it; the offsets keep neighbours out of step.
            let wobble = sin(time * 7 + Double(index) * 0.7)
                + 0.5 * sin(time * 11.3 + Double(index) * 1.3)
            let amplitude = 0.12 + level * 0.88
            return floor + maxHeight * 0.9 * envelope * amplitude * abs(wobble) / 1.5
        case .speaking:
            // Ego's own voice isn't measurable (the mic is muted while it
            // talks), so this is a synthetic cadence — busier than idle,
            // steadier than speech.
            let wobble = sin(time * 9 + Double(index) * 0.9)
                + 0.4 * sin(time * 14 + Double(index) * 1.7)
            return floor + maxHeight * 0.62 * envelope * abs(wobble) / 1.4
        }
    }
}
