# U4 production deployment — P0-P10 EXECUTED, 2026-08-20

**P0-P10 HAVE BEEN RUN AGAINST PRODUCTION AND ALL PASSED, 2026-08-20.** The
schema is deployed, both Edge Functions are ACTIVE, and the B-23 gate returned
GREEN after recapture. **P11-P13 are NOT done: the Sandbox notification URL is
still unset, so Apple delivers nothing to the endpoint and no notification has
ever reached it.**

**Two results that differ from what this file predicted, both recorded rather
than smoothed over.**

**(i) P2 was not achieved and could not have been.** The package said the
`delete_account_v1` comment correction would be folded into this deploy.
`supabase functions deploy <names>` re-versioned it **7 -> 8** as predicted, and
`revoke_apple_identity_v1` **1 -> 2**, but **both bundle SHAs are UNCHANGED**
(`78b7f902...`, `e9b34aa8...`) — the CLI re-versions neighbours without
re-uploading their source. So the correction is still undeployed, and folding it
in would require deploying `delete_account_v1` by name, which is a deliberate
P0-path deploy and was outside the authorised scope. **The obligation carries
forward.**

**(ii) The identical SHAs are better evidence than the version numbers**, and
they confirm the standing rule in `supabase/README.md`: a version number is not
evidence that code changed. Nothing about either existing function moved.

**U4 IS NOT PURELY ADDITIVE, AND THAT IS THE FIRST DIFFERENCE FROM U3.** U3 could
be described as "additive and inert" without qualification. U4 **modifies four
CHECK constraints on the deployed `membership_notification` table** (B-26/B-27)
and drops one of them by name. The table holds **zero rows**, which is what makes
this cheap — but a modification is not an addition and the rollback below is
correspondingly different.

**What U4 still does NOT do.** No policy is created or changed. No grant to
`anon` or `authenticated`. No table or column privilege to any role. No worker,
no scheduler, no deletion, no client change. `ensure_membership_binding` remains
ungranted — that is U5's.

---

## 0. What is being deployed

| Artefact | |
|---|---|
| `supabase/migrations/20260820120000_u4_ingestion.sql` | B-26/B-27 amendments · `membership_notification_reject_stat` · 7 functions · 4 EXECUTE grants |
| `supabase/functions/appstore_notifications_v1/` | ASSN V2 ingestion, **unauthenticated by necessity** |
| `supabase/functions/appstore_reconcile_v1/` | App Store Server API reads, service-role only |
| `supabase/functions/_shared/appstore/` | JWS verification, derivation, API client, pinned anchor |
| `supabase/functions/deno.json` + `deno.lock` | `@peculiar/x509@1.12.3` exactly pinned, 19 packages with sha512 integrity |

---

## 1. Predicted structural delta

Measured from the local instance built from committed migrations against the
committed production snapshot. **Post-deploy recapture must match this exactly.**

| Surface | Before | After | Δ | What the delta is |
|---|---|---|---|---|
| `functions` | 14 | **21** | **+7** | The seven U4 functions |
| `function_grants` | 42 | **63** | **+21** | 7 functions × 3 roles. **Rows, not privileges** — see below |
| `columns` | 107 | **115** | **+8** | `delivery_count`, `last_received_at`, and six on the new table |
| `constraints` | 50 | **56** | **+6 net / 11 lines** | 7 added, **3 modified**, 1 dropped |
| `rls_enabled` | 12 | **13** | **+1** | `membership_notification_reject_stat`, RLS enabled |
| `policies` | 33 | **33** | **0** | **No policy is created or modified** |
| `table_grants` | 102 | **102** | **0** | **The security claim** |
| `column_grants` | 523 | **523** | **0** | **The security claim** |
| `triggers` | 5 | **5** | **0** | U4 adds no trigger |
| `storage_buckets` | 2 | **2** | **0** | Untouched |

**48 raw difference lines: 44 additive, 3 modified, 1 removed.**

### The eleven constraint lines, itemised so none is taken on trust

| Constraint | Difference |
|---|---|
| `membership_notification_reject_stat_pkey` | added |
| `..._bucket_aligned` / `..._category_check` / `..._count_positive` / `..._sample_bounded` | added |
| `membership_notification_delivery_count_positive` | added |
| `membership_notification_failure_only_when_categorised` | added |
| `membership_notification_failure_only_when_rejected` | **dropped** — renamed to the line above, because the rule it expresses changed |
| `membership_notification_outcome_check` | **modified** — `'ignored'` admitted |
| `membership_notification_failure_category_check` | **modified** — `'unmapped'`, `'not_applicable'`, `'incomplete'`, `'unestablished'` admitted |
| `membership_notification_accepted_is_complete` | **modified** — `environment` relaxed for `'ignored'` only |

