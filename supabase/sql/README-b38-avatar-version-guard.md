# B-38 — `account_directory.avatar_version` becomes server-derived

**Prepared 2026-09-20. Samuel AUTHORISED this deployment on 2026-09-20, and Codex reviewed this
exact text; Claude applies it to the linked production project.** This record exists so the apply
is the reviewed text and nothing else. The apply itself is recorded in "Apply record" below.

## The defect

`authenticated` holds **table-level** INSERT and UPDATE on `public.account_directory`, and the
stamping trigger `tg_directory_avatar_version` is `BEFORE UPDATE OF avatar_key`. A PATCH that
sets `avatar_version` **without** touching `avatar_key`, or an INSERT that supplies one, is
therefore stored as sent.

**The consequence is narrow and was measured:** the owner-bound update policy confines it to the
member's **own** row, so a member can only perturb caching of **their own** avatar. No other
member's data is reachable and no privilege is gained. **A genuine avatar replacement still
re-stamps**, because changing `avatar_key` fires the trigger.

**A column-level revoke would NOT fix it:** a table-level privilege covers every column. B-14's
precedent (`2026-08-13-follows-update-column-privileges.sql`) replaced the table grant with
per-column grants, which here would have to enumerate every column the client writes, including
two legacy preference columns older builds may still send. **That is broader than B-38.**

## The change

`2026-09-20-b38-avatar-version-guard.sql`, sha256
`11b7499d901bea65193453f35497a28c2300f0e57f7864ffcb262966b905e688` (its **executable body**,
between the markers, is `e6fcf156089c791a7375c923277f4fba88fda5e82523fbaa39b30b5f852ecbf8` — the
reviewed text, unchanged; only the header comment names the authorisation).

- **`public.tg_guard_avatar_version()`** — plpgsql, `search_path = ''`, **not** SECURITY DEFINER,
  EXECUTE revoked from `public`, `anon`, `authenticated` and `service_role`.
  - **INSERT:** `new.avatar_version := null` (the column is nullable with no default, and no
    writer supplies a value).
  - **UPDATE:** `new.avatar_version := old.avatar_version`.
- **Trigger `tg_directory_avatar_guard`** — `BEFORE INSERT OR UPDATE … FOR EACH ROW`. It fires
  **before** `tg_directory_avatar_version`, because same-timing row triggers run in name order,
  so an `avatar_key`-targeted update is still re-stamped to `now()`.
- **The stamping trigger, table grants, policies and the column are untouched.**

**One submission, guarded inside the transaction, ending in a SELECT that returns a row.** PRE
asserts the relation by `regclass`, the absence of both new objects, the stamping trigger's exact
definition, enabled state and bound function, and that `avatar_version` is nullable `timestamptz`
with no default. POST asserts the new function's attributes and that no client or service role can
execute it, the guard trigger's exact definition, the stamping trigger unchanged, and the trigger
name order. Every comparison uses `IS DISTINCT FROM`.

**Rollback:** `2026-09-20-b38-avatar-version-guard-rollback.sql`, sha256
`6733c6bc186775f65f869db7d4e6b358e6eebf30ee28b3770005dde65df2fd70` (body
`fc83a09ddb4ac66a941b75215994ecf7ead8d550ba662421410d1b1040fd5e2a`, unchanged). It drops the trigger and the
function, then asserts both are gone and that the stamping trigger is exactly as before.

## Predicted structural delta (`supabase/schema/`)

