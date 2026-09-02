# U7c — RESULTS, SCORED AGAINST `README-u7c-contract-and-predictions.md`. 2026-09-02

**LOCAL ONLY. NOT DEPLOYED. PRODUCTION UNTOUCHED AND UNQUERIED.**

**U7c e2e 75/75. U7b Half A 47/47, Half B 20/20. All pre-existing suites green,
including the two Deno batteries that could not run at U7b.** Four predictions
missed; all four recorded below, none repaired forward. **One measured failure
changed the design and is the most important thing in this document (§8).**

---

## 1. SCORE

| Group | Predicted | Measured | |
|---|---|---|---|
| **C — dry run non-mutating** | all pass | **9/9** | ✅ |
| **D — authority** | all pass | **12/12** | ✅ |
| **E — retention matrix** | all pass | **26/26** | ✅ |
| **F — ordering / lease** | F-1,3,6,7,8 pass; F-2,4,5 need fault injection | **passed as scoped; F-2/F-4/F-5 UNEXERCISED** | ⚠️ §7 |
| **G — structural** | all pass | **8/8** | ✅ |
| Structural delta | +2 functions, +3 grants | **+3 functions, +9 grants** | ❌ **MISS 1 & 2** |
| Regression failures | **exactly 1** (A-14) | **2** (A-14 **and** A45 again) | ❌ **MISS 3** |
| Deno suites | must run | **ran — u4 73/73, u5 68/68** | ✅ |

---

## 2. WORKER CONTRACT AND CALL SURFACE

```
POST /functions/v1/membership_cleanup_v1
Authorization: Bearer <SERVICE_ROLE_KEY>        constant-time compare
{ "mode": "dry_run" | "execute",                DEFAULT "dry_run"
  "limit": 25,                                  bounds IDENTITIES, not rows
  "user_id": "<uuid>" }                         optional, bounds to one identity
```

`verify_jwt = false` plus the function's own service-role check — the same
authorisation story as the other five functions, for `appstore_reconcile_v1`'s
stated reason: `verify_jwt = true` admits **any** valid user JWT, which every
authenticated Apple user can obtain.

