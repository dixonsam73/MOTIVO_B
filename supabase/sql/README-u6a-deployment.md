# U6a — SHADOW ENFORCEMENT. PLAN AND PREDICTIONS, committed 2026-08-30 BEFORE
# implementation

**NOTHING BELOW IS A RESULT.** Written and committed first, in the D14/D15
style, so the outcome is scored against a prediction rather than read off the
aftermath. Every number here is a claim that can be wrong.

**U6a IS STRICTLY SHADOW-ONLY.** No binding enforcement. No maintained
`account_directory` visibility state — that is U6b. No U6b work of any kind. No
unrelated cleanup. The observer returns `true` on every path, so **U6a changes
no request's outcome**, and that is a property of the code rather than a promise.

**STOP AND REPORT, DO NOT REPAIR FORWARD.** If any predicted structural delta,
behavioural invariant, captured baseline or acceptance assertion differs from
this document, the run stops and reports. A repaired-forward number is not
evidence.

---

## 0. SCOPE, AND THE DECISIONS IT IMPLEMENTS

| Decision | Settled | Effect here |
|---|---|---|
| **B-33** | Filed 2026-08-30 | EXECUTE **is** checked in a policy qual, so the predicate is a zero-argument SECURITY DEFINER wrapper, granted to `authenticated` only |
| **D-U6-1** | Server-owned visibility state on `account_directory` | **U6b.** Not in this unit. No uuid-addressable membership oracle is created, and no exception goes inside the Production entitlement predicate |
| **D-U6-2** | Withdrawal never gated | All 6 DELETE policies untouched |
| **D-U6-3** | Self-profile maintenance allowed while lapsed | `account_directory` SELECT/UPDATE untouched |
| **D-U6-4** | Own retained material readable while lapsed | Own-material branches stay open; only branches reaching other members' content are observed |
| **Q1** | Open `author_user_id` only | `post_comments_select_visible` observes the `owner_user_id` and `recipient_user_id` branches; the author branch is open |
| **Q2** | Full coverage, one step | All 23 policies and 9 functions in a single unit. Partial coverage would make the evidence epoch-dependent |

## 0.1 The own-material rule, stated once so it is checkable

**A branch that reduces to `= auth.uid()` on an ownership column stays OPEN. A
branch that reaches another member's content is OBSERVED.**

---

## 1. OBJECTS — the entire additive delta is three

```
public.shadow_enforcement_stat      table, bounded aggregate, zero client privilege
public.connected_member_self()      zero-arg, STABLE, SECURITY DEFINER  -> authenticated
public.shadow_observe(text)         VOLATILE, SECURITY DEFINER, fail-open -> authenticated
```

### THE NAMES ARE DELIBERATE AND THEY ARE NOT AN EVASION

They are **outside** the `membership%` namespace, and that is a substantive
choice, not a way to keep assertions green. In this schema `membership%` means
*authoritative membership lifecycle state and its writers*: six tables and their
functions, **none of which is executable by `authenticated`** except
`ensure_membership_binding()`. U3, U4 and U5 assert exactly that, repeatedly.
`shadow_observe` **is** granted to `authenticated`, so putting it in that
namespace would falsify several deliberate invariants — and the honest reading
of those invariants is that they are right and this object does not belong there.
Telemetry is not membership state.

**Where a name WOULD have kept an assertion green dishonestly, the assertion is
re-pointed instead — see §4.**

### `shadow_enforcement_stat` — bounded by construction, in B-29's shape

```
user_id uuid, surface text, decided_clause text, bucket_hour timestamptz,
would_deny boolean, observations bigint, first_seen timestamptz, last_seen timestamptz
primary key (user_id, surface, decided_clause, bucket_hour)
```

8 columns. 6 constraints: PK, FK to `auth.users` **on delete cascade**, and
CHECKs for hour alignment, the five clause values, `observations > 0`, and a
surface length bound. **Repeated identical decisions increment a counter and
create no row** — the same shape as `membership_notification_reject_stat` and
`membership_binding_conflict`, and for the same reason B-29 was filed.

### `shadow_observe(text)` — inert and fail-open, both structurally

- **Returns `true` on every path.** One `return`, and it is `true`.
- **The INSERT is wrapped in `exception when others then null`.** Telemetry that
  can fail a request is not telemetry. A full disk must not deny a feed.
- Calls `connected_member_self()` and `membership_state()` internally; **neither
  appears in any policy qual**, so no uuid-addressable predicate is ever exposed.

---

