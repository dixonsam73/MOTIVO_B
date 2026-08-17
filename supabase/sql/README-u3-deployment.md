# U3 production deployment — PREPARED, NOT EXECUTED

**Nothing here has been run against production.** This is the reviewed package,
awaiting explicit separate authorisation.

U3 is **additive and inert**: no existing policy, function, grant or row is
touched, and no Edge Function is deployed. Rollback is therefore `drop` in
reverse dependency order — see the end of this file.

---

## Order — local first, always

Production is never mutated before the migration exists and is proven.

| # | Step | State of the B-23 gate |
|---|---|---|
| 1 | Author the migration locally | green (pre-U3) |
| 2 | Destroy and rebuild local; apply from scratch | **legitimately RED** — local has objects production does not |
| 3 | Run the U3 acceptance suite locally | red, expected |
| 4 | **This package reviewed and authorised** | red, expected |
| 5 | Apply step A (structural DDL) to production | red, expected |
| 6 | Verify the structural delta against §2 | red, expected |
| 7 | Run step B (cutover population) | red, expected |
| 8 | `./supabase/capture-schema.sh` — refresh the production snapshot | — |
| 9 | `./supabase/verify-baseline.sh` | **must be GREEN again** |
| 10 | Commit migration + refreshed snapshot together | green |

**The red state between 2 and 9 is expected and must not be "fixed" by
weakening the gate or by refreshing the production snapshot early.** Steps 1–4
are complete; **5 onward are not authorised.**

---

## 1. Pre-flight, immediately before step A

Read-only. **Do not assume the design-pass figure of 16 identities still
holds** — re-read it and record what you actually see.

```sql
select
  (select count(*) from auth.users)                                as auth_users,
  (select count(*) from auth.users where created_at is null)       as null_created_at,
  (select count(*) from information_schema.tables
     where table_schema='public' and table_name like 'membership%') as existing_membership_tables;
```

**Expected:** `existing_membership_tables = 0` before step A, and
**`null_created_at` = 0 — a hard gate.** `auth_users` is whatever it is: record
it, because step B compares against the value read at execution time rather than
against any number written here.

### Privilege diagnostics — EVIDENCE ONLY, added 2026-08-17

```sql
select current_user, session_user;

select defaclrole::regrole::text as owner_role,
       defaclnamespace::regnamespace::text as schema,
       defaclobjtype as obj_type,
       defaclacl::text as default_acl
  from pg_default_acl
 where defaclnamespace = 'public'::regnamespace;
```

**Record both. NEITHER IS A GO CONDITION, and neither may be used to decide what
U3's privilege state should be.** They exist so that the applying identity and
the ambient defaults are on the record at the moment of the change — useful when
reading this back later, and useful if some *other* surface ever turns out to
depend on them.

**Why they are diagnostics rather than gates.** The migration now revokes every
privilege on all five tables from `public`, `anon`, `authenticated` **and**
`service_role`, and revokes EXECUTE on all three helpers from the same four,
granting back exactly one privilege. The end state is therefore identical under
every `pg_default_acl` entry, so there is nothing here for the deployment to
branch on. That is the point of the change: **the target state is defined by our
SQL, not discovered from the environment.**

**Also record the owner** that the DDL produces, because ownership is not
normalised by any revoke and every helper is `SECURITY DEFINER`:

```sql
select c.relname, c.relowner::regrole::text as owner
  from pg_class c
 where c.relnamespace = 'public'::regnamespace
   and c.relkind = 'r' and c.relname like 'membership%'
 union all
select p.proname, p.proowner::regrole::text
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('connected_member','membership_state','ensure_membership_binding')
 order by 1;
```

**GO condition at P2: all eight rows report the SAME owner.** A split owner
would mean a `SECURITY DEFINER` helper runs as a different role from the tables
it reads, which is a real difference in effective authority rather than a
cosmetic one.

**Why the NULL gate is hard.** `auth.users.created_at` is nullable with no
default and belongs to GoTrue, not to us. A NULL satisfies **neither**
`< cutover_at` **nor** `>= cutover_at`, so such an identity would be excluded
from the snapshot *and* from every completeness check — the counts would agree
while it sat silently unclassifiable, and U6b would deny it. That is a worse
failure shape than the race, because it leaves nothing to detect.

---

## 2. Predicted structural delta

Measured from the local instance built from committed migrations, compared with
the committed production snapshot. **Post-deploy recapture must match this
exactly.**

