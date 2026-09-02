# U7b — RESULTS, SCORED AGAINST `README-u7b-predictions.md`. 2026-09-02

**LOCAL ONLY. NOT DEPLOYED. PRODUCTION UNTOUCHED.** No `supabase link`, no
`db push`, no `functions deploy`, no production query of any kind was run.

**Two halves, two suites, two exit codes: HALF A 45/45, HALF B 20/20.** Nothing
was repaired forward. Three predictions missed and all three are recorded below
as misses, with what they change.

---

## 1. SCORE

| | Predicted | Measured | |
|---|---|---|---|
| Half A behavioural | all pass | **45 passed, 0 failed**, exit 0 | ✅ |
| Half B behavioural | all pass | **20 passed, 0 failed**, exit 0 | ✅ |
| Structural, `columns` | **+2** | **+2** | ✅ |
| Structural, `functions` | +2 new, 1 modified | **+2 new, 1 modified** | ✅ |
| Structural, `function_grants` | **+2** | **+6** | ❌ **MISS 1** |
| Structural, `constraints` | 0 | 0 (+1/−1 = the declared standing exception) | ✅ |
| `policies`, `rls_enabled`, `triggers`, `table_grants`, `column_grants`, `storage_buckets` | IDENTICAL | **all IDENTICAL** | ✅ |
| B-23 pre-deploy | not predicted as a number | **GATE NOT MET, 11 problems, every one a U7b object** | ❌ **MISS 2** |
| Regression suites | all green, **zero** failures | **one failure — u4 `A45`** | ❌ **MISS 3** |

---

## 2. THE THREE MISSES

### MISS 1 — `function_grants` is +6, not +2. A UNITS ERROR IN THE PREDICTION

**The privilege CONTENT is exactly as predicted.** `service_role` true on both
new functions; `anon`, `authenticated` and `PUBLIC` false on both. Nothing was
over-granted.

**What was wrong is the unit.** The capture emits **one row per (function,
grantee)** across `anon`, `authenticated` and `service_role` — so each new
function contributes **three** rows, two of them recording a denial:

```
{"grantee":"anon",          "proname":"membership_due_for_cleanup_v1", "can_execute":false}
{"grantee":"authenticated", "proname":"membership_due_for_cleanup_v1", "can_execute":false}
{"grantee":"service_role",  "proname":"membership_due_for_cleanup_v1", "can_execute":true }
```

2 functions × 3 grantees = **6**. The prediction counted *grants written in the
migration* rather than *rows the capture emits*.

**THIS MATTERS FOR U7d AND IS THE MOST USEFUL THING THIS RUN PRODUCED.** Carried
into a production deploy unchanged, a **correct** outcome would have failed its
own committed gate — and the pressure at that moment is to "reconcile" the
number, which is repairing forward against a prediction that was simply
measured in the wrong unit. **U7d's committed figure is +6.**

### MISS 2 — the B-23 pre-deploy count was never predicted, and should have been

