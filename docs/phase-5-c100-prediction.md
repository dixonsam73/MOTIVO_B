# C-100 — the test host overwrote the backend mode; local-stack tests trusted it. Prediction, before any fix

2026-09-14. **Scope: test fixtures and the unit-test host only.** C-101, B-43 and C-3
are separate. No deployment, no push. The account holder's personal Études Dev
account, installation, history and in-progress session are not involved — this
unit runs only on the simulator test host and the local stack.

## 1. The writer — identified from a call stack, not inferred

A temporary probe (`MOTIVOTests/C100WriterProbe.swift`) observed the
`backendMode_v1` UserDefaults key with KVO, which is delivered synchronously on
the writing thread, after doing exactly what a local-stack `setUp` does
(`setBackendMode(.backendConnected)`). Run alone, `-test-iterations 2`:

- **Iteration 1 (first test in the process):** 0.227 s after the test's write,
  `localSimulation` was written by
  `SwiftUI onReceive(connectedMembershipStore.$membershipState)` →
  `MOTIVOApp.handleMembershipState` → `AppModeManager.applyActivation(auth:isEntitled:)`
  → `applyMode` → `applyBackendRuntimeMode` → `setBackendMode(.localSimulation)`.
  Final mode: `localSimulation`.
- **Iteration 2:** no write after the test's own. Final mode: `backendConnected`.

So the host app's **launch-time StoreKit membership read resolving not-entitled**
writes Solo's backend mode inside the unit-test host, shortly after the first
test's setup. That is C-100's race. `MOTIVOApp` has four more launch-time
activation writers of the same kind (`onAppear`, and the `currentUserID` /
`backendUserID` receivers); they are removed by the same gate.

## 2. The change

**App — scoped strictly to the hosted unit-test process.**
- `UnitTestHost.isActive`: `#if DEBUG` **and** the XCTest configuration environment
  variable present; `false` in every Release build and in every ordinary Debug
  launch.
- `MOTIVOApp` skips `connectedMembershipStore.start()` and its five
  `applyActivation` calls when `UnitTestHost.isActive`. **The gate is at the
  `MOTIVOApp` call sites, not inside `AppModeManager`,** so any test that calls
  `applyActivation`/`applyMode` directly is unaffected, and the Debug viewer's
  own activation is untouched. StoreKit code is unchanged. **Corrected on
  review (Codex review 001, 2026-09-14):** this line previously said StoreKit is
  "simply not started by the test host". That overstated the gate. It suppresses
  exactly `connectedMembershipStore.start()` and the five app-owned
  `applyActivation` calls. **Host side effects that still run, ungated, include
  the foreground `connectedMembershipStore.refreshEntitlement()`
  (`MOTIVOApp.swift:370`) and the scene-phase foreground refresh/flush path.**
  None was observed writing the backend mode, and the negative control shows the
  measured writer is suppressed; they are recorded as outside this fix, not as
  gated.

**Tests — shared support plus the eight local-stack classes.**
- **Disposable identities:** each class creates the `auth.users` rows it uses
  through the local auth admin API with an explicit id (`…0f0001`, `…0f0002`,
  `…0f0065`, `…aaa1`, `…bbb1`), idempotently, and **verifies each exists** —
  measured: the API accepts an explicit id and answers a repeat with 422
  `email_exists`, which is accepted only after confirming the user by id.
- **Real-backend requirement in setUp** (for classes that set Connected there):
  mode is `backendConnected`, configuration and base URL are the local stack, and
  `BackendEnvironment.shared.publish` / `.follow` resolve to the HTTP services.
  **Unmet requirement = the test FAILS with a named reason**, never passes.
  An unreachable local stack still SKIPS, as today.
- **Activation-write sentinel for the whole test:** KVO on the mode key; any write
  whose call stack contains a `MOTIVOApp` frame fails the test in `tearDown`,
  quoting the stack. Tests' own deliberate transitions (e.g.
  `PublishServiceConnectedDeleteTests` switching to `.backendPreview`) are
  allowed, because their stacks carry no `MOTIVOApp` frame.
- `SyncQueueOrderingTests` (stub server, same exposure) gets the same guard with
  its stub base URL.
- A support test asserts `UnitTestHost.isActive` is `true` inside the test
  process, so the gate cannot be silently inactive.

## 3. Predictions

