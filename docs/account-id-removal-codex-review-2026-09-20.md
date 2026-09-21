# Account ID removal — Codex independent review

## Current checkpoint — 20 September 2026, 22:49 UTC approximately

**LOCAL IMPLEMENTATION ACCEPTED. SAMUEL FINAL SIGN-OFF PENDING.** Full suite1000/0/6, final Debug/Release and18source+8test hashes independently verified. No open product-code blocker. No commit/push, production or device action. Phase6open. Overnight automation paused; Claude instructed to update status docs only and hold.

Samuel explicitly authorised overnight scope → Codex approval → Claude implementation/testing → independent Codex code/evidence review → local acceptance, with final sign-off retained by Samuel. No commits/push or production/device actions. Eight-minute heartbeat `tudes-overnight-review-with-claude` is ACTIVE on this Codex task.

Real Claude task: **Account ID/handle removal discussion**, `claude.ai/epitaxy/local_9fc1063f-53be-4cab-a17d-c628eba7bae8`. Use native Claude UI; no substitute agents. Claude owns app edits; Codex owns this review.

Baseline HEAD `05ad6a8`; preceding app source acceptance `8b54ba6` (972 passed, 0 failed, 6 standing skips; final Release passed). Later commits documentation only. Baseline full suite does not need repeating absent an unresolved concern. Phase 6 remains open; device QA still outstanding.

## First scope review

Read complete `docs/account-id-removal-assessment-and-scope-2026-09-20.md`, reviewed actual PeopleUserRow fallback, all subtitle/peek argument call sites, setup completion/freshness sequence, sort implementation, comment styling and affected test references. No source changes found in working tree. Existing untracked review records and protected invitation edits remain unrelated.

Corrections sent to Claude before approval:

1. Retained server handle search is **not inert**. Existing values and old-client writes remain searchable under unchanged B-37 controls. New-client removal cannot discharge global namespace/reuse or old-client obligations.
2. Opaque invitation tokens prove possession, not necessarily intended-person identity. Withdraw the scope's “strictly better” verification claim. Invitation design stays unresolved and protected.
3. There are **eight** handle subtitle sites, and **17** named source files before CommentsView, not seven/fourteen. Name all source/test additions and changes. Include bounded removal of CommentsView's placeholder mention styling/chips/alert (18 source files unless inspection justifies a difference), preserving original comment text and unrelated reply/actions/accessibility.
4. Preserve non-handle subtitle overrides for attachments, shared posts and ensembles. New formatter consumes only returned directory instruments/location, trims/drops blanks, uses a defined bound (proposed first two nonempty instruments plus +N, then location). No extra fetch, location search, fabricated details or another person's local-owner fallback. Test presence combinations, whitespace, international text and multiple/long instruments.
5. Preserve setup evidenced-success/freshness decision, C-70 save/Retry/reset/identity protections and scoped 401 refresh. Explain any removal of redundant generation-only guards.
6. Use accepted baseline evidence. Run appropriate targeted tests and final full suite/Debug/Release after changes, no redundant baseline full suite. Investigate actual warning deltas only when needed.
7. Enumerate tests retired with removed APIs versus converted tests versus retained coordinator/evidence coverage. Test real production payload omission on owner PATCH and missing-row creation fallback. Demonstrate a meaningful new assertion fails against pre-change code. Raw aggregate test counts alone are insufficient.

Subtitle replacement is approved in principle: it renders information already returned and available on the corresponding profile, without changing access/discovery controls. It supports Samuel's explicit name/instrument/location recognition rationale. No need for another product permission request within this boundary.

## Protected baselines independently rechecked

- `docs/connected-invitations-direction.md`: `90f60494f42ec2500254b6a7aa6384ee670ffa49fd5b678fb26191eeb27885c0`
- `docs/private-connection-invitations-scope-2026-09-17.md`: `c470d4a18c79cff102b01b472f7d06ddb4079fdbcffc998f11e260882236223d`
- `AGENTS.md`: `f948387812c8e6b8a002e4baf84cce472430c954677bed8577e5d9b2f1cbaaaa`

No tests/builds run by Codex this checkpoint. No implementation acceptance claimed.

## Revision 2 approval

Read the complete revised scope. All seven correction areas resolved sufficiently for implementation. Independently verified `persistAvatarToBackendIfPossible` is the next function after removed generation, and inspected the three Coordinator source-extraction tests and setup completion assertions. Claude correctly identified their dependence on the deleted function/guard strings; these must be re-expressed, not silently dropped.

