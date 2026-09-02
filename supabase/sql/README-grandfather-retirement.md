# RETIRING THE GRANDFATHER MECHANISM — design decision and the
# prediction-first shadow experiment. 2026-09-01

**NOTHING HERE IS EXECUTED.** `grandfather_enabled` is untouched, no schema has
been removed, and U6b has not begun. This document is the decision and the
committed predictions for the experiment that tests it.

---

## 1. THE PRODUCT CONSTRAINT THAT CHANGED THE ANSWER

**Confirmed by the account holder, 2026-09-01: Études has never been publicly
released. It is in TestFlight/beta development and there are NO production
customers.** The existing Connected accounts are pre-release development and beta
accounts, and **preserving their accounts or server-side content is not a release
requirement.**

**This is a product decision, not an inference from the data, and it is recorded
as one.** The database could not have established it: the Production ASSN URL is
unset, so a Production purchase would not have been visible to us either way. What
the database *does* corroborate — zero Production membership rows ever, zero
Production notifications, two distinct Sandbox subscriptions in total — is
consistent with it and contradicts nothing.

**STANDING RULE ADOPTED THE SAME DAY: where the identity or purpose of an
existing account is relevant and uncertain, ASK. Do not infer it from indirect
evidence.** The classification below was built from email shape, content and
activity because the question was live before the rule existed; it should not be
the pattern next time.

## 2. WHAT THE POPULATION TURNED OUT TO BE — B-36

16 pre-cutover identities, all Sign in with Apple, all email-confirmed, **all 16
completed onboarding** with a display name and instruments, **zero test-like
display names, zero test-like account IDs**, created across **14 distinct days
between 2026-02-26 and 2026-08-15** with no batch clustering.

| Class | n |
|---|---|
| Confirmed fixtures (Device A, Device B) | **2** |
| **Best explained as genuine external TestFlight beta testers** | **9** |
| Plausibly developer-owned, unresolved from the data | up to **5** |

The 9 all use **Hide My Email**; 5 published posts (19 total) across spans of up
to 130 days; 4 hold follow relationships. **100 posts exist across the whole
population.** None has ever attested.

**THE CLASSIFICATION NO LONGER DRIVES THE DECISION, and that is the point.** Under
§1 all 16 receive identical treatment, so which are the developer's and which are
external changes nothing about the architecture, the sequence or the risk.
**Identifying the five ambiguous accounts would not materially affect the
recommendation** — its residual value is operational (Device B is one of the 15
and loses server-side Connected access when the clause goes off) and courtesy.

## 3. THE FINDING THAT REFRAMED GATE 2 — the snapshot has no entitlement test

Read from the migration rather than assumed:

```sql
insert into public.membership_cutover (user_id)
select u.id from auth.users u
 where u.created_at < (select cutover_at from public.membership_control where id);
```

Its own note says `pre-cutover = auth.users.created_at < cutover_at`. **There is
no subscription or entitlement predicate anywhere in it.** The snapshot is *every
identity that existed*, not *every identity that was paying*.

Two consequences, and the second is the one that matters:

1. **Gate 2 as framed was unsatisfiable by construction.** "Every snapshot
   identity acquires authoritative membership state" cannot happen for someone who
   never had a subscription, and they cannot attest to one that never existed.
2. **The grandfather clause is not a "protect existing payers" mechanism.** It is
   a "don't break anyone who existed" mechanism, and it currently grants full
   Connected entitlement to every pre-cutover identity, paid or not.

## 4. THE DECISION — retire the mechanism, do not discharge the population

**GATE 2 IS RETIRED, NOT SATISFIED.** It existed to protect a population that does
not need protecting. Keeping it as fifteen per-identity obligations would be
complicating the architecture to preserve historical beta state, which §1 rules
out. It is replaced by **one recorded product decision** — §1 itself.

### What removal collapses

- `connected_member()` loses its middle `coalesce` arm. **No fall-through, no
  `bool_or`-over-an-empty-set subtlety, no clause ordering.** The predicate D4
  spent a full design round getting right becomes trivially correct.
