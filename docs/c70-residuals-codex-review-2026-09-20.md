> **HISTORICAL — ARCHIVED 21 September 2026. NOT CURRENT WORK.**
>
> Independent review of the C-70 residual scope. Its own header records local acceptance at 972/0/6 with nothing committed.
>
> That work is now committed and pushed inside `b479487`, and the suite has since moved to 1076 tests. The uncommitted state it describes no longer exists.
>
> **Any instruction, scope, baseline, cadence or "next step" below is spent.** For the
> current position see `docs/account-id-removal-evidence-2026-09-20.md`, `docs/fresh-join-f3-evidence-2026-09-21.md`, `docs/recorder-r1-evidence-2026-09-21.md` and `docs/release-priority-review-2026-09-21.md`, and take the repository state from
> `origin/feature/solo-connected` rather than from any commit named here.
>
> The text is preserved unchanged; only this banner was added.

# C-70 residual scope — independent Codex review, 20 September 2026

**Current status: LOCAL IMPLEMENTATION ACCEPTED.** Final Debug test compilation and Release build passed; 65 focused tests passed and the full suite passed 972/0/6 (978 total). Nothing committed or pushed. Real lapsed-owner hardware QA remains unperformed. Phase 6 remains open. The entries below preserve the review chronology and do not supersede this current checkpoint.

Samuel authorised proceeding with the next C-70 scope. Claude owns implementation; Codex reviews the scope and resulting changes. This record does not close Phase 6, accept its proposed deferrals, or authorise a commit, push, device experiment or production mutation.

Baseline: `e5b3b08788e88324c942421ed64b640db122acf0`. Existing documentation alignment edits are preserved. The two protected invitation documents and untracked AGENTS.md remain protected.

## Independent source findings

- `ProfileView.syncDirectoryFromCurrentState` checks both `canShowConnectedAccountManagement` and `BackendEnvironment.shared.isConnected`. The first derives from app mode; the second derives from the backend mode stored in UserDefaults. Removing only one cannot make naturally lapsed maintenance reachable.
- `AccountDirectoryService.upsertSelfRow` and its owner-bound request transport have no corresponding mode guard. Existing-row PATCH is followed by creation on no-row, with a bounded PATCH probe after policy refusal or row conflict. Any residual-scope policy must explicitly preserve gated creation and the existing receipt, owner, generation and sequence checks.
- `NetworkManager.boundRequest` delegates a 401 to `onAuthChallenge`. `AuthManager` installs a callback to the mode-gated `ensureValidSession(force: true)`. In Solo that helper returns the local sign-in flag without refreshing. Therefore removing the ProfileView guards alone does not establish expired-token lapsed-owner recovery. This finding was sent to Claude before scope approval. A bounded refresh design must retain owner/generation checks around suspension, forced-refresh semantics and the one-retry rule; it must not globally widen unrelated request behavior.
- Local `save()` mutates Profile then silently catches `ctx.save()` failure. `persistProfileEdits()` is called on disappearance; a separate sign-out path calls `save()` too. Do not describe disappearance as the only caller of `save()`.
- The context-save notification calls `load()`, which reloads the name from the managed object. Draft protection must cover unrelated context saves, hydration, and identity transitions. A generic save notification is not evidence that the current draft was persisted.
- Account ID and location use separate per-identity defaults storage; the name belongs to the local Profile. A local save mechanism must respect those different ownership rules. Factory-reset paths must not recreate erased profile data.
- The existing account-ID field and directory error message are hidden by the Connected-management gate. Opening only the write path leaves maintenance feedback hidden from a lapsed member; a narrowly scoped visibility rule is needed rather than opening general Connected controls.

## Review state

Scope pending from Claude. No implementation approval has been given. Required review covers local failure recovery and dismissal behavior, draft/hydration interactions, lapsed session refresh, missing-row behavior, and a meaningful local evidence plan. C-34 avatar work, general Connected access, age policy, sharing protocol and recorder work remain outside this scope.

### First proposal returned for revision