Approved 18 source files listed in §7.1, five existing test files (C70DirectoryWriteTransportTests, C70DirectoryWriteEvidenceTests, C70DirectoryWriteCallerPolicyTests, C70DirectoryWriteCoordinatorTests, DirectorySyncFailureTests), two new test files (DirectorySubtitleTests, AccountIDRemovalTests), and Claude's scope/evidence document. File-level formatter in PeopleUserRow is acceptable. Changes to this boundary need a concrete explanation, not a new Samuel permission request for routine dependencies.

Clarifications sent with approval, to apply while proceeding:

- Source-text assertions prove wiring, not rendered SwiftUI behaviour. Preserve this evidence distinction.
- Scope §9.3 counts a helper among “seven conversions”; final accounting must separate test IDs/helper edits and include the three Coordinator conversions.
- Search success remains conditional on privacy/membership. Requests are not necessarily approved relationships. Historical row counts are dated evidence, not current production measurement.
- The new client still forwards arbitrary search input: retained server handle matching and the `@` mismatch remain technically callable. Do not globally close audit findings or add a search rewrite in this unit.
- Positive controls require isolated copies or carefully restored local mutations with no overlapping builds. Record intentional failures, restoration and final accepted hashes. No implementation acceptance until restored final bytes and actual results are reviewed.

Next check-in: inspect Claude progress, any requested boundary adjustment, implementation diff and final evidence when ready. No duplicate builds. Automation remains active.

## Interim source review at 21:59 UTC

Read core service/setup/AuthManager/ProfileView and people/peek/sort/store/comment diffs while Claude continued tests. Changes track the approved 18-source-file boundary. Protected hashes independently rechecked and unchanged. No Codex build run concurrently. Formatter uses first two nonempty instruments plus +N and location; all reviewed row call sites use the corresponding returned account. Non-handle overrides remain outside those edits. Comment deletion removes placeholder helpers/chips/alert without editing comment body storage. Payload removes the handle while retaining owner/evidence mechanisms.

Sent these corrections to Claude as an in-flight message (UI showed queued/unread while test compilation ran):

1. Generation function deletion accidentally swept the following Avatar MARK and explicit `@MainActor` from `persistAvatarToBackendIfPossible`; restore unrelated lines even if inherited isolation means it builds.
2. Remove orphaned `isAccountIDFocused` state/dismiss assignment and `lastAccountIDSubmitAt`.
3. New fingerprint comment invented an across-upgrade persisted-latch rationale. The latch is view-local state; remove the unused handle segment or give a truthful reason to retain it. Do not claim persistence that does not exist.
4. DirectorySyncFailure explanation incorrectly says neither server attribution nor actionability holds. The classifier still proves attribution; only user actionability was removed. Keep classification and correct explanation.

No implementation acceptance. Next check must verify these corrections were received/applied and inspect completed tests/evidence. Source is still moving; this was an interim review, not a final hash-bound review.

## Test review at 22:08 UTC

Independently verified Avatar MARK/`@MainActor` restored, orphan focus/submission state removed, fingerprint's unused nil segment removed with corrected lifetime explanation, and collision attribution explanation corrected. Read new structure/compatibility/formatter tests and CallerPolicy/Evidence/DirectorySyncFailure test diffs. They cover payload compatibility and formatter values; source assertions are appropriately labelled wiring-only. No new build run by Codex.

Found and sent a concrete setup structural-test defect: `testSetupPerformsExactlyOneAwaitedWriteSoOneFreshnessGateSuffices` rejects any `capturedGeneration` substring, but correct retained code includes the argument label `capturedGeneration: result.generation`. Must reject the removed local declaration rather than the retained API label. Also its directory-service-only await count cannot prove absence of another service's suspension after freshness. Requested an assertion on the code tail from the surviving freshness decision to completion containing no await, rather than overstating that narrower count. Keep all production guards intact.

Asked Claude to verify targeted result IDs include actual classes `C70SetupCallerStructureTests` and `C70ProfileViewEffectGuardTests` (their filenames differ), and report evidence location durably. UI message was marked read. Next check: verify corrected assertion and results/controls; full suite still pending. Do not count Claude's interim summary as independently verified pass evidence.

## 22:18 UTC checkpoint

Claude confirmed the targeted-selection concern was real: the filename was not an XCTest class, so the first selected run silently omitted three classes. Reports a corrected selection ran 114 passing tests across 12 classes. Reports payload-key control, three re-anchored guard controls and feedback-surface control failed as intended, followed by byte-identical restoration. Full suite is now running, final Debug/Release to follow. No duplicate run requested.

Read corrected setup assertion: absence applies to `let capturedGeneration`, retained `capturedGeneration: result.generation` is positively asserted, and no `await` may occur in the source tail from decision to completion. Code-side freshness stays unchanged. Reviewed it as structural evidence only; no new product-code finding. `git diff --check` clean.

