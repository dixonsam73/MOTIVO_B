# C-90 — `StagingStore` reports success when its reference write failed. Prediction, before any run

2026-09-15. Weekend audit finding A6.

- **Scope:** `claude-scope-005.md` (sha256 `8c2535f1…`, kept) as superseded in part by
  `claude-scope-005-revision-1.md`.
- **Approval:** `codex-scope-review-005-revision-1.md`, with execution clarifications
  recorded in §2 **before any run**.
- **Predictions are hypotheses to test, not results to force.**

## 1. Source inspection at HEAD `3c68d81` (to be confirmed or refuted by the runs)

- **The swallowed write.** `saveRefs` (`StagingStore.swift:570-576`) wraps the `staged.json`
  write in `catch {}`.
- **Extension-changing `replace`** (`:138-150`):
  - it deletes any existing `<stem>.<new ext>` (`:144`);
  - it places the trim, "saves" the ref, then deletes the original and returns success.

  If the write failed, the ref names a deleted file.
- **`saveNew`:**
  - it deletes an existing poster destination (`:95-97`);
  - on a second collision `moveOrCopy` deletes the destination (`:332-334`);
  - it places media and poster, "saves" the ref and returns success. A poster-copy failure
    throws **after** the media has been placed, leaving the source consumed.
- **`writePoster`** writes the poster file, then "saves" the ref, and returns `true`.
- **Legacy migration** (`:540-547`) "saves" and then removes the `stagedAttachments_v2`
  defaults key unconditionally.
- **Only caller of `replace`:** `handleTrimReplaceOriginal` (`PracticeTimerView.swift:5097`).
  On a thrown error it deletes the trim and keeps the original.
- **The hosted unit-test app builds `PracticeTimerView`:** the route defaults to `.timer`.
  Its `onAppear` runs `cleanupAbandoned()` and, without an active session,
  `clearAllStagingStoreRefs()`.

## 2. Execution clarifications (Codex scope review 005 revision 1) — recorded before any run

1. **Isolation-only step first.** The source diff and hashes are recorded **separately**
   before the failing-first run. `StagingStoreError` is declared in that step (a
   declaration only, no changed write behaviour, identified in the step-1 diff) so the
   tests compile without introducing the fix early. The complete failure trace is kept.
2. **Real store and legacy key.**
   - In each test's `setUp`, **before** the override is set: snapshot the real store's
     `staged.json` existence and bytes, and the `stagedAttachments_v2` defaults value.
   - **Then clear the legacy key**, before any isolated-store API can read it.
   - `tearDown` restores the key's original existence and value exactly and asserts it.
   - Every store operation is awaited, and the store tests run sequentially. The override
     is cleared only after all of a test's awaited work has finished. **It is not safe for
     concurrent store work, and no such claim is made.**
3. **Fault controls throw immediately.**
   - F-0 and F-M throw `FaultNotEstablished` **out of the test** before the scored
     operation. There is no assertion followed by the operation.
   - A control failure is recorded as *fault not established*, never as a reproduced
     defect or its absence.
   - The migration's scored `list()` is a single separate call, and M-2 is **not**
     reseeded.
4. **Rollback decides moved versus copied, in both `saveNew` and extension-changing
   `replace`.**
   - `moveOrCopy` can succeed while its source remains (an external copy, or a failed
     best-effort source removal).
   - On a later failure: if the source **still exists**, it is never overwritten or
     deleted; only the staged copy **this call created** is removed.
   - If the source is **absent**, the placed file is moved back.
   - The original recording and its ref are untouched in either case.
   - **A failed rollback** keeps the bytes where they are and rethrows. It is
     source-inspected only and **not claimed as executed**.
5. **Poster and migration semantics.**
   - **Migration:** a persistence failure is caught **inside** the migration branch, so it
     still returns the decoded, normalised legacy refs and does not fall into the outer
     decode-error `return []`.
   - **Poster tests** keep apart unchanged metadata and deliberately un-rolled-back poster
     bytes.

## 3. Order and change

