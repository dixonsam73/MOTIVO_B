# P5-M — TWO DEVICE DEFECTS: TRACE AND FIX PREDICTION

**Committed BEFORE any product mutation, 2026-09-09.** P5-M is
*implementation complete; physical-device verification FAILED*. Audio pre-play
rate application is GREEN and is not touched.

---

## A. FAILURE B — "video ignores the selected rate". **TRACED. CERTAIN.**

**There is a SECOND video play path, and I missed it.**

```
VideoPage.requestPlay()            :2069
    …
    player.play()                  :2084   ← resets rate to 1.0
```

**`requestPlay()` has two callers — `:2034` and `:2233` — and `:2034` is the big
centre play button on the poster/immersive surface.** That is the control a
member naturally uses to start a video.

`togglePlayPause()` (`:2196`) — the **transport-row** play/pause — was fixed and
does use `playImmediately(atRate:)`. **So the rate is honoured only from the small
transport button, and never from the main play button.** The reported symptom is
"video always runs at ~1× regardless", which is exactly this.

**This fully explains B. No further hypothesis is needed.**

**Fix:** `requestPlay()` resumes with `playImmediately(atRate: playbackRate.playerRate)`.
Its deliberate `seek(to: current)` immediately before is unchanged.

---

## B. FAILURE A — "cannot change rate while playing". **STRONGLY INDICATED, NOT PROVEN.**

**The common factor across audio AND video is a high-frequency `@State` write that
only happens during playback:**

| media | driver | rate |
|---|---|---|
| video | `addPeriodicTimeObserver(forInterval: 0.1s)` → writes `currentTime` (`:2295`) | **10 ×/s** |
| audio | `.onReceive(Timer.publish(every: 0.1))` → writes `audioCurrentTime` (`:2871`) | **10 ×/s** |
| audio | waveform timer, `1.0/30.0` (`:3012`) | **30 ×/s** while playing |

**When stopped, these values do not change**, so the transport row is stable and
selection works. **When playing, the view tree containing the `Menu` is rebuilt up
to 30 times a second**, and an open SwiftUI `Menu` is recreated underneath the
member's tap.

**That matches the report exactly:** works stopped, fails playing, both media
types, and the *displayed value* never updates — i.e. **the binding write never
commits**, rather than committing and being reverted.

**RULED OUT by inspection:** nothing is `isPlaying`-conditioned around the rate
state; the `.onChange(of: playbackRate)` handlers only push the value into
players and never write back to the binding; and the video chrome auto-hide
cannot explain the audio case.

**I CANNOT SEPARATE THE TWO SUB-MECHANISMS FROM SOURCE:** (i) the open menu being
torn down by re-render, versus (ii) the `Picker`'s selection binding failing to
commit through a view that is being replaced. **Both are consequences of the same
cause, and the fix below addresses both** — neither part risks the approved UX,
and the targeted device checks will adjudicate.

**Fix, in two minimal parts:**

1. **Extract the control into its own small `View` struct** (`PlaybackSpeedMenu`)
   taking only `@Binding var rate: PlaybackRate`. It then depends on **none** of
   the high-frequency time state, so those writes cannot invalidate it.
2. **Use explicit `Button`s inside the `Menu` instead of `Picker`**, each setting
   the rate directly and showing a **checkmark** on the selected one. A `Button`'s
   action fires on tap; it does not depend on a selection binding surviving a
   rebuild.

**UX IS UNCHANGED:** same five rates, same compact circular control, same face
showing the current rate, same checkmark treatment, no "Normal" terminology, no
slider, no settings screen, same accessibility label/value/hint.

---

## C. WHY THE TESTS PASSED — AND WHAT CAN HONESTLY BE STRENGTHENED

**Failure B — the test was the wrong shape, and this is the lesson.**
`testAVPlayerResumePathsUseRateAwarePlayback` asserted `playImmediately(atRate:`
appears **exactly twice**. It does. **I asserted the PRESENCE OF THE FIX and never
the ABSENCE OF THE DEFECT**, so a third, unfixed play path was invisible to it.

**Strengthened, and this one is genuinely catchable:** assert that
**`player.play()` / `player?.play()` appear ZERO times** in the `VideoPage` and
`RemoteAudioPlayerController` regions. `AVAudioPlayer.play()` in
`AudioPlayerController` stays legitimate and is excluded by region, not by
guesswork.

**Failure A — no structural or unit test could have caught it, and I will not
pretend otherwise.** It is a SwiftUI runtime interaction between a presented
`Menu` and a view rebuilt 10-30 times a second. **There is no assertion over
source text or over a pure model that reaches it.** The honest position is that
this class of defect is only reachable by running the UI, and the three targeted
device checks are the evidence.

