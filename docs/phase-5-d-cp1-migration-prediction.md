# P5-D / CP-1 APPLY — MIGRATION PREDICTION. 2026-09-06

**NOTHING APPLIED. NO DDL EXECUTED. Read-only measurement plus two harmless
probes on temporary objects that were rolled back.** For review.

Design authority: `docs/phase-5-b-cp1-design-r2.md` at **revision 3**.
Population authority: post-CP-0 production, re-measured for this document.

---

## 1. THE CLEAN STATE CP-1 APPLIES AGAINST

**Re-measured after CP-0.** `auth.users` **2** · `account_directory` **2** ·
`posts` **7** · `post_comments` **5** · `follows` **2** (both approved) ·
`membership` **1** · `membership_binding` **1** · storage **9** objects.

**Structural baseline, measured against the committed snapshot's own method** —
`supabase/schema/*.json`, which spans `public` **and** `storage`:

| surface | now |
|---|---|
| `columns` | **135** |
| `constraints` | **65** |
| `functions` | **34** |
| `policies` | **33** |
| `triggers` | **11** |
| `rls_enabled` | **14** |
| `table_grants` | **102** |
| `column_grants` | **562** |
| `function_grants` | **102** |
| `storage_buckets` | **2** |

**My own ad-hoc counts do NOT match these and must not be used** — they scope to
`public` only and count grants differently. **Verification after apply is
`capture-schema.sh` plus a diff**, as every prior unit did.

---

## 2. A MEASURED BEHAVIOUR THAT CHANGES THE TRIGGER

**`BEFORE INSERT` FIRES ON `INSERT … ON CONFLICT DO UPDATE`, BEFORE THE CONFLICT
IS RESOLVED.** Probed on a temporary table inside a rolled-back transaction: a
trigger that raises unconditionally **fired on an upsert onto an already-existing
row**.

**This matters because `upsertSelfRow` is exactly that statement** — PostgREST
with `Prefer: resolution=merge-duplicates` — and it runs on **every profile
publish**.

**So the trigger as designed in r1 §3.2 would raise on every profile publish by
Samuel and Steve**, who have no `account_privacy` row and are not going to be
given one (§7). It would have broken the two surviving identities' profile
editing on the day it shipped, and it would have looked like a client bug.

**Resolution — the trigger constrains genuinely NEW directory rows only:**

```sql
create function public.tg_account_directory_requires_band()
returns trigger language plpgsql security definer set search_path to '' as $$
begin
  -- MEASURED 2026-09-06: BEFORE INSERT fires on ON CONFLICT DO UPDATE before
  -- the conflict is resolved. An upsert onto an existing directory row is an
  -- UPDATE in effect and must not be blocked.
  if exists (select 1 from public.account_directory ad
              where ad.user_id = new.user_id) then
    return new;
  end if;

  if not exists (select 1 from public.account_privacy p
                  where p.user_id = new.user_id) then
    raise exception 'age band must be declared before a directory row is created'
      using errcode = '23514';
  end if;
  return new;
end $$;
```

**Its invariant is re-runnable and must be asserted at apply and afterwards:**

```
select count(*) from public.account_directory ad
 where not exists (select 1 from public.account_privacy p where p.user_id = ad.user_id);
--  = 2 at apply (Samuel, Steve). MUST NEVER INCREASE.
```

**Two is not a grandfather clause and must not become one.** It is a closed,
enumerated set of rows that predate the constraint; the assertion exists so that
a third can never appear silently.

---

## 3. TABLE, COLUMNS, CONSTRAINTS

```sql
create table public.account_privacy (
  user_id                        uuid        primary key
                                   references auth.users(id) on delete cascade,
  age_band                       text        not null,
  band_updated_at                timestamptz not null default now(),

  lookup_enabled                 boolean     not null,
  lookup_set_under_band          text        not null,
  lookup_changed_at              timestamptz,

  follow_requests_enabled        boolean     not null,
  follow_requests_set_under_band text        not null,
  follow_requests_changed_at     timestamptz,

  constraint age_band_values
    check (age_band in ('band_13_17','band_18_plus')),
  constraint lookup_set_under_band_values
    check (lookup_set_under_band in ('band_13_17','band_18_plus')),
  constraint follow_requests_set_under_band_values
    check (follow_requests_set_under_band in ('band_13_17','band_18_plus'))
);
alter table public.account_privacy enable row level security;
```

**9 columns, 5 constraints** (pkey, FK, 3 checks). **No `'under_13'` and no
`'unknown'`** — absence is the unknown state, and it is fail-protective by the
*shape* of every predicate rather than by a branch anyone can forget.

