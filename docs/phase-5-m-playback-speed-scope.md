# P5-M — PLAYBACK SPEED: SCOPE AND PRODUCT PROPOSAL

**Derived from the current code on 2026-09-09. NOT IMPLEMENTED — for product
approval.** C-3 and C-56 are **not** part of this unit.

## 1. The current playback architecture

`AttachmentViewerView` (2,979 lines) is a **`TabView(selection: $currentIndex)`**
(`:728`) paging between attachments. Each page is `ImagePage`, `VideoPage` or
`AudioPage`, and **each page owns its own player state**.

**THERE ARE THREE PLAYER STACKS, NOT ONE — and they use TWO different APIs:**

| stack | class | API |
|---|---|---|
| **video** | inline in `VideoPage` (`:1711`), `@State private var player: AVPlayer?` | **`AVPlayer`** + `AVPlayerLayer` |
| **local audio** | `AudioPlayerController` (`:2344`) | **`AVAudioPlayer`** |
| **remote audio** | `RemoteAudioPlayerController` (`:2435`) | **`AVPlayer`** |

**There is no shared playback abstraction.** Each has its own
`play/pause/stop/setCurrentTime`, its own `isPlaying`, and its own end handling.

**Transport controls** are two separate clusters, each with its own private
`mediaControlButton` helper (`:2252` video, `:2766` audio):

- **video** — mute · `gobackward.10` · play/pause · `goforward.10`, plus a scrub `Slider` (`:1877`)
- **audio** — `gobackward.10` · play/pause · `goforward.10`, plus a scrub `Slider` (`:2629`)

**Lifecycle.** Paging destroys/recreates page state. `VideoPage.onDisappear`
(`:1817`) stops and seeks to zero, so revisiting starts from the beginning.
Completion is handled by `.AVPlayerItemDidPlayToEndTime` (video, remote audio)
and `audioPlayerDidFinishPlaying` (local audio). **No looping.**

**Existing rate support: NONE for speed control.** The only `.rate` uses are
**play/pause detection** — `(player?.rate ?? 0) == 0` (`:2120`) and
`isPlayingState = rate > 0` (`:2131`, `:2169`). Nothing is unwired and waiting.

**Accessibility: the transport controls have NO labels.** All 12
`accessibilityLabel` uses in the file are the **top toolbar** (close, favourite,
privacy, rename, trim, delete, share) and the score rename. `mediaControlButton`
adds none. **Recorded as an observation; not fixed in this unit.**

## 2. Rate and pitch — read from the installed SDK, not assumed

**`AVPlayer` (video + remote audio) — pitch is preserved by default.**
`AVPlayerItem.audioTimePitchAlgorithm` defaults to
**`AVAudioTimePitchAlgorithmTimeDomain`** for apps linked on or after iOS 15.
`AVAudioTimePitchAlgorithmSpectral` is documented as *"often the best choice due
to the highly inclusive range of rates it supports, assuming that it is desirable
to maintain a constant pitch"* — and `Varispeed` is the one that lets pitch vary.
**Recommendation: set `.spectral` explicitly on the item.** One property, better
quality for music at 0.5×, and it removes any dependence on a default.

**`AVAudioPlayer` (local audio) — supported, with one open question.** The header
states: *"You must set `enableRate` to YES for the rate property to take effect.
You must set this before calling `prepareToPlay`."* `AudioPlayerController.play`
already calls `prepareToPlay()` (`:2374`), so this is a one-line insertion
**before** it.

> **THE ONE REAL RISK — §10.** `AVAudioPlayer` exposes **no pitch algorithm**, and
> **the header does not document whether its rate change preserves pitch.** For a
> musician's practice app, transposing the material would be unacceptable.
> **This must be settled by listening before the unit is accepted**, not assumed.

## 3. Recommendations

**3.1 Rates — five, not six.** `0.5× · 0.75× · 1× · 1.5× · 2×`.

Derived rather than assumed: `AVAudioPlayer`'s header names 0.5 and 2.0 as its
reference points, so the set sits inside the range both APIs handle comfortably.
**I dropped 1.25×**: the perceptual step from 1× is small, and every extra rate
lengthens the menu on a control that must stay compact. **Trivial to add back if
you want it** — it is one array element.

**3.2 Persistence — per viewer session, not stored.** Hold one
`@State private var playbackRate` in **`AttachmentViewerView`** and pass it into
the pages. So: **1× on every viewer open; persists while paging between
attachments; gone when the viewer closes.** Matches your stated preference, and a
musician comparing three takes at 0.75× should not have to reset at each one. **No
`UserDefaults`, no profile field, no server state.**