## 2. THE SURFACE MAP — 23 policies observed, 10 untouched

**Observed (23).** `posts` SELECT *(non-owner branch)*, INSERT, UPDATE ·
`post_shares` SELECT, INSERT, UPDATE · `post_comments` SELECT *(owner and
recipient branches)* · `follows` INSERT, UPDATE · `connected_attachments` SELECT,
INSERT, UPDATE · `post_comment_views` all 3 · `account_directory` INSERT ·
`storage.objects` 7 (`attachments_select_via_visible_post`,
`connected_attachment_recipient_select`, `attachments_user_insert_auth`,
`attachments_user_update_auth`, `avatars_select_owner_or_approved_follower`
*(non-owner branch)*, `avatars_insert_owner_only`, `avatars_update_owner_only`).

**Untouched (10).** All 6 DELETEs (D-U6-2) · `follows` SELECT — you cannot delete
what you cannot see · `account_directory` SELECT (C-35) and UPDATE (D-U6-3) ·
`attachments_user_select_auth` (own prefix, D-U6-4).

**23 + 10 = 33.** Asserted mechanically, not counted by hand.

**Functions (9).** The 8 SECURITY DEFINER RPCs plus
`get_unread_private_comment_groups`. **Omitting them would measure two-thirds of
the surface and report it as the whole** — `post_comments` has no INSERT/UPDATE
policy at all, so every comment write is invisible to policy work.

**The directory asymmetry is preserved and is the point.**
`search_account_directory` is observed as GATE-VIEWER and is where U6b's
subject-gating will land. `get_account_directory_by_user_ids` is observed as
GATE-VIEWER and **must never gate on the subject**, or retained-comment
attribution breaks (G10).

---

## 3. PREDICTED STRUCTURAL DELTA — measured baselines, not estimates

Baseline is the committed snapshot in `supabase/schema/`.

| Surface | Before | After | Delta |
|---|---|---|---|
| `columns` | 122 | **130** | +8 |
| `constraints` | 61 | **67** | +6 |
| `functions` | 22 | **24** | +2 new, **9 MODIFIED** |
| `function_grants` | 66 | **72** | +6 rows (2 fns x 3 roles; only `authenticated` true) |
| `rls_enabled` | 14 | **15** | +1 |
| `policies` | 33 | **33** | 0 added, **23 MODIFIED** |
| `table_grants` | 102 | **102** | **IDENTICAL** |
| `column_grants` | 523 | **523** | **IDENTICAL** |
| `triggers` | 5 | **5** | **IDENTICAL** |
| `storage_buckets` | 2 | **2** | **IDENTICAL** |

**U6a IS NOT PURELY ADDITIVE, and more so than U4 or U5b:** 23 policies and 9
functions are modified. The B-23 gate will correctly report GATE NOT MET
pre-deploy and return green after recapture.

---

## 4. PREDICTED BLAST RADIUS ON EXISTING SUITES — **2 assertions**

**Stated as a number because U5b predicted 4 and the actual was 11.** The
question is which assertions change their RESULT, not which mention the thing
being changed.

| Assertion | Now | Becomes | Disposition |
|---|---|---|---|
| **U4 A57b** | `0` — "NO policy consults membership" | **23** | **Re-pointed and made STRICTER.** Its regex is extended to name `shadow_observe`, so it cannot pass merely because the new objects sit outside the `membership%` namespace. A companion assertion is added: the observed policies' row counts are **identical** attached and detached, which is the honest form of "enforcement has not begun" |
| **U5 A67c** | `0` — same predicate, U5b wording | **23** | Same treatment |

**Predicted UNCHANGED, and each was checked rather than assumed:** U3 A15
(`qual ilike '%connected_member%'` — policies call `shadow_observe`, and
`connected_member_self` appears only inside a function body), A15b, A15c
(`prosrc ilike '%membership%'`), A3e, A3f, A4c; U4 A41 (7 `membership%` tables),
A45, A45c, A45d, A47f, A44d, A50e, A57, A57c–A57g; U5 A67, A67b, A67e.

**If any assertion outside this table changes, the run STOPS and reports it as an
under-prediction, exactly as U5b's was recorded.**

---

## 5. CAPTURED BASELINES — measured 2026-08-30 on a clean `db reset`

| Suite | Assertions |
|---|---|
| U3 acceptance | **97** |
| U4 modules / acceptance / e2e | **73 / 96 / 43** |
| U5 modules / client-structural / acceptance / e2e | **68 / 53 / 55 / 62** |
| **Total existing** | **547** |
| **New U6a acceptance (predicted)** | **62** |
| **Predicted total** | **609** |

