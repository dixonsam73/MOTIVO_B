# Fresh-join fix (F1 + F2) — implementation evidence

**21 September 2026. Claude.** Scope: §11 of `docs/fresh-join-investigation-2026-09-21.md`,
approved by Codex.

## STATUS

**CODEX LOCAL CODE AND VALIDATION ACCEPTANCE GRANTED, 21 September 2026**, for F1 and F2 at the
four hashes in §4. Codex independently verified the retained bundle (1039 total / 1032 passed /
0 failed / 7 skipped), the separate re-check, the five original control logs, the incremental
diffs, both successful builds, all four final hashes, the 17 + 7 untouched hashes, the protected
hashes, and `HEAD` at `05ad6a8`.

**PENDING SAMUEL'S DEVICE QA. NOT committed, NOT pushed, NOT device-verified.** Phase 6 remains
open and this closes nothing.

**No commit, push, production statement, schema change, credential or device action.** The
accepted handle-removal unit is preserved: **17 source and 7 test files byte-identical** to its
manifest, verified after the work. `AGENTS.md` and both invitation documents untouched.

---

## 1. Artifacts

```
/private/tmp/claude-501/-Users-samueldixon-Documents-Xcode-projects-MOTIVO-B-MOTIVO/c657c407-b562-4523-b151-9170cc9ae8a2/scratchpad/freshjoin/
  baseline/    pre-edit copies + hashes of the 3 accepted files edited here
  logs/        targeted-new, targeted-transport, full-suite-final, unshare-recheck, build-{Debug,Release}, warnings-{Debug,Release}
  controls/    control-A..E logs, pre-control copies and hashes
  bundles/     both .xcresult bundles, copied OUT of DerivedData
  post-hashes.txt, untouched-{source,test}-{now,accepted}.txt
```

**Every run here was `tee`d at the time and both bundles copied out immediately** — the
previous unit's controls survived only as transcripts because Xcode pruned them.

| Bundle | Result |
|---|---|
| `Test-MOTIVO-2026.09.21_10-50-41-+0100.xcresult` | **1039 total / 1032 passed / 0 failed / 7 skipped** |
| `Test-MOTIVO-2026.09.21_10-56-49-+0100.xcresult` | `UnshareDurabilityTests` re-check — 12 total / 12 passed / 0 skipped |

## 2. Results — TWO DISTINCT RUNS, reported as two

**Not combined into "1033/0/6". They are separate runs and one does not amend the other.**

- **Full suite: 1032 passed, 0 failed, 7 skipped.** This is the acceptance run.
- **Targeted re-check: `UnshareDurabilityTests` 12/12 passed, 0 skipped.** Diagnostic only.

Debug and Release builds both **SUCCEEDED**.

### The seventh skip — environment, not regression, and established rather than asserted

`UnshareDurabilityTests.testAlreadyAbsentObjectIsSuccessNotPoison` skipped in the full run and
**passed in the accepted handle-removal run**. It is opt-in behind `skipUnlessLocalStack()`,
which probes `127.0.0.1` with a **5-second timeout**.

**What the measurements show, and no more:** its eleven siblings passed in the same run, so the
local stack was reachable then; the skipped instance recorded **6.236 s** against **2.955 s**
when it passed and **2.891 s** on the re-check; and re-run in isolation it **passes**. The
change touches nothing in the publish/unshare path.

**These are CONSISTENT WITH a transient probe or load effect. They do not prove that cause.**
No probe result, timeout or system-load measurement was captured, so the exact mechanism is
**not established** — an earlier revision of this record read the timings as demonstrating it
and that reading is withdrawn. What is evidenced is the skip itself, the surrounding timings,
and an isolated pass.

## 3. Warnings — zero delta, by attribution

**71 unique warnings in Debug and 71 in Release — identical to the accepted baseline's 71/71 —
and ZERO of them fall in either touched source file.** No baseline rebuild was needed.

## 4. Hashes

```
3f61af7cffa85802f103cc2ffe7bf3669c085706f3a9e7d40e03994343892b0a  MOTIVO/ProfileView.swift
5cf6be3ddedf8b458a523f3b0e75b03755a30cdc80cbbc3f18a01000306ea766  MOTIVO/MembershipAttestationCoordinator.swift
0ae946b2c2b5f609599452b1eb164aaf2c2955dc6034160d8cffbc7bbe0f521a  MOTIVOTests/C70DirectoryWriteTransportTests.swift
24a8aa4f62db091d0cfc020cef9a1bb49eb7094b69a7faff4287888c44364817  MOTIVOTests/FreshJoinContinuationTests.swift
```

