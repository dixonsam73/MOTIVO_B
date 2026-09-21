> **HISTORICAL — ARCHIVED 21 September 2026. NOT CURRENT WORK.**
>
> Fresh-window handover for Phase 6 / B-37, telling the next windows to refresh their baseline before working.
>
> Three windows of work have landed since: `b479487` (handle removal and the fresh-join fixes), `1a4c09f` (the recorder route diagnostic) and `15af5c9` (roadmap). Refresh from `origin/feature/solo-connected`, not from this document.
>
> **Any instruction, scope, baseline, cadence or "next step" below is spent.** For the
> current position see `docs/account-id-removal-evidence-2026-09-20.md`, `docs/fresh-join-f3-evidence-2026-09-21.md`, `docs/recorder-r1-evidence-2026-09-21.md` and `docs/release-priority-review-2026-09-21.md`, and take the repository state from
> `origin/feature/solo-connected` rather than from any commit named here.
>
> The text is preserved unchanged; only this banner was added.

# Études — shared fresh-window handover: Phase 6 / B-37

Prepared by Codex on 20 September 2026 for the next Codex and Claude windows.
This records Samuel's instructions and the reviewed checkpoint. Refresh the baseline before
working: Claude is doing separately authorised housekeeping before the window transition.

## 1. Start here: authority and next action

Samuel approved the following B-37 direction:

1. Correct search wildcard handling so special characters do not turn an ordinary query into
   an unintended broad browse.
2. Add a server-enforced per-account search budget, considering both bursts and sustained
   searching. Normal searching should remain easy; excessive searching should receive a clear,
   temporary refusal rather than misleading empty results.
3. Preserve useful name/instrument discovery and current profile information. Choose limits
   from normal usage and testing, not an arbitrary restrictive quota.

His implementation instruction was:

> Have Claude scope it out, you approve the scope in line with our current workflow and in
> context of the app, have Claude implement and test it, you approve that, and then report to
> me (and let me know if any on device QA required).

**This approval supersedes the older proposal's statement that B-37 is awaiting a decision
whether to proceed.** Scope, implementation and testing are authorised. No B-37 code has yet
been written. Exact limits and failure behaviour have not yet been settled.

**Current pause:** Samuel is moving Claude to a fresh window after housekeeping and said he
will say when she is ready. Do not send new work to the old Claude session or start a competing
implementation. When he signals readiness, first establish the fresh baseline and ask the new
Claude window for a bounded implementation scope; Codex reviews that before coding begins.

## 2. Division of responsibilities and guardrails

- **Claude scopes, codes, tests and makes approved commits. Codex independently reviews and
  coordinates. Samuel pushes.** Samuel explicitly corrected Codex when Codex attempted to stage
  the last checkpoint: committing is Claude's job. That attempt failed; Claude subsequently
  made the actual commit.
- Do not spawn a replacement agent and call it Claude. Coordinate with Samuel's real Claude
  session, using the app UI when available. Identify the new session rather than reusing a
  stale window/session identifier. Samuel has not asked this window to create new tasks.
- Proceed autonomously within the approved bounded scope. Surface significant product choices
  unless Samuel's intended behaviour is already established. Do not repeatedly request approval
  for ordinary implementation choices. Do not make the owner design a rate-limiter unaided:
  bring a concrete recommendation and explain any meaningful usability trade-off.
- Commit approval remains checkpoint-specific. B-37 implementation approval is not permission
  to deploy production SQL, push, or commit everything in the shared tree. Present the reviewed
  checkpoint for the normal commit/deployment steps; Claude commits, Samuel pushes.
- No production data experiments or destructive cleanup. A historical statement that beta
  data is expendable is not an instruction to delete it. Device B contains valuable long-term
  data; use disposable synthetic fixtures and the positively identified local backend.
- Keep it proportionate: “one musician with a couple of AI in Hertfordshire, not NASA.” No
  speculative platform, new proxy/Redis service, or unrelated cleanup. Run appropriate checks
  once; repeat only for changes, failures or a concrete unresolved concern. Do not rebuild
  Debug and Release merely because two comment lines moved.
- **Adult-assurance implementation is frozen.** Solo remains local/account-free. The target
  direction is globally 18+ Connected, failing closed until adequate Apple-provided assurance
  is established. Apple/HEAA/server-trust questions remain unresolved. Do not implement that
  architecture, assume `.confirmed` is sufficient, or remove existing teen protections here.
- No active overnight automation is authorised by this handover. The old eight-minute
  heartbeat was paused; do not silently restart it.

## 3. Baseline at handover preparation

- Repository: `/Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO`
- Branch: `feature/solo-connected`
- HEAD: `4ac01c9a6ae46e810d34500bd405007bfde12c9f`
- Commit: **Bind journal deletion to its owner and reject superseded publishes before send**
- Samuel explicitly reported this commit **pushed**. No fresh remote fetch was performed for
  this handover; do not present a user report as independently measured remote state.
- “MOTIVO” remains the project/scheme/source-directory name; the product is Études. Renaming
  folders is not this scope.

