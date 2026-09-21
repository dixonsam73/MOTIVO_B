> **HISTORICAL — ARCHIVED 21 September 2026. NOT CURRENT WORK.**
>
> Scope review and fresh-window instructions for the bounded C-70 fix, written against baseline `79fe153` when no code was yet approved.
>
> The C-70 work it scopes was implemented and committed as `8b54ba6`, and the remaining gaps were addressed inside `b479487`. Its baseline, its "no code approved yet" and its window instructions are all spent.
>
> **Any instruction, scope, baseline, cadence or "next step" below is spent.** For the
> current position see `docs/account-id-removal-evidence-2026-09-20.md`, `docs/fresh-join-f3-evidence-2026-09-21.md`, `docs/recorder-r1-evidence-2026-09-21.md` and `docs/release-priority-review-2026-09-21.md`, and take the repository state from
> `origin/feature/solo-connected` rather than from any commit named here.
>
> The text is preserved unchanged; only this banner was added.

# C-70 scope review and fresh-window instructions

Samuel authorises the bounded C-70 fix with Claude implementing and Codex reviewing. Scope only;
no code approved yet. Baseline 79fe153, feature/solo-connected. B-37 deployed and verified;
recorder pending-start unit accepted. No need to revisit those units.

Review of claude-opus5-c70-profile-write-scope.md:

1. **Part B is already decided.** D-U6-3 explicitly allows self-profile maintenance while lapsed:
   supabase/sql/README-u6a-deployment.md:27 and README-u6b-plan.md:161,416. Adopt B2 (existing-row
   owner update, gated creation) as restoring documented intent, not a new product decision.
2. ProfileStore.hydrateMissingLocalIdentity fills missing fields only. Preserve existing nonempty
   local edits; no destructive hydration redesign. Examine deliberate empty-field semantics
   against the existing contract, rather than silently broadening this change.
3. 403/42501 establishes policy/privilege refusal, NOT necessarily membership expiry. Do not
   attribute all such failures to subscription state. Existing red warning means local/remote
   divergence was not literally silent; local persistence was mistaken for remote success.
4. Before implementation, specify exact owner-bound PATCH/result evidence, including returned
   row identity and expected values, zero-row handling, gated absent-row creation, races between
   PATCH and creation, ambiguous transport, identity switches and same-owner stale completions.
   Account-ID generation must not overwrite a concurrently chosen manual/newer handle.
5. Keep local ownership, privacy payload omission, current scope011 entitlement and server
   policies/grants unchanged. No age/join-flow redesign, sharing protocol, recorder work,
   production mutation, new credentials, account cleanup, commit/push or device actions.

Claude flagged implementation context tight at ~714k/1M. Samuel has separately asked Claude in
its UI for a handover and intends to paste into a new window. Incorporate these corrections in
that handover, then fresh window designs the exact sequence; Codex reviews before code.

Protected: invitation docs, untracked AGENTS.md, Codex review/handover docs. Existing review
record: docs/phase-6-b37-codex-review-2026-09-20.md. Source schema authority is current capture
and scope011 (active Sandbox accepted), not earlier Production-only migration.

## Fresh-window protocol review — 20 September, approximately 17:00 UTC

Read `claude-opus5-c70-write-protocol-design.md` in the external outputs folder,
and current AccountDirectoryService/ProfileView source. Returned for revision;
implementation is NOT approved yet. Delivered to verified fresh Claude task.

- Owner equality does not suppress same-owner stale responses or A→B→A identity
  transitions. Require explicit operation ordering/generation across writer callers,
  outbound credential binding, and guards around cache/feed/UI effects and awaits.
  Inspect existing NetworkManager owner-bound facilities. Response suppression alone
  does not prevent reordered server writes.
- Returned value mismatch is not evidence of concurrency. Compare exactly the sent,
  sanitised fields, accounting for omitted fields/nulls; do not confirm unproved saves.
- Specify POST Prefer semantics and bounded handling of PATCH-to-create races;
  distinguish primary-key conflict from handle collision. No blind ambiguous retries.
