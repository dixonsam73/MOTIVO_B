# U6b-4 — GRANDFATHER RETIREMENT. P0–P2 COMPLETE, NOT APPLIED. 2026-09-02

**NOTHING IS DEPLOYED.** Production is untouched and `grandfather_enabled`
remains `false`, `enforcement_enabled` remains `false`, `u6b_bound_at` remains
set. This is the P0–P2 record and the package awaiting P3 authorisation.

**P3 IS A SEPARATE HUMAN AUTHORISATION AND THAT IS STRUCTURAL, NOT CEREMONY.**
Before this runs, restoring grandfathering is **one boolean**. After it, it is
`2026-09-02-u6b4-rollback-production.sql`.

---

## P0 — pre-flight, live and read-only

`capture-schema.sh --linked` produced **zero diff** against the committed
snapshot: production is byte-identical to `supabase/schema/`. Every number below
is derived from that verified snapshot rather than from local counts.

### The dependency surface is one function and one literal

Measured, not assumed:

| Retired object | Referenced by |
|---|---|
| `membership_cutover` | `connected_member` — **and nothing else** |
| `grandfather_enabled` | `connected_member` — and nothing else |
| `grandfather_expires_at` | `connected_member` — and nothing else |
| `'grandfathered'` literal | `membership_state` — and nothing else |
| `cutover_at` | **NO function at all** |

**Zero policies** reference any of them. `membership_cutover` carries 2 columns,
2 constraints (pkey + FK), 1 index, RLS on, **0 client grants**, **0 triggers**,
16 rows.

**A measurement error worth keeping.** The first live query for this table
returned `(none)` for every pattern — wrong, and silently so. `pg_get_functiondef`
**throws on aggregate functions**, which aborted the whole query, and the error
was swallowed by the pipeline. The same defect then failed two U3 assertions
loudly, which is how it was found. **Every such query now filters `prokind='f'`.**

### THE PREMISE, AND IT IS MEASURED

`grandfather_enabled` has been **`false`** since 2026-09-01. Production census
2026-09-02: **1 identity `sandbox_only`/false, 16 `unknown`/false — all 17
false.** So `connected_member`'s middle arm already returns false for everyone
and `membership_state` already reaches its final `else`.

**U6b-4 removes an arm that is ALREADY INERT. Its behavioural delta is zero**,
and the apply file's Guard B1 asserts that rather than claiming it.

---

## The measured structural delta

| Surface | Before | After | Δ |
|---|---|---|---|
| functions | 28 | **28** | 0 — **2 MODIFIED** |
| policies | 33 | **33** | **0** |
| columns | 136 | **132** | **−4** |
| constraints | 67 | **65** | **−2** (pkey + FK) |
| rls_enabled | 15 | **14** | **−1** |
| triggers | 10 | **10** | 0 |
| function_grants | 84 | **84** | 0 |
| table_grants | 102 | **102** | **0** |
| column_grants | 554 | **554** | **0** |
| storage_buckets | 2 | **2** | 0 |

**The two grant surfaces are ZERO because U3 revoked everything**, which is why
dropping the table and two columns removes no grant row. `table_grants` tracks
`anon`/`authenticated`/`service_role` only; `information_schema` reports 7 grants
on `membership_cutover`, all owner/admin, outside that filter. **The two numbers
are not in conflict and neither is wrong.**

`membership_control` goes 10 columns → 8: `grandfather_enabled` and
`grandfather_expires_at` drop; `cutover_at`, `cutover_identity_count`,
`cutover_verified_at`, `u6b_bound_at`, `notes`, `updated_at` and
`enforcement_enabled` are all **retained**.

---

## P2 — local rehearsal

**B-23 GATE MET before applying**, so the instance was a faithful reproduction.

### All eight suites green under U6b-4

| Suite | Result |
|---|---|
| `u3/acceptance` | **91 passed, 0 failed** |
| `u4/acceptance` | **99 passed, 0 failed** |
| `u4/e2e` | **43 passed, 0 failed** |
| `u5/acceptance` | **59 passed, 0 failed** |
| `u5/e2e` | **62 passed, 0 failed** |
| `u5/client-structural` | **60 passed, 0 failed** |
| `u6a/acceptance` | **3 passed, 0 failed** |
| `u6b/acceptance` | **54 passed, 0 failed** |
| | **471 assertions, 0 failures** |

### The suites were RE-POINTED, never edited until they passed

Roughly 30 assertions read the retired surface. Each was handled one of three
ways, following the U6a→U6b group K precedent:

- **Re-pointed with the result flipped**, so the assertion now proves the
  retirement: U3 `A6` (`t`→`f`), `A28`/`A26b`/`A27d` (`grandfathered`→`unknown`),
  U5 `A60h`/`A60i`.
- **Retired in place and REPLACED by an assertion that the mechanism is gone** —
  never deleted. U3's `A11`/`A11b` (the switch) and its entire `A32`–`A40`
  cutover-boundary section, which now pins that the table, both controls and
  every function reference are absent, and that the retained record survives.
- **Re-pointed with the count kept exact**: U3 `A1` (5→4 tables) and U4 `A41`
  (7→6), each paired with a new assertion naming the dropped table, so neither
  can pass again because some other table appeared.

### ONE ASSERTION LOST DISCRIMINATING POWER, AND IT IS RECORDED AS A LOSS

U5's **`A60`** was D4's critical case: a Sandbox-only identity in the snapshot.
Under the naive WHERE-clause fix, `bool_or` returned NULL over an empty set and
`coalesce` fell through to the **granting** grandfather clause — the exact
inversion of invariant 8. **With that clause retired, NULL now falls through to
`false`, so a correct implementation and the buggy one produce the same answer.**
A60 still asserts the right outcome; it can no longer catch that bug.

**`A60m` restores the discrimination structurally**, pinning that the environment
test lives inside `bool_or` and not in the `WHERE`. That placement is currently
harmless to get wrong and becomes load-bearing again the moment anyone adds a
third `coalesce` arm — which is exactly why the migration keeps it.

---

## The rollback, and what it can and cannot restore

**Regenerated from production and rehearsed end to end. B-23 returned GATE MET on
the rolled-back instance** — structural identity with live production, with only
the standing `account_id_format` exception. That is the proof, not that the
statements succeeded.

Behaviourally verified on the rolled-back instance: restored **inert**
(16 `unknown`/false), and re-enabling the flag deliberately produces
16 `grandfathered`/true.

### The 16 rows are reconstructed, not backed up

The snapshot is destroyed by the DROP and rebuilt from `auth.users` using the
**retained `cutover_at`** — which is the original population predicate, so **no
identifier needs to live in this repository**. Verified against production before
U6b-4 was offered: **16 rows, 16 recorded, 16 reconstructible, zero discrepancy
in both directions.**

**Guard 5 refuses if the reconstruction does not equal `cutover_identity_count`.**
If a pre-cutover identity has since been deleted, the rollback is genuinely lossy
and stops rather than silently restoring a smaller snapshot that would
under-grandfather.

**`captured_at` is NOT recovered.** The identities are exact; their capture
timestamps become `now()`. Nothing reads `captured_at` — the grandfather clause
never did — so this is a fidelity loss in the record, not in behaviour. Stated
because a rollback that quietly invents data is worse than one that names the
column it invented.

### THREE DEFECTS WERE FOUND IN THE ROLLBACK BY REHEARSING IT

None would have been caught by review, and one was caught only by the gate.

1. **It restored the mechanism MORE PERMISSIVE than the state it undid.**
   `grandfather_enabled` re-adds with `default true`, so the rollback would have
   grandfathered 16 identities the instant it committed. **A rollback that grants
   access nobody asked for is not a rollback.** It now carries the value `false`
   explicitly and guards it.
2. **`ALTER TABLE ADD COLUMN` cannot restore production.** PostgreSQL cannot
   reorder columns, so the two land at positions 9–10 where production holds 5–6.
   **B-23 returned GATE NOT MET on exactly that** — two UNAPPROVED
   `ordinal_position` differences. It was **not allowlistable**: the gate's rule
   is that a reproducible difference must be reproduced, and this one is. The
   rollback now **rebuilds the single-row table** with the exact column order —
   safe because zero FKs reference it, zero policies, zero triggers, one index.
3. **All five constraint names collided** with the live table during the rebuild,
   `membership_control_pkey` first, because an index name is schema-global rather
   than table-scoped. The constraints are now added **after** the rename.

**A no-op verification file is not applicable here and none was manufactured.**
The U6a/U6b pattern verifies a rollback whose statements are `CREATE OR REPLACE`
against unchanged objects; this rollback restores dropped ones and can never be a
no-op. Its equivalent proof is stronger and already run: **B-23 reporting
`functions IDENTICAL` on the rolled-back instance.**

---

## The apply file

`2026-09-02-u6b4-apply-production.sql` — one submission, guards inside, ending in
a `SELECT` that returns a row, so **"Success. No rows returned." is the symptom
rather than the disguise**. The body between its VERBATIM markers is
byte-identical to the migration.

