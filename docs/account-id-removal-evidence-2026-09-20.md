# Handle removal — implementation evidence

**20 September 2026. Claude.**

## STATUS

**CODEX LOCAL IMPLEMENTATION ACCEPTANCE GRANTED, 20 September 2026**, for the bounded
handle-removal unit at the **18 source + 8 test hashes in this record's manifest**. Codex
independently read the actual diffs, the final `.xcresult` (1000 passed / 0 failed / 6 skipped),
the per-test comparison (39 IDs in, 11 out, all 6 skips unchanged), the successful Debug and
Release logs, and the protected-document hashes. **No remaining source blocker.**

**SAMUEL'S FINAL SIGN-OFF IS PENDING. Nothing is closed by this.**

| | |
|---|---|
| Committed | **NO** |
| Pushed | **NO** |
| Production / schema / credential / device action | **NONE** |
| Device QA | **NOT DONE, and not accepted** |
| Rendering acceptance | **NONE.** Structural tests prove WIRING; no test in this target renders a view |
| Phase 6 | **OPEN** |
| Further source/test changes or reruns | **NONE** — bytes are fixed at the manifest hashes |

### Codex's evidence qualification, preserved verbatim in substance

**Codex read the positive-control transcripts and did NOT independently verify the original
control runs.** Pruned bundles and transcribed output are **weaker evidence and are not
interchangeable with the final bundle**. Its acceptance rests on the **final reproducible tests
and builds, the reviewed production wiring, and the fixed hashes** — see §7, whose language was
corrected so that nothing there implies Codex saw the original controls.

**All historic caveats below are retained, not tidied.**

Scope: `docs/account-id-removal-assessment-and-scope-2026-09-20.md` (revision 2, Codex-approved,
plus one approved sixth-file dependency correction — §6 below).

**No commit, push, production statement, schema change, credential or device action was taken.**
Working tree only. `AGENTS.md` and both invitation documents are **untouched** — their mtimes
remain 14 and 17 September, verified after the work.

---

## 1. Artifact directory

```
/private/tmp/claude-501/-Users-samueldixon-Documents-Xcode-projects-MOTIVO-B-MOTIVO/c657c407-b562-4523-b151-9170cc9ae8a2/scratchpad/evidence/
```

Its `MANIFEST.md` lists every file with what it is. **This scratchpad is session-scoped**, so
the accounting below is reproduced here in full and does not depend on it surviving.

### Result bundles

**Xcode prunes this directory, and only TWO bundles survive.** Checked at write time, not
assumed:

| Bundle | Contents | State |
|---|---|---|
| `Test-MOTIVO-2026.09.20_23-19-42-+0100.xcresult` | **The acceptance run** — 1006 total, 1000 passed, 0 failed, 6 skipped | **EXISTS** |
| `Test-MOTIVO-2026.09.20_23-19-00-+0100.xcresult` | The 2-test `C70WiringPinTests` run | **EXISTS** |
| `Test-MOTIVO-2026.09.20_23-08-31-+0100.xcresult` | Corrected 12-class targeted run | **PRUNED — citation withdrawn** |
| (first full suite; five controls) | — | **PRUNED** |

Both surviving bundles are under
`/Users/samueldixon/Library/Developer/Xcode/DerivedData/MOTIVO-ezwfngloiavjzsgbiehetfqnilcc/Logs/Test/`.

**An earlier revision of this record cited the `23-08-31` bundle. It no longer exists and that
citation is withdrawn.** Its raw log survives as `targeted-run.log` because that run was `tee`d.
**The five positive controls were never `tee`d and left no bundle**, so they survive only as
terminal output — preserved verbatim in `evidence/CONTROLS.md`, which states that provenance
and its limits before quoting anything. **They were not re-run to manufacture artifacts**:
source and test bytes are fixed and reviewed, and an honestly-labelled transcript is a better
trade than mutating them again.

### Logs

