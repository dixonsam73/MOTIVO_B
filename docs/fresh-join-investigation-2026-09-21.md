# Fresh-join QA failure — investigation

**21 September 2026. Claude, read-only.** Source read at the working tree (HEAD `05ad6a8` plus
the accepted, uncommitted handle-removal unit). **No implementation, no commit, no push, no
production or schema statement, no device action, no purchase, no reset.** The handle-removal
source and test bytes are unchanged and still match the accepted manifest hashes.

**Two defects are traced below. One is structural and confirmed by reading control flow. The
other has a confirmed SHAPE and an UNRESOLVED CAUSE**, with two candidate refusals that are
distinguishable on the wire and have not been distinguished. **Nothing here is labelled a
measured cause.**

**Scope guard:** nothing in this note touches age-policy or sharing behaviour, and the fixes
proposed must preserve C-70's lapsed-owner PATCH, real-error reporting, and the identity and
freshness guards. **No blind delays, no retry loops, no swallowing a genuine refusal.**

---

## 1. Measured facts, as reported and independently read

| # | Fact | Source |
|---|---|---|
| M1 | Lapsed-owner maintenance PASSED: `Ben Craft` / `London QA` persisted; directory row matched while `entitled_until` was in the past | `docs/lapsed-profile-device-qa-2026-09-21.md`, Codex read 08:29:29 |
| M2 | Fresh onboard as Clara Reed / Bristol / Cello; subscription inactive before joining | Samuel |
| M3 | Pre-join: no old directory row, no Clara row; `backendMode_v1 = localSimulation` | Codex, read-only |
| M4 | **Joining presented SIWA first, and then required re-entering Explore Connected** | Samuel |
| M5 | Returned to Profile with details intact and the red *"We couldn’t confirm your profile changes were saved to Connected."* No feed refresh, no further interaction | Samuel |
| M6 | New identity `ab4b1b0e…` created **08:44:09.757503+00**; `connected_member = true`; provenance `sandbox_only`; **no directory row** at that inspection | Codex, read-only |
| M7 | After closing/reopening Profile **without editing**: warning gone, and a directory row **exists** — `Clara Reed / Bristol / [Cello]`, `connected_member` still true | Codex, read-only |

**What M6 does NOT establish:** membership state *at the moment of the failed request*. Both
inspections happened after membership was live, so they are consistent with a pre-membership
refusal without evidencing one.

---

## 2. Defect 1 — the SIWA→join continuation. **CONFIRMED BY CONTROL FLOW**

Codex's trace is independently verified here against the source, and it is correct.

### The path

1. `ProfileView.continueToConnectedJoin()` (`:1287`). With **no** identity it takes the `else`
   branch: `connectedSignInIntent = .join`, `showConnectedSignInSheet = true` (`:1297-1298`).
2. The sheet body is `signedOutGateView` (`:568`).
3. `signedOutGateView.onAppear { signedOutGateWasVisible = true }` (`:692-694`) — **unconditional.
   The view does not know why it is on screen**, and it is reused for both the signed-out gate
   and the join-time SIWA sheet.
4. SIWA succeeds → `.onChange(of: auth.signInCompletionCount)` (`:2296`).
5. **`if signedOutGateWasVisible { … return }` (`:2302-2314`) runs FIRST and returns**, before
   the `.join` branch at `:2322` that exists precisely to continue the flow.
6. `onClose` is non-nil in normal use — `PracticeTimerView:1753` passes
   `{ showProfile = false }` — so the branch calls `onClose()` and **dismisses ProfileView
   entirely.**

### Why this is exactly the case the code says must not happen

The `.join` branch carries its own reason, at `:2316-2321`: *authentication used to be the last
step of joining; under B-24 it is the FIRST, and unwinding a joining member would drop them out
of the flow they just authenticated in order to continue.* **That is what happens.** The
protection is present, correct, and unreachable — an earlier branch consumes the event.

**This is structural, not timing.** It does not depend on ordering, latency or membership, and
it reproduces every time an unauthenticated member joins.

### The trap in the obvious fix

Simply reordering the two branches is **not** sufficient. `shouldSuppressSignedInProfileAfterGateSignIn`
(`:495`) is `signedOutGateWasVisible && auth.currentUserID != nil && onClose != nil`, and the
body renders `Color.clear` when it is true (`:503`). Leaving the flag set while continuing into
the join would leave **a blank Profile underneath the membership screen**.

**Smallest coherent fix:** in the `.join` case, clear `signedOutGateWasVisible`, dismiss the
sheet, and present membership selection — i.e. make the purpose, which
`connectedSignInIntent` already records, decide which branch runs. Nothing else changes.

---

## 3. Defect 2 — a truthful refusal outlives the event that makes it false

**Shape confirmed. Cause NOT established.**

### What the code does

`ProfileView.syncDirectoryFromCurrentState` (`:1784`) gates remote work on **identity +
configuration + token** and deliberately **not** on membership or `AppMode` (`:1806-1814`).
**That is correct and is C-70's fix** — it is what makes lapsed-owner maintenance work (M1), and
it must not be narrowed.

The consequence for a *brand-new* identity is that a write is attempted before any membership
exists:

1. `.onChange(of: name)` (`:2411`) and `.onChange(of: locationText)` (`:2431`) schedule a
   650 ms debounced sync. **Both fire on PROGRAMMATIC assignment** — the `name` handler says so
   in its own comment — so ordinary hydration schedules a write.
2. `upsertSelfRow` PATCHes `user_id=eq.<uid>` first. A new identity has **no row**, so zero rows
   match.
3. It falls through to creation. **`account_directory` INSERT is membership-gated; owner UPDATE
   is not.** Pre-membership the INSERT is refused.
4. The refusal classifies as `.refusedByPolicy` (or `.failed`) and renders
   `DirectorySyncFailure.genericMessage` — **the exact string in M5, and TRUE when produced.**
5. Purchase completes; attestation establishes membership. **`onJoinComplete` (`:550`) unwinds
   three booleans and does nothing else** — no directory reconciliation, no re-attempt, no
   message retraction. Verified by reading it.
6. The message persists, now stale, until something unrelated re-triggers a write.

### The cause is genuinely open: TWO candidate refusals, distinguishable on the wire

