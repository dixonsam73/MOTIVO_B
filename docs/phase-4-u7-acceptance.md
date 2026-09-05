# P4-U7 / C-58 — IMPLEMENTED AND LOCALLY VERIFIED. NOT YET DEPLOYED

**Prediction `cac7d5b`, committed before any mutation.**
Accepted checkpoints: client `7744027`, server `dfba1d8`, U6 `8aaced4`.

**PRODUCTION IS UNCHANGED — verified read-only after the work:**
`get_account_directory_by_user_ids` is still `d0d1322e926fa0c9c385c6272395c207`
with `has_follow_scope = false`. The apply file is
`supabase/sql/2026-09-05-u7-c58-follow-scoped-attribution.sql` and awaits an
explicit decision to run it.

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

- **Not deployed to production.** Local only.
- **Does not broaden discovery.** `search_account_directory` is untouched; a
  lapsed member stays undiscoverable (`U7-C3`/`C4`, `U7-E8`).
- **Does not weaken the membership model.** No policy changed (`U7-E7`), grants
  unmoved (`U7-E5`), the gate remains the first disjunct (`U7-E2`), and the kill
  switch restores the pre-U7 world completely (`U7-D3`).
- **No subject-side filter** (`U7-E1`, which is U6b-J3).
- **Not device-verified.** Belongs to the Phase 4 physical-device QA pass.

---

## 7. REMAINING PHASE 4 OBLIGATIONS

- **P4-U8** — **D-1**, **D-2** (expected to *dissolve* under U2, not to be
  implemented), **C-32** (jointly with RC), and the **App Store privacy
  disclosure alignment**.
- **The physical-device QA pass**, carrying **U2b's** and **C-34's** device
  verification.
- **This unit's production deployment.**
