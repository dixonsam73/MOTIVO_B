# Scope 011 — verified Apple Sandbox membership counts as Connected entitlement: prediction

**Recorded 2026-09-15, before any implementation or run.**

**Governing documents:**
- `claude-scope-011.md`, as corrected by `claude-scope-011-revision-1.md`;
- `codex-scope-review-011-revision-1.md`;
- Samuel's explicit approval of this local stage.

**Not authorised:** live SQL/Edge deploy, hosted data or account mutation, retention exceptions, App Store changes, app/UI changes, commits.

## 1. Change under test

`supabase/migrations/20260915160000_scope011_verified_sandbox_entitlement.sql`:

**Changed bodies.** It re-issues B-39's `connected_member` and `membership_entitled_until` bodies **verbatim**, except that `m.environment = 'Production'` becomes `m.environment in ('Production', 'Sandbox')`. The A60m placement stays: the test is inside `bool_or`, never in `WHERE`.

**Comment and recompute:**
- updates the `membership_state` comment (metadata only; no value change);
- recomputes the four cached columns for identities holding Sandbox rows: `posts.owner_entitled_until`, `post_shares.owner_entitled_until`, `follows.followed_entitled_until` and `account_directory.entitled_until`.

**In-transaction guards:**
- both bodies carry the new literal pair;
- the B-39 revoked conjunct is retained;
- `anon` and `authenticated` still cannot execute either function;
- stored equals recomputed on all four tables.

**No other object changes.**

## 2. Before baseline

**The "before" run uses B-39 without scope 011.**
- **Where:** a disposable local stack reset from the repository migrations **without** the scope 011 file.
- **Contents:** B-39, B-40 and B-41 are all present, as in the local tree.
- **What is recorded:** the actual `supabase_migrations.schema_migrations` last version and function fingerprint for each run.

## 3. Focused suite `supabase/tests/p5/sandbox-entitlement.sh` — 12 checks

**How it runs:**
- one rolled-back transaction per run, with fresh fixture ids;
- enforcement set on **inside** the transaction;
- client paths run as `authenticated` with actor claims;
- a state fingerprint is taken before and after.

**The two modes:**
- **before:** no migration;
- **after:** fixtures first, then the migration file inside the same transaction, so its recompute is what is tested.

| # | Check | Before | After |
|---|---|---|---|
| 1 | Active Sandbox: `connected_member` true **and** `enforcement_gate` allows as that identity | FAIL | PASS |
| 2 | Lapsed Sandbox: false, gate denies | PASS | PASS |
| 3 | Revoked Sandbox (status 5, future renewal): false | PASS | PASS |
| 4a | Sandbox billing retry within grace: true | FAIL | PASS |
| 4b | Sandbox billing retry past grace: false | PASS | PASS |
| 5 | Production entitled true / expired false (unchanged) | PASS | PASS |
| 6 | Mixed: revoked Production + live Sandbox → true (stated consequence) | FAIL | PASS |
| 7 | All **four** cached columns for an active Sandbox identity: `> now()` after recompute, then `<= now()` after its membership lapses (propagation) | FAIL | PASS |
| 8a | Cleanup authority: active Sandbox + due schedule → **not** authorised | FAIL | PASS |
| 8b | Cleanup authority: lapsed Sandbox + due schedule → authorised (unchanged) | PASS | PASS |
| 9 | `membership_state`: sandbox-only `sandbox_only`; Production `entitled` / `expired` (no new value) | PASS | PASS |
| 10 | Under enforcement: an active Sandbox identity's own directory INSERT succeeds, and an entitled viewer's search returns it | FAIL | PASS |

**Predicted:** **6 fail / 6 pass before; 12 / 12 after.** Retained-state fingerprint unchanged in both.

## 4. Legacy suites — after only, on the disposable stack with scope 011 applied

**Suite set.** Only suites with re-pointed assertions run: `u6b/acceptance.sh`, `u4/e2e.sh`, `u5/e2e.sh`, `u5/acceptance.sh` and `b39/acceptance-refund.sh` (`B39_PHASE=post`). The disposable stack is reset between suites only where a suite documents a reset precondition.

**Re-pointed, never weakened:**

| Suite | Assertion | Old | New |
|---|---|---|---|
| u6b | E5 | `false` | `true` (active Sandbox grants) |
| u6b | new E5b | — | lapsed Sandbox `false` (new fixture `V_SBL`) |
| u6b | fix1 | 8 fixtures | 9 fixtures |
| u4 e2e | E17d | `f` | `t` |
| u5 e2e | E5d-19 | `f` | `t` (predicted: the attest fixture is a live subscription) |
| u5 acceptance | A60 | `f` | `t` |
| u5 acceptance | A60f (mixed) | `f` | `t` |
| u5 acceptance | A60g (mixed) | `expired` | `entitled` |
| b39 | M1 (mixed) | `false` | `true` |
| b39 | M2 (mixed) | `expired` | `entitled` |
| b39 | M3 (mixed) | `false` | `true` |

**Unchanged and predicted to pass:** A60c (all-NULL Sandbox row), A60m (placement), A60n, every `sandbox_only` state assertion, K9/K10, and B39-M4/M5/M6.