| Candidate | Mechanism | Wire signature |
|---|---|---|
| **C-a — membership gate** | INSERT gated on `connected_member()`; false until the purchase attests | **403**, SQLSTATE **42501**, RLS violation |
| **C-b — CP-1 band trigger** | `tg_account_directory_requires_band` is BEFORE INSERT and raises when no `account_privacy` row exists | **400**, SQLSTATE **23514** |

**Both produce the identical user-visible message**, because the generic copy deliberately names
no field. **Neither is evidenced**: no request-level response was captured.

**C-b is not idle speculation.** In the fresh-join path the band is held in memory
(`auth.pendingAgeBand`, set at `ProfileView:477`) and only reaches the server later —
`AuthManager.hydrateDirectoryStateFromBackend` establishes it *before* publishing, under an
explicit "CP-3 ORDERING INVARIANT" comment (`AuthManager:664-676`). **ProfileView's 650 ms
debounce is not ordered against that**, so whether the band was live at the refused request is
an open question, not a settled one.

### There are TWO writers, and only one of them owns the message

- `AuthManager.publishLocalProfileSnapshotToDirectoryIfPossible` — background, **logs and shows
  nothing**, by design.
- `ProfileView.syncDirectoryFromCurrentState` — owns `directorySyncMessage`.

**So a successful repair by the background writer cannot clear the foreground's message.** That
asymmetry is worth stating on its own: it means the message can outlive the failure even after
the row exists.

### Recovery is incidental, and "reopening Profile" is not established as the trigger

At least two independent paths could have created the row at M7, and **nothing distinguishes
them**:

- **R1 — ProfileView remount.** `directorySyncMessage` and `directorySyncLatch` are both
  `@State`, so remounting resets the message to nil and clears the skip token; `load()` then
  assigns `name`/`locationText`, which schedules a fresh sync that now succeeds.
- **R2 — AuthManager re-hydration.** For a no-row account, `hydrateDirectoryStateFromBackend`
  returns early **without setting `lastHydratedDirectoryUserID`** (`:662-684`), so a later
  hydration re-enters the full path — band check, then publish — and succeeds once membership is
  live. This fires on session refresh and foreground, **not only on reopening Profile.**

Codex's caution is correct and is now specific: R1 and R2 are both live, and M7 does not
separate them.

### What this is probably not — HYPOTHESES, held as hypotheses

**Revised 21 September 2026. An earlier revision stated the first two categorically. Both are
withdrawn as verdicts and retained as reasoning**, because neither has a control.

- **Handle removal is not an obvious cause, and that is an argument rather than a measurement.**
  The removed generation never created a directory row — it required one to already exist — and
  `upsertSelfRow` no longer carries `account_id` at all, so it is hard to see how it reaches an
  INSERT refusal. **No control has been run**, so this is not cleared. §5.3 names the control
  that would settle it.
- **C-70 is not an obvious cause, on the same footing.** Its ungated owner PATCH is what makes M1
  pass. That it must stay is a design commitment; that it is not implicated here is reasoning,
  not evidence.
- **Gating the writer on membership would re-break M1.** This one is not a hypothesis: it is
  what M1 measured.

---

## 4. Proposed fix scope — smallest coherent, and explicitly NOT approved

**Two bounded client changes. No SQL, no migration, no policy, no server change.**

### F1 — the join continuation (Defect 1)

In `ProfileView`'s `signInCompletionCount` handler, let the recorded **purpose** decide. When
`connectedSignInIntent == .join`: clear `signedOutGateWasVisible`, dismiss the sheet, present
membership selection. Otherwise the existing gate behaviour is untouched.

**One file, one handler.** No new state: `connectedSignInIntent` already exists and already
means this.

### F2 — post-join reconciliation (Defect 2) — **SUPERSEDED, SEE §10**

**WITHDRAWN 21 September 2026. Its premise was false.** It read: *"`onJoinComplete` … give it
one more job: invalidate the sync latch and schedule a directory sync, so the write … is
attempted again once it does."*

**`onJoinComplete` does not mean membership was established.** Codex read
`MembershipSelectionView.purchaseSelectedProduct` (`:331-352`) and `restorePurchases`
(`:379-403`): on the `.verified` branch `onJoinComplete()` runs **after `attestIfNeeded`
regardless of what attestation returned** — `pending`, `conflict`, `terminalRefusal`,
`claimRefused`, `appleUnavailable`, `serverError`, `transport` and `nil` all reach it. Verified
here against the same source. **"Once it does" was wrong**, and a reconciliation keyed on that
callback would have written into a refusal for every one of those outcomes.

**Replaced by §10, which is keyed on the attestation OUTCOME rather than on the callback.**

**Deliberately NOT proposed, and each for a stated reason:**

| Rejected | Why |
|---|---|
| Gate the writer on membership | Re-breaks C-70 / M1 |
| Clear the message on `onJoinComplete` | Hides a refusal that may still be real. **The write must decide the message** |
| A delay before the first write | A blind delay; races the same problem more slowly |
| Retry loop / backoff | Unbounded work on a path that already has a natural re-trigger |
| Suppress the message pre-membership | Would have hidden a TRUE failure, and would make a genuinely broken join silent |

**F2 preserves real-error reporting exactly:** if the INSERT is still refused after the
purchase, the member is told again, truthfully. The identity, generation and screen-freshness
guards are untouched — the reconciliation goes through the same `syncDirectoryFromCurrentState`
and therefore through the same gates.

**F1 stands alone and is worth landing on its own merits** even if F2 is deferred: it is
confirmed, structural, and independent of the unresolved cause.

---

## 5. Establishing the cause deterministically — proposed, not run

**The cheapest decisive evidence is the HTTP response of the refused create.** C-a and C-b
differ as 403/42501 versus 400/23514, so **one captured response settles it.**

1. **Temporary instrumentation**, in this project's established pattern (`ActivationTrace`,
   `JWSFreshnessProbe`, `C42StorefrontProbe`): one `os.Logger` line with `privacy: .public` on
   the directory-write failure path, carrying status and SQLSTATE and no personal data. **With a
   standing removal condition: delete it the moment the cause is scored, and verify the removal
   as a pure deletion.** Needs a device run, which is Samuel's to authorise.

