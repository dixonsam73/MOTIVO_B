# C-88 — clearing notes while a publish is queued can republish the old notes. Prediction, before any test or change

2026-09-15. Scope approved in Codex scope review 003; recorded in
`claude-scope-003.md` in the coordination folder. Weekend audit finding A3.

## 1. Source inspection (to be confirmed by the failing-first run)

- **Only live producer that sets notes:** `PublishService.publish(payload:objectID:shouldPublish:)`.
  The editor views save notes to Core Data; the service rebuilds the **payload**
  notes from the saved `Session`.
- On a successful read it turns empty or whitespace notes into `nil`, and an
  actual-nil `notes` stays `nil`. The queue merge reads `nil` as "unspecified"
  (`payload.notes ?? existing.notes`) and keeps the old privacy flag with it — so
  an explicit clear, made while a publish is still queued, is lost before
  `uploadPost` / `patchPostMetadata` see it.
- **Recorded discrepancy:** the `catch` comment promises to keep the incoming
  payload unchanged, but the code starts from `nil`/`false` and uses those defaults
  on failure.
- **Contract boundary:** `nil` as "unspecified" is a producer/queue-merge rule. The
  metadata PATCH always writes notes (NULL for nil), so no claim is made that a
  partial payload leaves server notes untouched.
- Unreachable legacy producers (`publishIfNeeded`, `publish(objectID:)`,
  `unpublish(objectID:)`, `FeedInteractionStore.markForPublish` /
  `enqueueForPublish`) are left in place.

## 2. Change

Only the notes/privacy enrichment in `MOTIVO/PublishService.swift`: start from the
incoming payload's values; when the Session and its `notes` attribute are resolved,
use the trimmed saved value with **empty, whitespace or nil as `""`** (explicit
clear) and the saved privacy flag; on failure keep the incoming values. Log field
distinguishes present/empty/nil. `SessionSyncQueue.swift`, `BackendShim.swift`,
views, model and every other surface unchanged.

## 3. Predictions

Tests: `MOTIVOTests/NotesClearPublishTests.swift` —
`NotesClearProducerQueueTests` (local simulation; not an offline-network test) and
`NotesClearEndToEndTests` (local backend, offline network via `127.0.0.1:1`).

**Before the fix, exactly these fail:** P-1 (`""` clear), P-2 (whitespace clear),
P-3 (nil clear), P-4 (clear + private), P-8 (failure keeps incoming notes/privacy),
P-10 (pending clear survives the queue file), E-1 (first publication after a queued
clear), E-2 (same, + private), E-3 (existing row with old notes, cleared through the
metadata PATCH), E-4 (same, + private).

**Passing before and after:** P-0 preconditions, P-5 text replacement, P-6 privacy
toggle with existing text, P-7 unspecified partial payload keeps the queued value,
P-9 / P-9b a failure with unspecified notes is never a clear, P-10b legacy payload
without notes decodes as `nil`.

**After the fix:** all of the above pass; queue ordering/reset, consent and
payload-compatibility regressions unchanged; one full app suite with every declared
test executed, all passing except the three queue reproduction skips.

Any miss is recorded as a miss and diagnosed before a further run.

## 4. Failing-first run 1 — before any product change (recorded before the next run)

`PublishService.swift` unchanged (sha256 `b0b098a6…`, matching Codex's scope
baseline). Evidence `claude-evidence/c88/before/run-1/`. Census from the result
bundle: **16 executed, 6 passed, 10 failed, 0 skipped.**

- **Met, on the assertion under test:** P-1, P-2, P-3 and P-4 each queued `"old"`
  (P-4 also `false`) after the clear, with their P-0 preconditions passing; P-8 queued
  `nil`/`false`; P-10's queue file held `"old"`/`false`; E-1 and E-2 published a row
  whose notes were `"old"`, with every precondition passing. P-5, P-6, P-7, P-9, P-9b
  and P-10b passed.
- **MISS — E-3 and E-4 failed for the wrong reason.** Both stopped at their first
  step: *"the publish task never merged the save titled E-3-1"* (E-4-1). That step is
  an ONLINE publish, which flushes and dequeues at once, so waiting for the queued
  title was a fixture defect. **Neither reached the existing-row assertion, so the
  pre-fix failure of the metadata-PATCH path is NOT established by this run.** The
  id-level match with the predicted set is coincidental for these two and is not
  counted.
- **Correction, test fixture only:** the online step now waits for the server row
  with the old notes. No product code has changed. E-3/E-4 are re-run before the fix.

## 5. Failing-first run 2 — E-3/E-4 only, still before any product change