`full-suite-final.log` (acceptance), `full-suite.log` (first run, one failure — §6),
`targeted-run.log`, `build-Debug.log`, `build-Release.log`,
`warnings-{Debug,Release}-unique.txt`, `xctest-classes.txt`,
`{pre,post}-source-hashes.txt`, `{pre,post}-test-hashes.txt`, `pre-control-hashes.txt`.

---

## 2. Results

| Measure | Result |
|---|---|
| **Full `MOTIVOTests`** | **1000 passed, 0 failed, 6 skipped** (the 6 are the standing opt-in set) |
| Baseline reused | `8b54ba6`: 972 / 0 / 6. `d0d7812` and `05ad6a8` verified **docs-only**, so `05ad6a8`'s source is byte-identical to `8b54ba6`'s |
| Total test IDs | **978 → 1006** |
| Net test movement | **+28 = 39 new IDs − 11 removed IDs.** Reconciled by ID in §5.6 |
| Skips | **6 before, 6 after, the same 6.** Unchanged by this work |
| **Debug build** | SUCCEEDED |
| **Release build** | SUCCEEDED |
| **Warning delta attributable to this change** | **ZERO**, established by attribution (§4) |

---

## 3. Source hashes

**Pre-change (at `05ad6a8`) → post-change**, the 18 source files:

```
PRE
317faf8432aed3638b2c4758785b62db1907a35eef06a21b729f38cafee44668  MOTIVO/AccountDirectoryService.swift
bc19cee1c8e27123a6803a27309a885fd52dde3053c5fb9d928d928066aba937  MOTIVO/AuthManager.swift
7bee8b879e3550cd53a8a20cdb49313a8be78870c91b227059fb9931bed0a0f5  MOTIVO/AppSetUpView.swift
6948e2ac72734dbc1e8e474670d585fe12b56c164059f6de0de9c2b81a3c02cc  MOTIVO/ProfileStore.swift
4268387e0e688864c0e8f5ce9c34b31d279e650c6c335dbb2a6583bbbe40b8d9  MOTIVO/ProfileView.swift
f5c69d8cf20b34c62b579428a5833720805b73d00cf8230e17a418174291dc14  MOTIVO/PeopleUserRow.swift
066c83de677d252436d4b2d40ae9943ffee70abc4174546ae595a7f94b6aaf42  MOTIVO/PeopleView.swift
66d5f85346e764e312798fc587c145dc20778e56e8edaeff959caa2b84e68ebf  MOTIVO/FollowersListView.swift
4f1c129cbdb1dc0b9b42f415b59bcdbc341d3fb05d064146ded34893354da8f8  MOTIVO/FollowingListView.swift
43810752cdabb6511a12367063b54b0b0ccf17138118acd55366d8e0a5685ae7  MOTIVO/ContentViewRowSupport.swift
fd1525548f964e4e36d50a1332da2fc8b92df279fb5e02bfe672d73d34afe6a4  MOTIVO/ContentViewSessionRow.swift
e0937ace9a6045a84f723a7661ce6d31c2afab1bf6d10ad0e717f3b60b9242cf  MOTIVO/ContentViewRemotePostRowTwin.swift
bb0991f4dc1f34dbf7607869a77d40a9e59946660dbf4e26816fb3fed2381c98  MOTIVO/SessionDetailView.swift
c47b6014f84c555ee140c4953471ebc910045a379ff7a444941cc27dbdfe918f  MOTIVO/BackendSessionDetailView.swift
29fe4f029eeaa81b3c7afb0af414d46a021768e5b8b5235f84e84341d1c17f18  MOTIVO/ConnectedAttachmentShareUI.swift
669dd3de60b02efc3c8333e8741b5f0fd2e63fed40e2360344494044f60d0ca6  MOTIVO/ProfilePeekView.swift
02f5d11a53e110da35ab1233a986c2f624461596522cf6215f56da367c14b55a  MOTIVO/DirectorySyncFailure.swift
714dbe1486eced9064a487e3b982e2e545dc57b3ac9ad0935bf7e848dc5cdac4  MOTIVO/CommentsView.swift

POST
727408baa64929b55c0dccecafa7eedc912b8713d409e19dfed5cd11298d9a88  MOTIVO/AccountDirectoryService.swift
b717f4b7e41e78115694b84c3ba3d7dddb9c3359a3a6ef2c6ab0534b91e5801b  MOTIVO/AuthManager.swift
afd0ccf4fb1fe9693f6c69a2b4ff699cbee090bfd42eb782ba36c1089c570c60  MOTIVO/AppSetUpView.swift
44a0abbdf577e6e88d69baaba4448359208aafc77b044e59620bde36009260b0  MOTIVO/ProfileStore.swift
e662564a4c0d5dc7085f9037aeeeb7d127a5c459873d472439002acddc9b4490  MOTIVO/ProfileView.swift
f584f2124e40c13376c793585eb7eb2709867df6d6a14633578be0609507f051  MOTIVO/PeopleUserRow.swift
c546e1a6b7224e5c3b17ec4e5fc8e5b36efa5227ab8ac2a0cb1331ce83d45a6c  MOTIVO/PeopleView.swift
41e6b27f32faefd0b0564a3fd959d711d632d800bd61399cedf3491546cc6724  MOTIVO/FollowersListView.swift
867c7d4c54fef3097fcd473109cd1e9d92497aa5e10bdd5542f97993fe592557  MOTIVO/FollowingListView.swift
4869316570b082e7ba2bdb4c1e3f361b5ffe55c32e558a3522b479005ef78a50  MOTIVO/ContentViewRowSupport.swift
3b5c17e7386a2c50f06f4279dd1f20843095de77bf507603c87d58be4a92cac6  MOTIVO/ContentViewSessionRow.swift
5aef1da7643880b2879bd6f7050b3f151b4d386523418d5453efd6e045f78b5f  MOTIVO/ContentViewRemotePostRowTwin.swift
ea0fd396b13a62b3a600c6b196cb1d042f52e44ee5f082b6168bf6d8b98d6170  MOTIVO/SessionDetailView.swift
d696439481ef4b0d721235fc9d6f35d69d1bb4f6bbe6a42b0e2f9198222a5b02  MOTIVO/BackendSessionDetailView.swift
a8de1b785892f7d38787018dd377417e134db05013bef241aafd0aa672ccba35  MOTIVO/ConnectedAttachmentShareUI.swift
72cdf04f401dbc6eba37d264c8b6216046b24dab4c888893638f111d0e1d409d  MOTIVO/ProfilePeekView.swift
488854b69939256713786da34c91e38705a54e5390272220f880cb7ba57cd654  MOTIVO/DirectorySyncFailure.swift
1412c9860f6cd394f3a98460c7bd18c4c027c37b6e4db8994766ab4d8992020d  MOTIVO/CommentsView.swift
```

