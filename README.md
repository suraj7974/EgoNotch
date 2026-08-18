# EgoNotch

A macOS notch app with an on-device voice assistant that runs your Mac.

The notch expands into fifteen modules — media, a real login shell, a camera,
timers, notes, clipboard history, games. On top sits **Ego**, a voice assistant
that hears a wake word, understands free phrasing through Apple's on-device
language model, and drives both the notch and the rest of the Mac.

Nothing leaves the machine. No API keys, no account, no subscription.

---

## Demo

**Everything the notch does**

<video src="REPLACE_WITH_FEATURES_VIDEO_URL" controls width="100%"></video>

**Ego, the voice assistant**

<video src="REPLACE_WITH_ASSISTANT_VIDEO_URL" controls width="100%"></video>

---

## What it does

**The notch** — hover or click to expand into a tabbed panel.

| | |
|---|---|
| **Now Playing** | Artwork, a live visualiser, a seekable scrubber. Works with Spotify, Music and browsers |
| **Terminal** | A genuine login shell over a PTY, themed to match Ghostty — your aliases, prompt and history |
| **Recorder** | Photo, video, boomerang, caption GIF, photo booth, daily-selfie streak, live filters |
| **Focus** | Pomodoro, custom countdowns, stopwatch |
| **Quick Notes / To-Do** | Notes with checkboxes, a todo list, both persistent |
| **Clips / Files** | Clipboard history and a drag-and-drop file shelf |
| **Games** | Four games built for a strip: runner, snake, pong, shooter |
| **Calendar / System / Battery** | Today's events, CPU, memory, disk, battery |

It hides during fullscreen video, and it is **invisible to screen sharing**
while still visible to you.

**Ego** — say the wake word, then talk.

```
"Hey Zoro, pause"                    →  Paused.
"how far through is this song"       →  It's 1:12 into the song.
"make it a bit quieter"              →  Volume 40.
"open Zed"                           →  Zed.
"put Chrome on the left"             →  Left half.
"export as PDF"                      →  presses the menu command, in any app
"run git status"                     →  Run git status?  ← waits for your yes
"set a timer for ten minutes"        →  10 minutes.
"take a photo"                       →  Photo.
"gaana chalu karo aur volume full karo"  →  Playing. Volume 100.
```

Common commands hit a deterministic grammar and act immediately. Anything
phrased freely goes to Apple's on-device model, which picks from a set of tools
narrowed to whatever the sentence could plausibly mean.

---

## Requirements

- macOS 26 or later, Apple Silicon
- Xcode 26 (to build)
- **Apple Intelligence enabled** — for free phrasing. Everything else works
  without it; the fixed commands never need a model.

## Build

```sh
git clone git@github.com:suraj7974/mac-notch.git
cd mac-notch
make bootstrap     # installs xcodegen, generates the project
make install       # builds and puts EgoNotch in /Applications
```

`make run` builds and runs in place. `make stop` quits it.

## Permissions

Nothing is asked for up front — each prompt appears the first time you use the
feature that needs it.

| Permission | Needed for | Without it |
|---|---|---|
| **Microphone** | Ego hearing you | The assistant is silent; everything else works |
| **Speech Recognition** | Turning speech into text | Same. Grant it in Settings › Ego |
| **Accessibility** | Moving windows, pressing menu commands, noticing fullscreen | Apps still open and quit; windows and menus don't |
| **Camera** | The Recorder tab | That tab only |
| **Calendar** | Today's events | That column only |

---

## Privacy

Everything runs on the device.

- **No network calls.** No API keys, no account, no telemetry.
- Speech recognition, language understanding and speech synthesis are all local
  — Apple's on-device models, with the speech assets downloaded once by macOS.
- **Audio is never written to disk.** Live transcripts stay in memory and are
  cleared when Ego is dismissed.
- Voice matching stores measurements, never recordings.
- The debug log is off by default, capped when on, and there is a **Delete log**
  button in Settings › Ego.

Commands Ego runs in the terminal land in your shell history, deliberately — a
command you didn't type is the one you most want to find later.

---

## The assistant, in more detail

**Wake word.** Pick from Zoro, Ego, Siri, Notch, Jarvis, Edith or Friday, or add
your own name in Settings. Each carries a list of the ways speech recognisers
actually mangle it, and the chosen name is fed to the recogniser as a vocabulary
hint — without that, a rare name is substituted for a commoner word about half
the time.

**Only your voice.** Optional, on by default once taught. macOS exposes no
speaker-identification API, so this is built from scratch: MFCC features
compared with dynamic time warping, and a threshold measured from your own
repetitions. It reliably turns away a different voice; it will not stop a
recording of you.

**Terminal, gated.** Every command is read back and waits for your yes.
Dangerous ones — `sudo`, `rm -rf /`, `mkfs`, `curl … | sh` — are refused
outright, with no confirmation offered. Ego refuses to type while a password
field is open.

**Calls.** Off by default. Calls are always confirmed with the number read back
digit by digit; messages are drafted but never sent for you.

**Conversation mode.** One wake word opens the floor and it stays open until you
say "dismiss". Off means one command per wake word.

---

## How it is built

Swift 6 with strict concurrency, SwiftUI and AppKit, XcodeGen for the project.

A few decisions worth knowing if you read the source:

**One implementation per verb.** `EgoActions` is the only place anything
happens. The grammar calls it, the model's tools call it, the debug harness
calls it — so the fast path and the model can never drift into doing different
things for the same phrase.

**Grammar first, model second.** Recognised phrasings act immediately. Only what
isn't recognised costs a model call, and a scope router then narrows eighteen
tools to the handful that sentence could mean.

**Isolation is load-bearing.** The audio tap runs on a real-time thread and is
`nonisolated` with a lock — an implicitly main-actor callback traps the process
on its first buffer. Accessibility calls are synchronous IPC into other apps, so
they run off the main actor behind deadlines; a beachballed app costs Ego six
seconds instead of freezing the notch.

**The panel has one state machine.** Every transition flows through
`NotchStateController`, which keeps the AppKit window frame and the SwiftUI
spring in sync — the window is sized to the union of what's on screen and the
target, then trimmed once the spring settles.

```
EgoNotch/
├── NotchCore/      the panel, its geometry, its state machine
├── Widgets/        fifteen modules, each self-contained
├── Assistant/      Ego — ears, brain, voice, actions
│   ├── Ears/       audio tap, transcription, wake phrase, voice matching
│   ├── Brain/      command grammar, on-device model, tools, scope router
│   └── Actions/    every verb Ego knows, and the guardrails around them
└── Settings/       preferences and the settings window
```

---

## Debugging

```sh
launchctl setenv EGO_DEBUG 1                  # trace to ~/Library/Application Support/EgoNotch/ego.log
launchctl setenv EGO_DEBUG_TRANSCRIPT 1       # also record what the mic heard
launchctl setenv EGO_COMMANDS "pause;;volume 40"   # run commands at launch, no voice needed
```

The log is capped and rotates. `EGO_DEBUG_TRANSCRIPT` is a second, deliberate
switch because those lines contain speech that was never a command.

---

## Licence

MIT.
