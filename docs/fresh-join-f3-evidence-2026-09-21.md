# F3 — initial directory publication after a fresh join. Implementation evidence

**21 September 2026. Claude.** Scope: §13 of `docs/fresh-join-investigation-2026-09-21.md`,
approved by Codex.

## STATUS

**CODEX LOCAL CODE AND VALIDATION ACCEPTANCE GRANTED, 21 September 2026**, at the four hashes in
§4. Codex independently verified the retained bundle (1060 / 1054 / 0 / 6), the original F/G/H
control logs, both successful builds with zero errors, the four final hashes, the 16 untouched
sources and 7 untouched tests, the unchanged F2 coordinator, the protected hashes, and `HEAD` at
`05ad6a8`, and read the incremental `AuthManager`/`ProfileView` logic and tests. **No remaining
source blocker.**

**DEVICE QA RUN 21 September 2026 (Steve Jerkz). COMMITTED ON SAMUEL'S EXPLICIT AUTHORISATION;
NOT PUSHED — Samuel pushes.** Phase 6 remains open; this closes nothing.

### What the device run established, and what it did not

**Established:** on the latest build, after a successful purchase, the directory row
**Steve Jerkz / Prague / [Guitar]** was present with `connected_member = true` and **no
navigation, edit or feed refresh** — the F2/F3 failure mode from the Daniel run did not recur.
Identity `f0ba3610…` created 12:51:17; independent read-only server check at 12:52:47.

**NOT established, and not to be read into it:**

- **The run is NOT a clean first-attempt join.** The first monthly purchase attempt displayed
  approximately *"we are unable to process your membership"*; Samuel returned to Profile and
  purchased again, and the second succeeded. **The run contains navigation and a retry before
  success, so it cannot score a first-attempt clean join.**
- **The first purchase failure is UNEXPLAINED.** All 98 console lines were read and contain no
  purchase outcome, StoreKit error domain or code, or attestation response for the failed
  attempt. **It must not be attributed to Sandbox or to any vendor rather than to the app** —
  there is no evidence either way. `MembershipSelectionView` renders `.failed(error)` as
  "Purchase unavailable" plus `error.localizedDescription`, and `ConnectedMembershipStore`
  catches purchase errors **without a structured purchase-error log**, which is why the console
  cannot settle it.
- **Which request created the directory row was not captured.**

**Samuel plans a fresh-install retest.** The missing purchase diagnostic is recorded as an
observability gap, not as a defect attributed to anyone.

**No commit, push, production statement, schema change, credential or device action.**

---

## 1. Artifacts

`/private/tmp/claude-501/-Users-samueldixon-Documents-Xcode-projects-MOTIVO-B-MOTIVO/c657c407-b562-4523-b151-9170cc9ae8a2/scratchpad/f3/` — `baseline/` (pre-F3 copies + hashes), `logs/`, `controls/`,
`bundles/`, `post-f3-hashes.txt`, `untouched16-{now,accepted}.txt`.
**Every run `tee`d at the time; the final bundle copied out of DerivedData immediately.**

## 2. Results

**The BUNDLE is authoritative: `Test-MOTIVO-2026.09.21_12-24-23-+0100.xcresult` —
1060 total / 1054 passed / 0 failed / 6 skipped.**

**A discrepancy, stated rather than smoothed over:** my log-line grep reports **1053** passed.
The regex matches XCTest-formatted lines only, and at least one swift-testing test is reported
differently, so **the grep is a lossy proxy and the bundle is the number to trust.** Both are
recorded; neither was chosen for convenience.

**Skips are back to the baseline SIX** — the same six as the handle-removal acceptance run. The
seventh seen in the F2 run does not recur, which is consistent with the transient reading
recorded there and still does not prove its exact cause.

Debug and Release both **SUCCEEDED**.

## 2.1 Test-ID accounting — reproduced from the two retained bundles

**Not taken on trust: recomputed here by diffing test IDs between the F2 bundle
(`10-50-41`) and the F3 bundle (`12-24-23`), both retained.**

| | |
|---|---|
| Added IDs | **22** |
| Removed IDs | **1** |
| **Net** | **+21 — 1039 → 1060** |

**The one removed ID is `DirectoryReconciliationPolicyTests.testNoOutstandingFailure
NeverReconciles()`, and it is an INTENDED F3 change, not unexplained coverage loss.** Its
assertion — that no outstanding failure always means no reconciliation — became false by design
when F3 added the initial-publication path. It is **replaced** by
`testAReturningMemberWithNoAbsenceEvidenceNeverReconciles()`, which pins the property the old
test was actually protecting: a member whose row already exists, having no absence evidence,
still writes nothing however many completions arrive.

**The only surviving-test status change in the whole suite is
`UnshareDurabilityTests.testAlreadyAbsentObjectIsSuccessNotPoison()`, Skipped → Passed** — the
opt-in local-stack test that skipped once in the F2 run. **The same six standing skips are
unchanged.** No other test changed status in either direction.

