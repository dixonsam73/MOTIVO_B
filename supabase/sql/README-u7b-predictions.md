# U7b — PREDICTIONS, COMMITTED BEFORE ANY MUTATION. 2026-09-02

**Written before the migration existed and before any test was run.** Scored in
`README-u7b-results.md`. Nothing here is edited after measurement; a miss is
recorded as a miss.

**U7b COMBINES TWO HALVES AND THEY ARE SCORED SEPARATELY** — ratified condition,
so neither can hide a failure in the other. Two suites, two tallies, two exit
codes, disjoint fixtures.

- **HALF A — the cleanup primitive.** Two columns, two functions, two grants.
- **HALF B — the born-lapsed correction.** One modified function, nothing else.

---

## 1. STRUCTURAL DELTA — ITEMISED PER HALF

Measured against the committed snapshot in `supabase/schema/`.

| Surface | Half A | Half B | Combined |
|---|---|---|---|
| `columns` | **+2** — `membership.cleanup_completed_at`, `membership.cleanup_claimed_at`, both `timestamptz` NULLable | 0 | **+2** |
| `functions` | **+2 new** — `membership_due_for_cleanup_v1`, `membership_cleanup_complete_v1` | **1 MODIFIED** — `membership_apply_state_v1` | **+2 new, 1 modified** |
| `function_grants` | **+2** — both new functions, `EXECUTE`, `service_role` only | 0 | **+2** |
| `constraints` | 0 | 0 | **0** |
| `policies` | 0 | 0 | **IDENTICAL** |
| `rls_enabled` | 0 | 0 | **IDENTICAL** |
| `triggers` | 0 | 0 | **IDENTICAL** |
| `table_grants` | 0 | 0 | **IDENTICAL** |
| `column_grants` | 0 | 0 | **IDENTICAL** |
| `storage_buckets` | 0 | 0 | **IDENTICAL** |

**No index is added**, and none is needed: `membership_pending_cleanup_idx`
already covers the selector. Indexes are not in the B-23 capture regardless.

**PRIVILEGE PREDICTION — the entire U7b privilege delta is two EXECUTE grants.**
`anon`, `authenticated` and `PUBLIC` gain **nothing**. No role gains any table or
column privilege on any membership table. `service_role` still holds **zero**
table privilege on all six membership tables.

---

## 2. HALF A — CLEANUP PRIMITIVE. BEHAVIOURAL PREDICTIONS

Suite `supabase/tests/u7/acceptance-primitive.sh`. **This suite never calls
`membership_apply_state_v1`.**

### Selection boundaries

| ID | Case | Predicted |
|---|---|---|
| **A-1** | fixture non-vacuity | all fixture identities exist before use |
| **A-2** | `pending_cleanup_at <= now()` | **selected** |
| **A-3** | `pending_cleanup_at` in the future (**N6**) | **not selected** |
| **A-4** | `pending_cleanup_at is null`, not entitled (**N7**) | **not selected** |
| **A-5** | no `membership` row at all (**N8**) | **not selected**, on every path |
| **A-6** | selector returns **every** row of a candidate identity (**N5 / §1.4**) | an identity with a due Sandbox row **and** a live Production row yields **2 rows** |
| **A-7** | the live Production row's own schedule | returned with `pending_cleanup_at` still NULL — the selector reports state, never alters entitlement |
| **A-8** | `p_limit` bounds **identities**, not rows | limit 1 against 2 candidate identities → exactly **1 identity**, all of its rows |
| **A-9** | ordering | earliest `pending_cleanup_at` first |

### Lease — live from U7c, semantics land here

| ID | Case | Predicted |
|---|---|---|
| **A-10** | first call | claims the due rows; `cleanup_claimed_at` set |
| **A-11** | immediate second call | **returns nothing** — the claim holds |
| **A-12** | claim is set only on **due** rows | a live Production row alongside keeps `cleanup_claimed_at` NULL |
| **A-13** | expired claim (crash recovery) | claim backdated beyond the lease → identity **is a candidate again** |
| **A-14** | lease interval | **1 hour** |
| **A-15** | claim does not entitle or alter membership | `connected_member()` and `membership_state()` unchanged across a claim |

### Completion

