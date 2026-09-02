# U7c — WORKER CONTRACT AND PREDICTIONS, COMMITTED BEFORE IMPLEMENTATION. 2026-09-02

**Written before the Edge Function existed and before any U7c test was run.**
Scored in `README-u7c-results.md`. Not edited after measurement.

---

## 1. THE STORAGE MEASUREMENT — TAKEN FIRST, BECAUSE IT CHANGES THE DESIGN

Ratified decision 5: measure once, at the retry path, not as a research unit.
Measured against the **same client and route the worker uses** —
`supabase-js` `storage.from(b).remove([...])` with the service role.

| Probe | Result |
|---|---|
| remove a key that never existed | `error: null`, `data: []` |
| remove `[present, absent]` together | `error: null`, `data.length = 1` |
| remove the same key twice | first `n=1`, second `n=0`, **both `error: null`** |

**FINDING 1 — absent-key removal is NOT an error.** Retries are therefore safe
and idempotent, and **no existence check is needed** before removal. This is what
§4.2 of the scope hoped for and did not assume.

**FINDING 2, WHICH IS THE DANGEROUS ONE AND WAS NOT ANTICIPATED.** `remove()`
returns **success for keys it did not delete**. `error === null` therefore means
*"nothing failed"*, **not** *"the objects you named are gone because we deleted
them"* — the two are indistinguishable from the return value.

**Consequence: a doomed set containing a WRONG path would report success, delete
nothing, and the worker would then delete the rows** — orphaning the real objects
permanently, with no row left to find them by and no policy path able to reach
them. That is exactly B-8's unreachable-orphan state, arriving through a
success message.

**THIS PROJECT HAS ALREADY BEEN BITTEN BY THIS EXACT SHAPE TWICE**: `supabase
storage rm` silently no-oping at exit 0 with an empty `deleted` list, and the
U6a apply reporting *"Success. No rows returned."* while changing nothing. The
standing generalisation applies unchanged — **any procedure whose success is
reported by the thing being asked to act is unverified.**

**DESIGN CONSEQUENCE, ADOPTED: object removal is verified by RE-LISTING the
prefix, never by `error === null`.** The doomed objects must be **observably
absent** before any row that names them is deleted. A re-list that still shows a
doomed object **aborts that identity** with no row deletion.

---

## 2. THE WORKER CONTRACT

### 2.1 Call surface

```
POST /functions/v1/membership_cleanup_v1
Authorization: Bearer <SERVICE_ROLE_KEY>      constant-time compare, as appstore_reconcile_v1
{
  "mode":    "dry_run" | "execute",     // DEFAULT "dry_run"
  "limit":   25,                        // optional, bounds IDENTITIES
  "user_id": "<uuid>"                   // optional, bounds to one identity
}
```

`verify_jwt = false` plus the function's own service-role check — the same
authorisation story as the other five functions, and for
`appstore_reconcile_v1`'s stated reason: `verify_jwt = true` would admit **any**
valid user JWT, which every authenticated Apple user can obtain.

### 2.2 ONE ELIGIBILITY DEFINITION, TWO BEHAVIOURS

Ratified: dry run **must not mutate and must not claim**.

| | Function | Volatility | Claims |
|---|---|---|---|
| Eligibility — **the single definition** | `membership_cleanup_eligible_v1(p_limit)` | **`stable`** | **no** |
| Preview | *the same function*, called directly | `stable` | **no** |
| Execute | `membership_due_for_cleanup_v1(p_limit)` | `volatile` | **yes** |

**`membership_due_for_cleanup_v1` is REPLACED to derive its candidate set from
`membership_cleanup_eligible_v1`**, so there is exactly one place where "eligible"
is defined and the two paths cannot drift. **The lease interval likewise moves to
one place**, `membership_cleanup_lease_v1()`, because a constant duplicated
across the two paths is itself a drift vector.

**`stable` IS A STRUCTURAL GUARANTEE, NOT A CONVENTION.** PostgreSQL refuses a
write inside a non-volatile function at runtime, so the preview path **cannot**
acquire a claim even if someone later adds an UPDATE to it. Asserted on
`provolatile` rather than by reading the body.

**The claiming UPDATE keeps its own lease predicate**, which is the EvalPlanQual
re-check and not a second definition of eligibility — its purpose is concurrency,
and it is the reason two racing selectors cannot both claim one identity.

### 2.3 Dry run does NOT contact Apple, and that is deliberate

**Dry run reports eligibility and blast radius. It does not evaluate authority.**

Answering "will this proceed" requires *applying* Apple's state through the
canonical writer, which is a mutation. The alternatives were both worse: a second
implementation of Apple's entitlement formula in TypeScript — a **third** copy,
after `connected_member()` and `membership_apply_state_v1` — or a dry run that
writes. **So the honest contract is that dry run answers the blast-radius
question only**, and says so in its own output rather than implying more.

**This is not a weakening of U7d.** What P4 must produce is which identity, which
rows, which objects — and per the ratified correction the oracle is the
**independent** hand-derived prediction, never the dry run. Whether Apple
authorises is answered at P5, by the cleanup-authority rule, and a P5 that
declines because Apple says entitled is **correct behaviour, not a surprise.**

### 2.4 Execute — the decision flow

```
1  CLAIM       membership_due_for_cleanup_v1(limit)  -> rows, ALL environments
2  REFRESH     for EVERY row returned: live Apple read, applied through
               membership_apply_reconciliation_v1
               ANY read fails -> ABORT this identity, delete nothing
3  AUTHORISE   ALL of:
                 (a) every read in 2 succeeded
                 (b) connected_member(user_id) = false
                 (c) a schedule is STILL due after the refresh
               otherwise ABORT this identity, delete nothing
4  DESTROY     §3 of the scope, objects before rows, re-listed
5  COMPLETE    membership_cleanup_complete_v1(user_id)
```

