# C-99 — concurrent `StagingStore` operations can lose each other's reference updates. Prediction, before any run

2026-09-15. Audit R2. Register row C-99, **Unverified** until this unit's evidence.

- **Scope:** `claude-scope-006.md` as superseded in part by
  `claude-scope-006-revision-1.md`.
- **Approval:** `codex-scope-review-006-revision-1.md`, with execution clarifications
  recorded in §2 **before any run**.
- **Predictions are hypotheses, not results to force.**

## 1. Source inspection at `StagingStore.swift` `26aeaf0f…` (to be tested)

- **Class A — stale-list lost update.** A writer's `loadRefs()` → `saveRefs()` can span
  another writer's commit:
  - background `saveNew` and `replace`;
  - main-actor writers;
  - `removeMany`, which loads, deletes files, then saves **that same list**.
- **Class B — stale-item metadata conflict.** `replace` writes a whole ref built from its
  caller-supplied `ref`, and the same-extension branch writes `ref` unchanged. `update(_:)`
  writes its argument; it has no production caller and is **not changed** here.
- **Class C — file-versus-index races.** Not addressed; residuals R-a, R-b, R-d.

## 2. Execution clarifications (review 006 revision 1) — recorded before any run

1. **Install order.**
   - The isolated root and the hook are installed **before** any worker.
   - The legacy key is snapshotted and **cleared before any store read**.
   - IDs and barrier configuration are generated before workers launch.
   - **Restoration happens only after every test-owned task AND release watcher has
     finished.**
   - Event and cause storage is synchronised (an `NSLock`-guarded log); no ordinary array is
     mutated from concurrent closures. The worker list is mutated only on the main actor.
   - Watchers use GCD only and signal; they never depend on the main actor.
2. **Assertions and validity.**
   - **Behavioural assertions are identical before and after.**
   - Order witnesses are recorded, and the pre-fix validity rules (§4) are applied
     independently. **A failed assertion with invalid overlap is not a reproduced defect.**
   - The 10 s barrier timeout bounds that barrier only, not filesystem stalls or a newly
     introduced lock cycle.
   - **If a run hangs or cleanup cannot join its workers, stop at the isolated checkpoint and
     report.** The override is **never cleared while work could continue**: teardown leaves
     the hook and isolated root in place and marks the class unsafe, and later tests in the
     process refuse to run.
3. **X-5 has its own validity rule.** B is placed before the removal begins, B commits during
   the removal hook, and the removal returns only after that witness. Its main-actor hook
   releases B through a semaphore, with no main-actor dependency. X-1…X-4's rules do not apply
   to X-5.
4. **Stop rules.**
   - **Class A fix only if all five class A reproductions (X-1…X-5) are valid and fail as
     predicted.**
   - **If Y-1/Y-2 disagree with the predictions, stop and report before any class B change.**
   - An inconclusive setup is never a reason to shorten waits, remove assertions, dismiss C-99
     or rerun until green.
5. **Retained limitations.**
   - A replacement whose id is missing, stale file paths, and the destination races are
     **not fixed**.
   - **Removing the same-extension ref write leaves that branch's returned snapshot stale.**
     The only caller uses its path and separately merges duration; no claim is made that every
     returned metadata field is fresh.
   - No caller or UI change.
6. **Runs are sequential** (`-parallel-testing-enabled NO`) for the focused **and** full runs,
   because of the process-global store override. **Predicted counts, not results:** 57
   focused; 481 full, with the existing three queue reproduction skips. The existing local
   backend is health-checked before the full run. **No reset, new manual fixtures or service
   configuration change.**
7. **Files and checkpoints.**
   - Source and test changes are limited to `StagingStore.swift` and the new test file;
     existing tests are unchanged; protected caller, recording and scheme hashes stable.
   - **The seam-only checkpoint is recorded before failing-first**, and the fix diff
     separately.
   - Report 006 only after all work finishes and edits are paused.

## 3. Seam (step 1; write logic byte-identical)

`#if DEBUG` file-scope `enum UnitTestRefsPoint: Hashable` with five cases:
`saveNewPlaced(UUID)`, `saveNewLoaded(UUID)`, `saveNewCommitted(UUID)`, `replaceLoaded(UUID)`,
`removeManyFilesDeleted`.

It adds `StagingStore.unitTestRefsHook` (`nonisolated(unsafe)`) and
`nonisolated static func unitTestReach(_:)`, which calls the hook only when
`UnitTestHost.isActive`.

