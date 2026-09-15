# C-89 — a camera photo staged in the timer has two ids, so a deleted photo can return. Prediction, before any test or change

2026-09-15. Weekend audit finding A5.

- **Scope:** `claude-scope-004.md` (sha256 `81932a61…`), approved by
  `codex-scope-review-004.md` with execution clarifications, recorded in §2 before any
  run.
- **Standing decision (register, 2026-09-14):** the identity fix is required
  irrespective of C-3's performance result, with its own regression and acceptance.
- **Outcome on success:** C-89 becomes **fixed/verified locally; device acceptance
  pending**.

## 1. Source inspection at HEAD `3c68d81` (to be confirmed by the failing-first run)

- **The mismatch.** `PracticeTimerView.stageImage` (`PracticeTimerView.swift:4863`)
  appends the photo under a visible `id` and persists that id. It then calls
  `StagingStore.saveNew(… kind: .image, suggestedName: id.uuidString …)` (`:4875`)
  without `id:`, so the store mints a different id. The file stem is still the visible
  id; the returned ref is discarded.
- **Deletes find nothing.** The card trash (`AttachmentsCard.swift:92-100`) and the
  viewer delete (`PracticeTimerView+Sheets.swift:358-384`) look up the store by the
  visible id. `StagingStore.remove` deletes the media and poster **and** drops the ref
  from `staged.json`, but it is never reached.
- **Reload restores the photo.** On `.active`, hydration keeps only persisted image ids
  that have refs. The store image id set then differs, so `mirrorFromStagingStore()`
  rebuilds images from every store ref, restoring the deleted photo under the store's id.
- **The other `saveNew` calls in the file:**
  - audio (`:4662`): no `id:`, but re-keys to `ref.id` via `if ref.id != id` and
    `StagedAttachment(id: ref.id, …)`;
  - video (`:4722`): `id: id`;
  - trim save-as-new (`:5081`): `id: newID`.
- **Store details the tests depend on.** When `staged.json` is absent, `loadRefs`
  migrates and **removes** the `stagedAttachments_v2` defaults key.
  `cleanupAbandoned()` is whole-store: it drops refs whose file is missing and deletes
  empty day folders.

## 2. Execution clarifications from Codex scope review 004 — recorded before any run

1. **Local stack — corrects scope 004 §4.** The new C-89 tests and the focused
   C-84/C-85 run need no backend. **The full `MOTIVOTests` run does.** It includes
   existing local-backend suites, among them the C-88 end-to-end tests and C-100
   fixture setup, so it uses the **already-authorised disposable loopback stack** and
   those suites' explicit disposable fixtures. The claim that the whole plan made no
   backend/network/account operation and needed no local stack **was incorrect**.
   - No hosted backend, blanket reset or new account scope.
   - Availability is confirmed immediately before the full run (auth health 200 at
     2026-09-15 before writing this).
   - If it is unavailable, the boundary is reported; a broadly skipped suite is not
     treated as equivalent coverage.
2. **Store tests: isolated and sequential, disposable simulator only** (iPhone 17 Pro
   simulator `73EA3A14…`; no personal device or installation).
   - **setUp snapshot:**
     - whether `staged.json` exists, and its exact bytes;
     - whether the `stagedAttachments_v2` defaults key exists, and its data;
     - whether the Staging base directory exists;
     - the set of subdirectories and which were empty.
   - **Tracking:** each created ref id, media path and temporary source is recorded
     immediately after its awaited save, before any assertion can fail.
   - **tearDown:**
     - remove only owned files and folders;
     - restore `staged.json` byte-for-byte, or remove it if it was absent;
     - restore or remove the defaults key;
     - recreate any pre-existing empty folder that `cleanupAbandoned()` removed;
     - remove the base directory only if this test created it and it is empty;
     - assert the restored `staged.json` state equals the snapshot.
   - **Sequencing:** every save is awaited. The failing-first and focused runs use
     `-parallel-testing-enabled NO`. In the full run, parallel clones are separate
     simulator devices with separate containers, and methods within a class run
     serially, so no two tests mutate the same store at once.
   - **Known hazard, recorded rather than fixed:** the host app's root view can present
     `PracticeTimerView`, whose appearance runs `cleanupAbandoned()` and, without an
     active session, `clearAllStagingStoreRefs()`. The existing C-84/C-85 store tests
     pass under the same host. An unexpected store result is investigated as a
     possible overlap before any rerun.
   - No production storage or existing test class is changed.