**`age_band NOT NULL` needs no backfill because the table starts EMPTY.** CP-0
did not enable this; it was always true of a new table (recorded as an honest
correction in r1 §8.1 and unchanged).

### The band-at-last-write fields

`lookup_set_under_band` and `follow_requests_set_under_band` record **the band in
force when that preference was last written**. They are what let a protective
downgrade take effect **without destroying preference history** (r3 §7.3′):

```
effective(pref, set_under) =
  pref AND NOT (age_band = 'band_13_17' AND set_under = 'band_18_plus')
```

`*_changed_at` is **NULL while the value is still the initial default**, which is
what distinguishes an initial default from a user choice.

---

## 4. WRITER MODEL, GRANTS AND RLS

**Zero client DML. RLS on, ZERO policies** — U3's membership-table pattern.

```sql
revoke all on public.account_privacy from public, anon, authenticated, service_role;
```

**This revoke is LOAD-BEARING, not ceremony.** U3 recorded that a new table
inherits whatever `pg_default_acl` applies to its creator, and that the entry
differs between deployments — which is how a migration's final state becomes a
property of the environment rather than of the migration. **The predicted
`table_grants` and `column_grants` delta is ZERO, and that zero is the assertion
that the revoke worked**: `membership` and `membership_binding` both show 0 rows
on both surfaces today, so the shape is known-good.

**Every write goes through a `SECURITY DEFINER` function taking identity from
`auth.uid()` and never from an argument.**

| function | grant | semantics |
|---|---|---|
| `account_privacy_upsert_v1(text)` | `authenticated` | creation **and** reconciliation. Never deletes |
| `account_privacy_set_lookup_v1(boolean)` | `authenticated` | the **only** writer of the discovery preference |
| `account_privacy_set_follow_requests_v1(boolean)` | `authenticated` | the **only** writer of the follow-request preference |
| `account_privacy_self_v1()` | `authenticated` | returns stored **and effective** values |
| `tg_account_directory_requires_band()` | **nobody** | trigger only |

```sql
revoke all on function <each of the five> from public, anon, service_role;
grant execute on function <the four RPCs> to authenticated;
```

**The trigger function's grant is the one most likely to be got wrong**, and this
project has already got it wrong once: Phase 4's `avatar_version` work introduced
a trigger function that *"inherited Supabase's default grants where
`tg_set_entitled_until` is revoked"*, and **the snapshot caught it**. The
predicted shape is the revoked one — `anon/authenticated/service_role` all
`can_execute: false` — identical to `tg_set_entitled_until`.

**`account_privacy_self_v1` returns the EFFECTIVE values, computed server-side.**
The override rule lives in exactly one place; a client that recomputed it could
drift, and the drift would be permissive.

---

## 5. AGE-BAND PERSISTENCE AND RECONCILIATION PATHS

**`account_privacy_upsert_v1(p_age_band)`** — the only path that writes
`age_band`:

| state | action |
|---|---|
| **no row** | INSERT. `lookup_enabled` and `follow_requests_enabled` **derived from the band** (`band_18_plus` → true, `band_13_17` → false); both `*_set_under_band` = the band; both `*_changed_at` **NULL** |
| **row exists, same band** | no write. Return current state |
| **`band_13_17` → `band_18_plus`** | update `age_band`, `band_updated_at`. **No preference touched** (r3 §7.2) |
| **`band_18_plus` → `band_13_17`** | update `age_band`, `band_updated_at`. **No preference touched** — the protective effect is the read-time override, so history survives (r3 §7.3′) |

**Idempotent under retry and concurrency**, using
`insert … on conflict do update … returning`, copied from
`ensure_membership_binding`, whose own comment records why `do nothing` is wrong:
the loser skips without taking a lock and a following `SELECT` can miss the
winner's uncommitted row. **A retry after an ambiguous network failure must
return the band that already exists, never write a second row.**

**No provenance is stored** — `ageRangeDeclaration` is not persisted and no
column exists for it (r3 §4.1). **No `under_13` is ever written**: that outcome
writes nothing at all.

**`set_lookup_v1` / `set_follow_requests_v1`** write their own preference,
set `*_set_under_band` to the **current** band, and stamp `*_changed_at`. They
**never** touch `age_band`. **Two functions, two columns, no overlap** — so
"the default was applied once" and "the member has since chosen" cannot be
conflated by any call sequence.

---

## 6. PREDICTED SNAPSHOT DELTA

