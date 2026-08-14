import SwiftUI
import SwiftTerm

/// A real terminal in the notch: the user's login shell inside a full xterm
/// emulator, wearing their Ghostty theme and font.
final class TerminalWidget: NotchWidget {
    let id = "terminal"
    let displayName = "Terminal"
    let icon = "terminal"
    let tileSize: WidgetTileSize = .wide
    let tab: NotchTab = .terminal
    /// The terminal fills the tab: no card, no title bar above it.
    let wantsTileChrome = false

    let terminal = NotchTerminal()

    var companionAppName: String? { "Ghostty" }
    func openCompanionApp() {
        let directory = terminal.directory ?? FileManager.default.homeDirectoryForCurrentUser
        GhosttyLauncher.open(at: directory)
    }

    /// The shell only lives while the widget is enabled.
    func deactivate() { terminal.stop() }

    func makeExpandedView() -> AnyView? {
        AnyView(TerminalTileView(widget: self))
    }
}

// MARK: - Tile

struct TerminalTileView: View {
    let widget: TerminalWidget
    @State private var sessions = TerminalSessions()

    @State private var hovering = false

    var body: some View {
        // The terminal owns the whole tab; controls float on top of it so no
        // row of chrome eats terminal lines.
        ZStack {
            // The card is the terminal's own background colour, so the inset
            // around the text still reads as part of the terminal — and a
            // click anywhere on it lands in the shell.
            widget.terminal.backgroundColor
            TerminalHost(terminal: widget.terminal)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
        }
            .overlay(alignment: .topTrailing) { controls }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Ego.border, lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture { widget.terminal.focus() }
            .onHover { hovering = $0 }
            .onAppear {
                widget.terminal.applyTheme()
                widget.terminal.startIfNeeded()
                sessions.refresh()
            }
    }

    private var controls: some View {
        HStack(spacing: 2) {
            if let session = widget.terminal.attachedSession {
                Text(session)
                    .font(Ego.font(9.5, .medium))
                    .foregroundStyle(Ego.win)
                    .padding(.horizontal, 5)
            }
            Menu {
                sessionMenu
            } label: {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 10.5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 22, height: 18)
            .foregroundStyle(Ego.textMute)
            .help("Attach a running terminal")
            .onHover { if $0 { sessions.refresh() } }

            iconButton("arrow.up.forward.app") { widget.openCompanionApp() }
                .help("Open this directory in Ghostty")
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(.black.opacity(0.45), in: Capsule())
        .padding(5)
        .opacity(hovering ? 1 : 0.25)
        .animation(Ego.Motion.spring(response: 0.2), value: hovering)
    }

    @ViewBuilder
    private var sessionMenu: some View {
        if sessions.tmuxSessions.isEmpty && sessions.runningShells.isEmpty {
            Text("No other terminals running")
        }
        if !sessions.tmuxSessions.isEmpty {
            Section("tmux — shares the live session") {
                ForEach(sessions.tmuxSessions) { session in
                    Button {
                        widget.terminal.attach(tmuxSession: session.name)
                    } label: {
                        Text("\(session.name) · \(session.windows) window\(session.windows == 1 ? "" : "s")"
                             + (session.attached ? " · attached" : ""))
                    }
                }
            }
        }
        if !sessions.runningShells.isEmpty {
            Section("Open terminals — continue in their folder") {
                ForEach(sessions.runningShells.prefix(8)) { shell in
                    Button("\(shell.app) · \(shell.displayName)") {
                        widget.terminal.open(directory: shell.directory)
                    }
                }
            }
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(Ego.textMute)
                .frame(width: 20, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AppKit bridge

/// Hosts the one persistent terminal view. Never rebuilds it: the shell must
/// survive tab switches and panel collapses.
private struct TerminalHost: NSViewRepresentable {
    let terminal: NotchTerminal

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        terminal.view
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        terminal.applyTheme()
        // Typing must land in the shell as soon as the tab is on screen.
        DispatchQueue.main.async {
            guard let window = view.window, window.isKeyWindow,
                  window.firstResponder !== view else { return }
            window.makeFirstResponder(view)
        }
    }
}

// MARK: - Ghostty

enum GhosttyLauncher {
    static let appURL: URL? = {
        let candidates = [URL(fileURLWithPath: "/Applications/Ghostty.app"),
                          FileManager.default.homeDirectoryForCurrentUser
                              .appendingPathComponent("Applications/Ghostty.app")]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }()

    /// Opens Ghostty in `directory` (falls back to the default terminal).
    static func open(at directory: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        if let appURL {
            NSWorkspace.shared.open([directory], withApplicationAt: appURL, configuration: configuration)
        } else {
            NSWorkspace.shared.open(directory)
        }
    }
}
