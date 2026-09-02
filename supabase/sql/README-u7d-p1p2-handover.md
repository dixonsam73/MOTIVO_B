# U7d — P1/P2 BLOCKED ON THE ACCOUNT HOLDER. APPLY FILES READY AND REHEARSED. 2026-09-02

**NOTHING WAS DEPLOYED. NO PRODUCTION WRITE OF ANY KIND. Device A's
`pending_cleanup_at` is untouched at `2026-11-01 15:16:44+00`. No dry run has
run, because the objects it needs do not exist in production yet.**

---

## 1. WHY I STOPPED — A PROCEDURAL CONSTRAINT, NOT A FAILURE

`supabase/README.md` is explicit, and it names this exact moment:

> **NEVER RUN `supabase db push` AGAINST PRODUCTION. IT WOULD REPLAY EVERY
> MIGRATION, INCLUDING THE LOCAL BASELINE REPRODUCTION.**
>
> *"This is recorded here rather than only in the U5 package because `db push` is
> the obvious command to reach for, and the next person to deploy — at U6 or U7 —
> will not necessarily have read a unit-specific file first."*

**That warning was written for this step.** Production's
`supabase_migrations.schema_migrations` records none of the existing migrations,
so `db push` would attempt the local baseline reproduction against the live
database.

The two documented alternatives are also closed:

- **`supabase db query --linked` is SINGLE-STATEMENT.** Enough for the read-only
  checks below; not enough for a migration.
- **Folding a migration into one `DO $$ … $$` block is explicitly forbidden** —
  it means editing the file to make the mechanism accept it.

> *"Multi-statement production SQL goes through the account holder in the SQL
> editor."*

**So P1 and P2 are yours to run.** Everything either side of them is done.

---

## 2. WHAT IS DONE — READ-ONLY VERIFICATION, ALL PASSED

| Check | Result |
|---|---|
| **Production vs committed snapshot** | **`capture-schema.sh` produced an EMPTY DIFF across all ten surfaces.** Production is byte-identical to `supabase/schema/`, so the §2 delta prediction is valid |
| `SERVICE_ROLE_KEY` | **present** (digest only; value never read) |
| `APPLE_IAP_KEY_ID`, `_ISSUER_ID`, `_BUNDLE_ID`, `_P8_B64` | **all four present** |
| `APPLE_API_BASE_URL_SANDBOX` / `_PRODUCTION` | **ABSENT — required.** The worker will reach the real Apple hosts |
| B-23, pre-deploy | **GATE NOT MET — 23 problems**, every one a U7b/U7c object. The correct pre-deploy state |
| Production state at handover | users **17**, posts **101**, comments **5**, follows **9**, attachment objects **15**, conflicts **0**, `pg_cron` **0** |
| Device A schedule | **`2026-11-01 15:16:44+00` — UNCHANGED** |
| `connected_member()` / `membership_state()` | **false** / **`sandbox_only`** |

---

## 3. THE TWO APPLY FILES — READY, AND REHEARSED BOTH WAYS

`supabase/sql/2026-09-02-u7b-apply-production.sql` **then**
`supabase/sql/2026-09-02-u7c-apply-production.sql`. **Order is load-bearing:**
U7c replaces a function U7b creates.

Each is the migration **verbatim**, wrapped `begin; … commit;`, with a guard
**inside the transaction** asserting the state it just produced, ending in a
`SELECT` that returns exactly one row.

**REHEARSED AGAINST A FAITHFUL PRE-DEPLOY LOCAL STATE** — the two migrations
withheld, then the production fixture reproduced (1 membership row, the real
`original_transaction_id`, the real schedule, 101 posts):

```
U7b APPLIED | new_columns 2 | new_functions 2 | schedule_untouched 2026-11-01 15:16:44+00
U7c APPLIED | cleanup_functions 4 | preview_volatility s | b33_oracle_reachable f
            | schedule_untouched 2026-11-01 15:16:44+00
```

**AND THE GUARDS WERE PROVEN TO FIRE, because a guard that cannot fire is
worthless (C56-7):**

| Deliberate fault | Result |
|---|---|
| Re-run U7b on an already-applied database | **`ERROR: column "cleanup_completed_at" already exists`** — refuses; no silent double-apply |
| `pending_cleanup_at` tampered before apply | **`ERROR: U7b guard: pending_cleanup_at was altered by the deploy`**, and **0 columns present afterwards** — the whole transaction rolled back |