## 3. Warnings

**71 unique in Debug, 71 in Release — identical to the accepted baseline — and ZERO in either
touched source file.** No baseline rebuild needed.

## 4. Hashes

```
c77b63d5087a5911fff2bcaba6ad868d7e68944ac0e19eadd25af2e700939da7  MOTIVO/AuthManager.swift
e5d54af754b670d32757184c598cec8798a3e51c03bcad5b7ec0e5b260418c78  MOTIVO/ProfileView.swift
4d1e7ffcc88cd21b184e8971855216fd50789243bbed6b8aa93ac7dda497cd9b  MOTIVOTests/FreshJoinContinuationTests.swift
99dbf65fe55ee871dc16ba2da1c314988fc507dfba4da2a3b535339ef2ae1705  MOTIVOTests/C70DirectoryWriteTransportTests.swift
```

**Untouched and verified: 16 accepted sources, 7 accepted tests, and
`MembershipAttestationCoordinator.swift` byte-identical to its F2-accepted state** — F3 did not
touch it, as scoped. Pre-F3 baselines are in `baseline/` for incremental review.

## 5. What was built

| Piece | Where |
|---|---|
| `DirectoryRowAbsence` + `applyDirectoryRowAbsence`, published only when the fetch's captured owner AND generation still hold | `AuthManager` |
| Scope captured **before** `fetchSelfRow`; both hydration outcomes route through the one guarded applier | `AuthManager` |
| Policy widened: repair path **OR** (current absence evidence AND no current applied evidence) | `ProfileView` |
| `DirectoryReconciliationEvaluator` — the per-screen state and the code the view itself runs | `ProfileView` |
| Applied evidence from `result.generation`, recorded only in the accepted branch | `ProfileView` |
| Events 1+3 in one observer over both async inputs; event 4 at the END of `onAppearLoad` | `ProfileView` |

**`backendBootstrapState` is unchanged and unread by the policy**, and hydration is otherwise
untouched.

### Two implementation notes worth review

- **The two observers had to become one.** Adding a second `.onChange` to this view body made
  the type-checker fail outright ("unable to type-check this expression in reasonable time"), so
  both inputs are observed through one `Equatable` struct in which **both fields participate**.
- **Event 4 sits LAST in `onAppearLoad`**, after `load()` and the location rehydration, because
  a publish reads its snapshot from the live screen: evaluating earlier would publish the
  initial empty defaults over a real profile. Pinned by a test.

## 6. Remount behaviour — the bounded honesty

**Per-screen state is `@State` and RESETS ON REMOUNT.** This scope therefore does **not** promise
zero writes across arbitrary reopens of Profile while absence evidence is still standing: each
fresh mount may publish once more. It is bounded by a deliberate user action, never by a timer,
and it stops entirely once a write is evidenced within a mount. Recorded in source and here.

## 7. Positive controls — three, each with a retained log

| # | Mutation | Log | Observed |
|---|---|---|---|
| **F** | The widened condition reverted to failure-only | `control-F.log` | **6 FAILED**, including both fresh-join writer tests and the no-error policy test |
| **G** | Row absence dropped from the observed inputs (trigger 3 removed) | `control-G.log` | `testBothAsynchronousInputsAreObservedAndAppearanceReevaluates` **FAILED**, alone — and it fails **for that reason**, which the behavioural driver could not have caught |
| **H** | Evidence compared by owner only, generation dropped | `control-H.log` | The same-generation and A→B→A tests **FAILED**, alone |

Restored byte-identical by hash. **A control-text sweep returned three matches that are NOT
mine** — pre-existing "CONTROL FAILED" strings in three unrelated test files; checked
individually rather than trusted to a count.

## 8. Limits — what the evidence does NOT establish

- **The `applyDirectoryRowAbsence` tests prove the production GUARD, not a delayed network
  fetch.** No `fetchSelfRow` runs and no identity really changes mid-await; what connects the
  guard to real hydration is the before-await capture and the two call sites, pinned separately
  by structural assertions. **Neither half proves the other.**
- **The behavioural driver runs the production evaluator, not the view's observers.** It would
  keep passing with every `onChange` deleted — which is exactly what control G demonstrates, and
  why both kinds of test exist.
- **Structural tests read source and prove WIRING, not rendering.** Nothing in this target
  renders a view.
- **The historical failed request's cause remains UNKNOWN.** The source account in §12.1 of the
  investigation is supported, not captured; a silent screen is also consistent with a superseded
  or not-permitted path, and that categorical claim was corrected.
- **No device QA.** Samuel's fresh-join test is the next step and has not been run.
- **Codex's acceptance is LOCAL code and validation only.** It does not extend to device
  behaviour, to rendering, to the F2 run's transient skip cause, or to Phase 6 closure.
- **Samuel has not signed off.**
