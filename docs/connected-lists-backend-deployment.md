# Connected Lists backend deployment

17 September 2026. Samuel explicitly approved the scoped backend commits and live deployment, then authorised direct coordination with Claude. Claude independently reviewed all seven backend artifact hashes; her corrected GO review is preserved in `connected-lists-backend-review.md`. Codex independently verified the client size check and resolved the review's initial oversized-upload finding without code changes.

## Before apply

All ten structural surfaces were freshly read from production and match the committed snapshot, including full constraints and policies. The exact MIME and bucket guard predicates returned true; List-MIME delivery count and List object count both returned zero. A CLI temporary-login authentication failure interrupted the first concurrent reads; retrying without concurrent temporary-login requests completed verification. No data or schema writes were used for preflight.

The lowercase wire suffix is intentional. The sender-path constraint assumption is pinned by the full fresh baseline comparison. The apply and rollback SQL are unchanged from Claude's reviewed hashes.

## Approved operation

Commit the reviewed backend SQL, local verification scripts and review/deployment notes. Submit `supabase/sql/2026-09-17-lists-apply-production.sql` once as one transaction; require the response row `Lists MIME enabled`. Immediately capture the production schema and require only the expected changes: one MIME constraint extension, one new List metadata constraint and the private bucket MIME allowlist extension (13 to 14 entries). Record the result and commit the snapshot. Samuel pushes himself.

No app changes, unrelated legal/invitation records or `AGENTS.md` are included in these backend commits. No RLS/grant/function/worker changes are authorised or required. Once any List object or row exists, the guarded rollback refuses to remove support.

## Status at this pre-apply commit

Reviewed and ready; not yet applied. A following deployment record must distinguish applied/structurally verified from device end-to-end acceptance. Samuel's next check is a real Person send, receive and Save to Lists, then the remaining feature QA.

## Applied and structurally verified

The reviewed source was committed as `1f36ef1` and the apply was submitted once. The response contained exactly `[{"verification":"Lists MIME enabled"}]`. The immediate full production recapture succeeded. Codex compared all ten surfaces with the fresh pre-apply capture: only `constraints.json` (one MIME extension, one metadata check addition) and `storage_buckets.json` (attachments allowlist 13 → 14) changed, exactly as predicted. All eight other surfaces are unchanged.

Applied UTC: 2026-09-17T08:24:17.642957+00:00

No rollback was executed, no device was operated, and nothing was pushed. Real-device send/receive/adopt acceptance was pending at deployment; see Samuel’s subsequent confirmation below. The client UI fix and other app changes remain uncommitted; only the separately approved backend work is being committed.

Both deployed constraints were independently re-read and confirmed `convalidated = true`. Claude accepted the closing structural verification; see `connected-lists-backend-closeout.md`. This commit records the refreshed production snapshot and acceptance. Core device send/receive/adopt QA is now confirmed below; other device checks are not implied.

## Device QA confirmed by Samuel — 17 September 2026

After deployment, Samuel confirmed a List successfully sent from Device B to Device A, was saved into A's Lists manager, and behaved like a List created on A. Repeated Save to Lists actions for the same delivery did not create duplicates. This provides real-device evidence for the core send/receive/adoption flow and same-delivery idempotency. The preceding device setup was latest Release builds on both devices in Connected mode.

**The compact Send label's appearance is ACCEPTED** — Samuel installed the new build on 17 September 2026 and confirmed it visually (*“Send button looks much nicer”*). **That is acceptance of the control's appearance only, and nothing more.** This confirmation does not independently establish Ensemble delivery, deletion isolation or re-adoption after local deletion; those retain their existing local-test evidence. No push or further device action was performed to record this result.
