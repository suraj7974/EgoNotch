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
                              tint: assistant.isActive ? Ego.text : Ego.textMute)
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
                    SettingsBadge(text: "Granted", tint: Ego.text)
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
            SettingsDivider()
            SettingsRow(label: "Understanding", hint: brainHint, icon: "brain") {
                if case .unavailable = EgoPlanner.readiness {
                    SettingsActionButton(title: "Open Settings", prominent: true) {
                        if let url = URL(string:
                            "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } else {
                    SettingsBadge(text: "On-device model", tint: Ego.text)
                }
            }
        }
    }

    // MARK: - Listening

    private var listeningCard: some View {
        SettingsCard(title: "Listening") {
            SettingsRow(label: "Answers to", hint: nameHint, icon: "person.text.rectangle") {
                Picker("", selection: $settings.egoWakeName) {
                    Text("Hey Ego").tag("ego")
                    Text("Hey Siri").tag("siri")
                    Text("Hey Notch").tag("notch")
                    Text("Hey Jarvis").tag("jarvis")
                    Text("Hey Edith").tag("edith")
                    Text("Hey Friday").tag("friday")
                }
                .labelsHidden()
                .frame(width: 140)
            }
            SettingsDivider()
            SettingsRow(label: "Wake word",
                        hint: "Say it, then your command. Off means ⌘⌥E only.",
                        icon: "ear") {
                Toggle("", isOn: $settings.egoWakeWord)
                    .toggleStyle(SwitchToggleStyle(tint: Ego.accent))
                    .labelsHidden()
            }
            SettingsDivider()
            SettingsRow(label: "Also answer to plain “\(bareName)”",
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
            SettingsRow(label: "Keep talking",
                        hint: "After a reply, keep listening so the next command needs no wake word. Say “stop” to end it.",
                        icon: "bubble.left.and.bubble.right") {
                Toggle("", isOn: $settings.egoConversation)
                    .toggleStyle(SwitchToggleStyle(tint: Ego.accent))
                    .labelsHidden()
            }
            SettingsDivider()
            SettingsRow(label: "Let Ego use the terminal",
                        hint: "Every command is read back and waits for your yes. Dangerous ones are refused outright.",
                        icon: "terminal") {
                Toggle("", isOn: $settings.egoTerminalControl)
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
            SettingsRow(label: "Voice", hint: voiceHint, icon: "person.wave.2") {
                Picker("", selection: $settings.egoVoiceIdentifier) {
                    Text(automaticLabel).tag("")
                    ForEach(Self.voices, id: \.identifier) { voice in
                        Text(Self.label(for: voice)).tag(voice.identifier)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }
            SettingsDivider()
            SettingsRow(label: "Get better voices",
                        hint: "Siri's voice is off-limits to apps by name, but the same recordings ship as Premium voices — download one and Ego uses it automatically.",
                        icon: "arrow.down.circle") {
                HStack(spacing: 8) {
                    SettingsActionButton(title: "Test") { testVoice() }
                    SettingsActionButton(title: "Download…", prominent: !hasGoodVoice) {
                        if let url = URL(string:
                            "x-apple.systempreferences:com.apple.preference.universalaccess?SpeakableItems") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
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

    private func testVoice() {
        assistant.speakSample()
    }

    /// Ego works without Apple Intelligence — the command grammar is the fast
    /// path either way — so this is phrased as what you gain, not as an error.
    private var brainHint: String {
        switch EgoPlanner.readiness {
        case .ready:
            "Phrasings the shortlist doesn't know go to Apple's on-device model. Nothing leaves this Mac."
        case .unavailable(let why):
            "\(why) Set commands still work; free phrasing like “make it quieter” won't. "
                + "Apple Intelligence is separate from “Hey Siri” — you can leave that off."
        }
    }

    /// The recogniser, not taste, decides which name works: a word it already
    /// knows is heard every time, a rare one about half the time.
    private var nameHint: String {
        switch settings.egoWakeName {
        case "siri":
            "Heard most reliably of all — but every nearby iPhone, Watch and HomePod answers to it too."
        case "notch":
            "A common word, so it's heard reliably."
        case "jarvis", "edith", "friday":
            "A name the recogniser already knows, so it's heard reliably."
        default:
            "The name, but rare enough that it's sometimes misheard. Switch if it keeps missing."
        }
    }

    /// Also announce the name to the bare-word toggle, which is about the same
    /// word without a greeting.
    private var bareName: String {
        settings.egoWakeName.prefix(1).uppercased() + settings.egoWakeName.dropFirst()
    }

    /// Nudges toward a Premium voice when only the compact ones are present —
    /// the default voices are what make an assistant sound like a 2005 GPS.
    private var voiceHint: String {
        hasGoodVoice
            ? "Automatic picks Siri's own voice at the best quality you have."
            : "Only compact voices are installed — they sound robotic."
    }

    /// Names what Automatic actually resolves to, so the picker isn't a guess.
    private var automaticLabel: String {
        guard let voice = EgoVoice.bestAvailable() else { return "Automatic" }
        return "Automatic (\(voice.name))"
    }

    private var hasGoodVoice: Bool {
        Self.voices.contains { $0.quality != .default }
    }

    private static func label(for voice: AVSpeechSynthesisVoice) -> String {
        let quality = switch voice.quality {
        case .premium: " (Premium)"
        case .enhanced: " (Enhanced)"
        default: ""
        }
        return voice.name + quality
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
                SettingsBadge(text: "Granted", tint: Ego.text)
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
        case .listening, .capturing: Ego.text
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