Read `phase-6-c70-remaining-gaps-scope-2026-09-20.md`. Existing-owner PATCH with unchanged gated creation and Connected-only automatic handle generation is an acceptable boundary. Location may travel with the existing local persistence function. Approval remains withheld for these concrete gaps:

1. Deferring the mode-independent refresh leaves natural-lapse recovery incomplete. Address it within an operation-specific boundary and test the actual 401 path, including identity changes during refresh.
2. The proposed identity-transition discard treats the local name as backend-owned. Existing sign-out deliberately preserves the local profile. Preserve that behavior while invalidating previous-owner network work and reloading owner-scoped handle/location state.
3. Blur/background/disappearance does not establish local-first persistence when the existing debounce can publish while the name field remains focused. Establish a local commit before that remote submission; local failure must prevent publishing that unsaved revision.
4. Guard `load()` itself against overwriting dirty drafts, including its direct context-save caller. Explain dismissal/reopening recovery honestly: retaining SwiftUI state is not durable storage.
5. Lapsed maintenance errors need a visible location. Keep general Connected controls gated, but define profile-maintenance feedback and account-ID field visibility explicitly.
6. Behavioral tests must exercise dirty draft, retry, unrelated save, identity transition, reset, dismissal and transport policy. Source text checks cannot be the primary evidence.

Protected SHA256 values were rechecked against the handover and match all three files. No source changes at this review checkpoint.

### Revision review and delegated decisions

The next revision corrected local-name ownership and the direct `load()` callers, but still deferred the 401 challenge and asserted unmeasured Core Data behavior. Returned for correction:

- A preflight alone does not cover a server-refused token. An optional operation-specific challenge handler, defaulting to the existing global callback, is a bounded route; global policy need not change. A forced mode-independent helper must preserve non-force defaults and C-98 refresh slot ownership. No 403 refresh and no identity-crossing retry.
- Do not assert that a failed Core Data save posts a did-save notification without evidence. `save()` assigns the managed object's name before saving; failed persistence can leave changed values in the shared context. Same-context reopening, a fresh context, and process loss are distinct cases and need honest evidence.
- Local commit must cover the common sync entry, including direct account-ID submit/blur callers, not only the debounced caller. Previous-owner debounce work needs invalidation before it reaches the coordinator.
- The narrow profile-maintenance message and Account ID editor may use Connected identity independently of membership. General management stays gated. Do not hide the editor as its text becomes empty. Manually assigning a handle on an existing row is not automatic generation; creation remains server-gated and automatic generation remains Connected-only.
- Positive controls need attributable behavioral failures, not compilation failures caused by removing newly introduced APIs. Predict the outcome and restore exact bytes.

Awaiting one consolidated scope with exact file boundary before implementation approval.

### Revision 2: measurement checkpoint authorised

The consolidated direction is acceptable. Claude is authorised to run isolated Core Data measurements M1–M3 and an on-disk store teardown/reopen proxy for M4 before application implementation. This uses disposable test stores, never real user data; an in-process teardown is not a measured process kill.

Implementation approval still awaits the measured failure-handling design. The shared view context must not be rolled back merely to simplify draft recovery: unrelated changes could be discarded. Additional requirements sent to Claude:

- Preserve the existing global challenge callback, which already explicitly uses `force: true`. The non-force default belongs to the mode-independent helper's proposed optional `force` parameter, not to the global challenge callback.
- Persist locally before the no-identity remote guard, so account-free Solo also benefits from debounce persistence.
- Cover factory-reset invalidation and prevent erased values being reintroduced.
- Capture/check owner and generation before and after any newly added preflight suspension.
- Pass the optional maintenance challenge through the service from ProfileView only. Setup, hydration and automatic generation retain existing behavior.

No commit, push, UI-test suite, device QA or production action authorised by this checkpoint.

### Independent measurement results

Read `c70-measurements-raw.txt` in the persistent evidence directory and the second result bundle's summary (using a temporary copy because Xcode's reader updates report caches). Two tests passed, zero failures/skips, on iPhone 17 Pro simulator iOS 26.5.

