# C-98 — an auth refresh that completes after sign-out or identity withdrawal can repopulate tokens and the backend user id. Prediction, before any edit or run

2026-09-15. Audit R1. Register row C-98, **Unverified** until this unit's evidence.

- **Scope:** `claude-scope-007.md`, as superseded in part by `claude-scope-007-revision-1.md`
  (Codex copy `9f3be6c2…`).
- **Approval:** `codex-scope-review-007-revision-1.md`, whose **seven mandatory clarifications
  are recorded in §2 before any edit or run**.
- **Predictions are hypotheses, not results to force.**

## 1. Source inspection (to be tested)

| Pinned state | Value |
|---|---|
| `AuthManager.swift` | `1b2624d0…` (`@MainActor`) |
| `SessionRefreshPolicy.swift` | `a6f4bf54…` |
| `NetworkManager.swift` | `f593e869…` |
| Supabase Swift | 2.5.1 at `ff883c94…` |

- **The window.** `refreshSupabaseSession` suspends at `supabase.auth.refreshSession` (`:994`).
- **Success writes with no lifecycle check.** It then writes Keychain tokens, both user-id
  defaults and the bearer, and, through `await MainActor.run`, `backendUserID` plus hydration and
  backfill scheduling.
- **Failure withdrawals are unconditional.** The `.withdrawIdentity`/`.terminal` withdrawals also
  run through `await MainActor.run` with no check.
- **Ownership.** Both wrappers clear `sessionRefreshInFlight` unconditionally after awaiting their
  own task.
- **Not restored:** `currentUserID`. The reachable consequence is token, bearer and backend-id
  resurrection, **not** a complete automatic sign-in; no cross-account data access is claimed.
- **Skew.** `SessionReconciliation.hasNewerUsableSession` judges a changed persisted session by
  expiry with **skew 0**. The preflight gate `shouldRefresh` uses **`defaultExpirySkew = 60`**.

## 2. Mandatory clarifications (Codex review 007 revision 1) — recorded before any edit or run

1. **Interception outlives restoration verification.**
   - Both `URLProtocol`s are registered **before** the initial bearer probe.
   - **Teardown order:**
     1. drain tracked tasks and the stub callback group;
     2. restore saved state **with interception still installed**;
     3. temporarily point **only** `baseURL` at the stub for the verification probe;
     4. await the probe and the callback group;
     5. restore the exact saved `baseURL`;
     6. **then** unregister both protocols (also on normal completion).
   - **A probe never uses the saved real base URL.**
   - Snapshot values live in memory only. Assertions and logs expose **match booleans**, never
     captured credentials or actual values, including on failure.
2. **Recovered-session usability keeps the existing skew-0 criterion.**
   - **Definition:** `usableChangedSession` = `currentUserID != nil` ∧ persisted refresh token
     non-empty ∧ persisted access token non-empty ∧ `SessionReconciliation(attempted: presented,
     persisted: …, persistedAccessTokenExpiry: …, now: Date()).hasNewerUsableSession`.
   - That last clause is skew 0, and already requires the token to have changed.
   - **The normal preflight gate (`shouldRefresh`, skew 60) is unchanged.** It is not substituted
     here.
   - **L-3/L-4 and F-3/F-4:** the modelled newer sign-in does **not** restore `currentUserID`, so
     their stale caller **returns `false` even with unexpired persisted B credentials**. Their
     evidence is **preservation**, not a full live sign-in.
3. **`.recoverWithNewerSession` keeps its side effects.**
   - An accepted usable recovered session still reapplies the persisted bearer and schedules
     hydration and backfill per `schedulesDirectoryHydration(after: .recoveredNewerSession)`.
     This runs **synchronously on the main actor, with the guarded current-state read**, and the
     test suppression covers Connected scenarios.
   - **A discarded stale success creates no writes and no scheduling.**
   - Removing the post-network `MainActor.run` hops preserves every existing side effect and
     reason on the legitimate current and recovered paths. The only removals are the explicitly
     rejected stale writes and stale withdrawals.
