> **HISTORICAL — ARCHIVED 21 September 2026. NOT CURRENT WORK.**
>
> Phase 6 disposition review against `dec0236`, accepting the bounded cleanup and explicitly declining to close the phase.
>
> **Phase 6 is still open**, so that part stands. The dispositions and next-step recommendations were made before the handle removal, the fresh-join fixes and the recorder diagnostic landed.
>
> **Any instruction, scope, baseline, cadence or "next step" below is spent.** For the
> current position see `docs/account-id-removal-evidence-2026-09-20.md`, `docs/fresh-join-f3-evidence-2026-09-21.md`, `docs/recorder-r1-evidence-2026-09-21.md` and `docs/release-priority-review-2026-09-21.md`, and take the repository state from
> `origin/feature/solo-connected` rather than from any commit named here.
>
> The text is preserved unchanged; only this banner was added.

# Phase 6 disposition review — 20 September 2026

Prepared by Codex against `dec0236` and the chronological acceptance records.
**Bounded cleanup source and required validation accepted. Phase 6 is not declared closed.**

**Current checkpoint:** cleanup committed as `e5b3b08`; Samuel reports pushed.
HEAD and locally recorded origin ref independently match that commit (no fetch).
Samuel has selected the remaining C-70 gaps as the next workstream: naturally
lapsed self-profile maintenance and local name-save reliability. Scope/design
review and isolated persistence measurements are complete; the bounded local
implementation and final validation are independently accepted (972 passed, zero
failed, six standing skips; final Release passed). Nothing committed yet; real
lapsed-owner device QA remains unperformed. This selection does not accept every recommended
deferral, close Phase 6 formally, or unfreeze age/sharing implementation. Independent
work is not subject to a blanket wait for solicitor or Supabase responses.
An owner below identifies who must carry the next action; it does not authorise
that action or imply Samuel has accepted a deferral. Claude implements scoped
work, Codex independently reviews, Samuel owns product/release and explicit
commit, production and device decisions.

## Accepted work is not reopened

Recording preservation, queue ownership/durability, withdrawal reporting, sharing
choice persistence, Lists migration/defaults and attestation completion ownership
have accepted bounded checkpoints. Lists instrument transition and journal swipe
deletion have later user-reported device acceptance; their earlier pending labels
are historical. F-5/F-7/F-8 cleanup and F-9 simulated deletion have later accepted
commits. U1–U3, S1/S2b, B-38, B-37 and the C-97 pending-start sub-gap are recorded
in the 19 September client checkpoint and subsequent 20 September records.

B-37 deployment is accepted in `79fe153`; C-70 bounded profile writes are accepted
in `dec0236`. Neither needs another deployment. C-70's normal save and eventual
latest-value device results do not prove controlled races, failure paths or
naturally lapsed client reachability. Its earlier full-suite failure remains
unexplained; the later preserved passing run is separate evidence.

## Carried inventory and next gates