| Surface | Predicted |
|---|---|
| `functions.json` | **+1** — `tg_guard_avatar_version` |
| `triggers.json` | **+1** — `tg_directory_avatar_guard` on `account_directory` |
| `function_grants.json` | **+3 rows** — one per client role for the new function, each `can_execute`, `direct_execute` and `public_execute` **false** (identical in shape to `tg_stamp_avatar_version`'s three rows) |
| `columns`, `constraints`, `policies`, `rls_enabled`, `table_grants`, `column_grants`, `storage_buckets` | **IDENTICAL** |

Recapture with `./supabase/capture-schema.sh` after the apply, and the committed diff is the
record of what changed.

**Local replay:** `supabase/migrations/20260920120000_b38_avatar_version_guard.sql` mirrors the
same objects so a rebuilt local baseline reproduces them and the B-23 gate stays meaningful. The
guards and assertions live in the production script; **this project does not use
`supabase db push`.**

## Preflight evidence, 2026-09-20

### 1. Fresh production parity: CONFIRMED

`./supabase/capture-schema.sh` (linked; structure only, reads no user table) produced **an empty
diff** against the committed snapshot. Production is exactly what `supabase/schema/` records.

### 2. B-23 gate, FIRST RUN: GATE NOT MET — 8 problems

**Raw log: `evidence/b38-b23-gate-before-replay.log`.** The failure is recorded as a failure, and
was **not** waived.

| # | Surface | Difference |
|---|---|---|
| 1–3 | `functions` `account_privacy_requests_open`, `account_privacy_self_v1`, `account_privacy_upsert_v1` | Production: `age_band <> 'band_13_17'`. Local: the older CP-1/CP-2 form `not (age_band='band_13_17' and …_set_under_band='band_18_plus')` |
| 4 | `functions` `connected_member` | Production: `m.environment in ('Production', 'Sandbox')`. Local: `= 'Production'` |
| 5 | `functions` `membership_entitled_until` | The same environment difference |
| 6 | `constraints` `connected_attachments_list_metadata` | Present in production, **absent locally** |
| 7 | `constraints` `connected_attachments_supported_mime_types` | Production includes `application/vnd.etudes.list+json` |
| 8 | `storage_buckets` `attachments.allowed_mime_types` | The same list type, present in production only |

**Two of these are directly relevant to B-38's neighbourhood** — `membership_entitled_until` feeds
`tg_set_entitled_until`, the other BEFORE INSERT OR UPDATE trigger on this table, and
`connected_member` governs the gate in its insert policy. **The earlier note calling all eight
"unrelated" was wrong and is withdrawn.**

### 3. Cause: the LOCAL database was behind three reviewed migrations

`supabase migration list --local` showed three local files never applied to the local database:
- `20260915150000_b40_teen_follow_requests_closed.sql` (explains 1–3);
- `20260915160000_scope011_verified_sandbox_entitlement.sql` (explains 4–5);
- `20260917120000_connected_lists_mime.sql` (explains 6–8).

**Every difference is local drift behind production. No production object was unexpected, and
nothing in production needed repair.**

### 4. Bounded, non-destructive repair: replay, no reset

`supabase migration up --local` applied exactly those three reviewed migrations. **No
`db reset`, no wipe.** Local test data was identical before and after: **10 `auth.users`, 0
`account_directory` rows.**

### 5. B-23 gate, SECOND RUN: GATE MET

**Raw log: `evidence/b38-b23-gate-after-replay.log`.** All ten surfaces identical except the
**single standing, mechanically verified exception** `account_directory/account_id_format`
(catalog serialization: production stores a left-nested two-way AND, local a flat three-way AND;
logically identical). **This is local fidelity, not production verification.**

### 6. Local proof, re-run on the now-faithful stack: 14/14 PASS

The earlier run was on the drifted stack; **it was re-run after the replay** and is the evidence
of record (`evidence/b38-local-proof.out`, sha256
`acbac3480b1247fd3ed5eb5fa1b0255f095034c98b1b76a1377d61d1d49d17d5`; re-run once more through the
packaged harness, which resolves its sibling SQL from its own path and accepts an output path).
- One outer transaction ending in `ROLLBACK`, running the **exact** apply and rollback bodies
  extracted verbatim from the two SQL files (`evidence/b38-local-proof-harness.py`; apply body
  `e6fcf156…`, rollback body `fc83a09d…`).
- Each re-stamp or "unchanged" assertion first set a distinguishable old value, so a stamp that
  did nothing could not pass.
- Covered: the baseline defect, an owner's direct write ignored, neighbouring fields, a client
  upsert carrying the column, a real and a same-value `avatar_key` change (both re-stamp), a
  privileged direct write, key plus version together, the cleanup writer, `entitled_until`,
  inserts as both roles, and the rollback restoring grants, the stamping trigger and the original
  behaviour.
- **Local database unchanged afterwards:** 10 users, 0 directory rows, no guard, no synthetic rows.

**Preflight reviewed and accepted by Codex on 2026-09-20.**

## Consequence to accept deliberately

**The guard applies to EVERY role, including `service_role` and `postgres`.** After this,
`avatar_version` can only change through an `avatar_key`-targeted update. No current writer needs
anything else — the only server writers of this table set `entitled_until` (a trigger) or clear
`avatar_key` (`membership_cleanup_v1`). **A future backfill would have to disable this trigger
deliberately.**

## Apply record — 2026-09-20, APPLIED TO PRODUCTION

**Authorised by Samuel; the exact reviewed text was applied by Claude to the linked project
`rlwtqxumfobakvdueugm`.** No behavioural fixture was created and nothing was deleted: the change
is DDL only.

1. **Pre-apply parity re-check:** `./supabase/capture-schema.sh` → **empty diff**, and the script's
   sha256 re-verified as `11b7499d…`.
2. **Apply:** `supabase db query --linked -f supabase/sql/2026-09-20-b38-avatar-version-guard.sql`,
   one submission. **Scored on the RESPONSE BODY, not the exit code** (the CLI exits 0 even on an
   error), and the body carried the final SELECT:

   ```json
   "rows": [ { "guard_triggers": 1, "result": "B-38 applied" } ]
   ```

   **That row is the proof the intended text ran.** A bare success message would not have been.
3. **Recapture:** `./supabase/capture-schema.sh`. The snapshot diff is **exactly the prediction**,
   **32 insertions, 0 deletions, 0 modifications**, in three files:
   - `functions.json` **+1**: `tg_guard_avatar_version`, `security_definer: false`,
     `SET search_path TO ''`;
   - `triggers.json` **+1**: `CREATE TRIGGER tg_directory_avatar_guard BEFORE INSERT OR UPDATE ON
     public.account_directory FOR EACH ROW EXECUTE FUNCTION tg_guard_avatar_version()`,
     `tgenabled: "O"`;
   - `function_grants.json` **+3**: `anon`, `authenticated`, `service_role`, each with
     `can_execute`, `direct_execute` and `public_execute` **false**.
   - `columns`, `constraints`, `policies`, `rls_enabled`, `table_grants`, `column_grants` and
     `storage_buckets`: **untouched**.
4. **Local fidelity after the apply:** the replay migration was applied with
   `supabase migration up --local` (no reset; local test data unchanged at 10 users, 0 directory
   rows), and **the B-23 gate returned GATE MET** against the recaptured production snapshot, with
   only the standing `account_id_format` exception. Log:
   `evidence/b38-b23-gate-after-apply.log`.

**Rollback remains available:** `2026-09-20-b38-avatar-version-guard-rollback.sql`. Run it as one
submission and recapture; the diff must return to the pre-apply snapshot.

**Not verified by this record:** any device or behavioural observation in production. The change
is structural, and its behaviour is evidenced by the local proof.

## Apply procedure (as followed; kept for the rollback path)

1. Re-run `./supabase/capture-schema.sh` and confirm the diff is still empty. **If it is not,
   stop:** the PRE guards encode the snapshot and the apply will refuse anyway.
2. Apply `2026-09-20-b38-avatar-version-guard.sql` as **one submission**. **A success message is
   not evidence that the intended text ran** — the final SELECT must return `B-38 applied` with
   `guard_triggers = 1`.
3. Recapture and confirm the diff is **exactly** the predicted delta above.
4. If anything deviates, run the rollback file and recapture to an empty diff.