**Call points:**

| Point | Where |
|---|---|
| `saveNewPlaced` | `saveNew`, before `var list = loadRefs()` |
| `saveNewLoaded` | `saveNew`, immediately after that load |
| `saveNewCommitted` | `saveNew`, immediately after `try saveRefs(list)` |
| `replaceLoaded` | extension-changing `replace`, after its load |
| `removeManyFilesDeleted` | `removeMany`, after `deleteFiles(for: doomed)` |

The C-90 root-override comment names the C-99 class as its second user.

## 4. Synchronisation, validity, scoring

**Release rule (X-1…X-4):**
1. A blocks at its barrier point (10 s timeout).
2. The test awaits "A reached" via GCD; if it never comes, `OverlapNotEstablished`.
3. A GCD watcher waits up to 2 s for B's `bReturned` signal, then logs
   `aReleasedByBReturned` or `aReleasedByWatcherTimeout` and signals the release.
4. B runs: main-actor B synchronously, background B as an awaited task.
5. The test joins the workers and the watcher.

**Common validity (thrown as `OverlapNotEstablished` before the behavioural assertions):**
- `aBarrierReached` precedes `bStarted`;
- for a background B, `bLoaded` follows `aBarrierReached`;
- no `barrierTimeout`;
- the watcher finished.

**Pre-fix validity (scoring rule):**
- `aReleasedByBReturned`, meaning B finished before A's release.
- A pre-fix X test that **passes**, or that has `aReleasedByWatcherTimeout`, is
  **inconclusive**: stop, no scored reproduction.

**Post-fix validity:** no ordering requirement; B may block until the watcher's timeout
release.

**X-5 validity:** `bPlaced` < `removalStarted`; `removalHookReached` < `bCommitted` <
`removalReturned`; no `removalHookWitnessTimeout` or `barrierTimeout`.

**Evidence:** every test attaches its event log to the result bundle (`keepAlways`).

## 5. Tests and predictions

`MOTIVOTests/C99StagingRefsConcurrencyTests.swift`, 9 tests, each in its own isolated root
`tmp/C99-<uuid>/Staging`. "Before" = seam present, write logic unchanged.