Test files, post-change:

```
529b1c9d0a989f4d044ce7348c325a1f9ed27889820d91ac85a355bbbe6c1319  MOTIVOTests/C70DirectoryWriteTransportTests.swift
dacef64e36ae5fb1e8615c8774de6920df28976c7c38f6ba879c31cd00cbf13a  MOTIVOTests/C70DirectoryWriteEvidenceTests.swift
439910997af074046b1a690e8ff559c84665030ce91d0106cab50c7510c652e1  MOTIVOTests/C70DirectoryWriteCallerPolicyTests.swift
107ee2d4b0ab08809d97b9bb8aac425ce68be156baa654c6bc06fc37c8ec3855  MOTIVOTests/C70DirectoryWriteCoordinatorTests.swift
8d7e6ed538c21fbfbc12f9325b26c7f7409757f8b3d0a1bece3c5743c17285e4  MOTIVOTests/DirectorySyncFailureTests.swift
e5a10f419815d3337a3000b33cc35a6a7feecb0eef79e8d2b45eb9907110c176  MOTIVOTests/C70WiringPinTests.swift
8ef7c08ddf7a22a6d37b193e2a2081ba6de166b088e8c7172bb31385f2406b3e  MOTIVOTests/DirectorySubtitleTests.swift
dd6444e78c5cbfe0229aa1ed24af430c0a3958187bf3e774dfdc0082a5ca5d5e  MOTIVOTests/AccountIDRemovalTests.swift
```

