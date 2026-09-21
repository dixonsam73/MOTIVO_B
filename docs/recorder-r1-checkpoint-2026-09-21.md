# C-97 R1 — checkpoint (SUPERSEDED: the work was finished and accepted)

**SUPERSEDED 21 September 2026.** The pause below was lifted: Samuel asked not to waste the work
if worthwhile, Codex authorised a bounded finish, the seven corrections were applied and
**Codex granted FINAL LOCAL ACCEPTANCE**. See `docs/recorder-r1-evidence-2026-09-21.md`.

**Still true, and the reason this file is kept:** nothing was committed then and nothing is
committed now, and the two corrections recorded below — `applyAndVerify` not configuring the
category, and `VideoRecorderController` not being `@MainActor` — are unchanged.

**The record of the pause follows as written.**

---

# C-97 R1 — PAUSED at a safe checkpoint

**21 September 2026.** Paused on Codex's instruction while Samuel's challenge to R1's value is
reviewed against the roadmap and release documents. **Nothing is committed, nothing is running,
and no further build or scope was started after the pause.**

## State

- **Working tree is clean of every deliberate control edit.** Control I (an early return
  restored so the no-input case would be skipped) was reverted and **verified byte-identical**
  against `controls/pre-control-hashes.txt`; a sweep for control text returns zero.
- **No `xcodebuild` or other process is running.**
- `HEAD` = `b479487`, equal to `origin/feature/solo-connected`. **Nothing committed.**

## Files this R1 work changed — the complete list

| File | State |
|---|---|
| `MOTIVO/RecordingRouteObservation.swift` | **NEW, untracked.** The diagnostic: stages, outcomes, sink protocol, `os.Logger` sink, and `observe(_:stage:sink:)` which classifies through `RecordingInputPolicy.verify` |
| `MOTIVO/VideoRecorderView.swift` | **MODIFIED.** Two observation call sites; `applyPreferredRecordingInput` given a single exit so the no-input case is covered; one injectable `routeObservationSink` property |
| `MOTIVOTests/RecordingRouteObservationTests.swift` | **NEW, untracked.** 13 tests across two classes |
| `docs/recorder-c97-reconciliation-2026-09-21.md` | **NEW, untracked.** Reconciliation + matrix, with my `applyAndVerify` error corrected |
| `docs/recorder-r1-checkpoint-2026-09-21.md` | **NEW, untracked.** This file |

**No other source or test file was touched by R1.** `docs/recorder-reliability-codex-review-2026-09-21.md`
is Codex's and was only read.

## Where it had got to

Implemented and green: **13 tests passed** (match, built-in match, mismatch, unavailable, empty
session, no-mutation across all four outcomes, policy agreement, types-not-identifiers, plus
five wiring assertions). Debug built clean. **Control I discriminated correctly** — it failed
exactly `testThePreferencePathHasASingleExitSoTheNoInputCaseIsObserved` and nothing else.

**Not done:** the full suite, Release build, remaining controls, evidence document, device QA
plan. **No acceptance was given and none is claimed.**

## Two corrections made during implementation, worth keeping whatever is decided

1. **`applyAndVerify` does NOT configure the audio-session category.** I had written that it
   did; `AudioRecordingAttempt.begin` calls `configureForAudioRecording` separately. Codex
   caught it. The reconciliation is corrected in place with the claim withdrawn. The conclusion
   survives for a different reason: `applyAndVerify` still mutates the preference.
2. **`VideoRecorderController` is NOT `@MainActor`** — the annotation in that file belongs to
   `StagingStoreObject`. I had assumed the preference path could observe at selection time;
   **the compiler caught it.** Both observations are deferred to main, and both stage names now
   say so.

## Carried, untouched

**C-97 R2** (the `isArmedToRecord` cross-queue race), **R3** (a permanently blocked
`startSession`), **R4** (a missing-audio watchdog) — none addressed by a route measurement, and
a full concurrency audit remains separately scoped. Previously accepted first-use setup, the
shipped observers and cancellation, and the waived device checks are all unchanged.

## On the challenge itself

**Samuel's point is fair and I should record it plainly rather than defend the work.** R1 was
always observability, never a fix: it repairs no reproduced defect, and after extensive
successful device QA its value is the ability to say in Release which input the recorder
actually got. That is worth something only if the route is still a live question. **If the
roadmap says it is not, the right outcome is to drop it, and the two corrections above are the
part worth keeping.**

**Holding. No further work until directed.**

---

## Outcome

Work resumed under a bounded finish and was accepted locally. The files listed above are
unchanged in number; `MOTIVOTests/RecordingRouteObservationTests.swift` grew by three capture
tests, and `routeObservationSink` was removed from the controller. `docs/recorder-r1-evidence-2026-09-21.md`
carries the acceptance, the corrections and the limits.
