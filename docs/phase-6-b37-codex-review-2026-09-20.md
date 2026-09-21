> **HISTORICAL — ARCHIVED 21 September 2026. NOT CURRENT WORK.**
>
> Codex coordination and review for B-37, including the eight-minute cadence then in force.
>
> B-37 is deployed and committed (`79fe153`). The cadence it describes is not running; recorder automation was paused on 21 September.
>
> **Any instruction, scope, baseline, cadence or "next step" below is spent.** For the
> current position see `docs/account-id-removal-evidence-2026-09-20.md`, `docs/fresh-join-f3-evidence-2026-09-21.md`, `docs/recorder-r1-evidence-2026-09-21.md` and `docs/release-priority-review-2026-09-21.md`, and take the repository state from
> `origin/feature/solo-connected` rather than from any commit named here.
>
> The text is preserved unchanged; only this banner was added.

# B-37 — Codex coordination and independent review

## 20 September 2026: resumed; scope pending

Samuel explicitly confirmed the fresh Claude window is ready and instructed Codex to
proceed with Claude, checking every eight minutes and hard-stopping for product decisions.
This supersedes the shared handover's pause and its absence of automation authority.
The controlling handover is `phase-6-b37-fresh-window-handover-2026-09-20.md`.

Fresh baseline: `feature/solo-connected`, HEAD `4ac01c9`. The two modified invitation
documents and untracked `AGENTS.md` still match the handover hashes; the shared handover
is also untracked. No implementation, commit, production apply or push by Codex.

Claude's real desktop session was identified through the UI as **Handover to fresh
Claude window**, `claude.ai/epitaxy/local_4b3649e0-e768-4040-9e5c-9cf2d0e803eb`.
Her response independently recognises Samuel's B-37 authorisation and supersedes her
older proposal's pending-decision wording. Codex sent the bounded scope request and
instructed her to stop for review before coding. No unrelated housekeeping was authorised.

The existing paused heartbeat `tudes-overnight-review-with-claude` was updated, renamed
**Études B-37 review with Claude**, and attached to this fresh Codex task at eight-minute
intervals. Its saved configuration was read back: ACTIVE, interval 8, target task
`01a0beac-1b2b-78e0-be57-cbd46aae8285`. It must remain quiet on unchanged/non-actionable
progress and stop dependent work for Samuel's decisions. Pause it at the final checkpoint
or an owner decision where further checking cannot help.

### Independent source review before scope

- `PeopleView.lookupSection` submits only on the search-button tap. No per-keystroke
  requests; allowance rationale must use explicit searches rather than typing cadence.
- `AccountDirectoryService.search` sends POST and decodes the existing seven-field array.
- `PeopleView.performLookup` retains the input but clears prior results; errors currently
  show "Search unavailable." A throttle needs a distinct temporary message.
- `NetworkManager.request` retries authentication only for HTTP 401. Keep HTTP 429 out
  of that path; no broad networking rewrite is indicated by this source review.
- The committed function capture agrees with the CP-1/CP-2 migration: unescaped tokens
  reach account-prefix, display-name and instrument LIKE predicates. Two-character floor,
  all-token matching, self exclusion, effective privacy, membership checks, returned fields
  and ordering need preservation. This is source evidence, not a local exploit result.
- Committed account-directory SELECT policy is owner-only. The by-ID RPC's existing
  membership/approved-follow disjunction and discovery-opt-out carve-out remain unchanged.

### Focused requirement sent to Claude