**Measured: GATE NOT MET, 11 problems**, and every one is a U7b object. This is
the *correct* pre-deploy result — U5b recorded the identical shape ("GATE NOT
MET, 20 problems pre-deploy, every one a U5b object; GREEN after deploy and
recapture"). The miss is that no number was committed for it, so there was
nothing to score.

**Itemised per half, which is the ratified condition** — the two halves'
predictions must stay independently attributable:

| Half | Problems | What |
|---|---|---|
| **A — cleanup primitive** | **10** | 2 functions present locally/absent in production, 2 columns, 6 function_grants |
| **B — born-lapsed floor** | **1** | `membership_apply_state_v1`: "UNAPPROVED difference in definition" |
| | **11** | |

**Half B contributing exactly 1 is itself evidence**: the writer replacement
changed one function definition and touched no column, no grant and no
constraint — which is what "the floor is the only change" means, measured rather
than asserted.

**U7d P2's committed prediction: 11 problems before, GATE MET after deploy and
recapture, with only the standing `account_id_format` exception.**

### MISS 3 — one regression assertion moved. THE ASSERTION WAS RIGHT

**Predicted zero regression failures. Measured one: u4 `A45`.**

A45 pins the **exact** set of `membership%_v1` functions `service_role` may
execute. U7b grants two more, so the set genuinely changed and A45 caught it.
**A correct assertion doing its job, not a defect** — and it was the *only*
assertion in any suite whose result moved.

**This is U5b's blast-radius lesson recurring, and I made the same mistake it
records.** U5b: *"'which assertions change their RESULT' is a different question
from 'which assertions mention the thing I am changing', and only the first one
matters."* The U7b prediction was written at the **schema-surface** level —
columns, functions, grants — which answers neither question. Predicting "all
suites stay green" was an assumption dressed as a prediction.

**Amended, not silently re-pointed**, in A45's own comment block, following how
`A45e` was handled for U5b. **Deliberately still a whole-surface exact set**: its
value is the negative half — that nothing *else* is reachable by `service_role` —
and that survives only while every future grant is forced to edit the line
consciously. It was not relaxed to a `LIKE` or a count.

**Four neighbouring assertions were checked and did NOT move, each for a reason
worth keeping:**

| | Why it held |
|---|---|
| `A45c` | *no* client EXECUTE on any `membership%` function — still **0**. **This is the assertion that would have caught an accidental client grant, and it stayed green.** |
| `A45d` | PUBLIC EXECUTE anywhere — still **0**; the explicit revokes hold |
| `A57d` | no `membership%` function deletes Domain 3 content — still **0**, and it now covers U7b's two functions **for free**. It is the assertion that fires if anyone ever moves deletion into SQL instead of the worker |
| `A57e` | no `membership%` function touches `storage.objects` — still **0**, same coverage gain |

---

## 3. EXACT SCHEMA AND FUNCTION CHANGES

Migration `supabase/migrations/20260902130000_u7b_cleanup_primitive.sql`, 435
lines. **Zero `delete` statements — verified over the file and over
`pg_get_functiondef` (A-26).**

### Columns — both on `public.membership`, both nullable

| Column | Purpose |
|---|---|
| `cleanup_completed_at timestamptz` | Records that cleanup ran. **Necessary because clearing `pending_cleanup_at` alone would make NULL mean two things** — "resubscribed in time" (QA C5) and "cleanup ran" (QA C7) — which are the two cases the phase must tell apart. `membership_cleanup_requires_end` already permits the clear, so no constraint moved |
| `cleanup_claimed_at timestamptz` | The lease. **Live from U7c, not U7e** |

### Functions

**NEW — `membership_due_for_cleanup_v1(p_limit integer default 25)`**, returns
`(user_id, environment, original_transaction_id)`, `security definer`,
`search_path = ''`, granted to `service_role` only.

- Selects identities with `pending_cleanup_at <= now()` and a free lease.
- **Returns EVERY membership row of each candidate identity, not only the due
  ones** — so the identity-scoped authority rule is structural. A worker that
  refreshes exactly what it was handed is automatically correct.
- **`p_limit` bounds IDENTITIES, not rows** (`group by user_id`), because a
  partial identity is the stale-authority defect by another route.
- Returns **no Apple state and no scheduling state**, so a caller cannot mistake
  the schedule for permission.

**NEW — `membership_cleanup_complete_v1(p_user_id uuid)`**, returns `jsonb`,
`service_role` only. Clears `pending_cleanup_at` and `cleanup_claimed_at` and
sets `cleanup_completed_at` on **all** scheduled rows of the identity, in one
statement. **Idempotent by predicate**: a second call matches nothing and returns
`{"rows": 0, "outcome": "noop"}` without overwriting the timestamp.

**MODIFIED — `membership_apply_state_v1`**: the born-lapsed floor and nothing
else. Signature, volatility, security, search_path and grants all unchanged; it
remains granted to **no role**.

### Privilege delta — two EXECUTE grants, and that is all

`anon`, `authenticated` and `PUBLIC` gain **nothing** (A-23/A-24, and u4's A45c
independently). `service_role` still holds **zero** table privilege on all six
membership tables (A-25).

---

## 4. BORN-LAPSED — BEFORE AND AFTER

**Before.** `membership_establish_v1` writes `entitlement_ended_at` and
`pending_cleanup_at` NULL on every insert path (F11), *including* when Apple
already reports the subscription expired. The first transition afterwards
computed `v_cleanup := v_ended + 60 days` from Apple's own dates — so for a
subscription that lapsed 240 days ago the schedule landed **180 days in the
past, due the instant it was written**. Zero quarantine, for the dormant
returning subscriber U5 exists to rescue.

**After.** When **no schedule existed** and the computed deadline is already
past, it is floored to `now() + 60 days`.

```sql
if v_prev.pending_cleanup_at is null and v_cleanup <= now() then
  v_cleanup := now() + c_quarantine;
end if;
```

**Measured, both directions (N24 — a guard that cannot fire is worthless, and one
that always fires is a different defect):**

| | Measured |
|---|---|
| **Born-lapsed** (B-3, B-5) | schedule `> now()` and `>= now() + 59d`; it differs from `entitlement_ended_at + 60d` by **more than 100 days** — the guard demonstrably **fired** |
| **Ordinary lapse** (B-6) | schedule equals `entitlement_ended_at + 60 days` **exactly** — the guard demonstrably **cannot fire** |
| **`entitlement_ended_at`** (B-4) | **still Apple's truth**, ~240 days past. Only the schedule is floored; **no fact is falsified** |
| **Anti-sliding** (B-7, B-8) | an existing schedule is **never** pushed out; `entitlement_ended_at` never slides forward |
| **Cancellation** (B-9) | entitled again → both columns NULL. QA C5's server half intact |
| **F11** (B-10) | establishment **still** schedules nothing, even against a long-expired subscription |
| **Staleness** (B-11) | an older `renewal_info_signed_date` is still `'stale'`, row unchanged |
| **UPDATE-ONLY** (B-12) | still no `insert into public.membership` in the writer |
| **Only change** (B-13b) | exactly **three** `v_cleanup :=` assignments — cancel, compute, floor |

---

## 5. THE CLEANUP PRIMITIVE CONTRACT, AND ITS RETENTION EFFECTS

**Retention effect on Domain 3 content: NONE. U7b removes nothing, from any
table or bucket.** The retention matrix is untouched because nothing here can
touch it — asserted structurally (A-26) and independently by u4's A57d/A57e,
which now cover these functions too.

**What U7b changes about a membership row is scheduling bookkeeping only:**
`pending_cleanup_at`, `cleanup_claimed_at`, `cleanup_completed_at`, `updated_at`.
**A-20 asserts that completion touches no Apple state** — `renewal_date`,
`entitlement_ended_at`, `binding_method`, `bound_at` and
`original_transaction_id` all byte-identical across a completion. **A-21 asserts
a control identity is byte-identical** across the whole suite.

**Selection is not authority, and the contract says so by omission:** the
selector returns no scheduling column, so the caller cannot read a schedule as
permission. Authority remains the live Apple read plus `connected_member()`,
performed by U7c.

---

## 6. LEASE — SCHEMA AND SEMANTICS, LANDED IN FULL

| | |
|---|---|
| Column | `membership.cleanup_claimed_at timestamptz` |
| Interval | **1 hour**, a literal in the selector (A-14) |
| Claimed | by the selector, in its own transaction, on **due rows only** (A-12) |
| Released | by `membership_cleanup_complete_v1` (A-16c), or by expiry |
| Crash recovery | a claim older than the lease makes the identity a candidate again (A-13) |
| Live from | **U7c**, the worker's first executable version |

**Why durable state and not `for update skip locked`.** A row lock lives for the
transaction that took it, and the selector's transaction **commits before** the
worker's Apple reads, deletions and completion happen. The lock would have
protected the milliseconds in which nothing dangerous occurs and nothing at all
during the minutes in which everything does — a clause a reviewer reads as
protection that provides none.

**The race fix is the repeated lease predicate inside the claiming UPDATE**, and
that repetition is load-bearing rather than redundant: two selectors can compute
the same candidate set because both read before either writes. The loser blocks
on the row lock; on resuming, READ COMMITTED re-evaluates the UPDATE's `WHERE`
against the **updated** row, sees the fresh claim and takes nothing. Without the
repeated predicate it would re-check only `uid in (...)`, still true, and both
runs would claim the same identity. **A-11 measures the outcome.**

**Not a job system, deliberately:** one timestamp, one predicate, one interval.
No queue, registry, heartbeat, retry counter or state machine.

---

## 7. SUITE RESULTS

| Suite | Result |
|---|---|
| **u7 `acceptance-primitive.sh`** (Half A) | **45 passed, 0 failed** — exit 0 |
| **u7 `acceptance-bornlapsed.sh`** (Half B) | **20 passed, 0 failed** — exit 0 |
| u3 `acceptance.sh` | 91 passed, 0 failed |
| u4 `acceptance.sh` | **99 passed, 0 failed** — after A45 amended; **98/1 before** |
| u4 `e2e.sh` | 43 passed, 0 failed |
| u5 `acceptance.sh` | 59 passed, 0 failed |
| u5 `e2e.sh` | 62 passed, 0 failed |
| u5 `client-structural.sh` | 60 passed, 0 failed |
| u6a `acceptance.sh` | 3 passed, 0 failed |
| u6b `acceptance.sh` | 64 passed, 0 failed |
| **u4 `modules.ts`, u5 `modules.ts`** | **NOT RUN — no `deno` on this machine.** Recorded as not run, never as passed |

**On the two not-run suites.** They are Deno tests over `_shared/appstore`
TypeScript, and **U7b changed no TypeScript at all** — zero files under
`supabase/functions/`, so they have no U7b-reachable surface. That is a stated
sufficiency argument, not a claimed pass, and it is exactly the form Phase 2 used
for its three source-verified closures. **They must be run before U7c is scored**,
because U7c is entirely TypeScript.

**u4's `A57f` — `pg_cron` extension count 0 — STILL PASSES.** U7b adds no
scheduler. The assertion that would fail if it did is the assertion working, and
U7e must amend it consciously rather than delete it.

**A run tally worth recording: two halves, 65 assertions, and the FIRST run of
Half A failed 5 of them.** All five were defects in the assertions themselves —
a fixture miscount (8 rows written, 9 asserted) and four `jsonb` patterns using
`jsonb_pretty` spacing against plain output. **Correcting them was not repairing
forward, and the reason is specific rather than a judgement call:** A-16b, A-16c,
A-16d and A-19 assert the same completion behaviour at the **column** level,
share none of the defective string format, and **passed on that first run** — so
the underlying fact was independently witnessed before any expected value was
touched. Had the JSON assertions been the only evidence, matching them to
observed output would have been exactly the forbidden move.

---

## 8. ONE GENUINE ISSUE THAT CHANGES U7c's DESIGN

**The dry-run / execute split must NOT be a late branch around the removal
calls, and the lease is why.**

The obvious implementation runs the whole pipeline and skips the deletions when
`mode = "dry_run"`. **But the selector claims a lease as a side effect of being
called at all.** A dry run would therefore claim every identity it inspected and
hold it for an hour — so an operator who dry-runs and then, seeing the output,
authorises an execute would find the execute **returns nothing**, because its own
dry run is still holding the claims. The failure looks exactly like "there was
nothing to do", which is the most dangerous possible misreading at an
authorisation point, and it lands precisely at U7d P4→P5.

**This was not visible at scope time.** It appears only once the lease is durable
(itself a correction) and the dry run is a first-class mode (the other
correction) — the two corrections interact, and neither alone produces it.

**Two candidate resolutions, to be decided in U7c rather than now:**

- **A read-only selection path for dry run** — the same predicate without the
  claiming UPDATE. Costs a second selector function, and the two predicates could
  drift apart, which is the failure mode to design against.
- **A dry run that releases its claims before returning.** One statement, no new
  function, no second predicate to keep in step. Weaker under concurrency — but a
  dry run holds nothing worth protecting, because it deletes nothing.

**Second, smaller, same family:** `membership_due_for_cleanup_v1` is `volatile`
and **writes**, so it can never be called from a read-only transaction and must
never be described as a read. Its name says `due_for`, which reads passive. The
comment says otherwise; U7c must not rely on the name.

---

## 9. WHAT U7b DID NOT DO

- **Deleted nothing** — no `delete`, no storage call, no worker.
- **Deployed nothing.** Local only; production untouched and unqueried.
- **Shipped no Edge Function** and no `config.toml` change.
- **Granted no client role anything.**
- **Added no scheduler** — `A57f` still passes.
