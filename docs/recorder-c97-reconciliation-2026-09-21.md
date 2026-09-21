# C-97 recorder work — reconciliation, and a bounded residual scope

**21 September 2026. Claude, read-only.** Source read at `b479487` (pushed; `HEAD` and
`origin/feature/solo-connected` agree). **No implementation, no commit, no push, no server,
device, purchase or reset action.** Protected and unrelated documents untouched.

**Method:** the C-97 register row and the Phase 6 checkpoints were read, and then **every claim
below was checked against the code rather than inherited from the record.** Line references are
`MOTIVO/VideoRecorderView.swift` unless stated.

**Nothing here is a reproduced defect.** No silent video, no blocked start and no armed-state
misbehaviour has been observed on a device. That distinction governs §4.

---

## 1. COMPLETED — verified in code, not to be redone

| # | Item | Evidence in source |
|---|---|---|
| C1 | **Capture runtime-error observer** | `AVCaptureSession.runtimeErrorNotification` → `.captureRuntimeError` (`:1878`) |
| C2 | **Capture interruption began / ended observers** | `:1879`, `:1880` |
| C3 | **Media-services-reset observer** | `AVAudioSession.mediaServicesWereResetNotification` (`:1776`) |
| C4 | **`CaptureDisruptionTracker` and its gating** | `:350`; new capture refused while `blocksNewCapture` (`:897`, `:1243`) |
| C5 | **Pending-start cancellation across all six stages** | `requestPendingStartCancellation` (`:2020`), `handleSessionStartReturn` (`:1976`), claim resolution on `writerQueue` (`:1972`) |
| C6 | **`pendingStartRecordingToken` deleted** | absent from source |
| C7 | **Audio recorder's own interruption + reset observers** | `AudioRecorderView:680`, `:686` — a separate, already-handled path |

**Also accepted and not reopened:** the CM-15, Bluetooth, drone and video regressions to their
stated limits, and part (1)'s first physical evidence (QA7, 2026-09-17). **The extra drone-unplug
run is waived.** None of the above is proposed for change.

---

## 2. RESIDUAL — the four candidates, each measured

### R1 — the video path discards its input-preference result, and a tested verifier already exists

**This is the finding that most changes the shape of the work.**

`RecordingInputPolicy` already provides `verify(_:)` and `applyAndVerify(_:)`
(`RecordingInputPolicy.swift:38`, `:44`), which compare the **effective route**
(`currentRoute.inputs`, `:61`) against the USB-first preference. **The AUDIO recorder uses it
and throws on failure** (`:77`, `AudioRecordingAttempt.begin` `:93`).

**The VIDEO path does not.** It calls `try? session.setPreferredInput(...)` at `:1688`, `:1690`,
`:1713`, `:1717` — **four sites, result discarded** — and reads `currentRoute` **only inside
`#if DEBUG`** (`:2465`). So in a Release build nothing checks which input the video recorder
actually got.

**So R1 is REUSE of existing, tested code on a second caller, not new machinery.**

**CORRECTED 21 September 2026 — I had this wrong, and Codex caught it.**

An earlier revision said *"`applyAndVerify` calls `configureForAudioRecording()`, which sets the
audio-session category"*. **It does not.** `applyAndVerify`
(`RecordingInputPolicy.swift:44`) resolves the desired port, conditionally calls `prefer(_:)`
and then `verify(_:)`; the category is configured **separately** by
`AudioRecordingAttempt.begin` (`:87`), which calls `configureForAudioRecording()` itself before
delegating. **The claim is withdrawn.**

**The conclusion is unchanged, for a different and correct reason:** `applyAndVerify` still
**mutates the preference** via `prefer(_:)`, and this unit is observability only. **Only the
read-only `verify(_:)` is used**, and no category, option, activation or preference write is
added anywhere.

**Also corrected:** the four `setPreferredInput` statements are **not four independent
verification points.** They are **two alternative branches in each of two paths** —
`preactivateRecordingAudioSessionIfNeeded` (`:1672`, body on a background queue) and
`applyPreferredRecordingInput` (`:1708`, `@MainActor`). **One observation per path, after its
selection attempt, including the case where neither port is available.**

### R2 — `isArmedToRecord` is written from main and read/written from the capture queue

**Confirmed by enclosing function, not by grepping the name:**

| Site | Enclosing function | Queue |
|---|---|---|
| `:1272` writes `true` | `startRecording()` (`:1240`) | main / UI |
| `:2204` reads, `:2240` writes `false` | `handleVideoSampleBuffer(_:)` (`:2190`) | capture / sample delivery |