**3.3 Reset semantics.**

| event | rate |
|---|---|
| viewer opened | **1×** |
| moving to another attachment | **persists** |
| pause → resume | **persists** — requires §4 |
| playback reaches the end | **persists**; re-applied on replay |
| viewer closed and reopened | **1×** |

**3.4 Control — a compact `Menu`, not a slider and not a new screen.** A button in
the **existing** transport row, reusing `mediaControlButton`, labelled with the
current rate as text (`1×`, `0.75×`). Tapping opens a short menu of the five
rates with the current one checked.

**A `Menu` beats tap-to-cycle** because every rate is directly selectable without
counting taps, which is also the accessibility requirement. The current rate is
**always visible on the button face**, so no state is hidden.

**3.5 Accessibility.**
- label **"Playback speed"**
- value the current rate, spoken **"one times", "zero point seven five times"** — so the value string should be `"0.75×"` rendered but an explicit `accessibilityValue` of `"0.75 times"`.
- hint **"Choose a playback speed"**
- each menu item is a standard button and is individually selectable; **no gesture precision is required**, and there is no drag target.

## 4. STATE HAZARDS — one is a real defect trap

**`AVPlayer.play()` SETS THE RATE TO 1.0.** So on the video and remote-audio
stacks, a chosen 0.75× would **silently revert on every pause/resume** if `play()`
were used. The fix is `playImmediately(atRate:)` (or assigning `rate` directly)
wherever playback resumes — `VideoPage.togglePlayPause` (`:2117`) and
`RemoteAudioPlayerController.play` (`:2510`).

**`AVAudioPlayer` does NOT have this problem** — `rate` is a property that
survives `pause()`/`play()`.

| situation | handling |
|---|---|
| change rate **while playing** | apply immediately; `AVPlayer` via `rate`, `AVAudioPlayer` via `rate` |
| change rate **while paused** | store it; apply on resume. **Must not start playback** |
| change rate **while seeking** | seek completes, then rate is re-applied — do not set rate inside a seek completion that may be superseded |
| **switching attachment** | the new page adopts the session rate on first play |
| **completion** | rate persists; re-applied when replay starts, because `play()` on an ended item resets it |
| play/pause **detection** | unaffected — `rate > 0` remains true at 0.5× |

## 5. Files expected to change

| file | change |
|---|---|
| `MOTIVO/AttachmentViewerView.swift` | one `@State` rate in the viewer; pass into pages; one menu button per transport row; `enableRate` + `rate` in `AudioPlayerController`; `playImmediately(atRate:)` in the two `AVPlayer` paths; `.spectral` on the items |
| `MOTIVO/PlaybackRate.swift` (new, small) | the rate enum, its display strings and its accessibility strings — **pure, so it is unit-testable without a player** |
| `MOTIVOTests/…` | rate-model and structural tests |

**Nothing else.** No `PracticeTimerView`, no `MediaTrimView`, no attachment
mutation, no transcoding, no new screen.

## 6. Proposed tests and acceptance

**Pure/unit** — the rate set and its ordering; display strings (`1×`, `0.75×`);
accessibility value strings; cycling/selection maps to the right value; default is
`1×`.

**Structural** — both transport rows contain the speed control; the two `AVPlayer`
resume paths use `playImmediately(atRate:)` and **not** bare `play()`;
`enableRate` is set **before** `prepareToPlay()`; `.spectral` is set on items.

**Acceptance** — Debug and Release clean; full suite green; warning delta zero; no
production/ASC mutation.

**Device (deferred, with C-50's):** play a local audio attachment at 0.5× and
**confirm by listening that the pitch is unchanged**; confirm rate survives
pause/resume and paging; confirm 1× on reopen.

## 7. WHAT COULD MAKE THIS BIGGER THAN IT LOOKS

1. **`AVAudioPlayer` pitch behaviour is undocumented in the header (§2).** If it
   transposes, the options are to migrate local audio to `AVPlayer` — **a genuine
   redesign of one of the three stacks, and out of this unit's scope** — or to
   ship speed for video and remote audio only, which is an incoherent product.
   **This is the one thing that could change the size of the unit, and it should
   be settled first.**
2. **Three stacks means three integrations**, not one. The work is small in each,
   but there is no single place to change.
3. **`AVPlayer.play()` resetting rate (§4)** is the kind of defect that would ship
   silently and look like "the speed control sometimes forgets".