**REVISED 2026-08-17, and two surfaces moved.** The earlier prediction of `+15`
`table_grants` and `+47` `column_grants` was measured while `service_role` still
inherited whatever the creating role's `pg_default_acl` supplied — `Dxtm`
locally, `arwdDxtm` under the stock `supabase_admin` entry. That made two of the
ten surfaces a property of the deployment rather than of the migration, so P3
could have failed on a deployment that was in fact secure. **The migration now
revokes from `service_role` as well, so both surfaces go to zero and the whole
delta is environment-independent.**

| Surface | Before | After | Δ | What the delta is |
|---|---|---|---|---|
| `functions` | 11 | **14** | **+3** | `connected_member`, `membership_state`, `ensure_membership_binding` |
| `policies` | 33 | **33** | **0** | **No policy is created or modified** |
| `rls_enabled` | 7 | **12** | **+5** | The five new tables, all `rls_enabled = true` |
| `triggers` | 5 | **5** | **0** | U3 adds no trigger |
| `constraints` | 24 | **50** | **+26** | PK/FK/unique/check across the five tables |
| `columns` | 60 | **107** | **+47** | Columns of the five tables |
| `function_grants` | 33 | **42** | **+9** | 3 helpers × 3 roles. **Rows, not privileges** — eight of the nine read `false/false/false` |
| `table_grants` | 102 | **102** | **0** | **Was `+15`. Zero: no role holds any table privilege** |
| `column_grants` | 523 | **523** | **0** | **Was `+47`. Zero, for the same reason** |
| `storage_buckets` | 2 | **2** | **0** | Untouched |

**Total: 90 additive differences, zero missing, zero modified** beyond the one
approved `account_id_format` catalog-serialization exception. Every one of the 90
names a U3 object — the four that do not contain the string `membership` are
`connected_member` and its three grant rows.

### The rows that carry the security claim

**`table_grants` and `column_grants` must be byte-IDENTICAL to the pre-U3
snapshot.** Not "service_role only" — *identical*. U3 grants no table or column
privilege to any role, so a single new row on either surface means a revoke did
not take and the ambient default is showing through.

**Of the 9 new `function_grants` rows, exactly one has any privilege:**

| Function | anon | authenticated | service_role |
|---|---|---|---|
| `connected_member` | none | none | none |
| `ensure_membership_binding` | none | none | none — **granted at U5, not U3** |
| `membership_state` | none | none | `eff=true direct=true` |

All nine must read `public_execute = false`. **Effective privilege alone is not
sufficient evidence** — that was B-23's blind spot, and the widened three-column
capture exists for exactly this check.

**The `service_role` column of the first two rows is now explicitly revoked, not
merely never granted** (revised 2026-08-17). The stock `supabase_admin` default
grants EXECUTE on new functions to all three roles, so "we never granted it"
would have been an environment-dependent claim in exactly the way the table
privileges were. All three helpers are revoked from `public, anon,
authenticated, service_role` first; `membership_state` is then granted back to
`service_role`, and that single line is **the entire privilege surface U3
creates**.

### P2 — the three queries, so the gate is executed rather than eyeballed

```sql
-- 1. No non-owner grantee on any of the five tables. Covers anon,
--    authenticated, service_role AND PUBLIC (grantee 0) in one read, including
--    the PUBLIC case the structural capture cannot see.
select count(*) as non_owner_privileges
  from pg_class c
  cross join lateral aclexplode(c.relacl) a
 where c.relnamespace = 'public'::regnamespace
   and c.relkind = 'r' and c.relname like 'membership%'
   and a.grantee <> c.relowner;                       -- must be 0

-- 2. Helper EXECUTE, all three roles, direct and via PUBLIC.
select p.proname, r.rolname,
       has_function_privilege(r.rolname, p.oid, 'EXECUTE') as can_execute,
       exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                where a.privilege_type='EXECUTE' and a.grantee=0) as public_execute
  from pg_proc p
  cross join (select rolname from pg_roles
               where rolname in ('anon','authenticated','service_role')) r
 where p.pronamespace = 'public'::regnamespace
   and p.proname in ('connected_member','membership_state','ensure_membership_binding')
 order by 1,2;
-- must be: membership_state/service_role can_execute = true, every other row
-- false, and public_execute false on all nine.

-- 3. RLS on all five.
select count(*) as tables_without_rls
  from pg_class c
 where c.relnamespace = 'public'::regnamespace
   and c.relkind = 'r' and c.relname like 'membership%'
   and not c.relrowsecurity;                          -- must be 0
```

These are the same assertions the local suite runs as A3c–A3h, A4b and A4c, so a
production P2 that disagrees with a green local run is itself the finding.

### Nothing existing may move