- Generation zero-match is ambiguous (missing row or populated handle); silent stop
  acceptable, but no invented cause. Verify empty-handle schema contract.
- Keep avatar behaviour outside implementation scope; record 204 observation against
  existing findings. Do not adopt avatar receipts as inherently fresher.
- Reject refusal copy saying retry cannot help. Accurate local-versus-remote wording
  is routine delegated work, not a new Samuel product gate; verify local persistence
  before promising it. Add deterministic ordering/evidence/race tests.

Claude is revising the design. Eight-minute heartbeat confirmed ACTIVE and addressed
to the fresh task; no production, device, commit or push action authorised here.

## R2 reviewed; bounded implementation authorised — approximately 17:09 UTC

Read external `claude-opus5-c70-write-protocol-design-r2.md` and independently
read NetworkManager boundRequest and current call sites. Authorised Claude's local
implementation/tests with these conditions, delivered in the fresh Claude task:

- Preserve local persistence timing; generic copy says only that Connected saving
  could not be confirmed. No new Core Data save behaviour to justify local-save copy.
- Serial dispatch does not prove server ordering after timeout/cancellation; carry
  that residual alongside process-death/cross-device races. No automatic ambiguous
  replay or cancel-active-to-start-new strategy.
- Prefer FIFO; any coalescing must preserve operation semantics and explicit fields,
  never replace handle-only generation with an unrelated snapshot. Resolve all callers.
- Wire identity epochs at actual identity/reset transitions; test A→B→A without
  intervening submission. Guard actual mutations across awaits and local edits made
  during debounce before submission. Generated handles cannot overwrite manual intent.
- Bounded PATCH following creation 403 is not proof a row exists. Distinguish writer
  fallback from transport refresh/retry. Refresh already begun cannot be prevented
  retroactively by identity change; retry/effects can be withheld.
- Compare only sent fields (generation only account_id); strict receipt identity,
  cardinality and selected-key decoding, distinguishing omitted JSON from null.

Claude implements/tests and returns diff/evidence for independent review. No commit,
push, device, production, schema, age/sharing/recorder/avatar work authorised.

### Early implementation check — 17:15 heartbeat

Claude running first Debug build; no completed checkpoint yet. Read new coordinator,
evidence types and writer. Queued concrete feedback in Claude UI: notEvidenced currently
merges cache contrary to design; in-flight operation has no sequence effect guard after
newer submission; actor cache mutation needs guard at actual mutation boundary; require
all selected receipt keys before consuming omitted-field values; capture generation's
identity epoch before fetchSelfRow, not after, and preserve it across retries. Claude
continues implementation/tests; these are provisional in-progress findings, not final
review results. No second build launched by Codex.

### 17:24 heartbeat — implementation still in progress

Claude reports Debug green, writing deterministic tests. Early fixes present, but
two remaining gaps sent back: actor applyIfNewer compares last APPLIED epoch rather
than latest submitted/identity invalidation, leaving a guard-to-mutation race;
writer can suppress cache effects but return applied, and ProfileView lacks post-await
identity/epoch guards and gates only latch (not messages) on screen freshness.
Requested atomic freshness enforcement and deterministic caller-effect tests,
including debounce edits and generation adoption. Await completed checkpoint;
no tests rerun by Codex and no implementation acceptance inferred from Debug build.

### 17:33 heartbeat

Claude reports test build green; focused tests hit simulator launch failure and
are being retried after simulator boot. UI result freshness guard now present.
Read lock-backed validity/cache correction: isCurrent releases lock before cache
mutation, allowing cross-thread invalidation between check and assignment even
without await. Sent exact atomicity correction (hold same lock through short
synchronous cache mutation; no await/re-entry) and deterministic test request.
Feedback visibly queued in fresh Claude task. Final checkpoint still pending.

### 17:43 heartbeat

Independently confirmed cache assignment now occurs inside withCurrent's shared
lock. All three protected file hashes match baseline. Claude correcting focused
test fixtures/source paths and registration-order barriers after discovering
vacuous passes; no completed validation claim yet. Asked finish focused/full
validation and return exact evidence, excluding earlier vacuous coverage. No new
scope or owner decision, and no second build launched.

