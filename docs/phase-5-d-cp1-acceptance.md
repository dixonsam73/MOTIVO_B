# P5-D / CP-1 APPLY — LIVE IN PRODUCTION AND VERIFIED. 2026-09-06

**`account_privacy` is deployed, EMPTY, and reachable by no read path.**
Applied exactly the committed `dd9e93c` prediction. **All ten snapshot surfaces
match; the diff is insertions only, zero deletions.**

---

## 1. THE FIRST APPLY ABORTED ON ITS OWN GUARD, AND THE DEFECT WAS MY ASSERTION

**Nothing was applied on the first attempt.** The post-guard raised
`CP1 post: table_grants on account_privacy not zero`, the transaction rolled back
whole, and `to_regclass('public.account_privacy')` was **null** with `functions`
back at **34** — verified, not assumed.

**The migration was correct; the assertion was mis-scoped.** My guard counted
**every** grantee in `information_schema.role_table_grants`. Measured against the
fully-revoked reference table `membership`:

| | all grantees | client roles only |
|---|---|---|
| `membership` table grants | **7** | **0** |
| `membership` column grants | **84** | **0** |

**All seven are the owner, `postgres`.** An owner's implicit grants always exist
and are not meaningfully revocable — which is exactly why `capture-schema.sh`
scopes both queries `where grantee in ('anon','authenticated','service_role')`.
**My guard asserted something no correct migration could satisfy** — the same
shape as U4's B-26, where QA asserted a state the implementation could never
produce.

**The fix was to make the assertion match the snapshot's own filter**, not to
weaken it: the re-scoped guard still demands **zero client-role grants**, which
is the property that matters.

**This is the guard working, not failing.** It aborted before commit on a
predicate it could not satisfy, and the diagnosis came from measuring a
known-good table rather than from relaxing the check.

## 2. THE APPLIED DELTA — ALL TEN SURFACES, ZERO MISMATCHES

`capture-schema.sh` against production, diffed against the committed snapshot:

| surface | before | after | predicted | |
|---|---|---|---|---|
| `columns` | 135 | **144** | +9 | ✅ |
| `constraints` | 65 | **70** | +5 | ✅ |
| `functions` | 34 | **39** | +5 new, 0 modified | ✅ |
| `function_grants` | 102 | **117** | +15 | ✅ |
| `triggers` | 11 | **12** | +1 | ✅ |
| `rls_enabled` | 14 | **15** | +1 | ✅ |
| `policies` | 33 | **33** | **0** | ✅ |
| `table_grants` | 102 | **102** | **0** | ✅ |
| `column_grants` | 562 | **562** | **0** | ✅ |
| `storage_buckets` | 2 | **2** | 0 | ✅ |

**243 insertions, ZERO deletions**, across six files. `policies.json`,
`table_grants.json`, `column_grants.json` and `storage_buckets.json` are
**untouched** — the zero-delta prediction proven by the file not moving at all.

## 3. INDEPENDENT VERIFICATION OF EVERY REQUESTED ITEM

| # | check | result |
|---|---|---|
| 1 | all predicted schema deltas | **10/10 exact** (§2) |
| 2 | `account_privacy` starts at 0 rows | **0** |
| 3 | Samuel/Steve receive no manufactured privacy rows | **0 keeper rows** |
| 4 | both existing bandless directory rows still exist | **2** — Samuel 1, Steve 1 |
| 5 | existing-row profile-upsert still permitted | **ALLOWED** — behavioural |
| 6 | genuinely new bandless directory creation refused | **REFUSED, `23514`** — behavioural |
| 7 | client table and column grants zero | **0 / 0** |
| 8 | trigger-function privilege explicit, not inherited | **`proacl` non-null**, owner only |
| 9 | no deployed behavioural/read path changed | **7 functions byte-identical** |

### 5 and 6 are behavioural, run in rolled-back transactions

**Test 5** upserted onto Samuel's existing bandless directory row —
**allowed**, confirming the measured `ON CONFLICT DO UPDATE` case does not raise.

**Test 6** deleted Samuel's directory row inside a transaction and re-inserted it
with no band — **refused** with
`23514: age band must be declared before a directory row is created`, raised from
the trigger. **The transaction aborted and rolled back; Samuel's row was verified
still present afterwards** (`directory_rows 2`, `samuel_row 1`).

**Test 6 is the one that makes 5 meaningful.** A trigger that never raises would
pass test 5 trivially; only the pair shows it discriminates.

### 8 — explicit, and PUBLIC is absent

| function | `proacl` |
|---|---|
| `tg_account_directory_requires_band` | `postgres=X/postgres` — **no client role at all** |
| the four RPCs | `postgres=X/postgres \| authenticated=X/postgres` |

`proacl` is **non-null on all five**, so these are explicit grants, not inherited
defaults. **`PUBLIC` appears in none of them** — the default would have been
`=X/postgres`, i.e. execute for PUBLIC. This is the trap Phase 4 already fell
into with the `avatar_version` trigger function, and the shape now matches
`tg_set_entitled_until` exactly.

### 9 — read paths byte-identical

`search_account_directory`, `get_account_directory_by_user_ids`,
`follow_requests_open`, `connected_member`, `connected_member_self`,
`membership_state` and `enforcement_gate` all hash **identical** to the
pre-CP-1 snapshot. **Zero modified functions**, as predicted.

## 4. THE TRIGGER'S MECHANISM IS STRUCTURAL, NOT A COUNT

```sql
if exists (select 1 from public.account_directory ad where ad.user_id = new.user_id)
  then return new; end if;
```

**Keyed on the incoming row's own `user_id`.** It consults no global count, no
ordering, no "first two" allowance and nothing race-sensitive. The structural
fact it tests is the permitted one: *a directory row for this user already
exists, so this statement is an update in effect.*

**`bandless_directory_rows = 2` is an ACCEPTANCE INVARIANT ONLY.** It is computed
separately, is never referenced by the trigger, and **must never increase**.

## 5. PRODUCT STATE — CP-1 IS INERT

**No behaviour changed for any member.** No policy, RPC or client consults
`account_privacy`; the only new behavioural surface is the trigger, and it is
provably inert for both existing rows (§3, tests 5 and 6).

Samuel and Steve: directory rows, 7 posts, 5 comments, mutual approved follow and
Steve's membership all **unchanged**. **Neither has an `account_privacy` row and
neither was given one.** The fail-protective absence state is real.

**The rollback window is "before the first declared band", not "before CP-2".**
The table is empty today, so the drop in `dd9e93c` §8 loses nothing; that ceases
to be true the moment anyone declares.

## 6. STATUS

**CP-1 apply complete and verified. CP-2 / P5-E NOT started, as instructed.**