3. **Structural checks bind to executable calls.**
   - Comments are removed before inspection: line and trailing `//` outside string
     literals, and `/* … */`.
   - **S-1** takes the brace-matched `func stageImage(` block, requires exactly one
     `StagingStore.saveNew(` call, extracts that call's parenthesis-matched argument
     list, and requires a top-level `id: id` argument and `kind: .image`.
   - **S-2** extracts every `StagingStore.saveNew(` call in the file, requires exactly
     **4**, and classifies each by its own arguments:
     - a top-level `id:` argument; or
     - (audio only) the call is bound as `let ref = try await StagingStore.saveNew(`
       inside its enclosing function's brace block, and that same block contains, after
       the call, `if ref.id != id` and `StagedAttachment(id: ref.id`.

     An unrelated `ref.id` elsewhere cannot satisfy it. Any unclassified call fails with
     its arguments shown. This uses the existing narrow source-check pattern, not a
     general parser.
4. **Run scope.**
   - **Order:** failing-first, fix, focused regressions, one full **unit-target** run
     (`-only-testing:MOTIVOTests`; no UI target), then one Release build, all
     sequential.
   - **Census:** reconciled by name, including extension and Swift Testing cases, with
     a final mapping artifact.
   - **Failures and skips:** every one is kept, and an unexpected outcome is
     investigated before any rerun.

## 3. Change

**Product code:** `MOTIVO/PracticeTimerView.swift` `stageImage` only. Pass `id: id` to
the one camera-photo `saveNew`, with a brief C-89 comment.

**Unchanged:**
- the `Task`, `try?`, tmp write and persistence order, and so the accepted
  asynchronous window;
- `StagingStore.swift`, both delete paths, hydration, the mirror, audio/video/trim
  paths, `VideoRecorderView.swift`, `PostRecordDetailsView.swift`;
- UI, schemes, dependencies;
- C-3 performance, C-90, C-99, the post-Save observation.

**Photos already staged with mismatched ids are not migrated.**

## 4. Tests and predictions

New file `MOTIVOTests/C89CameraPhotoIdentityTests.swift`, one class
`C89CameraPhotoIdentityTests`, **five tests**:

| ID | Test | Before fix | After fix |
|---|---|---|---|
| **S-1** | `testStageImagePassesTheVisibleIDToTheStore` | **FAIL** (the call has no `id:`) | PASS |
| **S-2** | `testEveryTimerStagingCallKeepsOneIdentity` | **FAIL** (image call neither passes `id:` nor re-keys) | PASS |
| B-1 | `testCompletedPhotoStageDeletedByVisibleIDStaysDeletedAfterReload` — fixed call shape, awaited; ref id and file stem equal the visible id; delete as both paths do; re-read `staged.json` from disk; ref and media gone; `cleanupAbandoned()` recreates nothing | PASS | PASS |
| B-2 | `testOldCallShapeLeavesTheMismatchedRefOnDisk` — **negative control**, pre-fix call shape; lookup by visible id finds nothing; after an on-disk reload an image ref for this stage remains under a different id, with its media file present | PASS | PASS |
| B-3 | `testReconciliationInputsAgreeAfterACompletedPhotoStage` — fixed shape; store image ids for this stage equal `{visible id}`; both sets empty after delete | PASS | PASS |

**Only S-1 and S-2 are product discriminators.** B-1…B-3 invoke the call shapes
directly, not the SwiftUI view, and establish the store contract the fix relies on.

**Pre-fix predicted failure set: exactly S-1 and S-2.**

**Focused after the fix:**
- `C89CameraPhotoIdentityTests` 5/5;
- `C84SessionPreservationTests` and `C85FormatIntegrityTests` all pass, including
  `testWholeSessionDeletionSitesArePinned` (no deletion site changes).

**Full unit target after the fix:**
- **455 declared and executed** (450 + 5), **0 failed**;
- skips: the three `SyncQueueOrderingReproductionTests` cases. The C-88 run's
  unshare-preflight skip is **not predicted either way**, and any skip or failure is
  kept and investigated.

**Release build:** succeeds.

**Not claimed:** the SwiftUI view's own delete and reload paths, and device behaviour.

**Device acceptance** stays Samuel's physical QA, as specified by Codex. Using a
disposable unsaved session, not his protected in-progress session:
- stage a new camera photo, let staging finish, delete it via the card, and check it
  stays absent across background/foreground and relaunch;