`git diff --stat`: **24 tracked files** (18 source, 6 test) plus **2 new untracked test files**.
The two invitation documents appear in `git diff` because they were **already modified in the
working tree before this session began**; their mtimes confirm they were not touched.

---

## 4. Warnings — measured by attribution, not by rebuilding a baseline

71 unique warnings in Debug, 71 in Release. **Five fall in files this change touched**, and all
five are pre-existing:

| Warning | Why it is not ours |
|---|---|
| `BackendSessionDetailView.swift:331` `+` deprecated | The construct exists at `HEAD` in the same count |
| `ContentViewRemotePostRowTwin.swift:435` | ditto |
| `ContentViewSessionRow.swift:648` | ditto |
| `SessionDetailView.swift:980` | ditto |
| `SessionDetailView.swift:1149` `duration` deprecated | ditto |

**Checked, not assumed:** no line this change ADDS matches either construct — measured with
`git diff -U0` restricted to added lines, which returned zero in every one of the four files.
So the delta attributable to this change is zero **without** rebuilding a baseline, which is the
narrower and better-evidenced claim.

---

## 5. Test accounting — by class, never as a raw total

### 5.1 Retired — 6 tests, coverage loss declared

| Test | Class | Disposition |
|---|---|---|
| `testGenerationWritesOnlyTheHandleAndOnlyWhileItIsAbsent` | `C70DirectoryWriteTransportTests` | **Coverage REMOVED, not relocated** |
| `testGenerationStopsSilentlyWhenTheFilterMatchesNothing` | same | **same** |
| `testGenerationRetriesOnlyOnAnEvidencedHandleCollision` | same | **same** |
| `testGenerationExpectsOnlyTheHandle` | `C70DirectoryWriteEvidenceTests` | Replaced by `testAReceiptCarryingAHandleIsNotHeldAgainstAPayloadThatNeverSentOne` |
| `testHandleAdoptionAfterGenerationIsGuardedAgain` | `C70SetupCallerStructureTests` | Replaced by `testSetupPerformsNoSuspensionBetweenTheFreshnessDecisionAndCompletion` |
| `testHandleAdoptionIsGuardedAgainstNewerIntentAndIdentity` | `C70ProfileViewEffectGuardTests` | Replaced by `testNoHandleAdoptionSurvivesToBeGuarded`; the generic protection is `testEveryUIEffectSitsBehindBothFreshnessGuards` |

**The three Transport tests are a genuine, unreplaced coverage loss** — they exercised a
network-shaped behaviour (read self row → PATCH under `account_id=is.null` → retry on an
evidenced collision) that no longer exists anywhere in the client. Stated plainly rather than
absorbed into a total.

### 5.2 Converted — 8 tests, 1 helper edit

| # | Test / helper | Class or file | Change |
|---|---|---|---|
| 1 | `testAnExistingRowEditIsAnOwnerBoundPatchAskingForEvidence` | `C70DirectoryWriteTransportTests` | **+ the PATCH body carries no `account_id`** |
| 2 | `testNothingMatchedFallsThroughToGatedCreation` | same | **+ the missing-row CREATION carries none either** |
| 3 | `testANamedHandleCollision…` → `…IsStillTypedButNoLongerNamesAField` | same | Classification kept; copy asserted against `genericMessage` directly |
| 4 | `testOnlyAnEvidencedWrite…` → `testNoOutcomeNamesAFieldAndOnlyAnEvidencedWriteSaysNothing` | `C70DirectoryWriteEvidenceTests` | Collision now reads generic |
| 5 | `testCollisionKeepsItsOwnCopy` → `testACollisionIsStillClassifiedButItsCopyNamesNoField` | `DirectorySyncFailureTests` | Asserts BOTH halves: still classified, no longer named |
| 6 | `testNoNonCollisionFailureNamesTheAccountID` → `testNoFailureAtAllNamesTheAccountID` | same | **Strengthened**: collision joins the list |
| 7 | `testOnCompleteIsReachedOnlyPastTheGuards` | `C70SetupCallerStructureTests` | Re-anchored to the surviving freshness decision |
| 8 | `testTheSetupTailConsumesFreshnessAndNotJustTheOutcome` | same | One assertion dropped (`let capturedGeneration`), two kept |
| — | `write(...)` loses `accountID:`; `selfRow(...)` removed; `row(...)` KEEPS `accountID:` | `C70DirectoryWriteTransportTests.swift` | **Fixture-helper edits, not tests** |