| Item | Disposition and evidence | Accountable next owner / gate |
|---|---|---|
| Named Lists import/save and C-12 alert/helper | Accepted and committed `e5b3b08`; Samuel reports pushed, local origin agrees. 426 pure deleted lines; Debug/Release pass; unit bundle 938/0/8 with two additional local-stack exclusions recorded. Extra UI run confirms launch only. See `phase-6-cleanup-codex-review-2026-09-20.md`. | Checkpoint complete. No further deployment or test action needed. |
| Other orphaned manager/default-sheet/duplicate code | Outside this bounded removal. Naming helpers remain required by retained lexical callers. | Codex/Claude scope only if a later cleanup is commissioned; no deletion by declaration counts. |
| `AttachmentSharePageScope` / `SimulatedPostCommentService` | Earlier inventory retains them; public/shared boundaries prevent treating them as this private UI removal. | Codex/Claude independent reachability scope if commissioned; sharing freeze remains applicable. |
| Adult assurance / R0 | Implementation FROZEN. Adult-only direction is a decision, not shipped behaviour or proof of adequate assurance. `adult-only-connected-rescope-2026-09-18.md`. | Samuel, with legal/Apple/HEAA and server-trust evidence; explicit unfreeze and reviewed scope before implementation. |
| Sharing concern 1: in-flight publish versus withdrawal / physical bytes | OPEN. S2b stops superseded preparation before transport; does not prove cancellation after admission, prevent a late server commit, or establish physical removal. | Samuel owns protocol disposition; Claude designs and Codex reviews counterexamples before any unfreeze. |
| Sharing concern 2: cleanup ownership / epochs | OPEN, prospective protocol requirement. `cleaned_through` and related constructs are not shipped. | Same protocol owners; demonstrate late-upload/cleanup ordering with ownership evidence. |
| Sharing concern 3: deletion of referenced files | OPEN. API success and row removal are insufficient proof that surviving references remain usable or that physical bytes were removed. | Same protocol owners; reference-safe lifecycle and provider evidence gate. |
| Sharing concern 4: mutable content / reused paths | OPEN. A sweep or old cleanup must not remove a newer legitimate object at a reused path. | Same protocol owners; review stable identity/version and concurrency model before implementation. |
| Sharing concern 5: fresh consent after cleanup / stale devices | OPEN. Restores and other devices are outside the accepted same-installation queue safeguards. | Same protocol owners; define consent and ordering across restore/rejoin, then verify. |
| Sharing concern 6: refusals consuming newer work | OPEN, prospective requirement. Current phase-blind 409 analogue is latent; no later-phase production trigger established. | Same protocol owners; prove refusal handling retains newer work; do not label an unbuilt protocol a reproduced production defect. |
| F-6 delivery reconciliation | No validated blanket client-only cleanup. A reported failure may follow a committed delivery; unconditional delete could break it. | Claude/Codex protocol investigation after Samuel approves scope; reconcile uncertain outcomes before any cleanup implementation. |
| Provider SU-478356 | Hosted physical-byte/retention semantics unconfirmed in carried evidence. Public documentation is not a measurement of this deployment. | Samuel/provider liaison; carry explicit evidence limits without indefinite waiting or inventing a favourable answer. |
| C-97 remaining recorder work | OPEN beyond accepted pending-start cancellation. Blocked `startSession`, unsynchronised `isArmedToRecord`, missing-audio watchdog, effective input enforcement and real-media failure timing remain. Device regression did not inject cancellation. | Samuel decides any follow-up; Claude scopes hardware/concurrency work and Codex reviews before code. Extra drone unplug diagnostic was waived, not outstanding. |
| F-3 media work | PARTIALLY MEASURED. SessionDetailView asset construction/teardown sampled CPU, not per-open wall time; staging write unmeasured. Evidence did not justify immediate fix. | Samuel decides whether further measurement is useful; no new capture requested. If scoped, Claude measures and Codex reviews attributable results. |
| C-15 PDF selected-page metadata | OPEN P3. UUID/page-number residue, no document-content leak established; growth unmeasured. Deferral recommended, **not user-accepted**. | Samuel accepts/rejects a concrete deferral; otherwise Claude scopes metadata collection and Codex reviews preservation boundaries. |
| C-22 AVFoundation/SwiftUI deprecations | Optional scoped maintenance, not a count-driven sweep. Audit recorded 77 unique warnings on its baseline versus register's historical 53. Neither is asserted to be today's count. | Samuel chooses scope if wanted; Claude/Codex preserve behaviour and use F-3 evidence to prioritise. |
| Three `membership_control` columns | Separate backend cleanup candidate: `cutover_at`, `cutover_identity_count`, `cutover_verified_at`. No production authority in this task. | Samuel's separate production-DDL approval after dependency proof, local rehearsal, parity and reviewed apply/rollback. |
| F-10 instruction drift | AGENTS.md remains protected. Mitigation here: current source and newer evidence take precedence over dated descriptions. No synchronisation/deletion performed. | Samuel decides canonical instruction-file strategy before any protected-file edit. |
| F-11 historical/current record drift | Current disposition is stated here without erasing dated history. Opening worker version and old CP-3 blocker statements are not current authority. | Codex/Claude maintain dated current records; any broader reconciliation must preserve evidence provenance. |
| F-12 count drift | 53→77 was the audit-baseline correction, not a new sweep or current census. | Record owners should date counts; maintenance scope remains C-22. |
| C-70 residuals | Bounded local implementation ACCEPTED: identity-based maintenance with scoped forced refresh, and local persistence before remote submission with visible failures/Retry and draft/reset protection. Full suite 972/0/6, final Release passed; not committed or device-verified. | Claude holds for Samuel's explicit commit instruction. Samuel owns the real lapsed-owner device checkpoint; do not claim it passed. See `c70-residuals-codex-review-2026-09-20.md` for evidence and limits. Account-free Solo, gated creation, identity protections and general Connected access rules remain preserved. |
| C-34 residuals | Feed-row propagation has accepted device evidence; same identity on two devices and other surfaces remain unclaimed. Avatar metadata minimal-return 2xx cannot evidence a changed row; observed structurally, no impact established. | Samuel chooses bounded follow-up/QA; Claude and Codex keep this under C-34, without a duplicate finding. |
| Forced purchase attestation joining old work | Unverified candidate. Accepted generation ownership prevents stale publication, not every purchase-result association. | Claude/Codex reproduce under a separately reviewed scope before calling it a defect; no new purchase/device action here. |
| G7 | OPEN, earliest naturally matured cleanup 2026-11-01. Zero-identity scheduled runs do not discharge it. | Existing U7 owner; elapsed time then genuine live-authority evidence. Never advance schedule or mutate worker to force completion. |
| C-31 / B-34 / B-11 Gate 6 part 3 | Standing Phase 3 obligations unchanged: Production Billing Grace, denied-write telemetry limitation, first real subscription production GRANT. | Existing Phase 3 owners; their original evidence gates remain. No transfer into this cleanup. |

