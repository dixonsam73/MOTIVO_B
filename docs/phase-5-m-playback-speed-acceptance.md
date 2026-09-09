# P5-M — PLAYBACK SPEED: ACCEPTANCE

**COMPLETE 2026-09-09.** Scored against
`docs/phase-5-m-playback-speed-prediction.md`, committed at `6d7ea64` **before**
any product mutation.

## 1. Results

| # | prediction | actual |
|---|---|---|
| P1 | five rates, ordered, default 1× | ✅ |
| P2 | `1×`, not `1.0×` | ✅ |
| P3 | accessibility label / value / hint | ✅ |
| P4 | viewer-session state: persists across paging, resets on a new viewer | ✅ structurally |
| P5 | `AVPlayer` resumes via `playImmediately(atRate:)`, **no bare `play()`** | ✅ both stacks |
| P6 | `enableRate` before `prepareToPlay()` | ✅ |
| P7 | `.spectral` on both `AVPlayer` items | ✅ |
| P8 | existing seek/reset semantics unchanged | ✅ asserted |
| P9 | Debug / Release | **both BUILD SUCCEEDED** |
| P10 | full suite | **114 passed, 0 failed** — see §4 |
| P11 | new warning kinds | **25 → 25, zero** |
| P12 | production / ASC mutation | **none** |

## 2. The three integrations

| stack | mechanism |
|---|---|
| local audio (`AVAudioPlayer`) | `enableRate = true` **before** `prepareToPlay()`, then `rate`. Survives pause/resume by itself |
| video (`AVPlayer`) | `playImmediately(atRate:)` to start/resume; `rate` while playing; `.spectral` on the item |
| remote audio (`AVPlayer`) | same |

**No shared player abstraction was created.** Three small integrations over three
genuinely different APIs.

**Pitch:** Apple documents, on `AVAudioPlayer.rate`, *"Adjusting the audio's
playback rate doesn't alter its pitch."* For the `AVPlayer` stacks `.spectral` is
set explicitly. **THIS IS A DOCUMENTED API CONTRACT. No listening test was
performed and no perceptual or device evidence is claimed.**

## 3. THE STRUCTURAL TEST THAT FAILED AGAINST CORRECT CODE

`testEnableRatePrecedesPrepareToPlay` failed on a correct implementation. The
**comment** explaining that `enableRate` must precede `prepareToPlay()` *mentions*
`prepareToPlay()`, and it sits above the call — so an ordering assertion over raw
source found the comment first.

**The file explaining the rule defeated the check for the rule.** This is
`U5c-34`'s failure, recorded again in U5d, and now a third time. The structural
tests now read a **comment-stripped** copy of the source, and the reason is
written next to the helper so the next person does not rediscover it.

## 4. FULL-SUITE FLAKINESS — REPORTED, NOT SWEPT

The **first** full-suite run after this unit showed **115 passed / 1 failed** —
`SharedOnlyUploadTests.testSharedThenUnsharedRemovesRow()`. **It is not a P5-M
regression, and that was established rather than assumed:**

- it **passes twice in isolation with P5-M applied**;
- the **second** full-suite run was **114 passed / 0 failed**, no code change;
- the two runs **executed different numbers of tests — 116 then 114**.

That last point is **C-64's original signature**, so C-64 has been **widened**: the
phenomenon now covers a **second suite** and a **second symptom** — intermittent
*failure*, not only intermittent *non-execution*. Both suites are local-stack
dependent, so neighbouring-test state is the leading hypothesis; it is **untested
and deliberately not asserted**.

## 5. Scope held

Touched: `AttachmentViewerView.swift`, new `PlaybackRate.swift`, new tests.
**Not touched:** `PracticeTimerView` (C-3, C-56), `MediaTrimView`, media files,
seek/reset semantics, the general transport accessibility debt (**C-67**, filed
into P5-N).

## 6. Not claimed

No device verification. The control has not been operated by a human, and the
audio has not been listened to. **A device pass would sensibly ride along with
C-50's outstanding one:** change rate mid-playback, pause/resume, page between
attachments, reopen the viewer, and confirm VoiceOver reads
"Playback speed, 0.75 times".