**The suites require a fresh `supabase db reset --local` before each full run.**
Observed this session: U4 ran 43/43 green, then 31/12 on an immediate re-run
against the dirty database. That is the cross-suite state leak U5d recorded, not
a regression — and it is written down here because it will otherwise be
rediscovered as a failure.

### Predicted U6a assertion breakdown

| Group | n | Asserts |
|---|---|---|
| G4-S1 | 4 | The observer is inert on every path |
| G4-S2 | 16 | **Row counts IDENTICAL attached vs detached**, 4 identity classes x 4 surface families. The assertion that makes "shadow" mean something |
| G4-S3 | 23 | **No bare call** — `(select ` immediately precedes every reference, one per observed policy |
| G4-S4 | 6 | `connected_member(uuid)` and `membership_state(uuid)` still ungranted; the oracle stays unbuildable |
| G4-S5 | 3 | Zero client privilege on `shadow_enforcement_stat` |
| G4-S6 | 4 | `service_role` still `bypassrls`; both destructive Edge Functions unchanged — **C-35 cannot regress** |
| G4-S7 | 3 | The aggregate is bounded: N identical decisions produce ONE row |
| G4-B1/B3/B4 | 3 | Clause vocabulary; `sandbox_only` separable and excluded; denials attributable |

---

## 6. ROLLBACK — restoration, not "drop what was added"

`supabase/sql/2026-08-30-u6a-rollback-baseline.sql`, **generated from the
catalog at a clean migrated state and already verified**: applied to an unchanged
database it is a byte-identical no-op (policy and function fingerprints
unchanged, `68dc0f37…` and `b30d3f86…`).

It captures **all 33 policies and all 9 functions**, not the 23 and 9 U6a
touches — capturing exactly the planned set would make the rollback correct only
if the plan was correct, which is the one thing a rollback must not assume.

Full rollback = apply that file, then
`drop function public.shadow_observe(text); drop function
public.connected_member_self(); drop table public.shadow_enforcement_stat;`

---

## 7. WHAT U6a STILL WILL NOT PROVE

- **Anything about identities that generate no traffic.** A dormant pre-cutover
  subscriber produces zero observations, and zero observations is not evidence
  of safety. That is **G11**, which has never been run and is **U6b's** entry
  condition.
- **G4-B2 (zero grandfather-only decisions) is NOT a U6a pass condition.** It is
  U6b's entry condition. A window that observes grandfather-only decisions is a
  *successful* G4 and a *blocked* U6b, and conflating the two is how one metric
  came to stand for four questions.
- Nothing about production. Everything here is local until deployed.

---

# ACTUAL RESULTS — 2026-08-30, appended. THE PREDICTION ABOVE IS UNCHANGED.

**Everything above this line is the prediction as committed at `5945855`, and it
is preserved verbatim including the parts that were wrong.** Overwriting it would
destroy the only thing that makes a prediction worth committing.

## Structural delta — 10 of 10 surfaces MATCHED

`columns` 130 · `constraints` 67 · `functions` 24 with **9 modified** ·
`function_grants` 72 · `rls_enabled` 15 · `policies` 33 with **23 modified** ·
`table_grants` 102 · `column_grants` 523 · `triggers` 5 · `storage_buckets` 2.

**23 policies attached, 9 functions modified, and ZERO bare observer calls** —
G4-S3's cliff was avoided on the first attempt.

