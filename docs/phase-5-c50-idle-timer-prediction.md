# P5-K / C-50 — IDLE TIMER DURING RECORDING: PREDICTION

**Committed BEFORE any product mutation, 2026-09-09.**

## 1. The invariant

**An active practice recording must not be interrupted merely because the device
reaches its normal Auto-Lock timeout.**

## 2. Evidence already held

Device-observed 2026-08-14 on Device A during the C-3 run, with a **controlled
discriminator**: Auto-Lock at 30 s reproduced the interruption; Auto-Lock at
Never removed it. **Re-verified 2026-09-09: `isIdleTimerDisabled` appears
NOWHERE in `MOTIVO/`** — so this is a **gap, not a broken implementation**.

## 3. THE LIFECYCLE, READ BEFORE DESIGNING

**There are TWO independent recorders**, and they are shaped differently:

| | `AudioRecorderView` | `VideoRecorderView` |
|---|---|---|
| state | `@State private var state: RecordingState` (**View struct**, `:43`) | `@Published var state: RecordingState` on `VideoRecorderController` (**class**, `:321`) |
| assignments | 10 | 13 |
| existing single hook | **YES** — `.onChange(of: state)` at `:195` fires on **every** transition, and `onDisappear` posts `false` at `:189` | **NONE** |
| teardown resets state? | effectively yes, via `onDisappear` | **NO** — `onDisappear` (`:497`) stops the session but **never sets `state = .idle`** |

**So the smallest lifecycle is NOT a new subsystem, and it is NOT one hook:**

- **Audio already has the exact single owner.** `.onChange(of: state)` already
  computes `newState == .recording` and broadcasts it. The idle-timer call goes
  **alongside that existing call**, plus the existing `onDisappear`.
- **Video's single owner is `state`'s `didSet`**, which covers all 13 assignment
  sites at once — including the error and cancel paths, which each set
  `state = .idle`.
- **Video needs one extra restore in `onDisappear`**, because teardown while
  recording leaves `state == .recording`. **This is precisely the "torn down
  while recording state is active" case** and it is reachable only in the video
  recorder.

## 4. WHY A TINY SHARED OWNER, AND WHY IT IS NOT A SUBSYSTEM

`UIApplication.shared.isIdleTimerDisabled` is **one global flag with two
independent writers**. If each recorder set it directly, one recorder's
"restore" could clear the other's "hold".

So: **one small reference-counted holder** (`RecordingIdleTimerGuard`), with
`hold(_:)` / `release(_:)` keyed by an owner token, that writes the UIKit flag
only when the set of holders becomes non-empty or empty.

**It is deliberately NOT** an app-wide "activity" framework, not a manager
injected into the environment, and not observed by anything. One type, two
methods, used by two call sites each.

## 5. SEMANTICS

| event | idle timer |
|---|---|
| recording genuinely begins (`state == .recording`) | **disabled** |
| recording ends successfully | **restored** |
| cancel | **restored** |
| recording/setup failure | **restored** |
| view/controller torn down while recording | **restored** |
| paused recording | **restored** — see below |

**`pausedRecording` deliberately does NOT hold the timer.** No samples are being
captured, so the invariant does not apply, and holding it would let a paused
recorder keep the screen awake indefinitely — the "app permanently prevents
Auto-Lock after an abnormal path" failure this unit exists to avoid. **If a
paused recording later proves to be interrupted by lock on resume, that is a
separate finding with its own evidence.**

## 6. PREDICTED DIFF

| file | change |
|---|---|
| `RecordingIdleTimerGuard.swift` (new) | ~30 lines: reference-counted hold/release around `isIdleTimerDisabled`, `#if canImport(UIKit)`, `@MainActor` |
| `AudioRecorderView.swift` | idle-timer call alongside the **existing** `.onChange(of: state)` and `onDisappear` |
| `VideoRecorderView.swift` | `didSet` on `state`; one restore in `onDisappear` |
| `MOTIVOTests/…` | lifecycle tests on the guard |

**NOT touched:** capture pipelines, writer/session code, timers, UI layout,
transport controls, `PracticeTimerView`, `MediaTrimView`, or any recording
behaviour other than the idle timer.

## 7. PREDICTIONS

| # | prediction |
|---|---|
| P1 | pre-fix, `isIdleTimerDisabled` occurs **0** times in `MOTIVO/` |
| P2 | post-fix, the flag is **held** while `state == .recording` and **released** on every exit — success, cancel, failure, teardown |
| P3 | two overlapping holders: releasing one does **not** clear the other's hold |
| P4 | releasing an unknown/duplicate token is **idempotent** and cannot drive the count negative |
| P5 | Debug and Release build clean |
| P6 | full `MOTIVOTests` passes |
| P7 | **zero** new warning kinds |
| P8 | no production / ASC / device mutation |

## 8. EVIDENCE BOUNDARY — STATED UP FRONT

**Unit and structural tests CANNOT prove the device stays awake.** They prove the
guard's lifecycle and that the flag is written. **C-50 will therefore be recorded
as `implementation complete; physical-device behavioural confirmation
outstanding`, and MUST NOT be described as device-verified.** The device test is
specified in the acceptance record.