| ID | Case | Predicted |
|---|---|---|
| **A-16** | `membership_cleanup_complete_v1` | `pending_cleanup_at` → NULL, `cleanup_claimed_at` → NULL, `cleanup_completed_at` set |
| **A-17** | clears **all** scheduled rows of the identity | both environments, where both were due |
| **A-18** | second call (**N19 / QA C8**) | `outcome = 'noop'`, `rows = 0`, `cleanup_completed_at` **unchanged** |
| **A-19** | after completion | identity **not selected** |
| **A-20** | completion never touches Apple state | `renewal_date`, `entitlement_ended_at`, `binding_method`, `bound_at`, `original_transaction_id` all unchanged |
| **A-21** | completion never touches another identity | control identity's every column unchanged |
| **A-22** | null argument | raises, `errcode 22004` |

### Privilege

| ID | Case | Predicted |
|---|---|---|
| **A-23** | `membership_due_for_cleanup_v1` | `service_role` **true**; `anon`, `authenticated`, `PUBLIC` **all false** |
| **A-24** | `membership_cleanup_complete_v1` | same |
| **A-25** | table privilege | `service_role` holds **zero** on all six membership tables |
| **A-26** | U7b deletes nothing | **no `delete from` statement in either new function** — asserted over `pg_get_functiondef` |
| **A-27** | U7b originates no membership row | **no `insert into public.membership`** in either new function |

---

## 3. HALF B — BORN-LAPSED CORRECTION. BEHAVIOURAL PREDICTIONS

Suite `supabase/tests/u7/acceptance-bornlapsed.sh`. **This suite never calls the
selector or the completion RPC.**

| ID | Case | Predicted |
|---|---|---|
| **B-1** | fixture non-vacuity | fixture identities exist before use |
| **B-2** | **ordinary lapse** — Apple's dates ≈ now, no prior schedule | `pending_cleanup_at ≈ now() + 60d`; **the floor does NOT fire** |
| **B-3** | **BORN-LAPSED (N22)** — first schedule, Apple's dates ~8 months past | `pending_cleanup_at > now()`, and **`>= now() + 59 days`** |
| **B-4** | born-lapsed `entitlement_ended_at` | **still Apple's own truth**, ~8 months in the past — the floor moves the *schedule*, never the fact |
| **B-5** | **the guard fires (N24)** — proof it is not decorative | B-3's `pending_cleanup_at` differs from `entitlement_ended_at + 60d` by **> 100 days** |
| **B-6** | **the guard cannot fire on an ordinary lapse (N24)** | B-2's `pending_cleanup_at` equals `entitlement_ended_at + 60d` **exactly** |
| **B-7** | **anti-sliding preserved (N23)** | an existing schedule is **never pushed out** by a later notification |
| **B-8** | anti-sliding, `entitlement_ended_at` | never slides forward — `least()` retained |
| **B-9** | entitled state still cancels | entitled → `entitlement_ended_at` **NULL**, `pending_cleanup_at` **NULL** (QA C5's server half) |
| **B-10** | establishment still schedules nothing (**F11**) | `membership_establish_v1` against a long-expired subscription → both NULL |
| **B-11** | stale ordering still a no-op | older `renewal_info_signed_date` → `outcome = 'stale'`, row unchanged |
| **B-12** | writer is still UPDATE-ONLY | no `insert into public.membership` in `membership_apply_state_v1` |
| **B-13** | the floor is the **only** change | the function's definition differs from its deployed form in exactly the floor block |

---

## 4. REGRESSION PREDICTION

The full pre-existing suites are re-run. **All must remain green.**

| Suite | Predicted |
|---|---|
| `supabase/tests/u3` | unchanged, green |
| `supabase/tests/u4` (acceptance, e2e, module) | unchanged, green |
| `supabase/tests/u5` | unchanged, green |
| `supabase/tests/u6a`, `u6b` | unchanged, green |

**U4's `A57f` — `pg_cron` extension count 0 — MUST STILL PASS.** U7b adds no
scheduler; the assertion that would fail if it did is the assertion working.

---

## 5. WHAT U7b DOES NOT DO

- **Deletes nothing.** No `delete`, no storage call, no worker.
- **Touches no client role's privileges.**
- **Ships no Edge Function**, no `config.toml` change.
- **Is not deployed.** Local only.