| ID | Test | Before | After |
|---|---|---|---|
| X-0 | `testX0_sequentialControl` | PASS | PASS |
| **X-1** | `testX1_saveNewOverlappingSaveNewKeepsBoth` | **FAIL** (B's ref lost) | PASS |
| **X-2** | `testX2_saveNewOverlappingRemoveKeepsTheRemoval` | **FAIL** (R resurrected) | PASS |
| **X-3** | `testX3_saveNewOverlappingRenameKeepsTheTitle` | **FAIL** (title reverted) | PASS |
| **X-4** | `testX4_replaceOverlappingSaveNewKeepsBoth` | **FAIL** (B's ref lost) | PASS |
| **X-5** | `testX5_removeManyDoesNotSaveItsPreDeletionList` | **FAIL** (B lost) | PASS |
| **Y-1** | `testY1_extensionChangingReplaceKeepsACurrentRename` | **FAIL** (title reverted by stale snapshot) | PASS |
| **Y-2** | `testY2_sameExtensionReplaceKeepsACurrentRename` | **FAIL** (title reverted) | PASS |
| S-1 | `testS1_refsLoadAndSaveSitInsideTheRefsCriticalSection` (**structural corroboration only**) | **FAIL** | PASS |

- **Pre-fix predicted failures (8):** X-1…X-5, Y-1, Y-2, S-1. **Pass both:** X-0.
- **Substantive evidence:** the executable cases, plus the manual call-graph review recorded
  in the report. S-1 proves nothing about helpers, re-entrancy or deadlock.

## 6. Fix (only as reproduced) — boundaries as scope revision 1 §3

- **Primitive:** `NSLock` via `withRefsLock`.
- **`saveNew` and extension-changing `replace`:** locked load → modify → save. `replace`
  applies a **path-only merge onto the current ref**. The lock is released before C-90's
  rollback.
- **Same-extension `replace`:** writes no ref.
- **`writePoster`:** locked snapshot → JPEG outside → fresh locked commit.
- **`update(_:)`, `updateAudioMetadata`:** locked whole.
- **`remove(_:)`:** files outside, then locked reload and filter.
- **`removeMany`:** locked snapshot → files outside → fresh locked reload and filter by the
  deleted ids.
- **`cleanupAbandoned`:** locked refs part; folders outside.
- **`list()`, `ref(withId:)`:** locked.
- **Main-thread latency unmeasured.**

## 7. Residuals — kept open in the C-99 row

- **R-a** destination preflight and placement not atomic.
- **R-b** same-id file-versus-index races (`removeMany` snapshot paths; `replace` of an id
  removed concurrently).
- **R-c** `update(_:)` stale whole-ref write.
- **R-d** `remove(_:)` stale caller paths.
- **R-e** main-thread latency unmeasured.
- **R-f** real-interaction frequency unmeasured.

**C-99 is not to be closed comprehensively.**

## 8. Seam-only checkpoint and failing-first run

**Seam** (`claude-evidence/c99/step1-seam/`):
- **Diff against Codex's `scope-006-baseline` copy** (`26aeaf0f…`): **+38/−2**. The two removed
  lines are the reworded C-90 override comment; write logic is unchanged.
- **Hashes:** `StagingStore.swift` `5df7dee5…`; test file `4d2d51f5…`; this document at run
  time `12e86332…`.
- **Protected files:** caller, recording, `MOTIVOApp`, `UnitTestHost` and existing test hashes
  unchanged.

**Failing first** (`claude-evidence/c99/before/`), sequential, simulator `73EA3A14…`, no
backend: **9 executed, 1 passed, 8 failed, 0 skipped. Every prediction met; no miss.**

**Validity and joins:**
- **No `OverlapNotEstablished` or setup error.**
- Every X-1…X-4 log shows `aBarrierReached` → `bStarted` (→ `bLoaded` for background B) →
  `bReturned` → **`aReleasedByBReturned`**, so **pre-fix validity is met in all four**.
- X-5's log meets its own rule: `bPlaced` → `removalStarted` → `removalHookReached` →
  `bCommitted` → `removalReturned`.
- No barrier or witness timeout, and no teardown join failure.

| ID | Result | Observed |
|---|---|---|
| X-0 | PASS | — |
| **X-1** | **FAIL** | B's ref and media missing after reload (A saved its stale list) |
| **X-2** | **FAIL** | the removed item's ref reappeared |
| **X-3** | **FAIL** | `audioUserTitle` nil, display title back to the auto title |
| **X-4** | **FAIL** | B's ref missing after the paused replacement committed |
| **X-5** | **FAIL** | B, committed during the removal hook, missing (`removeMany` saved its pre-deletion list) |
| **Y-1** | **FAIL** | title reverted by the stale snapshot (extension change) |
| **Y-2** | **FAIL** | title reverted (same extension) |
| S-1 | FAIL | no `withRefsLock` section; 11 `loadRefs()` and 9 `saveRefs(` occurrences outside one (structural only) |

**Stop rules met:** all five class A reproductions are valid, and Y-1/Y-2 agree with the
predictions, so the approved fix may be applied.

## 9. After the fix — focused run

**Fix recorded** (`claude-evidence/c99/after/`):
- `StagingStore.fix-only.diff`: **raw +122/−68**, against the seam-only copy, whose hash
  matched `5df7dee5…` (kept at `step1-seam/StagingStore.step1.swift`).
- `StagingStore.c99-total.diff`: **raw +151/−61**, against Codex's baseline `26aeaf0f…`.
- `StagingStore.swift` is now **`420bcecb…`**.
- **Protected files unchanged** against `scope-006-baseline`: `MOTIVOApp`, `UnitTestHost`,
  `PracticeTimerView`, `+Sheets`, `+AudioPlayback`, `AttachmentsCard`, `PostRecordDetailsView`,
  `VideoRecorderView`, `AudioRecorderView`, and the C-84/C-85/C-89/C-90 tests.

**Critical sections, as applied:**
- **`saveNew`:** load/append/save.
- **Extension-changing `replace`:** load, a path-only merge onto the current ref, save; the
  lock is released before C-90's rollback.
- **Same-extension `replace`:** no ref write.
- **`writePoster`:** a locked snapshot, the JPEG outside the lock, a fresh locked commit.
- **`update(_:)`:** whole; still writes the caller's ref (R-c).
- **`updateAudioMetadata`:** whole.
- **`remove`:** files outside, then a fresh locked filter.
- **`removeMany`:** a locked snapshot, files outside, then a fresh locked filter by the deleted
  ids.
- **`cleanupAbandoned`:** refs part locked; folders outside.
- **`list()`, `ref(withId:)`:** locked.
- **Not locked:** the migration save inside `loadRefs`, which is always reached from a locked
  caller.

**Focused run** (`claude-evidence/c99/after/focused/`), sequential:
- **57 executed, 57 passed, 0 skipped, 0 failed**, matching the predicted 57.
- **Per class:** C-99 9/9, C-90 17/17, C-84 20/20, C-85 6/6, C-89 5/5.
- **Changed from before the fix:** all eight pre-fix failures now pass, and X-0 still passes.
- No worker or watcher join failure; the event-log attachments are extracted to
  `after/focused/event-logs.txt`.

**After-fix order witnesses** (from those attachments; no post-fix ordering requirement
applies, these are recorded as evidence):

| Test | Ordered events |
|---|---|
| X-1 | `aBarrierReached` → `bStarted` → **`aReleasedByWatcherTimeout@2005ms`** → `watcherFinished` → `aSaveCommitted@2007ms` → `bLoaded@2007ms` → `bReturned@2008ms` |
| X-2 | `aBarrierReached` → `bStarted` → **`aReleasedByWatcherTimeout@2005ms`** → `aSaveCommitted@2007ms` → `bReturned@2009ms` |
| X-3 | same shape as X-2 (`bReturned@2009ms`) |
| X-4 | `aBarrierReached` → `bStarted` → **`aReleasedByWatcherTimeout@2005ms`** → `bLoaded@2008ms` → `bReturned@2009ms` |
| X-5 | `bPlaced` → `removalStarted` → `removalHookReached@2ms` → `bCommitted@3ms` → `removalReturned@39ms` |

**What these show:**
- In X-1…X-4, operation B made **no store progress until A was released**: B blocked on the
  refs lock A held at its barrier, and the watcher's 2 s timeout released A. That is the
  serialised behaviour the fix introduces.
- X-5 needed no serialisation of B against the removal. The removal holds no lock while
  deleting files, and its fresh locked load kept B.
- **Not shown:** anything about real-interaction latency or frequency (R-e, R-f). The 2 s
  wait is the test's safeguard, not a product delay.

## 10. Manual call-graph review — the re-entrancy and deadlock evidence

Evidence: `claude-evidence/c99/after/call-graph-review-extract.txt`, a comments-stripped
extraction of `StagingStore.swift` `420bcecb…`. It supports the reasoning below; like S-1, it
is not a proof by itself.

**12 critical sections, each where §6 planned it:**
- `saveNew` (1) and extension-changing `replace` (1);
- `list()` and `ref(withId:)` (1 each);
- `cleanupAbandoned` (1);
- `writePoster` (2: snapshot, commit);
- `update(_:)` and `updateAudioMetadata` (1 each);
- `remove` (1);
- `removeMany` (2: snapshot, fresh commit).

**None contains** `await`, `MainActor`, `DispatchQueue`, a nested `withRefsLock`, or any media
or poster file operation (`removeItem`, `moveItem`, `copyItem`, `jpeg.write`, `deleteFiles`,
`undoPlacement`).

**Calls inside the sections, and their bodies:**
- The calls are `loadRefs`, `saveRefs`, `refByChangingPath`, `absoluteURL`, `unitTestReach`,
  and collection or `FileManager.fileExists` operations.
- Traced through `refsFileURL`, `bootstrap`, `relativePath`, `dateFolderName` and
  `BackupPolicy.exclude`/`setExcluded`, **no body takes `refsLock` or calls `withRefsLock`,
  awaits, references `MainActor`, dispatches, or creates a `Task`**.
- **`refsLock.lock()` is acquired at exactly one site**, inside `withRefsLock`.

**Re-entrancy.** Every `loadRefs()` call site (12) and every writer's `saveRefs(` (8) lies
inside a section. The only other `saveRefs(` is the legacy migration **inside `loadRefs`
itself**, so it runs with the caller's lock held and takes no lock. The non-recursive `NSLock`
is therefore never acquired twice on one path.

**Deadlock.**
- **Background holders** (the `saveNew`/`replace` closures on `DispatchQueue.global`) do only
  synchronous, lock-free work inside their sections, and never wait on the main actor.
- **Main-actor holders** do the same.
- A main-thread caller can wait for a background holder, but no holder waits for the main
  thread, so **there is no cycle**.
- **Test only:** `unitTestReach` runs the test hook, which may block on its own semaphores with
  timeouts (the barrier) and releases from GCD; it never touches `refsLock` or the main actor.

**Not established by this review:**
- main-thread latency under contention or filesystem stalls (R-e);
- the behaviour of Swift runtime or Foundation internals below `FileManager`/`Data.write`;
- any path not reachable from these sections.

## 11. After the fix — one full unit-target run

- **Evidence:** `claude-evidence/c99/after/full/`; start at `INDEX.md`.
- **Pre-run check:** existing local backend answered auth **200**, REST **200** at
  2026-09-15T10:50:52Z. No service started, no reset, no new manual fixtures.
- **Run:** `-only-testing:MOTIVOTests`, **`-parallel-testing-enabled NO`** (clarification 6),
  simulator `73EA3A14…`; xcodebuild exit 0; bundle result **Passed**.

| Scope | Declared | Executed | Passed | Skipped | Failed |
|---|---|---|---|---|---|
| `MOTIVOTests` | **481** | **481** | **478** | **3** | **0** |
| C-90's full run (retained) | 472 | 472 | 469 | 3 | 0 |

- **Per name** (`final-census-reconciliation.md`): 481 executed map one-to-one to 481 source
  declarations, 0 unmatched, 0 unmapped; 4 `extension` cases and 15 Swift Testing labels.
- **Against C-90's run:** exactly **+9** `C99StagingRefsConcurrencyTests`, **0 removed, and no
  existing test changed result**.
- **Skips:** exactly the three `SyncQueueOrderingReproductionTests` cases.

**The predicted counts (481 full, three queue skips) were met.** This was one run after the
fix, not a rerun until green. Passing results show that no existing test changed result; they
do not measure latency (R-e) or real-interaction frequency (R-f).

## 12. Release build

Run after the full run, sequentially: `xcodebuild … -configuration Release -destination
"generic/platform=iOS Simulator" build` (`claude-evidence/c99/after/release-build/`).

- **Result:** **BUILD SUCCEEDED**, xcodebuild exit 0, **0** ` error:` lines. The `#if DEBUG`
  seam compiles out of Release.
- **ONE NEW WARNING INTRODUCED BY THIS FIX, NOT CORRECTED:**
  `StagingStore.swift:711:5: 'nonisolated(unsafe)' is unnecessary for a constant with
  'Sendable' type 'NSLock', consider removing it`. That is the `refsLock` declaration.
  - **Harmless:** the attribute is redundant, not incorrect.
  - **Why left:** removing it is a source change that would need its own re-verification,
    and edits are paused.
  - **Open:** recorded for review as a trivial follow-up.
- **Other warnings:** existing project warnings elsewhere remain.

## 13. Records corrections — 2026-09-15, after Codex review 006 (accepted locally; R-a…R-f open)

The sections above are kept as written; these corrections supersede the statements they
name.

1. **§8, X-1 "B's ref and media missing" is narrowed.** The media assertion checks
   `mediaExists(refs.first { $0.id == b })`, which returns false once the ref is absent without
   examining B's independently known path. **Established:** B's index entry was lost.
   **Inference only, not measured:** that B's media file survived unreferenced.
2. **§9/§6, "the original is removed only after a commit" is qualified.** It holds for the
   successful indexed path. **Absent-id exception (R-b):** if the id is gone from the fresh
   locked load, extension-changing `replace` writes nothing, still removes the old path, and
   returns the path-changed fallback ref.
3. **§10, the call-graph review is qualified.**
   - **What it establishes:** the **production** graph inside the sections (one `refsLock`
     acquisition site, no `await`, main-actor hop, dispatch or nested acquisition) plus the
     **observed joins in these runs**.
   - **`unitTestReach`'s transitive graph is not lock-free in a hosted test run.** The C-99
     callback takes the event log's `NSLock` and waits on semaphores; its production relevance is
     that the hook is absent from Release and nil outside a hosted unit-test run.
   - **What the 10 s barrier timeout bounds:** that one semaphore wait, not every store operation
     or worker lifetime.
   - **What the joins show:** these runs finished, not that every future filesystem or lock
     wait must.
   - "No cycle" is source reasoning, **not a proof** against every deadlock or filesystem stall.
     **R-e remains open.** See `claude-evidence/c99/after/call-graph-review-correction.md`.
