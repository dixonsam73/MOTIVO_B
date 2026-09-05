# P4-U7 / C-58 — LIVE IN PRODUCTION, 2026-09-05

**Prediction `cac7d5b`, committed before any mutation.**
Accepted checkpoints: client `7744027`, server `dfba1d8`, U6 `8aaced4`.

**DEPLOYED TO PRODUCTION 2026-09-05** from
`supabase/sql/2026-09-05-u7-c58-follow-scoped-attribution.sql`, executed manually
by the account holder. Deployment prediction `08e719f`, committed before the run.
**Every prediction matched and nothing was repaired forward.** §8 is the
production evidence; it was gathered independently rather than read off the
apply's own output.

---

## 1. WHAT CHANGED

**One function, one additional disjunct.** Resolution is now also permitted when
the viewer holds an **APPROVED** follow with the requested `user_id`, **in
either direction**:

```sql
and (
  (select public.enforcement_gate('rpc.get_account_directory_by_user_ids'))
  or exists (
    select 1 from public.follows f
    where f.status = 'approved'
      and ((f.follower_user_id = auth.uid() and f.followed_user_id = ad.user_id)
        or (f.followed_user_id = auth.uid() and f.follower_user_id = ad.user_id))
  )
)
```

**No client change.** The lists already render `overrideDisplayName` from
resolved directory accounts; supplying the row is sufficient.

---

## 2. `approved`, NOT "any row the viewer can already see"

The register's criterion is *"the viewer already knows the row exists"*, and its
literal reading — key on any `follows` row the viewer can SELECT — was
**considered and rejected**.

An unentitled viewer cannot manufacture a relationship **today** only because
`follows_insert_requester` carries `enforcement_gate('follows.insert')` —
**measured, not assumed**. Keying on mere visibility would therefore **borrow its
safety from a neighbouring policy**: were that gate ever removed, this RPC would
become a self-serve **UUID → identity oracle** — request to follow any uuid, then
resolve it — which is exactly the general resolver B-5 hardened these RPCs
against.

**`approved` makes the safety intrinsic.** An approved row cannot be produced by
an unentitled viewer by any route, because approval is a **gated UPDATE
performed by the other party** (`follows_update_approve_by_followed`). This is
B-24's own rule applied: an authority predicate must not contain a branch whose
safety rests on operational discipline.

**The accepted cost, stated rather than glossed:** incoming and outgoing
*requests* keep the `User • <suffix>` fallback for a lapsed viewer. A lapsed
viewer **cannot approve anything anyway** — that UPDATE is gated — so a request
is not actionable beyond declining, and the register's requirement concerns *"a
surviving follow relationship … allowed to manage and remove it"*.

---

## 3. MEASURED BEFORE AND AFTER — every prediction held

Local stack, **enforcement ON**, lapsed viewer (`connected_member = false`):

| # | case | BEFORE | AFTER |
|---|---|---|---|
| **P1/P2** | approved follow, viewer → author | **0** | **1** |
| | approved follow, author → viewer | **0** | **1** |
| **P3** | **stranger, no relationship** | 0 | **0** |
| **P4** | **`requested` relationship only** | 0 | **0** |
| **P5** | entitled viewer → lapsed author | 1 | **1** |
| **P6** | `search_account_directory` as the lapsed viewer | 0 | **0** |
| **P7** | G10 subject predicate present | false | **false** |
| **P8** | grants anon/authenticated/service_role | f/t/f | **f/t/f** |

**P3 and P4 are the discriminators.** Without them P2 would be satisfied by
simply ungating the RPC — the global fix the register rejects. They are what
prove the permission is bounded by an existing approved relationship rather than
granted at large.

**Acceptance suite:** `supabase/tests/p4/u7-acceptance.sh`, **26 passed, 0
failed**. Run against the **pre-U7 definition** it fails **3** — `U7-B3`, `U7-B4`
(the behavioural unit) and `U7-E3` (the structural claim) — while the negative
cases `U7-C1`/`U7-C2` correctly pass in **both** worlds, which is what they must
do to be worth anything.

---

## 4. A PREREQUISITE DEFECT FOUND BY THIS UNIT — U5 NEVER REACHED `migrations/`

**The local reproduction had drifted from production, and it was caught by a
failure rather than by a review.** The `CREATE OR REPLACE` — correct against
production — failed locally with:

```
ERROR:  cannot change return type of existing function
```

**Cause: `supabase/sql/2026-09-05-u5-avatar-version.sql` was applied to
PRODUCTION and never added to `supabase/migrations/`.** So
`supabase db reset --local` rebuilt a stack whose directory RPCs returned **six**
columns while production returns **seven**.

**This is a B-23 fidelity defect, not a cosmetic one.** Every local rehearsal of
a change to these objects would have been a rehearsal of the wrong object —
and B-23's entire value is that the local stack is a faithful reproduction.

**Repaired by `supabase/migrations/20260905120000_u5_avatar_version.sql`**, which
replays U5's production DDL locally and **changes nothing in production**.
Fidelity is now *measured*, not asserted: after a reset both RPCs are
**byte-identical to the committed production snapshot** —
`d0d1322e926fa0c9c385c6272395c207` and `077f73f28c5d5c477635c9878a35d790`.
Pinned by `U7-F1`–`F4`.