1. **Step 1 — isolation only.**
   - `StagingStore.swift`: `enum StagingStoreError: Error, Equatable { case destinationExists(String) }`
     (declaration only). Plus, under `#if DEBUG`,
     `nonisolated(unsafe) static var unitTestRootOverride: URL?`, read by `baseURL` only
     when `UnitTestHost.isActive`.
   - `MOTIVOApp.swift`: the `.timer` route shows `Color.clear` when `UnitTestHost.isActive`,
     and otherwise `PracticeTimerView` exactly as before.
   - Write logic unchanged. Diff and hashes recorded.
2. **Step 2 — failing first:** `C90StagingMetadataWriteFailureTests` only, sequential, on
   simulator `73EA3A14…`. **Stop if any fault control is not established.**
3. **Step 3 — fix,** `StagingStore.swift` only:
   - `saveRefs` throws;
   - preflight rejection of a pre-existing destination in extension-changing `replace` and
     in `saveNew` (final media destination, poster destination);
   - rollback per §2.4 on any failure after placement;
   - migration keeps the key on failure;
   - `writePoster` returns `false`;
   - every other writer uses `try?`, **with its best-effort durability questions left
     open**.
4. **Step 4 — verification:**
   - focused run: C-90, C-84, C-85, C-89;
   - full unit target: the authorised disposable local stack checked immediately before,
     and the command does not start otherwise;
   - Release build.

## 4. Tests and predictions

`MOTIVOTests/C90StagingMetadataWriteFailureTests.swift`, 17 tests. Each test uses its own
isolated root `tmp/C90-<uuid>/Staging`.

**Fault:** `chmod 0555` on that root. Today's day folder exists beforehand and stays `0755`.

**F-0:** an ordinary ref exists (fault off); then:
- a direct atomic probe write into the root **throws**;
- a probe write into the day folder **succeeds**;
- `staged.json` decodes by direct read.

**F-M:** `staged.json` absent and the legacy key absent; fault on; the same direct probes;
**only then** write the key.

"Before" = after step 1, write logic unchanged.

| ID | Test | Before | After |
|---|---|---|---|
| I-1 | `testI1_overrideIsHonouredAndTheRealStoreIsUntouched` | PASS | PASS |
| I-2 | `testI2_isolationIsLimitedToTheHostedTestProcess` (source: override inside `#if DEBUG`, read under `UnitTestHost.isActive`; `.timer` gated) | PASS | PASS |
| **R-1** | `testR1_extensionChangingReplaceUnderTheFaultKeepsTheOriginal` | **FAIL** | PASS |
| **R-2** | `testR2_replaceRecoversAfterTheFaultIsRemoved` | **FAIL** | PASS |
| R-3 | `testR3_extensionChangingReplaceSucceedsWithoutAFault` | PASS | PASS |
| R-4 | `testR4_sameExtensionReplaceUnderTheFaultKeepsItsPath` | PASS | PASS |
| **R-5** | `testR5_replaceRefusesAnExistingDestination` | **FAIL** | PASS |
| **N-1** | `testN1_saveNewWithPosterUnderTheFaultLeavesNothingAndRestoresTheSource` | **FAIL** | PASS |
| **N-2** | `testN2_saveNewRecoversAfterTheFaultIsRemoved` | **FAIL** | PASS |
| N-3 | `testN3_saveNewWithPosterSucceedsWithoutAFault` | PASS | PASS |
| **N-4** | `testN4_saveNewRefusesAnExistingFinalMediaDestination` | **FAIL** | PASS |
| **N-5** | `testN5_saveNewRefusesAnExistingReferencedPosterDestination` | **FAIL** | PASS |
| **N-6** | `testN6_posterCopyFailureRestoresTheSourceAndStagesNothing` | **FAIL** | PASS |
| **P-1** | `testP1_writePosterUnderTheFaultReportsFailureForANewPoster` | **FAIL** | PASS |
| **P-2** | `testP2_writePosterUnderTheFaultReportsFailureForAReferencedPoster` | **FAIL** | PASS |
| **M-1** | `testM1_failedMigrationKeepsTheLegacyKeyAndReturnsItsRefs` | **FAIL** | PASS |
| **M-2** | `testM2_migrationRecoversAfterTheFaultWithoutReseeding` | **FAIL** | PASS |

