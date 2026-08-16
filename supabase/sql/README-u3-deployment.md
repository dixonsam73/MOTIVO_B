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

| Surface | Before | After | Δ | What the delta is |
|---|---|---|---|---|
| `functions` | 11 | **14** | **+3** | `connected_member`, `membership_state`, `ensure_membership_binding` |
| `policies` | 33 | **33** | **0** | **No policy is created or modified** |
| `rls_enabled` | 7 | **12** | **+5** | The five new tables, all `rls_enabled = true` |
| `triggers` | 5 | **5** | **0** | U3 adds no trigger |
| `constraints` | 24 | **50** | **+26** | PK/FK/unique/check across the five tables. **+1 vs the first draft: `membership_control_verified_needs_cutover`** |
| `columns` | 60 | **107** | **+47** | Columns of the five tables. **+1: `cutover_verified_at`** |
| `function_grants` | 33 | **42** | **+9** | 3 helpers × 3 roles |
| `table_grants` | 102 | **117** | **+15** | **`service_role` only** |
| `column_grants` | 523 | **570** | **+47** | **`service_role` only. +1 for the new column** |
| `storage_buckets` | 2 | **2** | **0** | Untouched |

### The two rows that carry the security claim

**All 15 new `table_grants` and all 47 new `column_grants` rows have grantee
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

## 4. STOP / GO sequence

**No improvising through any checkpoint. Stop and report.**

| # | Checkpoint | GO condition | Failure means | Rollback? |
|---|---|---|---|---|
| **P0** | Pre-flight read | Zero `membership*` objects; **`null_created_at` = 0**; `cutover_at`/`cutover_verified_at` null; live `auth.users` count recorded | Collision, or an unclassifiable identity | Nothing done |
| **P1** | Structural DDL + revokes | All statements succeed | Stop. **Never `CASCADE`** — an unpredicted dependency means the analysis was wrong | Full `drop` |
| **P2** | **Security verification** | Zero `anon`/`authenticated` table and column grants; all three helpers `public_execute=false`; `ensure_membership_binding` ungranted | **Live security consequence. Stop immediately** | Full `drop` |
| **P3** | Structural delta vs §2 | All ten match; **zero modified rows** | Something unintended landed | Full `drop` |
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
