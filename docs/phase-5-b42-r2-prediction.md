# B-42 / R2 — make four local suites run to completion again. Prediction, before any change

2026-09-14. **Starts only after B-41/R1 proved GATE MET** (`docs/phase-5-b41-r1-prediction.md` §5).
Tests only — no migration, no application code, no production. C-100 is out of scope.

**Rule: fix fixtures and stale counts; never weaken or delete an assertion. Any
failure among assertions that have not executed against the current schema is a
FINDING to diagnose, never a fixture to adjust.**

## 1. The four breaks, measured

| Suite | Break | Baseline (after R1) |
|---|---|---|
| `u6b/acceptance.sh` | fixture inserts `account_directory` rows (A_OK, A_LAP) with no declared band; CP-1's `tg_account_directory_requires_band` refuses; the `ON_ERROR_STOP` heredoc exits 3 | only `U6b-fix1` executes; **56 of 57 assertions have not run since CP-1** |
| `p4/u7-acceptance.sh` | same refusal at its directory insert (A_FOL, A_STR, A_REQ, A_REV, A_LAP); the **follows** inserts share that heredoc, so they never land either | 19 passed / 7 failed; the 7 are consequences of the aborted fixture |
| `u3/acceptance.sh` A16b | `count(*) = 10` triggers in public+storage; now 12 (P4-U5 `tg_directory_avatar_version`, CP-1 `tg_directory_requires_band`) | 90/1 |
| `u4/acceptance.sh` A57c | `count(*) = 6` triggers in public; now 8 | 98/1 |

## 2. The changes

- **u6b and p4/u7:** before the directory insert, give each directory identity an
  `account_privacy` row with **exactly what CP-1's `account_privacy_upsert_v1`
  writes for an adult** — `age_band`, `lookup_set_under_band` and
  `follow_requests_set_under_band` all `band_18_plus`, `lookup_enabled` and
  `follow_requests_enabled` true. That reproduces the pre-CP-1 world both suites
  were written against (discoverable, requests open). The band is **setup, not
  subject**: neither suite asserts anything about age bands.
- **u3 A16b and u4 A57c:** replace the count with the **exact ordered set of
  trigger names**. **Stronger, not weaker**: a count passes a swapped or renamed
  trigger; a named set fails it, and still fails on any added trigger.

  u3 (public + storage, 12):
  `public.account_directory.tg_directory_avatar_version`,
  `public.account_directory.tg_directory_entitled_until`,
  `public.account_directory.tg_directory_requires_band`,
  `public.connected_attachments.connected_attachments_recipient_update_guard`,
  `public.follows.tg_follows_entitled_until`,
  `public.membership.tg_membership_propagate`,
  `public.post_shares.tg_shares_entitled_until`,
  `public.posts.tg_posts_entitled_until`,
  `storage.buckets.enforce_bucket_name_length_trigger`,
  `storage.buckets.protect_buckets_delete`,
  `storage.objects.protect_objects_delete`,
  `storage.objects.update_objects_updated_at`.
  u4 (public, 8): the eight `public.*` names above.

## 3. Predictions (each suite after its own `supabase db reset --local`, R1 + B-39 present)

- **P1 — u3 91/0 and u4 99/0**: A16b and A57c pass; every other assertion identical to the R1 run.
- **P2 — u6b 57/57.** Groups A (propagation), B (drift), C (client-supplied
  timestamp overwritten), D (inert when off), E (viewer matrix incl. retry-without-
  grace denied), F (subject visibility), G (retention and discovery), H–J
  (carve-outs, grants, G10), K (structure) and L (C-59 write-deny, by database
  outcome). **Basis:** 64/64 at P4-U5 on 2026-09-05, the day before CP-1; every
  `posts` insert in the suite uses `is_public = true`, so R1's shared-only
  conjunct does not change what L1/L3/L8 test; no fixture uses `apple_status = 5`,
  so B-39 does not reach it. **Stated uncertainty:** CP-1, P4-U7 and R1 changed
  the schema after that run, and these assertions have not executed since, so
  this is a prediction, not an assumption — **any failure is a finding.**
- **P3 — p4/u7 26/26**: the seven current failures pass once the follow rows land,
  and the 19 current passes stay passing.
- **P4 — unchanged everywhere else**: u5 59/0, u7 A 47/0, u7 B 20/0, b39 35/0,
  p4 u2s 12/0, u2c 18/2, u2b 16/0, u2a2 22/0, u2a 16/0, u1-baseline 10/6,
  u5 client-structural 60/0, b39 modules 6/0, b39 ordering 11 with N4/N5 failing.
- **P5 — gate unchanged**: exactly B-39's three function rows (R2 touches no schema).

Any miss is recorded as a miss and diagnosed before continuing.

## 4. Results (2026-09-14) — outcomes as predicted; one counting miss

| Check | Result | Against prediction |
|---|---|---|
| u3 | **91/0** — only A16b moved (FAIL → PASS) | P1 met |
| u4 | **99/0** — only A57c moved (FAIL → PASS) | P1 met |
| u6b | **runs to completion: 64 passed, 0 failed** | **outcome met; count MISSED** — see below |
| p4/u7 | **26/0** — exactly the seven failures moved to PASS; the 19 passes unchanged | P3 met |
| u5, u7 A, u7 B, b39, p4 u2s/u2c/u2b/u2a2/u2a/u1-baseline, u5 client-structural | per-assertion **identical** (59/0, 47/0, 20/0, 35/0, 12/0, 18/2, 16/0, 22/0, 16/0, 10/6, 60/0) | P4 met |
| b39 modules / ordering | 6/0 · 11 passed with exactly N4a/N4b/N5a/N5b failing | P4 met |
| B-23 gate (R1 + B-39) | exactly B-39's three function rows | P5 met |

**No assertion that had not executed since CP-1 failed**, so there is no finding
to diagnose — U6b's groups A–L, including C-59's write-deny group L, pass against
the current schema.

**Prediction miss, recorded as one:** P2 predicted **57/57**, counting lines that
begin `is U6b-`. The suite executed **64** unique assertions — its P4-U5 figure —
because seven ids are built in loops the count could not see: `U6b-D-$2` (line
100: the gate stays inert for ent/lap/non/sbx while unbound) and `U6b-K1-$R`
(line 152: no role holds privilege on `shadow_enforcement_stat`). The outcome was
unaffected; the counting method was wrong. **Count executed assertions from the
run, not from the source.**

**What this establishes, stated without overreach:** every local acceptance
suite now runs to completion, and the B-23 gate differs from production only by
B-39's intended local-only change. **It is not a clean sweep:** two red results
remain and neither is R2's — p4 u2c **U2c-2/U2c-4** (the enclosing-function
detector reports `discardTemporaries`, the helper C-65 nested inside
`uploadPost`; pre-existing, **filed as C-101** after an independent review the same day), and p4 u1-baseline's six
documented flips, which are that suite's intended pinned state.