- **Pre-fix predicted failure set (12):** R-1, R-2, R-5, N-1, N-2, N-4, N-5, N-6, P-1, P-2,
  M-1, M-2. Each must fail **on its scored assertion**, not on a fault control or setup.
- **Predicted pass before and after (5):** I-1, I-2, R-3, R-4, N-3.
- **Superseded, kept for the record:** scope 005 predicted M-2 **PASS** before the fix;
  revision 1 corrected it to FAIL.
- **Hypotheses at risk:**
  - **R-4** relies on `replaceItemAt` working with a writable day folder under a read-only
    root.
  - **Every fault test** relies on the simulator enforcing `0555`.

  A different outcome is a miss, preserved and diagnosed before any rerun.

**Expected full unit-target census after the fix:** 455 + 17 = **472** declared and
executed, 0 failed, skips only the three queue reproductions. Reconciled by name against
C-89's run.

**Not claimed:** the rollback-failure branch as executed; concurrency (C-99); the durability
of the best-effort writers; UI recovery; device behaviour.

## 5. Step 1 (isolation only) and the failing-first run

**Step 1 recorded before the run** (`claude-evidence/c90/step1-isolation/`). Diffs are
against Codex's `revision-1-baseline` copies:

| File | Change | Hash (baseline → step 1) |
|---|---|---|
| `StagingStore.swift` | **14 lines added, 0 removed**: the `StagingStoreError` declaration and the `#if DEBUG` override with its `baseURL` read. Write logic byte-identical | `c1a46b1d…` → `eea71aaa…` |
| `MOTIVOApp.swift` | the `.timer` gate (15 changed lines) | `e3ed5db1…` → `c347c767…` |

Test file `f952c9fe…`, this document at run time `2f6ac30a…`.

**Failing first** (`claude-evidence/c90/before/`): `-parallel-testing-enabled NO`, simulator
`73EA3A14…`.

**17 executed, 5 passed, 12 failed, 0 skipped. Every prediction met; no miss.**

**Every fault control was established.**
- No test threw `FaultNotEstablished` or `C90SetupError`, so the simulator enforces `0555`
  on the isolated root while the day folder accepts writes.
- Every failure is on a scored assertion.
- No teardown restoration assertion failed: real store unchanged, legacy key restored,
  root mode restored.

**Passed:** I-1, I-2, R-3, R-4 (the same-extension replace worked under the fault, as
hypothesised), N-3.

**Failed, with the observed state:**

- **R-1** — no throw; the original `.mov` **deleted**; the on-disk ref **still names the
  deleted `.mov`**; the `.mp4` is present and unreferenced; the trim is consumed.
  **This is C-90 reproduced deterministically.**
- **R-2** — the retry threw `NSCocoaErrorDomain 260`: the trim was consumed by the first
  attempt.
- **R-5** — no refusal. The other item's `<stem>.mp4` was **overwritten with the trim's
  bytes**, the original was deleted, and the original's ref now names `.mp4` too, so
  **two refs name one file** and the other item's bytes are lost.
- **N-1** — no throw; staged media and poster present; no ref; source consumed.
- **N-2** — the retry threw 260: the source was consumed.
- **N-4** — no refusal; the collision-named existing file was **overwritten** ("existing B"
  became "new recording"); a ref was written.
- **N-5** — no refusal; the other item's **referenced poster overwritten** ("other poster"
  became "new poster"); media staged; ref written.
- **N-6** — threw (missing poster, 260), but the source media was **consumed** and the
  staged media left.
- **P-1 / P-2** — `writePoster` returned `true` under the fault. The other two assertions
  in each held: metadata unchanged, and the poster bytes as documented.
- **M-1** — the decoded ref was returned, but **the legacy key was removed** while no
  `staged.json` was written.
- **M-2** — the key was gone after the failed migration; unreseeded recovery returned
  **`[]`**.

## 6. After the fix — focused run

**Fix recorded** (`claude-evidence/c90/after/`):
- `StagingStore.fix-only.diff` is **+100/−43**. It was taken against the step-1 file
  rebuilt from Codex's baseline plus the recorded step-1 patch, whose hash matched
  `eea71aaa…`.