- **P1 — probe after the fix, `-test-iterations 2`:** exactly **one** write in
  **both** iterations (the test's own), final mode `backendConnected` both times.
- **P2 — focused, after a fresh `supabase db reset --local` (so `…aaa1`/`…bbb1`
  and every other identity are ABSENT):** the eight local-stack classes **47/47
  pass** — StalePath 4, UnshareDurability 12, PdfAttachmentMime 2,
  DirectionalFollowDelete 4, AttachmentPreparationAtomicity 4, SharedOnlyUpload 5,
  PublishServiceConnectedDelete 8, OmissionIdentity 8. Queue classes: acceptance
  4 pass, reproduction 3 skip, reset 2 pass. Support tests pass.
- **P3 — first-in-process repeats:** `DirectionalFollowDeleteTests` and
  `UnshareDurabilityTests.testAlreadyAbsentObjectIsSuccessNotPoison`, each alone
  with `-test-iterations 2`, pass **both** iterations.
- **P4 — negative control:** with only the `MOTIVOApp` gate reverted, the same
  first-in-process run **fails in iteration 1 with the sentinel's message naming
  `MOTIVOApp`** — proving the guard detects the mechanism rather than passing
  vacuously. The gate is then restored and the file verified byte-identical to
  the pre-control version.
- **P5 — full suite, probe removed (verified as a pure deletion):** every declared
  test executes; **all pass except the three reproduction skips; zero failures.**

**Previous evidence is retained, not replaced:** the full suite of 2026-09-14
recorded 433 declared, 429 passed, 3 skipped, 1 failed
(`UnshareDurabilityTests.testAlreadyAbsentObjectIsSuccessNotPoison`), and the
earlier run recorded four `DirectionalFollowDeleteTests` failures.

Any miss is recorded as a miss and diagnosed before a further run.

## 4. Results P1–P4 (2026-09-14)

Evidence: `/Users/samueldixon/Documents/Codex/2026-09-12/a/outputs/Etudes-Claude-Codex-overnight-2026-09-14/claude-evidence/c100/`.

| Prediction | Result | Evidence |
|---|---|---|
| **P1** probe after fix, 2 iterations | **Outcome met; count MISSED.** No host-app write in either iteration; final mode `backendConnected` both times; `UnitTestHost.isActive` true both times. Iteration 1 recorded **one** write (the probe's own); iteration 2 recorded **zero**, not one — `setBackendMode` returns early when the stored value is already the requested one (the C-55 guard), and iteration 1 left it Connected. The prediction miscounted a no-op write; no host write occurred. | `p1-probe/` |
| **P2** focused, after a fresh `db reset --local` | **Met.** Identities present before the run: **0**; after: **5** (created by the tests). Local-stack classes **47/47 passed** (StalePath 4, UnshareDurability 12, PdfAttachmentMime 2, DirectionalFollowDelete 4, AttachmentPreparationAtomicity 4, SharedOnlyUpload 5, PublishServiceConnectedDelete 8, OmissionIdentity 8). Queue: acceptance 4 passed, reproduction 3 skipped (each naming its unexercised sequence), reset 2 passed. Support gate test passed. **57 executed: 54 passed, 3 skipped, 0 failed.** | `p2-focused/` |
| **P3** first-in-process repeats | **Met.** `DirectionalFollowDeleteTests` alone ×2: all 4 cases passed in both iterations. `UnshareDurabilityTests.testAlreadyAbsentObjectIsSuccessNotPoison` alone ×2: passed both — both previously failed their first iteration. | `p3-first-in-process/` |
| **P4** negative control, gate reverted | **Met.** With the ungated `HEAD` `MOTIVOApp.swift` in place, iteration 1 of `testDeclineDeletesOnlyTheIncomingRequest` failed on **both** guards: setUp's requirement ("backend mode is localSimulation, not backendConnected") and tearDown's sentinel, quoting `AppModeManager.applyActivation` and `MOTIVOApp.handleMembershipState` — the originally measured writer. Iteration 2 and every other case passed. Gated file restored: sha256 `e3ed5db1…` before and after, **identical**; its only difference from `HEAD` is the six gated lines. XCTest additionally listed the thrown setUp error as a generic "skipped" line inside the already-failed repetition; it adds no information. | `p4-negative-control/` |

The temporary probe was removed before P5 (it was never tracked, so the removal
leaves no diff); its source is preserved at `p5-full-suite/C100WriterProbe.removed.swift`.

## 5. Result P5 — full suite (2026-09-14)

**Met.** Probe removed first (no git trace; zero references remain). `MOTIVOTests`,
Debug, iPhone 17 Pro simulator:

| | Declared | Executed | Passed | Skipped | Failed |
|---|---|---|---|---|---|
| **After C-100** | **434** | **434** | **431** | **3** | **0** |
| Previous run, retained (before C-100) | 433 | 433 | 429 | 3 | **1** |

The one additional declared test is `LocalStackTestSupportTests.testUnitTestHostGateIsActiveInsideTheTestProcess`.
The three skips are the queue reproduction cases, each naming the sequence the
C-87 fix made unreachable. The previously failing
`UnshareDurabilityTests.testAlreadyAbsentObjectIsSuccessNotPoison` passes.
Evidence: `claude-evidence/c100/p5-full-suite/` (`full.xcresult`, `census.txt`,
`non-passing.txt`). **This was one run following the diagnosed fix, not a rerun
until green.**
