# P5-K / C-50 — IDLE TIMER DURING RECORDING: IMPLEMENTATION ACCEPTANCE

**IMPLEMENTATION COMPLETE; PHYSICAL-DEVICE BEHAVIOURAL CONFIRMATION
OUTSTANDING. 2026-09-09.**

Scored against `docs/phase-5-c50-idle-timer-prediction.md`, committed at
`4f91c25` **before** any product mutation.

**THIS UNIT IS NOT DEVICE-VERIFIED AND MUST NOT BE DESCRIBED AS SUCH.** §5 is the
outstanding step.

## 1. Results

| # | prediction | actual |
|---|---|---|
| P1 | pre-fix, `isIdleTimerDisabled` occurs 0× | **0** ✅ |
| P2 | held while `.recording`, released on success, cancel, failure, teardown | ✅ |
| P3 | one recorder releasing does not clear the other's hold | ✅ |
| P4 | release is idempotent; cannot strand the flag | ✅ |
| P5 | Debug / Release | **both BUILD SUCCEEDED** ✅ |
| P6 | full `MOTIVOTests` | **102 passed, 0 failed** ✅ |
| P7 | new warning kinds | **25 → 25, zero new** ✅ |
| P8 | production / ASC / device mutation | **none** ✅ |

## 2. The diff is six lines of product code

`AudioRecorderView` +6 and `VideoRecorderView` +16 — **22 insertions, 16 of them
comments, so SIX non-comment lines** — plus `RecordingIdleTimerGuard.swift`.

```
audio:  setHolding(newState == .recording, owner: "audio-recorder")   // existing .onChange
        release("audio-recorder")                                     // existing onDisappear
video:  .onChange(of: controller.state) { … setHolding(…) }           // new hook
        release("video-recorder")                                     // existing onDisappear
```

**No capture pipeline, writer, session, timer, transport control or UI layout was
touched.**

## 3. Lifecycle ownership

**One hook per recorder, at the View layer, in both cases.**

| | owner | why |
|---|---|---|
| audio | the **existing** `.onChange(of: state)` (`:195`) | it already fires on every transition and already computes `newState == .recording`. Nothing new was introduced |
| video | a **new** `.onChange(of: controller.state)` in the View | 13 assignment sites, one hook |
| both | `onDisappear` | teardown |

**A `didSet` on `VideoRecorderController.state` was written first and REJECTED
BY THE COMPILER**: the controller is not main-actor isolated, so it could not
call a `@MainActor` guard, and hopping asynchronously would let two rapid
transitions land out of order. **Hooking the View instead makes both recorders
use the same shape**, which is a better outcome than the original plan.

**Why `onDisappear` is not redundant:** `VideoRecorderController.onDisappear`
stops the capture session but **never sets `state = .idle`**, so teardown while
recording is the one exit `.onChange` cannot see.

**Why reference-counted:** `isIdleTimerDisabled` is one global flag with two
independent writers. Holders are a **set**, not a counter, because lifecycle
callbacks can fire more than once for one recording — so a repeated hold must
not require matching releases.

**`pausedRecording` deliberately does NOT hold.** Nothing is being captured, and
holding it would let a paused recorder keep the screen awake indefinitely — the
permanent-Auto-Lock-prevention failure that would be worse than the defect being
fixed. **If a paused recording is later shown to be interrupted on resume, that
is a separate finding with its own evidence.**

## 4. What the tests do and do not prove

Nine tests cover: hold/release; the `setHolding` shape both call sites use; every
transition away from `.recording` releasing; teardown-while-recording; two
recorders not clearing each other; idempotent release; repeated hold needing one
release; and two structural assertions that both recorders drive the guard and
that neither holds while paused.

**THEY CANNOT PROVE THE DEVICE STAYS AWAKE.** They prove the guard's lifecycle
and that the flag is written.

## 5. THE OUTSTANDING PHYSICAL-DEVICE ACCEPTANCE TEST

**Minimal — one recording and one check afterwards. Not yet authorised; no device
work has been performed.**

**Setup.** Device A, Release build. **Settings → Display & Brightness → Auto-Lock
→ 30 seconds.** Note the previous value to restore it.

**Test 1 — the invariant.**
1. Open Études and start a **video** recording.
2. Do not touch the screen for **at least 90 seconds** (comfortably past 30 s).
3. **PASS:** the screen stays awake and the recording continues uninterrupted.
   **FAIL:** the device locks or the recording is interrupted.
4. Stop the recording and confirm the clip saved normally.

**Test 2 — the failure this must not cause, and it is the more important half.**
5. With the recorder **closed** and the app idle on an ordinary screen, do not
   touch the device for **at least 60 seconds**.
6. **PASS:** the device auto-locks as normal. **FAIL:** Auto-Lock never fires —
   the app is stranding the flag.

**Test 3 — teardown.**
7. Start a recording, then **dismiss the recorder mid-recording** without
   stopping it.
8. Leave the device untouched for **at least 60 seconds**.
9. **PASS:** the device auto-locks. **FAIL:** the flag was stranded by teardown.

**Then restore Auto-Lock to its previous value.**

**Repeat Test 1 once for the AUDIO recorder** — the two recorders take separate
paths, and only the video one was device-observed originally.

**Scoring:** all four observations must pass. **Tests 2 and 3 are not optional
politeness — a stranded flag flattens the battery silently and is a worse defect
than the one being fixed.**