### 17:52 heartbeat

Claude reports all focused classes green and full suite running serially. Read
test inventory and revised caller/writer wiring; final review still pending full
checkpoint and independent result evidence. No new action requested while full
suite runs; no duplicate builds or tests launched.

### 18:01 completed checkpoint reviewed — NOT accepted

Read implementation checkpoint; raw full-suite log independently counted 930 pass,
0 fail, 9 skipped. Claude reports Release green. xcresulttool summary blocked by
report-cache filesystem permissions both original and copied bundle; no xcresult
verification claimed. Two concrete regressions returned for correction/tests:

1. AppSetUpView ignores returned generation/seq and switches only outcome, then
   adopts generation and completes setup across stale identity/operation. Guard
   all post-await caller effects and distinguish stale generation from benign nil.
2. ProfileView saved fingerprint A survives dispatch B. Revert to A while B is in
   flight skips re-publish A; B lands and response is suppressed, leaving server B.
   Invalidate/re-scope skip token around differing submissions; deterministic test.

Also requested stale notEvidenced comment, race residual wording, and coverage
counts correction. Local corrections/tests authorised; full validation to refresh
after changes. No user decision or commit/device/production action needed.

### 18:11 heartbeat

Claude incorporated onboarding identity guards and invalidates the profile skip
token at differing submission. Independently read revised call sites and extracted
caller-policy tests. Full suite is running again after those changes; no final
validation/acceptance claim yet. No competing test run or new user dependency.

### 18:20 heartbeat

Latest full run exposed test registration-order assumption and a structural test
matching its own comment; Claude corrected both and is rerunning. Read explicit
older-before-newer registration fix. Asked exact final skipped test names/reasons
and baseline comparison because Claude reported a skip-count change; also final
raw logs/xcresult path and refreshed Release evidence. No acceptance yet.

### 18:29 heartbeat

Independently parsed scratch logs: full-suite2 940 pass/2 fail/10 skip (coordinator
registration and comment-matching test failures, since corrected); full-suite3
942 pass/1 fail/9 skip. Nine skip names match first run; extra prior skip was
SharedOnlyUploadTests.testConnectedShareOffCreatesNoPostRow. Latest failing test:
PublishServiceConnectedDeleteTests.testPrivatePayloadUnsharesEvenWhenCallerAsksToPublish.
Claude reports isolated rerun passes and Release rebuilding. Requested exact
assertion/runner evidence: isolation pass plus adjacent simulator launch failure
does not establish causality. Final report must preserve full-suite failure and
separate rerun, not combine into all-green claim. No blanket rerun requested.

### 18:38 checkpoint — one controlled final validation authorised

Read corrected checkpoint: isolated failing class 8/8, refreshed Release reported
green, full-suite failure remains unexplained; exact failure bundle lost to
DerivedData retention (independently verified only isolated bundle remains).
No additional source blocker identified. Authorised ONE full-suite run with
parallel testing disabled/one worker and UNIQUE persistent resultBundlePath/raw
log, final code unchanged. Justified by unresolved full-run failure, not repetition
of passing checks. Preserve before any next invocation. On failure inspect exact
reason, do not loop reruns; on pass keep prior failure recorded separately.
Next gate after preserved validation is bounded device-QA plan/checkpoint.
No device/production/commit/push action authorised.

### Controlled validation independently verified — LOCAL IMPLEMENTATION ACCEPTED

After Samuel said Claude is done, independently read persistent controlled
xcresult: result Passed, failedTests 0, skippedTests 9, passedTests 941 aggregate
and 944 device row. Summary records one dynamic-parameter test with four runs;
consistent with the difference, not needed for acceptance. Read tests tree and
verified exact nine skipped identities against baseline; final Release log has
BUILD SUCCEEDED. git diff --check clean; protected hashes unchanged.