### The rows that carry the security claim

**`table_grants` and `column_grants` must be byte-IDENTICAL to the pre-U4
snapshot**, exactly as at U3. U4 grants no table or column privilege to any role;
a single new row on either surface means a revoke did not take.

**Of the 21 new `function_grants` rows, exactly FOUR carry any privilege**, and
all four are `service_role`:

| Function | anon | authenticated | service_role |
|---|---|---|---|
| `membership_ingest_notification_v1` | none | none | **`eff=true direct=true`** |
| `membership_apply_reconciliation_v1` | none | none | **`eff=true direct=true`** |
| `membership_due_for_reconciliation_v1` | none | none | **`eff=true direct=true`** |
| `membership_record_reject_v1` | none | none | **`eff=true direct=true`** |
| `membership_apply_state_v1` | none | none | **none — the canonical writer is internal, and is UPDATE-ONLY** |
| `membership_resolve_binding_v1` | none | none | none |
| `membership_record_notification_v1` | none | none | none |

**All 21 must read `public_execute = false`.** Verified locally: 4 with
privilege, 0 with PUBLIC execute.

### Nothing existing may move

Verified locally and **must hold after deployment**: **zero** pre-existing
function definitions changed, **zero** pre-existing `function_grants` rows
changed, and `policies`, `triggers`, `table_grants`, `column_grants` and
`storage_buckets` byte-identical.

---

## 2. Pre-flight, immediately before anything

Read-only.

```sql
select
  (select count(*) from public.membership)              as membership_rows,
  (select count(*) from public.membership_notification) as notification_rows,
  (select count(*) from public.membership_binding)      as binding_rows,
  (select count(*) from information_schema.tables
     where table_schema='public'
       and table_name='membership_notification_reject_stat') as u4_already_applied;
```

**Hard gates:** `u4_already_applied = 0`, and **`notification_rows = 0`.** The
B-26/B-27 constraint changes are safe precisely because the table is empty; a
non-zero count means something has been writing to it and this package must stop
and be re-reasoned rather than forced.

`membership_rows` and `binding_rows` are expected to be **0** and **0** — U3 was
inert and U5 does not exist — but they are recorded rather than gated, because a
non-zero value would be a finding in its own right.

---

## 3. STOP / GO sequence

**The order encodes two real constraints and neither may be reordered for
convenience.**

| # | Step | Notes |
|---|---|---|
| **P0** | Record pre-flight values | Gates above |
| **P1** | Download-diff both existing functions — **see the corrected method in `supabase/README.md`** | **EXECUTED 2026-08-20: PASS.** A plain `git diff` cannot be empty at CLI 2.113.0 — the download returns transpiled JS. Comments and string literals survive; compare those, plus executable tokens with whitespace collapsed, against `revoke_apple_identity_v1` as an unmodified control. Result: control shows **zero** token differences and byte-identical comments; `delete_account_v1` shows **zero** executable token differences, **44/44 identical string literals**, and a **17-line comment delta that is exactly the corrected `post_comments` block**. Restore the tree with `git checkout --` afterwards |
| **P2** | **Fold the `delete_account_v1` comment correction into this deploy** | `supabase/README.md` has instructed this since 2026-08-14. U4's deploy re-versions the function regardless, so this is the "next legitimate deploy" it was waiting for |
| **P3** | `supabase secrets set` the five `APPLE_*` values | **Before the function deploy.** Setting secrets is the leading hypothesis for the observed unscoped re-versioning |
| **P4** | Apply `20260820120000_u4_ingestion.sql` to production | **Migration before function deploy**, so the functions never exist without their writers |
| **P5** | Verify §1's delta and §4's queries | Any disagreement stops the deploy |
| **P6** | `supabase functions deploy appstore_notifications_v1 appstore_reconcile_v1` | |
| **P7** | **Download-diff ALL FOUR functions** | `supabase functions deploy` is **not scoped to the function you name** — deploying `c44_exchange_probe` once re-versioned `delete_account_v1`. If a P0 function must not move, verify it explicitly rather than reasoning from the command line you typed |
| **P8** | `supabase functions list` — confirm `verify_jwt: false` on both new functions | `config.toml` pins it; confirm the deployed state agrees |
| **P9** | `./supabase/capture-schema.sh` then `./supabase/verify-baseline.sh` | **Must return GREEN** with only the standing `account_id_format` exception |
| **P10** | Commit migration + refreshed snapshot together | |
| **P11** | **S2b — set the SANDBOX notification URL (V2, version 2)** to the deployed endpoint | **STRICTLY LAST of the configuration steps.** Sandbox delivers exactly once and never retries, so a URL configured before the endpoint is live loses whatever it is sent, permanently |
| **P12** | Apple **test notification** via `appstore_reconcile_v1` `mode=request_test_notification`, then `mode=test_notification_status` | |
| **P13** | Verify the audit row, and B-28's remaining half | See §5 |

