> **HISTORICAL — ARCHIVED 21 September 2026. NOT CURRENT WORK.**
>
> Independent review of the bounded Phase 6 cleanup. Its header already notes the cleanup committed as `e5b3b08`.
>
> The workstream it names as next — C-70 lapsed-owner maintenance and local name-save reliability — is done and committed inside `b479487`.
>
> **Any instruction, scope, baseline, cadence or "next step" below is spent.** For the
> current position see `docs/account-id-removal-evidence-2026-09-20.md`, `docs/fresh-join-f3-evidence-2026-09-21.md`, `docs/recorder-r1-evidence-2026-09-21.md` and `docs/release-priority-review-2026-09-21.md`, and take the repository state from
> `origin/feature/solo-connected` rather than from any commit named here.
>
> The text is preserved unchanged; only this banner was added.

# Phase 6 bounded cleanup — independent Codex review

**Current status:** accepted cleanup committed as `e5b3b08`; Samuel reports pushed.
HEAD and locally recorded origin independently match; no fetch. The dated
uncommitted checkpoints below are history. Next selected workstream is remaining
C-70 lapsed-owner maintenance and local name-save reliability, scope before code.

20 September 2026. Baseline `dec0236a30a7de6af9d59a6c3a1962994fff1f36`, branch
`feature/solo-connected`. HEAD and locally recorded origin ref match; no fetch.
Implementation belongs to Claude; Codex reviews. No commit/push, production or
device authority is supplied by this review.

## Entry verification

Working tree matches the handover (two modified invitation documents and the
listed untracked instruction/review records). All three protected SHA256 values
match the handover exactly. No protected file changed by Codex.

Verified NEW real Claude task: **Études cleanup scope review**,
`claude.ai/epitaxy/local_da835abb-65fd-4810-925d-c65f5fe94862`.
Requested scope/evidence before implementation. No substitute agent spawned.

Read the exact C-35 account-deletion lesson in CLAUDE.md: a mode dependency
travelled through UserDefaults despite absence of the audited identifiers. The
following arguments examine actual state writers and presentation roots; reference
counts are navigation, not the proof.

## Independent trace before removal approval

| Candidate | References and reachability at baseline | Retained dependencies / expected delta |
|---|---|---|
| C-12 `showDeleteConfirm`, alert, `deleteSession()` | Private `@State` initialised false at SessionDetailView:203; its only projection is the alert at :866; Delete closure calls helper at :1786. No setter or supplied initial value. UserDefaults notification only increments `_refreshTick`; Core Data notification does likewise. Debug sheet/gesture does not write this state. Plain Swift struct, no selector or persisted-state restoration supplies the flag. SwiftUI dismissal can reset the binding but no app route presents this alert. Same conclusion in Debug and Release. | Retain `AttachmentStore.deleteAttachmentFiles`, the live journal deletion flow and its queue/backend steps. Zero reachable behaviour change. |
| Lists private paste sheet and import helpers | `TasksManagerView.body` at :793 enters selectors, saved-list rows, editor destination and two picker sheets. The editor has a fourth live presentation (`listShareRequest`). No edge enters private `taskImportPasteSheet` at :862. Its TextEditor, paste button, save button, drop delegate and focused-line state belong to the disconnected subtree. `init(activityRef:)` seeds only the activity selection. Loaders read lists/context, not import presentation state. | Preserve separate live PracticeTimerView import/parser and ListImportEditorSheet routes. Preserve list persistence, selection, editor, sharing and deletion. Zero reachable behaviour change. |
| Lists import launcher / scan representable | Private file-level launcher has no construction site. Scanner must be assessed through representable construction and coordinator registration, not named callback counts: NSObject delegate methods are protocol callbacks. Neither scanner conditional branch is constructed by this view. | Remove only after Claude's exact closure table confirms the scope. No camera/device experiment needed to establish absence of the construction root. |
| Save-current prompt and two functions | `saveCurrentItemsAsTaskSet` only sets name/flag, has no entry edge; `commitSaveCurrentItemsAsTaskSet` has no entry edge. No prompt presentation consumes the flag. | Retain shared naming helpers if the separately retained `duplicateTaskSet` still references them. Do not expand into all unrelated orphaned manager/default-sheet code. Zero reachable behaviour change. |