**Two guards are worth naming because they protect settled properties rather than
this deploy:**

- **`b33_oracle_reachable` must be `f`.** U7c's guard raises if
  `connected_member(uuid)` becomes executable by **any** role. B-33 cannot be
  weakened by this deploy without the transaction aborting.
- **`preview_volatility` must be `s`.** The preview path is `STABLE`, so
  PostgreSQL structurally forbids it acquiring a lease.

---

## 4. HOW TO RUN P1 AND P2

1. Open the Supabase SQL editor on the production project.
2. Paste the **entire** contents of `2026-09-02-u7b-apply-production.sql`. Run
   **once**. **Expect exactly one row** reading `U7b APPLIED`, `new_columns 2`,
   `new_functions 2`, `schedule_untouched 2026-11-01 15:16:44+00`.
3. Then the **entire** contents of `2026-09-02-u7c-apply-production.sql`. **Expect
   one row** reading `U7c APPLIED`, `cleanup_functions 4`, `preview_volatility s`,
   **`b33_oracle_reachable f`**, `schedule_untouched 2026-11-01 15:16:44+00`.

**Do not split either file across Run clicks** — Studio gives no session
continuity between them, so a split `BEGIN`/`COMMIT` reads exactly like success.

**"Success. No rows returned." IS A FAILURE HERE.** That is the U6a signature: it
means the intended text did not run. Anything other than the one expected row —
including an error — means **stop and tell me**; nothing has been applied,
because the guard is inside the transaction.

---

## 5. WHAT I WILL DO THE MOMENT YOU CONFIRM P1/P2 LANDED

Each of these is mine, and none needs you:

1. **P2 verification** — recapture production, score the delta (`columns` +2,
   `functions` +5 new/1 modified, `function_grants` **+15**, everything else
   identical), and confirm **B-23 GATE MET**.
2. **P3** — `supabase functions deploy membership_cleanup_v1`, verify the
   **deployed bundle** (not the tree), and confirm a wrong bearer gets **401** in
   production.
3. **Re-capture the independent prediction** immediately before touching the
   fixture.
4. **The fixture mutation** — the single guarded statement in
   `README-u7d-preflight.md` §7, whose `WHERE` clause *is* the guard, so a guard
   failure returns **zero rows**. It is a single statement, so it goes through
   `supabase db query --linked` and needs nothing from you.
5. **The dry run**, and the comparison against §5 of the preflight.
6. **STOP** for your P5 destructive authorisation.

---

## 6. THE INDEPENDENT PREDICTION — UNCHANGED AND RE-VERIFIED AT HANDOVER

Derived from read-only production `select`s, before any deploy, and **not** from
the worker in any mode. Re-checked at handover: **identical**.

**Subject `5ae3faab…`, after one cleanup:**

| | Before | After | |
|---|---|---|---|
| own posts | 1 | **0** | REMOVE |
| storage objects under the subject | 1 | **0** | REMOVE |
| follows (1 in, 1 out) | 2 | **0** | REMOVE |
| comments on the subject's own post | 3 | **0** | **CASCADE** — authored by `Samuel Dixon` / `samueldixon`, **authorised as disposable 2026-09-02** |
| the subject's comment on another member's post | 1 | **1** | **RETAIN** |
| `account_directory` row + `display_name` | 1 | **1** | **RETAIN** |
| `auth.users` | 17 | **17** | **RETAIN** |
| `membership` / `membership_binding` | 1 / 1 | **1 / 1** | **RETAIN** |
| shares, views, connected attachments, avatar objects | 0 | 0 | nothing to exercise |

**Globals:** posts **101 → 100**, comments **5 → 2**, follows **9 → 7**,
attachment objects **15 → 14**; users, directory, avatars,
`connected_attachments`, bindings and conflicts **unchanged**.

**Still not exercised in production**, unchanged from the preflight and accepted:
reference-counted shared sent attachments, received references, received shares,
comment-views, avatar removal and C-33 ordering, and B-19's addressed-on-others'-
posts retention. **Local e2e (75/75) remains the coverage for all of them.**

---

## 7. NOTHING ELSE HAPPENED

Not deployed. No production write. Timestamp untouched. No cleanup. No scheduler.
C-58 not started. **Awaiting P1/P2 by the account holder.**