- repeat via the viewer;
- check an undeleted new photo survives the same transitions.

Any miss is recorded as a miss and diagnosed before a further run.

## 5. Failing-first run — before any product change

Evidence `claude-evidence/c89/before/`. `PracticeTimerView.swift` confirmed at the
baseline `dce3997d…` immediately before the run. Sequential
(`-parallel-testing-enabled NO`), simulator `73EA3A14…`, no backend.

**5 executed, 3 passed, 2 failed, 0 skipped. Every prediction met; no miss.**

- **S-1 failed on its own assertion.** `stageImage` has exactly one staging call, with
  arguments `["from: tmp", "kind: .image", "suggestedName: id.uuidString", "duration: nil", "poster: nil"]`,
  so there is no `id: id`.
- **S-2 failed on its own assertion.** The only unclassified call is
  `from: tmp, kind: .image, suggestedName: id.uuidString, duration: nil, poster: nil`.
  The count of 4 held, and the audio re-key, video `id: id` and trim `id: newID` were
  each classified correctly. That is the evidence the check binds to the calls
  themselves.
- **B-1, B-2 and B-3 passed**, including every teardown restoration assertion
  (`staged.json` existence and content, the legacy defaults key, pre-existing empty
  folders). B-2's old call shape left its mismatched ref and media on disk; B-1's fixed
  shape removed both.

## 6. After the fix — focused run

**Product change:** `PracticeTimerView.swift` `stageImage` only, +3/−1: `id: id` plus a
two-line C-89 comment. Diff `claude-evidence/c89/after/PracticeTimerView.diff`.

Evidence `claude-evidence/c89/after/focused/`. Sequential, no backend.

**31 executed, 31 passed, 0 skipped, 0 failed. Every prediction met.**

- `C89CameraPhotoIdentityTests` 5/5; S-1 and S-2 now pass.
- `C84SessionPreservationTests` 20/20, including `testWholeSessionDeletionSitesArePinned`
  and `testSaveNewHonoursTheCallersID`.
- `C85FormatIntegrityTests` 6/6.

## 7. After the fix — one full unit-target run

- **Evidence:** `claude-evidence/c89/after/full/`. Start at `INDEX.md`; the final census
  is `final-census-reconciliation.md`, written directly rather than as an intermediate.
- **Local stack:** checked immediately before the run, loopback auth 200 and REST 200 at
  2026-09-15T07:13:03Z. The existing disposable local-stack suites and their fixtures
  ran as authorised; no hosted backend, reset or new account scope.
- **Command:** `-only-testing:MOTIVOTests`, simulator `73EA3A14…`. xcodebuild exit 0;
  bundle result Passed.

| Scope | Declared | Executed | Passed | Skipped | Failed |
|---|---|---|---|---|---|
| `MOTIVOTests` | **455** | **455** | **452** | **3** | **0** |
| C-88's full run, `MOTIVOTests` only (retained) | 450 | 450 | 446 | 4 | 0 |

- **Per name:** 455 executed cases map one-to-one to 455 source declarations, 0 unmatched,
  including 4 `extension` cases and 15 Swift Testing labels.
- **Against C-88's unit-target run:** +5 `C89CameraPhotoIdentityTests`, 0 removed.
- **Skips:** the three `SyncQueueOrderingReproductionTests` cases ("sequence not
  exercised"), as predicted.
- **One result changed:** `UnshareDurabilityTests.testUnshareRemovesAttachmentsAndUploadsNothing`
  **Skipped → Passed**. C-88's preflight skip did not recur. That was not predicted either
  way, and it **does not establish** the earlier skip's cause, which stays unproven.

**Every §4 prediction for the full run met.** This was one run following the fix, not a
rerun until green.

## 8. Release build

`xcodebuild … -configuration Release -destination "generic/platform=iOS Simulator" build`
after the full run. Evidence `claude-evidence/c89/after/release-build/`.

- **Result:** **BUILD SUCCEEDED**, xcodebuild exit 0 (`exit.txt`), no ` error:` line, and
  no warning at the changed `stageImage` lines.
- **Wrapper status:** the background wrapper reported exit 1. That came from its final
  `grep -c " error:"`, which exits 1 when it finds **zero** matches. It is not a build
  failure.
- **Existing project warnings elsewhere remain;** this is not a claim of a warning-free
  build.

Tests and builds for this unit are finished.
