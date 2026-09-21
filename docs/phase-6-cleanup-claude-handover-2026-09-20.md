> **HISTORICAL — ARCHIVED 21 September 2026. NOT CURRENT WORK.**
>
> Instructions to a fresh Claude window for the bounded cleanup, prepared after `dec0236`.
>
> That cleanup was completed and committed as `e5b3b08`. **Read this as a record of how the window was set up, not as instructions to follow.**
>
> **Any instruction, scope, baseline, cadence or "next step" below is spent.** For the
> current position see `docs/account-id-removal-evidence-2026-09-20.md`, `docs/fresh-join-f3-evidence-2026-09-21.md`, `docs/recorder-r1-evidence-2026-09-21.md` and `docs/release-priority-review-2026-09-21.md`, and take the repository state from
> `origin/feature/solo-connected` rather than from any commit named here.
>
> The text is preserved unchanged; only this banner was added.

# Études — fresh Claude window: bounded cleanup, then Phase 6 disposition

Prepared by Codex on 20 September 2026, after Samuel reported dec0236 pushed.

You are the implementation agent in a fresh REAL Claude desktop window. Samuel wants
Codex to review your scope before removal. First read the instructions/current evidence,
then produce a short reachability/dependency table for the two cleanup candidates. No
code removal until Codex's review approves the exact scope. After approval, implement
only that scope and return exact diff/build/test evidence with explicit limits. Do not
stage protected files or commit/push unless Samuel instructs it. Reply with the scope
path and a clear ready-for-Codex checkpoint. This handover was prepared by Codex from
the accepted record; do not mistake it for a new product design or a Claude-authored
independent review.

## Current verified state

Repository: `/Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO`.
Product Études; Xcode project/scheme/source directory retain legacy name MOTIVO.
Branch `feature/solo-connected`. HEAD and locally recorded origin ref both equal
`dec0236a30a7de6af9d59a6c3a1962994fff1f36`; Samuel explicitly reports pushed.
No remote fetch was needed or performed for that comparison.

Accepted work this window:
- `1940ca3`: B-37 literal directory search and per-account request budgets.
- `25d032e`: C-97 pending recorder-start cancellation. One sub-gap only.
- `79fe153`: B-37 production deployment record/schema recapture. Deployed and independently verified on 20 September at 16:24 UTC. No more deployment needed.
- `dec0236`: C-70 evidenced profile writes. Existing rows use owner PATCH;
  absent rows use gated creation, with bounded fallback. Owner-bound transport,
  serial dispatch, exact returned-row evidence, stale-effect suppression, conditional
  handle-only generation, guarded UI/setup effects, and edit-reversion latch fix.
  Local implementation and bounded Device A QA accepted. No backend deployment.

## Next scope — authorised to investigate, NOT yet approved for removal

Samuel agreed a fresh-window unit: prove the remaining Lists import/save scaffolding
and C-12 deletion UI unreachable, have Codex review the evidence, then approve bounded
removal. Follow with Phase 6 closure/disposition review. Do not start deleting on the
strength of historical labels alone.

Candidate surfaces (line numbers at dec0236, re-check current source):
- `MOTIVO/TasksManagerView.swift`: `TasksManagerImportLauncherSheet` (~1405),
  `taskImportPasteSheet` (~862), `showSaveCurrentTaskSetPrompt` (~71),
  `saveCurrentItemsAsTaskSet` / `commitSaveCurrentItemsAsTaskSet` (~1205).
  Trace entire presentation/state/caller chain and helpers. Some import helpers may
  serve LIVE features; never delete by naming similarity or declaration counts.
- `MOTIVO/SessionDetailView.swift`: C-12 `deleteSession()` (~1786),
  `showDeleteConfirm` (~203), alert (~866). IMPORTANT: the helper DOES have a lexical
  caller in the alert's Delete button (~867). The hypothesis is an unreachable alert
  trigger, not zero references. Prove no live route can set the state, including
  bindings/modifiers/conditional builds. Preserve live journal swipe deletion and
  every shared deletion helper used elsewhere. Do not delete sessions or fixtures.

### Samuel's relayed Claude warning — reachability must survive indirection

Samuel explicitly asked to carry Claude's warning from this session. Absence of
textual references is NOT proof of dead code. The structural scanner counted a
comment as code; C-35's entitlement dependency travelled through UserDefaults and
escaped identifier-based review. Read the exact C-35 record in CLAUDE.md before
claiming equivalent indirect routes are absent here.

Trace roots and edges through SwiftUI modifiers, state bindings and their writers,
conditional configurations, selectors/Objective-C exposure, string-keyed lookups,
persisted flags/UserDefaults, queued payloads and restoration paths WHERE APPLICABLE.
Do not mechanically invent a runtime route for a private Swift function; explain
which mechanisms are possible and which are excluded by its declaration/context.
A grep result is navigation/evidence of a reference, not the reachability argument.