- `StagingStore.c90-total.diff` and `MOTIVOApp.c90-total.diff` are against Codex's baseline.
- `StagingStore.swift` is now `26aeaf0f…`.
- Every `saveRefs(` call site is explicit: `try` in `saveNew`, extension-changing `replace`,
  the migration and `writePoster`; `try?` in the other six writers.

**Focused run** (`claude-evidence/c90/after/focused/`), sequential:
- **48 executed, 48 passed, 0 skipped, 0 failed.**
- Per class: `C90StagingMetadataWriteFailureTests` 17/17, `C84SessionPreservationTests`
  20/20, `C85FormatIntegrityTests` 6/6, `C89CameraPhotoIdentityTests` 5/5.
- **Every §4 "after" prediction met.** All 12 pre-fix failures pass, and the 5 controls still
  pass.

## 7. Full unit-target run — NOT STARTED: the local stack was unavailable (boundary)

- **What the check found:** at 2026-09-15T08:14:34Z the pre-run check read loopback auth
  **000** and REST **000**. The guard stopped the command, so **no test ran** and nothing is
  scored.
- **Diagnosis** (read-only, `after/full/local-stack-diagnosis.txt`, 08:15:11Z):
  - the Colima Docker socket `~/.colima/default/docker.sock` does not exist;
  - no containers are running;
  - `supabase status` cannot reach Docker;
  - machine uptime is 31 minutes, **consistent with the restart before this unit resumed
    leaving Colima stopped**.
- **No data was touched:** no reset, no container or volume operation.
- **Not substituted.** A broadly skipped unit-target run is not accepted as equivalent
  coverage.
- **What resuming needs:** Colima started and the existing stack brought up with its volumes
  intact. That is a service start, not a reset. It is **not done by me without
  confirmation**; recorded for Codex and Samuel in `claude-status-005-boundary.md`.
- **Limitation of that diagnosis:** with the Docker socket unavailable, the reported
  `running=0` and the empty container listing **cannot establish** how many saved containers
  or volumes exist. It is **not evidence of an empty or lost database**.
- **Status of the failed check:** the 08:14:34Z health check is kept as a run that **never
  started**.
- **Recovery authorised 08:21 UTC** (`codex-c90-local-stack-resume.md`): start the existing
  default Colima profile with its saved configuration; verify the Docker context and the
  project's existing containers and data volumes; then resume the same stack with
  `supabase start`. No reset, reinitialisation, deletion, migration, seeding, upgrade, hosted
  command, or exposure or permission change. **Stop on any such condition or prompt.**