Test `Prefer: tx=rollback` as well as alternate methods and helper routes. PostgREST's
[transaction documentation](https://docs.postgrest.org/en/stable/references/transactions.html#transaction-end)
describes configurations that permit a response while rolling back its transaction. A
transactional counter must not allow directory data to be returned without a durable debit
through that route. Establish local behaviour; do not assume production configuration or
run production probes. Also cover empty/whitespace tokens. This is a candidate bypass
requiring testing, not a claim that the current deployment enables it.

Scope review and implementation acceptance are still pending. Exact allowances and
counter-failure policy are not approved. Claude owns implementation/tests and separately
approved commits; Samuel owns pushes and production approval. Adult assurance remains frozen.

## Scope review accepted with corrections — 20 September, first heartbeat

Samuel clarified: **"If you approve of the scope, have claude proceed with implementation..
only pause if you need me for a serious product changing decision"**. This supersedes the
earlier requirement to refer routine scope choices to him. Codex read Claude's entire scope at
`/Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/claude-opus5-b37-implementation-scope.md`
and sent explicit local implementation/test approval through the verified desktop session.
The UI showed the approval delivered and Claude running. No second scope approval round is
required unless evidence defeats the constraints below. These are Codex review decisions under
Samuel's delegation, not individual choices attributed to Samuel.

1. **No per-token minimum.** Decline D4's proposed restriction: preserve `J Smith` and
   legitimate multi-token searches. `a e` is broad literal matching, not a wildcard bypass;
   two-character terms and instruments can also match most of a small population. Keep the
   whole-query floor of two, and require at least one non-empty token to avoid vacuous matching
   for separator-only queries. Test both conditions.
2. **Initial allowances: 10/60 seconds and 120/60 minutes**, as named function constants.
   These are anchored fixed windows, not rolling windows. Boundary doubling is a residual.
   Validate realistic explicit-submit scenarios; these are provisional choices from interaction
   shape, not measured optimal launch quotas. Do not add settings to `membership_control`.
3. **Counter errors fail closed**, displaying ordinary search-unavailable copy. Only actual
   budget exhaustion gets a typed throttle. Failed/refused transactions consume no allowance;
   they still cost database work. Remove claims otherwise and unproven contention claims.
4. **Wait copy must be honest.** Derive `retry_after_seconds` from the blocked window ends,
   taking the maximum if both block. Send machine-readable detail and render a rounded
   duration without a countdown/timer. Generic temporary copy is the fallback for missing or
   malformed duration. Preserve the query, no authentication refresh or sign-out.
5. **Retain escaped LIKE** with the escape character escaped first and explicit ESCAPE on all
   branches. Positive special-character tests need two-character queries to respect the floor;
   test all matching branches and unambiguous SQL backslash literals.
6. **Transaction defence requires both testing and a deployment precondition.** Test header
   forms supported by PostgREST, including mixed preferences and duplicates. A header guard
   cannot defend unconditional `db-tx-end=rollback` without a header, so production commit-mode
   verification remains a deployment prerequisite. Prove durable debits under relevant local
   configurations and restore them. No production calls authorised.
7. Test concurrency crossing both limits, bounded successful debits, excess refusals,
   independent identities, counter faults, and reset boundaries. One-row locking is not a
   global proof of deadlock impossibility. Positively identify the disposable local target
   before reset; no valuable data or unrelated experiments.

Claude is to amend her scope, run probes, implement and test, then return actual changes and
evidence for independent review. Implementation acceptance is **pending**. Commit, deploy and
push authority are unchanged. The eight-minute heartbeat continues.

## Probe and first-draft review — heartbeat around 12:30 UTC

Claude remains running in the same verified session. Codex read `outputs/b37/probe-results.md`
and `probes3.log` in the external exchange directory. Claude reports the unmodified local
function matches the committed capture, wildcard searches return all four non-self fixture
rows, and separator-only queries expose the same empty-token problem the approved guard
addresses. These are local fixture results, not production measurements.

The local probes show PT429 carries error details and produces HTTP 429. The stable RPC's
nested telemetry write fails in the read-only transaction; changing volatility may therefore
enable telemetry on this search path. This remains local evidence only. Default local
transaction settings ignored rollback preferences; the permissive-mode bypass tests are still
required. Implementation acceptance is not implied by the probes.

Codex sent three evidence corrections: an invalid PGRST payload does not prove the mechanism
unsupported (keep working PT429 without further alternative investigation); post-implementation
GET evidence must remain pending until run; a single surviving duplicate header does not prove
the gateway and transaction parser agree, so test both duplicate orders with durable debits.

Codex read the first migration draft and requested replacement of per-call temporary table
DDL with a local token array, plus checking PL/pgSQL `user_id` conflict-target ambiguity through
the real RPC. Claude independently identified the temporary-table overhead and was replacing
it with an array when that review message arrived. No product decision or scope expansion is
needed. Tests and final source review remain pending; no commit or deployment approval.

## Updated implementation/test review — heartbeat around 12:39 UTC

The migration now uses a local token array and a named conflict constraint. Claude's ongoing
local test run found the duplicate-Prefer bypass anticipated in review: one duplicate order
hid rollback from the SQL-visible header while PostgREST honoured it. The revised guard refuses
any Prefer header on this RPC. Codex accepts that narrow correction for local implementation:
the current app sends none. This deliberately restricts direct callers using count preferences,
so the draft claim "nothing legitimate is refused" must be narrowed to current app requests.
The production commit-mode prerequisite still stands. Final raw bypass evidence review is pending.

Codex reviewed the first acceptance script and sent concrete verification corrections:
separate body/status files for concurrent calls; exact success/refusal totals at both limits;
exact six successes/debits after a reset rather than accepting any count from one to six;
counter-write fault coverage; long-window recovery; behavioural entitlement/privacy cases;
by-ID argument `user_ids` and actual definition comparison rather than a function count;
project-specific database-container selection instead of the first matching container; and
restoring prior local transaction settings through a failure-safe trap. Some fixture corrections
were already being made independently by Claude as this review arrived. These are unfinished
verification requirements, not new product choices or reasons to stop independent client work.

## Client review — heartbeat around 12:49 UTC

Claude reports the strengthened server suite at 99 PASS / 0 FAIL; raw final evidence has not
yet been independently reviewed. Codex read the updated suite and client diff. Concurrency now
scores individual statuses; counter-fault and entitlement cases were added. Final schema delta,
client tests and Release verification are underway, not accepted yet.

Focused client corrections sent: require actual HTTP 429 rather than accepting a PT429 code
under any status; trust duration only for the known code/message; reject boolean/fractional
durations; use no-time "try again later" for absent duration; round minutes upward; and add
a real NetworkManager 429 test with one request/zero auth-challenge callbacks instead of
claiming that pure mapping tests demonstrate networking behaviour. Local-only test evidence
must not be called a deployed function. The requested source refinements remain within scope.

Also requested final-newline-only normalisation for the by-ID byte comparison, an explicit
absent-prior-tx-setting check or true restoration, and failure-safe enforcement/fault cleanup.
Claude was told to finish these corrections before final checks to avoid repeated full builds.

## Final independent acceptance — 20 September 2026, around 13:08 UTC

**B-37 local implementation ACCEPTED. UNCOMMITTED, UNPUSHED, UNDEPLOYED.**
Claude completed the bounded corrections, including removing the transport test's unnecessary
bearer-token mutation so it cannot leak fake credentials into later tests. Codex reviewed the
final source and tests, raw server log, Release log, schema capture and actual test result bundle.

**Evidence independently verified:**
- Server acceptance: **99 passed, 0 failed**, including exact concurrency totals (10/10
  accepted/refused at burst; 2/8 with two long-window slots left; six successes/six debits at
  reset), counter-fault refusal/recovery, both window resets, duplicate headers in both orders
  under commit-allow-override, and entitlement/privacy behaviour.
- Client result bundle: **836 passed, 0 failed, 9 skipped; 845 total**. Both B-37 suites passed,
  adding 13 tests to the previous 823 passes. The nine skipped names match the S1/S2b baseline.
  Claude's initial report of 847 cases came from counting the log and is superseded by the
  bundle's top-level summary. The per-device summary counts 839 passes because of parameterised
  runs; it is not the comparable top-level count. No test rerun is warranted for this correction.
- Release log: **BUILD SUCCEEDED**. The test log includes simulator launch diagnostics; the
  completed result bundle nevertheless reports Passed, zero failures and the unchanged skips.
- Independent JSON comparison: only `search_account_directory` changes among functions;
  six budget columns, two constraints and one RLS row are added. The existing catalog exception
  on `account_id_format` remains. Policies, triggers, function/table/column grants and storage
  buckets match the committed capture. The by-ID function remains unchanged.
- Protected invitation documents and `AGENTS.md` retain their original SHA-256 hashes.

Evidence directory:
`/Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/b37/` — `acceptance-final.log`,
`client-final.log`, `client-final.skips.txt`, `release-build.log`, `schema-after-capture/`,
`implementation-results.md`. Actual bundle:
`/Users/samueldixon/Library/Developer/Xcode/DerivedData/MOTIVO-ezwfngloiavjzsgbiehetfqnilcc/Logs/Test/Test-MOTIVO-2026.09.20_14-00-15-+0100.xcresult`.
Codex read a temporary copy using xcresulttool; no tests were re-executed for this review.

**No additional device QA requested for this bounded change.** The UI copy/query-retention
branch was source-reviewed; pure refusal tests and the real NetworkManager transport test cover
the error path. This is not a claim of on-device throttle observation.

**Accepted behaviour:** literal special characters across all matching branches; empty-token
queries cannot browse; ordinary initials, short names and instruments remain searchable;
10 searches per anchored minute and 120 per anchored hour per account; server-derived waits;
ordinary unavailable copy for counter faults; no auth refresh/retry on 429. A search may still
return many legitimate profiles, and deliberate slow/multi-account collection remains possible.

**Next checkpoint is Samuel's.** Claude was told to correct the written test count and stop.
No commit permission was inferred. Selective implementation files are the two changed client
files, two B-37 test files, the new migration and acceptance script. These two new Codex records
(this review and the shared handover) are also available for explicit inclusion; protected files
remain excluded. Production work still requires commit-mode verification, guarded apply,
rehearsed rollback, fresh B-23 parity and independent post-apply evidence. The migration alone
is not an approved production apply package. All six broader sharing/deletion blockers and
the adult-assurance freeze remain unchanged. Pause the eight-minute heartbeat at this checkpoint.

## Resumed after commit and Samuel's reported push

Local HEAD is now **1940ca3**, `Match directory search tokens literally and meter search per
account`. Claude committed the six implementation/test files on Samuel's instruction. Samuel
reports it pushed; Codex has not independently fetched the remote. The two Codex records remain
untracked and the protected files remain outside that commit.

Samuel instructed continuation in the recommended sequence. Codex resumed the existing
eight-minute heartbeat as **Études Phase 6 review with Claude**, and sent the verified Claude
session two bounded tasks:

1. Prepare B-37's concrete deployment checkpoint: guarded apply/rollback, local rehearsal,
   expected delta and read-only fresh production parity/commit-mode preflight using existing
   access. No production apply or live search experiments yet. If commit mode cannot be
   established read-only, describe the gap and minimal verification for review. Production
   apply retains its separate approval gate once the complete package is reviewable.
2. Scope C-97 pending recorder startup: interruption/reset after Record but before first
   frame/writer startup, with writer/session queues, generation ownership and safe cancellation
   that preserves existing takes. Source trace and reproduction plan precede implementation
   approval. No broad deprecation sweep, watchdog, unrelated audio-route changes or age work.

Codex reviews each scope/checkpoint independently and may approve bounded local implementation
under Samuel's standing delegation. Serious product changes remain Samuel's. The six broader
sharing/deletion blockers need a later disposition review, not an automatically authorised new
protocol. Existing device passes and the drone waiver remain intact. No automatic commits/push.

### Deployment preparation review — heartbeat around 14:01 UTC

Claude reports fresh read-only production parity and local apply/rollback rehearsal, including
rollback restoring B-23 GATE MET; final artifacts/evidence review remains pending. Codex read
the two new guarded SQL files in `supabase/sql/`. Production apply is not authorised yet.

Codex challenged the proposed non-mutating commit-mode discriminator: absence of a
`Preference-Applied: tx=rollback` response header may also occur under unconditional rollback
when overrides are disabled. A missing role-level setting does not establish hosted process
configuration. Claude was asked to test the read-only signal against all four local transaction
modes and not promote ambiguous absence into proof. If commit and unconditional rollback
cannot be distinguished, record the gap and propose a minimal separately approved verification.
This does not block independent C-97 scoping. Rollback documentation must also state that it
discards all current account counters and restores the previous unmetered/wildcard behaviour,
not merely that it costs one member's allowance window.

### Deployment and C-97 scope review — heartbeat around 14:11 UTC

Read the completed deployment runbook and Claude's pending-start scope. The four-mode local
matrix confirms the header discriminator is insufficient. Historical persisted production
writes establish historical durability, not today's process setting. Asked Claude to withdraw
the present-tense exclusion of both rollback modes and propose a minimal concrete verification;
no production request or mutation authorised. `commit-allow-override` is not itself a blocker:
the any-Prefer guard addresses overrides. Default durability is the unresolved property.

C-97 scope is NOT approved for implementation yet. Source shows pending UI state can span writer
creation, cadence gating, off-queue startSession and deferred main-thread transition, not merely
tap to first frame. Requested complete callback/identity audit and deterministic ordering plan.
A lock around a token does not by itself close check-then-act; a queue-owned cancellation needs
to handle startup winning and safe finalisation, not merely clear the token. Ten device taps or
failure to reproduce cannot establish unreachability. No device timing prerequisite approved;
eventual ordinary start/record/save device regression remains a genuine gate. File preservation
claims need coverage of the real file-effect path, not just pure decision outputs. Claude is
revising the scope and deployment verification proposal; existing device passes and waiver stand.

### C-97 scope v2 accepted for bounded implementation — Samuel: “shes ready”

Read `claude-opus5-c97-pending-start-scope-v2.md` and independently checked the off-queue
startSession/continuation source. Approved Claude to implement locally, incorporating these
acceptance requirements without another scope-only round:

- If startup commits before its main transition, carry the disruption event through the matching
  main transition and stop. Existing tracker handling alone is insufficient: its original
  startPending branch has not set takeDisrupted/tearDownAfterFinish. Verify eventual teardown
  and kept/error messaging in the actual orchestration.
- A stale startSession continuation must suppress shared/UI mutations AND perform exactly-once
  cleanup of its retired claim's captured writer/output after the blocking call returns. Never
  touch a newer claim; test disappear/reopen during the blocking call.
- Bind immutable output URL to claim ownership; prove it cannot alias a reviewed/newer take.
  Do not choose a deletion target by re-reading mutable recordingURL.
- Reconcile necessary start-path queue ownership (main currently resets writer/inputs); do not
  rely on the old unsynchronised flag for cancellation correctness. No unrelated refactoring.
- Include start/writer failure, repeat cancellation, deterministic ordering and wired real-file
  tests, then relevant builds/regressions. Independent review before commit/device QA.

B-37 revised runbook now correctly leaves current default durability unresolved. Preferred
eventual verification is an ordinary authorised app write plus independent fresh before/after
read, verifying the client sends no Prefer header. No production request/deploy/probe authorised.
Scratch-table alternative is conceptual only; any future concrete proposal must exercise
PostgREST and verify persistence in a separate transaction. This does not block C-97 work.

### In-progress implementation review — 14:27 UTC heartbeat

Claude is implementing and reports a clean build and 18 focused tests passing; not independently
scored yet. Reviewed draft coordinator, file effects, tracker and controller diff. Sent concrete
integration corrections while work continues (not a final rejection of unfinished work):

- A pre-arm queued frame can see main's armed flag before the queue-owned claim exists, clear
  the flag and strand startup. Samples must use queue-owned claim authority without stale
  no-claim callbacks resetting the UI.
- S5 main transition lacks identity validation, and deferred cancellation completion omitted
  generation. Bind every completion to the matching main-owned start/presentation; cancellation
  must name its originating claim rather than whichever claim is current when dequeued.
- Existing onDisappear still cancels shared writer/deletes mutable recordingURL while the
  retired claim's startSession may be in flight. Reconcile this competing teardown path.
- Setup failure while stage is armed returns no cleanup URL, despite possible partial setup.
- Full UUID requested for filenames; also recordingURL reuse means filename uniqueness alone
  does not prove distinct claim ownership. Cover cancellation/retry/reopen.

Claude continues implementation/test revision. Production unchanged; no commit/device checkpoint.

### In-progress review — 14:36 UTC heartbeat

Claude has added controller wiring tests and is fixing a test-exposed abandoned-claim file leak;
final results not yet available. Revisions add main start identity, claim-based pre-arm handling,
retired-continuation ownership and full UUID filenames. Further concrete sequence sent: disappear
with startSession blocked, delayed main cleanup, immediate reopen invalidating that cleanup,
then new Record can reuse the still-nonnil old recordingURL. A retired continuation could delete
the newer output. Requested synchronous ownership detachment at the lifecycle boundary or fresh
per-start URL and a deterministic rapid-reopen test. Also flagged unguarded setup-failure main
callback and S5 identity validation allowing missing token/presentation. Claude continues; no
additional owner decision or repeated baseline tests requested.

### Test-evidence review — 14:45 UTC heartbeat

Claude reports three focused suites green; full suite/Release running. Rapid-reopen now detaches
pending URL synchronously. Approval still pending: wiring tests inspected do not yet establish
some of their titles' claims. Startup-won test leaves state idle so stopRecording no-ops; pre-arm
test queries model disposition then drains without invoking a frame path; real-file tests
manually connect model output to effects rather than exercise controller cancellation. Requested
matching production completion/frame seams and real controller file-effects coverage, including
retired continuation. No broad capture harness or hardware-timing claim requested. Keep working;
no commit/device checkpoint yet.

### Startup liveness review — 14:54 UTC heartbeat

Controller/default-file-effect tests now cover real cancellation and retired cleanup. Claude
reports 11 wiring tests passing; serial full verification underway after concurrent DerivedData
build collision (not yet independently scored). New concrete defect sent: retired sessionStarting
leaves isStartingWriterSession true, new arm does not reset it, and retired return deliberately
cannot change shared state. New start can remain blocked forever at the video guard. Requested
per-claim pipeline reset, old-retired/new-start progression test and narrow pending-buffer/audio
ownership check. Also nil-token continuation must refuse shared mutation, not return true.
No final acceptance, commit or device QA yet.

### Samuel confirms continuing recorder coordination

After discussing future R0 role allocation, Samuel explicitly asked to resume current recorder
work with Claude. Latest code resets per-start pipeline state and refuses nil-token returns;
new wiring tests exercise the real arm path and stale-return isolation. Asked Claude to finish
serial verification and hold a stable checkpoint for independent review, with exact totals,
skips, builds and limits. Resetting new-claim flags does not cure a permanently blocked old call
on serial sessionStartQueue; no watchdog or new recovery guarantee is authorised. Current roles
and eight-minute check-ins continue. No age implementation, commit, deploy or device action.

### 15:20 UTC heartbeat — final verification still running

Claude reports wiring suite green and serial Release/full verification underway; final evidence
not delivered yet. `git diff --check` clean. Requested log/xcresult paths, exact tested source,
totals/skip comparison and a stable handover. If stalled, inspect last completed test/process
before rerunning; no duplicate builds requested. No acceptance/commit/device/deploy yet.

### Stable C-97 checkpoint independently accepted for device gate

Samuel reported Claude ready. Read c97/CHECKPOINT.md and independently queried final xcresult
Test-MOTIVO-2026.09.20_16-13-20-+0100: **868 passed, 0 failed, 9 skipped, 877 total**.
Device count 871 includes parameterized expansion. Raw TEST SUCCEEDED and Release BUILD SUCCEEDED
verified; skip method-name sets match B-37 baseline. Four new files match saved copies exactly;
tracked diff matches checkpoint before its appended new-file manifest. Protected hashes unchanged
and diff --check clean. Code review accepts bounded cancellation implementation for device QA,
not a claim of solving all recorder races or permanently blocked AVFoundation calls.

Claude told hold stable. Next owner step: on current build record/stop/preview/save, close/reopen
recorder and repeat, verifying earlier saved take survives. No forced reset timing or waived
drone diagnostic. No commit yet. Scheduled polling paused at this owner-dependent gate; resume
on result. B-37 production remains undeployed and separately gated.

### Device QA passed — recorder commit authorised

Samuel asked video or audio; instructed video including speech/clap, checking picture and sound.
Samuel then reported **“QA all green”** for the requested record/stop/preview/save and
close/reopen/repeat sequence, with saved recordings preserved. Accepted as user-reported QA,
not independently observed hardware evidence. No install time/source attestation supplied;
the static 1.0 (131) version cannot prove identity and is not cited as doing so.

Bounded pending-start unit accepted with the recorded residuals. Claude authorised to commit
the seven reviewed source/test files plus concise relevant acceptance/audit documentation,
explicit staging only, no code changes after review. Exclude protected files, Codex documents
and all B-37 deployment artifacts. No push/deploy. Commit verification pending; Samuel pushes.

Commit independently verified: **25d032e**, nine paths (seven reviewed source/tests plus
audit-findings and Phase 6 client-cleanup checkpoint). All committed source/tests match the
reviewed checkpoint exactly. Remaining worktree contains only protected/untracked carried files
and B-37 deployment package. Not pushed by Codex/Claude. Recorder sub-gap accepted; broader
C-97 and Phase 6 remain open. Polling stays paused at completed checkpoint pending next direction.

### B-37 deployment preparation resumed after recorder push

Samuel reports 25d032e pushed and says proceed with Claude. Sent Claude fresh read-only parity
into scratch, apply/rollback consistency review and final deployment checkpoint preparation.
Current default PostgREST durability remains the sole verification gap; requested a baseline
for an existing QA account's ordinary display-name update, checking the client sends no Prefer
header. Asked Samuel which device/account/display name, leaving it unchanged until baseline is
captured. No live probe, new credentials or production apply authorised; separate reviewed apply
approval remains. Recorder work closed at its bounded checkpoint; no further recorder edits.

Samuel identifies Device A, Connected profile **Ben Craft**, open and attached to Mac. Name
left unchanged pending baseline. Claude capturing identity/name/privacy baseline. Display-name
upsert does send Prefer resolution=merge-duplicates,return=minimal, so earlier “no Prefer”
criterion was overly strict: relevant property is no transaction override. Claude measuring this
exact header locally across transaction modes. Device A appears to be the protected opt-out
identity; clarified that exclusion protects discovery evidence, not all ordinary profile fields.
Require unchanged account_privacy lookup values/timestamp and no trigger side effect, then name
change can proceed. No device change requested yet; baseline/local verification still underway.

### Device A baseline captured; ordinary name update requested

Claude confirms fresh ten-surface production parity, apply/rollback consistency, local rehearsal.
Device A identity 6fd0a833 corroborated by established tester transaction record, name Ben Craft,
account_id devicearlease. IMPORTANT clarification of earlier shorthand: protected directory
lookup_enabled is FALSE; authoritative account_privacy.lookup_enabled is TRUE, with
lookup_changed_at 2026-09-10 06:02:41.524643+00. Preserve both, not a presumed privacy-table false.
Exact ordinary upsert header measured locally in all four modes: persists only in commit modes;
privacy row unchanged, directory false preserved, no privacy-writing trigger. Entitlement trigger
may recompute entitled_until as normal; not a privacy mutation. No directory updated_at exists.
Requested durable baseline/time/matrix record. Samuel now asked Ben Craft -> Ben Craft QA1,
save and leave until independent read. No production apply authorised.

### Ordinary profile write FAILED — durability gate remains unresolved

Samuel first reported saved, then a red “couldn't update your profile…please try again” message,
with the edited name surviving local navigation. Claude's independent server read still shows
Ben Craft and no row with the new name. This is NOT a durability pass and NOT evidence of default
rollback: request failure must be diagnosed first. Local persistence cannot establish remote
success. Asked Claude to trace request error/attached existing logs, current policy/membership
read-only, with no retries, config flips, credential/session reset, deploy or unreviewed changes.
Source confirms generic DirectorySyncFailure copy and profile upsert; deployed baseline has
INSERT membership gate but owner UPDATE carve-out, a candidate distinction to investigate,
not yet a measured diagnosis. All privacy evidence remains protected.

### Diagnosis review — Sandbox renewal proposal rejected

Claude measured enforcement true, connected_member false, membership_state sandbox_only,
server name unchanged and privacy values unchanged. Proposed expired Sandbox subscription as
cause and resubscription as remedy. Codex rejected that inference: connected_member explicitly
requires environment Production; renewing Sandbox cannot make this predicate true. No device
request-level error exists. INSERT policy vs ungated owner UPDATE is a structurally supported
explanation, not captured HTTP proof, and expiry is not its causal distinction.

Asked Claude to verify live predicate and locally reproduce active/expired Sandbox upsert vs
PATCH, correct narrative, check existing findings for duplication, and propose a concrete safe
durability alternative. No resubscribe/retry, production mutation or profile fix authorised.
Do not change Device A's protected privacy timestamp. B-37 deployment remains held.

### CORRECTION TO CODEX'S DIAGNOSIS REVIEW — current scope011 supersedes old migration

The preceding claim that Sandbox renewal cannot change connected_member was WRONG. Codex read
20260902120000 without checking subsequent changes. Claude challenged it with live predicate
bytes; Codex independently confirmed migration 20260915160000 and canonical functions.json:
connected_member accepts Production AND Sandbox, excludes revoked status, and requires future
renewal or eligible grace. membership_state still reports sandbox_only independently of the
effective eligibility predicate. That label cannot decide entitlement.

Claude's local exact-client reproduction: active Sandbox upsert 200/persists; expired Sandbox
403/42501; expired owner PATCH 204/persists. Supports membership-gated INSERT explanation;
Device A request-level error remains uncaptured. Existing C-70 covers this mismatch, no duplicate
needed. Authorised docs-only reproduction addendum, no client fix. Codex acknowledged its error
to Samuel. Next: Samuel renews existing Device A Sandbox subscription; independent read must
confirm connected_member true before another profile edit. No production override/apply.

Samuel reports renewed. Claude independently observes 2026-09-20 16:10:18.944347+00:
connected_member TRUE, Sandbox/status1, renewal_date 16:39:33 UTC, ended_at null. All protected
privacy values unchanged. Server display_name now Ben Craft QA1 (was Ben Craft at 15:53), proving
a persisted change in that interval; retry mechanism/time not observed. To restore profile and
bracket a fresh write, requested QA1 -> original Ben Craft and saved report, replacing Claude's
unnecessary QA2 suggestion. Independent read next, then final deployment approval checkpoint.

### Final B-37 production approval checkpoint ready

Samuel reports restoration done. Independent Claude reads bracket QA1 at 16:11:27.924973 UTC
and original Ben Craft at 16:12:54.889440 UTC, connected_member true both ends. All protected
privacy values, account_id/location/avatar_version unchanged. Current default durability gate
met at that observation, not a permanent configuration guarantee; profile restored.

Codex verified artifact SHA256: apply 2b5fa03573be1cafee34e4c6aab6afcac028be991547c707869d6e29c800bc1a;
rollback 112467221dd787908feb730b45eaabfa21238e2966ca25d611a4485c25d6ba7a.
Apply/rollback guards reviewed. Expected one function replaced and private budget table added;
no content/identity/privacy change. Local 99 server checks, prior client tests, parity and
rollback rehearsal stand. Rollback removes all counters and restores unmetered wildcard search.
Await Samuel's explicit production apply approval, then independent row/schema/B-23 verification.

### Production apply explicitly authorised

Samuel: **“approved. deploy”**. Sent Claude authority for the exact apply SHA above, established
production target, existing access, fresh PRE check, single submission, raw verification row
and independent post-capture/delta/B-23 review. On ambiguity read state, never repeat blindly.
No synthetic live search, member-content changes, config flips, repair-forward, push or commit.
Postcondition failure requires state report and reviewed rollback decision. Deployment in progress.

### B-37 DEPLOYED AND INDEPENDENTLY VERIFIED — 2026-09-20 16:24 UTC

Apply landed 16:24:00.874241 UTC with exact expected md5. Initial CLI positional-text submission
was rejected by argument parser, then production independently read unchanged before --file
submission. No blind duplicate apply. Codex read raw response, independent post-read JSON at
16:27:04, and B-23 report: expected VOLATILE/plpgsql, table present/RLS on, 0 policies/client
grants, authenticated-only execute, 23 public policies/42 functions. GATE MET with standing
account_id_format serialization exception. Compared post-apply production captures to HEAD:
+6 columns/+2 constraints/+1 RLS/one function replacement; six other surfaces identical. All ten
captures match recaptured canonical. Privacy/name restored baseline unchanged per final read.

No synthetic production searches run; zero durable counter/search telemetry rows observed.
Production rate-limit behaviour not exercised live; tested local function is byte-identical to
deployment. Accepted structural deployment with those limits. Asked Claude finish current-state
headings/audit record, preserving dated history, then hold deployment/schema/docs uncommitted.
No push. Deployment objective complete; final documentation checkpoint remains to be committed.

Samuel will instruct Claude to commit and will push himself. Scheduled check-ins paused at this
accepted checkpoint; no additional changes or deployment actions requested.

### Next unit authorised: bounded C-70 profile-sync scope

Samuel agrees proposed next C-70 fix, reports 79fe153 pushed, asks proceed with Claude under
guardrails and asks whether window remains usable. Claude UI shows 703k/1M (~70%); current
window suitable for bounded scope with durable handover and attention to limits. No fresh window
required yet. Requested scope before implementation: complete existing-account edit/initial
creation/generation/hydration/error lifecycle, preserve gated creation and ungated owner updates,
no membership/age-policy change. Explicit cases: empty PATCH response, missing row, account-ID
uniqueness, identity switch/stale completion, ambiguity/retry, truthful local-vs-remote state.
No production writes, code before reviewed scope, commit/push or device action. Independent
read confirms current source always upserts, including auto-generation. Read latest scope011,
not superseded migration, for server authority. Protected files unchanged.

### C-70 scope review / Claude fresh-window transition

Scope reviewed; no code approved yet. D-U6-3 already authorises lapsed self-profile maintenance,
so proposed product question is redundant. Preserve existing missing-only hydration. Detailed
corrections saved in docs/c70-codex-scope-review-2026-09-20.md and delivered to Claude for the
handover Samuel requested directly in Claude UI. Claude handover path:
docs/phase-6-c70-fresh-window-handover-2026-09-20.md. Await correction incorporation; original
version may still list resolved product questions. Samuel confirms moving Claude to fresh window.
Polling paused so it does not keep addressing old task. Resume with verified NEW Claude task
URL once user says ready. C-70 is client-only proposed work, no production deployment proposed.

Samuel pasted handover into fresh Claude and requested ~2 minutes before check-in. Waited,
verified fresh task **B-37 production deployment handover**, URL
claude.ai/epitaxy/local_06010a5d-1f5a-48ec-8f74-3d2e81195e87, context ~174k. Corrected handover read;
Claude designing exact transport protocol, no code. Confirmed review boundaries and asked to
trace INSERT-only band trigger against existing-row/Q6 contract, not invent new age policy.
Claude observed trigger itself short-circuits existing rows. Eight-minute check-ins retargeted
to fresh task; old task no longer coordination target.

### C-70 protocol R2 reviewed; local implementation authorised — 20 September ~17:09 UTC

First protocol returned for concrete ordering/identity/evidence corrections. R2 read
in full, existing boundRequest independently checked; bounded local implementation
and tests now authorised with conditions in docs/c70-codex-scope-review-2026-09-20.md.
Preserve local-save timing and use generic Connected-confirmation wording. Explicitly
carry timeout/cancellation server-ordering residual, guard actual effects and identity
epochs, prevent coalescing from losing unlike edits, compare strict receipt evidence.
Claude is implementing; no commit/push/device/production action. Eight-minute heartbeat
remains active against the fresh Claude task. Next checkpoint is actual diff/tests.

### C-70 local implementation accepted after independent controlled validation

Full review returned multiple stale-result/caller/cache corrections, all recorded
in docs/c70-codex-scope-review-2026-09-20.md. Controlled preserved xcresult now
independently verified Passed / zero failures / same nine skips; Release success
verified. Earlier full-run transient remains unexplained, not erased by later pass.
Protected hashes unchanged. Claude preparing durable audit records and concrete
Device A QA/build checkpoint. No device install/launch, commit/push or production
policy/schema change authorised; device QA remains pending, C-70 not fully closed.

### C-70 bounded device checks accepted — 20 September 19:14 UTC

Samuel renewed Sandbox himself and ran existing Device A account. C70-1:
Ben Craft C70 persisted, no warning; independent POST1 read confirmed server name.
C70-2: temporary edit then Ben Craft, persisted/no warnings; independent POST2
19:14:54.742106UTC confirms Ben Craft and protected privacy unchanged. Unit accepted
within these limits. C70-3 natural-lapse path remains inaccessible because existing
Solo mode guard prevents profile sync; carried, not called closed. Claude finishing
audit/QA checkpoint; no commit/push authorised. Monitoring paused for Samuel.

### dec0236 pushed; fresh-window handovers prepared

Samuel reports C-70 pushed. HEAD and locally recorded origin/feature/solo-connected
both verified dec0236a30a7de6af9d59a6c3a1962994fff1f36. Implementation/docs committed;
pre-existing protected/untracked records remain. Next authorised unit: scope and
prove remaining Lists import/save scaffolding and C-12 alert/helper unreachable,
Codex review before removal, then Phase 6 explicit disposition review.

New self-contained handovers:
- docs/phase-6-cleanup-codex-handover-2026-09-20.md
- docs/phase-6-cleanup-claude-handover-2026-09-20.md

Both incorporate Samuel's relayed Claude warning: reachability must survive
indirection, not absence of grep references; mutation checks need a predicted
behavioural falsifier, not a generic requirement that dead-code removal fail tests.
Fresh observation: C-12 helper has an actual lexical caller in an alert; establish
the alert state's reachability, never claim zero callers. No cleanup code changed.
Heartbeat remains PAUSED; new Codex must verify NEW Claude task and retarget before
resuming. Old Claude task must not receive automated work after transition.
