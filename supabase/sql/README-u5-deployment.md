# U5 production deployment — EXECUTED AND ACCEPTED, 2026-08-23

**The prediction below was committed BEFORE any production mutation**, in the
U3/U4 discipline, and is left unedited. **P0-P8 AND P6b HAVE NOW RUN AND ALL
PASSED — see §8.** Every predicted number matched production exactly; nothing was
repaired forward.

**Local evidence — 547 assertions green (updated 2026-08-23 with B-32's 25):**
U3 97 · U4 73 + 96 + 43 · U5 68 (U5c modules) + 53 (U5e/U5f client structural) +
55 (U5b acceptance) + 62 (U5d e2e). Client: 15 unit tests, Debug and Release
clean. **B-23 delta unchanged at 20**, so B-32 added no schema surface.

---

## 0. BLOCKER FOUND AT PRE-FLIGHT — `supabase db push` IS NOT THE MECHANISM

**Discovered 2026-08-23 by a genuine dry run, before any mutation.**

```
$ supabase db push --dry-run
Would push these migrations:
 • 20260816000000_baseline_production_reproduction.sql
 • 20260816120000_u3_membership_schema.sql
 • 20260820120000_u4_ingestion.sql
 • 20260823120000_u5b_establishment.sql
```

**IT WOULD REPLAY ALL FOUR, INCLUDING THE BASELINE REPRODUCTION AND THE
ALREADY-DEPLOYED U3 AND U4.** Production's `supabase_migrations.schema_migrations`
records none of them, because U3 and U4 were applied directly by the account
holder rather than through `db push` — and the baseline migration exists only to
rebuild a LOCAL reproduction and must never touch production at all.

**Consequences if it were run:** at best it fails partway on objects that already
exist, leaving the migration history half-written; at worst the baseline
reproduction executes against a live database. Neither is acceptable and neither
is recoverable by re-running.

**This is exactly the "do not silently improvise a production SQL mechanism"
case.** The U5b migration must be applied the same way U3 and U4 were: as one
atomic transaction executed by the account holder. §3 gives that procedure
verbatim.

**A second consequence, and it is the reason this is a finding rather than a
note:** the same command would have been the obvious thing to reach for at U6 or
U7 by someone who had not read this. `supabase/README.md` now carries a standing
warning.

### What this environment can and cannot do

| | |
|---|---|
| Management API — `functions list`, `functions deploy`, `secrets set` | **Available** |
| Production **SQL**, read or write | **NOT available.** No `psql`, no arbitrary-SQL CLI path, and `db push` is unusable per above |

**So the read-only DB pre-flight in §2 CANNOT be executed from here either**, and
its hard gates are unverified. They must be run by the account holder and their
output compared against §2 before anything in §3 proceeds.

---

## 1. PREDICTED B-23 DELTA — measured, not estimated

Measured by building the local instance from committed migrations and running the
gate against the committed production snapshot. **20 problems, every one a U5b
object.** Identical to the figure measured at U5b, which is how "U5c, U5d, U5e
and U5f added no schema surface" is checked rather than asserted.

| Surface | Delta | Detail |
|---|---|---|
| `columns` | **+7** | `membership_binding_conflict` |
| `constraints` | **+5** | pkey, user FK, and three CHECKs |
| `rls_enabled` | **+1** | RLS on the new table |
| `functions` | **+1 new, 2 MODIFIED** | `membership_establish_v1` new; `connected_member` and `membership_state` **replaced** |
| `function_grants` | **+3 new, 1 MODIFIED** | three rows for `membership_establish_v1`; `ensure_membership_binding`/`authenticated` flips `can_execute` false → **true** |
| `table_grants` | **0** | IDENTICAL |
| `column_grants` | **0** | IDENTICAL |
| `policies` | **0** | IDENTICAL — **U5 enforces nothing** |
| `triggers`, `storage_buckets` | **0** | IDENTICAL |

**U5 IS NOT PURELY ADDITIVE.** Like U4 — which modified four CHECK constraints —
it **modifies deployed objects**: two function definitions and one grant row. The
rollback in §6 is correspondingly not "drop what was added".

**The `account_id_format` constraint pair in the raw diff is NOT U5's.** It is the
single declared standing exception in `baseline-exceptions.json`, a PostgreSQL
parenthesisation normalisation, detected and approved by the gate. Counting it
would overstate the delta by one.

### Privilege delta — the whole of it is two grants

```sql
grant execute on function public.ensure_membership_binding()  to authenticated;
grant execute on function public.membership_establish_v1(...) to service_role;
```

`ensure_membership_binding()` becomes **the only client-reachable membership
object in the system**, and it is the narrowest shape the design admits: no
argument, identity from `auth.uid()`, idempotent, at most one row per
`auth.users` row. **No table or column privilege is granted to any role.** U3's
A3f invariant — no grantee other than the owner in `relacl` for any membership
table — survives U5 unchanged.

---

## 2. PRE-FLIGHT — READ-ONLY, and every gate is a STOP

Run by the account holder. **Any unexpected value is stop-and-report, not
something to normalise.**

```sql
select
  (select count(*) from public.membership)                    as membership_rows,
  (select count(*) from public.membership_binding)            as binding_rows,
  (select count(*) from public.membership_notification)       as notification_rows,
  (select count(*) from public.membership_notification_reject_stat) as reject_stat_rows,
  (select count(*) from public.membership_cutover)            as cutover_rows,
  (select count(*) from information_schema.tables
     where table_schema='public'
       and table_name='membership_binding_conflict')          as u5_already_applied,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname='public' and p.proname='membership_establish_v1') as u5_fn_present,
  (select count(*) from pg_policies
     where schemaname in ('public','storage')
       and (coalesce(qual,'')||coalesce(with_check,'')) ~* 'connected_member|membership')
                                                              as policies_enforcing,
  (select count(*) from pg_policies where schemaname in ('public','storage')) as total_policies,
  (select count(*) from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public','storage') and not t.tgisinternal)
                                                              as triggers_in_scope,
  (select has_function_privilege('authenticated',
            'public.ensure_membership_binding()','EXECUTE'))   as binding_already_granted;
```

| Gate | Required | If not |
|---|---|---|
| `u5_already_applied` | **0** | U5 is already applied — STOP |
| `u5_fn_present` | **0** | as above |
| `binding_already_granted` | **false** | the grant exists already — STOP |
| `membership_rows` | **0** | **STOP AND REPORT.** U4 cannot create rows and U5 does not exist yet, so a row means something unmodelled has written. Only genuine Apple traffic *plus* a matching notification row could explain it, and that combination still needs explaining before deploying |
| `binding_rows` | **0** | as above — nothing has been able to mint one |
| `policies_enforcing` | **0** | enforcement exists — STOP, U6 has not begun |
| `total_policies` | **33** | the policy surface moved — STOP |
| `notification_rows` | **accounted for, NOT a fixed number** | See "the two gates corrected" below. A static count was wrong by construction |
| `reject_stat_rows` | **0** | any signature failure since U4 is a finding |
| `cutover_rows` | **16** | the frozen snapshot. Any other value contradicts U3's verified population |
| `triggers_in_scope` | **5** | public+storage only, matching `capture-schema.sh`. Triggers in `auth`, `realtime`, `vault`, `cron` and `net` are platform-managed and outside B-23's captured surface **by design** |

### THE TWO GATES ABOVE WERE BOTH DEFECTIVE, AND BOTH DEFECTS WERE MINE

**Executed 2026-08-23. Production was correct on both counts; the package was
not.** Recorded here rather than silently amended, because the second one is a
mistake worth not repeating.

**`triggers_total` — wrong query.** The expectation of 5 came from
`supabase/schema/triggers.json`, which `capture-schema.sh` scopes to
`('public','storage')`. The gate I wrote counted `pg_trigger` across **every
schema**. The two measured different things, so 6-vs-5 was never a valid
comparison. Production's sixth is **`realtime.tr_check_filters` on
`realtime.subscription`** — Supabase platform-managed, in a schema B-23
deliberately does not capture. **Not drift.** The public/storage set is exactly
the expected five.

**`notification_rows = 1` — wrong KIND of gate, which is the more instructive
error.** U4 is live and receiving genuine Apple Sandbox traffic, so a fixed count
was guaranteed to go stale the moment Device A bought a subscription at F3b. **A
pre-flight gate on a table that legitimately grows must assert that every row is
ACCOUNTED FOR, never that a particular number of them exist.** The replacement:

```sql
-- Every row must be an ignored Sandbox notification for a known subscription.
select count(*) filter (where outcome <> 'ignored')            as non_ignored,          -- 0
       count(*) filter (where environment is distinct from 'Sandbox'
                          and notification_type <> 'TEST')     as non_sandbox,          -- 0
       count(distinct original_transaction_id)                 as distinct_subscriptions,
       coalesce(max(delivery_count), 1)                        as max_delivery_count,   -- 1
       count(*)                                                as total
  from public.membership_notification;
```

**Gates: `non_ignored = 0`, `non_sandbox = 0`, `max_delivery_count = 1`, and every
distinct `original_transaction_id` explicable by known device QA.** `total` is
recorded, never gated.

**EXECUTED RESULT, 2026-08-23 — all gates pass.** 14 rows, and they reconcile to
exactly one subscription lifecycle plus U4i's keystone:

| Rows | Shape |
|---|---|
| 1 | `TEST` / `ignored` / `not_applicable` — U4i, 2026-08-20 17:48:30 |
| 1 | `SUBSCRIBED` / **`RESUBSCRIBE`** / `ignored` / `unmapped` |
| 11 | `DID_RENEW` / `ignored` / `unmapped` |
| 1 | `EXPIRED` / `VOLUNTARY` / `ignored` / `unmapped` |

All Sandbox, all `original_transaction_id = 2000001220187383` — **F3b's own
recorded value** — `max_delivery_count = 1`, `non_ignored = 0`,
`distinct_subscriptions = 1`, `reject_stat_rows = 0`.

**`unmapped` on all thirteen is the load-bearing part**, not incidental: it is
U4's acceptance-window prediction holding exactly. No Apple subscription carries
an `appAccountToken` until U5 ships, so nothing can map, and `membership_rows = 0`
follows. An `applied` row would have meant something bound a subscription while
U5 did not exist.

**MY PREDICTED COMPOSITION WAS WRONG WHILE THE TOTAL WAS RIGHT, AND THAT IS THE
WARNING.** I predicted 1 TEST + 1 initial + **12 renewals** = 14. The truth is 1
TEST + 1 initial + **11 renewals + 1 EXPIRED** = 14. **A matching total reached by
wrong reasoning is exactly the kind of agreement that should not be trusted**, and
it is only the row-level breakdown that settled it.

### THE INDEPENDENT APPLE CROSS-CHECK COULD NOT BE COMPLETED — B-32

`appstore_reconcile_v1 mode=notification_history` returned
`apple_notification_count: 0` for a window that provably contains Apple's own TEST
notification. **The zero is a defect in our tooling, not an answer from Apple:**
the mode reads a `notificationUUID` field that `NotificationHistoryResponseItem`
does not have, so it reports zero whatever Apple sent. Filed as **B-32**.

**This does not block U5 deployment, and the reason is structural rather than
convenient:** U5's establishment performs its own live authoritative Apple read
and never consults notification history, so a blind diagnostic cannot mislead it.
**It does block G3**, which is U4-owned and already outstanding.

**CORRECTED LOCALLY 2026-08-23, and folded into this deploy** rather than carried
through it. 25 deterministic assertions (U4b-49..73) cover the real uuid, the
uuid SET across multiple items, hostile validly-*shaped* but not validly-*signed*
payloads, a mixed page proving contamination runs in neither direction, and the
`0 items / 0 unverifiable` pair the old code could never express. **B-32 is NOT
production-resolved and G3 is NOT closed** until **P6b** reconciles a real Apple
history against `membership_notification`.

### CONSEQUENCE FOR DEVICE QA — F3b's SUBSCRIPTION HAS EXPIRED

The `EXPIRED`/`VOLUNTARY` row is not merely bookkeeping. **Device A's Sandbox
subscription from F3b ended around 2026-08-21**, after 1 purchase + 11 hourly
renewals — consistent with Apple's documented sandbox cap of up to 12 renewals
before auto-renewal turns off.

**So it CANNOT be reused for S-1, S-2, B-24n, G11 or F10.** Every one of those
needs a live entitlement, and the fixture is spent. §7's plan must assume a fresh
Sandbox purchase, and the first purchase after U5 ships will be **bound at source**
— which conveniently makes it B-24n's evidence, but means **S-2's legacy claim now
needs a deliberately token-less subscription**, i.e. one purchased *before* U5f's
client reaches the device.

**Also observed and worth recording:** the initial notification was
`SUBSCRIBED`/**`RESUBSCRIBE`**, not `INITIAL_BUY`, so the sandbox tester had
subscribed before. Consistent with the rig's history and unremarkable in itself,
but it means this tester can no longer produce a clean first-purchase
observation.

**Also confirm, from `supabase functions list` (already captured 2026-08-23):**

| Function | Expected | Observed at package time |
|---|---|---|
| `delete_account_v1` | v8, `verify_jwt:false`, sha `78b7f902…` | **matches** |
| `revoke_apple_identity_v1` | v2, `verify_jwt:false`, sha `e9b34aa8…` | **matches** |
| `appstore_notifications_v1` | v1, `verify_jwt:false`, sha `0a10cf63…` | **matches** |
| `appstore_reconcile_v1` | v1, `verify_jwt:false`, sha `6de05502…` | **matches** |

**And confirm no worker/scheduler exists** — U7 has not begun:

```sql
select count(*) as scheduled_jobs
  from pg_class where relname in ('job','job_run_details');   -- pg_cron: expect 0
select count(*) as membership_scheduled
  from public.membership where pending_cleanup_at is not null; -- must be 0
```

---

## 3. DEPLOYMENT ORDER — and the two account-holder steps

**The order encodes real constraints and must not be reordered around a blocker.**

| # | Step | Who | Notes |
|---|---|---|---|
| **P0** | Pre-flight §2 | **Account holder** | Every gate. Any surprise stops the deploy |
| **P1** | Download-diff all four live functions | Either | Corrected transpilation-aware method in `supabase/README.md`. `revoke_apple_identity_v1` is the control |
| **P2** | `supabase secrets set APPLE_ATTEST_ALLOWED_ENVIRONMENTS=Sandbox` | Either | **BEFORE the function deploy.** Never rely on the code default. **This is known to re-version unrelated functions** — P5 accounts for it |
| **P3** | **Apply the U5b migration atomically** | **ACCOUNT HOLDER ONLY** | §3.1. **NOT `supabase db push`** — see §0 |
| **P4** | Verify §1's delta and §5's queries | **Account holder** | Any disagreement stops the deploy |
| **P5** | `supabase functions deploy membership_attest_v1 appstore_reconcile_v1` | Either | **Both, deliberately** — see §4. `appstore_reconcile_v1` carries **two** changes: U5c's `api.ts` and **B-32's corrected `notification_history`** |
| **P6** | Download-diff **all five** functions | Either | Deploy is not scoped to what you name. **`appstore_reconcile_v1` MUST show the B-32 delta** — if its diff looks like transpilation alone, the corrected source did not ship |
| **P6b** | **Re-run the B-32 cross-check that failed at pre-flight** | Either | `mode=notification_history`, Sandbox, 2026-08-19..24. **Expect ~14 uuids reconciling against `membership_notification`, `unverifiable_items: 0`.** A second `0` means the fix did not deploy. **This is the step that closes B-32 and unblocks G3** |
| **P7** | `supabase functions list` — `verify_jwt:false` on `membership_attest_v1` | Either | `config.toml` pins it; confirm deployed state agrees |
| **P8** | `./supabase/capture-schema.sh` then `./supabase/verify-baseline.sh` | Either | **Must return GREEN**, only the `account_id_format` exception |
| **P9** | Commit migration + refreshed snapshot + results together | Either | |
| **P10** | **STOP.** No device action | — | Genuine Sandbox QA needs the account holder present |

### 3.1 The migration, as ONE atomic transaction

Run in the Supabase SQL editor (or `psql`) by the account holder. The file is
`supabase/migrations/20260823120000_u5b_establishment.sql`, applied **verbatim**,
wrapped so that a partial application is impossible:

```sql
BEGIN;
-- paste the ENTIRE contents of
--   supabase/migrations/20260823120000_u5b_establishment.sql
-- unmodified, then:
COMMIT;
```

**Do not `CASCADE` anything. Do not edit the file to make a statement succeed.**
A statement that fails means the analysis was wrong; `ROLLBACK` and report.

**The migration is safe to wrap in one transaction** because it is pure DDL plus
grants — no `CONCURRENTLY`, no `VACUUM`, nothing that forbids a transaction block.

---

## 4. WHY `appstore_reconcile_v1` IS REDEPLOYED — NOW TWO REASONS

**Reason 2, added 2026-08-23: it carries the B-32 correction.** Its
`notification_history` mode reported `apple_notification_count: 0`
unconditionally — it read a `notificationUUID` field that
`NotificationHistoryResponseItem` does not have. The fix reads the UUID from the
**verified** signed payload via the new `_shared/appstore/history.ts`, counts
unverifiable items instead of dropping them, and surfaces `hasMore` /
`paginationToken`.

**This is folded into the redeploy this package already required, deliberately.**
Deploying a knowingly-broken diagnostic and correcting it afterwards would mean
two production mutations where one will do, and would leave G3 unscoreable across
the whole Sandbox window in between.

**Files in this function's deploy:** `appstore_reconcile_v1/index.ts`,
`_shared/appstore/api.ts` (U5c), **`_shared/appstore/history.ts` (NEW, B-32)`**.

### The original reason, unchanged

U5c **modified `_shared/appstore/api.ts`** (adding `setAppAccountToken`, the
`allowEmptyBody` parameter, the PUT method and the error taxonomy). Import graph:

| Function | Imports | Bundle changes? |
|---|---|---|
| `appstore_reconcile_v1` | `api.ts`, `derive.ts`, `jws.ts` | **YES — api.ts changed** |
| `appstore_notifications_v1` | `derive.ts`, `jws.ts` only | **No** |
| `membership_attest_v1` | `api.ts`, `attest.ts` | new |

**So a deployed U4 function's bundle changes as a side effect of U5c**, and
leaving it stale would create exactly the repo-vs-production divergence
`supabase/README.md` exists to prevent. It is redeployed deliberately.

**Its behaviour is unchanged and that is the reason this is safe:** every `api.ts`
change is additive with a default — `allowEmptyBody` defaults to `false`, so
`request()` behaves identically for every existing caller, and `setAppAccountToken`
has no caller in that function. U4's 48 module and 43 e2e assertions cover the
unchanged paths and are green.

---

## 5. POST-DEPLOY VERIFICATION — prove, do not state

```sql
-- 1. No non-owner grantee on ANY membership table. Covers anon, authenticated,
--    service_role AND PUBLIC in one read.  MUST BE 0.
select count(*) as non_owner_table_privileges
  from pg_class c cross join lateral aclexplode(c.relacl) a
 where c.relnamespace='public'::regnamespace and c.relkind='r'
   and c.relname like 'membership%' and a.grantee <> c.relowner;

-- 2. EXACTLY the intended executable surface.
select p.proname,
       has_function_privilege('anon',          p.oid,'EXECUTE') as anon,
       has_function_privilege('authenticated', p.oid,'EXECUTE') as authenticated,
       has_function_privilege('service_role',  p.oid,'EXECUTE') as service_role,
       exists (select 1 from aclexplode(p.proacl) a
                where a.privilege_type='EXECUTE' and a.grantee=0) as public_execute
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname like 'membership%' or p.proname='connected_member'
 order by 1;
-- REQUIRED:
--   ensure_membership_binding   authenticated=true, anon=false, service_role=false
--   membership_establish_v1     service_role=true,  anon=false, authenticated=false
--   membership_apply_state_v1   ALL false  (U4's canonical writer stays internal)
--   membership_resolve_binding_v1 ALL false
--   membership_record_notification_v1 ALL false
--   connected_member            ALL false
--   public_execute              false on EVERY row

-- 3. Ownership provenance cannot be supplied by a client parameter.
select count(*) as provenance_parameters
  from information_schema.parameters
 where specific_schema='public'
   and specific_name like 'membership_establish_v1%'
   and parameter_name ilike '%binding_method%';        -- MUST BE 0

-- 4. Establishment cannot schedule cleanup.
select count(*) as scheduled_rows
  from public.membership where pending_cleanup_at is not null;   -- MUST BE 0

-- 5. Exactly ONE function inserts into public.membership, and it is the
--    establishment writer.
select p.proname
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.prokind='f'
   and pg_get_functiondef(p.oid) ~* 'insert into public\.membership *\(';
-- MUST return exactly: membership_establish_v1

-- 6. Still no enforcement, still no cleanup.
select (select count(*) from pg_policies
         where schemaname in ('public','storage')
           and (coalesce(qual,'')||coalesce(with_check,'')) ~* 'connected_member|membership')
       as policies_enforcing,                                   -- MUST BE 0
       (select count(*) from pg_policies
         where schemaname in ('public','storage')) as total_policies;  -- MUST BE 33

-- 7. Sandbox does not confer Production entitlement, and sandbox_only is honest.
--    Run against a scratch identity ONLY if one exists; otherwise this is
--    covered by the 55 local acceptance assertions and is not re-proved here.
```

**`membership_state()` must report five values, not four** — `entitled`,
`expired`, `sandbox_only`, `grandfathered`, `unknown`. Verify the definition
contains `sandbox_only`:

```sql
select pg_get_functiondef(p.oid) ~ 'sandbox_only' as has_fifth_state
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname='membership_state';   -- MUST BE true
```

---

## 6. ROLLBACK — not "drop what was added"

U5 **modifies** two function definitions and one grant, so a full rollback must
**restore** them, not merely drop the new objects.

```sql
BEGIN;

-- 1. Drop what U5 added.
drop function if exists public.membership_establish_v1(uuid, text, text, uuid, uuid, jsonb);
drop table    if exists public.membership_binding_conflict;

-- 2. Restore the grant U5 changed.
revoke execute on function public.ensure_membership_binding() from authenticated;

-- 3. Restore the two MODIFIED functions to their U3 definitions, by pasting the
--    `create function public.connected_member` and `create function
--    public.membership_state` blocks from
--    supabase/migrations/20260816120000_u3_membership_schema.sql
--    as CREATE OR REPLACE. Their ACLs are preserved across a replace, so no
--    re-grant is needed.

COMMIT;
```

**Then redeploy the previous `appstore_reconcile_v1`** from the commit preceding
U5c, and delete `membership_attest_v1`. **The client needs no rollback**: U5e/U5f
call an endpoint that would simply return 404, and the attestation coordinator
treats that as `serverError` — no membership is claimed, no mode changes, and
nothing local is touched.

**The secret may be left in place.** It is inert without the function.

---

## 7. EXPLICIT PREDICTIONS FOR THE FIRST GENUINE SANDBOX RUN

Committed now so the run is scored rather than interpreted. **None of these is
verifiable locally** — that is the whole reason they are listed.

| # | Prediction |
|---|---|
| **S-1** | A real `currentEntitlements` JWS from Device A passes the **pinned Apple Root CA G3**. Local evidence used a test CA, so a dead verifier and a green endpoint are indistinguishable until this runs |
| **S-1b** | The claim boundary accepts it: `bundleId`, product, and `Sandbox` environment all match |
| **B-24n** | The **new-purchase** path returns `established` with `binding_method = 'purchase'`, and Apple reports our token on the very first read — **no `PUT` is issued**, because the token was bound at source |
| **S-2** | For a **pre-U5f** subscription, `Set App Account Token` is accepted by Apple and the independent re-read observes our token. Outbound order must be `GET, PUT, GET` |
| **S-2b** | If the re-read does not yet show it, the outcome is **`pending`** with no membership row — propagation, not failure |
| **S-3** | The token survives into a **real renewal notification**, so `appstore_notifications_v1` records `applied` rather than `ignored`/`unmapped`. **The single assertion that proves the whole protocol**, and it needs a renewal cycle |
| **G11** | With the membership row deleted and the grandfather clause disabled, a **cold launch** issues the attestation request unconditionally and Connected is reached without a second launch or a re-purchase |
| **F10** | A genuine purchase whose attestation is momentarily pending shows *"Finishing setup"* and **never** "Purchase unavailable" |
| **D4** | The resulting row is `environment = 'Sandbox'`, `connected_member()` returns **false**, and `membership_state()` returns **`sandbox_only`** — a Sandbox subscription confers no Production entitlement |

**`membership` will hold rows for the first time in this project's history.** That
is the intended outcome of U5 and the point at which the U4-era prediction "zero
rows" stops being true by design. It must not be read later as a regression.


---

## 8. EXECUTED RESULTS — 2026-08-23

**Every prediction in §1 matched production exactly.** Measured by capturing
production and diffing against the committed pre-U5 snapshot:

| Surface | Predicted | Observed |
|---|---|---|
| `columns` | +7 | **+7** |
| `constraints` | +5 | **+5** |
| `function_grants` | +3 new, 1 modified | **added 4, removed 1** |
| `functions` | +1 new, 2 modified | **added 3, removed 2** |
| `rls_enabled` | +1 | **+1** |
| `table_grants`, `column_grants`, `policies`, `triggers`, `storage_buckets` | 0 | **0** |

Itemised: **new** `membership_establish_v1`; **replaced** `connected_member` and
`membership_state`; the modified grant is `ensure_membership_binding`/
`authenticated` flipping `can_execute` **false → true**, exactly as predicted.

### P4 — every safety property PROVEN in production, not stated

| Property | Result |
|---|---|
| Non-owner privilege on any membership table | **0** |
| `ensure_membership_binding` | **`authenticated` ONLY** — anon, service_role and PUBLIC all false |
| `membership_establish_v1` | **`service_role` only** |
| U4's canonical writer `membership_apply_state_v1` | **all false — still internal** |
| `membership_resolve_binding_v1`, `membership_record_notification_v1` | **all false** |
| `connected_member` | **all false** — evaluated inside policies, never called |
| Client-suppliable provenance parameter | **0** |
| Functions inserting into `membership` | **exactly one: `membership_establish_v1`** |
| Rows with `pending_cleanup_at` | **0** — establishment schedules nothing |
| Policies enforcing membership / total | **0 / 33** |
| `membership_state` contains `sandbox_only` | **true** |

### P5-P7 — deployment

| Function | Before | After | Bundle |
|---|---|---|---|
| `membership_attest_v1` | — | **NEW v1**, `verify_jwt=false` | sha `98e06419…` |
| `appstore_reconcile_v1` | v2 | **v3** | **SHA CHANGED** — the corrected source shipped |
| `appstore_notifications_v1` | v2 | v2 | unchanged |
| `delete_account_v1` | v9 | v9 | unchanged |
| `revoke_apple_identity_v1` | v3 | v3 | unchanged |

**THE UNSCOPED RE-VERSIONING IS NOW CAUSALLY ATTRIBUTED, AND IT IS NOT THE
FUNCTION DEPLOY.** U4 recorded that a deploy re-versioned neighbours and named
`secrets set` as the leading hypothesis. This run separates them cleanly: between
the pre-flight capture and the pre-deploy capture the **only** action was P2's
`supabase secrets set`, and **all four functions moved v8→v9, v2→v3, v1→v2, v1→v2
with every SHA UNCHANGED**. The subsequent `functions deploy` then moved **only
the two named**. So the secret set re-versions everything and changes nothing;
the deploy is correctly scoped. **A version number remains no evidence that code
changed** — the SHAs are what carry that.

**Download-diff (P6), transpilation-aware, tree restored afterwards
(`git status` clean):** the deployed `appstore_reconcile_v1` contains
`readNotificationHistory`, `unverifiable_items` and `pagination_token`, and
**zero** occurrences of the old bare `.notificationUUID` read. The deployed
`membership_attest_v1` contains **5** `verifyAttestationJWS` references and
**ZERO** `verifyAppleJWS(` calls — **B-31's structural boundary verified in the
DEPLOYED bundle**, not merely in the tree.

### P8 — B-23 GATE MET

Nine of ten surfaces **IDENTICAL**; the only difference is the standing,
mechanically-verified `account_id_format` catalog-serialization exception.

### P6b — THE APPLE CROSS-CHECK THAT FAILED AT PRE-FLIGHT NOW PASSES

```
apple_notification_count : 14
unverifiable_items       : 0
has_more                 : false
```

**Set reconciliation against `membership_notification`, not merely counts:**

| | |
|---|---|
| Apple's uuids | **14** |
| Our uuids | **14** |
| In Apple but **not** ours (lost notifications) | **0** |
| In ours but **not** Apple (unexplained rows) | **0** |
| **Sets identical** | **TRUE** |

**This closes B-32 on real evidence.** The same call returned a structural `0`
before the fix, against the same window and the same fourteen rows.

**One small observation, recorded rather than smoothed:** Apple returned a
`paginationToken` even with `hasMore: false`. Harmless — the token is
informational and the corrected code keys continuation on `hasMore` — but a
future reader should not treat a present token as proof of more pages.

### Post-deploy production state

`membership` **0** · `membership_binding` **0** · `membership_binding_conflict`
**0** · `membership_notification` **14** · `reject_stat` **0**.

**U5 is deployed and nothing has attested yet**, which is correct: no client
build carrying U5e/U5f exists on any device.