Pre-existing unrelated changes, excluded from the last commit:

| File | State | SHA-256 before housekeeping |
|---|---|---|
| `docs/connected-invitations-direction.md` | Modified | `90f60494f42ec2500254b6a7aa6384ee670ffa49fd5b678fb26191eeb27885c0` |
| `docs/private-connection-invitations-scope-2026-09-17.md` | Modified | `c470d4a18c79cff102b01b472f7d06ddb4079fdbcffc998f11e260882236223d` |
| `AGENTS.md` | Untracked | `f948387812c8e6b8a002e4baf84cce472430c954677bed8577e5d9b2f1cbaaaa` |

Do not overwrite, stage or discard these by assumption. Housekeeping may intentionally change
them or HEAD; inspect Samuel/Claude's resulting record first. This handover itself is newly
created and uncommitted.

## 4. What the last checkpoint completed

**S1:** journal backend deletion now binds every request/refresh/retry to the initiating
identity, applies owner filters, validates the deletion result, and checks identity generation
again before local/queue mutation. A never-shared entry can still delete normally. Existing
queue recovery remains reachable. A→B→A and reset cases are covered.

**S2b:** a queued publish checks whether its intent is still current after attachment
preparation, immediately before entering the first transport call. Superseded work sends
nothing. Once admitted, the existing phases continue; it does not abort halfway through an
object upload and leave the later reference write undone.

- Final full suite: **823 passed, 0 failed, 9 unchanged skips (832 total)**.
- Final Release build: **BUILD SUCCEEDED**. Codex read the result bundle and build log.
- Seventeen new tests: eleven S1, six S2b. The held-upload fixture scores request ordering:
  object upload → references → object deletion → row deletion. This is not proof of physical
  byte deletion. Temporary cleanup on pre-send refusal was source-reviewed through the
  existing `defer`, not newly exercised with a derived temporary file.
- No additional device QA was requested for these safeguards.
- The final comment-only tidy changed no executable code. An unnecessary extra build was
  stopped; it is not a missing verification gate.

Durable acceptance: `docs/phase-6-client-cleanup-checkpoint-2026-09-19.md`, final S1/S2b section.
The test bundles/logs are temporary local artifacts; their paths are recorded there.

## 5. B-37: verified source facts and honest limits

Read the current committed schema capture and code, not just historical narrative:

- `supabase/schema/functions.json` and `supabase/schema/policies.json`
- `supabase/migrations/20260906120000_cp1_cp2_account_privacy.sql`
- `supabase/migrations/20260905130000_u7_c58_follow_scoped_attribution.sql`
- `MOTIVO/AccountDirectoryService.swift`, `MOTIVO/PeopleView.swift`

Search currently matches account-name prefixes, display-name substrings and instruments. It
returns at most 20 rows per query, with no pagination argument. Location is returned, **not
searched**. There is a two-character floor; do not raise it casually because genuine short
names must remain searchable. Existing discovery privacy and membership checks must survive.

Search tokens enter SQL `LIKE` patterns without escaping `%` and `_`. The broad-match shortcut
is source-established, not newly exercised against real members. Confirm the behaviour and
literal-character fix locally, including the escape character and every matching branch.
Do not describe this as SQL injection or a bypass of row/privacy restrictions.

The historical U5 investigation simulated repeated searches and reached all 17 then-recorded
directory rows. That is evidence of enumeration in that small historical sample, **not** a
current census, live bot attack, or performance estimate for a large directory. Codex's earlier
“not demonstrated” phrasing was too broad and was corrected.

Any member can copy information legitimately returned to them. A search budget limits speed
and volume; it cannot prevent slow collection, use of multiple accounts, or reuse of already
collected data. A single ordinary search can itself return many profiles in a small community.
The 20-result cap is not an anti-enumeration guarantee.

`get_account_directory_by_user_ids` resolves known UUIDs and intentionally ignores discovery
opt-out for attribution. Its membership/follow carve-outs are load-bearing (C-58/G10).
Do not add the discovery filter or an arbitrary array cap that breaks existing unchunked
client requests. The reviewed feed path requires approved follows for other members' posts;
the follow table does not expose a stranger's whole graph. These observations bound the
proposal; they are not a universal proof that UUIDs cannot be obtained elsewhere.

**Rejected suggestion:** removing location only from search results. The unmetered by-ID
lookup can return it immediately for those UUIDs, so this adds complexity with little
protection. Samuel approved preserving current profile information, not a new visibility model.

Do not claim every current beta requester necessarily paid anew: the paid Connected product
model is not evidence excluding test arrangements, exceptions or enforcement-switch states.

## 6. Scope-review checklist for the fresh pair

Preferred candidate: a narrow atomic per-account budget inside the protected search RPC,
using server-established identity and private counter state. No new infrastructure tier.
Supabase documents database-side rate limiting:
https://supabase.com/docs/guides/api/securing-your-api

- The old claim that SQL cannot express rate limiting is wrong. Do not repeat it.
- Do not reuse the membership telemetry counter as enforcement: its writes deliberately
  swallow failures. Keep search budgeting separate from membership/age authority.