**What I can add is a guard against regression of the STRUCTURE**: assert the
control is its own view type and does not read any of the time-state properties.
That is weaker than a behavioural test and is labelled as such.

---

## D. PREDICTIONS

| # | prediction |
|---|---|
| P1 | `requestPlay()` uses `playImmediately(atRate:)`; its `seek` is unchanged |
| P2 | **zero** bare `player.play()` in `VideoPage` and `RemoteAudioPlayerController` |
| P3 | `AudioPlayerController` keeps its `AVAudioPlayer.play()` calls — **untouched** |
| P4 | the speed control is a standalone `View` reading only the rate binding |
| P5 | menu items are `Button`s with a checkmark on the selected rate |
| P6 | five rates, `1×` face, accessibility strings — **all unchanged** |
| P7 | Debug and Release build clean |
| P8 | full `MOTIVOTests` passes |
| P9 | zero new warning kinds |
| P10 | no production / ASC mutation |

## E. WHAT IS NOT CLAIMED

**The fix for A is a hypothesis-driven repair, not a verified one.** If the three
targeted device checks still fail, the cause is something the source does not
reveal, and the next step is instrumentation — **not another speculative edit.**

---

# F. RESULT — 2026-09-09. BOTH FIXED, TESTS STRENGTHENED.

| # | prediction | actual |
|---|---|---|
| P1 | `requestPlay()` uses `playImmediately(atRate:)`, `seek` unchanged | ✅ |
| P2 | zero bare `player.play()` in `VideoPage` / `RemoteAudioPlayerController` | ✅ |
| P3 | `AudioPlayerController` keeps `AVAudioPlayer.play()` | ✅ asserted explicitly |
| P4 | control is a standalone view reading only the rate binding | ✅ |
| P5 | menu items are `Button`s with a checkmark | ✅ |
| P6 | rates, face, accessibility strings unchanged | ✅ |
| P7 | Debug / Release | **both BUILD SUCCEEDED** |
| P8 | full suite | **118 passed, 0 failed** |
| P9 | new warning kinds | **25 → 25, zero** |
| P10 | production / ASC | **untouched** |

**Diff: 71 insertions / 73 deletions in one file** — the two inline menu helpers
were replaced by one shared view, so the file got slightly shorter.

## F.1 THE NEW TEST IS NON-VACUOUS, AND THAT WAS PROVEN

`testNoAVPlayerPathUsesBarePlay` was run against a **deliberately reintroduced
defect** — `requestPlay()` restored to bare `play()` — and **FAILED**, then passed
again once the fix was restored.

**That is the difference between the old test and the new one.** The old one
asserted `playImmediately` appeared twice; it passed while the bug shipped. This
one fails on the actual defect.

## F.2 What is still unproven

**Failure A's fix is hypothesis-driven.** The high-frequency-rebuild explanation
is strongly indicated and the repair is sound on its own terms — but **no test
here can demonstrate that a `Menu` now commits a tap during playback.** Only the
three targeted device checks can.

**If they still fail, the next step is instrumentation, not another edit.**

---

# G. TARGETED DEVICE CHECKS — ALL THREE GREEN. 2026-09-09

Device A / Release, build carrying `2983102`.

| # | check | result |
|---|---|---|
| 1 | audio playing at 1× → select 0.75× → value changes, audibly slows, does not stop | **GREEN** |
| 2 | video stopped → select 0.5× → play → clearly half speed, A/V in sync | **GREEN** |
| 3 | video playing at 1× → select 2× → value changes, clearly accelerates, does not stop | **GREEN** |

**Both defects are fixed on device.** Check 3 exercises both at once: the rate must
commit *during* playback (A) **and** reach the player (B).

## G.1 WHAT THIS PROVES — AND ONE THING IT DOES NOT

**Proved: the repair works.** Rate selection commits during active playback in
both media, and video honours the selected rate from the ordinary play control.

**NOT proved: that my causal explanation was correct.** Failure A's fix changed
**two** things at once — isolating the control into its own view *and* replacing
the `Picker` with `Button`s. **A green result does not say which of them mattered,
or whether the high-frequency-rebuild account was right at all.**

**That is an acceptable trade here** — both changes are minimal, both are
independently defensible, and neither risks the approved UX — but it is recorded
so that nobody later cites this as confirmation of the mechanism. **The mechanism
remains a well-supported hypothesis, not a measurement.**

Failure B carries no such caveat: it was a single, plainly-traced missing call
site, and the regression test fails against its reintroduction.