Claude proposed a cheap delete-and-observe-failure discriminator. Use this carefully:
a genuine dead-code removal should leave the suite passing. Passing tests alone do
not prove deadness; a compiler failure only proves a lexical dependency. For any
mutation/control experiment, state the specific observable behaviour and expected
failure FIRST, verify the failure is attributable to that mutation, restore exact
bytes, and record limits. Prefer an existing relevant behavioural check; no new
brittle source-text tests merely mirroring deleted implementation. If execution is
needed to settle a plausible hidden route, propose the smallest non-destructive local
probe before removal approval. Do not conduct blind shared-tree deletion experiments
or real session/account deletions. No device action without its explicit checkpoint.

First deliverable: a small scope table with each proposed removal, all references,
why unreachable in both configurations, shared dependencies retained, and expected
behavioural delta (target zero). Codex independently checks it before coding approval.
A reachable feature or changed deletion/list behaviour is outside this cleanup.

Validation should be proportionate: required builds/checks and existing relevant
regressions. No new tests merely proving lines were deleted. No automatic device QA
for proved unreachable-only removal. Do not run two xcodebuild processes concurrently.
Preserve test evidence with a UNIQUE explicit resultBundlePath outside DerivedData.
Stop for the actual failure cause rather than repeatedly rerunning until green.

## Operating agreement

Claude implements/tests; Codex independently reviews design, actual code/callers and
raw evidence; Samuel instructs commit and pushes himself. No simultaneous code editing
by Codex. No spawned substitute agents. Coordinate with the REAL Claude desktop app.

Routine bounded choices are delegated. Do not re-ask settled product policy. Hard-stop
for serious product-changing decisions and explicit commit/deployment/device gates.
No production writes, new credentials, account resets/deletions, purchases, or phone
operations in the next cleanup. No commit/push unless Samuel instructs this unit.

Eight-minute check-ins are requested, but the automation is PAUSED at the completed
checkpoint. Resume only after verifying the NEW Claude task; never message the old
window on autopilot. Read the automation file and preserve fields when updating it.
Automation id: `tudes-overnight-review-with-claude`.
Old Codex target: `01a0beac-1b2b-78e0-be57-cbd46aae8285`.
Old Claude task: `claude.ai/epitaxy/local_06010a5d-1f5a-48ec-8f74-3d2e81195e87`
(title `B-37 production deployment handover`). This is historical, NOT the new target.
A new Codex task must use its actual task identity when resuming the heartbeat.
Notify meaningful changes only; pause at owner dependency/final checkpoint.

## Working tree and protection

At handover preparation all implementation/QA changes are committed. The tree is NOT
clean: two pre-existing modified invitation documents and untracked instruction/review
records remain. These are not cleanup material; do not stage, overwrite or restore them.

Protected baseline SHA256:
- `docs/connected-invitations-direction.md`:
  `90f60494f42ec2500254b6a7aa6384ee670ffa49fd5b678fb26191eeb27885c0`
- `docs/private-connection-invitations-scope-2026-09-17.md`:
  `c470d4a18c79cff102b01b472f7d06ddb4079fdbcffc998f11e260882236223d`
- untracked `AGENTS.md`:
  `f948387812c8e6b8a002e4baf84cce472430c954677bed8577e5d9b2f1cbaaaa`

Codex-owned untracked records: `docs/c70-codex-scope-review-2026-09-20.md`,
`docs/phase-6-b37-codex-review-2026-09-20.md`,
`docs/phase-6-b37-fresh-window-handover-2026-09-20.md`,
`docs/phase-6-c70-fresh-window-handover-2026-09-20.md`, and these two new cleanup
handovers. Claude should leave Codex records alone. Both invitation docs and AGENTS
remain protected even if their content appears to need reconciliation.

## C-70 accepted evidence and remaining limits

Persistent evidence root:
`/Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/`.
- `claude-opus5-c70-implementation-checkpoint.md` (final section governs).
- `c70-controlled-20260920-controlled-1.xcresult`: independently read by Codex;
  Passed, zero failures, nine unchanged skips. 941 top-level passed, 944 device-row
  passed; summary lists one dynamically parameterised test with four runs. Preserve
  literal accounting; this difference is not a failure.
- `c70-release-build-final.log`: BUILD SUCCEEDED independently verified.
- Earlier final-code parallel run: 942 pass / 1 fail / 9 skip. The failing
  `PublishServiceConnectedDeleteTests.testPrivatePayloadUnsharesEvenWhenCallerAsksToPublish`
  passed with its class in isolation (8/8). Failure bundle was lost to DerivedData
  retention; cause remains UNEXPLAINED, not proven simulator fault. Later controlled
  full run is separate evidence, not retrospective explanation.
- `c70-source-manifest.txt`: all 13 Swift/test content hashes independently matched.
  There was no preinstall phone binary hash; version 1.0(131) is not build identity.