The 33 pre-existing `function_grants` rows were verified byte-identical between
the pre-U3 production snapshot and the local post-U3 capture. The same must hold
after deployment: **no existing policy, function, grant, constraint, column or
bucket may change.**

---

## 3. Outside structural fidelity — asserted separately

**`membership_cutover`'s contents are production identity data and are invisible
to the B-23 gate**, which captures structure only and reads no user table. A
green gate after step 9 therefore proves the *schema* reproduces; **it proves
nothing about the snapshot.**

That is correct and deliberate — no production UID is written into the
repository — but it means the count must be asserted on its own, by step B's
assertions and its post-commit verification. **Do not read a green gate as
covering it.**

---

## 4. STOP / GO sequence

**No improvising through any checkpoint. Stop and report.**

| # | Checkpoint | GO condition | Failure means | Rollback? |
|---|---|---|---|---|
| **P0** | Pre-flight read | Zero `membership*` objects; **`null_created_at` = 0**; `cutover_at`/`cutover_verified_at` null; live `auth.users` count recorded; **`current_user` and `pg_default_acl` recorded as evidence — neither is a GO condition** | Collision, or an unclassifiable identity | Nothing done |
| **P1** | Structural DDL + revokes | All statements succeed | Stop. **Never `CASCADE`** — an unpredicted dependency means the analysis was wrong | Full `drop` |
| **P2** | **Security verification** | **Zero table and column grants on all five tables for `anon`, `authenticated` AND `service_role`** — equivalently, no grantee other than the owner appears in `relacl`; zero PUBLIC table privileges; all three helpers `public_execute=false`; `connected_member` and `ensure_membership_binding` hold **no** EXECUTE for any of the three roles; `membership_state` holds `direct_execute=true` for `service_role` only; **all five tables and all three helpers report the same owner** | **Live security consequence. Stop immediately** | Full `drop` |
| **P3** | Structural delta vs §2 | All ten match — including **`table_grants` and `column_grants` byte-identical**; **zero modified rows** | Something unintended landed | Full `drop` |
| **P4** | Boundary + population (one transaction, **READ COMMITTED**) | `boundary_declared` true; `count_still_unset` true; `captured` > 0 | ROLLBACK; nothing declared | **Yes, until commit** |
| **P5** | **COMMIT** | — | — | **No. The boundary is now irreversible** |
| **P6** | **Convergence check** (fresh snapshot) | `missing` = 0, `null_created_at` = 0, `invalid_members` = 0 | `missing` > 0 → **one** repair, then P7. `invalid_members` > 0 → **STOP** | Repair forward |
| **P7** | Re-verify after the single repair | All three zero | **STOP AND REPORT. Do not repair again, do not loop** — a second divergence is not explained by a millisecond race and is itself the finding | Stop |
| **P8** | Finalise | `cutover_identity_count` set, `cutover_verified_at` set, `materialised = by_predicate = recorded_count` | ROLLBACK the finalise transaction; boundary and snapshot survive | Yes, for this step |
| **P9** | Production recapture | Snapshot refreshed | — | Repo file |
| **P10** | **B-23 gate** | **GREEN**, only the approved `account_id_format` exception | Anything outside the §2 delta | Repo file |
| **P11** | Inertness re-check | Zero policies call `connected_member`; 33 policies unchanged; 5 triggers; membership empty; nothing scheduled; functions still v7/v1 | U3 changed something | Full `drop` |

**Convergence is bounded, deliberately.** At most one repair, then a single
re-verification, then stop. Repeated divergence is unexpected evidence rather
than something to retry through, and automating past it would destroy exactly
the information needed to understand it.

## 5. Rollback

U3 is additive and inert, so rollback is a `drop` in reverse dependency order.
**Nothing existing is preserved-or-lost, because nothing existing is touched** —
no policy, no grant on an existing table, no function, no row of user content.

```sql
drop function if exists public.ensure_membership_binding();
drop function if exists public.membership_state(uuid);
drop function if exists public.connected_member(uuid);
drop table    if exists public.membership_control;
drop table    if exists public.membership_cutover;
drop table    if exists public.membership_notification;
drop table    if exists public.membership;
drop table    if exists public.membership_binding;
```

**What is lost on rollback:** the cutover snapshot, if step B had run. It is
re-derivable only for identities created before the original boundary — so a
rollback after step B means the boundary must be re-established, and any
identity created in between is then post-cutover. **Record the boundary
timestamp before rolling back.**

**This stops being a `drop` the moment any policy calls `connected_member()`** —
which is U6, not U3. Keeping U3 free of that is what keeps rollback trivial.