- Both controlled validation failure and read-only-store failure produced zero did-save notifications.
- Both retained `EDITED` in a same-context fetch and left `context.hasChanges == true`.
- The read-only-store case returned `STORED` from a fresh context and after store teardown/reopen. The latter is an in-process proxy, not a process-kill test.

These measurements support preserving the context's pending values, reporting the failure, and retrying without rolling back unrelated work. They do not establish durable recovery after failed persistence. First run passed but did not yield readable printed measurements; the second added a durable file/attachment evidence sink. This is not an unexplained failure rerun.

Claude is additionally measuring whether a later successful save commits a pending edit (M5), directly relevant to retry semantics.

### Bounded implementation approved

Read M5's raw result and harness: after the validation cause was corrected, a later successful save committed `EDITED` without reapplying the name, independently fetched through a fresh context. Approved implementation in the revised four application files plus tests, with sequential Debug/Release and full unit validation. No commit/push/device/production permission is conferred.

Final clarifications attached to approval:

- Every new edit reopens the draft-clobber window. A previous failed or successful save does not make a newer UI draft safe from `load()`; protect the newest draft until evidenced persistence.
- M2 measured a same-context fetch, not SwiftUI dismissal and reopening. Recovery depends on retaining the context without reset; process-loss durability remains absent after failed persistence.
- Factory reset is an explicit exception to draft retention; erased data must not be resurrected.
- Keep local failure feedback separate, clear and retryable, and never represent a failed save as durable.
- Preserve the exact global forced challenge callback. Only ProfileView maintenance supplies the operation-specific override.
- A small testable helper may live inside scoped ProfileView.swift. A new application-file boundary requires review first.

Implementation and final evidence review are pending.

### In-progress code review corrections

Reviewed the actual four-file diff as Claude implemented it. The transport override and force-capable helper preserve existing defaults and owner/generation guards. Returned these implementation defects before acceptance:

1. A missing local Profile initially returned success. That is no persistence evidence and must not unblock publishing. Claude changed it to a local failure.
2. Marking name dirty only in `onChange` was late and also marked programmatic hydration as user intent. Claude moved it into the user-edit binding setter.
3. Cancelling a debounce before factory reset is insufficient: local-only reset may produce no identity transition, and later disappearance can call persistence after the global reset flag clears, recreating location defaults. Require a view-lifetime invalidation that blocks load/save/defaults writes/scheduling and clears presented state when reset actually begins.
4. An untracked outer Task in name/location `onChange` can schedule after identity-change cancellation. Capture owner/generation before delayed work, verify before acting, and remove avoidable scheduling hops. Direct-submit tasks need the same scrutiny.
5. Local failure feedback needs an actionable Retry route through the common local-first path.

Final acceptance awaits these corrections, meaningful tests and required build evidence.

Further caller review found the sign-out path discarding `save()`'s new result, and two direct defaults writes (sign-out location and Account-ID edit) needing the lifetime reset guard. Claude has been instructed to preserve existing location ownership while surfacing the save result and guarding those writes. Direct-submit/Retry tasks now capture owner/generation before task creation, matching debounce protection.

An intermediate Debug and Release build passed (Release marker independently read). These precede the final corrections and are not final-byte validation.

The first acceptance-test draft mostly exercised Boolean policy and dirty-state setters. Returned for substantive behavioral coverage of the actual production-used local-save gate, reset storage suppression, delayed submission ownership, and real transport/forced-refresh paths. Merely naming a Boolean-reset test “does not resurrect” or calling the helper while signed out does not prove those behaviors. Requested an opt-in measurement evidence sink instead of a hardcoded personal path appended during future test runs.

The first sequencing extraction passed a no-op submission closure in production and did the real write after the helper returned. Rejected: its counted test would not exercise the real continuation, and the new await separated local persistence from later snapshot/owner capture. Requested either a synchronous, honestly named permission gate or a helper carrying the actual remote step, with no new unguarded suspension. Also requested trimming structural tests back to the two scoped supporting pins.

## Final implementation review and unit evidence