2. **Local-stack reproduction, no device**, which is the deterministic one: drive the real
   sequence against the byte-identical local stack with (i) no `account_privacy` row and
   membership live, and (ii) a band present and membership absent. Each should produce its own
   distinct refusal, which both confirms the two signatures and shows which the client renders.

3. **A handle-removal control**, to settle §3's reasoning rather than assert it: run the same
   fresh-join reproduction against the pre-removal bytes. Identical behaviour would retire the
   question.

**Until one of these runs, the cause stays a hypothesis and must not be recorded otherwise.**

---

## 6. Proposed tests — **SUPERSEDED BY §10.3**, retained as the first draft

**Codex's objection is accepted: structural substring presence plus standalone refusal
classification does not prove reconciliation BEHAVIOUR.** §10.3 replaces this.


| # | Test | Why it is not ceremony |
|---|---|---|
| T1 | A `.join` sign-in completion presents membership selection and does **not** call `onClose` | Fails against current code; this IS Defect 1 |
| T2 | A `.join` completion leaves `signedOutGateWasVisible` false, so the suppression view cannot blank Profile | Pins the trap in §2 that a naive reorder walks into |
| T3 | A gate sign-in (`.returning`, and the genuine signed-out gate) still unwinds exactly as today | Proves F1 narrowed nothing |
| T4 | Join completion schedules a directory reconciliation | Fails against current code; this IS Defect 2's gap |
| T5 | A refused create still renders the generic message **after** F2 | Proves F2 did not swallow a real refusal |
| T6 | The reconciliation passes through the identity and freshness guards | Proves F2 opened no unguarded write path |
| T7 | Transport: PATCH-zero-rows → create refused **403/42501** → `.refusedByPolicy` → generic copy | Pins C-a's signature |
| T8 | Transport: PATCH-zero-rows → create refused **400/23514** → generic copy | Pins C-b's signature, and that the two are told apart at the transport layer even though the copy is shared |

T7 and T8 are worth writing **whatever the cause turns out to be**: they make the two refusals
distinguishable in the suite, which is the thing that was missing when the device produced one
of them.

---

## 7. Status

- **Defect 1: cause confirmed by control flow.** Fix scope F1 proposed.
- **Defect 2: shape confirmed, cause OPEN.** Two candidates, neither evidenced; fix scope F2
  proposed and is **independent of which one it is**, because both are refusals that want the
  same reconciliation.
- **Recovery mechanism: OPEN.** R1 and R2 both live; M7 does not separate them.
- **Nothing implemented. Awaiting Codex's scope review, then Samuel.**

---

## 8. BOUNDED SCOPE FOR CODEX APPROVAL — nothing implemented

**Client-only. Two files. No SQL, no migration, no policy, no server change, no device action,
no commit, no push.** The accepted handle-removal unit is preserved byte-for-byte; its 18
source and 8 test hashes are re-verified before and after.

### 8.1 Source — 1 file

| File | Change |
|---|---|
| `MOTIVO/ProfileView.swift` | **(a)** In `.onChange(of: auth.signInCompletionCount)`, let `connectedSignInIntent` decide: for `.join`, clear `signedOutGateWasVisible`, dismiss the sheet and present membership selection; every other case keeps today's behaviour exactly. **(b)** In `onJoinComplete`, after unwinding the three booleans, invalidate the directory-sync latch and schedule a sync. |

**`connectedSignInIntent` is a complete discriminator, verified rather than assumed:**
`signedOutGateView` has exactly ONE render site (`:569`), the sheet has exactly THREE openers
(`:465`, `:546`, `:1297`), and **all three set the intent before opening it.**

**Clearing `signedOutGateWasVisible` in the `.join` branch is load-bearing, not tidying.**
`shouldSuppressSignedInProfileAfterGateSignIn` (`:495`) renders `Color.clear` while that flag is
set and `onClose` is non-nil — and **both** presentations pass a non-nil `onClose`
(`PracticeTimerView:1753`, `MOTIVOApp:249`). Reordering the branches without clearing it would
leave a blank Profile behind the membership screen.

**No new state, no new type, no new file.**

### 8.2 Tests — 1 new file

| File | Contents |
|---|---|
| `MOTIVOTests/FreshJoinContinuationTests.swift` | T1–T4 and T6 from §6 as structural assertions over `ProfileView.swift`, in the established `C70…` style; plus T7/T8 as behavioural transport tests **added to the existing `C70DirectoryWriteTransportTests`**, because that suite already drives `upsertSelfRow` through a stubbed transport and therefore exercises real payload construction |

**T5 is folded into T7/T8** rather than written separately: "F2 did not swallow a real refusal"
is the same assertion as "a refused create still renders the generic message".

**Structural tests read source text and prove WIRING, not rendering.** No test in this target
renders a view, and none will claim to.

### 8.3 Explicitly out of scope

Gating the writer on membership (re-breaks C-70/M1); clearing the message without a write
deciding it; any delay, retry loop or backoff; suppressing the message pre-membership; any
change to `AuthManager`'s background publish or to its CP-3 band ordering; any age, sharing,
recorder or feed work; any server or schema change; resolving §3's open cause — **F1 and F2 are
both correct regardless of which refusal occurred**, and §5 remains the way to settle it.

### 8.4 Validation

1. Targeted suites **by actual XCTest class name**, never by filename — the failure mode from
   the previous unit.
2. One final full `MOTIVOTests` run plus Debug and Release builds against the finished bytes.
3. Test accounting reported as new / converted / retired / unchanged, never as a raw total.
4. Warning delta by attribution against the existing logs.
5. **Positive controls with artifacts retained this time** — each control run `tee`d to a log
   file, so the evidence does not depend on a transcript (§9).
6. Handle-removal hashes re-verified unchanged at the end.
7. **No device QA.** Samuel performs it when Codex and I say the reviewed build is ready.

---

## 9. Artifact retention — corrected for this unit

**Xcode pruned its test bundle directory to two during the last unit**, which cost the targeted
run's bundle and all five control bundles, leaving transcripts where artifacts should have been.

**Both surviving bundles are now copied out of `DerivedData`**, and the copy was verified
readable rather than assumed:

```
/private/tmp/claude-501/-Users-samueldixon-Documents-Xcode-projects-MOTIVO-B-MOTIVO/c657c407-b562-4523-b151-9170cc9ae8a2/scratchpad/evidence/bundles/Test-MOTIVO-2026.09.20_23-19-42-+0100.xcresult   (127M)
   -> re-read after copying: Passed, 1006 total, 1000 passed, 0 failed, 6 skipped
/private/tmp/claude-501/-Users-samueldixon-Documents-Xcode-projects-MOTIVO-B-MOTIVO/c657c407-b562-4523-b151-9170cc9ae8a2/scratchpad/evidence/bundles/Test-MOTIVO-2026.09.20_23-19-00-+0100.xcresult
```

**For this unit every test and control run will be `tee`d to a log at the time**, and the final
bundle copied out immediately, so nothing again rests on a transcript.

---

# 10. BOUNDED SCOPE revision 2 — **NOT APPROVED. SUPERSEDED BY §11.**

**Codex rejected this on 21 September 2026 for a gap it does not cover: SUCCESS BEFORE
FAILURE.** Keying on `lastOutcome` means that if the establishing attestation lands while
no failure is yet outstanding, the observer correctly declines to write — and when the
already-dispatched write's refusal arrives moments later there is **no further outcome
change to retrigger anything**, so the stale message persists. That is the observed
symptom, and revision 2 misses it.

**Two further faults, both accepted:** diagnostic equality on `lastOutcome` COLLAPSES two
genuinely distinct completions, and `attestation.reset()` fires only when `currentUserID`
becomes nil (`MOTIVOApp:422-441`), so a current-owner re-read does **not** prove that a
completion belongs to the session that is now on screen.

**Retained as history. §11 is the live scope.**

## 10.0 (revision 2 text follows)

**Supersedes §4's F2, §6 and §8's arithmetic.** F1 is unchanged and Codex approved it in
principle. **Client-only, THREE files, no SQL, no migration, no policy, no server change, no
device action, no commit, no push, no temporary device logging.**

## 10.1 What F2 becomes — keyed on the OUTCOME, not on the callback

**The callback is the wrong signal; the attestation outcome is the right one**, and it is
already `@Published` (`MembershipAttestationCoordinator.lastOutcome`, `:66`) with exactly one
reader today (`MembershipSelectionView:347`).

ProfileView observes that outcome and reconciles **only** when all three hold:

1. the new outcome **establishes membership** — `.established` or `.alreadyEstablished`, and no
   other case;
2. a **directory failure is currently outstanding** on this screen;
3. identity and configuration permit remote maintenance — the existing
   `ProfileMaintenancePolicy` condition, unchanged.

Then, and only then: invalidate the sync latch and schedule one sync.

**This drops the `onJoinComplete` edit entirely.** The `.verified` path sets `lastOutcome`
*before* calling `onJoinComplete`, so the observer already covers purchase, restore, and every
later attestation — **one mechanism instead of two, and no captured closure at all.**

### What it GUARANTEES, stated exactly

| | |
|---|---|
| **G1** | If a directory write was refused while membership was absent, and membership later becomes established **while Profile is mounted**, **exactly one** further write is attempted |
| **G2** | If that write succeeds, the message clears — through the existing `.applied` branch, not by a separate clear |
| **G3** | If it is still refused, the member is told again, **truthfully**. Nothing is swallowed |
| **G4** | With **no** outstanding failure, **no write is made** — so `.alreadyEstablished` on every foreground costs nothing. This is condition 2's whole job |
| **G5** | For every outcome that does **not** establish membership, **nothing fires**: no useless write, and the existing truthful message stands |

### What it does NOT guarantee — named, not implied

- **It does not guarantee a row exists after joining.** With attestation `pending`, membership is
  not established and nothing fires; the row is created later by a subsequent attestation (G1,
  if still mounted) or by `AuthManager`'s re-hydration publish (R2).
- **It does not fire when Profile is not mounted.** R2 remains the path there, and R2 has no UI.
  **That asymmetry is unchanged by this scope and is not being fixed here.**
- **It does not resolve §3's open cause.** F1 and F2 are both correct whichever refusal occurred.

### No blind delay anywhere

The trigger is a state change published by the coordinator. There is no timer, no retry loop,
no backoff, no polling. The only delay is the existing 650 ms debounce that every profile edit
already uses.

## 10.2 Identity and generation across the async boundary

**Codex's hazard — a fresh token submitted inside a stale callback treating identity B as the
recipient of A's purchase — is largely designed out by keying on the outcome rather than on a
captured closure.** There is no closure to go stale. What remains is shown from existing code
rather than newly built:

| Guarantee | Where it already lives |
|---|---|
| A stale `.established` cannot survive an identity teardown | `attestation.reset()` nils `lastOutcome` (`MOTIVOApp:440`), deliberately not gated on `isConnected` |
| The owner is re-read at write time, not captured earlier | `syncDirectoryFromCurrentState` reads `auth.backendUserID` (`:1829`) after its gate |
| The request is bound to that owner and epoch | `DirectoryWriteCoordinator.binding(owner:capturedGeneration:)` |
| A write for a replaced identity is refused | `.supersededIdentity`, and `mayApplyEffects` withholds every local effect |

**One narrowly bounded addition, because the above is not quite complete:** the observation
captures `auth.backendUserID` at the instant it fires and the reconciliation is abandoned if it
no longer matches when the sync runs. **This adds no new authority** — it is the same owner
comparison the writer already makes, moved one step earlier so a spurious write is never
submitted rather than being submitted and then discarded.

## 10.3 Tests — behavioural through production sequencing

**Codex's objection is accepted:** source-substring presence plus standalone refusal
classification does not prove reconciliation behaviour.

**The decision moves OUT of the view as a pure value type**, following this codebase's own
precedent — `ProfileMaintenancePolicy` and `ProfileMaintenanceGate` (`ProfileView.swift:182`,
`:229`) and `ConnectedSetupDecision` (`DirectoryWriteCallerPolicy.swift:78`). That makes the
decision itself exhaustively testable without rendering anything, and leaves only the wiring to
be pinned structurally.