No mutation experiment performed. Passing builds/tests will corroborate source
compatibility and existing regressions, not independently prove deadness. No
session, account, media or fixture deletion is authorised by the cleanup.

## Scope checkpoint

Await Claude's exact scope table before approval. Requested separation of the
named import/save closure from unrelated orphaned manager/default-sheet/duplicate
members. Also corrected root-versus-whole-view presentation accounting: three
root modifiers plus the editor's live share sheet.

### Exact scope approved after reading Claude's table

Read `phase-6-cleanup-scope-2026-09-20.md` in full. Approved its Tier B table
(named Lists candidates and strict orphan closure) plus C-12's three sites.
Tier C, scanner, unrelated manager/default UI and naming helpers remain. No
product decision is required to choose the narrower delegated scope.

Returned proof-wording corrections: absence of `$` alone cannot exclude a
manually constructed `Binding(get:set:)`; the actual writer/consumer trace does.
Protocol witnesses are callback entry points conditional on construction and
registration, not live instances in this disconnected graph. There are two
paste-sheet declarations plus a use, not three declarations. The import focus
state is `@FocusState`, not `@State`. These do not alter the approved source scope.

Claude authorised to implement and run sequential Debug/Release builds and the
existing regression suite, with a unique preserved result bundle outside
DerivedData. No new deletion-only tests, device QA, commit/push or production
action. Actual diff and raw evidence review still pending.

### Actual source diff reviewed

Read the complete two-file diff: **405 deletions in TasksManagerView and 21 in
SessionDetailView; zero insertions**. Matches the approved table; adjacent blank
lines account for differences from proposed counts. The import parser is internal
static, so module-wide references were independently checked as well: its sole
call is the removed `Self` handler; the live timer parser belongs to another type.
Retained live bodies, persistence helpers, scanner branches and Tier C remain.
Existing Lists source checks still extract the same retained function boundaries.
No test source changed. `git diff --check` passes and protected hashes match.

Reviewed source SHA256:
- TasksManagerView: `8c60a178323c9b297611faf9281533ecfae29022219c017da6b0705cdd48fbd4`
- SessionDetailView: `bb0991f4dc1f34dbf7607869a77d40a9e59946660dbf4e26816fb3fed2381c98`

Source scope accepted; build/test evidence remains pending. No final unit
acceptance or commit authorisation yet.

### Build evidence and test-launch correction

Independently read both persistent raw logs under
`/Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/`:
`p6cleanup-20260920-debug-build.log` and
`p6cleanup-20260920-release-build.log` each report **BUILD SUCCEEDED**.

`p6cleanup-20260920-suite-1.log` stopped before tests: selected simulator
`DF4362E3-4C4B-4AFE-9369-15881D6BD793` is absent from Xcode's eligible list.
Claude reports exit 70. Its initial apparent zero was the log-tail command's exit,
not xcodebuild's. The iOS 26.3.1 incompatibility at the bottom of the log belongs
to the connected physical iPad, not evidence of this simulator's runtime; returned
that attribution correction. No source failure or passing tests established.

Second invocation selects explicitly eligible simulator
`336BE316-177B-46D8-8D28-809E4F41204B` (iOS 26.5) and uses unique
`p6cleanup-20260920-suite-2.xcresult`, preserving attempt 1. Validation pending.

### Required validation independently verified — bounded implementation accepted

Read suite-2 directly with xcresulttool: **Passed, 938 passed, 0 failed, 8 skipped,
946 total**, iPhone 17 Pro / iOS 26.5. Read the test tree and compared test-case
identifiers against the preserved C-70 controlled bundle: **no unit-test identity
missing or added**. Four absent identities belong to the excluded UI target
(prior launch pass, three prior UI skips), which the approved `MOTIVOTests`
invocation did not request.