**Guard A (pre)** — `membership_cutover` present; **`grandfather_enabled` FALSE**
(the premise); `enforcement_enabled` FALSE; `u6b_bound_at` set.

**Guard B (post)** — B1 the entitlement census is **IDENTICAL**; B2 no membership
or auth row count moved; B3 the retired objects are gone and no function
references them; B4 all five retained control columns survive, `u6b_bound_at`
undisturbed, enforcement still FALSE; B5 **`shadow_stat_clause_check` still
accepts `'grandfathered'`**; B6 privileges unchanged — `connected_member`
reachable by **zero** client roles (B-33) and `membership_state` by
**exactly** `service_role`; B7 policy count still 33.

### The guards were proven to FIRE, not merely to pass

A guard that cannot fail is worthless — the C56-7 lesson. Three negative tests,
each leaving the database untouched:

| Condition | Result |
|---|---|
| Re-run when already applied | `ABORT: membership_cutover absent` |
| `grandfather_enabled = true` | `ABORT: ... assumes it is already false and would change behaviour` |
| `enforcement_enabled = true` | `ABORT: ... must not run against bound enforcement` |

**Two defects in the apply file were also found by rehearsal:** a `count(*) as n`
column colliding with the PL/pgSQL variable `n`, which PostgreSQL refuses as
ambiguous; and the aggregate-function issue above.

---

## SCOPE REFINEMENT — RECORDED AS A REFINEMENT, NOT AS THE ORIGINAL SCOPE

**The approved U6b-4 scope said: drop `grandfather_enabled`, `grandfather_expires_at`,
and the `cutover_*` control columns that become dead. THIS PACKAGE RETAINS ALL
THREE `cutover_*` COLUMNS.** That is a deviation from the approved wording, it
was made while preparing the package and NOT flagged at the time, and it was
reconciled and accepted only when the account holder challenged it on
2026-09-02. **It is recorded here as an intentional refinement agreed after the
fact — not rewritten to look as though it was always the scope.**

**Retained:** `cutover_at`, `cutover_identity_count`, `cutover_verified_at`.
**Note the naming:** the column is `cutover_identity_count`, and there are THREE
retained `cutover_*` columns, not two — `cutover_verified_at` is the third.

**They have NO live entitlement, security or runtime semantics after U6b-4.**
Measured, not assumed: zero references across all 28 production functions, zero
policies, and neither `connected_member` nor `membership_state` touches them once
this migration lands. They are **inert historical metadata**, with one
operational role — `cutover_at` is the ROLLBACK'S RECONSTRUCTION KEY, which is a
recovery input rather than a runtime path.

**THE ARGUMENT THAT DECIDED IT IS AN ASYMMETRY, and it is the part worth
re-reading:** retention is reversible and the retirement is not. Dropping these
three columns later is a one-line migration with no behavioural effect, available
at any time. Removing them *now* would permanently discard the reconstruction key
in the very transaction that makes the snapshot unrecoverable — **two
irreversible losses in one step, for tidiness.**

**One consequence not stated in the original proposal:** the three columns are
bound by three CHECK constraints — `membership_control_count_nonnegative`,
`membership_control_count_with_verification` and
`membership_control_verified_needs_cutover`. Dropping the columns means dropping
those too, so the delta would move from columns −4 / constraints −2 to
**columns −7 / constraints −5**.

**The literal-compliance route remains open and is the safer ordering:** apply
U6b-4 as prepared, then drop the three columns as a separate trivial migration
once the rollback is no longer wanted.

## Constraints carried and honoured

| Constraint | How |
|---|---|
| `shadow_stat_clause_check` keeps `'grandfathered'` | **Preserved by NOT ACTING** — the safest form. Guard B5 asserts it; U3 `A39` asserts it; `A39b` proves such a row can still be **written**, not merely tolerated |
| No enforcement re-bind | Nothing in U6b-4 touches `enforcement_enabled`; guarded on both sides |
| `enforcement_enabled` stays FALSE | Guard A and Guard B4 |
| `u6b_bound_at` preserved | **Retained deliberately**, correcting the retirement design; Guard B4 |
| No client work | Zero client files touched |
| No U7 work | No worker, no cleanup |
| C-59 open, non-blocking | It concerns the enforcement **write-deny** path; U6b-4 binds nothing |
| No cohort preservation work | The 16 rows are dropped. The rollback reconstructs them from a retained column — that is rollback fidelity, not preservation |
| Retained `cutover_*` columns | **An intentional refinement from the approved wording, agreed 2026-09-02 after being challenged** — see the section above. Inert historical/rollback metadata with no live semantics |