| # | Test | Kind | Why it is not ceremony |
|---|---|---|---|
| **T1** | `.join` completion presents membership selection and does **not** call `onClose` | structural | Fails against current code — this IS Defect 1 |
| **T2** | `.join` completion leaves `signedOutGateWasVisible` false | structural | Pins the blank-Profile trap a naive reorder walks into |
| **T3** | `.returning` and genuine gate sign-in unwind exactly as today | structural | Proves F1 narrowed nothing |
| **T4** | **Refused-before-join, then evidenced-success-after-join, through `upsertSelfRow` against the stub**: PATCH 0 rows → create refused → message; then PATCH 0 rows → create 201 → `.applied` with an evidenced receipt and no message | **behavioural, production sequencing** | This is the actual claim. Drives the real writer twice, in order |
| **T5** | **Still-refused after join**: second attempt also refused → generic message present again | **behavioural** | Proves G3 — nothing swallowed |
| **T6** | **Delayed attestation**: `pending` then later `.established` → reconciliation fires **only** on the second | value | Proves G5 and the delayed case with no timer |
| **T7** | Every non-establishing outcome — `pending`, `conflict`, `terminalRefusal`, `claimRefused`, `appleUnavailable`, `ineligible`, `serverError`, `transport`, `nil` — yields **no** reconciliation | value, exhaustive | Codex's central objection to the withdrawn F2 |
| **T8** | No outstanding failure → **no** reconciliation even on `.established` | value | Proves G4 — no repeated unrelated writes |
| **T9** | **Identity change**: reconciliation abandoned when the owner no longer matches; and a dispatched write for a replaced identity is `.supersededIdentity` with effects withheld | **behavioural** | Codex's stale-recipient hazard |
| **T10** | Transport: create refused **403/42501** → `.refusedByPolicy`; create refused **400/23514** → generic copy | behavioural | Makes §3's two candidates distinguishable IN THE SUITE, which is what was missing on device |
| **T11** | The view's observer calls exactly the pure policy, with no second decision inline | structural | Stops the decision drifting back into the view where it cannot be tested |

**T4, T5, T9 and T10 go into the existing `C70DirectoryWriteTransportTests`**, because that
suite already drives `upsertSelfRow` through a stubbed transport and therefore exercises real
payload construction and real sequencing. T1–T3, T6–T8 and T11 go in the new file.

## 10.4 File boundary — corrected arithmetic

**THREE files.** The earlier count of "one source file, one new test file" omitted the existing
transport suite, which T4/T5/T9/T10 necessarily touch.

| # | File | Status |
|---|---|---|
| 1 | `MOTIVO/ProfileView.swift` | modified — F1, F2's observer, and the new pure policy hosted beside the two existing profile policies |
| 2 | `MOTIVOTests/C70DirectoryWriteTransportTests.swift` | modified — T4, T5, T9, T10 |
| 3 | `MOTIVOTests/FreshJoinContinuationTests.swift` | **new** — T1–T3, T6–T8, T11 |

**Two of the accepted handle-removal hashes therefore change, necessarily and by design:**
`ProfileView.swift` and `C70DirectoryWriteTransportTests.swift`. **The other 16 source files and
7 test files must remain byte-identical**, and that will be verified against the accepted
manifest at the end rather than asserted. Review is on the **incremental diff** from the
accepted bytes, not on the combined change.

**The new policy could equally live in `DirectoryWriteCallerPolicy.swift` beside
`ConnectedSetupDecision`.** That would make it four files. Hosting it in `ProfileView.swift`
follows the precedent of the two profile policies already there; say if you prefer the
separation.

## 10.5 Out of scope, restated

Gating the writer on membership; clearing the message without a write deciding it; any delay,
retry loop or backoff; suppressing the message pre-membership; changing `AuthManager`'s
background publish or its CP-3 band ordering; fixing the background-writer/foreground-message
asymmetry; any age, sharing, recorder or feed work; any server or schema change; **recovering
the uncaptured historical response**; **temporary device logging** — neither is needed for
approval or for this fix, and §5 stays available if the cause is ever pursued on its own merits.

**This is a bounded fix, not a redesign.**

## 10.6 Validation

Targeted suites **by actual XCTest class name**; one final full `MOTIVOTests` run plus Debug and
Release builds against the finished bytes; accounting as new/converted/retired/unchanged, never
a raw total; warning delta by attribution; **every test and control run `tee`d to a log at the
time and the final bundle copied out of `DerivedData` immediately** (§9); the 16 + 7 untouched
handle-removal hashes re-verified; **no device QA** — Samuel runs it when we both say the
reviewed build is ready.

---

# 11. BOUNDED SCOPE revision 3 — **APPROVED AND IMPLEMENTED**

**Approved by Codex 21 September 2026; implemented the same day. Codex granted LOCAL CODE AND
VALIDATION ACCEPTANCE, pending Samuel's device QA.** Uncommitted and unpushed.
Evidence: `docs/fresh-join-fix-evidence-2026-09-21.md`.

**The historical failed request's cause remains UNKNOWN.** §3's timing account is a hypothesis
and no request-level trace was ever captured; the fix is correct whichever refusal occurred.


**F1 is agreed and unchanged.** This revises F2 only.

## 11.1 The gap revision 2 missed, and the rule that closes it

**The reconciliation decision must be evaluated at BOTH events, because either can arrive
first:**

| Order | What happens | Revision 2 | Revision 3 |
|---|---|---|---|
| **Failure → success** | write refused, message set; attestation then establishes | reconciles | reconciles |
| **Success → failure** | attestation establishes while nothing is outstanding; the already-dispatched write's refusal lands after | **MISSES IT** — no further outcome change | reconciles |

So the trigger is not "an establishing outcome arrives". It is: **an unconsumed establishing
completion exists for this owner and this directory generation, AND a directory failure is
outstanding** — tested whenever either side changes.

## 11.2 The scoped completion — replacing `lastOutcome` equality

`lastOutcome` is a **diagnostic value**, so two genuinely distinct completions with the same
value are indistinguishable and `onChange` collapses them. Replaced by a token that is unique
per completion and carries its own ownership:

```
struct AttestationCompletion: Equatable {
    let sequence: Int              // the coordinator's own per-run generation: unique per completion
    let owner: String              // backendUserID, captured BEFORE the attestation await
    let directoryGeneration: Int   // DirectoryWriteCoordinator.identityGeneration, captured BEFORE
    let establishesMembership: Bool
}
```

