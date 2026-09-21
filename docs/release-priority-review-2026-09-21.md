# Release priorities — candid review, 21 September 2026

**Subsequent Samuel decisions, 21 September:** Founding 500 IS a launch requirement.
After the bounded recorder finish/review, Samuel intends fresh windows for both Claude and
Codex to scope it; no Founding implementation starts here. iPad launch must include Apple
Pencil Scores markup and a manuscript sketchpad. Discuss in a separate new planning window
after recorder completion. The minimal layout-only option below is therefore not the selected
iPad launch scope. iPad still is not authorised as pre-iPhone-release implementation.

Codex, at Samuel's request after questioning the value of further recorder diagnostics.
This is a recommendation and document reconciliation, not release approval, a blanket
acceptance of residual risks, or authority to implement a new feature.

## Recommendation

Pause open-ended coding and cleanup. There is no justification for keeping agents busy
merely because Apple or Supabase has not replied. There are still real release decisions
and verification obligations; the app is not declared ready for public Connected release.
Useful work must change a user outcome, resolve a launch decision, or satisfy an explicit
release gate. More diagnostics, more tests of already accepted behaviour, and more phase
ceremony do not meet that test by themselves.

## Current checkpoint and recorder pause

The accepted handle removal and fresh-join work is committed at `b479487`; Samuel reports
pushed. The latest Steve run demonstrated directory publication after successful purchase
without subsequent navigation, but included an earlier failed purchase attempt. The supplied
console did not establish its cause. Keep the planned fresh-join retest; investigate on
recurrence rather than inventing a Sandbox explanation or adding speculative fixes.

Claude has acknowledged the R1 pause. Her `recorder-r1-checkpoint-2026-09-21.md` reports the
deliberately failing control restored, no process running, and incomplete/unaccepted work
preserved. R1 source/test edits remain in the working tree, not in the accepted commit;
do not accidentally include them in the next release build or commit. The eight-minute
recorder automation is PAUSED. No further recorder QA is requested.

## Work that matters

1. **Adult-only Connected: wait for the missing evidence before implementation.**
   The age-assurance decision, what the server can trust, existing members, and payment
   ordering remain unsettled. Current 13+ protections stay in place. Final privacy policy,
   App Store disclosures and age-rating decisions follow the settled product/legal position.
   This review gives no legal conclusion about the adequacy of any Apple result.

2. **Founding 500: a substantive launch decision, currently unbuilt.**
   `pricing-launch-model.md` records the first 500 Connected activations receiving twelve
   months free, then an introductory subscription offer for later members. It explicitly
   says none of this is implemented. No later implementation record was found. This is
   meaningful work IF Samuel still wants that launch model, not a small configuration tweak:
   allocation, non-purchase access, expiry and conversion all affect the settled membership
   lifecycle. Clarification requested; no implementation started. The document's old
   Production-only entitlement statement is superseded by scope 011; that correction does
   not create a Founding entitlement mechanism.

3. **Sharing: a release decision, not an indefinite vendor waiting room.**
   Supabase's reply may clarify hosted deletion/retention guarantees, but cannot by itself
   settle our upload-versus-withdrawal ordering, surviving references, reused object paths,
   and stale-device consent. Keep implementation frozen until a sound design is reviewed.
   Useful next work would be a short disposition of which guarantees are essential to launch
   and which facts remain missing. If the provider never replies, the choices remain a
   support escalation, a design with supportable guarantees, narrower promises/capability,
   or holding the affected release. Silence is not evidence of either safety or failure.

4. **Final release verification and launch configuration: necessary, timed near release.**
   Reconcile later device evidence before asking Samuel to repeat anything. Carry the
   genuinely missing checks into one final checklist: clean first-attempt join, any still
   unclaimed remote-playback/avatar/Score-adoption coverage, and the Phase 4 authenticated
   private-write rejection observation. The last is NOT discharged by a UI save that never
   attempted a private upload. Do not use an RLS-bypassing operator connection as its proof.
   Production Apple notification configuration is explicitly release-gating in the decision
   register; its last recorded state is dated, not rechecked live here. Verify/configure it
   deliberately before launch, retaining Sandbox admission. Keep the required final
   TestFlight checkpoint distinct from Xcode-device testing. Prior TestFlight work did occur;
   do not describe the whole app as never tested there. Production Billing Grace, the first
   real subscriber grant, and G7 retain their original timing/owners; G7 cannot be forced
   early. Use an identifiable release build rather than treating repeated 1.0 (131) as
   proof of tested source.

## Work to park

R1 route diagnostics; warning-count/deprecation sweeps without an actual compatibility
problem; dormant backend-column deletion; cosmetic metadata cleanup; video optimisation,
imported-video naming and optional expanded features. Invitations have an approved scope
but remaining protocol/legal/release gates: not an automatic next implementation.

Known concurrency concerns are not dismissed: C-97's armed-state race and C-99's carried
file/index interactions deserve an explicit risk disposition before final release sign-off.
They are more relevant than R1, which fixes neither. Any further investigation must target a
specific reachable loss/failure scenario, with a bounded question, not promise to prove all
concurrency safe. This document does not newly accept those residual risks.

## iPad: worthwhile planning, separate from pre-release implementation

The app target currently specifies device family 1 (iPhone). Existing iPad orientation
settings and universal test targets are not evidence of an iPad product. No iPad build or
layout assessment was performed in this review, and no duration estimate is justified.

The roadmap deliberately defers M13 iPad and M14 personal iCloud sync. Architecture also
bundles M13 with first-class Threads and manuscript Thoughts. Discuss a smaller first iPad
version using existing capabilities before inheriting that whole bundle: journal/detail
layout, Scores alongside practice, resizing/rotation, keyboard/pointer and recording flows.
Separate manuscript/Pencil features, model migrations, and iCloud sync. Most important
product question: would an initially independent iPad library be useful, or is continuity
with the iPhone essential? Connected is not private-library sync. A local-first iPad version
may be smaller; cross-device continuity changes the scope substantially. Faster coding does
not remove that product decision or hardware verification.

## Document reconciliation and sources

Read the current roadmap/principles in CLAUDE.md, architecture.md, pricing-launch-model.md,
phase-5-scope.md, phase-4-exit-assessment.md (including 16 September amendments), the
adult-only rescope, invitation direction, relevant audit rows and QA records, both 20
September disposition reviews, later cleanup and 21 September fresh-join records, and
Claude's recorder reconciliation/checkpoint. Inspected project target settings. No live
backend/ASC audit, device action, build or test was performed for this document review.

The 20 September dispositions are NOT a reliable stand-alone current task list: they carry
older C-70 device-pending labels, and Claude's feedback says ASC labels are not entered,
while the amended Phase 4 assessment records nine types saved but unpublished. Share/unshare
device work also has later acceptance, and the USB/drone checks have accepted evidence.
The architecture still lists a handle in its domain description despite its removal from
the client. Preserve dated evidence, but do not manufacture work from obsolete labels.
This review is a compact current recommendation, not another request for a documentation sweep.