A plain `var`, unsynchronised, across two queues. **It is a genuine data race by construction.**
**No misbehaviour has been observed**, and the pending-start claim added beside it is
`writerQueue`-resolved and does not depend on it.

### R3 — a permanently blocked `startSession` occupies a serial queue for the controller's life

`sessionStartQueue` is serial (`:456`) and `startSession(atSourceTime:)` is dispatched onto it
(`:1128`, `:1150`). **There is no timeout, watchdog or recovery anywhere** — the only
`asyncAfter` calls are a 0.01 s hop (`:991`), a 0.4 s debounce (`:1045`) and a 5 s writer-queue
follow-up (`:1422`), none of which watches this.

If that call never returns, **no later start's writer session can begin.** Whether it can block
permanently on a device is **unknown and unobserved.**

### R4 — nothing verifies that audio samples actually arrive

No counter, timestamp or arrival check exists on the audio path of the capture writer; the only
read of the live route is the `#if DEBUG` print at `:2465`. **A camera-ready screen still does
not prove a working soundtrack** — the register's original wording, still true.

---

## 3. NOT REPRODUCED — stated so it is not quietly upgraded

**None of R1–R4 has produced an observed failure.** Specifically: no silent video has been
recorded; no blocked `startSession` has been seen; no armed-state corruption has been reported;
and the QA of 2026-09-20 exercised the **arm path only**, not any cancellation path. The
2026-09-21 recorder runs were regression sequences, not fault injection.

**No test drives a real `CMSampleBuffer` or a genuinely blocking AVFoundation call**, so hardware
timing remains uncovered by the suite.

---

## 4. PROPOSED SCOPE — tiered, and deliberately smaller than the candidate list

### APPROVED AND IMPLEMENTED — R1, as amended by Codex

**Input-route OBSERVABILITY only. Not a reliability defect fixed, and not proof of a
soundtrack.** See `docs/recorder-reliability-codex-review-2026-09-21.md` §Scope review for the
amendments, and `docs/recorder-r1-evidence-2026-09-21.md` for what was built and measured.

- **Two observation points, one per path**, after each path's selection attempt, including the
  no-preferred-input case.
- **`verify(_:)` only.** No `applyAndVerify`, no `prefer`, no category, option or activation
  write. First-use audio behaviour and `automaticallyConfiguresApplicationAudioSession` are
  untouched.
- **The preactivation observation is DEFERRED to main and labelled as such** — the verifier is
  `@MainActor` and that path's body runs on a background queue. It is **not** an atomic reading
  at selection time, and no blocking dispatch is introduced.
- **Release-enabled local diagnostic** for match, mismatch and unavailable, carrying **stage and
  port TYPES only**. No UID, name, account data, recording content, remote telemetry or
  per-buffer logging.
- **A mismatch is a point-in-time observation**, never a refusal, retry or user-facing warning.

### Recommended NOT to implement yet — R2, R3, R4

| # | Why not now |
|---|---|
| **R2** | It is a real race, but the fix sits in the **sample-delivery path**, where a confinement or lock changes timing on the one path with no test coverage. It deserves its own measured unit, not a ride-along. **A full concurrency audit remains separately scoped** |
| **R3** | A watchdog needs an invented timeout and a recovery action, and a wrong one **tears down a good take**. With no observation of the condition, the threshold would be a guess |
| **R4** | The same objection, more sharply: audio legitimately has no samples in the first moments, so a naive watchdog reports a defect that is not there. Needs a measured arrival profile first |

**This is the point of the reconciliation: three of the four candidates are gaps that want
EVIDENCE before code, and proposing fixes for all four would be treating a gap as a defect.**

### If Codex prefers a second unit now

**R2 is the next-safest**, and its smallest honest form is a **measurement, not a fix**: an audit
recording every read and write of `isArmedToRecord` with its queue, so the confinement can be
designed against a complete list rather than a grep. I would not fix it in the same unit as R1.

---

## 5. Validation for R1, if approved

Targeted suites by actual XCTest class name; one final full `MOTIVOTests` run plus Debug and
Release builds; warning delta by attribution; every run `tee`d and the bundle copied out of
`DerivedData`; test accounting as new/converted/retired/unchanged; a positive control that
removes the verification and watches the new assertion fail. **No device QA by me** — Samuel
runs it, and R1's whole value is that his next run can report the effective input.

## 6. Out of scope

Any change to `automaticallyConfiguresApplicationAudioSession`, the audio-session category or
options, or first-use audio behaviour; any watchdog, timeout or recovery; any change to the
shipped observers, the tracker or the pending-start cancellation; R2/R3/R4 implementation; age,
sharing, server, device, purchase or reset work; any commit or push.

**Scoped to Codex before implementation. Nothing implemented.**
