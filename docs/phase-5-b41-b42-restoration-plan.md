# B-41 / B-42 — restoring local backend validation before any deployment

Written 2026-09-14. **Plan only; nothing here is implemented.** Separate from
B-39/A1 and to be committed and reviewed on its own.

## Why this blocks deployment, stated precisely

Two different claims must not be merged:

- **"A1's checks pass locally"** — TRUE. `b39/acceptance-refund.sh` 35/35,
  `b39/modules.ts` 6/6, and every other suite's per-assertion result unchanged.
- **"The full backend validation passes"** — FALSE, before and after A1.
  (1) The B-23 gate is **NOT MET** with 19 pre-existing problems, so the local
  rebuild is not a faithful reproduction of production and cannot certify a
  deployment delta. (2) **Unchanged failures prove only that A1 did not change
  those results.** U6b aborts at its first fixture step and p4/u7 fails at its
  directory fixture, so every assertion after those steps — including U6b's
  enforcement matrix and C-59's write-deny group — **has not executed against
  the current schema since CP-1**. An assertion that never ran is not a pass.

## Unit R1 — B-41: bring migrations back to production (schema only)

Each item is a statement production already has and `supabase/migrations/`
lacks. **No new behaviour; the target is the committed snapshot.**

| # | Surface | Production (committed snapshot) | Local rebuild | Source of the missing statement |
|---|---|---|---|---|
| 1 | `posts_insert_owner.with_check` | includes `AND (is_public = true)` | missing | `supabase/sql/2026-09-04-u2s-posts-insert-privacy.sql` — applied to production, never added as a migration |
| 2 | `account_privacy_self_v1`, `…_set_follow_requests_v1`, `…_set_lookup_v1`, `…_upsert_v1` | `public_execute = false`; anon and service_role cannot execute | PUBLIC still holds EXECUTE (the CP-1 migration grants to `authenticated` but never revokes the PUBLIC default) | to be established from the CP-1 deployment record; the migration itself lacks `revoke … from public` |
| 3 | `tg_account_directory_requires_band` | no role can execute | PUBLIC default present | same |
| 4 | `tg_stamp_avatar_version` | no role can execute | PUBLIC default present | CLAUDE.md records this revoke as found and applied in production at P4-U5; **it is in neither `supabase/sql/2026-09-05-u5-avatar-version.sql` nor its migration** — locate the statement that was run before copying it |

**Steps.**
1. Read the committed snapshot rows and, for #2–#4, the deployment records, so
   each migration statement is copied from what ran, not re-derived.
2. One new migration, dated after B-39's, carrying exactly those statements
   (revoke-then-grant, the U3 pattern, so the end state is a property of the
   file). **Do not edit the historical migrations.**
3. Prediction: the gate returns **GATE MET with only the standing
   `account_id_format` exception**; with B-39's migration present it returns
   exactly B-39's three function rows and nothing else.
4. Negative control: temporarily drop the new migration and show the 19
   problems return.
5. **Production is not touched** — this unit changes the reproduction, not the
   thing reproduced. Read-only confirmation of the four sources may need a
   production query, which is asked for, not assumed.

**Why it matters beyond the gate:** local grants on the CP-1 functions are
today not evidence about production, which B-40's recommendation depends on.

## Unit R2 — B-42: make the four suites run to completion again

**Rule: fix fixtures and stale counts; never weaken an assertion or delete one.**

| Suite | Break | Fix | Assertion meaning preserved |
|---|---|---|---|
| u6b acceptance | fixture inserts `account_directory` rows (line ~58) without a declared age band; CP-1's `tg_account_directory_requires_band` refuses; psql exits 3 | insert an `account_privacy` row (`band_18_plus`) for each directory fixture identity before the directory insert, through the same mechanism CP-1 uses | unchanged — the band is setup, not subject |
| p4/u7 acceptance | same, at its directory insert (line ~49) | same | unchanged |
| u3 A16b | `count(*) = 10` triggers (U3 5 + U6b 5); now 12 | assert the **exact named set** of triggers rather than a count, adding P4-U5's avatar-version and CP-1's band triggers by name | **stronger**: a renamed or swapped trigger fails, which a count cannot detect |
| u4 A57c | `count(*) = 6` (U4 1 + U6b 5); now 8 | same exact-set treatment | stronger, same reason |

**Steps and prediction.**
1. Record each suite's current result (done: u3 90/1, u4 98/1, u6b exit 3,
   p4/u7 19/7).
2. Apply the fixture and set changes.
3. **Predict before running:** u3 and u4 fully green; for u6b and p4/u7, the
   assertions that previously never executed are **new evidence**, so the
   prediction is stated per group rather than as "green", and **any failure
   they reveal is a finding to diagnose, not a fixture to adjust.**
4. Re-run after R1, since u6b's structural assertions compare against
   production-shaped state.

## Order and boundary

R1 → R2 → re-run every suite and the gate with B-39's migration present →
only then prepare a B-39 production deployment package, which is separately
authorised. **None of R1 or R2 is part of A1's change set.**

## Outcome — 2026-09-14

**Both units completed as planned, R1 before R2.** R1: G1 GATE MET, G2 exactly
B-39's three function rows, G3 negative control 22
(`docs/phase-5-b41-r1-prediction.md` §5). R2: u3 91/0, u4 99/0, u6b 64/64,
p4/u7 26/26, no newly executing assertion failed
(`docs/phase-5-b42-r2-prediction.md` §4). **The "Why this blocks deployment"
section above describes the state before these units and is kept as written.**
What remains outside both: C-100 (local-stack client test infrastructure), the
p4 u2c detector failures, and B-43.