Evidence `claude-evidence/c88/before/run-2/`; `PublishService.swift` still `b0b098a6…`.
**2 executed, 0 passed, 2 failed.** Each failed with exactly one message, on the
assertion under test: *"server notes must be JSON null after the clear, found
Optional(old)"*. Their preconditions passed: the row existed with `"old"` and the
queued offline edit carried `"old"`. The `title == "E-3-3"` / `"E-4-3"` assertion
passed, so the metadata PATCH did reach the existing row and wrote the old notes
back. **The pre-fix failure of the existing-row path is now established.** The log
also records one simulator-clone launch denial (`FBSOpenApplicationServiceErrorDomain
Code=1`) before the tests ran; both tests executed, and it is noted, not scored.

With runs 1 and 2 together, all ten predicted pre-fix failures are observed on their
own assertions, and the six predicted passes passed.

## 6. After the fix — focused and regression run

Only the enrichment in `PublishService.swift` changed (diff
`claude-evidence/c88/after/PublishService.diff`). Evidence
`claude-evidence/c88/after/focused/`. **51 executed, 48 passed, 3 skipped, 0 failed**
(result bundle census).

- All 16 C-88 tests pass: P-1…P-10b and E-1…E-4.
- Unchanged regressions pass: `SyncQueueIntentAcceptanceTests` 4/4,
  `SyncQueueFactoryResetTests` 2/2, `PublishConsentCarriageTests` 4/4,
  `QueuePayloadCompatibilityProbe` 5/5, `UnshareDurabilityTests` 12/12,
  `SharedOnlyUploadTests` 5/5.
- `SyncQueueOrderingReproductionTests` 3 skipped, each "sequence not exercised",
  exactly as before this unit.

Every prediction in §3 met.

## 7. After the fix — one full app suite

Evidence `claude-evidence/c88/after/full/` (`full.xcresult`, `summary.json`,
`executed.txt`, `reconciliation.txt`, `declared-vs-executed.txt`,
`uitests-and-parallelism.txt`). xcodebuild exit 0; bundle result **Passed**.

| Scope | Declared | Executed | Passed | Skipped | Failed |
|---|---|---|---|---|---|
| Whole run (scheme default: `MOTIVOTests` + `MOTIVOUITests`) | **454** | **454** | **447** | **7** | **0** |
| `MOTIVOTests` only (C-100's P5 scope) | **450** | **450** | **446** | **4** | **0** |
| `MOTIVOUITests` | 4 | 4 | 1 | 3 | 0 |
| C-100 P5, retained for comparison (`MOTIVOTests`) | 434 | 434 | 431 | 3 | 0 |

**Per-name reconciliation against C-100's `full.xcresult`:** nothing in C-100's run is
missing from this one; this run adds exactly the 16 `NotesClear*` tests (all passed)
and the 4 `MOTIVOUITests` tests; **one test changed result**. Declared-by-name from
source equals executed-by-name (four methods live in `extension` blocks and were
checked by hand). 15 swift-testing tests declared and executed.

**Two misses against §3, recorded as misses:**

1. **Scope.** §3 predicted "434 + the new tests" against C-100's run, but C-100's P5
   was `MOTIVOTests` only, and this run used the scheme default, which also builds and
   runs `MOTIVOUITests`. That adds 4 executed: `MOTIVOUITestsLaunchTests.testLaunch`
   passed; `AccessibilityAndPersistenceTests.testBackgroundTimerPath`,
   `testEditSessionDescriptionPersists` and `testPrimaryActivityFallbackOnHideOrDelete`
   skipped on their own preconditions ("Timer not present", "No sessions available to
   open.", "Activity Manager not available"). No C-88 file touches that target. On
   C-100's scope the prediction was met in count.
2. **One unrelated skip.** `UnshareDurabilityTests.testUnshareRemovesAttachmentsAndUploadsNothing`
   passed in C-100's run but **skipped** here, "local Supabase stack not reachable".
   Measured: its duration was 5.006 s, which equals the probe's 5-second wait, so the
   probe got no answer; it ran on simulator clone 1 while clones 2 and 3 were running
   local-stack suites (including E-3/E-4); every other local-stack test in the run
   passed; the stack answered its health check in 0.018 s afterwards. **Inferred, not
   proven:** a probe timeout under parallel load. **Its assertions did not execute in
   this run.** It exercises the unshare path, which C-88 does not change, and it passed
   in §6's after-fix focused run (12/12). Not rerun: no additional run was requested.

**This was one run following the fix, not a rerun until green.**

## 8. Release build

`xcodebuild … -configuration Release -destination "generic/platform=iOS Simulator"
build`: **BUILD SUCCEEDED**, exit 0, no warning or error in `PublishService.swift`.
Evidence `claude-evidence/c88/after/release-build/`. Tests and builds for this unit
are finished.