Pre-edit baselines of the three accepted files edited here are in `baseline/`, so review can be
on the **incremental diff** rather than the combined change.

**Untouched from the handle-removal manifest: 17 source, 7 test — both verified identical.**

## 5. Test accounting

| Class | File | Tests | Status |
|---|---|---|---|
| `FreshJoinContinuationStructureTests` | `FreshJoinContinuationTests.swift` | 8 | new |
| `DirectoryReconciliationPolicyTests` | same | **10** | new |
| `AttestationCompletionPublicationTests` | same | 9 | new |
| `C70DirectoryWriteTransportTests` | existing | 22 → **28** | 6 added, none changed or removed |
| `P6I05AttestationOwnershipTests` | existing | 8 | **unchanged and green** — invariant, cooldown and single-flight intact |

**Nothing was retired, converted or weakened.**

### The arithmetic, corrected

**An earlier revision of this record said `DirectoryReconciliationPolicyTests` held ELEVEN tests.
It holds TEN.** Codex caught it against the bundle and the source; re-counted here from the
retained acceptance log and from `func test` in the file, which agree.

**8 + 10 + 9 = 27 in the new file, plus 6 in the transport suite = 33 new.
1006 → 1039**, which is the retained bundle's own total.

## 6. Positive controls — five, each with a RETAINED LOG

| # | Mutation | Log | Observed |
|---|---|---|---|
| **A** | F1's join branch moved back after the gate branch | `control-A.log` | `testTheJoinBranchPrecedesTheGateUnwind` **FAILED**, 7 others passed |
| **B** | A false policy answer also consumes the completion | `control-B.log` | `testAnEstablishingCompletionThatArrivesBeforeTheFailureStillReconciles` **FAILED**, alone — this is exactly the success-before-failure gap Codex found |
| **C** | Consumption removed | `control-C.log` | `testAPersistentlyRefusedCreateIsRetriedExactlyOnce` **FAILED**, alone — boundedness |
| **D** | A joining caller publishes under its own scope | `control-D.log` | `testAJoiningCallerDoesNotPublishItsOwnScope` **FAILED**, alone |
| **E** | A superseded run publishes a completion | `control-E.log` | `testASameOwnerResetDuringAnInFlightRunPublishesNoCompletion` **FAILED**, alone |

**Each control failed exactly the test whose subject it broke.** Restoration verified by hash
against `controls/pre-control-hashes.txt`, and a sweep for control text returned **0**. **The
full suite and both builds ran after restoration.**

## 7. Evidence qualification — a test whose NAME overclaims

**`testResetClearsTheCompletionEvenWhenItIsTheOnlyThingLeft` does NOT isolate completion-only
state, and its name says it does.** Codex established this. A normal completion leaves
`lastOutcome` and `lastAttemptAt` populated too, so the test body proves the weaker and still
useful statement: **a normal `reset()` clears the completion.** It does not exercise the case
where the completion is the only populated field.

**The stronger property is visible in source rather than in that test:** `reset()`'s early-return
guard includes `lastCompletion == nil` among its conditions, so a completion standing alone
does not short-circuit the clear.

**Deliberately NOT done, per Codex:** no test-only state mutation was added to manufacture the
isolated case, and the test was not re-run merely to rename it. **The name is a naming defect
carried openly**, and a rename belongs in a later pass where a run is happening anyway.

## 8. What is NOT established

- **No device QA.** Samuel runs it when Codex and I say the build is ready.
- **No rendering is proven.** The F1 tests read source and prove WIRING; the policy tests are
  value tests; the reconciliation tests drive the real writer, not a view.
- **The historical failed request's cause remains UNKNOWN.** The inferred timing in
  `docs/fresh-join-investigation-2026-09-21.md` §3 is a hypothesis; **no request-level trace was
  ever captured, and none of this evidence is one.** T12 makes the two candidate refusals
  distinguishable in the suite; it does not say which occurred on device.
- **No server or schema change**, and no gate was altered.
- **Codex's acceptance is LOCAL code and validation only.** It does not extend to device
  behaviour, to rendering, to the seventh skip's exact cause, or to Phase 6 closure.
- **Samuel has not run device QA and has not signed off.**
