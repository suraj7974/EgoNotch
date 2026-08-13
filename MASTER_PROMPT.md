# MASTER PROMPT — "EgoNotch" (Custom macOS Notch App)

Keep this file in the repo root so future sessions can re-read it.

---

## MISSION

Build **EgoNotch** — a free, personal macOS notch utility app that replaces NotchNest and matches/exceeds the features of paid apps like NotchNook, Boring Notch, Alcove, and Seam. It turns the MacBook notch into a Dynamic Island-style hub. Target machine: **MacBook with Apple M5, latest macOS**. This is a personal app — no App Store sandboxing constraints, no monetization, local code signing only.

Work in phases (defined below). Complete and let me test each phase before moving to the next. At the end of every phase, give me exact build/run instructions.

## TECH STACK & ARCHITECTURE

- **Swift 5.10+ / SwiftUI**, native only. No Electron, no web views.
- Xcode project (create via `xcodegen` or a committed `.xcodeproj` — your choice, but it must build with `xcodebuild` from CLI).
- **Menu bar agent app**: `LSUIElement = true` (no Dock icon). Menu bar icon with Settings + Quit.
- **The notch window**: a borderless, non-activating `NSPanel`:
  - `styleMask: [.borderless, .nonactivatingPanel]`
  - `level = .statusBar + 1` (floats above fullscreen apps too — set `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`)
  - Transparent background, `ignoresMouseEvents = false`, positioned exactly over the physical notch.
- **Notch geometry**: derive the notch frame from `NSScreen.safeAreaInsets` + `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`. Fall back to a configurable virtual notch on external displays.
- **States**: `closed` (hugs the notch, shows slim live indicators on either side) → `hover` (slight grow + glow) → `expanded` (large panel drops down with spring animation, `interactiveSpring(response: 0.35, dampingFraction: 0.75)`).
- **Event-driven, low power**: no polling loops. Use NotificationCenter/Combine publishers, `DistributedNotificationCenter` for media, timers only while a widget is visible. Idle CPU must be ~0%.
- **Modular widget system**: each feature is a self-contained module conforming to a `NotchWidget` protocol (id, icon, closedAccessory view, expandedView, enabled flag). Settings lets me toggle every module independently.
- Persist settings with `UserDefaults` via a small `@AppStorage`-backed `SettingsStore`.
- Launch at login via `SMAppService.mainApp`.

## PHASES

### Phase 1 — Shell (foundation)
1. Menu bar app skeleton, notch panel positioned over the notch on the built-in display.
2. Closed/hover/expanded state machine with buttery spring animations and a subtle cyan glow on hover.
3. Expanded panel with the EgoLock design system (below), an empty modular widget grid, and a working Settings window (toggle widgets, launch at login, animation speed).
4. Handle display changes (lid close, external monitor, resolution change) without the panel drifting.

### Phase 2 — Media (the core daily-driver feature)
1. **Now Playing**: track title, artist, album art, progress bar, play/pause/next/prev. Prefer the private `MediaRemote` framework (dlopen + `MRMediaRemoteGetNowPlayingInfo`, register for change notifications); fall back to AppleScript/ScriptingBridge for Spotify & Apple Music if MediaRemote breaks on the current macOS.
2. Closed state: mini album-art thumb on the left of the notch, animated audio bars on the right (cyan).
3. Optional lightweight **audio visualizer** in expanded view (respect low-power: only animate while expanded).
4. Audio output device name + quick AirPods battery display if available.

### Phase 3 — File Shelf + AirDrop
1. Drag files onto the notch → they land in a shelf (temporary tray) shown in expanded view.
2. Drag out to any app; buttons for AirDrop, Copy, Reveal in Finder, Clear.
3. Persist shelf across restarts (store bookmarks, not copies).

### Phase 4 — Productivity widgets (replicate + beat NotchNest)
1. **Calendar/Events** (EventKit): month mini-grid + today's events; "No Events" empty state.
2. **Clock + date** and **Focus/Pomodoro timer** (start/pause/reset, configurable durations, menu-bar countdown, completion notification with streak count).
3. **Weather**: current temp + hourly strip (Open-Meteo free API, no key needed; location via CoreLocation with a manual city fallback).
4. **Quick Notes**: "What's on your mind?" scratchpad, persisted, checkbox strikethrough support.
5. **To-do quick list** (local, simple).