**Predicted results:**
- every re-pointed assertion passes;
- B-39's post phase reports `PREDICTION MATCHED` (no failures);
- the other suites pass fully.

## 5. Disposable stack and retained-stack protection

**Retained baseline (recorded read-only, 2026-09-15):**

| Measure | Value |
|---|---|
| Stack | `supabase_db_rlwtqxumfobakvdueugm`, DB `127.0.0.1:54322` |
| Volumes | `supabase_db_`, `supabase_edge_runtime_` and `supabase_storage_rlwtqxumfobakvdueugm` |
| `public` function fingerprint | `62e682a79b87ed63c67919b9aa5c04ac` |
| Row counts | `users=6 membership=0 notif=0 directory=0 posts=0 privacy=0 follows=0 shadow=60`; `enforcing=false` |
| Migrations | 14 applied, last `20260914130000` |

**CLI behaviour, verified from `supabase stop --help` at 2.113.0:** data volumes are deleted only with `--no-backup`.

**Procedure:**
1. Stop the retained stack **without** `--no-backup`.
2. Copy `supabase/` (excluding `.temp`, `.branches` and `.work`) to a scratchpad workdir, and set `project_id = "motivo-scope011-disposable"`.
3. From that copy, `supabase start` and `supabase db reset --local` **without** the scope 011 file.
4. Verify: `supabase status` resolves `127.0.0.1`; exactly one `supabase_db_*` container publishes that port; and it is `supabase_db_motivo-scope011-disposable`, never the retained name.
5. Focused suite **before**; focused suite **after**.
6. Add the migration file to the copy; `supabase db reset --local` in the copy; run the legacy suites (resetting the copy between them where required).
7. `supabase stop --no-backup` in the copy only; confirm its containers and volumes are gone.
8. Restart the retained stack from the repository, and compare fingerprint, counts and migration version with §5's baseline.

**Restoration on failure.** The retained service is restarted even if any step fails: the orchestrating script restores it on every exit path.

**Stop and report if:**
- the retained stack would be reset;
- a target check fails;
- the retained baseline differs after restart;
- a valid run contradicts a prediction.

**Failed output is preserved.**

## 6. Hosted read-only checks (authorised; one submission; counts and booleans only)

**Pre-check:** confirm the linked project ref is `rlwtqxumfobakvdueugm` (`supabase/.temp/project-ref`).

**The submission returns:**
- `enforcement_active()`;
- membership rows by environment, with counts entitled now vs entitled under the scope 011 rule (evaluated as expressions);
- `pending_cleanup_at` counts (set and due), earliest date, by environment;
- `account_directory` and `auth.users` counts;
- a count of `auth.users` whose id starts with the recorded prefix `1fbf664a`, and **only if exactly 1**, that identity's row count by environment, entitled now vs after, any schedule (set, due, earliest) and directory row present.

**It returns no content, identifiers or credentials, and writes nothing.**

**Absence is not evidence of data loss.**

## 6b. Addendum before the rerun (2026-09-15): image fidelity and the R5 structural gate

**Run 1 was aborted before any test ran.**
- **Cause:** the copy excluded `supabase/.temp`, so the disposable stack pulled CLI-default images instead of the retained/production pins.
- **Images pulled vs pinned:**
  - Postgres `17.6.1.158` vs `17.6.1.063`;
  - storage-api `v1.68.10` vs `v1.68.1`;
  - postgrest `v14.16` vs `v14.1`.
- **Evidence:** preserved in `run/`, and the retained stack was restored by its exit trap.

**Rerun (`run2/`) changes:**
- **Copied into the disposable `.temp`:** only `gotrue-version`, `postgres-version`, `rest-version`, `storage-version` and `storage-migration`.
- **Never copied:** `project-ref`, `linked-project.json`, `pooler-url` or `start-secrets`.
- **Added target check:** the running db, rest, storage and auth containers must use exactly the pinned image tags.

**R5 structural gate** — `verify-baseline.sh` on the disposable stack, with scope 011 applied, against the committed production snapshot.

**Predicted gate output:**
- **Headline:** `GATE NOT MET — 6 problems`.
- **Every problem line:** `functions <name>: UNAPPROVED difference in definition`.
- **The six names:**
  - B-39: `connected_member`, `membership_entitled_until`, `membership_apply_state_v1`;
  - B-40: `account_privacy_requests_open`, `account_privacy_self_v1`, `account_privacy_upsert_v1`.
- **Other surfaces:** `function_grants` and all eight remaining surfaces are identical, except the standing `account_id_format` exception, which is detected and matched.

**Predicted scope 011 entries:**
- **No problem line of its own:** its literal pair sits inside two bodies B-39 already changes, so the gate proves that no *other* object changed.
- **Comment check:** the capture has no comment surface, so the `membership_state` comment is read from the catalog. It is predicted to contain `Scope 011 (2026-09-15)`.

**Stop rule:** any other problem line stops the run before the legacy suites.

## 7. Limits

- **Local only:** everything here is local reproduction, with no deployment.
- **Secrets:** hosted secret values cannot be validated.
- **Consequence (recorded):** an active verified Sandbox subscription can confer access when a Production subscription on the same identity has expired or been revoked. A revoked row itself never confers access.