- Cover concurrent requests, direct API calls, alternate HTTP methods, any executable helper
  route and counter errors. Current client POST use alone is not proof of no bypass.
- A budget is server-enforced, not a client button delay. Counter state must not be writable
  by the member. A changing client token or supplied account ID must not reset the allowance.
- Scope state retention/cleanup and failure behaviour. An exception can roll back database
  writes; account for transaction semantics rather than assuming every attempt is counted.
- Preserve ordinary name/instrument matching, opt-out and membership checks, attribution,
  private content boundaries and existing API response compatibility where practical.
- Recommend reasonable burst and longer-window values with an explicit rationale. Beta usage
  may be too sparse to establish normal launch behaviour; do not claim the telemetry proves
  an optimal number. Escalate a significant usability/failure-policy decision to Samuel.
- The app should distinguish throttling from “No results” and recover without losing the
  search or signing the member out. Keep ordinary users' experience simple.
- Tests should demonstrate limits cannot be raced/bypassed and reset/recovery works, alongside
  legitimate short-name/instrument/literal-character search and existing access rules.
- Separate local implementation approval from production apply approval. Use the established
  guarded SQL, rollback, fresh-parity/B-23 and independent post-apply verification workflow
  for any eventual deployment. Never score a deploy solely on its exit code or success text.

Claude's read-only proposal, with Codex corrections accepted:
`/Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/claude-opus5-b37-proposal.md`.
Its final “pending Samuel's decision” wording predates the approval quoted above. The approved
direction here controls; it does not settle every implementation detail.

## 7. Remaining non-age Phase 6 work after B-37

Do not promise a fixed number of rounds or declare Phase 6 nearly closed solely from test counts.

1. **Six broader sharing/deletion concerns remain OPEN:** in-flight upload versus withdrawal
   and physical bytes; lifecycle cleanup ownership/epochs; deletion of referenced files;
   mutable content/reused paths; fresh consent after cleanup/stale devices; refusals consuming
   newer work. Some are requirements for an unbuilt protocol, not observed production bugs.
   S1/S2b do not close them. Broad prefix sweeps and all-phase revision cancellation were
   rejected because they can delete newer legitimate files or orphan uploads before refs land.
2. **Bounded reliability assessment/disposition:** C-97 recorder edge cases (including pending
   start and unusual disruptions); F-6 delivery reconciliation (no validated blanket client
   cleanup); possible forced-purchase attestation joining an older run, still an unverified
   candidate. Do not promote a candidate to a confirmed defect without evidence.
3. **Smaller findings and optional cleanup:** C-15 PDF page-selection metadata residue; C-22
   AVFoundation deprecations; remaining unreachable code; three dead membership-control
   columns requiring separate production DDL authority; F-10–F-12 record drift. These need
   proportionate fix/defer decisions, not automatic expansion into mandatory implementation.
4. **Exit review and records:** reconcile stale historical status paragraphs, give every
   carried item an explicit disposition, and retain limits of provider evidence. Supabase
   ticket **SU-478356** may never receive a substantive response; do not wait indefinitely
   or turn public-source review into proof of hosted physical-byte behaviour.

Already accepted / do not re-request casually:
- Lists/defaults device QA green; defaults are explicitly chosen per instrument/activity,
  never automatically transferred to a new instrument.
- Connected and Solo journal swipe-delete QA green, including relaunch and other entries
  remaining intact.
- CM-15/Bluetooth/drone checks and the recorded video-reset checks retain their stated passes
  and limits. Samuel explicitly waived the extra drone unplug diagnostic; it is not outstanding
  device QA. Do not silently label unmeasured exceptional paths green.
- F-3 media profiling is **partially measured**, not closed: Device A Release trace measured
  SessionDetailView asset CPU work, not per-open wall-clock stalls or staging-write costs.
  It did not justify an immediate fix; no further capture was requested.
- B-38 avatar-version guard is deployed and recorded; do not propose it again as pending.

Primary status record: `docs/phase-6-client-cleanup-checkpoint-2026-09-19.md`. Earlier sections
and `docs/phase-6-overnight-checkpoint-2026-09-19.md` are chronological history: later acceptance
supersedes earlier “uncommitted / needs device QA” statements. The adult-only direction is in
`docs/adult-only-connected-rescope-2026-09-18.md`; its implementation remains outside this work.

## 8. First actions in the fresh windows

1. Read this handover and the applicable repository instructions. Inspect current branch,
   HEAD and worktree; reconcile Claude's housekeeping with the baseline above.
2. Wait for Samuel to identify the fresh Claude window as ready. Do not interrupt housekeeping.
3. Claude writes the bounded B-37 scope, proposed allowance/failure behaviour and test plan.
   Codex reviews source and scope independently, with the app's ordinary search use in mind.
4. Once scope is accepted, Claude implements/tests; Codex reviews actual changes and evidence,
   sends focused corrections as needed, and reports outcome and any genuinely needed device QA.
5. Stop at a documented, reviewable checkpoint for the normal commit/deploy approvals. No push.
