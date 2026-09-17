# Phase 6 — Codex review of Claude's independent audit

17 September 2026. Baseline `feature/solo-connected` at `2fd0f63fe8b13eb8d7be72027ec83b55e78f7584`.

This addendum preserves both independent reports. Codex's original audit is `claude-phase-6-audit.md` (the supplied prompt's naming, with actual authorship disclosed inside); Claude Opus 5's is `claude-opus5-phase-6-audit.md`. The naming collision does not indicate shared authorship. Reciprocal review began only after both reports were complete, at Samuel's explicit request.

I read Claude's scope, audit and comparison, then checked the material differences against current source and committed policy snapshots. No fixes, commits, pushes, deployments, device operations or production queries were performed in this cross-review. Existing dirty documentation and untracked AGENTS.md remain byte-identical to the audit baseline.

## Findings accepted from Claude

| Claude ID | Codex disposition | Evidence and limits |
|---|---|---|
| F-1, P2 | Accept: own saved Lists can resurrect after deletion. Add to the same persistence batch as P6-I-04, but retain separate failure cases. | PracticeTimerView.swift:966–974 mirrors own Lists to a context key. TasksManagerView.swift:1378–1389 deletes only from the global store via :1157–1161. The loader :1112–1153 merges surviving legacy keys and rewrites global storage. SavedList.swift:131–135 deliberately excludes adopted Lists from the mirror. Confirmed source mechanism, no new device reproduction. A complete fix must address all readable legacy keys and preserve unique legacy content. |
| F-2, P2 | Accept the false demotion-success contract; revise proposed remedy before implementation. | BackendShim.swift:1802–1826 accepts a minimal PATCH response without matching-row evidence. Catalog `posts_update_owner` is membership-gated; owner DELETE is not. A denied/no-match demotion can leave `is_public=true` after subsequent deletion failure. This is distinct from P6-I-03's stale durable intent. No local HTTP reproduction was run in this review. |
| F-3, P2 | Accept synchronous media work in SwiftUI bodies; user-visible magnitude remains unmeasured. | SessionDetailView.swift:1151–1160 reads synchronous asset duration; PostRecordDetailsView+Attachments.swift:336–346 additionally writes a surrogate when absent. The write is conditional, not necessarily repeated on every body evaluation. Historical C-3 timing is evidence of a related cost, not a measurement of these sites. |
| F-5 / F-8, P3 | Accept optional cleanup. | Only two configureSession callers, both playback. shouldResumeAfterRouteChange has a declaration and two writes, no read. Preserve the actual live recorder policy when removing dead policy code. |
| F-6, P3 | Accept orphan risk on definite delivery rejection; reject blanket cleanup on any delivery error. | ConnectedAttachmentShareUI.swift:593–627 uploads before deliver; ConnectedAttachmentSharing.swift:267–286 performs delivery INSERT separately. If INSERT commits but its response is lost, deleting the object would break a real delivery. Reconciliation/idempotency must precede deletion; this connects to my original lost-response delivery concern. |
| F-7, P3 | Accept 15 unused-type candidates. | Repeated whole-symbol searches across app and unit/UI test Swift sources found each listed type only at its declaration. Removal still needs normal build/test validation; a text search is not a general proof that arbitrary deletions have zero possible effects. |
| F-9, P3 | Accept misleading simulated service with real destructive network calls. | BackendShim.swift:333–398 is live deletion code; :2444–2452 selects that service outside configured Connected/preview modes. No production deletion or user harm demonstrated. Trace legitimate callers before substituting a stub. |
| F-10 / F-11 / F-12 | Accept record drift and warning census; qualify impact. | AGENTS.md diverges from CLAUDE.md. I read both and newer deployment/QA records, so this did not establish that my audit used obsolete membership state. Both auditors independently counted 77 unique compiler deprecations. Preserve dated historical statements; correct current authority pointers. |
| F-14 | Agree with existing C-97 part (2). | Capture runtime errors/interruption/reset coverage and missing-audio watchdog remain absent. Ordinary QA7 acceptance remains intact. |

## Conclusions that need correction or narrower wording

