# P5-M — PLAYBACK SPEED: PREDICTION

**Committed BEFORE any product mutation, 2026-09-09.**

## 1. THE PITCH PREREQUISITE — RESOLVED ON VERIFIED APPLE DOCUMENTATION

**Independently verified against live Apple documentation on 2026-09-09**, fetched
from `developer.apple.com/tutorials/data/documentation/avfaudio/avaudioplayer/rate.json`.
The statement is present as a **Note aside** on `AVAudioPlayer.rate`:

> **"Adjusting the audio's playback rate doesn't alter its pitch."**

The same page confirms the other two facts this unit depends on:

> *"This property supports values in the range of `0.5` for half-speed playback
> to `2.0` for double-speed playback."*

and, on `enableRate`:

> *"To enable modifying the player's rate, set this property to [true] after you
> create the player, but before you call [prepareToPlay]."*

**A CORRECTION TO MY OWN EARLIER REPORT.** I previously reported this page as
"silent on pitch". **That was wrong, and it was my extraction at fault, not the
documentation:** I printed only top-level `paragraph` nodes, and the sentence sits
inside an `aside` node. **The evidence was there and I failed to read it.**

**THE EVIDENCE FOR LOCAL AUDIO IS APPLE'S DOCUMENTED API CONTRACT, NOT A
LISTENING TEST.** No perceptual evidence is claimed anywhere in this unit, and
none must be.

**For the `AVPlayer` stacks the evidence is the installed SDK header**, already
recorded in the scope: `audioTimePitchAlgorithm` defaults to `TimeDomain` on
iOS 15+, and `Spectral` is documented as *"often the best choice … assuming that
it is desirable to maintain a constant pitch"*.

## 2. APPROVED PRODUCT SEMANTICS

Rates **0.5× · 0.75× · 1× · 1.5× · 2×**, default **1×**; **ephemeral per viewer
session**; persists while paging; resets to 1× on viewer close/reopen;
pause/resume preserves it; **media is never modified**.

## 3. THE THREE INTEGRATIONS — no shared abstraction

| stack | mechanism |
|---|---|
| local audio (`AVAudioPlayer`) | `enableRate = true` **before** `prepareToPlay()`; then `player.rate` |
| video (`AVPlayer`) | `playImmediately(atRate:)` on start/resume; `player.rate` while playing; `.spectral` on the item |
| remote audio (`AVPlayer`) | same as video |

**`AVPlayer.play()` sets rate to 1.0**, so it must not be used to resume — that is
the hazard identified in the scope and the reason for `playImmediately(atRate:)`.

**Deliberately NOT built:** a shared player protocol. Three small integrations are
less risk than one abstraction over three genuinely different APIs.

## 4. UI AND ACCESSIBILITY

Compact `Menu` in each **existing** transport row, reusing `mediaControlButton`.
Button face shows the current rate. Selected rate uses the **normal checkmark
treatment** (`Picker`-in-`Menu` or `Label` with a checkmark) — **no "Normal"
terminology**. No slider, no settings screen.

- label **"Playback speed"**
- value **"0.75 times"** etc.
- hint **"Choose a playback speed"**

**One wording note:** for consistency the 1× value speaks as **"1 times"**. Slightly
stilted, but it avoids introducing the "Normal" terminology that was explicitly
excluded. Easy to change to "normal speed" for the accessibility value alone if
preferred.

## 5. PREDICTED DIFF

| file | change |
|---|---|
| `MOTIVO/PlaybackRate.swift` (new) | pure enum: five cases, display strings, accessibility strings, default — **no player types**, so it is unit-testable |
| `MOTIVO/AttachmentViewerView.swift` | one `@State` in the viewer; `@Binding` through `MediaPage` (which already takes several bindings); one menu per transport row; the three integrations above |
| `MOTIVOTests/PlaybackRateTests.swift` (new) | model + structural tests |

**Nothing else.** No `PracticeTimerView`, no `MediaTrimView`, no media mutation,
no change to seek/reset semantics beyond preserving rate.

## 6. PREDICTIONS

| # | prediction |
|---|---|
| P1 | five rates, ordered, default `1×` |
| P2 | display strings `0.5× 0.75× 1× 1.5× 2×` — **`1×`, not `1.0×`** |
| P3 | accessibility label/value/hint as §4 |
| P4 | rate is viewer-session state: persists across paging, resets on a new viewer |
| P5 | `AVPlayer` paths resume via `playImmediately(atRate:)`; **no bare `play()` on a resume path** |
| P6 | `enableRate` is set **before** `prepareToPlay()` |
| P7 | `.spectral` set on both `AVPlayer` items |
| P8 | existing seek/reset/position semantics unchanged |
| P9 | Debug and Release build clean |
| P10 | full `MOTIVOTests` passes |
| P11 | **zero** new warning kinds |
| P12 | no production / ASC mutation |

## 7. EVIDENCE BOUNDARY

Tests prove the **rate model**, the **state semantics** and the **structural
integration**. **They do not prove that audio sounds pitch-correct** — that rests
on Apple's documented contract (§1), and **must not be described as measured or
device-verified.**