**Captured before the await, not read after it.** `coordinate()` already increments its own
`generation` per run and publishes from inside the run's task
(`MembershipAttestationCoordinator:129-149`), so `sequence` is available exactly where the
completion is published. **This is the same reasoning as U5f's attestation epoch and C-70's
write epoch**: a value read after a suspension can look current while resting on a session that
has since been torn down and rebuilt.

**`directoryGeneration` is what proves event ownership**, and it is why a current-owner re-read
is not enough: an A→B→A cycle leaves the owner equal to A again, and only the generation shows
that the completion belongs to the previous A.

## 11.3 The decision — one pure policy, consulted from both events

```
DirectoryReconciliationPolicy.shouldReconcile(
    completion:                  AttestationCompletion?,
    hasOutstandingFailure:       Bool,
    currentOwner:                String?,
    currentDirectoryGeneration:  Int,
    lastConsumedSequence:        Int?
) -> Bool
```

True only when **all six** hold: a completion exists; it establishes membership; a directory
failure is outstanding; its `owner` matches the current owner; its `directoryGeneration` matches
the current one; and its `sequence` has not already been consumed.

**Consumption is the boundedness rule: at most ONE reconciliation per completion.** On a true
result the sequence is recorded as consumed before the write is scheduled.

### What that yields

| Property | Why it holds |
|---|---|
| Both event orders covered | The policy is consulted on completion change **and** when a directory failure is recorded |
| Persistent refusal is bounded | The completion is consumed on the first reconciliation; a still-refused write cannot re-trigger itself. A **new** attestation completion may drive one more, which is new information, not a loop |
| Repeated equal completions are not collapsed | `sequence` differs even when the outcome value is identical |
| Same-owner reset is handled | `reset()` nils the completion; and an A→B→A cycle fails the `directoryGeneration` test even though the owner matches |
| No failure → no write | The outstanding-failure condition, evaluated at both events |
| No blind delay | Both triggers are state changes. No timer, no polling, no backoff. The only delay is the existing 650 ms debounce |
| Truthful errors preserved | The message is set and cleared by the WRITE, never by the policy. A still-refused reconciliation says so again |

## 11.4 Files — four touched, and the untouched accounting Codex corrected

| # | File | Status |
|---|---|---|
| 1 | `MOTIVO/ProfileView.swift` | modified — F1; the two policy call sites; `DirectoryReconciliationPolicy` hosted beside the two existing profile policies; one `lastConsumedSequence` state |
| 2 | `MOTIVO/MembershipAttestationCoordinator.swift` | modified — publish `lastCompletion`; capture owner + directory generation **before** the await; clear it in `reset()`. **Narrow expansion only: no gate change, no trigger change, no change to `attestIfNeeded`'s invariant.** The scope is passed in as a defaulted parameter so existing `coordinate` callers are unaffected |
| 3 | `MOTIVOTests/C70DirectoryWriteTransportTests.swift` | modified — the writer-driven tests |
| 4 | `MOTIVOTests/FreshJoinContinuationTests.swift` | **new** |

**Untouched from the accepted handle-removal manifest: 17 source files and 7 test files** —
Codex's arithmetic, and mine was wrong. `MembershipAttestationCoordinator.swift` is **not** in
that manifest, so touching it does not reduce the untouched count; only `ProfileView.swift` and
`C70DirectoryWriteTransportTests.swift` do. Both untouched sets are verified byte-identical
against the manifest at the end, and review is on the **incremental diff**.

## 11.5 Tests — production trigger policy plus the real writer

| # | Test | Kind |
|---|---|---|
| T1–T3 | F1: `.join` continues and clears the gate flag; `.returning` and the genuine gate unwind unchanged | structural |
| **T4** | **Failure → success**, driving `upsertSelfRow` against the stub: refused create → failure recorded → completion arrives → policy true → **second real write** returns 201 → `.applied`, evidenced, message cleared | **policy + real writer** |
| **T5** | **Success → failure**, the order revision 2 missed: completion arrives first with nothing outstanding → policy false, **not consumed** → refusal lands → policy true → second real write succeeds | **policy + real writer** |
| **T6** | **Persistent refusal is bounded**: both creates refused → exactly **two** writes total, message present and truthful; no third | **policy + real writer** |
| **T7** | **Repeated equal completions**: two `.established` completions with equal outcome but different `sequence` are each eligible once; three are not driven by one | value |
| **T8** | **Same-owner reset**: `reset()` clears the completion; and an A→B→A cycle with the owner equal again but a changed `directoryGeneration` yields false | value |
| **T9** | **No outstanding failure → no write**, including on `.established` | value + writer (asserts **zero** requests) |
| **T10** | Every non-establishing outcome yields no reconciliation | value, exhaustive |
| **T11** | An identity change between scheduling and dispatch yields `.supersededIdentity` with effects withheld | writer |
| **T12** | Transport: create refused **403/42501** and **400/23514** both classify and both render the generic copy | writer |
| **T13** | The view consults exactly the policy at both sites, with no second decision inline | structural |

T4, T5, T6, T9, T11, T12 go in the existing transport suite; the rest in the new file.

## 11.6 Unchanged from revision 2

Out of scope (§10.5) stands, with one addition: **no gate changes** — `attestIfNeeded`'s
invariant, the CP-1 band ordering, `AuthManager`'s background publish and every RLS/enforcement
surface are untouched. Validation (§10.6) stands, including `tee`ing every run and copying the
final bundle out of `DerivedData` immediately.

---

# 12. F2 FAILED ON DEVICE — trace and bounded incremental scope (F3)

**21 September 2026. Read-only. Nothing implemented. F1 PASSED on device.**

## 12.1 What the device showed, and why F2 could not fire

**Measured (Daniel Brown, `ee32dfe0…`, created 10:46:17):** SIWA led straight to the
subscription choices — F1's fix working — monthly purchased, back to Profile **with no
warning**; `connected_member = true` and **no directory row** at 10:49:39 with Profile still
open and untouched; closed to timer, reopened Profile, nothing else tapped; at 10:53:17 the row
**Daniel Brown / Manchester / [Guitar]** existed.

**The absence of a warning is the finding, not a detail.** F2 requires
`hasOutstandingFailure`, and there was no failure because **ProfileView never attempted a write
at all**:

1. `AuthManager`'s hydration ran at sign-in, found no row, set `backendBootstrapState =
   .newAccount`, established the band and called
   `publishLocalProfileSnapshotToDirectoryIfPossible`. Pre-purchase the INSERT is
   membership-gated, so it was refused — and that path **logs only, with no UI**
   (`AuthManager:678`). No message, by design.
2. ProfileView's only sync triggers are `.onChange(of: name)` and `.onChange(of: locationText)`.
   With F1 fixed, **Profile stays mounted through the whole join**, so `load()` had already
   assigned both before the identity arrived. **Nothing changed afterwards, so nothing was
   scheduled.**
3. Membership became established at the purchase. Nothing re-publishes on that event.
4. Closing to the timer and reopening **remounted** ProfileView: `@State` name/location start
   empty, `load()` assigns them, `onChange` fires, the debounced sync runs — and now succeeds.

**So the gap is an INITIAL PUBLICATION with no foreground error, and F2's failure-outstanding
condition cannot reach it.** Codex named this exactly.

**Not established:** which request created the row at 10:53:17. The remount-driven sync is the
strongest candidate; a re-hydration publish is not excluded. **This remains a hypothesis.**

## 12.2 The signal that distinguishes a fresh join from a routine foreground

`backendBootstrapState` is `@Published` and already says what is needed: **`.newAccount` means
hydration found no directory row**, `.existingAccount` means it found one (`AuthManager:664`,
`:713`).

**It is never flipped after a successful publish** — the no-row branch sets it and returns — so
it alone would authorise a write on every later establishing completion. That is what the
second input below bounds.

## 12.3 F3 — the bounded incremental change

**One condition widens, in the SAME policy, at the SAME two call sites.** No new trigger, no new
observer, no timer.

```
publishAfterEstablishment  =  hasOutstandingFailure
                           || (bootstrapSaysNoRow && !thisScreenHasEvidencedAWrite)
```

- **`bootstrapSaysNoRow`** — `auth.backendBootstrapState == .newAccount`.
- **`thisScreenHasEvidencedAWrite`** — a new `@State` holding the OWNER for which this screen
  last saw `.applied`. Comparing it to the current owner makes it **self-clearing on identity
  change**, so no new identity handler is needed.

Everything else in the approved policy is unchanged: establishing outcomes only, owner match,
directory-generation match, and **consumption of at most one reconciliation per completion**.

### What each case does

| Case | Behaviour |
|---|---|
| **Fresh join, no error** — the failing case | `.newAccount`, nothing evidenced → publishes on the establishing completion. **This is the fix** |
| **Attestation `pending` first** | No establishing completion, so nothing fires. A later `.established` **or `.alreadyEstablished`** still publishes, because the row is still unevidenced — which is why both outcomes stay eligible |
| **Returning member, row exists** | `.existingAccount` → **no write on any foreground**, however many completions arrive |
| **After a successful publish** | Evidenced → no further writes, even though `backendBootstrapState` remains `.newAccount` |
| **Failure outstanding** | Unchanged repair path |
| **Identity change** | The evidenced owner no longer matches, and the completion's generation no longer matches |

### Preserved, and asserted rather than assumed

Membership and privacy gates are untouched — the publish is an ordinary directory write the
server judges as it judges every other; the CP-1 band ordering is untouched; C-70's lapsed-owner
PATCH is untouched; the completion remains **a hint, never membership authority**; the message
is still set and cleared by the WRITE, so a refused publish still tells the member truthfully.

## 12.4 Files — two, plus one new test class

| # | File | Change |
|---|---|---|
| 1 | `MOTIVO/ProfileView.swift` | Two inputs added to the policy call; one `@State` evidenced-owner; set it in the existing `.applied` branch |
| 2 | `MOTIVOTests/FreshJoinContinuationTests.swift` | Policy cases for the new condition |
| 3 | `MOTIVOTests/C70DirectoryWriteTransportTests.swift` | The production-sequencing tests below |

`MembershipAttestationCoordinator.swift` is **not** touched again. Untouched from the
handle-removal manifest stays **17 source / 7 test**.

## 12.5 Tests — the orchestration, including the no-error fresh join

| # | Test | Kind |
|---|---|---|
| **F3-1** | **No-error fresh join**: no failure ever recorded, `.newAccount`, nothing evidenced → the establishing completion drives **one real write** that creates the row | policy + real writer |
| **F3-2** | The same run does **not** write a second time once evidenced | policy + real writer |
| **F3-3** | **Returning member**: `.existingAccount` with no failure → **zero requests** across several completions | policy + real writer |
| **F3-4** | **Pending then established**: a `pending` completion writes nothing; the following `.established` publishes | value |
| **F3-5** | **Pending then alreadyEstablished** publishes too — the row is still unevidenced | value |
| **F3-6** | Evidenced under owner A does not suppress a publish for owner B | value |
| **F3-7** | The repair path (failure outstanding) is unchanged under `.existingAccount` | value |
| **F3-8** | Boundedness is unchanged: one reconciliation per completion | value |

Plus a positive control: revert the widened condition and watch **F3-1** fail.

## 12.6 Out of scope

Any new trigger or observer; any timer, delay or retry loop; any change to `AuthManager`'s
background publish, its CP-3 band ordering, or the coordinator; any gate, server or schema
change; fixing the background-writer/foreground-message asymmetry; identifying which request
created the row at 10:53:17.

**Scoped to Codex before implementation. Nothing implemented; no commit, push, server or device
mutation.**

---

# 13. F3 revision 2 — **APPROVED, IMPLEMENTED, LOCALLY ACCEPTED**

**Approved by Codex 21 September 2026, implemented the same day, granted LOCAL CODE AND
VALIDATION ACCEPTANCE, and DEVICE-RUN the same day. COMMITTED on Samuel's explicit
authorisation; NOT PUSHED.**

**The device run is not a clean first-attempt join** — the first purchase attempt failed for an
unexplained reason the console cannot settle, and the row was verified after a retry. See
`docs/fresh-join-f3-evidence-2026-09-21.md` §STATUS.
Evidence: `docs/fresh-join-f3-evidence-2026-09-21.md`.

**The historical failed request's cause remains UNKNOWN**, and §12.1's source account is
supported rather than captured — a silent screen is also consistent with a superseded or
not-permitted path.


**Supersedes §12.3–12.6.** All three gaps accepted; one claim in §12.1 corrected.

## 13.0 Correction to §12.1

**"No warning" does NOT prove no foreground request was made.** `.superseded` and
`.supersededIdentity` break without a message, and the remote gate returns before any request.
So a silent screen is consistent with several paths, not only with "nothing was attempted".
**The source account in §12.1 is plausible and uncaptured; no request-level history exists for
that device run.** The rest of §12.1 stands as measured.

## 13.1 Gap 1 — bootstrap is a THIRD asynchronous input

Completion and failure are not the only events. The row-absence signal arrives on its own
schedule, so a completion landing while it is still unknown is missed by both existing triggers.

**Three evaluation points, all calling the one policy:**

| # | Trigger | Covers |
|---|---|---|
| 1 | completion change | absence known first |
| 2 | a directory failure is recorded | the repair path (unchanged) |
| 3 | **row-absence evidence change** | **completion first, absence after** |
| 4 | **Profile appearance** | a remount, where `@State` consumption and evidence start empty and the events have already passed |

**4 is bounded by user action**, not by a timer: at most one publish per manual Profile open, and
none once evidenced. It is the mechanism Samuel performed by hand at 10:53:17, made deliberate.

## 13.2 Gap 2 — evidence must carry owner AND generation

An owner alone is not self-clearing: an A→B→A cycle, or a same-owner reset, leaves the owner
equal again while the evidence belongs to a previous session.

**Evidence becomes `(owner, directoryGeneration)`, and the generation is taken from the ACCEPTED
WRITE RESULT** — `DirectoryWriteResult.generation`, the epoch the writer actually bound — never
re-read afterwards. It matches only when both still hold. Existing freshness guards are
untouched; this is a second use of the same epoch, not a new authority.

## 13.3 Gap 3 — `backendBootstrapState` is UNSCOPED and must not be promoted

**Measured:** `hydrateDirectoryStateFromBackend` guards `self.backendUserID == userID` at
`:650`, **before** `await fetchSelfRow` at `:655`, and sets `.newAccount` at `:664` **with no
fresh guard**. Its value can therefore describe a fetch whose identity has since been replaced.
**It is not proof about the current identity and this scope will not treat it as such.**

**`backendBootstrapState` is NOT changed** — other consumers depend on it
(`PracticeTimerView:1057`, `:1068`, `:1087`; `ContentView:702`), and hydration is not rewritten.

**One narrowly scoped addition to `AuthManager`, enumerated:**

```
struct DirectoryRowAbsence: Equatable { let owner: String; let directoryGeneration: Int }
@Published private(set) var directoryRowAbsence: DirectoryRowAbsence?
```

- Owner and `DirectoryWriteCoordinator.identityGeneration` are captured **before**
  `fetchSelfRow`; after it, both are re-checked and the value is published **only if they still
  match**. A stale fetch publishes nothing.
- No row → set it. Row found → clear it, under the same fresh guard.
- Cleared wherever `backendBootstrapState` already resets to `.unknown` (`:1293`, `:1354`).

**The policy consumes this, never `backendBootstrapState`.** A returning member has no absence
evidence, so the no-failure path cannot fire for them — the zero-write-per-foreground property
comes from scoped evidence rather than from an unscoped enum.

## 13.4 The condition

```
publish = hasOutstandingFailure
       || (absenceEvidenceMatchesCurrentOwnerAndGeneration
           && !appliedEvidenceMatchesCurrentOwnerAndGeneration)
