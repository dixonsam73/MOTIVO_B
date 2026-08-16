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
  (select count(*) from public.membership_control where id)        as control_rows,
  (select count(*) from information_schema.tables
     where table_schema='public' and table_name like 'membership%') as existing_membership_tables;
```

**Expected:** `existing_membership_tables = 0` before step A. `auth_users` is
whatever it is — record it; step B's assertions compare against the value read
at execution time, not against a number written here.

---

## 2. Predicted structural delta

Measured from the local instance built from committed migrations, compared with
the committed production snapshot. **Post-deploy recapture must match this
exactly.**

| Surface | Before | After | Δ | What the delta is |
|---|---|---|---|---|
| `functions` | 11 | **14** | **+3** | `connected_member`, `membership_state`, `ensure_membership_binding` |
| `policies` | 33 | **33** | **0** | **No policy is created or modified** |
| `rls_enabled` | 7 | **12** | **+5** | The five new tables, all `rls_enabled = true` |
| `triggers` | 5 | **5** | **0** | U3 adds no trigger |
| `constraints` | 24 | **49** | **+25** | PK/FK/unique/check across the five tables |
| `columns` | 60 | **106** | **+46** | Columns of the five tables |
| `function_grants` | 33 | **42** | **+9** | 3 helpers × 3 roles |
| `table_grants` | 102 | **117** | **+15** | **`service_role` only** |
| `column_grants` | 523 | **569** | **+46** | **`service_role` only** |
| `storage_buckets` | 2 | **2** | **0** | Untouched |

### The two rows that carry the security claim

**All 15 new `table_grants` and all 46 new `column_grants` rows have grantee
`service_role`. Zero for `anon`, zero for `authenticated`.** Anything else means
the revokes did not take, and production's default ACLs would have published
membership state.

**Of the 9 new `function_grants` rows, exactly one has any privilege:**

| Function | anon | authenticated | service_role |
|---|---|---|---|
| `connected_member` | none | none | none |
| `ensure_membership_binding` | none | none | none — **granted at U5, not U3** |
| `membership_state` | none | none | `eff=true direct=true` |

All nine must read `public_execute = false`. **Effective privilege alone is not
sufficient evidence** — that was B-23's blind spot, and the widened three-column
capture exists for exactly this check.

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

## 4. Stopping rules

**No improvising through any of these. Stop and report.**

| Condition | Action |
|---|---|
| Pre-flight shows any `membership*` object already present | **Stop.** Unexpected collision; the analysis is wrong |
| `auth.users` count materially different from expectation, or changing under observation | **Stop.** Establish why before defining a cutover boundary |
| Any DDL statement errors | **Stop.** Do not reach for `CASCADE` — an unpredicted dependency means the analysis was wrong |
| Structural delta differs from §2 in any surface | **Stop.** Do not proceed to step B |
| **Any client privilege appears on membership state** — any `anon`/`authenticated` row in `table_grants`/`column_grants`, or any non-false `can_execute`/`direct_execute`/`public_execute` for those roles | **Stop immediately.** The one failure with a live security consequence |
| `ensure_membership_binding` shows any `authenticated` privilege | **Stop.** That grant belongs to U5 |
| Step B assertion 3 fails (`captured ≠ by_pred`) | **ROLLBACK.** A straggler identity crossed the boundary. Report; **do not top up silently** |
| `control_count ≠ captured` | **ROLLBACK** |
| `cutover_at` already set | **ROLLBACK.** It has already run |
| Helper returns anything contradicting the local acceptance results | **Stop.** Re-run the acceptance suite locally before touching production again |
| Any existing policy or function modified | **Stop.** U3 must change nothing that exists |
| Post-recapture B-23 diff shows anything outside the §2 delta and the one approved `account_id_format` exception | **Stop** |

---

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