Requested complete durable handoff with artifact directory, exact bundles/logs, source hashes, final test-ID accounting and disclosure of initial targeting omission. Message queued while full suite runs. No local acceptance yet; next check should inspect final artifacts when available.

## 22:27 UTC checkpoint

First full suite found a further reference to removed generation in `MOTIVOTests/C70WiringPinTests.swift`. Read its exact diff and approved this sixth existing-test-file adjustment: rename the combined global-challenge/generation pin, keep the exact forced global auth challenge assertion, replace now-nonexistent generation mode guard with generator absence. No product guard removed to satisfy it. Claude reports rerun full suite **1000 passed / 0 failed / 6 skipped**; final Debug/Release are running. These counts are not yet independently verified.

Requested first-suite failure and conversion be included in final test accounting. No open product-code blocker found so far, but final hash-bound review and raw result verification remain required. No other action or duplicate build; await evidence handoff on next wake.

## Independent final evidence inspection — 22:38 UTC

Artifact directory: `/private/tmp/claude-501/-Users-samueldixon-Documents-Xcode-projects-MOTIVO-B-MOTIVO/c657c407-b562-4523-b151-9170cc9ae8a2/scratchpad/evidence/`.

Read Claude's `docs/account-id-removal-evidence-2026-09-20.md` and MANIFEST. Independently read final bundle with xcresulttool: `/Users/samueldixon/Library/Developer/Xcode/DerivedData/MOTIVO-ezwfngloiavjzsgbiehetfqnilcc/Logs/Test/Test-MOTIVO-2026.09.20_23-19-42-+0100.xcresult` — **1000 passed,0 failed,6 skipped,1006 total**, simulator. Tool cache writes required escalated read, approved successfully; no blocker. Individual results exported to `/private/tmp/codex-handle-final-tests.json`.

Compared to `/private/tmp/codex-c70-fullsuite-tests.json`: **978→1006 IDs,11 removed,39 added,zero result changes among surviving IDs**. Same six standing opt-in skips. Three generation transport tests disappear without replacement; three other retired handle tests get new replacement tests; five conversions rename their IDs;31 genuinely new tests. Thus net+28 =31+3−6; renamed conversions netzero. Claude's evidence row claiming three baseline skips became passes is **false** and correction requested. Targeted selection omission is unrelated to full-baseline skips.

Independently verified all **18 source +8 test hashes** match post manifests; final Debug and Release logs each contain BUILD SUCCEEDED and no error lines. Core final diff has no new product issue beyond already-corrected interim findings. Read all changed areas over successive checkpoints; final source hashes recorded in Claude's evidence document bind the result.

Pending acceptance requirements sent to Claude: correct arithmetic, replace remaining scope claims of rendering with wiring, and give exact positive-control result bundles/raw logs (currently only summaries found in evidence directory). Prose accounting is not preserved raw evidence. Reuse existing artifacts; do not rerun final green suite/builds. Keep tested bytes unchanged. Next wake should inspect those controls and finish local acceptance if claims are supported, then pause automation and leave Samuel final sign-off.

## Final disposition — 22:49 UTC

Claude corrected the arithmetic and remaining rendering claims. Positive-control originals were not retained: commands were piped through grep without saved logs, and Xcode pruned their bundles. `evidence/CONTROLS.md` contains **Claude-transcribed terminal outputs**, with provenance/weakness explicit. Codex read the transcript but **did not independently verify original control runs**. The corrected targeted bundle was also pruned; its saved log survives. Neither is represented as independently inspected original control evidence.

Local acceptance rests on reviewed actual production code/wiring, final saved1000/0/6 xcresult and per-ID comparison, final Debug/Release logs, matching26source/test hashes and unchanged protected hashes. Intentional-failure transcripts provide supplementary reported evidence only. This limit does not justify further source mutation or repeated green suites; no open implementation blocker remains.

Accepted client behaviour: no handle field/generation/writes/display or placeholder mention chips; eight identity subtitles use returned instruments/location; UUID ownership/access and C70 save/retry/freshness/401 behaviour preserved. Server column, values, search branch, privacy/membership controls and RPC shapes remain untouched. Typed handle search remains supported under existing gates. No invitation design settled.

Remaining owner checkpoint: Samuel final product sign-off, then explicit commit instruction and Samuel push. Device/UI visual QA remains outstanding before release; neither rendering nor real-device behaviour claimed. Phase6notclosed. Claude notified of local acceptance, asked to update current scope/evidence statuses only then hold. Eight-minute heartbeat paused via automation tool.
