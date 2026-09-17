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