4. **One added stateful recovery control, R-1 (13 C-98 cases).**
   - **Case:** an older held refresh fails with the SDK-decoded **"Already Used"** error after a
     newer forced same-identity refresh committed, while `currentUserID` remains present. The newer
     access token is **valid but within the 60 s preflight skew** (expires in 30 s).
   - **Required:** the older caller **returns `true`**, retains the newer credentials, bearer and
     backend id, and **withdraws nothing**.
   - **Predicted PASS before and after.**
   - **Why added:** revision 1's 12 tests did not exercise the changed-token recovery branch or the
     skew-0/skew-60 distinction (point 2). Revision 1 is kept as proposed.
5. **Instrumentation is observational.**
   - **Gating:** hooks under `#if DEBUG` and `UnitTestHost.isActive`; suppression defaults
     `false`, is test-only, and is installed **before** any test-owned Connected refresh can
     schedule tasks.
   - **Recording only:** slot hooks record synchronously into a lock-guarded log; they spawn no
     work and change no slot or token state.
   - **C's witness:** C's **actual slot event** is recorded while B is held.
   - **Joins, not events:** caller `Task`s are **joined**; a `finished` event is never treated as
     wrapper completion.
   - **Final census:** coalescers and task owners are counted separately.
   - **Deny-all:** the fail-safe protocol is **instrumentation for requests using the inspected
     `URLSession` paths**, not an OS-level firewall. It rejects unexpected requests and claims no
     control over unrelated sessions.
6. **An unjoinable failure is a real stop.**
   - Isolation and interception stay installed, evidence is preserved, and **the unit and the test
     invocation stop**. No later full-suite class may restore or reuse global state.
   - **Prior focused success is a gate, not a proof** that a later full run cannot hang.
   - No broad reset, no kill of other simulator work, **no restoration while a test-owned callback
     or task survives**.
   - **Callback counts and quiet intervals never substitute for awaiting tracked `Task`s.**
7. **Measured-before boundary and SDK storage.**
   - **The real path:** each held-request test confirms the **real SDK `refreshSession` request was
     intercepted** (method, path `/auth/v1/token`, `grant_type=refresh_token`, presented token)
     **and** the expected success decode or error classification occurred. A stub or setup failure
     is **not** the intended product reproduction.
   - **Contrary results:** valid contrary results are counter-evidence.
   - **SDK storage:** the session item (`defaultLocalStorage` = `KeychainLocalStorage(service:
     "supabase.gotrue.swift")`, key `"supabase.session"`) is compared before and after **in memory
     at 2.5.1**. **The confirmed-session persistence path is not exercised** (fixture users carry
     no confirmation dates), and that limitation is retained. **On mismatch nothing is removed or
     rewritten: stop and report.**
   - **Out of scope:** protected files, retained data, ordinary Debug/Release behaviour and prior
     phase work.

## 3. Seam (step 1; refresh and ownership logic byte-identical)

`AuthManager.swift`, `#if DEBUG`:
- a file-scope `enum AuthRefreshSlotEvent: Equatable { coalesced(String), startedNew(String),
  finished(String) }`;
- an `extension AuthManager` holding `static var unitTestSuppressesPostSessionScheduling = false`,
  `static var unitTestRefreshSlotHook`, and `unitTestReachSlot(_:)`, which calls the hook only when
  `UnitTestHost.isActive`.

**Call sites:**
- **Suppression:** the first statement of `scheduleDirectoryHydrationIfNeeded` and
  `scheduleAccountIDBackfillIfNeeded` returns when `UnitTestHost.isActive &&
  unitTestSuppressesPostSessionScheduling`.
- **Slot events,** in **both** wrappers: `.coalesced` before `return await existing.value`;
  `.startedNew` after `sessionRefreshInFlight = task`; `.finished` after `let ok = await
  task.value`.

## 4. Fix (only as reproduced; `AuthManager.swift`)

**Atomicity.** After the network await, every check runs in the **same uninterrupted main-actor
segment** as its writes or withdrawal; the `await MainActor.run` hops become direct code.
`presented` is the refresh token captured before the await; `persisted` is re-read after it.