## Cross-phase carryovers — not new cleanup scope

Claude's separate feedback prompted this cross-check. Its first revision repeated
historical entitlement blockers and misidentified C-56; those claims are not
adopted. Active Sandbox membership is accepted under scope011. No current census,
runtime entitlement or live credential status is inferred from old paragraphs.

| Item | Disposition / evidence | Next owner and gate |
|---|---|---|
| Phase 4 exit conditions 2, 6-ASC and 8 | `phase-4-exit-assessment.md` and later Phase 5 records carry them; no explicit full discharge found in this review. Earlier “17 unentitled / Production-only” blocker is obsolete, not current authority. Later normal profile and feed-avatar QA is not automatically the full share/unshare exit protocol. | Samuel owns formal disposition and any device/ASC action; Claude/Codex reconcile exact later evidence before scheduling fresh QA. No automatic device work. |
| CP-3 teen evidence | No end-to-end teen-range/default-row hardware observation in its closure record; automated/deployed-expression coverage remains distinct. Adult-only direction supersedes the target, not the historical evidence. Further teen fixture experimentation was explicitly closed. | P5-G/H and Samuel carry the evidence limit during re-scope; do not spend more identities to retest it. |
| CP-3 band-before-directory ordering | Named verification obligation remains unclaimed here. The old Production-only Sandbox blocker is superseded by scope011; no new hardware ordering proof follows merely from that change. | Claude/Codex reconcile under the eventual adult-assurance scope, Samuel owns device gate. Never weaken enforcement to obtain evidence. |
| Shipped B-40 and directory band trigger | The 13+ design, including B-40 and `tg_directory_requires_band`, remains in force until a reviewed replacement ships. Adult-only is direction, not implemented access enforcement. | Samuel/P5-G/H own unfreeze; Claude replacement design and Codex review. Current protections must survive until replacement. |
| P5-G/H and StoreKit/TestFlight release gates | Legal/evidential determination and publication remain separate. P5-H must re-derive ASC disclosures against the final product. Required TestFlight checkpoint is not satisfied by simulator or Xcode device runs. | Samuel/release owner, with legal input and reviewed publication/QA plans. No submission, purchase or deployment authority here. |
| Connected invitations | Existing approved scoping and legal clearance are distinct. Both modified invitation documents remain protected; adult-only direction changes the context. No implementation or reconciliation performed here. | Samuel chooses the next scoped work; Claude/Codex reconcile current direction without overwriting protected documents. |
| C-36 / QA B7 | First-join verification remains carried; `phase-5-c36-prediction.md` assigns backend/device confirmation to Samuel. Returning/reinstalled identity evidence does not substitute for fresh first join. | Samuel owns suitable fixture and explicit device checkpoint; no new identity or purchase requested here. |
| C-5 | Store identity rule fixed locally with five cases; register does not claim UI/device acceptance. Legacy untracked adoption limitation remains. | Samuel owns eventual QA scheduling; Claude/Codex preserve exact store-versus-device evidence distinction. |
| C-32 | Register carries RC final copy review. The accepted 18 September About/Explore presentation refresh is later work and must be included, rather than claiming no rewrite occurred. | Samuel/RC owner reviews both surfaces against final shipped product and records explicit disposition. |
| C-56 | Resolved source/simulator body-time Core Data fetch defect, not a U6a telemetry defect. Device evidence was not claimed in `phase-5-c56-acceptance.md`; this review does not reopen the fix. | Existing Phase 5 acceptance record governs; preserve its device limit in release QA. B-34 separately owns denied-write telemetry. |
| Historical C-44 gate (b2) token residue | CLAUDE.md records an abandoned, unrevoked test token. No current validity check or credential access performed; do not describe dated “live” as a fresh measurement. | Samuel owns operational disposition through an explicitly authorised credential procedure. No agent credential/reset action here. |

## Closure gate

Completion of this optional deletion cannot by itself close Phase 6 or clear
release. The bounded review and commit checkpoint are complete. Resolve explicit
disposition decisions (including C-15 and protected-file
strategy) and keep frozen protocol/legal work and carried evidence limits visible.
Recommendations in this document are not accepted deferrals.

## Sources read

- `phase-6-client-cleanup-checkpoint-2026-09-19.md`, with later sections governing.
- `phase-6-overnight-checkpoint-2026-09-19.md` and `phase-6-checkpoint-2026-09-18.md`.
- `phase-6-b37-fresh-window-handover-2026-09-20.md` §7 and latest B-37 Codex review.
- `c70-codex-scope-review-2026-09-20.md`, latest entries; audit C-70/C-34 and QA Group C70.
- `phase-6-audit-2026-09-17/phase-6-reconciled-synopsis.md` and original F-10–F-12 records.
- Current source and git history at `dec0236`; no production or device verification performed here.