### 5.3 The three Coordinator re-anchorings, counted explicitly

`syncBody()`'s end delimiter was the removed function's name. Three tests read it:
`testEveryUIEffectSitsBehindBothFreshnessGuards`,
`testTheSkipTokenIsConfirmedOnlyOnAnEvidencedWrite`,
`testTheSkipTokenIsInvalidatedWhenADifferingWriteIsSubmitted`. All three are re-anchored to
`persistAvatarToBackendIfPossible` and **each was demonstrated failing against its own guard**
(§7, controls 2 / 2b / 2c).

### 5.4 New — 31 tests in 2 files, 3 classes

| Class | File | Tests |
|---|---|---|
| `DirectorySubtitleTests` | `MOTIVOTests/DirectorySubtitleTests.swift` | **17** |
| `AccountIDRemovalStructureTests` | `MOTIVOTests/AccountIDRemovalTests.swift` | **9** |
| `AccountIDCompatibilityTests` | same file | **5** |

**The structural tests read SOURCE TEXT and prove WIRING, not rendering.** No test in this
target renders a view, and none claims to. The `DirectorySubtitle` tests are VALUE tests: they
establish what the formatter returns, not what was drawn.

### 5.6 The +28 reconciled by ID — CORRECTED

**An earlier revision of §2 said the movement included "+3 previously-skipped now running".
That was FALSE and is withdrawn.** It confused §6.1's targeted-selection omission — three
classes a `-only-testing:` filter silently failed to match — with the suite's six BASELINE
skips, which are the standing opt-in set and are **unchanged: 6 before, 6 after, the same 6**.
Codex established this by comparing actual test IDs across bundles; nothing was re-run to
correct it.

| | Count |
|---|---|
| Genuinely new tests (§5.4) | **31** |
| Replacement tests for retired ones — `testAReceiptCarryingAHandleIsNotHeldAgainstAPayloadThatNeverSentOne`, `testNoHandleAdoptionSurvivesToBeGuarded`, `testSetupPerformsNoSuspensionBetweenTheFreshnessDecisionAndCompletion` | **+3** |
| Renamed conversions — 5 old IDs out, 5 new IDs in | **net 0** |
| Retired (§5.1) | **−6** |
| **Net** | **+28** |

Equivalently, and this is the form Codex verified: **39 new IDs − 11 removed IDs = +28**, with
**zero status changes among surviving tests**. The 11 removed are the 6 retired plus the 5
old names of the renamed conversions.

### 5.5 Final per-class census for the affected classes

```
   5 AccountIDCompatibilityTests
   9 AccountIDRemovalStructureTests
   5 C70ConnectedSetupDecisionTests
   5 C70DirectorySyncLatchTests
  11 C70DirectoryWriteCoordinatorTests
  20 C70DirectoryWriteEvidenceTests
  22 C70DirectoryWriteTransportTests
   3 C70DirectoryWriteValidityBarrierTests
   3 C70LocalSaveFailureMeasurementTests
  19 C70OwnerMaintenanceTests
   4 C70ProfileViewEffectGuardTests
   3 C70SetupCallerStructureTests
   2 C70WiringPinTests
  17 DirectorySubtitleTests
  11 DirectorySyncFailureTests
```

---

## 6. Two evidence limitations, recorded rather than tidied

### 6.1 The first targeted selection silently ran nothing for three classes

`-only-testing:MOTIVOTests/C70DirectoryWriteCallerPolicyTests` names a **FILE**, not a class.
The classes in it are `C70DirectorySyncLatchTests`, `C70ConnectedSetupDecisionTests` and
`C70SetupCallerStructureTests`. That selection matched nothing, reported
`** TEST SUCCEEDED **`, and I read 68 passes as "the converted suites pass" — **a conclusion
inferred from filenames rather than from result IDs.** Found by Codex.

