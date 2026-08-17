# EgoNotch — portfolio entry

Everything needed to add this project to **surajpatel.me**. Taken from the
live site's own bundle, so the shape matches the ten entries already there.

---

## 1. Paste-ready entry

Your projects array uses this schema. Drop this in as `id: 11`:

```js
{
  id: 11,
  title: "EgoNotch",
  description: "A macOS notch app with an on-device voice assistant that runs your Mac.",
  tags: ["Swift", "SwiftUI", "FoundationModels", "Speech", "Accessibility"],
  type: "AI/ML",
  size: "big",
  projectUrl: "https://github.com/suraj7974/mac-notch",
  githubUrl: "https://github.com/suraj7974/mac-notch",
  image: "/projects/egonotch.png",
  featured: true
}
```

### Alternative descriptions

Your existing entries are one short third-person sentence, so these match that
length. Pick whichever reads best to you:

- "A macOS notch app with an on-device voice assistant that runs your Mac." ← recommended
- "A voice-controlled macOS notch utility with a real terminal, camera and local AI."
- "A free notch app for macOS, driven entirely by an offline voice assistant."
- "A notch utility whose voice assistant runs apps, windows and a shell — all on-device."

### Three decisions to make

**`type`** — the site currently filters on `"Web Dev"`, `"AI/ML"` and
`"Game Dev"`. This is the only native desktop app among ten web projects, which
is exactly what makes it stand out, so adding a **`"Desktop"`** category is
worth considering. `"AI/ML"` is defensible if you'd rather not touch the filter
list — on-device LLM, speech recognition and speaker verification all qualify.

**`size`** — `"big"`. Three entries use it; this is the largest piece of work
in the list by a distance and deserves the same weight.

**`projectUrl`** — a Mac app has no live demo, so both URLs point at the repo,
the same pattern used by Facial Detection, SreAI and evolvedotEXE.
**Check `mac-notch` is public before publishing** — a 404 from the portfolio is
worse than no link at all.

---

## 2. Screenshot

Existing project images are **full-screen retina captures** at roughly 16:10
(2968×1848, 3024×1964), not window crops. Match that: press **⌘⇧3**, then save
to `public/projects/egonotch.png`.

**The one shot to take**, if you take only one:

> The notch **expanded on the Home tab**, with music playing so the visualiser
> is moving, on a dark wallpaper, with Ghostty or Zed visible behind it.

That single frame shows the notch, the modules, and that it is a real desktop
app rather than a web page.

### If you want more later

| Shot | What it proves |
|---|---|
| Terminal tab with a live prompt and output | It is a genuine login shell, not a fake console |
| Ego mid-command — waveform and caption on screen | The assistant is real and has a face |
| "Run git status?" confirmation on screen | Judgement, not just features — the best shot here |
| Recorder tab — camera preview and filter chips | Breadth |
| Settings › Ego | Depth: wake names, voice ID, permissions, toggles |

---

## 3. Longer copy

Nothing on the site takes prose today — there is no long-description field — so
this is for the repo README, a detail page, or a LinkedIn post.

### Short (≈50 words)

> EgoNotch replaces a paid notch utility with a free, fully local one. Fifteen
> modules live in the notch — media, a real login shell, camera, timers, notes,
> clipboard, games. On top sits Ego: a wake-word voice assistant built on
> Apple's on-device language model, with speaker verification written from
> scratch.

### Long (≈180 words)

> EgoNotch began as a free replacement for a paid macOS notch app and grew into
> a voice-controlled workspace. The notch expands into fifteen modules —
> now-playing with a live visualiser, a genuine login shell themed to match
> Ghostty, a camera with six capture modes, focus timers, notes, clipboard
> history and a file shelf.
>
> The assistant, Ego, is the centrepiece. It listens for a wake word, matches
> common commands against a deterministic grammar for instant response, and
> falls back to Apple's on-device language model with 18 tools for anything
> phrased freely. It runs the terminal behind a confirmation gate, drives other
> applications through Accessibility — including any command in any app's menu
> bar — and runs the user's own Shortcuts.
>
> Everything happens on the device. No network calls, no API keys, no account.
> Speech recognition, language understanding and speech synthesis are all local,
> and because macOS exposes no speaker-identification API, voice matching is
> implemented from first principles with MFCC feature extraction and dynamic
> time warping.

---

## 4. Facts and figures

| | |
|---|---|
| Lines of Swift | 17,645 |
| Files | 116 |
| Commits | 121 |
| Built in | 4 days (13–16 August 2026) |
| Notch modules | 15 |
| Assistant tools | 18 |
| Network calls | 0 |
| Role | Sole developer |
| Platform | macOS 26, Apple Silicon |

**Frameworks:** SwiftUI · AppKit · Observation · FoundationModels · Speech ·
AVFoundation · Accelerate/vDSP · ApplicationServices (Accessibility) · CoreAudio ·
IOKit · Carbon · CoreImage · SwiftTerm

---

## 5. Technical highlights

The parts worth talking about in an interview, in the order I would raise them.

**Speaker verification with no API to call.** macOS gives third-party apps no
speaker identification whatsoever — Speech has no diarization, and SoundAnalysis
classifies sound *types*, not people. So it is built from first principles:
MFCC feature extraction over Accelerate/vDSP, dynamic time warping so the same
phrase said faster or slower still lines up, and a threshold calibrated from the
user's own repetitions rather than a number chosen by hand. A statistical
text-independent model came first and measured worse — the speaker's own
readings varied as much as a stranger's — so it was replaced on the evidence.

**Grammar first, model second.** Common commands hit a deterministic matcher
and act immediately; only unrecognised phrasing costs a model call. A scope
router then narrows 18 tools to the one to five a sentence could plausibly need
— added after the model answered "open Zed" by starting a game.

**Concurrency under Swift 6 strict isolation.** The audio tap runs on a
real-time thread and is `nonisolated` with a lock, because an implicitly
main-actor callback traps the process on its first buffer. Accessibility calls
are synchronous IPC into other applications, so they run off the main actor
behind deadlines: a beachballed app costs the assistant six seconds instead of
freezing the notch.

**Making the recogniser hear.** The wake word failed about half the time until
`AnalysisContext.contextualStrings` — the recogniser had never been told the
name existed and kept substituting a commoner word ("Hey, Eagle"). The same fix
applied to installed application names cured "github" being heard as "geit".

**Diagnosis over guesswork.** Command latency went from 4–36 seconds down to
about 400 ms by measuring rather than tuning — the fix was realising that a
transcript-based endpoint detector never settles while music is playing, not
shortening a timer.

---

## 6. One-liners

For a CV bullet, a LinkedIn headline, or a README subtitle.

- "A macOS notch app with an on-device voice assistant — 17,000 lines of Swift, zero network calls."
- "Voice-controlled Mac workspace: wake word, on-device LLM, real shell, no cloud."
- "Built speaker verification from scratch because macOS doesn't ship one."