**Step 2 refreshes every row the selector returned, not only the due one** — the
selector returns the whole identity precisely so this is automatic. **Step 3(b)
is the identity-level Production predicate**, which is what stops a stale Sandbox
candidate destroying a live Production member's content.

**The earlier dry run is never authority.** Execute re-selects, re-claims,
re-reads and re-authorises. **A legitimate difference between an earlier preview
and an execution caused by intervening state is NOT a failure** — ratified.

---

## 3. PREDICTIONS

Suite `supabase/tests/u7/acceptance-worker.sh`, against a programmable Apple stub.

### C — dry run is non-mutating

| ID | Predicted |
|---|---|
| **C-1** | preview returns the eligible identity's rows |
| **C-2** | **`cleanup_claimed_at` stays NULL for every row** after a dry run |
| **C-3** | a dry run followed immediately by execute **still finds the identity** — the P4→P5 trap does not exist |
| **C-4** | dry run deletes **nothing**: posts, follows, shares, comments, attachments, objects all unchanged |
| **C-5** | dry run writes **no** membership state — `renewal_date`, `pending_cleanup_at`, `updated_at` unchanged |
| **C-6** | `membership_cleanup_eligible_v1` is **`provolatile = 's'`** — structurally unable to claim |
| **C-7** | dry run reports the blast radius: object paths and per-table row counts |
| **C-8** | dry run makes **zero** Apple requests |
| **C-9** | preview and execute select the **same identity set** on quiesced state |

### D — authority

| ID | Predicted |
|---|---|
| **D-1** | Apple read fails 5xx → **nothing deleted**, no completion, lease left to expire |
| **D-2** | Apple times out → same |
| **D-3** | Apple returns malformed → same |
| **D-4** | Apple says **entitled** → reconciliation clears the schedule, identity **self-eliminates**, nothing deleted (**QA C5**) |
| **D-5** | Apple says not-entitled, `connected_member()` false → cleanup **proceeds** |
| **D-6** | **due Sandbox + LIVE Production** → **nothing deleted**; `connected_member()` true is the refusal |
| **D-7** | identity with two rows → **both** refreshed before authority; falsifier: one Apple call |
| **D-8** | one environment's read fails, other succeeds → **nothing deleted** |

### E — the retention matrix

| ID | Predicted |
|---|---|
| **E-1** | own posts removed |
| **E-2** | own post-attachment objects removed |
| **E-3** | received `connected_attachments` rows removed |
| **E-4** | received `post_shares` removed |
| **E-5** | `post_comment_views` as viewer removed |
| **E-6** | follows removed **both directions** |
| **E-7** | sent attachment, **all references soft-deleted** → row and object removed |
| **E-8** | **sent attachment with a LIVE recipient reference → row AND object RETAINED** |
| **E-9** | **one asset, two recipients, one live one soft-deleted → RETAINED** |
| **E-10** | comments authored on **another member's surviving post** → RETAINED |
| **E-11** | another member's comment **addressed to** the subject → RETAINED (B-19) |
| **E-12** | `account_directory` row RETAINED, `display_name` intact |
| **E-13** | `avatar_key` NULL and the avatar object removed |
| **E-14** | **`auth.users` RETAINED** |
| **E-15** | **`membership` and `membership_binding` RETAINED** (QA A24 behavioural) |
| **E-16** | **third-party blast radius zero** — every control count unchanged |
| **E-17** | **NO unconditional `users/<uid>/` sweep** — retained connected objects survive inside the subject's own prefix |

### F — ordering, idempotency, crash

| ID | Predicted |
|---|---|
| **F-1** | objects are observably absent (**re-listed**) before rows are deleted |
| **F-2** | a doomed object still present after removal → **abort, no row deleted** |
| **F-3** | second execute over a completed identity → no-op, nothing further deleted |
| **F-4** | interrupted after objects, before rows → retry completes |
| **F-5** | avatar object removal fails → **`avatar_key` still populated** (C-33) |
| **F-6** | a crashed run's expired lease makes the identity a candidate again |
| **F-7** | a held lease excludes the identity from a concurrent execute |
| **F-8** | abort leaves `cleanup_completed_at` NULL |

### G — structural

| ID | Predicted |
|---|---|
| **G-1** | the worker contains **no** `auth.admin.deleteUser` |
| **G-2** | the worker never deletes `post_comments` by `recipient_user_id` (B-19) |
| **G-3** | the worker never deletes from `account_directory` |
| **G-4** | the worker never deletes from `membership` or `membership_binding` |
| **G-5** | `pg_cron` extension count still **0** |
| **G-6** | all pre-existing suites remain green |

**Structural delta prediction, in CAPTURE ROWS** — the U7b lesson applied:
`functions` **+2 new** (`membership_cleanup_eligible_v1`,
`membership_cleanup_lease_v1`) **and 1 modified** (`membership_due_for_cleanup_v1`);
`function_grants` **+3** — `membership_cleanup_eligible_v1` × 3 grantees;
`membership_cleanup_lease_v1` granted to **no role**, so it contributes **0**
grant rows. `columns`, `constraints`, `policies`, `rls_enabled`, `triggers`,
`table_grants`, `column_grants`, `storage_buckets` all **IDENTICAL**.

**One U7b assertion is predicted to move: `A-14`**, which pins the literal
`interval '1 hour'` inside `membership_due_for_cleanup_v1`. The lease moves to
`membership_cleanup_lease_v1()`, so A-14 must be re-pointed at the new home.
**Predicted regression failures: exactly 1.**