- `c70-device-qa-PRE-baseline.json`: 19:11:06 UTC, name Ben Craft QA1, eligible true.
- `c70-device-qa-POST1-after-name-edit.json`: 19:12:37 UTC, Ben Craft C70.
- `c70-device-qa-POST2-after-revert.json`: 19:14:54 UTC, Ben Craft.
  Samuel reported persistence after leaving/reopening and no warning for both checks.
  Codex independently read backend results; protected privacy unchanged.

Device QA proves normal-path save and eventual latest value. It does NOT demonstrate
controlled in-flight timing, creation, generation, failure responses or identity switches.
Those have local automated coverage with limits in the checkpoint.

C70-3 naturally lapsed maintenance remains NOT EXERCISED / CLIENT REACHABILITY GAP:
`canShowConnectedAccountManagement` requires Connected mode, so naturally lapsed Solo
returns before profile sync. D-U6-3 already permits server-side owner maintenance; do
not reopen that policy as if undecided or claim all of C-70 fulfilled. No client mode
change authorised here. Local-save error swallowing/onDisappear-only name persistence
is also carried under C-70, not fixed. Avatar minimal-return evidence observation is
filed under C-34, no duplicate finding or avatar implementation.

Device A: SD beta burner/iPhone16e, existing identity prefix6fd0a833, account handle
`devicearlease`, subscription chain2000001228947923. Last observed name Ben Craft.
Directory.lookup_enabled FALSE and authoritative account_privacy.lookup_enabled TRUE,
lookup_changed_at2026-09-10 06:02:41.524643+00, follow_requests_enabled TRUE are protected.
Samuel renewed Sandbox himself for QA. Last renewal date19:40:13UTC is HISTORICAL,
not current entitlement authority. Never request renewal merely to run cleanup.

Current scope011 accepts active Production AND Sandbox. `membership_state()` can say
sandbox_only regardless of eligibility; it is not an entitlement test. Use current
schema and connected_member for any authorised read; older Production-only migration
is superseded. A server name change's cause/time cannot be inferred just from membership:
owner UPDATE is ungated. Preserve observations separately from interpretations.

## Phase 6 closure review AFTER bounded cleanup

Do not declare Phase 6 nearly done from green tests or optional code deletion. Produce
an explicit disposition/owner/evidence/next gate for each remaining item. Do not silently
turn unaccepted deferrals into accepted ones.

- Adult assurance/R0 implementation FROZEN pending legal/Apple/HEAA/server-trust gates.
- Sharing/server cleanup protocol FROZEN independently of age: six open concerns cover
  in-flight upload vs withdrawal/physical bytes; cleanup ownership/epochs; referenced
  file deletion; mutable content/reused paths; fresh consent after cleanup/stale devices;
  refusals consuming newer work. No broad sweeps or guessed protocol.
- F-6 delivery reconciliation: no validated blanket client-only cleanup.
- C-97: pending-start sub-gap accepted; blocked startSession, old unsynchronised
  isArmedToRecord, hardware/real media coverage and other recorded residuals remain.
  Do not restart recorder work automatically. Drone unplug extra diagnostic was waived.
- F-3 profiling partially measured, did not justify immediate fix. No new capture asked.
- C-15 PDF selected-page metadata residue: P3, deferral recommended, NOT user-accepted.
- C-22 AVFoundation deprecations optional, avoid speculative API sweep.
- Three dead membership_control columns require separate production-DDL authority.
- F-10–F-12 record drift; AGENTS protected. Historical paragraphs are dated evidence,
  not automatically current authority; reconcile through current record without erasure.
- C-70/C-34 limits above and provider ticket SU-478356 remain explicit. No indefinite
  waiting for provider response; no claim public docs prove hosted physical-byte behaviour.
- G7 earliest naturally matured cleanup2026-11-01 and other standing Phase3 obligations
  unchanged. Do not touch lifecycle worker to force completion.

## Read in the new window

Read current `CLAUDE.md`/`AGENTS.md` and applicable repository instructions, preserving
protected files. For current task evidence read:
1. `docs/c70-codex-scope-review-2026-09-20.md` (chronological; latest entries govern).
2. `docs/phase-6-b37-codex-review-2026-09-20.md` (latest plus relevant earlier evidence).
3. `docs/phase-6-client-cleanup-checkpoint-2026-09-19.md` (remaining inventory is historical;
   cross-check later accepted units rather than treating all rows as still open).
4. `docs/phase-6-b37-fresh-window-handover-2026-09-20.md` §7 remaining inventory.
5. `docs/phase-6-audit-2026-09-17/phase-6-reconciled-synopsis.md`, current
   `docs/audit-findings.md`, and relevant `docs/qa-plan.md` sections.

Read selectively; no need to reload every historical megabyte. Authority conflicts
must be resolved against actual current code/evidence and Samuel's latest instructions.