The eight skips are **not** an unchanged set: six standing unit skips (three
SyncQueueOrderingReproduction and TL5–TL7) plus two prior passes now skipped:
- `UnshareDurabilityTests.testDemotionUnreachableKeepsIntentQueued`
- `StalePathQueuedPublishTests.testPublishThenReinspectFixture`

Independently read each test-details response: both say **local Supabase stack
not reachable**. Those are additional exclusions, not regression evidence or
passes; no rerun required for this unreachable UI-only subtraction. Baseline
parameterised-test aggregate/device accounting remains reported literally, not
forced into equivalence with this run's summary.

Relevant retained checks individually verified in the tree: Lists persistence
14, explicit defaults 12, journal queued deletion 28, bound journal deletion 11,
scheme configuration 2, List format 5 and List adoption 8 — all passed.

Approved source scope and required validation are accepted with those limits.
Claude independently started a UI-target run to compare with the prior baseline;
it was not required by the approved scope. Asked to finish the already-started
run separately, correct skip accounting, and run no more checks absent a new
failure. Final documentation and that in-flight result remain to be recorded.
No commit/push authorised.

### Final UI evidence and records checkpoint

Independently read `p6cleanup-20260920-uitests-1.xcresult`: **Passed**, top-level
**1 pass / 0 failures / 3 skips**, device row **4 passes / 3 skips**; summary names
one test with four dynamic runs. The session-detail test skipped for lack of a
session fixture, so this adds launch evidence only, not exercised detail-view
coverage. No further validation requested.

Reviewed C-12's audit-only update and scope evidence record. Returned two final
documentation corrections: failed local-stack reachability probes do not prove
the stack was down throughout the run; C-12's two occurrences are declaration
and alert binding, not declaration and direct assignment. No source changes or
retests needed. Implementation accepted; final checkpoint held uncommitted for
Samuel's specific commit instruction.

Phase 6 disposition reviewed in `phase-6-disposition-codex-2026-09-20.md`, with
Claude feedback separately preserved. Added cross-phase carried obligations but
rejected obsolete Production-only entitlement explanations as current blockers.
C-56 is a resolved Core Data fetch finding, not B-34 telemetry. Adult-only
direction does not retire deployed B-40/band protections. No deferral or release
approval inferred. Protected AGENTS/invitation records remain untouched.

Final documentation corrections independently re-read and confirmed. Source hashes
still match the validated pair, protected hashes match all three original values,
`git diff --check` passes, HEAD remains `dec0236`. Claude is idle at the completed
checkpoint with no further work in flight. Automation re-read: still PAUSED.

Proposed cleanup commit scope (requires Samuel's instruction): the two Swift
files, C-12 row in `docs/audit-findings.md`, and
`docs/phase-6-cleanup-scope-2026-09-20.md`. Codex review/disposition and Claude's
separate disposition feedback are review records, not automatically included.
Exclude both protected invitation documents, AGENTS.md and earlier untracked
handover/review records. No staging, commit or push performed.

### Post-commit alignment requested by Samuel

Samuel reports Claude committed and he pushed. Verified HEAD/origin at
`e5b3b08788e88324c942421ed64b640db122acf0`, all protected hashes unchanged.
Verified the same real Claude task and requested bounded documentation alignment
plus acknowledgement that the remaining C-70 gaps are next. No new implementation,
test/device action, production write or commit authorised by that message. Phase 6
formal closure and blanket acceptance of recommended deferrals have not been
granted; age and sharing implementation freezes remain separate, not a blanket
stop on independent reliability work.

## Automation

Existing automation was read and was PAUSED. An attempted retarget/resume to this
Codex task and verified new Claude task was rejected by automatic approval review
on the stated ground that ongoing coordination was not explicitly requested.
It remains paused; user confirmation requested. Direct review continues. Do not
work around the rejection or send automated messages to the old task.