- `membership_state()` drops `'grandfathered'` — five values become four.
- `membership_cutover`, `grandfather_enabled` and `grandfather_expires_at` all
  become dead.
- **CORRECTED 2026-09-02: `u6b_bound_at` IS NOT DEAD AND MUST BE RETAINED.** This
  bullet listed it among the dead columns, and that was written on 2026-09-01
  **before U6b bound**, when it was still null and read as an unused placeholder.
  It has been set since 2026-09-01 16:52:52, it records that binding happened,
  and it makes the bind statement **refuse to run a second time**. Dropping it
  would delete that refusal. **The same failure mode as C-52 and the U4 heading:
  a durable document describing a state it is not itself evidence of** — right
  when written, never re-read afterwards, and load-bearing for the unit that
  implements from it. U6b-4 retains it and its apply guard asserts it survives.
- **`cutover_at`, `cutover_identity_count` and `cutover_verified_at` are also
  RETAINED**, as the historical record of a boundary that was declared and
  verified. No function reads them (measured 2026-09-02: zero references across
  all 28 production functions), and CLAUDE.md's standing rule is that
  `cutover_at` is never altered. Retaining them also makes the U6b-4 rollback
  **data-complete**: the 16-row snapshot is exactly reconstructible from
  `auth.users` using `cutover_at`, so no identifier needs to live in this
  repository.
- **U6c DISAPPEARS AS PREVIOUSLY CONCEIVED.** No twelve-month clock, no liveness
  safety check, no dated post-phase obligation carried on B-11. It becomes an
  ordinary cleanup migration.
- **B-35's correction becomes moot operationally.** The finding stays as a
  lesson — *an auth column's silence is not evidence* — but the check it fixed no
  longer needs to run.
- **G4-B2 disappears as a gate.** There is no compatibility clause left for a
  decision to rest on.

**This simplification is available ONLY because the cohort is disposable.** If a
single production customer existed it would be unavailable, and the whole of U6c
would be required. That dependency is stated here so a future reader cannot adopt
the simpler architecture without also inheriting its premise.

### The sequence — separate "stop granting" from "start denying"

```
1.  grandfather_enabled = false, WHILE U6a IS STILL SHADOW-ONLY   <- the experiment below
2.  observe: the window shows exactly what U6b would deny, denying nothing
3.  Gate 6 resolved  (see §6 -- ON THE CRITICAL PATH)
4.  U6b binds enforcement, against a predicate that actually decides
5.  cleanup migration: drop the arm, the table, the control columns
```

**Step 1 is what makes the rest safe**, and it is why the flag is flipped before
enforcement rather than with it. With grandfathering on, binding would be masked
by the compatibility clause for 15 of 16 identities and would prove almost
nothing.

---

## 5. THE EXPERIMENT — PREDICTIONS, COMMITTED BEFORE EXECUTION

**NOT RUN.** `grandfather_enabled` is `true` in production as this is committed.

### Why it is safe, stated as a property rather than a hope

**Nothing reads `connected_member()` for a decision.** Its only reader is
`shadow_observe`, via `connected_member_self`, and `shadow_observe` returns `true`
on every path. U6a's acceptance asserts that **no policy calls an entitlement
predicate directly** (the companions to A57b/A67c). So flipping the flag changes
**what the telemetry records, not what any request may do.**

### The change

```sql
update public.membership_control set grandfather_enabled = false where id;
```

**One row, one boolean, no schema change, no migration.** The rollback is the
same statement with `true`.

### Predicted state, derived from the deployed function bodies

`connected_member()`'s grandfather arm is `select exists (...)`, and `exists`
returns `false` — never NULL — so `coalesce` yields **false** rather than falling
to the third arm. `membership_state()` then reaches its final `else`.