---

## 4. Post-deploy verification queries

```sql
-- 1. No non-owner grantee on ANY of the six membership tables. Covers anon,
--    authenticated, service_role AND PUBLIC in one read.
select count(*) as non_owner_privileges
  from pg_class c cross join lateral aclexplode(c.relacl) a
 where c.relnamespace='public'::regnamespace and c.relkind='r'
   and c.relname like 'membership%' and a.grantee <> c.relowner;   -- must be 0

-- 2. Exactly four U4 functions are executable by service_role, and they are
--    the four entry points. The canonical writer must NOT appear.
select p.proname
  from pg_proc p
 where p.pronamespace='public'::regnamespace and p.proname like 'membership%_v1'
   and has_function_privilege('service_role', p.oid, 'EXECUTE')
 order by 1;
-- must be exactly: membership_apply_reconciliation_v1,
--                  membership_due_for_reconciliation_v1,
--                  membership_ingest_notification_v1,
--                  membership_record_reject_v1

-- 3. No PUBLIC EXECUTE anywhere in the membership namespace.
select count(*) from pg_proc p
 where p.pronamespace='public'::regnamespace and p.proname like 'membership%'
   and exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                where a.privilege_type='EXECUTE' and a.grantee=0);   -- must be 0

-- 4. RLS on all six.
select count(*) from pg_class c
 where c.relnamespace='public'::regnamespace and c.relkind='r'
   and c.relname like 'membership%' and not c.relrowsecurity;        -- must be 0

-- 5. STILL OBSERVE-ONLY: no policy consults membership.
select count(*) from pg_policies
 where schemaname in ('public','storage')
   and (coalesce(qual,'')||coalesce(with_check,'')) ~* 'connected_member|membership';  -- 0

-- 6. U5's grant has not been made early.
select has_function_privilege('authenticated','public.ensure_membership_binding()','EXECUTE');
-- must be false
```

These are the same assertions the local suite runs as A44–A45e and A57–A57b, so
**a production result that disagrees with a green local run is itself the
finding.**

---

## 5. The acceptance-window prediction, and what it is not

**Two separate statements, and conflating them is how one of them gets read as
guaranteeing more than it does.**

**(a) PERMANENT, and true after U5 as well: U4 never originates a `membership`
row.** There is no `INSERT INTO public.membership` anywhere in the migration —
`membership_apply_state_v1` is UPDATE-only, and asserted so both behaviourally
(A47/A47b, E14e) and structurally over `pg_get_functiondef` (A47f). Ownership
establishment, and therefore `binding_method`/`bound_at`, belongs to U5.

**(b) ACCEPTANCE-WINDOW PREDICTION, U4 before U5: `select count(*) from
public.membership` remains `0`, and every notification recorded carries
`outcome='ignored'`, `failure_category='unmapped'`.** The only permitted mapping
is `appAccountToken → membership_binding.binding_token` (B-24); no Apple
subscription carries an `appAccountToken` until U5 sets one; and no binding
exists to match anyway, because `ensure_membership_binding` is ungranted until
U5. **This half becomes false the moment U5 ships, by design.** Anyone reading it
later as an invariant will conclude U5 broke something.

**If a binding somehow does exist and a token matches**, the expected record is
`outcome='ignored'`, `failure_category='unestablished'`, with `membership` still
at zero — that is (a) doing its job, and it is a finding worth investigating
rather than a failure.

**A non-zero `membership` count during the U4 window is a STOP-AND-REPORT.**
Given (a) it cannot come from ingestion or reconciliation at all, so it would
mean something wrote by a route this package does not describe.

### B-28's remaining half

**No genuine Apple-signed payload has ever been verified by this code.** The
local batteries prove the algorithm against a faithful synthetic chain, and the
**root→intermediate link against Apple's own certificates** — but the
intermediate→leaf link and the JWS signature itself are unproven against Apple.

**Apple's test notification at P12 is the first genuine Apple-signed payload this
project can legitimately obtain, and it is where B-28 discharges.** Until then
B-28 stays open. Expect at P13:

```sql
select notification_type, outcome, failure_category, delivery_count
  from public.membership_notification order by received_at desc limit 5;
-- expect: TEST / ignored / not_applicable / 1
```

**A `signature` row in `membership_notification_reject_stat` instead is the
failure this whole unit was designed to make visible** — it would mean the
verifier rejects real Apple traffic, which is precisely what the official Apple
library does on this runtime while reporting it identically to an attack.

---

## 5b. The four granted functions — audited 2026-08-20, found minimal

Recorded here as well as in the migration, because a deploy reviewer should be
able to see the whole executable surface without reading the SQL.

| Granted to `service_role` | Why it cannot be internal |
|---|---|
| `membership_ingest_notification_v1(jsonb)` | It is the entry point `appstore_notifications_v1` calls |
| `membership_due_for_reconciliation_v1(uuid, text)` | Runs **before** the Apple read. The HTTPS call sits between selection and application and must never be inside a transaction. **Narrowed in this audit** to the three columns the caller uses — it previously also returned `renewal_info_signed_date` and `pending_cleanup_at`, neither of which is read |
| `membership_apply_reconciliation_v1(uuid, text, jsonb, text)` | Runs **after** the Apple read. Same reason, other side of the network call |
| `membership_record_reject_v1(text, text)` | B-29 Tier 2, where verification failed and there is therefore no event to ingest. **Could technically fold into the ingest entry point and deliberately does not:** that would put the function able to write `membership` and `membership_notification` on the path an unauthenticated caller reaches by sending garbage. Kept separate, Tier 2 can touch nothing but the bounded aggregate. **Inputs are now validated inside the function** — a malformed digest is dropped, an unknown category normalised |

| Granted to **nobody** | |
|---|---|
| `membership_apply_state_v1` | The canonical writer. Internal, so the atomicity of the entry points and the ownership precondition cannot be bypassed |
| `membership_resolve_binding_v1` | The B-24 mapping |
| `membership_record_notification_v1` | Audit + dedupe |

**Unchanged and re-asserted:** zero table or column privilege to any role on all
six membership tables; nothing to `anon`, `authenticated` or `PUBLIC`; and
`ensure_membership_binding` still ungranted.

---

## 6. Secrets — names and shapes only

**Set by the account holder. Never written into this repository, never read by
tooling here, and deliberately not recorded anywhere in it.**

| Name | Content |
|---|---|
| `APPLE_IAP_KEY_ID` | In-App Purchase key ID (S2a) |
| `APPLE_IAP_ISSUER_ID` | Issuer ID (S2a) |
| `APPLE_IAP_P8_B64` | **base64 of the `.p8`** — base64 because a multi-line PEM in an env var gets its newlines mangled, and the resulting `importKey` failure looks nothing like its cause |
| `APPLE_IAP_BUNDLE_ID` | `com.sdsongs.etudes` — **separate from `APPLE_CLIENT_ID`** on purpose; they hold the same value today but mean different things, and coupling them means a future SIWA change silently breaks IAP |
| `APPLE_ASSN_ALLOWED_ENVIRONMENTS` | `Sandbox` — so a stray Production notification is recorded and refused rather than applied |

**`APPLE_API_BASE_URL_SANDBOX` and `APPLE_API_BASE_URL_PRODUCTION` must remain
UNSET in production.** They exist for local stubs and for Q5/Q6. Confirm with
`supabase secrets list`.

---

## 7. Rollback

**Different from U3's, because U4 modified deployed objects.**

The additive half reverses cleanly:

```sql
drop function if exists public.membership_ingest_notification_v1(jsonb);
drop function if exists public.membership_apply_reconciliation_v1(uuid, text, jsonb, text);
drop function if exists public.membership_due_for_reconciliation_v1(uuid, text);
drop function if exists public.membership_record_reject_v1(text, text);
drop function if exists public.membership_record_notification_v1(jsonb);
drop function if exists public.membership_apply_state_v1(uuid, text, text, jsonb, uuid);
drop function if exists public.membership_resolve_binding_v1(uuid);
drop table if exists public.membership_notification_reject_stat;
alter table public.membership_notification
  drop column if exists delivery_count,
  drop column if exists last_received_at;
```

**The constraint half is a restoration, not a drop**, and it is only safe while
`membership_notification` is empty — restoring the narrower CHECKs over rows
carrying `'ignored'` would fail. Restore the four U3 definitions verbatim from
`supabase/migrations/20260816120000_u3_membership_schema.sql`.

**And undo S2b first.** If the sandbox notification URL still points at a
withdrawn endpoint, Apple's single delivery attempt goes nowhere and cannot be
retried.