The final code uses a synchronous `ProfileMaintenanceGate.decide` with the real local persistence closure. There is no introduced await between local commit and snapshot capture. Scheduling tokens are captured before both delayed and immediate tasks. Reset lifetime guards cover persistence, load, sign-out defaults and Account-ID defaults. The name binding marks user edits dirty immediately; hydration cannot overwrite a newer draft. Local failure has a separate Retry surface. The four application files remain within scope; the service's optional challenge parameter is supplied by ProfileView maintenance only.

Independently read raw result summaries and all individual test identities:

- `c70-targeted-20260920-2.xcresult`: **65 passed, zero failed, zero skipped**.
- `c70-impl-fullsuite-1.xcresult`: **972 passed, zero failed, six skipped; 978 total**.
- Against `p6cleanup-20260920-suite-2.xcresult`: **zero missing tests, 32 added tests**. The only status changes are `UnshareDurabilityTests/testDemotionUnreachableKeepsIntentQueued()` and `StalePathQueuedPublishTests/testPublishThenReinspectFixture()`, both **Skipped → Passed**. The six remaining skips are the same standing opt-in cases (three ordering reproductions and P6I02 TL5/TL6/TL7).

The new C-98 cases demonstrate actual forced rotation of an unexpired token in Solo, unchanged non-forced behavior, and the global mode-gated helper's unchanged behavior. The scoped transport tests separately establish handler selection, one retry, refusal without refresh, and generation-change abandonment. This is component evidence plus independent call-chain review, not a hardware end-to-end claim.

The counted local gate/reset/draft/token tests exercise production policy types but **do not mount ProfileView or execute its SwiftUI modifiers**. Their storage-wiring coverage is supplied by this independent source review, not an invented UI-test result. Core Data failure and recovery measurements are separate evidence.

### Failure history and limits

- Intermediate compile failures were diagnosed: missing challenge parameter threading; duplicated `@MainActor`; helper types nested inside ProfileView rather than at file scope. Corrected before passing final test compilation.
- First targeted run: 48 passed, one failed. The pin's extractor preferred a later five-space declaration over a nearer four-space declaration and therefore included the generation function's legitimate mode guard. Corrected extraction; no product change was required for this failure. The two supplemental pins now exclude comments.
- **No designed production mutation/positive controls were run.** The unplanned pin failure is not one. This limits claims about counterfactual sensitivity; it does not erase the exercised injected failures, actual token changes, preserved test identities or source review.
- No real lapsed-owner hardware QA, production write, commit or push occurred. Failed saves remain vulnerable to process loss; no durable draft store was added. General Connected access, creation gates, automatic-generation mode gate, age/band protections, avatar work and sharing protocol are unchanged.

Final Release and documentation consistency checks remain pending at this entry.

## Final acceptance checkpoint

Independently read `c70-impl-release-final.log`: **BUILD SUCCEEDED**, with no compiler-error matches. Final Debug test compilation is evidenced by the passing final unit run. Recomputed and matched all **nine application/test hashes** in `c70-impl-source-manifest.txt`, plus all three protected-file hashes. `git diff --check` passed. HEAD remains `e5b3b08788e88324c942421ed64b640db122acf0`.

**Accepted the bounded local implementation and notified Claude to hold for Samuel's explicit commit instruction.** This accepts neither real-device behavior nor hosted-RLS end-to-end evidence, and does not close Phase 6 or approve production changes. No further source/test edits are needed for this checkpoint. The limits stated above remain explicit, including no designed mutation controls and no mounted-View tests; acceptance rests on the component tests, measured persistence behavior, unchanged baseline test identities and independent source/caller review.

Claude's scope, next-work note and audit row now record local implementation and unperformed lapsed-owner device QA. Requested two final wording corrections: revision 3's retained “no code/test action” sentence was stale, not historically true after measurements; the single unexpected test-assertion failure must not be conflated with the separately recorded compiler failures.

Persistent evidence directory: `/Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/`.
Key artifacts: `c70-impl-source-manifest.txt`, `c70-impl-release-final.log`, `c70-impl-fullsuite-1.xcresult`, `c70-targeted-20260920-2.xcresult`, `c70-measurements-raw-20260920-preserved.txt`.