| # | Prediction |
|---|---|
| **GF-1** | The **15** pre-cutover identities with no membership row: `connected_member()` **true → false** |
| **GF-2** | Their `membership_state()`: `'grandfathered'` → **`'unknown'`**, NOT `'expired'` |
| **GF-3** | **Device A is UNCHANGED** — `'sandbox_only'` / false. It has a Sandbox row, so arm 2 of `membership_state` decides and the grandfather arm is never reached |
| **GF-4** | The 1 post-cutover identity is **UNCHANGED** — already `'unknown'` / false |
| **GF-5** | **No existing `shadow_enforcement_stat` row changes.** The aggregate is keyed on `decided_clause`, so new decisions create NEW rows; the historical `grandfathered` rows survive as evidence |
| **GF-6** | New observations from those identities carry `decided_clause = 'unknown'`, `would_deny = true` |
| **GF-7** | **On the EXERCISED FIXTURES (Device A, Device B): not one request fails.** Row counts identical, no error observed |
| **GF-8** | **On the EXERCISED FIXTURES: no user-visible change.** `AppMode` resolves from local StoreKit; the server predicate is not consulted by the client |
| **GF-9** | `membership`, `membership_binding`, `membership_cutover` and `membership_binding_conflict` are **untouched** — this writes one boolean in `membership_control` and nothing else |

### GF-7 AND GF-8 ARE SCOPED TO WHAT WE CAN ACTUALLY OBSERVE

**Corrected 2026-09-01 before execution.** Both read *"on any device"*, and that
is a claim over a population we cannot observe: **the dormant beta installs are
exactly the ones that generate nothing**, which is B-34's lesson turned on my own
predictions. A prediction phrased over unobservable devices cannot be falsified
and therefore cannot be evidence.

**So the two claims are separated, and only one of them is an observation:**

- **Observed (GF-7, GF-8):** scoped to Device A and Device B, the fixtures this
  experiment actually drives. That is the whole of what the run can measure.
- **Structural, and it does cover every install including dormant ones:**
  `shadow_observe` returns `true` on every path, and **no policy calls an
  entitlement predicate directly** — asserted by U6a's acceptance companions to
  A57b/A67c and by the deployed function body, verified in the bundle rather than
  the tree. **No request decision changes for anybody, because nothing consults
  `connected_member()` to decide anything.**

**The safety property is the structural one, and it does not depend on the
observation.** The observation confirms it on the fixtures; it never extends it.
**Do not report "no user impact" as an observed result** — report that the
predicate is not consulted by any decision path, and that the two exercised
fixtures behaved accordingly.

### ROLLBACK CONDITION — stated before, so it is not negotiated afterwards

**Roll back immediately — `grandfather_enabled = true` — on ANY of:**

- any request failing **on an exercised fixture** (GF-7 violated: enforcement is
  live when it must not be) — **or a report of failure from any other install**,
  which would be evidence the structural claim above is false;
- any user-visible change **on an exercised fixture** (GF-8 violated: the client
  is consulting the server predicate, which contradicts the settled split);
- `connected_member()` returning **true** for an identity predicted false, or
  false for one predicted true (GF-1/GF-3/GF-4);
- any identity reading `would_deny = true` that **you identify as one that should
  be entitled** — under the standing rule of §1 this is a question for the account
  holder, not something to resolve from the data;
- any row appearing or changing in `membership`, `membership_binding`,
  `membership_cutover` or `membership_binding_conflict` (GF-9).

**The rollback is one row and takes effect on the next predicate evaluation.**
There is no window during which a rolled-back state is partially applied, because
the flag is read live inside the function on every call.

**What is NOT a rollback condition:** observing many `would_deny = true`
decisions. **That is the experiment succeeding.** The whole point is to see what
U6b would deny while it denies nothing.

---

## 6. GATE 6 IS UNRESOLVED AND ON THE CRITICAL PATH — do not lose this

**The enforcement-path Sandbox QA mechanism, deferred to U6b by D4 and B-11, is
still owed and is now unavoidable.**

Once enforcement binds, a Sandbox tester reads `'sandbox_only'` and is **denied
server-side**, while the *client* still shows Connected from local StoreKit. **Device
A would present the full Connected UI with every API call refused.** That is not a
cosmetic problem: it is the only QA route this project has, and after U6b binds it
stops working.

**It must be resolved before step 4 (binding). It does NOT block step 1** — the
shadow experiment denies nothing, so Sandbox QA is unaffected by it.

