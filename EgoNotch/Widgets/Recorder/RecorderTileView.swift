import SwiftUI
import AVFoundation

/// The Recorder tab's layout: bubble hard left, then the shutter, then three
/// stacked rows — modes, looks, and what you've shot. Same rhythm as Now
/// Playing, so the two tabs read as one app.
struct RecorderTileView: View {
    var camera: RecorderCamera

    var body: some View {
        Group {
            switch camera.access {
            case .denied:
                message("Enable Camera for EgoNotch in System Settings", chip: "No camera")
            case .unknown:
                message("Requesting camera…", chip: nil)
            case .granted:
                HStack(alignment: .center, spacing: 12) {
                    bubble
                    shutterColumn
                    Rectangle().fill(Ego.border).frame(width: 1).padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 7) {
                        modeRow
                        secondRow
                        capturesRow
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear { camera.appear() }
        .onDisappear { camera.disappear() }
    }

    private func message(_ text: String, chip: String?) -> some View {
        HStack(spacing: 10) {
            if let chip { Chip(text: chip, variant: .loss) }
            Text(text)
                .font(Ego.font(11))
                .foregroundStyle(Ego.textMute)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Bubble

    /// Circular, as before — but now it's our own render of the filtered
    /// frame, which is what lets the look you pick end up in the file.
    private var bubble: some View {
        ZStack {
            if let frame = camera.preview {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }

            if camera.flash > 0 {
                Color.white.opacity(camera.flash)
            }

            if let countdown = camera.countdown {
                Text("\(countdown)")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.7), radius: 6)
                    .transition(.scale)
            }

            if let prompt = camera.prompt, camera.countdown == nil {
                Text(prompt)
                    .font(Ego.font(12, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule())
                    .shadow(color: .black.opacity(0.5), radius: 4)
            }
        }
        .frame(width: 118, height: 118)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .overlay(alignment: .bottom) {
            if camera.mode == .daily, camera.streak.streak > 0 {
                Label("\(camera.streak.streak)", systemImage: "flame.fill")
                    .font(Ego.font(9.5, .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Ego.win, in: Capsule())
                    .offset(y: 4)
            }
        }
        .animation(.easeOut(duration: 0.12), value: camera.flash)
    }

    // MARK: - Shutter

    private var shutterColumn: some View {
        VStack(spacing: 8) {
            Button(action: { camera.trigger() }) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 2)
                        .frame(width: 46, height: 46)
                    if camera.isRecording {
                        RoundedRectangle(cornerRadius: 3).fill(Ego.loss)
                            .frame(width: 16, height: 16)
                    } else if camera.busy {
                        Circle().fill(Ego.textMute).frame(width: 30, height: 30)
                    } else {
                        Circle()
                            .fill(camera.mode == .video || camera.mode == .booth
                                  ? Ego.loss : Color.white)
                            .frame(width: 32, height: 32)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(camera.mode.hint)

            if camera.isRecording, let started = camera.recordingStarted {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.duration(from: started, to: context.date))
                        .font(Ego.font(10, .semibold))
                        .egoDigits()
                        .foregroundStyle(Ego.loss)
                }
            } else {
                Text(camera.mode.title.uppercased())
                    .font(Ego.font(8.5, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Ego.textMute)
            }
        }
        .frame(width: 54)
    }

    // MARK: - Row 1: modes + options

    private var modeRow: some View {
        HStack(spacing: 5) {
            ForEach(CaptureMode.allCases) { mode in
                PillButton(title: mode.title, icon: mode.icon,
                           selected: camera.mode == mode) {
                    camera.mode = mode
                }
            }
            Spacer(minLength: 6)

            IconToggle(icon: camera.selfTimer == 0 ? "timer" : "timer.circle.fill",
                       label: camera.selfTimer == 0 ? nil : "\(camera.selfTimer)",
                       on: camera.selfTimer > 0) {
                camera.selfTimer = camera.selfTimer == 0 ? 3 : (camera.selfTimer == 3 ? 10 : 0)
            }
            .help("Self-timer")

            IconToggle(icon: "flip.horizontal", on: camera.mirrored) {
                camera.mirrored.toggle()
            }
            .help("Mirror the picture")
        }
    }

    // MARK: - Row 2: looks, or the caption when it matters

    @ViewBuilder
    private var secondRow: some View {
        if camera.mode == .gif {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 10))
                    .foregroundStyle(Ego.textMute)
                EgoTextField(placeholder: "Caption for the GIF…",
                             text: Binding(get: { camera.gifCaption },
                                           set: { camera.gifCaption = $0 }),
                             placeholderColor: Ego.textMute)
                    .frame(maxWidth: 260)
                Text("2s · copied when it's done")
                    .font(Ego.font(9.5))
                    .foregroundStyle(Ego.textMute.opacity(0.8))
                Spacer(minLength: 0)
            }
            .frame(height: 40)
        } else {
            HStack(spacing: 6) {
                ForEach(CaptureFilter.allCases) { option in
                    FilterChip(option: option,
                               image: camera.chips[option.rawValue],
                               selected: camera.filter == option) {
                        camera.filter = option
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 40)
        }
    }

    // MARK: - Row 3: what you've shot

    private var capturesRow: some View {
        HStack(spacing: 8) {
            if camera.library.items.isEmpty {
                Text(camera.mode.hint)
                    .font(Ego.font(10))
                    .foregroundStyle(Ego.textMute)
            } else {
                ForEach(camera.library.items.prefix(6), id: \.self) { url in
                    CaptureThumb(url: url,
                                 selected: camera.library.selected == url) {
                        camera.library.selected = camera.library.selected == url ? nil : url
                    }
                }
            }

            Spacer(minLength: 4)

            if camera.busy {
                Text("Building…")
                    .font(Ego.font(9.5))
                    .foregroundStyle(Ego.textMute)
            } else if camera.saveFailed {
                Text("Save failed")
                    .font(Ego.font(9.5))
                    .foregroundStyle(Ego.loss)
                    .help("Check Pictures folder access in System Settings › Privacy")
            } else if let saved = camera.lastSavedName {
                Text(saved)
                    .font(Ego.font(9.5))
                    .foregroundStyle(Ego.win)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 150, alignment: .trailing)
            }

            if !camera.library.items.isEmpty {
                actionButton("magnifyingglass", "Reveal in Finder") { camera.library.reveal() }
                actionButton("doc.on.doc", "Copy") { camera.library.copy() }
                actionButton("square.and.arrow.up", "AirDrop") { camera.library.airDrop() }
                actionButton("tray.full", "Send to Shelf") { camera.library.sendToShelf() }
                actionButton("trash", "Move to Trash") { camera.library.delete() }
            }
            if camera.mode == .daily, camera.streak.total > 1 {
                actionButton("film.stack", "Make a time-lapse of every daily shot") {
                    Task {
                        if await camera.streak.makeTimelapse() != nil {
                            camera.library.refresh()
                        }
                    }
                }
            }
        }
        .frame(height: 54)
    }

    private func actionButton(_ symbol: String, _ help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(Ego.textMute)
                .frame(width: 26, height: 26)
                .background(Color.black, in: Circle())
                .overlay(Circle().strokeBorder(Ego.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private static func duration(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Pieces

private struct PillButton: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(Ego.font(10, selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? Ego.text : Ego.textMute)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(selected ? 0.14 : (hovering ? 0.06 : 0)), in: Capsule())
            .overlay(Capsule().strokeBorder(Ego.border, lineWidth: selected ? 0 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct IconToggle: View {
    let icon: String
    var label: String?
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                if let label {
                    Text(label)
                        .font(Ego.font(9.5, .semibold))
                        .egoDigits()
                }
            }
            .foregroundStyle(on ? Ego.text : Ego.textMute)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.white.opacity(on ? 0.14 : 0), in: Capsule())
            .overlay(Capsule().strokeBorder(Ego.border, lineWidth: on ? 0 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A look, previewed with your own face rather than a swatch.
private struct FilterChip: View {
    let option: CaptureFilter
    let image: CGImage?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Group {
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Color.black
                    }
                }
                .frame(width: 30, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(selected ? Ego.accentSoft : Ego.border,
                                  lineWidth: selected ? 1.5 : 1))
                Text(option.title)
                    .font(Ego.font(8.5, selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Ego.text : Ego.textMute)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct CaptureThumb: View {
    let url: URL
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Group {
                    if let thumb = ThumbnailProvider.shared.thumbnail(for: url, size: 44) {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                    }
                }
                .frame(width: 38, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(selected ? Ego.accentSoft : Ego.border,
                                  lineWidth: selected ? 1.5 : 1))
                Text(url.pathExtension.uppercased())
                    .font(Ego.font(8))
                    .foregroundStyle(selected ? Ego.text : Ego.textMute.opacity(0.75))
            }
            .padding(2)
            .background(Color.white.opacity(hovering && !selected ? 0.06 : 0),
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .help(url.lastPathComponent)
    }
}
