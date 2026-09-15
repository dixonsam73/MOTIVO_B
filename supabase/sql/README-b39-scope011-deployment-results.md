# B-39, then scope 011 — production deployment results, 2026-09-15

**Executed** under Samuel's explicit approval, within `README-b39-scope011-deployment.md` (committed at `81176fc`) and Codex review 012.

**Excluded:**
- B-40;
- secrets;
- other functions;
- any account, reset, purchase or device action.

**Evidence:** the coordination folder, `claude-evidence/deploy-b39-s11/`. It holds the exact submissions, raw responses, captures, function lists and downloads.

## Sequence and outcomes (UTC)

| # | Step | Time | Outcome |
|---|---|---|---|
| 0 | Preconditions and read-only transport probe | 19:40:33 | HEAD = upstream = `81176fc`; tree clean apart from `AGENTS.md`; linked ref confirmed; deliverables at their reviewed hashes. Positional multi-statement probe returned exactly the `marker` row |
| 1 | H4 aggregate and personal identity | 19:40:44–46 | 3 auth users, 0 directory rows, 2 live Sandbox memberships, 0 Production, no cleanup schedules. Études Dev identity present, one live Sandbox row, **no schedule set or due** |
| 2 | H1 recapture and H2 | 19:41:22 / 19:41:29 | Ten valid arrays, **byte-identical** to the committed snapshot. Six target md5 = `PRE_PROD`; grants unchanged; comment = `COMMENT_PRE`; drift 0; status-5 rows 0; enforcement on |
| 3 | **A1** `2026-09-15-b39-apply-production.sql` | 19:42:11 → row 19:42:18 | **Committed.** Three bodies = `POST_B39`; comment unchanged; drift 0; membership fingerprint `2:b4672841…`. Read-only inspection at 19:42:21 confirmed `POST_B39`, B-40 unchanged, drift 0 |
| 3b | Recapture after A1 | 19:43:26 | Exactly `connected_member`, `membership_apply_state_v1` and `membership_entitled_until` differ; the nine other surfaces are identical |
| 4 | E1 pre-check | 19:43:30 | Hosted versions and `ezbr_sha256` = manifest; other functions unchanged; forward package = recorded hashes = `git archive 81176fc` (functions tree `72c6060a…`); config `verify_jwt = false` ×4; fresh isolated downloads = rollback packages ×4 |
| 5–6 | E1 deploy and verify, **one at a time** | 19:44:22, 19:45:50, 19:45:59, 19:46:07 | `appstore_notifications_v1` v3→**v4**, `appstore_reconcile_v1` v4→**v5**, `membership_cleanup_v1` v6→**v7**, `membership_attest_v1` v2→**v3**. Each: explicit `--no-verify-jwt`; only that function moved; ACTIVE; `verify_jwt` false; fresh isolated download byte-equal to the forward package with the B-39 status-5 line |
| 6b | Consolidated Edge list | 19:46:39 | Exactly the four moved by one version; `delete_account_v1` v10 and `revoke_apple_identity_v1` v4 unchanged; all `verify_jwt` false |
| 7 | H4 before A2 | 19:46:34–36 | Unchanged; no schedule on the personal identity |
| 8 | **A2** `2026-09-15-scope011-apply-production.sql` | 19:47:12 → row 19:47:14 | **Committed.** `POST_S11` on the two predicates; `membership_apply_state_v1` = `POST_B39`; comment = `COMMENT_S11`; drift 0; membership fingerprint unchanged. Inspection at 19:47:17 confirmed it, with B-40 unchanged |
| 9 | Final recapture | 19:48:16 | Same three definitions differ, nothing else. **`supabase/schema/functions.json` updated to this capture** (+3/−3) |
| 9b | Final H4 | 19:48:20–22 | Unchanged; personal identity present, no schedule set or due |
| 9c | Deployed predicate (read-only) | 19:48:59 | Personal identity: `connected_member()` **true**, `membership_state()` `sandbox_only`, `membership_entitled_until()` in the future. Identities with membership: 2; `connected_member()` true: 2 |

## One stop, assessed and resolved within the sequence

**What stopped.** After the first Edge deploy, the pinned deploy script's pre-check for the second function **stopped**: the forward package no longer matched its recorded hashes.

**What had changed.** Read-only inspection showed the CLI had written one file, `supabase/.temp/linked-project.json` (keys `name`, `organization_id`, `organization_slug`, `ref`), into the package root.
- Nothing under `supabase/functions/` or in `config.toml` changed.
- Hosted state was exactly as expected: notifications v4 verified, and every other function at its pre-deploy version and SHA.

**Assessment.** Not production drift, and not an unclear or partial deploy.

**Resolution.**
- Before each remaining function, the CLI-created file was moved out of the package into that function's evidence folder.
- The **unchanged** deploy script (SHA-256 `4ced3642…`) then re-proved the full package hashes before deploying.
- The package was left at its recorded hashes afterwards.

## Not claimed

- **Entitlement readings** are timestamped query projections (the personal identity's Sandbox renewal was due at 20:00:02 UTC), not end-to-end acceptance.
- **Two-device Connected QA** has not run.
- **The hosted directory still holds 0 rows.** Scope 011 permits a verified Sandbox member's own directory insert; nothing here has created one.
- **No rollback** was needed or run. R2, the Edge rollback packages and R1 remain the prepared entry points.