D4 rejected putting an exception inside the entitlement predicate, and that
rejection stands. The options remain a separate QA project, a Production
subscription bought for the purpose, or a tester carve-out **outside** the
predicate — now weighable against a real enforcement surface, which is why it was
deferred rather than guessed.

---

# EXPERIMENT RESULTS — 2026-09-01. THE PREDICTIONS ABOVE ARE UNCHANGED.

**GF-1 to GF-9 ALL HIT. Zero rollback triggers. Nothing was repaired forward.**

## The statement's own returned row

```
grandfather_enabled f | pre_cutover_now_denied 15 | now_unknown 15 | still_grandfathered 0
device_a_state sandbox_only | device_a_connected f
membership 1 | binding 1 | cutover 16 | conflicts 0
```

`now_unknown = 15` and **not** `expired` — the derivation from the deployed
function bodies held: the grandfather arm is `select exists (…)`, which returns
`false` and never NULL, so `coalesce` yields false rather than falling through and
`membership_state()` reaches its final `else`.

## GF-6 — the window now shows what U6b would deny

Device B, driven through feed, post, attachment and one comment:

```
11:50:01  unknown  account_directory.insert       deny=true  n=2
11:50:08  unknown  storage.attachments_recipient  deny=true  n=2
11:50:08  unknown  storage.attachments_via_post   deny=true  n=1
11:50:08  unknown  posts.select                   deny=true  n=1
11:50:34  unknown  rpc.add_post_comment           deny=true  n=1
```

**Every `unknown` observation carries `would_deny = true` — zero exceptions**, and
all 7 belong to a single grandfather-dependent identity. **Device A produced NONE
of them**, so GF-3 held under live traffic and not merely at rest: its Sandbox row
decides at arm 2 and the grandfather arm is never reached.

## THE CONCRETE INERTNESS PROOF IS THE COMMENT

`rpc.add_post_comment` recorded **`unknown` / `would_deny = true`** at 11:50:34,
and `post_comments` went **3 → 4**. **The predicate said "not entitled" and the
write landed anyway.** That is the strongest single demonstration this window can
produce: a decision recorded, and no decision changed.

The device saw nothing — feed, post and attachment all normal — which is GF-7 and
GF-8 **scoped to the exercised fixtures**, exactly as corrected before the run.
The structural claim they rest on is unchanged and was asserted by the statement's
own preconditions 4 and 5 against the live catalog: no policy references an
entitlement predicate directly, and `shadow_observe` is still the inert fail-open
observer.

## GF-5 — the clause-keyed aggregate preserved the pre-flip evidence

**11 historical `grandfathered` rows carrying 16 observations survive untouched**
alongside the 5 new `unknown` rows. Nothing was mutated in place, because
`decided_clause` is part of the primary key. **The before and after of this
experiment sit in the same table**, and on `account_directory.insert` the same
identity can be read on both sides of the boundary:

```
before   grandfathered  deny=false
after    unknown        deny=true
```

## GF-9 — the membership tables did not move

`membership` 1 · `membership_binding` 1 · `membership_cutover` 16 · conflicts 0,
identical to the pre-check. One boolean changed and nothing else.

## STATE LEFT RUNNING, DELIBERATELY

**`grandfather_enabled` stays `false`.** This is not a temporary probe to be
reverted — it is the first step of the retirement in §4, and the flag being off is
now the intended steady state until the cleanup migration removes the branch
entirely. `u6b_bound_at` remains **null**: enforcement is still unbound, so the
system continues to deny nothing.

**The rollback statement remains valid and one row** for as long as
`u6b_bound_at` is null. After U6b binds, this flag stops being telemetry and
becomes access — which is what precondition 3 exists to refuse.

## WHAT THIS DOES NOT ESTABLISH

**Nothing about the 14 identities that generated no traffic.** The window now
records what U6b *would* do to the one grandfather-dependent identity we drive;
it says nothing about the others, and under B-34 it never can. **That is not a gap
to be closed — it is the reason Gate 2 was retired rather than satisfied.** The
census, not the window, is what enumerated the population.