*(One scare during checking was a measurement error, not a delta: an ad-hoc
trigger query omitted the `storage` schema and read 1 instead of 5.
`capture-schema.sh`'s own query reads 5. The lesson is small and real — check
the gate's query, not a query that looks like it.)*

## BLAST RADIUS — THE PREDICTION WAS WRONG IN BOTH DIRECTIONS

**Predicted 2 assertions changing. Actual: 1, and it was neither of them.**

| Assertion | Predicted | ACTUAL |
|---|---|---|
| **U4 A57b** | fails, 0 → 23 | **stayed GREEN at 0** |
| **U5 A67c** | fails, 0 → 23 | **stayed GREEN at 0** |
| **U3 A15c** | unchanged | **FAILED, 0 → 1** |

Measured on a fresh reset: U3 **96/1**, U4 **73/96/43 green**, U5
**68/53/55/62 green**.

### Why A15c failed, and it is the more useful half

`shadow_observe()` calls `membership_state()`. A15c asserts that no function
outside the `membership%` namespace depends on membership, and shadow_observe
acquires exactly that dependency. **The assertion was right and the prediction
was wrong.** When predicting, its source was checked for the string
"membership" — the table it *writes to* was read, and the function it *calls*
was missed.

### Why A57b and A67c staying green is the WORSE finding

Their claim is *"NO policy consults membership"*. Under U6a that is **false in
substance** — 23 policies reach membership state via
`shadow_observe -> membership_state` — and both still passed, because
`shadow_observe` matches neither alternation of `connected_member|membership`.

**§1 of the prediction argued the names were substantive and not an evasion, and
§4 committed to extending the regexes so they could not pass by namespace
accident. But §4 also predicted they would FAIL — and that wrong prediction was
doing the safety work.** They passed, so nothing forced the correction. **A
naming decision justified as honest still silently neutralised two invariants**,
which is precisely the outcome §1 claimed it would not have.

**A15c caught what A57b was built to catch, by accident of construction rather
than by design.** That is the transferable lesson: an invariant that names a
*namespace* is defeated by a new object outside it, while one that names a
*dependency* is not.

## DISPOSITION — approved 2026-08-30, and no assertion was weakened

| Assertion | Change |
|---|---|
| **A15c** | `shadow_observe` added as a **single explicit exception, by name**. No namespace, no pattern. Any other function acquiring a membership dependency still fails it |
| **A57b / A67c** | Regex extended to name `shadow_observe`; expectation **0 → 23**. **Made STRICTER**, not merely re-pointed: each gains a companion asserting **no policy calls an entitlement predicate directly** (`connected_member(`, `membership_state(`, `connected_member_self(` = 0), and a third asserting the observer returns `true`. The claim is now *"the enumerated policies consult shadow telemetry, and enforcement remains non-binding and behaviourally inert"* |

The attached-vs-detached row-count comparison — the strongest form of inertness —
is **G4-S2** in `supabase/tests/u6a/acceptance.sh`.

## FINAL SUITE COUNTS — all green, each on its own fresh `db reset`

| Suite | Predicted | Actual |
|---|---|---|
| U3 acceptance | 97 | **97** |
| U4 modules / acceptance / e2e | 73 / 96 / 43 | **73 / 98 / 43** |
| U5 modules / client-structural / acceptance / e2e | 68 / 53 / 55 / 62 | **68 / 53 / 57 / 62** |
| U6a acceptance | 62 | **74** |
| **Total** | 609 | **625** |

U4 and U5 acceptance each gained **+2**: the companion assertions paired with the
re-pointed A57b and A67c. U6a came in at 74 rather than the predicted 62, from
assertions added while writing it — G4-S2's capture/re-attach pair, and **G4-S8**,
which was not in the plan and should have been:

> **G4-S8 — the observer fires from POLICY EVALUATION, not only when called
> directly.** Nothing else in the suite distinguished *attached and working* from
> *attached and silent*, and those look identical from outside. It asserts that
> `posts.select` recorded **once per identity class, separately** — four rows,
> four distinct `user_id`s, none conflated, which is also what makes
> `sandbox_only` separable from a real lapse.

### Four defects were introduced while writing the suite and caught by running it

Recorded because each is a repeat of a lesson already in this repository.

1. **A source-text assertion defeated by a comment.** G4-S1c counted `return ` in
   raw `prosrc` and read 3 — two real returns plus the phrase *"the ONLY return
   value this can have"* **inside a comment**. `U5c-34` and three U5d assertions
   had the identical shape. Comments are now stripped, and the property asserted
   is the real one: every return yields `true`.
2. **`docker exec -i` inside a `while read` loop steals the loop's stdin**, and
   this host runs **bash 3.2**, which has no associative arrays. The G4-S3 loop
   died silently after one iteration and the suite simply stopped, with a zero
   exit and no error.
3. **A detection regex that could never match.** G4-S3 looked for
   `( SELECT public.shadow_observe`; Postgres renders the qual **without** the
   schema prefix and **with** an `AS shadow_observe` alias, so every policy read
   as "bare" while the bare-count double-counted the alias. **A check that cannot
   fire is worse than no check** — it reports the thing it never tested.
4. **A teardown that was not the inverse of the setup.** G4-S2 detaches via the
   rollback baseline, which restores **33 policies AND 9 functions**; the
   re-attach restored only policies. The suite passed and left the nine RPCs
   detached, and `inventory-complete.sh` then failed with
   `observed functions = 0`. Both halves are now captured, restored, and
   **asserted** — a teardown that is not asserted is a teardown that silently did
   not happen.