| surface | before | **after** | delta |
|---|---|---|---|
| `columns` | 135 | **144** | **+9** |
| `constraints` | 65 | **70** | **+5** |
| `functions` | 34 | **39** | **+5 new, ZERO modified** |
| `function_grants` | 102 | **117** | **+15** — 3 rows per function × 5 |
| `triggers` | 11 | **12** | **+1** |
| `rls_enabled` | 14 | **15** | **+1** |
| `policies` | 33 | **33** | **0** |
| `table_grants` | 102 | **102** | **0** |
| `column_grants` | 562 | **562** | **0** |
| `storage_buckets` | 2 | **2** | 0 |

**CP-1 IS PURELY ADDITIVE. It modifies no deployed object**, unlike U4, U5b and
U6a. `search_account_directory` and `follow_requests_open` are **CP-2 / P5-E**,
including binding requirement **CP-2-R1**.

**CP-1 CHANGES NO READ PATH AND IS THEREFORE PRODUCT-INERT** — no policy, no RPC
and no client consults `account_privacy` until CP-2 and CP-3. The only
behavioural surface it adds is the trigger, which is provably inert for both
existing rows (§2).

**Row delta: ZERO.** `account_privacy` is created **empty** and the migration
writes no rows.

---

## 7. SAMUEL AND STEVE AFTER MIGRATION — NO BOOTSTRAP

**Neither receives an `account_privacy` row. None is manufactured. The
fail-protective absence state is real, not simulated.**

**There is no `NOT NULL` pressure to relieve**: the constraint is on a table that
starts empty, so it is satisfied by having no rows at all. **Manufacturing a band
would be inventing a declaration neither of them has made** — the same defect
class as U4's rejected `binding_method` inference, where a value derived from
what had not happened yet was provenance invented rather than established.

| | at CP-1 | at CP-2 | at CP-3 |
|---|---|---|---|
| directory row, posts, comments, follow, membership | **unchanged** | unchanged | unchanged |
| profile publishing (`upsertSelfRow`) | **works** — §2's skip clause | works | works |
| discoverable by search | unchanged | **NO** — `EXISTS` is false | until they declare |
| Share default | unchanged | unchanged | **OFF** until `band_18_plus` |
| attribution to their approved follower | **unchanged** | **unchanged (G10)** | unchanged |

**The undiscoverability at CP-2 is real, intended, and reversible** — either
declares a band through CP-3's flow and their preference applies.

**IT DOES NOT ENDANGER THE PHASE 4 FIXTURE**, and this is the specific check that
matters: conditions **2** and **8** and **C-34** need the **approved follow** and
**attribution**, which `get_account_directory_by_user_ids` serves with **no
subject filter** (G10, re-verified in P4-U7). **They do not need discovery.**
Phase 4's real blocker is unchanged and unrelated — zero identities are
`connected_member()`, which needs a Production subscription.

---

## 8. ROLLBACK

**Purely additive, so the rollback is a drop** — the first time in this project
that is true of a schema unit:

```sql
drop trigger if exists tg_directory_requires_band on public.account_directory;
drop function if exists public.tg_account_directory_requires_band();
drop function if exists public.account_privacy_self_v1();
drop function if exists public.account_privacy_set_follow_requests_v1(boolean);
drop function if exists public.account_privacy_set_lookup_v1(boolean);
drop function if exists public.account_privacy_upsert_v1(text);
drop table if exists public.account_privacy;
```

**No deployed object is modified, so nothing needs restoring byte-compared.**
`capture-schema.sh` must return to the §1 baseline exactly.

**NO DATA LOSS AT P5-D, BECAUSE THE TABLE IS EMPTY — AND THAT EXPIRES.** From the
first declared band onward, a drop destroys a declaration only Apple and the
member can reproduce. **The rollback window is "before anyone declares", not
"before CP-2".**

---

## 9. THE APPLY PROCEDURE

**One submission**, with the guard **inside** the transaction and a final
`SELECT` that returns a row — and now known to be executable, because
`supabase db query` at CLI 2.113.0 **accepts multi-statement submissions** and a
`raise` **aborts the whole thing** (both measured during CP-0, both corrected in
CLAUDE.md).

1. **Pre-guard**: assert the §1 baseline; assert `account_privacy` does not exist.
2. DDL: table, RLS, revokes, 5 functions, grants, trigger.
3. **Post-guard, inside the transaction**: assert the §6 delta; assert
   `account_privacy` is empty; assert `table_grants`/`column_grants` for it are
   **0**; assert the trigger function is executable by **nobody**; assert §2's
   invariant = **2**.
4. Final `SELECT` returning every count.
5. **After commit**: `capture-schema.sh` + diff against §1, which is the
   authority — **not** the transaction's own report.

## 10. STATUS

**NOTHING APPLIED.** Awaiting review.
