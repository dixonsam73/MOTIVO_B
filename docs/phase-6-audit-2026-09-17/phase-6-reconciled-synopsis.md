# Études Phase 6 — synopsis after reciprocal review

17 September 2026 · baseline `2fd0f63fe8b13eb8d7be72027ec83b55e78f7584`

Both independent audits are complete. Codex read Claude's report and checked its material differences against source. Claude read Codex's report and evidence, independently traced all five findings, and returned a written cross-review. The originals remain unchanged; the addenda carry the corrections.

## Agreed priorities

Both reviewers agree on three P1 release-blocking recommendations:

1. **Preserve recordings when attachment saving fails.** The app can swallow an attachment-copy error, save the session and delete its staged originals. Both editors need explicit failure propagation and safe retry.
2. **Bind pending sharing work to its originating account.** A different Connected identity can otherwise dispatch another account's queued work. Existing ownerless entries need conservative handling, not assignment to the next signed-in user.
3. **Make queued intent durably acknowledged.** A failed disk write can leave an old Publish on disk after the user chooses Unshare. Relaunch can restore that obsolete action.

Additional important findings are unreadable Lists being overwritten, deleted own Lists reappearing through legacy mirrors, stale attestation completions clearing a newer operation, and withdrawal treating a zero-row demotion as success. Claude also identified synchronous media processing in view construction; its actual performance impact needs measurement.

## What cross-review changed

- **Withdrawal needs a coordinated design.** Account ownership, disk durability and truthful server acknowledgement are distinct causes, but belong in one coordinated batch. Preserve a lapsed owner's right to delete. A filtered empty response is not proof that somebody else's post is absent. Neither proposed implementation is ready merely because its finding is confirmed.
- **Delivery cleanup must distinguish rejection from an uncertain outcome.** Deleting an uploaded object after any reported delivery failure can break a delivery that actually committed before its reply was lost. Claude withdrew that blanket remedy.
- **Device evidence remains accepted.** Current source has no explicit automatic drone restart, but does not establish the exact mechanism behind the observed recovery. The accepted unplug record also does not clearly label which recorder was used. These are evidence limits, not reversed QA results.
- **Invitations scope was approved.** Claude corrected her original wording. Implementation authority in this audit, legal clearance and release decisions remain separate; B-40 stays in force.
- **Documentation drift is real, but did not invalidate this audit baseline.** Codex read both guidance files and the newer records. No guidance file was changed.

## Recommended next step

Approve bounded scopes in this order: attachment preservation; queue ownership/durability and withdrawal; Lists persistence/migration; attestation ownership. Each should have failure-path validation before implementation is accepted. Follow with measured media performance, delivery reconciliation, and separate cleanup/documentation work. Preserve existing legal, release and residual device gates rather than treating Phase 6 as blanket release clearance.

## Evidence and limits

Both Release builds succeeded; both counted 77 unique compiler deprecations. Codex's four disposable source probes reproduced narrow failure paths. Claude reports 534 passing unit cases, zero failures and three deliberate skips across 71 suites; Codex read that result but did not rerun or inspect her raw test bundle. These tests do not cover away the new findings. Neither audit operated physical devices or validated a live backend. No P0 was found in the reviewed scope; neither report certifies whole-app safety.

No fixes, commits, pushes or deployments were made. Repository HEAD and the existing dirty-file hashes stayed unchanged.

## Reports

- Codex original: `claude-phase-6-audit.md` (the supplied prompt's filename; authorship disclosed inside).
- Claude original: `claude-opus5-phase-6-audit.md`.
- Codex cross-review: `codex-phase-6-cross-review.md`.
- Claude cross-review: `claude-opus5-phase-6-cross-review.md`.

All are in this output directory. Read the addenda alongside the originals where conclusions or remedies differ.