### Phase 5 — System extras
1. **HUD replacement**: intercept volume/brightness keys and show a custom notch HUD instead of the macOS one (media key tap via `CGEvent` tap; require Accessibility permission and detect/prompt for it gracefully).
2. **Battery/charging live activity**: charge % pill animation when the charger connects.
3. **Mirror**: front-camera preview tile (AVFoundation; `NSCameraUsageDescription`).
4. **Clipboard history** (last 25 items, text + images, click to copy).
5. **App launcher row**: pinned apps (like NotchNest's ChatGPT shortcut) — configurable.

### Phase 6 — Polish
- Onboarding on first launch (permissions walkthrough: Calendar, Camera, Location, Accessibility).
- Haptic-feel micro-interactions, sound-free.
- Sparkle-free simple "check GitHub for update" button (optional).
- Memory/CPU audit: Activity Monitor idle target < 0.5% CPU, < 150 MB RAM.

## DESIGN SYSTEM — "EGOLOCK" THEME (mandatory)

The whole app must look like the EgoLock stock-exchange site. Dark, terminal-tech, electric.

**Color tokens** (define in `Theme.swift` as a single source of truth):

```swift
enum Ego {
    static let bg        = Color(hex: "050B14")   // near-black navy — panel base
    static let surface   = Color(hex: "0A1622")   // card/tile background
    static let surface2  = Color(hex: "0E1E2E")   // hover / elevated tile
    static let border    = Color(hex: "1E3A5F")   // 1px card borders
    static let cyan      = Color(hex: "38BDF8")   // PRIMARY accent — actions, active tab, glow
    static let cyanSoft  = Color(hex: "7DD3FC")   // secondary accent, highlights
    static let text      = Color(hex: "E2E8F0")   // primary text
    static let textMute  = Color(hex: "64748B")   // labels, captions
    static let win       = Color(hex: "4ADE80")   // positive: timer done, battery ok, WIN
    static let loss      = Color(hex: "F87171")   // negative: LOSS, errors, low battery
}
```

**Typography & motifs:**
- Headers: monospaced (SF Mono / JetBrains Mono), UPPERCASE, wide letter-spacing (tracking ~3–4).
- Section labels in the expanded panel use the EgoLock "file" motif: `— FILE // 02 — NOW PLAYING`, `— FILE // 04 — SHELF`, in `textMute` with a short leading rule line.
- Active elements get a thin cyan border + soft outer glow (`shadow(color: Ego.cyan.opacity(0.35), radius: 8)`), like the CATALYSTS tab on the site.
- Status chips: bordered mono pills — `[ WIN +1% ]` green, `[ LOSS -1% ]` red style — reuse for timer/battery/weather states.
- Buttons: angular/clipped-corner shape (like "OPEN THE MARKET"), filled cyan primary + outlined secondary.
- Subtle background: faint grid lines / scanline texture at ~3% opacity on the expanded panel.
- Numbers (clock, timer, prices, temps) always monospaced digits.

## RULES FOR YOU (CLAUDE CODE)

1. **One phase at a time.** After each phase: summarize what was built, list files changed, give me `xcodebuild` + run instructions, and wait.
2. Write real, compiling Swift — verify with a build before declaring a phase done.
3. Every permission (camera, calendar, location, accessibility) must degrade gracefully when denied — widget shows an "enable in Settings" tile, app never crashes.
4. Keep modules decoupled: deleting one widget folder must not break the build.
5. Commit per phase with clear messages (`phase-1: notch shell + state machine`).
6. If a private API (MediaRemote) fails on the installed macOS version, implement the fallback and tell me — don't silently ship a broken widget.
7. No analytics, no network calls except weather (and update check if I enable it).

## STATUS: ALL 6 PHASES COMPLETE (2026-08-13)

Every phase is built, adversarially reviewed, and committed. Final audit: idle CPU ≈0.05% (target <0.5%), ~90MB RAM (target <150MB). Remaining optional spec item: the Phase-2 audio visualizer (explicitly optional; skip unless requested).

## PROJECT NOTES — OVERRIDES (read these first)

- **The EgoLock design system below is DROPPED** (user decision, 2026-08-13): the app uses a neutral, native NotchNest-like dark theme — black panel, iOS-gray tiles, SF Pro normal case, white/gray text, sparing blue accent, system green/red, near-zero glow. `Theme.swift` (`enum Ego`) remains the single token source; restyle only through it. No FILE// headers, bracket chips, cut corners, grid textures, or cyan glow.
- Glow must stay minimal (`Ego.glowOpacity/glowRadius` are the only knobs).
- The EgoLock lightning animation is DROPPED permanently (user decision).
- Media: MediaRemote works via the embedded adapter dylib run inside /usr/bin/perl (macOS 15.4+ entitlement gate). Spotify additionally has a first-class official local channel (distributed notifications + AppleScript + artwork url; a small network fetch for Spotify artwork is user-approved). Fallback (Spotify/Music only) engages if the adapter dies, surfaced with a "Fallback" badge.
- `EGO_DEBUG_EXPAND=1` env var auto-expands the panel (headless testing).

## PROJECT NOTES (added during Phase 1)

- Build entry point: `make bootstrap` (once), `make run` (build + relaunch), `make stop`.
- `project.yml` is the single source of truth — never configure the project in Xcode's UI. The generated `.xcodeproj`, `Config/Info.plist`, and `Config/EgoNotch.entitlements` are gitignored.
- `EgoNotch/` is an Xcode 16 buildable folder (synced) — new Swift files are picked up with no regeneration.
- Signing uses the local Apple Development certificate (team 7GYNAZ2QSZ) so TCC permission grants stay stable across rebuilds. Never change the bundle id `com.suraj.EgoNotch`.
- macOS 15.4+ gates MediaRemote's now-playing API behind an entitlement — Phase 2 should evaluate the mediaremote-adapter technique before raw dlopen.
