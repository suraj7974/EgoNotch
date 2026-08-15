import SwiftUI
import AVFoundation
import Speech

/// Settings › Ego. Also the only place Speech Recognition can be granted:
/// the system prompt refuses to appear for a menu-bar agent, so it has to be
/// asked for from a real window with the app temporarily promoted.
struct EgoSettingsPane: View {
    @Bindable private var settings = SettingsStore.shared
    private var assistant = EgoAssistant.shared

    @State private var speechAuthorised = SFSpeechRecognizer.authorizationStatus() == .authorized
    @State private var requesting = false
    @State private var typed = ""

    var body: some View {
        SettingsPane(title: "Ego",
                     subtitle: "A voice assistant that lives in the notch. Everything runs on this Mac.") {
            statusCard
            listeningCard
            voiceCard
            tryCard
        }
        .onAppear { refreshPermission() }
    }

    // MARK: - Status

    private var statusCard: some View {
        SettingsCard(title: "Status") {
            SettingsRow(label: "Ego",
                        hint: assistant.isActive
                            ? "On. Turn it off in Modules to release the microphone."
                            : "Off. Enable “Ego (voice)” in Modules to switch it on.",
                        icon: "waveform.circle.fill") {
                SettingsBadge(text: assistant.isActive ? "On" : "Off",
                              tint: assistant.isActive ? Ego.win : Ego.textMute)
            }
            SettingsDivider()
            SettingsRow(label: "Microphone",
                        hint: "Used only while Ego is listening.",
                        icon: "mic") {
                permissionControl(granted: micAuthorised,
                                  settingsPath: "Privacy_Microphone")
            }
            SettingsDivider()
            SettingsRow(label: "Speech Recognition",
                        hint: speechAuthorised
                            ? "Transcription happens on this Mac."
                            : "Required — without it Ego can't hear anything.",
                        icon: "waveform") {
                if speechAuthorised {
                    SettingsBadge(text: "Granted", tint: Ego.win)
                } else {
                    SettingsActionButton(title: requesting ? "Asking…" : "Grant", prominent: true) {
                        requestSpeech()
                    }
                }
            }
            SettingsDivider()
            SettingsRow(label: "Listening state", hint: earsHint, icon: "dot.radiowaves.left.and.right") {
                SettingsBadge(text: earsBadge, tint: earsTint)
            }
        }
    }

    // MARK: - Listening

    private var listeningCard: some View {
        SettingsCard(title: "Listening") {
            SettingsRow(label: "Wake word",
                        hint: "Say “Hey Ego”, then your command. Off means ⌘⌥E only.",
                        icon: "ear") {
                Toggle("", isOn: $settings.egoWakeWord)
                    .toggleStyle(SwitchToggleStyle(tint: Ego.accent))
                    .labelsHidden()
            }
            SettingsDivider()
            SettingsRow(label: "Also answer to plain “Ego”",
                        hint: "Faster, but it's an ordinary word — expect false wakes.",
                        icon: "exclamationmark.bubble") {
                Toggle("", isOn: $settings.egoBareWakeWord)
                    .toggleStyle(SwitchToggleStyle(tint: Ego.accent))
                    .labelsHidden()
            }
            SettingsDivider()
            SettingsRow(label: "Stand down during calls",
                        hint: "While another app holds the mic, Ego stops listening entirely.",
                        icon: "video.badge.waveform") {
                Toggle("", isOn: $settings.egoPauseInMeetings)
                    .toggleStyle(SwitchToggleStyle(tint: Ego.accent))
                    .labelsHidden()
            }
            SettingsDivider()
            SettingsRow(label: "Push to talk", hint: "Works whether or not the wake word is on.",
                        icon: "keyboard") {
                KeyCapLabel(text: GlobalHotKey.Combination.egoDefault.displayName)
            }
        }
    }

    // MARK: - Voice

    private var voiceCard: some View {
        SettingsCard(title: "Voice") {
            SettingsRow(label: "Speak replies", hint: "Short and dry — a few words, never a speech.",
                        icon: "speaker.wave.2") {
                Toggle("", isOn: $settings.egoSpeakReplies)
                    .toggleStyle(SwitchToggleStyle(tint: Ego.accent))
                    .labelsHidden()
            }
            SettingsDivider()
            SettingsRow(label: "Voice", icon: "person.wave.2") {
                Picker("", selection: $settings.egoVoiceIdentifier) {
                    Text("System default").tag("")
                    ForEach(Self.voices, id: \.identifier) { voice in
                        Text(voice.name).tag(voice.identifier)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            SettingsDivider()
            SettingsSliderRow(label: "Speaking rate", value: $settings.egoSpeechRate,
                              range: 0.35...0.65, step: 0.01) { String(format: "%.2f", $0) }
        }
    }

    // MARK: - Try it

    /// The developer-and-user-facing way to exercise Ego without speaking —
    /// the same path a spoken command takes.
    private var tryCard: some View {
        SettingsCard(title: "Try a command") {
            SettingsRow(label: "Type it instead",
                        hint: "Runs through the same grammar, tools and voice as speech.",
                        icon: "text.cursor") {
                HStack(spacing: 8) {
                    EgoTextField(placeholder: "pause the music",
                                 text: $typed,
                                 onSubmit: run,
                                 placeholderColor: Ego.textMute)
                        .frame(width: 200)
                    SettingsActionButton(title: "Run") { run() }
                }
            }
            if !assistant.reply.isEmpty {
                SettingsDivider()
                SettingsRow(label: "Last reply", hint: assistant.detail) {
                    Text(assistant.reply)
                        .font(Ego.font(11.5, .medium))
                        .foregroundStyle(Ego.text)
                }
            }
        }
    }

    private func run() {
        let command = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        assistant.handle(command)
        typed = ""
    }

    // MARK: - Permissions

    private var micAuthorised: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func refreshPermission() {
        speechAuthorised = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    private func requestSpeech() {
        requesting = true
        Task {
            let granted = await EgoEars.requestSpeechAccess()
            requesting = false
            speechAuthorised = granted
            if granted { assistant.startListeningIfWanted() }
        }
    }

    private func permissionControl(granted: Bool, settingsPath: String) -> some View {
        Group {
            if granted {
                SettingsBadge(text: "Granted", tint: Ego.win)
            } else {
                SettingsActionButton(title: "Open Settings") {
                    if let url = URL(string:
                        "x-apple.systempreferences:com.apple.preference.security?\(settingsPath)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    // MARK: - Ears state

    private var earsBadge: String {
        switch assistant.ears.status {
        case .off: "Idle"
        case .preparing: "Preparing"
        case .listening: "Listening"
        case .capturing: "Hearing you"
        case .blocked: "Blocked"
        }
    }

    private var earsTint: Color {
        switch assistant.ears.status {
        case .listening, .capturing: Ego.win
        case .blocked: Ego.loss
        default: Ego.textMute
        }
    }

    private var earsHint: String? {
        switch assistant.ears.status {
        case .blocked(let why): why
        case .preparing(let what): what
        case .listening: "Waiting for “Hey Ego”."
        case .capturing: "Taking your command."
        case .off: "Not listening."
        }
    }

    private static var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }
}