- **Recovery performed** (`after/full/recovery-1…5.txt`):
  1. **08:21:55Z, read-only.** The existing `default` profile was **Stopped**. Its saved
     `colima.yaml` (16 Aug) is `vz`, docker, aarch64, 4 CPU / 8 GiB, `disk: 60`,
     `network.address: false`. Docker context `colima`; Supabase CLI 2.113.0; repository
     `project_id = "rlwtqxumfobakvdueugm"`.
  2. **08:22:25Z — my own guard stopped the start on a FALSE NEGATIVE.** It looked for
     `diffdisk`/`basedisk`, but this Lima version names the root image `disk`. Nothing
     changed.
  3. **08:22:52Z, read-only.** Root `disk` 21,474,836,480 B (= the instance's `disk: 20GiB`).
     Data disk `_disks/colima/datadisk` 64,424,509,440 B (= the profile's 60 GiB), 14 GB
     allocated, last written 08:43, before the restart. No mismatch, so no resize or new
     disk implied.
  4. **08:23:12Z.** The guard re-checked both sizes, then `colima start` with no flags. The
     profile is **Running**, disk sizes unchanged after start. Colima's routine in-VM
     emulator registration ("installing: 386/amd64 OK") and a negligible port-53
     forwarding warning are recorded.
     - **Docker's restart policy brought back all 11 existing `rlwtqxumfobakvdueugm`
       containers**, same images; no other Supabase project exists.
     - **Existing volumes:** `supabase_db_…`, created 2026-09-14T21:41:56+01:00 and labelled
       `com.supabase.cli.project=rlwtqxumfobakvdueugm`, plus `_storage_` and
       `_edge_runtime_`.
     - **`supabase start` was not needed and was not run.**
  5. **Readiness gate before the single full run:** poll until loopback auth/REST answer
     200, then read-only database checks — the local B-39/B-41 migrations recorded as
     applied, the `attachments` bucket present, and the `auth.users` count (informational).
     The full run starts only if the gate passes.

### 7b. Readiness established, then the single full unit-target run

**Readiness** (`after/full/recovery-5-readiness.txt`) at 08:24:33Z:
- loopback auth **200**, REST **200**;
- all 11 containers up (10 healthy; PostgREST has no health check and answered REST 200);
- **14 migrations recorded**, including the local `20260914120000` (B-39) and
  `20260914130000` (B-41), so no reset has happened since;
- buckets `attachments` and `avatars` present;
- **6** `auth.users` (informational).

Gate passed.

**Full unit target** (`after/full/`; start at `INDEX.md`): `-only-testing:MOTIVOTests`,
simulator `73EA3A14…`, xcodebuild exit 0, bundle result **Passed**.

| Scope | Declared | Executed | Passed | Skipped | Failed |
|---|---|---|---|---|---|
| `MOTIVOTests` | **472** | **472** | **469** | **3** | **0** |
| C-89's full run (retained) | 455 | 455 | 452 | 3 | 0 |

- **Per name** (`final-census-reconciliation.md`): 472 executed map one-to-one to 472 source
  declarations; 0 unmatched, 0 unmapped; 4 `extension` cases and 15 Swift Testing labels.
- **Against C-89's run:** exactly **+17** `C90StagingMetadataWriteFailureTests`,
  **0 removed, 0 result changes**.
- **Skips:** exactly the three `SyncQueueOrderingReproductionTests` cases ("sequence not
  exercised").

**Every §4 full-run prediction met.** No other suite changed outcome with the hosted timer
screen gated. That is the behavioural check the gate needed: every existing unit test that
ran in C-89's run passed or skipped identically.

One full run after the fix, not a rerun until green. The 08:14:34Z attempt never started and
is kept as that.
- **Also recorded:** the restart cleared the session scratchpad's census script (recreated
  as `c90_census.py`, same logic) and the Release derived data. The unit-test derived data
  and all evidence under `claude-evidence/` survived.

## 8. Release build

Run while the full unit target was blocked. It needs no backend and overlapped nothing.
The only change from the approved order is that it ran before, not after, the unit-target
run; the two do not depend on each other.

`xcodebuild … -configuration Release -destination "generic/platform=iOS Simulator" build`
(`claude-evidence/c90/after/release-build/`, clean derived data after the restart):

- **BUILD SUCCEEDED**, xcodebuild exit 0;
- **0** ` error:` lines;
- **no warning or error in `StagingStore.swift` or `MOTIVOApp.swift`**.

So the `#if DEBUG` store override is absent from Release and the gate compiles there.
Existing project warnings elsewhere remain.

## 9. Records corrections — 2026-09-15, after Codex review 005 (accepted locally)

The sections above are kept as written; these corrections supersede the statements they
name.

1. **Diff counts.** §5's step-1 "14 lines added" is **+16/−0**. §6's fix-only "+100/−43" is
   **+103/−43**. The total store diff is **+119/−43**. The earlier counts skipped added
   blank lines. `MOTIVOApp` +11/−4 was correct.
2. **§7b wording.** "No other suite changed outcome with the hosted timer screen gated. That
   is the behavioural check the gate needed" is **withdrawn**. The supported statement is
   that **no existing test changed result** against C-89's run. The gate stops the timer view
   being built in the test host, so this does not show the view's runtime behaviour is
   unaffected; device and runtime acceptance remain separate.
3. **Accounts and fixtures.** Claims of no account or fixture operation mean **no manual or
   hosted account or fixture work, and no reset**. The approved full run's existing
   local-stack suites create their own isolated local identities.
4. **Source-inspected only:**
   - the rollback-failure branch;
   - `undoPlacement`'s copy branch (source still present).

   The fixtures executed moved temporary files only.
