# P4-U3 — CONDITIONAL HISTORIC-PRIVATE-ROW PURGE. **MEASURED NO-OP.**

**2026-09-04, at `1a6afbb`.**

**THIS IS THE PREDICTED SUCCESSFUL OUTCOME OF U3, NOT A SKIPPED UNIT.** U1
committed the rule in advance: *"Predicted: a recorded NO-OP. If the pre-U3
census still reads `private_false = 0` and `private_null = 0`, U3 deletes nothing
and is recorded as a no-op with its evidence, not omitted and not written up as
a completed purge."* The census was re-measured and the rule applied.

---

## 1. PRE-U3 PRODUCTION CENSUS — READ-ONLY, MEASURED NOW

Re-measured **after** U2b, U2c and U2s had landed.

| measure | value |
|---|---|
| **`total_posts`** | **101** |
| **`is_public = true`** | **101** |
| **`is_public = false`** | **0** |
| **`is_public IS NULL`** | **0** |
| distinct owners | **9** |
| attachment reference count | **10** |
| `attachments` objects / referenced / **unreferenced** | **15 / 11 / 4** |
| `avatars` objects | **3** |
| `connected_attachments` rows / live | **31 / 6** |
| `post_comments` / `post_shares` / `follows` | **5 / 0 / 9** |
| earliest → latest post | 2026-03-02 → 2026-09-01 |

### 1.1 THE PRIVATE COUNT WAS MEASURED THREE WAYS, NOT ONE

A single predicate can be wrong in a way that looks like a pass, so:

| method | result |
|---|---|
| `count(*) filter (where is_public is false)` + `… is null` | **0 and 0** |
| `count(*) where is_public is not true` | **0** |
| `group by is_public` — the whole column domain | **one group: `true` × 101** |

**The `GROUP BY` is the decisive one.** It does not test a hypothesis about
private rows; it enumerates every value the column actually holds. **Nothing can
hide behind a predicate that was never written.**

---

## 2. DECISION — THE SCOPE'S RULE, APPLIED EXACTLY

**Private rows are zero, therefore:**

- **U1 baseline private population: ZERO** (measured 2026-09-04 at `f12330e`).
- **Immediately pre-U3 private population: ZERO** (measured above).
- **Therefore there are NO explicit ids eligible for purge.**
- **ZERO `DELETE` statements were issued.**
- **ZERO rows were deleted.**
- **NO production mutation whatsoever** — every query in this unit is a `select`.

**No predicate sweep was used, and none could have been:** with no eligible ids
there was nothing to enumerate, and B-22's rule (purge by explicit id, never by
predicate) is preserved by having nothing to purge rather than by restraint.

---

## 3. WHY THE RESULT IS NOW DURABLE AGAINST THE ORIGINAL MECHANISM

U1's zero was a fact about a population that **nothing prevented from growing**.
It is now defended at three independent layers:

| layer | what it prevents | evidence |
|---|---|---|
| **U2b** | both shipping call sites gate existence on visibility, so a Share-OFF save or a Thought creates no row at all | `u2b-acceptance` 16/16 |
| **U2c** | the client API **cannot construct** a private publish — `op` is derived from `isPublic`, so `.publish + isPublic:false` does not compile, and a contradictory queue file normalises to `.unshare` | `u2c-acceptance` 20/20 + the compile-failure discriminator |
| **U2s** | production `posts_insert_owner` **refuses** `is_public = false` INSERTs, including the omitted-column case that takes `DEFAULT false` | `u2s-acceptance` 12/12 + the local A/B matrix |

**So a historic pre-U2 client cannot recreate the original private-row mirror
through an authenticated INSERT.** That is the substantive change since U1: the
zero is no longer merely observed, it is **defended**.

**`UPDATE → false` remains intentionally possible**, and that is not a gap. It is
the **transient fail-safe state** used by durable unshare reconciliation: if a
delete fails, the row must be demotable to private while the queued `.unshare`
converges. Blocking it would leave withdrawn content **publicly visible** — the
regression C-61 was filed to prevent.

---

## 4. WHAT THIS DOES **NOT** SAY — THE HISTORICAL CORRECTION IS PRESERVED

**This is NOT a claim that production has never contained private rows.**

`docs/phase-4-scope.md` §F-1 already withdrew that claim and the withdrawal
stands: `public.posts` has **no audit column and no history table**, so a private
row created and later deleted would leave **no trace**, and a census cannot
distinguish that from one that never existed.

**The supported claim is exactly:** *no private post rows exist at the U1
baseline or at this pre-U3 measurement, so there is no private population to
purge* — and, newly, *the mechanism that could create one is now closed at three
layers.*

---

## 5. POST-RECORD CENSUS — RE-RUN, AND IDENTICAL

| measure | pre-U3 | post-record |
|---|---|---|
| `total_posts` / `is_public = true` | 101 / 101 | **101 / 101** |
| `is_public = false` / `IS NULL` | 0 / 0 | **0 / 0** |
| distinct owners | 9 | **9** |
| attachment reference count | 10 | **10** |
| `attachments` objects / **unreferenced** | 15 / 4 | **15 / 4** |
| `avatars` objects | 3 | **3** |
| `post_comments` / `follows` | 5 / 9 | **5 / 9** |

**Every value identical** — as it must be, since U3 issued no statement other
than `select`.

## 6. GATES

**No source and no production state changed, so no rebuild is warranted** — the
project's convention is that a measurement unit runs the gates its evidence
requires, not gratuitous ones. The structural suites that read the committed
schema snapshot were run because U3's claim rests on that snapshot being current:

| gate | result |
|---|---|
| `p4/u2s-acceptance.sh` | **12 / 12** |
| `p4/u2c-acceptance.sh` | **20 / 20** |
| `p4/u2b-acceptance.sh` | **16 / 16** |
| `p4/u2a2-acceptance.sh` | **22 / 22** |
| `p4/u2a-acceptance.sh` | **16 / 16** |
| `p4/u1-baseline.sh` | 10 pass / its 6 documented flips |
| `u5/client-structural.sh` | **60 / 60** |

Debug/Release builds and `MOTIVOTests` were green at `4febb8b` and **no source
changed since**, so they are not re-run.

## 7. REMAINING PHASE 4 OBLIGATIONS

| unit | state |
|---|---|
| **U4** — B-8 storage orphan cleanup | **NOT STARTED.** 4 unreferenced objects, unchanged since U1 |
| **U5** — B-15 directory anti-browse, with C-34's version signal | **NOT STARTED** |
| **U6** — C-51 runtime verification | **NOT STARTED** |
| **U7** — C-58 follower attribution | **NOT STARTED** |
| **U8** — copy and App Store privacy disclosure alignment (D-1, D-2, C-32) | **NOT STARTED.** Carries U2a-2's constraint: no UI state may assert *completed* removal while an `.unshare` is pending |
| **Exit condition 8** — Device A run | **OUTSTANDING**, now owning both U2b's and U2s's production behavioural observations |

**Carried from Phase 3, untouched by Phase 4:** C-31, B-34, G7, and the
production GRANT on B-11.