**Superseded by the corrected 12-class run: 114 passed**, including the 3 that had been
skipped. The earlier reading is withdrawn; the run is not repeated.

### 6.2 A sixth existing test file was outside the reviewed boundary

The reviewed scope named **five** existing test files. `MOTIVOTests/C70WiringPinTests.swift`
was not among them, and **the first full-suite run failed on it** —
`testTheGlobalChallengeAndGenerationGateAreUnchanged` required
`guard BackendEnvironment.shared.isConnected else { return nil }` in
`AccountDirectoryService`, which lived inside the removed generator.

Converted to `testTheGlobalChallengeIsUnchangedAndNoGenerationGateRemainsToPin`: the forced
global-auth-challenge assertion is kept **verbatim**, and the removed generator's predicate is
replaced by an assertion that no generation survives at all. **Codex approved this as a bounded
dependency correction.** Boundary is therefore **18 source files and 6 existing test files**,
plus 2 new test files.

---

## 7. Positive controls — each applied, observed failing, and restored

Applied to the working tree with **no overlapping build**, then restored from a copy taken
immediately beforehand.

| # | Mutation | Observed (Claude, transcript only) | What it indicated |
| **1** | `directoryPayload` re-carries `account_id` | **7 Transport tests FAILED**, including both converted payload tests | The payload assertions observe the **real writer's** dictionary, not a fixture |
| **2** | `mayApplyEffects` guard deleted from `syncDirectoryFromCurrentState` | `testEveryUIEffectSitsBehindBothFreshnessGuards` FAILED; other two passed | The re-anchored extract targets **real code**, not an empty string |
| **2b** | A second `directorySyncLatch.confirm` site added | `testTheSkipTokenIsConfirmedOnlyOnAnEvidencedWrite` FAILED | Non-vacuous, on its own guard |
| **2c** | Skip decision moved after the request | `testTheSkipTokenIsInvalidatedWhenADifferingWriteIsSubmitted` FAILED | Non-vacuous, on its own guard |
| **3** | C-70 maintenance feedback surface disabled | `testTheDirectorySyncFailureSurfaceStillExists` FAILED | The change's **highest-risk mistake** is caught |

**Raw evidence for the five controls is `evidence/CONTROLS.md`: a TRANSCRIPT of terminal
output, not a saved log or bundle** — none was written, and Xcode has since pruned the bundles.
The provenance and its weakness are stated at the top of that file rather than in a footnote.

**CODEX DID NOT INDEPENDENTLY VERIFY THESE FIVE RUNS.** The table above records Claude's
contemporaneous reading of terminal output; `evidence/CONTROLS.md` carries the transcripts and
says so before quoting anything. Read the "Observed" column as an observation, never as a
Codex-verified proof.

**Restoration verified by hash, not by inspection.** After the last control,
`AccountDirectoryService.swift` = `727408ba…` and `ProfileView.swift` = `e662564a…`, both
byte-identical to `pre-control-hashes.txt`, and a sweep for control text returned **zero**.
**The full suite and both builds ran AFTER this restoration.**

---

## 8. What is NOT established

- **No device QA.** Nothing here was observed on hardware.
- **No rendering is proven.** Structural tests read source; the subtitle tests are value tests.
- **No production or schema change.** `account_id`, its UNIQUE constraint, both CHECKs, the
  `search_account_directory` handle branch and both RPCs' output are all untouched.
- **The retained server handle matching is NOT inert.** Existing handles remain matchable, under
  unchanged B-37 gates and budgets and subject to authentication, subject entitlement and
  `account_privacy_discoverable`. The new client still forwards arbitrary search text, so a
  typed handle still matches and `@handle` still misses. **No global resolution is claimed.**
- **Codex's acceptance is LOCAL and evidence-qualified**, and does not extend to the original
  control runs, to device behaviour, to rendering, or to Phase 6 closure.
- **Samuel has not signed off.**