Accepted local implementation. Requested Claude finish audit/QA records and
cross-reference carried avatar/minimal-return and local persistence observations
without duplicate findings. Prepare concrete Device A build/QA checkpoint, no
install/launch yet: Ben Craft name edit/reopen, quick edit/revert, naturally lapsed
owner case if available, authoritative backend read bracket and privacy preservation.
No new purchase/reset/signup/deletion/production-policy/recorder work. Device QA
still pending; no commit/push authorised. Prior unexplained full-run failure stays
recorded separately. No further suite reruns needed absent changes.

### Device checkpoint prepared; handoff to Samuel

Read docs/qa-plan.md Group C70. Asked Claude correct documentation before QA:
generic cannot-confirm warning permits either changed or unchanged server state;
manual quick revert proves eventual latest value, not controlled in-flight race;
git-status digest is not a source-content digest, use content manifest plus binary
hash/build configuration. No application edits or retests required for these.
Samuel's next step: Xcode Release Run to SD beta burner, open existing Ben Craft
profile and leave name unchanged for read-only backend baseline. No reinstall by
Codex, no name edit/purchase/reset/commit/push performed. Scheduled polling paused
at this owner device checkpoint; resume when Samuel reports device ready.

### Device signed in but Solo — membership baseline checked by Claude

Samuel reports signed in, still Solo. Claude read-only baseline reports current
connected_member false, Sandbox renewal_date/entitlement_ended_at17:09:33 UTC,
no grace/revocation; privacy values intact. Name now Ben Craft QA1, differing
from16:12:54.889440 Ben Craft restoration. Cause/time of later write unknown.
Returned unsupported inference that name could only change while entitled:
owner UPDATE is ungated. Asked correct QA name/restore expectation and distinguish
renewed success-path QA from naturally lapsed-path coverage.

Independently read AppModeManager and ProfileView: mode==connected guards profile
sync, so naturally lapsed Solo cannot reach the writer. C70-3 unavailable on this
rig state. No gate change authorised; D-U6-3 settled intent remains. User renewal
would enable C70-1/2 only; no purchase/renewal/device mutation performed by agents.

### C70-1 device check PASS

Samuel renewed existing Sandbox subscription; Connected active. Independently read
Claude's persistent PRE-baseline:19:11:06.071988UTC, eligible true, name Ben Craft
QA1, protected privacy unchanged. Samuel changed name to Ben Craft C70 and reports
it persisted after leaving/reopening, no warning. Independently read POST1 raw
result confirming Ben Craft C70, eligible true, protected privacy unchanged.
C70-1 normal-path backend and UI outcomes pass; no request-level trace inferred.
Next user step: temporary name and quick return to Ben Craft, followed by POST2;
manual sequence proves eventual latest value only, deterministic race test local.

### C70-2 device check PASS — bounded unit accepted

Samuel reports Ben Craft and no warnings after temporary edit/revert and reopening.
Independently read POST2 persistent raw result:19:14:54.742106UTC, name Ben Craft,
connected_member true, directory lookup false, privacy lookup true/timestamp and
follow setting unchanged. Both normal edit and eventual latest-value device checks
pass. Controlled in-flight timing remains locally tested, not observed on phone.
Naturally lapsed Solo reachability remains carried; C70-3 not exercised and broad
lapsed-maintenance promise not closed. Device build provenance limit retained.
Claude recording final audit/QA and explicit commit scope; no source changes/test
reruns needed. No commit/push performed or authorised. Polling remains paused at
Samuel checkpoint.

### Final commit checkpoint reviewed

Independently matched all13 source/test files against recorded content manifest:
zero mismatches. git diff --check clean, protected hashes unchanged. Reviewed
final QA/audit records and approved bounded unit for Samuel's commit instruction.
Exact proposed scope15 paths:13 Swift/test files plus docs/audit-findings.md and
docs/qa-plan.md. Corrected Claude's summary count13 and requested remove unsupported
inference that same transaction chain alone proves no second membership row.
No source edits/retest necessary. Claude holds uncommitted; Samuel commits via
Claude and pushes himself. Codex records/invitation docs/AGENTS excluded.
