# Recorder reliability — Codex review checkpoint

**FINAL LOCAL ACCEPTANCE — 21 September 2026.** Codex independently reviewed the final
controller diff, diagnostic and tests, verified all three hashes against Claude's evidence,
parsed the retained original full-suite xcresult, and read Release/control logs. Accepted:
1070 passed, zero failures, six unchanged standing skips, 1076 total. Compared individual
test IDs/results to the accepted F3 bundle: 16 additions, zero removals, zero changed results
among existing tests. Release succeeded; independently normalised compiler warning sets
match the F3 baseline (no added/removed diagnostics). Control I fails its one wiring case;
control J fails precisely the three capture cases; final hashes confirm restoration.

No actionable code finding remains in this bounded diagnostic. Corrected evidence wording:
two observation sites do not imply two lines per session, since route-change callbacks can
invoke the preference helper again. Existing microphone rules, audio-session writes, observers
and cancellation remain unchanged. No new device QA required for this scope; actual Release
log capture remains unobserved and can be checked during an ordinary later recorder run.
This is local implementation acceptance, not recorder-wide reliability or Phase 6 closure.
Ready for Samuel's commit decision; no commit/push performed. Automation paused on completion.

**LATEST STATUS — BOUNDED FINISH AUTHORISED, 21 September 2026.** Samuel asked not to
waste the existing work if worthwhile. Codex read the complete source diff, diagnostic and
13 tests. Recommendation: retain the modest troubleshooting benefit, with only the
corrections below and final validation; no wider recorder work or new device QA campaign.

Required before acceptance: classify and render from one captured set of available/current
inputs (the current code re-reads live getters after verification and can describe a different
route); test with changing getters so that defect is observable. Capturing the two properties
is still not an atomic AVAudioSession snapshot, and should not be called one. Preserve policy
reuse with a small read-only snapshot adapter if needed. Remove the unused mutable controller
sink property if no test drives it; tests currently inject directly into the diagnostic only.
Replace lengthy development-history comments with short contract comments and keep the history
in docs. Correct the early-return explanation: the old return skipped the USB branch's later
observation, not the no-input path. Do not claim OS logs can never leave the device or never
persist: claim only no app-managed upload/persistence and port types only. Finish focused tests,
one final Release build and the planned final suite; retain original evidence. No new device
matrix, no commit/push, no R2/R3/R4 work. Implementation acceptance remains pending.

**Earlier pause, 21 September 2026 (superseded only for the bounded finish above).**
The scope approval below is historical:
Samuel challenged R1's value and Codex recommends parking this optional diagnostic. Claude
has stopped at the preserved checkpoint in `recorder-r1-checkpoint-2026-09-21.md`; incomplete
source/test changes remain uncommitted and unaccepted. Eight-minute recorder automation
paused. Do not resume from the earlier approval. See `release-priority-review-2026-09-21.md`.

Samuel authorised discussion with current Claude task, reconciliation of already completed work, then scoped implementation/review. Real Claude task remains “Account ID/handle removal discussion”; message requesting recorder reconciliation visibly received, Claude Running and checking C97. Eight-minute heartbeat reactivated and retargeted to recorder work. No recorder implementation approved yet.

HEAD independently checked b479487; Samuel reports pushed. Handle removal/F1/F2/F3 committed; latest Steve publication server evidence accepted with retry-context limit, first purchase anomaly unexplained. No connection between that anomaly and recorder work assumed.

Independent current audit-register read: C97 runtime-error/interruption/media-reset observers and pending-start cancellation already implemented and accepted. Pending start spans six stages, tested at abstract claim/queue level; normal device record/stop/preview/save regression passed but did not inject cancellation. Preserve CM15/Bluetooth/drone/video tests to exact evidence; extra drone unplug explicitly waived. Automatic capture audio-session configuration intentionally preserved for first-use audio and requires explicit scoped analysis before any change.

Candidate residuals: permanently blocked startSession occupying serial sessionStartQueue; unsynchronised cross-queue isArmedToRecord; missing-audio watchdog; effective input verification; genuine media-buffer/hardware failure timing. Do not call all candidates reproduced defects. Source search confirms isArmedToRecord and sessionStartQueue remain in VideoRecorderController paths, but no full concurrency audit yet. Claude asked to produce completed/residual/not-reproduced matrix grounded in current code and later evidence, choose smallest high-value measurable scope, reproduce/measure locally, then return scope before implementation.

Next review: read Claude's recorder reconciliation/scope and actual relevant source independently. Approve bounded fixes only when justified, then review implementation/tests and retained original artifacts. No speculative rewrites, age/sharing changes, server/credential/device actions, purchase/reset, commit/push. Protect AGENTS.md/invitation docs and unrelated handovers. User owns later device QA and final sign-off; routine bounded choices delegated. Phase6 remains open.

## Scope review — 21 September, R1 approved with amendments

Read the complete Claude reconciliation and independently inspected RecordingInputPolicy, AudioRecordingAttempt, video's preactivation, preference application, route-change caller and audio append diagnostic. Approve R1 as **input-route observability only**, not a reliability defect fixed or proof of a soundtrack. No R2/R3/R4 implementation in this unit.

Required amendments communicated to Claude:

- Correct the factual claim: `applyAndVerify` does NOT configure the category. `AudioRecordingAttempt.begin` separately calls `configureForAudioRecording`. Still use only read-only verification here because `applyAndVerify` can change the preference.
- Four preference statements are two alternative branches in two paths, not four independent verification points. Observe once after each path's selection attempt, including no available preferred input. Preactivation runs on a background queue while the reusable adapter/verifier is MainActor; preserve that boundary and document a deferred main-thread observation as such, not an atomic reading at selection time. No blocking dispatch or session-configuration changes.
- Provide a concrete Release-enabled local diagnostic for both match and mismatch/unavailable, recording stage and desired/effective port TYPE only. No device UID/name, account data, recording content, remote telemetry or per-buffer logs. A mismatch is a point-in-time observation, not proof of selection failure or silent audio; no user-facing warning/refusal/retry.
- Test the production diagnostic path with a fake session/sink for match, mismatch and unavailable, checking no preference/category/activation writes. Verify both production call paths are wired and retain a falsifying control. Tests cannot prove real hardware routing or eventual audio arrival.
- Preserve previously accepted first-use setup, observers/cancellation and waived device checks. Deliver a small device QA plan for this measurement with its build/provenance limits. Full suite/build evidence as proposed; retain original bundles. No commit/push.

Implementation acceptance remains pending actual code and evidence review.

## 14:30 UTC check — corrected source reviewed; validation running

Real Claude task reports 16 focused tests passing and control J failing exactly the three
capture tests. Full suite is still running; Release/evidence report not yet delivered.
Codex independently read the revised diagnostic and controller diff: captured available/current
inputs are reused for classification/output; mutable controller sink removed; selection writes
and automatic setup unchanged; local-log limitations corrected. No new blocking source finding
in this bounded review. Await original final results before acceptance; no duplicate build run.