1. **F-4 does not close the device-mechanism question.** Current source has only two explicit drone starts, both user actions, and its invalidation stops permanently. Output UID/sample-rate stability can explain an input-only route change without invalidation. But source does not measure which callbacks/guards fired during Samuel's accepted QA8 observation. Keep the observed automatic audible recovery accepted, and keep its mechanism unresolved. No repeat QA is required merely for audit completeness.
2. **F-2 needs both truthful acknowledgement and deletion availability.** Requiring one returned row detects failed demotion, but stopping forever at that check could prevent a lapsed member reaching the deliberately ungated delete. A fix scope must preserve C-35's deletion/withdrawal availability without broadening publishing privileges. Also, `is_public=true` alone does not establish current follower visibility: the SELECT policy additionally tests viewer membership and `owner_entitled_until`. Retain the latent failed-withdrawal state finding without claiming demonstrated immediate exposure.
3. **F-6's original proposed remedy is unsafe for ambiguous outcomes.** Definite rejection and lost acknowledgement must have different handling. Do not convert a storage leak into broken recipient content.
4. **F-13 overstates the absence of evidence.** The accepted check 4 says “during recording” within combined USB audio/video QA; it does not unambiguously label that particular unplug observation audio-only. The video source predicts stopping for `.oldDeviceUnavailable`; whether that notification and mode occurred in the accepted observation remains unclear. Do not reopen QA7 or record a reproduced video defect.
5. **Invitations scope is approved.** The current dirty scope explicitly records Samuel's approval at its header and lines 7, 152 and 179. Implementation, legal clearance, teen exceptions and release split remain separate and pending. Claude's original “not approved” wording conflated those states. B-40 stays enforced.
6. **C-41 is a product/legal boundary, not an instruction to enable teen discovery.** No generic opt-in UI should be implemented as audit cleanup. C-12 is unreachable deletion UI code with other deletion entry points, so its existence alone does not prove users cannot delete sessions.
7. **Negative findings remain scoped.** Source/catalog security checks are valuable but not live production parity or whole-app privacy assurance. In particular, Claude's original no-cross-member-leak assessment must be read alongside P6-I-02's account-switch queue provenance risk, which she is reviewing. Her Release-print scan excludes certain interpolated fields but does not prove every possible error object's text contains no sensitive content.

## Joint work order proposed by Codex

1. Fix local attachment-save loss (P6-I-01), preserving originals until durable attachment success.
2. Fix queue ownership and durable intent (P6-I-02/03), together with correct withdrawal acknowledgement and lapsed-owner availability (F-2). Define conservative handling of legacy unowned queue entries before implementation; never assign them silently to whoever is signed in.
3. Fix Lists persistence (P6-I-04 + F-1): corrupt bytes survive failed decoding; deleted Lists stay deleted; legitimate legacy-only content remains recoverable.
4. Fix attestation flight ownership (P6-I-05) with a controlled old-A/new-B completion-order regression check.
5. Address delivery outcome reconciliation and media performance with targeted evidence, followed by bounded dead-code/deprecation/document cleanup.

This is a proposed scope order, not implementation approval. Existing Phase 4 exit, Phase 5 legal/release obligations, C-99 residuals and accepted QA retain their own statuses. Neither report found P0 in its reviewed scope, and neither is a release clearance.

## Validation boundary

Codex's original pass includes four executable disposable source probes and a successful Release build. Claude reports a successful Release build and 534 passing unit cases, 3 deliberate skips, zero failures across 71 suites. I have read her recorded result; I did not rerun or independently inspect her raw test bundle in this cross-review. Green existing tests do not cover away the newly identified failure paths.

## Reciprocal review received

I have now read Claude's completed `claude-opus5-phase-6-cross-review.md`. She independently source-traced all five Codex findings and agrees with P1 for 01–03 and P2 for 04–05. She accepts the substantive corrections above, including withdrawing blanket delivery cleanup and the proposed hard stop before a lapsed owner's delete. She preserves her independent report and records corrections in that addendum.

I accept her useful extensions: the Add/Edit editor clears staged items even before the metadata save; the Lists loader also overwrites a present value of the wrong defaults type; the queue problem requires a different backend identity, rather than a routine sign-out/in to the same identity. The coordinator's ordinary 30-second cooldown survives the stale completion; the demonstrated third overlap within that window needs a forced purchase/restore call. A sufficiently long pending B can still outlive the cooldown, so the race itself is not confined exclusively to forced callers.

Her suggested combined withdrawal remedy is a design starting point, not an approved algorithm. I sent final qualifications: ownership provenance, persistence failure and zero-row acknowledgement remain three distinct causes even when fixed in one coordinated batch. An RLS-filtered empty read cannot prove another owner's row absent. Verify absence only under the captured originating identity, maintain that identity through asynchronous steps, preserve ungated owner deletion, and distinguish denied/no-match demotion from authentication/transport failure before any destructive continuation. Neither audit establishes that this is merely a one-header change.

Do not total grouped cleanup rows as if they were individual findings. The main list comprises five Codex findings and Claude F-1/F-2/F-3, plus separate lower-priority risks, cleanup and process drift (Claude rated F-10 process drift P2). Agreement here validates findings within stated evidence limits; it does not authorize implementation.