| After the await | `persisted == presented` | `persisted` changed or nil |
|---|---|---|
| success | **existing writes and scheduling** → `true` | **no write, no schedule** → `usableChangedSession` |
| `.ignore` | withdraw nothing → `false` (unchanged) | withdraw nothing → `false` |
| `.recoverWithNewerSession` | (not produced by the policy for an unchanged token) | if `usableChangedSession`: **existing bearer reapply and scheduling** → `true`; else no write → `false` |
| `.withdrawIdentity` / `.terminal` | **withdraw** (unchanged) → `false` | **withdraw nothing** → `usableChangedSession` |

**Ownership, in both wrappers:** `if sessionRefreshInFlight == task { sessionRefreshInFlight = nil }`.

**Unchanged:** `SessionRefreshPolicy`, the preflight gate, `signOut`, `clearConnectedIdentity`,
sign-in, the 401 handler, callers and signatures.

## 5. Tests and predictions — `MOTIVOTests/C98AuthRefreshLifecycleTests.swift`, 13 tests

"Before" = seam present, logic unchanged. All mutation happens behind the stub (`127.0.0.1:8`)
and the deny-all protocol.

| ID | Mode | Scenario | Before | After |
|---|---|---|---|---|
| A-0 | local sim | control: immediate success A2 | PASS | PASS |
| F-1 | local sim | control: current token terminal, so withdraw | PASS | PASS |
| F-2 | local sim | control: current token transient, so retain, `false` | PASS | PASS |
| **R-1** | connected + suppression | control: older held refresh "Already Used" after a newer forced commit (access +30 s) → `true`, newer state kept, nothing withdrawn | **PASS** | **PASS** |
| **L-1** | local sim | held → `signOut` → success | **FAIL** (resurrection) | PASS (`false`, cleared; `currentUserID` nil both runs) |
| **L-2** | local sim | held → `clearConnectedIdentity` → success | **FAIL** | PASS |
| **L-3** | local sim | held → `signOut` → arrange B (unexpired) → success | **FAIL** (A overwrites B) | PASS (B preserved; **`false`**, `currentUserID` nil) |
| **L-4** | local sim | as L-3, release terminal | **FAIL** (withdraws B) | PASS (B preserved; `false`) |
| **F-3** | local sim | held → `signOut` → arrange B (expired) → success | **FAIL** | PASS (B preserved; `false`) |
| **F-4** | local sim | as F-3, release terminal | **FAIL** | PASS |
| **O-1a** | connected + suppression | ownership with A and C from `ensureValidBackendSession` | **FAIL** (C `.startedNew`, 3 requests) | PASS (C `.coalesced`, 2 requests) |
| **O-1b** | connected + suppression | ownership with A and C from `ensureValidSession` | **FAIL** | PASS |
| **O-2** | connected + suppression | stale success after a newer forced commit | **FAIL** (A2 overwrites B2) | PASS (B2 kept; `true`) |

**Counts:**
- **Before the fix:** 4 pass (A-0, F-1, F-2, R-1); **9 fail**.
- **Focused:** 13 + 22 `SessionRefreshPolicyTests` = **35**.
- **Full unit target:** 481 + 13 = **494** (491 passed, 3 known queue skips, if all new cases pass).

**Stop rules:**
- **Invalid ordering, a missing witness, or a stub/setup failure** is inconclusive; stop.
- **A valid run contradicting a prediction** is counter-evidence, preserved and returned for review,
  with no speculative fix and no reruns.
- **An unjoinable task or callback** is a real stop (§2.6).
- **An SDK storage mismatch:** stop without rewriting.

## 6. Limitations

- **The newer sign-in is modelled** by persisted state only; real Sign in with Apple and its
  in-memory transitions are not exercised.
- **The stub is not GoTrue.**
- **The compare-and-set** guards persisted-token changes only; it does not prove that every
  lifecycle change rewrites the token.
- **SDK coverage:** confirmed-session storage is not exercised; evidence is tied to 2.5.1.
- **No frequency, device or live-backend claim.**
