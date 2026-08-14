import SwiftUI

/// A live shell in the notch. Dropping a folder (or a Terminal window's proxy
/// icon, which is its working directory) makes the session run there.
final class TerminalWidget: NotchWidget {
    let id = "terminal"
    let displayName = "Terminal"
    let icon = "terminal"
    let tileSize: WidgetTileSize = .wide
    let tab: NotchTab = .terminal
    let acceptsDroppedFiles = true

    let session = TerminalSession()

    var companionAppName: String? { "Terminal" }
    func openCompanionApp() {
        // Hand the current directory over to the real Terminal.
        let path = session.workingDirectory.path
        NSWorkspace.shared.open([URL(fileURLWithPath: path)],
                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    /// The shell only exists while the widget is enabled.
    func deactivate() { session.stop() }

    /// A dropped folder becomes the session's working directory.
    func handleDroppedFiles(_ urls: [URL]) -> Bool {
        guard let first = urls.first else { return false }
        session.changeDirectory(to: first)
        return true
    }

    func makeExpandedView() -> AnyView? {
        AnyView(TerminalTileView(widget: self))
    }
}

struct TerminalTileView: View {
    let widget: TerminalWidget
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        let session = widget.session
        VStack(alignment: .leading, spacing: 6) {
            header(session)
            output(session)
            prompt(session)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { session.start() }
    }

    private func header(_ session: TerminalSession) -> some View {
        HStack(spacing: 8) {
            Text(session.displayPath(session.workingDirectory))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Ego.textMute)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
            Button("Stop") { session.interrupt() }
                .buttonStyle(.plain)
                .font(Ego.font(10))
                .foregroundStyle(Ego.textMute)
            Button("Clear") { session.clear() }
                .buttonStyle(.plain)
                .font(Ego.font(10))
                .foregroundStyle(Ego.textMute)
        }
    }

    /// The one place scrolling is right: a terminal needs its scrollback.
    private func output(_ session: TerminalSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(session.lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(line.hasPrefix("❯ ") ? Ego.win : .white.opacity(0.9))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: session.lines.count) {
                guard session.lines.count > 0 else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(session.lines.count - 1, anchor: .bottom)
                }
            }
        }
    }

    private func prompt(_ session: TerminalSession) -> some View {
        HStack(spacing: 6) {
            Text("❯")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Ego.win)
            TextField("", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.white)
                .focused($inputFocused)
                .onSubmit {
                    session.send(input)
                    input = ""
                }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture { inputFocused = true }
    }
}
