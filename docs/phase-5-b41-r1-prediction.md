# B-41 / R1 — restore migration parity with production. Prediction, before any change

2026-09-14. **Local reproduction only; production is not touched.** Separate from
B-39 and from B-42/R2, which does not start until this unit's gate is proven.
C-100 is out of scope.

## 1. The 19 problems and where each missing statement comes from

Measured on a fresh `supabase db reset --local` against `supabase/schema/`:

| Surface | Production (snapshot) | Local rebuild | Missing statement, from the record of what ran |
|---|---|---|---|
| `posts_insert_owner.with_check` | `… AND (owner_user_id = auth.uid()) AND (is_public = true)` | no `is_public` conjunct | `supabase/sql/2026-09-04-u2s-posts-insert-privacy.sql` — applied to production, never a migration |
| `account_privacy_self_v1`, `…_set_follow_requests_v1`, `…_set_lookup_v1`, `…_upsert_v1` | anon and service_role cannot execute; authenticated direct; `public_execute` false | ACL `{=X/postgres,postgres=X/postgres,authenticated=X/postgres}` — PUBLIC still holds EXECUTE | `docs/phase-5-d-cp1-migration-prediction.md` §4: `revoke all on function <each of the five> from public, anon, service_role;` + `grant execute on function <the four RPCs> to authenticated;` — planned, and absent from the committed migration |
| `tg_account_directory_requires_band` | no role can execute | default ACL (PUBLIC EXECUTE) | same §4 statement |
| `tg_stamp_avatar_version` | no role can execute | default ACL (PUBLIC EXECUTE) | `docs/phase-4-u5-acceptance.md`: the function "picked up Supabase's default public EXECUTE" and "Four REVOKEs later" matched `tg_set_entitled_until` — the revokes were never added to a migration |

**Cause, established from the records rather than inferred: statements applied
to production and never added to `supabase/migrations/`** — not a difference in
default privileges between environments. The migration is the same either way,
because an explicit revoke makes the end state a property of the file (U3's
pattern).

## 2. The change

One new migration, `20260914130000_b41_restore_production_parity.sql`, carrying
exactly those three statement groups. **No historical migration is edited.**

## 3. Gate predictions (B-23, `supabase/verify-baseline.sh`)

B-39's migration is local-only, so the gate is proved in three runs, each after
`supabase db reset --local`:

- **G1 — R1 present, B-39 migration moved aside:** **GATE MET**, the only
  difference being the standing, verified `account_id_format` exception.
- **G2 — R1 and B-39 both present:** GATE NOT MET with **exactly three problems**
  — `functions connected_member`, `functions membership_apply_state_v1`,
  `functions membership_entitled_until` — and nothing else.
- **G3 — negative control, R1 moved aside, B-39 present:** the original **19
  problems** plus the same three function rows (22), proving R1 is what closes
  them.

**Precaution:** B-39's migration sha256 is recorded before it is moved and
verified identical after it is restored. The final working state has both
migrations present.

## 4. Suite predictions — per-assertion result identical to the recorded baselines

Reset-per-suite baseline (2026-09-14, B-39 applied, no R1):
u3 90/1 · u4 98/1 · u5 59/0 · u6b exit 3 at its first fixture step · u7 half A
47/0 · u7 half B 20/0 · p4/u7 19/7 · b39 acceptance `post` 35/0.

No-reset baseline (same state): p4/u2s 12/0 · p4/u2c 18/2 · p4/u2b 16/0 ·
p4/u2a2 22/0 · p4/u2a 16/0 · p4/u1-baseline 10/6 (its six documented flips) ·
u5/client-structural 60/0.

**Prediction: every one of those produces the same pass/fail for every assertion
id after R1.** R1 changes only privileges and one policy; no suite fixture
depends on anon or service_role executing the CP-1 functions, and u6b and p4/u7
still abort for B-42's reason because R2 has not run. `b39/modules.ts` stays
6/6; `b39/notification-ordering.sh` still fails exactly N4a/N4b/N5a/N5b.

**Recorded, not in scope:** p4/u2c U2c-2 and U2c-4 fail at baseline because the
enclosing-function detector now reports `discardTemporaries`, the helper C-65
nested inside `uploadPost`; `BackendShim.swift` is unmodified in this tree, so it
predates this work.

Any miss is recorded as a miss and diagnosed before continuing.

## 5. Results (2026-09-14) — every prediction met

| Check | Result |
|---|---|
| **G1** — R1, B-39 set aside | **GATE MET**, only the standing `account_id_format` exception |
| **G2** — R1 + B-39 | exactly the three B-39 function rows |
| **G3** — negative control, no R1 | 22 = the original 19 + the three B-39 rows |
| B-39 migration sha256 | `c3295a7e…` before and after — identical; both migrations present |
| u3, u4, u5, u7 A/B, p4/u7 | per-assertion results **identical** to baseline (90/1, 98/1, 59/0, 47/0, 20/0, 19/7) |
| u6b | aborts at the same first fixture step (B-42, unchanged) |
| p4 u2s, u2c, u2b, u2a2, u2a, u1-baseline, u5 client-structural | **identical** (12/0, 18/2, 16/0, 22/0, 16/0, 10/6, 60/0) |
| b39 acceptance / modules / ordering | 35/0 · 6/0 · 11 passed with exactly N4a/N4b/N5a/N5b failing |

**The local rebuild now reproduces production.** Production was not touched.