**Server surface used, all `service_role`-granted and nothing more:**
`membership_cleanup_eligible_v1` (preview), `membership_due_for_cleanup_v1`
(execute), `membership_apply_reconciliation_v1` (U4's, unchanged),
`membership_cleanup_authorised_v1` (the gate, §8),
`membership_cleanup_complete_v1`.

---

## 3. DRY RUN VERSUS EXECUTE

**ONE ELIGIBILITY DEFINITION, TWO BEHAVIOURS**, as ratified.

| | Preview | Execute |
|---|---|---|
| Selector | `membership_cleanup_eligible_v1` | `membership_due_for_cleanup_v1` |
| Volatility | **`stable`** | `volatile` |
| Acquires lease | **NO** (C-2, C-6) | yes |
| Contacts Apple | **NO** (C-8, zero requests) | yes |
| Writes anything | **NO** (C-4, C-5) | yes |
| Answers | blast radius | authority **and** blast radius |

`membership_due_for_cleanup_v1` derives its candidates **from**
`membership_cleanup_eligible_v1`, so the two cannot drift. The lease interval
likewise has exactly one definition, `membership_cleanup_lease_v1()` — asserted
by **A-14b** (neither selector hardcodes an interval) and **A-14c** (both consult
it).

**`stable` IS A STRUCTURAL GUARANTEE.** PostgreSQL refuses a write inside a
non-volatile function, so the preview path **cannot** claim even if someone later
adds an UPDATE. Asserted on `provolatile = 's'` (C-6), not by reading the body.

**C-3 IS THE ASSERTION THE WHOLE REDESIGN EXISTS FOR:** a dry run followed
immediately by another still finds the identity. **The P4→P5 trap does not
exist** — a preview cannot make the execution that follows it report "nothing to
do".

**Dry run does not contact Apple and does not evaluate authority**, and says so
in its own output. Answering "will this proceed" requires *applying* Apple's
state, which is a mutation; deriving entitlement in TypeScript instead would be a
**third** copy of Apple's formula after `connected_member()` and
`membership_apply_state_v1`. Both rejected. **A dry run answers the blast-radius
question honestly rather than the authority question approximately.**

**The earlier dry run is never authority.** Execute re-selects, re-claims,
re-reads and re-authorises. A difference caused by intervening state is not a
failure — ratified, and true by construction here.

---

## 4. THE AUTHORITATIVE APPLE DECISION FLOW

```
1 CLAIM     membership_due_for_cleanup_v1(limit)   -> ALL rows of each identity
2 REFRESH   EVERY returned row: live Apple read, verified against the pinned
            anchor, applied through membership_apply_reconciliation_v1
            ANY failure -> ABORT the whole identity, delete nothing
3 AUTHORISE membership_cleanup_authorised_v1(uid)  -> one server-side decision
4 DESTROY   objects before rows, every removal re-listed
5 COMPLETE  membership_cleanup_complete_v1(uid)
```

| Measured | |
|---|---|
| **D-1/D-3/D-3b** | 503, unparseable body, empty data → **abort, nothing deleted, no completion marker** |
| **D-4** | Apple says entitled → **refused**, and reconciliation **cleared the schedule** — QA C5's server half, end to end |
| **D-5** | not entitled + gate authorises → **cleaned** |
| **D-6** | lapsed Sandbox **+ live Production** → **refused** on `connected_member()` |
| **D-7** | an identity with two rows → **2 distinct Apple calls** before authority. Falsifier was 1 |
| **D-8** | one environment readable, the other 503 → **the whole identity aborts** |

**There is no escalation.** No "N failures then proceed". An identity Apple can
never be read for stays a visible candidate — an operator problem with a queue,
never a silent deletion.

---

## 5. EXACT CLEANUP EFFECTS — MEASURED

**Removed:** own posts (E-1); own post-attachment objects (E-2); received
`connected_attachments` (E-3); received `post_shares` (E-4); `post_comment_views`
as viewer (E-5); follows **both directions** (E-6); fully-dereferenced sent
assets, row **and** object (E-7, E-7b); avatar object then pointer (E-13, E-13b).

**Retained:** sent asset with a **live** recipient reference — object **and** both
rows (E-8, E-8b); **one live + one soft-deleted → retained** (E-9, E-9b);
comments authored on another member's surviving post (E-10); another member's
comment merely **addressed to** the subject (E-11, B-19); `account_directory` row
with `display_name` intact (E-12); **`auth.users`** (E-14); **`membership` and
`membership_binding`** (E-15, E-15b — **QA A24's behavioural half, discharged**).

**E-17 is the assertion that proves the sweep is selective:** after cleanup, **2
objects survive inside the subject's own `users/<uid>/` prefix**. Copying
`delete_account_v1`'s unconditional prefix sweep would have destroyed both while
every row assertion still passed.

**E-16, third-party blast radius: seven counts, all unchanged** — B's post,
follow, object, avatar, avatar pointer, comment-view, and `auth.users` at 4.

**Cascade, ratified:** comments by others on the subject's **own** deleted post go
with it via `post_comments_post_id_fkey`. The worker **never deletes
`post_comments` at all** (G-2) — the divergence from `delete_account_v1` is that
authorship is not a deletion criterion here.

---

## 6. STORAGE ABSENT-KEY MEASUREMENT, AND WHAT IT CHANGED

Measured against the **same client and route the worker uses**:

| Probe | Result |
|---|---|
| key that never existed | `error: null`, `data: []` |
| `[present, absent]` together | `error: null`, `data.length = 1` |
| same key twice | first `n=1`, second `n=0`, **both `error: null`** |

**FINDING 1 — absent-key removal is not an error.** Retries are safe and
idempotent; **no existence check is needed**. This is what the scope hoped for
and did not assume.

**FINDING 2, NOT ANTICIPATED, AND THE DANGEROUS ONE.** `remove()` reports success
for keys it did **not** delete. `error === null` means *"nothing failed"*, not
*"the objects you named are gone"* — indistinguishable from the return value.

**So a doomed set containing a WRONG path would report success, delete nothing,
and the worker would then delete the rows** — orphaning the real objects
permanently, with no row to find them by and no policy path able to reach them.
**B-8's unreachable-orphan state, arriving through a success message.** This
project has met the shape twice already: `supabase storage rm` no-oping at exit
0, and the U6a apply reporting *"Success. No rows returned."*

**RESULTING RETRY SEMANTICS, ADOPTED:** every removal goes through
`removeVerified`, which **re-lists the prefix and proves the doomed objects
absent** before any row that names them is deleted. A survivor **aborts the
identity** with no row deleted. Asserted structurally at **G-4c** — all three
removal sites go through the verifier. **Any procedure whose success is reported
by the thing being asked to act is unverified.**

---

## 7. LEASE AND CRASH BEHAVIOUR

| | Measured |
|---|---|
| **F-7** | a held claim excludes the identity from selection |
| **F-6** | a claim older than the lease makes it a candidate again — **crash recovery** |
| **C-2** | a dry run acquires **no** claim, anywhere |
| **F-3** | a second execute over a completed identity finds nothing; **no double cleanup** |
| **F-3c** | and the retained objects are still there afterwards |
| **F-8** | every abort path leaves `cleanup_completed_at` **NULL** |

**A resumed run is a new run.** Completion is written last; until it lands the
identity stays a candidate and the next run re-reads Apple and re-authorises from
scratch. A partially-completed cleanup acquires no right to finish itself.

**THREE PREDICTED CASES ARE UNEXERCISED AND ARE NOT COUNTED AS PASSES.**
**F-2** (a doomed object still present after removal → abort), **F-4**
(interrupted between objects and rows), **F-5** (avatar removal fails →
`avatar_key` still populated). All three need fault injection into the storage
layer, for which there is no clean local route: the Apple stub controls Apple, not
storage. **Recorded as unexercised rather than given invented fault injection** —
the same disposition C-33's runtime failure path carries. Their mechanism is
asserted structurally (G-4c, and the ordering in the source), which is weaker than
running them and is stated as such. **This is the largest coverage gap in U7c.**

---

## 8. THE MEASURED FAILURE THAT CHANGED THE DESIGN

**The worker's first executable version aborted EVERY identity with
`permission denied for function connected_member`.**

`connected_member(uuid)` is **ungranted to every role, `service_role` included**.
That is not an oversight — it is **B-33's resolution**, keeping the membership
oracle structurally unbuildable so no role can ask "is this arbitrary user a
member".

**A SECOND VIOLATION WAS HIDING BEHIND THE FIRST, which is C-54's exact shape.**
The worker also re-read `public.membership` directly to confirm a schedule was
still due — and `service_role` holds **zero** table privilege on all six
membership tables. That call never ran, because the first failed before it.
**Measured, not reasoned:**

```
has_function_privilege(service_role, connected_member(uuid))  = false
has_table_privilege(service_role, public.membership, select)  = false
```

**THE WRONG FIX WAS AVAILABLE AND OBVIOUS: grant `connected_member` to
`service_role`.** It would have worked, and it would have dismantled B-33 to save
one function.

**What was built instead is also better than the code it replaced.**
`membership_cleanup_authorised_v1(uuid)` — `security definer`, `stable`,
`service_role` only — makes the whole authority decision **in one statement, on
one snapshot**, and returns `{authorised, connected_member, still_due, reason}`.

- `connected_member(uuid)` **stays ungranted**; B-33 intact.
- The worker previously asked two questions over two round trips and composed the
  `AND` itself, **so the authority decision lived in the caller, where it can be
  got half right**. Now the database decides and the worker is never given the
  parts.
- Asserted at **G-4d**: authority comes from the gate, not composed locally.

**The gate reads the row refreshed immediately above it and cannot know whether
that refresh happened** — so calling it only after a successful Apple read is the
worker's obligation, which is why the refresh-failure branch `continue`s rather
than falling through. Recorded in both the SQL comment and the worker.

---

## 9. THE FOUR MISSES

**MISS 1 — the structural delta is +3 functions, not +2.**
`membership_cleanup_authorised_v1` did not exist when the prediction was written;
it was created in response to §8. An honest delta miss caused by a design change
forced by evidence, recorded rather than back-fitted.

**MISS 2 — `function_grants` is +9, not +3, AND IT IS THE U7b LESSON RECURRING
ONE UNIT LATER.** U7b established that the capture emits **one row per (function,
grantee)**. I applied that to the *granted* function and not to the *ungranted*
one, predicting `membership_cleanup_lease_v1` would contribute **0**. It
contributes **3**, all `can_execute = false`:

```
membership_cleanup_lease_v1  anon           can_execute=False
membership_cleanup_lease_v1  authenticated  can_execute=False
membership_cleanup_lease_v1  service_role   can_execute=False
```

**THE RULE FOR U7d, STATED WITHOUT THE EXCEPTION I INVENTED TWICE: every new
function contributes exactly 3 `function_grants` rows, whether or not anything
was granted to anybody.**

**MISS 3 — two regression failures, not one.** A-14 was predicted. **A45 moved
again** and was not — even though U7b had *just* demonstrated that A45 moves on
every new `service_role` grant. Both amended in place with their reasons; A-14
was made **stricter**, now pinning that the lease has exactly one definition,
which the old assertion could not express. `membership_cleanup_lease_v1` is
correctly **absent** from A45's set, and its absence is the evidence it is
granted to nobody.

**MISS 4 — the Deno blocker was misdiagnosed at U7b.** Installing Deno did not
fix it: `deno test` was never the entry point. `run.sh` executes those batteries
**inside the edge-runtime container**, which is the same runtime production uses.
Both now run: **u4 modules 73/73, u5 modules 68/68.** Bare `deno check` still
reports 3–4 type errors from `_shared/appstore/jws.ts` under Deno 2.9's newer
type lib — **a control proved these are environmental, not mine: the deployed,
untouched `appstore_reconcile_v1` produces the identical errors.**

---

## 10. SUITE RESULTS

| Suite | Result |
|---|---|
| **u7 `e2e-worker.sh`** | **75 passed, 0 failed** |
| **u7 `acceptance-primitive.sh`** | **47 passed, 0 failed** |
| **u7 `acceptance-bornlapsed.sh`** | **20 passed, 0 failed** |
| u3 acceptance | 91 / 0 |
| **u4 modules** (edge runtime) | **73 / 0** — first run in this project's history |
| u4 acceptance | 99 / 0 (after A45 amended) |
| u4 e2e | 43 / 0 |
| **u5 modules** (edge runtime) | **68 / 0** — first run |
| u5 client-structural | 60 / 0 |
| u5 acceptance | 59 / 0 |
| u5 e2e | 62 / 0 |
| u6a / u6b acceptance | 3 / 0 · 64 / 0 |
| **B-23** | **GATE NOT MET — 23 problems**, all U7b+U7c objects (11 + 12). Correct pre-deploy state |
| **`pg_cron`** | **still 0** (G-5) |

**A cross-suite note worth keeping.** Running `u4/run.sh` twice without
`supabase db reset` between produced **12 spurious failures**. That is U5d's
recorded state leak — *"a suite that only ever runs alone can carry an assertion
that is silently order-dependent"* — reproduced here by me. **Every suite result
above is from a freshly reset stack.**

---

## 11. WHAT CHANGES FOR U7d

**1. The structural prediction, corrected in capture rows.** U7b + U7c together:
`columns` **+2**; `functions` **+5 new, 1 modified**; `function_grants` **+15**
(5 new functions × 3 grantees); `constraints` 0 (the `account_id_format` pair is
the standing exception); everything else **IDENTICAL**. **B-23: 23 problems
before, GATE MET after deploy and recapture.**

**2. Two migrations deploy, in order** —
`20260902130000_u7b_cleanup_primitive.sql` then
`20260902140000_u7c_preview_path.sql`. Both carry a guard inside the transaction
and must end in a `SELECT` returning a row. **Neither contains a `delete`.**

**3. `config.toml` gains `[functions.membership_cleanup_v1] verify_jwt = false`**
— required, and its absence would silently default to `true`.

**4. P4's dry run is safe to run repeatedly** and acquires nothing (C-2, C-3), so
it may be run before *and* after the independent prediction is written.

**5. THE INDEPENDENT PREDICTION REMAINS THE ORACLE.** The dry run is scored
against it, never the reverse — ratified, and §3 does not soften it.

**6. The three unexercised failure cases (§7) are the honest gap to carry into
P5.** F-2 and F-5 in particular concern behaviour on a storage failure during a
real cleanup. They are not blockers — the mechanism is asserted structurally and
every abort path leaves no completion marker — but **U7d must not be described as
covering them.**

**7. Apple credentials must be present.** The worker needs the same four
`APPLE_IAP_*` secrets `appstore_reconcile_v1` uses. They are already set in
production; **P3 should verify that rather than assume it**, because the failure
mode is `credentials unavailable` on every identity, which reads like a worker
defect rather than a configuration one.