```

Unchanged from the approved policy: establishing outcomes only, owner match, generation match,
**at most one reconciliation per completion**. Preserved: no repeat after an evidenced success;
`pending` then later confirmation by either establishing outcome; the existing repair path; and
every server gate — the publish is an ordinary write the server judges as it judges any other.
**No guard is relaxed globally.**

## 13.5 Files — FOUR

| # | File | Change |
|---|---|---|
| 1 | `MOTIVO/AuthManager.swift` | the scoped absence value, its guarded publication in the existing branches, and its clears. **No other hydration change** |
| 2 | `MOTIVO/ProfileView.swift` | two new policy inputs; evidence as `(owner, generation)` recorded from the accepted result; triggers 3 and 4 |
| 3 | `MOTIVOTests/FreshJoinContinuationTests.swift` | policy and ordering cases |
| 4 | `MOTIVOTests/C70DirectoryWriteTransportTests.swift` | production-sequencing cases |

**§12.4's count of two was wrong even before the AuthManager addition** — it omitted the
transport suite. Untouched from the handle-removal manifest becomes **16 source / 7 test**,
because `AuthManager.swift` is in that manifest; every one of those is verified at the end.

## 13.6 Tests

| # | Test | Kind |
|---|---|---|
| **F3-1a** | **Absence known, THEN completion** — no failure ever → exactly one real write | policy + writer |
| **F3-1b** | **Completion, THEN absence** — the order gap 1 named → exactly one real write, driven by trigger 3 | policy + writer |
| **F3-1c** | Both already passed, then Profile appears → trigger 4 publishes once | policy + writer |
| **F3-2** | No second write once evidenced, across further completions | policy + writer |
| **F3-3** | Returning member (no absence evidence) → **zero requests** across several completions and appearances | policy + writer |
| **F3-4/5** | `pending` writes nothing; a later `.established` **or** `.alreadyEstablished` publishes | value |
| **F3-6** | **Same owner, changed directory generation**: applied evidence no longer matches → a publish is permitted; absence evidence from the old generation does **not** authorise one | value |
| **F3-7** | A→B→A: neither absence nor applied evidence from the first A session is honoured | value |
| **F3-8** | An absence value whose fresh guard failed is never published | AuthManager-level |
| **F3-9** | Repair path unchanged; boundedness unchanged | value |

Positive controls: revert the widened condition and watch **F3-1a** fail; remove trigger 3 and
watch **F3-1b** fail; drop the generation from the evidence and watch **F3-6** fail.

## 13.7 Out of scope

Rewriting hydration; changing `backendBootstrapState`; any timer, delay or retry loop; any
change to the coordinator; any gate, server or schema change; identifying which request created
the row at 10:53:17.