**U7's own change is in `migrations/` too**, and the migration and the guarded
apply file produce the **identical** definition (`48e7f743196e3ed43438ce0a8c449ea6`).

---

## 5. GATES

| gate | result |
|---|---|
| `u7-acceptance.sh` | **26 passed, 0 failed** |
| `u6b/acceptance.sh` | **64 passed, 0 failed** |
| `u2a / u2a2 / u2b / u2c / u2s / u5-client` | 16 / 22 / 16 / 20 / 12 / 30, **all 0 failed** |
| `u1-baseline.sh` | 10 passed, **6 failed — the standing expected inversions** |
| Debug / Release | **BUILD SUCCEEDED** / **BUILD SUCCEEDED** |
| `MOTIVOTests` | **TEST SUCCEEDED**, 49 passed |
| production delta | **none** — still `d0d1322e…` |

The eight in-transaction guards all passed on apply and the statement returned a
row, so *"no rows returned"* would have been the symptom rather than the
disguise.

---

## 6. WHAT THIS DOES NOT DO

- **Does not broaden discovery.** `search_account_directory` is untouched; a
  lapsed member stays undiscoverable (`U7-C3`/`C4`, `U7-E8`).
- **Does not weaken the membership model.** No policy changed (`U7-E7`), grants
  unmoved (`U7-E5`), the gate remains the first disjunct (`U7-E2`), and the kill
  switch restores the pre-U7 world completely (`U7-D3`).
- **No subject-side filter** (`U7-E1`, which is U6b-J3).
- **Not device-verified.** Belongs to the Phase 4 physical-device QA pass.

---

## 8. PRODUCTION DEPLOYMENT — INDEPENDENTLY VERIFIED

**The apply reported one row matching every predicted value. That is not the
evidence** — a procedure whose success is reported by the thing being asked to
act is unverified. Everything below was read back from production separately.

### Structure

| check | predicted | **production** |
|---|---|---|
| `get_account_directory_by_user_ids` def md5 | `48e7f743196e3ed43438ce0a8c449ea6` | **matches** |
| grants anon / authenticated / service_role | `f/t/f` | **`f/t/f`** |
| SECURITY DEFINER, `search_path=public` | unchanged | **unchanged** |
| follow scope present | true | **true** |
| G10 subject predicate | false | **false** |
| source mentions `requested` | false | **false** |
| `search_account_directory` def md5 | `077f73f28c5d5c477635c9878a35d790` | **unchanged** |

**The md5 is byte-exact to the locally rehearsed function**, and the local stack
had been confirmed byte-identical to production beforehand — so production
received exactly the rehearsed text, not merely something equivalent.

**Snapshot recapture: ONE line, in ONE file.** `functions.json`, exactly one
definition changed (`d0d1322e…` → `48e7f743…`), **zero functions added, zero
removed**, and the other nine snapshot files untouched.

### Behaviour, on real production rows — no fixture was created

UUIDs as `md5[0:8]`. Every viewer below is genuinely unentitled
(`connected_member` false).

| # | case | viewer → subject | before | **after** |
|---|---|---|---|---|
| 1 | approved follow, follower resolves followed | `41aacc65` → `daed2252` | **0** | **1** |
| 2 | approved follow, **reverse** direction | `daed2252` → `41aacc65` | — | **1** |
| 3 | **stranger**, zero relationship rows | `41aacc65` → `64ffb132` | 0 | **0** |
| 4 | **`requested` only** (1 requested, 0 approved) | `1fbf664a` → `965caeff` | 0 | **0** |
| 5 | discovery by exact display name | `41aacc65` searching a name it **can now attribute** | 0 | **0** |

**Case 1 is C-58 closing on the exact pair used for the pre-deployment
baseline** — the same viewer and subject that returned 0 before the run.

**Case 5 is the sharpest result.** The same viewer resolves that subject's
identity through the attribution RPC **and still cannot discover them by name**.
Attribution widened; discoverability did not (D-7 / B-15).

**Cases 3 and 4 are the discriminators in production**, not merely locally.
Without them, case 1 would have been equally satisfied by ungating the RPC — the
global fix the register rejects.

### Census — unchanged on every measure

identities **17**, directory rows **17**, membership **1**, binding **1**,
follows **9** (4 approved + 5 requested), posts **101**, comments **5**,
attachment objects **10**, avatar objects **3**, `follows` policies **4**,
enforcement **true**, `u6b_bound_at` **still set**.

### THE ONE CHECK THAT COULD NOT BE MADE, RECORDED AS A LIMIT

**"Entitled viewer → lapsed author remains unchanged" is NOT verified in
production, because there are ZERO entitled identities.** Grandfathering is
retired and the single `membership` row is Sandbox, so `connected_member` is
false for all 17. **Stated before the run, not after.**

It rests on three things instead: the local rehearsal (`U7-D1`, and U6b's own
`G1`), the byte-identical function text, and the structural fact that the gate
remains the **untouched first disjunct** — an entitled viewer short-circuits
before the new clause is ever evaluated. **Not folded into a pass.**

---

## 7. REMAINING PHASE 4 OBLIGATIONS

- **P4-U8** — **D-1**, **D-2** (expected to *dissolve* under U2, not to be
  implemented), **C-32** (jointly with RC), and the **App Store privacy
  disclosure alignment**.
- **The physical-device QA pass**, carrying **U2b's** and **C-34's** device
  verification.

