# U7a — EXPIRY CLEANUP WORKER. SCOPE ACCEPTED 2026-09-02. NOT IMPLEMENTED

**NOTHING IS BUILT, NOTHING IS DEPLOYED, NOTHING IN PRODUCTION IS TOUCHED BY
THIS DOCUMENT.**

**SCOPE ACCEPTED BY THE ACCOUNT HOLDER 2026-09-02, WITH SEVEN DECISIONS, THEN
FIVE FURTHER CORRECTIONS ON THE IMPLEMENTATION PLAN.** They
are recorded at the point they bear on rather than in a list, each marked
**RATIFIED**. Two of them **corrected this document** and both corrections are
made in place with the superseded claim quoted, never rewritten to look as
though it was always right:

- **Decision 7 WITHDRAWS an equivalence this file proposed** between enforcement
  visibility and expiry collectability — §2.4.
- **Decision 1 REVERSES this file's position on scheduling.** U7 *does*
  ultimately require unattended cleanup; what survives is only the *sequencing* —
  §7.2.

**A third correction is this document's own**, found while working out the
scheduler unit and not raised by anybody: **§4.5's concurrency claim was wrong
about the mechanism.** U7a is a scope unit in U5a's sense: decisions and predictions
committed before implementation, so that the implementation can be scored
against them rather than described afterwards.

**The requirement, restated so the rest of this file can be checked against it:**
`pending_cleanup_at` selects cleanup candidates; irreversible expiry cleanup may
proceed only after a fresh authoritative Apple read confirms cleanup is still
valid. If Apple cannot be consulted, or current state no longer authorises
cleanup, nothing is deleted and the candidate is retried later.

**Entry state, read from the repository and from production on 2026-09-02.**
Enforcement is live and durable (bound `2026-09-02 15:30:20.83726+00`). One
`membership` row exists — Device A, Sandbox — carrying
`entitlement_ended_at = 2026-09-02 15:16:44+00` and
`pending_cleanup_at = 2026-11-01 15:16:44+00`. **Nothing acts on it.** That row
is U7's first real input and its first real fixture.

---

## 1. CANDIDATE SELECTION AND THE FRESH-AUTHORITY DECISION FLOW

### 1.1 The two questions are separate, and keeping them separate is the design

| | Question | Answered by |
|---|---|---|
| **Selection** | *Which identities are worth asking Apple about?* | `membership.pending_cleanup_at <= now()` |
| **Authority** | *May this identity's Connected content be destroyed right now?* | `connected_member(user_id) = false`, evaluated **after** a successful fresh Apple read |

`pending_cleanup_at` is a **stored scheduling timestamp**. Under the standing
cleanup-authority rule it is not sufficient authority for anything irreversible —
it is a hint that the question is worth asking. The authority is the live read.

**The selector keys on `pending_cleanup_at` ALONE.** No join to `auth.users`, no
liveness heuristic, no directory predicate. This is the standing rule and its
reason is a real production identity: the "authenticated, no membership record"
shape (first observed 2026-08-15) must be unreachable by the worker, and keying
on a column such an identity does not possess is what makes that structural
rather than remembered. The partial index
`membership_pending_cleanup_idx ... where pending_cleanup_at is not null`
already exists from U3 and is exactly the right index for this.

### 1.2 The flow

```
  1  SELECT candidates
       membership where pending_cleanup_at is not null
                    and pending_cleanup_at <= now()
       order by pending_cleanup_at asc
       for update skip locked
       limit N                                        -- bounded batch

  2  For each candidate IDENTITY (not row) —
       fresh authoritative read from Apple for EVERY membership row that
       identity holds, in that row's own environment, via the same
       _shared/appstore code path appstore_reconcile_v1 uses.

  3  APPLY each read through the canonical writer
       membership_apply_reconciliation_v1 -> membership_apply_state_v1
       Apple says entitled  -> the writer sets pending_cleanup_at = NULL
                               and the candidate SELF-ELIMINATES
       Apple says not       -> the schedule stands

  4  RE-EVALUATE authority, on the refreshed rows:
       (a) the read in step 2 SUCCEEDED for every row of this identity
       (b) connected_member(user_id) = false
       (c) pending_cleanup_at is still not null and still <= now()
       ALL THREE, or abort this identity and retry later.

  5  DESTRUCTIVE EXECUTION — section 3.

  6  COMPLETION — clear pending_cleanup_at and set cleanup_completed_at in
       ONE statement, only after every step of 5 succeeded.
```

### 1.3 Why step 3 is an *apply*, not a *check*

The obvious shape — read Apple, compare, delete — needs a second implementation
of Apple's entitlement formula on the cleanup path, and a second place for it to
drift. Applying the read through the **canonical writer** instead gives
resubscription cancellation for free: if Apple reports entitled,
`membership_apply_state_v1` already sets `entitlement_ended_at` and
`pending_cleanup_at` to NULL (its "Resubscription, refund reversal or grace
recovery CANCELS pending cleanup" branch), and the candidate disappears from the
selector without the worker deciding anything.

**This is why resubscription cancellation is NOT a U7 unit** (constraint 1). U4
already implements it, S-3 proved it against genuine Apple, and the worker
inherits it by routing the read through the writer rather than around it. The
worker never writes `pending_cleanup_at` to NULL as a cancellation — only as a
**completion** (step 6), which is a different fact recorded in a different
column. **The condition that would reopen it:** if the worker ever needed to
clear that column for a reason other than completion, there would be two writers
of one scheduling column and the cancellation semantics would need re-proving.
The design above has one, so it does not.

### 1.4 The authority is IDENTITY-scoped, so the refresh must be too

**This is the one non-obvious correctness rule in the whole unit, and a per-row
worker gets it wrong by default.**

`membership` is keyed `(user_id, environment)`, so one identity may hold two
rows. `connected_member()` reads **all** of them. Expiry cleanup destroys
**identity-scoped** material — posts, follows, the social graph, the avatar —
because there is one Connected presence per identity, not one per environment.

So a worker that selects a candidate *row*, refreshes that *row*, and then
evaluates an identity-level predicate has computed its authority **partly from
stale state** — which is precisely what the cleanup-authority rule forbids, on
the half of the data it did not look at.

**Rule: refresh every `membership` row belonging to the candidate identity
before evaluating authority. If any of those reads fails, the identity is not
authorised and is retried later.** Falsifier N5 exists to catch an
implementation that refreshes only the candidate row.

**DECISION 4 — RATIFIED as a correctness requirement.** A stale Sandbox candidate
must never cause cleanup of an identity holding live Production entitlement.
**U7b makes this structural rather than a worker convention:** the selector
returns **every** `membership` row of each candidate identity, not only the rows
whose schedule is due — so a worker that refreshes exactly what it was handed is
automatically correct, and one that refreshes less has to discard rows it was
given.

### 1.5 Failure handling — there is no escalation, ever

Every failure mode of the Apple read — 5xx, timeout, malformed body, signature
failure, an unrecognised response shape — lands on **one** rule: **write nothing,
delete nothing, leave the schedule where it is, retry on the next invocation.**
This is Q6's rule, already implemented and asserted in `appstore_reconcile_v1`,
and it is inherited rather than restated.

**There is no "N consecutive failures, then proceed".** A member's content is
never destroyed because Apple was unreachable for long enough. A candidate that
can never be read simply stays a candidate forever, visibly, which is the right
failure: it is an operator problem with a queue to look at, not a silent
deletion.

---

## 2. SANDBOX VERSUS PRODUCTION

**Decision: the SCHEDULE may come from either environment. The AUTHORITY is
always `connected_member(user_id) = false`, which is Production-only by D4.
There is no environment branch anywhere in the destructive path.**

### 2.1 Why not "Production schedules only"

Because it makes cleanup permanently untestable and produces exactly the state
that exists in production today, deliberately and forever: rows carrying a
schedule nothing will ever act on. Sandbox is the only environment in which the
whole lifecycle — purchase, renew, cancel, expire, quarantine, clean — can be
exercised before public release. Refusing to clean Sandbox rows would defer the
first end-to-end exercise of the most dangerous code in the system until a real
paying customer lapses, which is the worst possible time to discover a defect in
it.

### 2.2 Why not "any schedule, clean on that row's own derived state"

Because it is unsafe in a way that is easy to miss. An identity holding a
**lapsed Sandbox row and a live Production subscription** would have its
Connected content destroyed on the Sandbox schedule — a paying member's content,
deleted because a test subscription expired. `connected_member()` in the
authority position forecloses this by construction, because it reads Production
entitlement and nothing else.

### 2.3 What the rule gives, stated plainly

- **Sandbox-only lapsed identity** — `connected_member()` false,
  `membership_state()` `sandbox_only`. Under live enforcement they are **already
  denied every gated surface** and their presence is already invisible. Cleanup
  removes retained content that nothing can currently reach. **Cleaned.**
- **Sandbox lapsed + Production live** — `connected_member()` **true**.
  **Never cleaned**, on the same predicate the API uses to serve them. Content
  cannot be destroyed for someone the server is currently serving.
- **Production lapsed** — `connected_member()` false. **Cleaned.**
- **Production lapsed + Sandbox live** — `connected_member()` false, because
  Sandbox never entitles. **Cleaned**, which is correct: they are not a member.

**This rule is derived from membership correctness, not from protecting beta
data** (constraint 4). Device A's Sandbox row needs no preservation machinery and
gets none; under this rule it simply becomes the first genuine candidate on
2026-11-01, which is a fixture, not a hazard.

### 2.4 DECISION 7 — RATIFIED. The equivalence proposed here is WITHDRAWN

**This section previously ended with the following paragraph, and it is now
withdrawn:**

> *"Consequence worth stating: cleanup and enforcement now share one predicate.
> Anything the API refuses to serve on entitlement grounds is eventually
> collectable, and anything it will serve is never collectable. That equivalence
> is the property to keep."*

**It is false in the first direction and misleading in the second.** Viewer-side
enforcement refuses a lapsed member access to *other members' entire corpus* —
none of which is remotely collectable. And subject-side gating is **derived from
the retention matrix, not equivalent to it**: `README-u6b-subject-visibility.md`
states the derivation in one direction only — *"if ordinary expiry cleanup would
REMOVE it, gate it at lapse; if cleanup would RETAIN it, do NOT gate it."* The
matrix is the authority and the gating is its consequence. **Restating that as a
two-way equivalence inverts the derivation and invites the exact error it was
written to prevent**: reasoning from a visibility fact to a retention decision.

**What survives is only the narrow authority rule, which was never the
equivalence:** cleanup does not run for an identity whose Production predicate
says connected. That is a statement about **when the worker may act**, not about
which bytes are collectable.

**THE RETENTION MATRIX REMAINS THE SOLE AUTHORITY ON WHAT IS REMOVED AND WHAT IS
RETAINED.** Enforcement visibility and expiry retention are related policies and
they are not one policy. §3 is the authority; nothing may be derived from §2.

---

## 3. THE RETENTION MATRIX AS CONCRETE DATABASE AND STORAGE EFFECTS

Subject is the lapsed identity, `uid`. Third parties are `other`.

### 3.1 REMOVED

| # | Effect | Statement / operation |
|---|---|---|
| R1 | Received attachment references | `delete from connected_attachments where recipient_user_id = uid` |
| R2 | Received post shares | `delete from post_shares where recipient_user_id = uid` |
| R3 | Comment-view state as viewer | `delete from post_comment_views where viewer_user_id = uid` |
| R4 | Social graph, both directions | `delete from follows where follower_user_id = uid or followed_user_id = uid` |
| R5 | Post-attachment **objects** | every object under `users/<uid>/` in `attachments` **except** `users/<uid>/connected/*` retained by R7 |
| R6 | Own posts | `delete from posts where owner_user_id = uid` — sent shares cascade via `post_shares_post_id_fkey` |
| R7 | Sent attachments with **no** live recipient reference | object first, then row — see 3.3 |
| R8 | Avatar object, then pointer | object in `avatars`, **then** `account_directory.avatar_key = null` — see 5.2 |

### 3.2 RETAINED — and asserted as hard as the removals

| # | Retained | Must be provably untouched |
|---|---|---|
| K1 | Comments `uid` authored on **other members' surviving posts** | `post_comments where author_user_id = uid and owner_user_id <> uid` |
| K2 | Comments authored by others merely **addressed to** `uid` | **B-19. `recipient_user_id` is never a deletion criterion.** |
| K3 | Sent attachments with a **live** recipient reference | row **and** object |
| K4 | `account_directory` row | `display_name` intact; `avatar_key` nulled by R8; `entitled_until` already past, so `search_account_directory` excludes it |
| K5 | `auth.users` | **U7 never calls `auth.admin.deleteUser`. There is no such call anywhere in the unit.** |
| K6 | `membership` and `membership_binding` | **QA A24's behavioural half.** No FK from `membership` to `membership_binding` and none is added |
| K7 | All local data | **Invariant 1. U7 ships no client code and adds no `LocalFactoryReset` caller.** The two-caller count remains a Phase 3 exit assertion |

### 3.3 The reference count — the one place a naive implementation is wrong

`connected_attachments_asset_recipient_unique` is `UNIQUE (asset_id,
recipient_user_id)` and
`connected_attachments_sender_storage_path` pins `storage_path` to
`users/<sender>/connected/<asset_id>.<ext>`. **So one asset sent to two
recipients is TWO rows sharing ONE object.**

```
  doomed assets  = { asset_id : sender_user_id = uid
                              and no row for that asset has deleted_at is null }
  retained assets= { asset_id : sender_user_id = uid
                              and at least one row has deleted_at is null }
```

For a doomed asset: delete the object, then delete **all** its rows. For a
retained asset: touch neither row nor object.

**This is the reference-counted preservation removed from `delete_account_v1` on
2026-08-13** — its gravestone comments survive at
`supabase/functions/delete_account_v1/index.ts:30` and `:209`. U7 re-implements
it in its own worker, which is an independent reason the two paths do not share
a sequence.

**R1 and R7 cannot interfere**, and this is a constraint rather than a
convention: `connected_attachments_not_self` is
`CHECK (sender_user_id <> recipient_user_id)`, so `uid`'s sender-scoped and
recipient-scoped row sets are **disjoint**. Their ordering is immaterial. Same
reasoning `delete_account_v1` records for its own steps 1 and 3b, verified
against the same constraint.

### 3.4 R5 is NOT `delete_account_v1`'s prefix sweep, and the difference is the whole unit

`delete_account_v1` sweeps `users/<uid>/` **unconditionally**, because under
account deletion nothing under that prefix survives. **U7 must not do that**:
K3's retained objects live at `users/<uid>/connected/<asset>.<ext>`, inside the
same prefix. R5 is therefore a **selective** sweep — list `users/<uid>/`
recursively, then subtract the retained set computed in 3.3.

**Copying `delete_account_v1`'s step 3 into the worker would destroy every
retained sent attachment while every assertion about rows still passed.** That is
the single most likely implementation error in U7 and N10/N12 exist to catch it.

**DECISION 6 — RATIFIED. Selective object deletion is load-bearing.** The
unconditional prefix sweep is not to be copied; a retained sent attachment keeps
**both** row and object; and successful object removal must precede destruction or
clearing of the database evidence needed to find that object again — §4.2 and
§5.2.

### 3.5 DECISION 2 — RATIFIED. The comment cascade is accepted, as a decision

`post_comments_post_id_fkey` is `ON DELETE CASCADE`. **R6 therefore destroys
comments authored by OTHER members on the lapsed member's posts.**

The matrix says "own posts — Removed" and is silent about the conversation on
them. Under account deletion this was accepted because the user asked. Under
expiry, a third party's words are destroyed because somebody else stopped paying
— mechanically different from B-19's defect but adjacent to it.

**RATIFIED 2026-09-02, in both halves, and it is now a decision rather than an
inherited cascade:**

- **Comments by other members on the lapsed member's OWN deleted post MAY
  cascade-delete with it.** After R6 the post is gone, so a preserved comment has
  no render site and no owner surface; preserving one would mean retaining orphan
  rows nothing can display or delete.
- **Comments the lapsed member authored on OTHER members' SURVIVING posts MUST
  remain** — K1, unchanged, and asserted by N13.

**No schema redesign for orphan-comment preservation.** The cascade stays exactly
as `post_comments_post_id_fkey` already defines it; what changes is that it is now
recorded as chosen. **The distinction to keep is authorship versus location:**
`author_user_id` decides what survives, and B-19's rule that `recipient_user_id`
is never a deletion criterion is untouched by any of this.

---

## 4. TRANSACTION, IDEMPOTENCY AND RETRY BOUNDARIES

### 4.1 One cleanup is NOT atomic and must not pretend to be

Three boundaries force this, and only the third is negotiable:

1. **The Apple read is HTTPS and must never sit inside a transaction** — B-30,
   already settled and already the reason `membership_due_for_reconciliation_v1`
   is a separate function from the applier.
2. **Storage deletes are not transactional with Postgres at all.** No amount of
   SQL discipline makes an object removal roll back.
3. The relational deletes *could* be one transaction, and should be — but that
   buys atomicity only across R1–R6, not across the whole cleanup.

So U7 takes the same honest position `delete_account_v1` takes: **the sequence is
not transactional, every step is idempotent, and the ORDER is chosen so any
failure leaves a state a retry can complete.**

### 4.2 Objects before rows — always, and here is the reason

**If rows are deleted first and the object delete then fails, the object is
orphaned permanently.** Nothing can find it again: B-8's lesson is that a
`users/<uid>/` path-prefix heuristic reads the **sender's** uid and cannot
establish liveness, so a later sweep cannot tell a retained asset from an
abandoned one. The row was the only liveness evidence and it is gone.

Reversed — object first, row second — a failure between them leaves a row
pointing at a missing object, which the **next run recomputes and completes**.
The doomed set is derived from rows, so as long as rows outlive objects the
computation is always available.

**Rule: within R7 and within R5/R6, storage removal precedes the row deletion it
is derived from.** N20 proves it by interrupting between them and requiring the
retry to complete.

### 4.3 Completion, and why a new column earns its place

**Proposed schema delta: `membership.cleanup_completed_at timestamptz`, and
nothing else.**

Clearing `pending_cleanup_at` alone is necessary (otherwise the identity is
selected forever and cleanup re-runs on every pass) but not sufficient, because
`pending_cleanup_at = null` would then mean two different things: *the member
resubscribed in time* and *cleanup ran*. Those are QA **C5** and QA **C7**
respectively — the two cases the phase is required to tell apart — and a single
nullable column cannot.

`membership_cleanup_requires_end` permits `pending_cleanup_at` null with
`entitlement_ended_at` not null, so the clear is legal and needs no constraint
change. Completion is written in **one statement** with the clear, last, only
after every step of §3 succeeded.

### 4.4 A resumed run is a NEW run

**A partially-completed cleanup acquires no right to finish itself.** Every
attempt re-reads Apple and re-evaluates `connected_member()` from scratch before
touching anything.

**Accepted consequence, stated rather than hidden:** a member who resubscribes
between a failed attempt and its retry gets their presence back **minus whatever
the first attempt already deleted**. Non-atomicity across storage and Postgres
makes this unavoidable. It is bounded by the 60-day quarantine having already
elapsed, and the alternative — letting a resumed run finish on the strength of
its earlier authorisation — is deletion on stale authority, which is the one
thing the whole unit exists to prevent.

### 4.5 Concurrency and batching — WITH A CORRECTION TO THIS DOCUMENT

**THIS SECTION PREVIOUSLY SAID:**

> *"`for update skip locked` in the selector, so two overlapping invocations
> cannot both claim one identity. Cheap insurance now, load-bearing the moment a
> schedule exists."*

**THAT IS WRONG ABOUT THE MECHANISM, AND NOBODY RAISED IT — it was found while
working out the scheduler unit.** A row lock lives for the duration of the
**transaction that took it**, and the selector's transaction ends when the
function returns. The worker's Apple reads, deletions and completion all happen
**after** that transaction has committed, with no lock held. So `for update skip
locked` would have protected precisely the few milliseconds during which nothing
dangerous happens, and nothing at all during the minutes in which everything
does.

**The failure this would have produced is instructive:** a plausible-sounding
clause, visible in the source, that a reviewer would read as concurrency control
and that provides none. Under U7e's scheduler an overrunning run — one stuck on an
Apple timeout while the next fires — is exactly the realistic case, and the guard
would have been decorative.

**The correct mechanism is a LEASE, which is durable state rather than a lock:**

- `membership.cleanup_claimed_at timestamptz`, written **by the selector, in the
  selector's own transaction**, and therefore surviving it.
- A row is a candidate only when
  `cleanup_claimed_at is null or cleanup_claimed_at < now() - interval '1 hour'`,
  so a crashed run's claim expires rather than blocking the identity forever.
- Cleared by `membership_cleanup_complete_v1`, alongside the completion marker.
- `for update skip locked` is **still used**, but only for what it can actually
  do: making two selectors racing on the same statement pick disjoint sets.

**CORRECTED 2026-09-02. THIS DOCUMENT SAID THE LEASE WAS "INERT UNTIL U7e" AND
THAT WAS WRONG ABOUT WHEN THE REQUIREMENT STARTS.**

> *"The lease column is added in U7b and is INERT until U7e, deliberately."*

**The moment the worker can be invoked at all, concurrent invocations are
possible** — two terminals, a retried curl, an operator who does not know a run is
already going. **U7e raises the LIKELIHOOD of concurrency; it does not create the
correctness requirement.** So the lease is **live from the worker's first
executable version**, which is U7c, and U7b lands the column and the claim
semantics it needs.

**Minimal and crash-recoverable, and explicitly NOT a job system.** One
timestamp column, one predicate, one expiry interval. No queue table, no worker
registry, no heartbeat, no retry counter, no state machine. A crashed run leaves a
claim that expires on its own after the lease interval and the identity becomes a
candidate again — which is the whole of the recovery design.

- **Bounded batch**, proposed `N = 25` identities and never unbounded. Bounds
  blast radius and makes a run scoreable against a prediction.
- **Idempotency of `storage.remove` on an absent key is an ASSUMPTION, not a
  fact.** **DECISION 5 — RATIFIED: it is measured once, inside U7c, at the point
  the retry path is built — not promoted into a research unit.** If it errors, the
  removal is preceded by an existence check and the ordering rule is unaffected.

---

## 5. OBJECT DELETION FAILURE

### 5.1 The general rule

**A failed object removal ABORTS that identity's cleanup.** No further steps, no
completion marker, no partial credit. The rows that name the surviving objects
are still present, so the next run recomputes exactly the same doomed set and
resumes. Reporting is per identity, so one identity's abort never blocks the
batch.

### 5.2 The avatar, and C-33's ordering applied to a path that RETAINS the row

**Object first. Clear `account_directory.avatar_key` only on success.** If the
removal fails, `avatar_key` stays populated and the retry has a pointer to work
from. Clearing the pointer first strands a real photo behind a null column —
C-33's exact defect.

**Sweep by prefix AND by pointer**, the B-20 union, in both directions: the
prefix catches an object the column does not name, the pointer catches a stale
key pointing outside the prefix. `avatars_insert_owner_only` pins every client
write to `users/<uid>/avatar.jpg`, so the sweep can reach one object and cannot
touch anyone else's; the listing is flat for the same reason.

**One thing is genuinely better here than under deletion, and it changes nothing
about the ordering.** `delete_account_v1` nulls the pointer and then loses the
row to the `auth.users` cascade, so a stranded object is unreachable forever.
U7 **retains** both the row and the identity, so a stranded object stays
reachable by a later run. The ordering is kept anyway — the failure direction is
identical and the cost is zero.

### 5.3 Predicted render after cleanup

A retained comment (K1) by a cleaned-up member renders as **initials**: the
directory row and `display_name` survive, `avatar_key` is null. This is already
what U6b's subject-side gating produces at lapse, so **quarantine and
post-cleanup are visually identical and U7 introduces no new UI state.**

---

## 6. THE BORN-LAPSED CASE

### 6.1 The concrete reachable state

`membership_establish_v1` inserts `entitlement_ended_at` and
`pending_cleanup_at` as **NULL unconditionally on every insert path** (F11) —
including when Apple reports the subscription **already expired** at
establishment. This is reachable and is in fact U5's headline target case: a
dormant pre-cutover subscriber returns, attests, and a row is created for a
subscription that lapsed months ago.

The row then carries no schedule until the **first subsequent transition** seen
by the canonical writer, which computes:

```
  v_ended   := coalesce(v_revoked, greatest(v_renewal, v_grace), now())
  v_cleanup := v_ended + 60 days
```

For a subscription that expired eight months ago, `v_ended` is eight months ago
and **`v_cleanup` is six months in the past — immediately due.**

### 6.2 The harmful consequence

**Their Connected content is destroyed on the next worker pass with zero
quarantine.** The quarantine exists so a returning member can resubscribe and get
their presence back whole; a schedule already overdue at the instant it is first
written gives them none of it.

**The timing is the worst possible.** A dormant member who attests is, by
definition, holding the app open right now. Under live enforcement they are being
denied, which is exactly the moment they are most likely to resubscribe — and it
is the moment this defect deletes everything they would have got back.

### 6.3 DECISION 3 — RATIFIED. The smallest safe rule, in the writer

**The quarantine is never retroactively spent.** In
`membership_apply_state_v1`, when a schedule is being written for the first time
and the computed deadline is already past, floor it:

```sql
v_cleanup := v_ended + c_quarantine;
if v_prev.pending_cleanup_at is null and v_cleanup <= now() then
  v_cleanup := now() + c_quarantine;
end if;
```

Three properties, each deliberate:

- **`entitlement_ended_at` is untouched** and stays Apple's own truth. Only the
  *schedule* is floored, so no fact is falsified.
- **The floor applies only when no schedule existed.** An already-recorded
  schedule is never pushed out, so the anti-sliding rule the writer already
  enforces survives intact (N23).
- **It lives in the writer, not the worker.** The worker cannot distinguish this
  case: its only durable evidence is `entitlement_ended_at`, which for a
  born-lapsed row is genuinely long past and passes every test the worker could
  apply. There is no smaller correct place.

**This is a change to a deployed, production-critical function**, and it stays in
the **canonical membership writer** rather than becoming worker special-casing —
ratified 2026-09-02. It is scored by its own predictions (N22, N23, N24) and
deploys with U7b.

**Its blast radius on ordinary traffic is provably nil, which is why it can share
a deploy with additive work.** The floor's guard is
`v_prev.pending_cleanup_at is null and v_cleanup <= now()`; on an ordinary lapse
`v_ended` is approximately now, so `v_cleanup` is sixty days in the future and the
guard **cannot** fire. N24 proves it fires at all, on a constructed born-lapsed
row — because a guard that cannot fire is worthless, and one that fires on every
lapse would be a different defect.

---

## 7. SCHEDULING — DECISION 1 REVERSES THIS DOCUMENT'S POSITION

**THIS SECTION PREVIOUSLY CONCLUDED:**

> *"U7 ships with no scheduler. Manual, authenticated invocation only... Adding a
> schedule afterwards is its own step."*

**The conclusion was right about SEQUENCING and wrong about SCOPE.** It treated an
unscheduled worker as a finished U7; it is not. **RATIFIED 2026-09-02: U7 requires
automatic scheduling to be complete.** A 60-day quarantine that ends only when a
human remembers to invoke a function is not the product — the quarantine's whole
promise is that it expires on its own.

**What survives unchanged is the reason for the ordering**, and it is a risk
statement rather than an inherited ritual: **the scheduler is the component that
makes unattended destructive execution possible.** Nothing before it can delete
without a person deciding to; the scheduler is precisely the point at which that
stops being true. So it goes last, alone, and it is the one place in U7 where a
kill mechanism is genuinely earned.

**The ratified progression:**

```
  implement and accept LOCALLY            U7b, U7c      no production
  deploy SQL + worker, dry_run default    U7d P1-P3     production, inert
  DRY RUN — no deletion possible          U7d P4        -> AUTHORISATION 1
  manual execute, ONE identity            U7d P5-P6     -> AUTHORISATION 2
  scheduler enabled, unattended accepted  U7e           -> AUTHORISATION 3
```

**Everything in the old §7.1 still holds and is why P1–P3 are safe.** U7b's SQL
contains no path to a deletion, because the deletion lives in the Edge Function.
An Edge Function does not run itself: it needs an inbound POST bearing the service
role key. **That "no scheduler" property is ASSERTED, not merely observed** — U4
acceptance `A57f` requires
`select count(*) from pg_extension where extname='pg_cron'` to be **0**, and
`README-u5-deployment.md` re-checks it against production. **U7e must therefore
consciously AMEND A57f rather than delete it** — and the amendment should assert
*the expected schedule*, so the property stays checked instead of becoming
unwatched. An assertion that fails when U7e lands is the assertion working.

**`dry_run` remains the default mode** and destructive execution requires an
explicit `mode: "execute"`. That defends against the realistic failure — a bad or
replayed invocation — and it keeps defending after U7e, because the scheduler must
name the mode explicitly in its own request body.

---

## 8. PREDICTION-FIRST LOCAL ACCEPTANCE

**The fixture largely exists already.** `supabase/tests/u2/fixture.sh` builds
three identities, the two-recipient shared asset on one storage path, third-party
comments and follows that must survive, avatars with directory pointers, and a
post attachment — built for `delete_account_v1`'s blast-radius verification and
almost exactly U7's shape. `supabase/tests/u2/lib.sh` already provides `putobj`
and `objcount`. **U7 forks it and adds two things: `deleted_at` variants to make
the reference count non-vacuous, and `membership` rows to make the subject
lapsed.**

**Non-vacuity is a pass condition, not a nicety.** Every deletion below must have
real work to do and every retention rule a real row to spare; the fixture
inventory is asserted before the run, as U2's is.

### Authority

| | Case | Prediction | Falsifier |
|---|---|---|---|
| **N1a/b/c** | Apple read fails — 5xx, timeout, malformed | zero rows and zero objects deleted; `pending_cleanup_at` unchanged; `cleanup_completed_at` null | any deletion, or any write |
| **N2** | Apple reports **entitled** at the fresh read | writer clears `pending_cleanup_at`; candidate self-eliminates; **nothing deleted** — this is **QA C5** | any deletion |
| **N3** | Apple reports not-entitled, `connected_member()` false | cleanup proceeds | refusal |
| **N4** | Sandbox schedule due, identity holds a **live Production** row | **nothing deleted** | any deletion — §2.2 as an executable assertion |
| **N5** | Identity holds rows in **both** environments | **both** refreshed before authority is evaluated | authority computed after refreshing only the candidate row |
| **N6** | `pending_cleanup_at` in the future | not selected | selection |
| **N7** | Not entitled, `pending_cleanup_at` **null** | not selected | selection |
| **N8** | No `membership` row at all | never selected, on any path | selection — the "authenticated, no membership record" protection |

### Deletion and retention

| | Case | Prediction |
|---|---|---|
| **N9** | Full matrix, one fixture | every count in §3.1/§3.2 matches a figure committed before the run |
| **N10** | Sent attachment, **live** recipient reference | row **and** object both survive |
| **N11** | Sent attachment, all references soft-deleted | row and object both gone |
| **N12** | One asset, two recipients, **one live one soft-deleted** | **retained, both** — the case a naive per-row implementation destroys |
| **N13** | `uid`'s comment on another member's surviving post | retained, and `get_account_directory_by_user_ids` still resolves the author — **G10** |
| **N14** | Another member's comment **addressed to** `uid` | retained — **B-19** |
| **N15** | `auth.users`, `membership`, `membership_binding` | all three survive — **QA A24's behavioural half** |
| **N16** | `account_directory` | row survives, `display_name` intact, `avatar_key` null |
| **N17** | Third-party blast radius | every count on the control identity **unchanged**, as D14/D15 scored theirs |

### Failure, idempotency, retry

| | Case | Prediction |
|---|---|---|
| **N18** | Object removal fails mid-run | no rows deleted, no completion marker; retry completes. **Needs fault injection — if unavailable, recorded as UNEXERCISED, never as a pass** |
| **N19** | Second run over a completed identity | no-op, zero further deletions — **QA C8** one level down |
| **N20** | Interrupted between objects and rows | retry completes; this is what proves §4.2's ordering |
| **N21** | Avatar object removal fails | `avatar_key` **still populated**. Falsifier: nulled pointer with the object present — C-33's exact defect |

### Born-lapsed

| | Case | Prediction |
|---|---|---|
| **N22** | Establish against a long-expired subscription, then deliver a transition | `pending_cleanup_at >= now() + 59 days`. Falsifier: any schedule in the past |
| **N23** | An **existing** schedule, later notification | never pushed out — the anti-sliding rule survives the floor |

### Guards

| | Case | Prediction |
|---|---|---|
| **N24** | Every guard added by U7 | each one is **proved to fire** under a constructed condition. **A guard that cannot fire is worthless** (C56-7) |

---

---

## 9. THE IMPLEMENTATION PLAN

**Four units, against an expectation of five.** Two combinations are proposed and
each is argued from safety, not tidiness; nothing is split merely to match a list.

### 9.1 U7b — CLEANUP PRIMITIVE, WRITER CORRECTION, FIXTURES. LOCAL ONLY

**COMBINES two of the expected units — the cleanup primitive and the born-lapsed
writer correction — and here is why that is safer rather than merely fewer.** Both
are SQL-only; both are inert with respect to deletion; neither depends on the
other, so combining costs no sequencing. What it buys is **one production SQL
submission instead of two**, and a production SQL submission is the single most
dangerous routine act in this project — the U6a apply reported *"Success. No rows
returned."* and changed nothing at all. Halving the number of them is a real
safety gain. The usual objection — that mixing additive work with a modification
to a deployed function means the rollback cannot be "drop what was added" — is
answered the way U4, U5b and U6a answered it: a **regenerated full rollback
baseline**, not a drop list. And the writer change's blast radius on ordinary
traffic is provably nil (§6.3).

**THE COMBINATION IS PERMITTED ON ONE CONDITION, RATIFIED 2026-09-02: THE TWO
HALVES' PREDICTIONS AND TESTS MUST STAY INDEPENDENT, SO NEITHER CAN HIDE A
FAILURE IN THE OTHER.** Concretely, and enforced by construction rather than by
care:

- **Two separate acceptance scripts** with **separate PASS/FAIL tallies and
  separate exit codes.** One green suite can never carry a red one.
- **Disjoint fixtures.** The born-lapsed suite exercises
  `membership_apply_state_v1` and never calls the selector or the completion RPC;
  the primitive suite never calls the writer. Neither half can satisfy an
  assertion belonging to the other.
- **The structural prediction is ITEMISED PER HALF**, so the deploy delta is
  attributable and a miss cannot be absorbed by an aggregate that happens to
  total correctly.

**Mutation surface — repository only:**

| | |
|---|---|
| New migration | `membership.cleanup_completed_at timestamptz`; `membership.cleanup_claimed_at timestamptz` — the lease, **live from U7c**, the worker's first executable version (§4.5) |
| New function | `membership_due_for_cleanup_v1(p_limit int default 25)` — returns **every** membership row of each candidate identity (§1.4), claims the lease, `for update skip locked` for same-statement racing only. Returns `(user_id, environment, original_transaction_id)` and **no Apple state, no scheduling state** — the narrowing U4's own grant audit applied to its selector |
| New function | `membership_cleanup_complete_v1(p_user_id)` — clears `pending_cleanup_at` and `cleanup_claimed_at` on **all** that identity's rows and sets `cleanup_completed_at`, in ONE statement |
| Modified function | `membership_apply_state_v1` — the §6.3 quarantine floor, and nothing else |
| Grants | the two new functions to `service_role` only; revoke from `public`, `anon`, `authenticated` first, per the established pattern. **No client role gains anything** |
| Fixtures | Membership/identity rows only. **The content-and-storage fixture forked from `u2/fixture.sh` belongs to U7c**, which is the first unit that deletes anything — building it here would ship an unexercised fixture and invite it being read as tested |
| Acceptance | **TWO scripts, separate tallies, separate exit codes, disjoint fixtures** — `acceptance-primitive.sh` and `acceptance-bornlapsed.sh` |

**Prediction-first acceptance:**

- **N6, N7, N8** — selection boundaries, including that an identity with no
  membership row is unreachable on every path.
- **Selector shape** — a candidate identity with rows in two environments yields
  **both**; falsifier: only the due row returned.
- **N22, N23, N24** — the born-lapsed floor: fires on a constructed born-lapsed
  row, **cannot** fire on an ordinary lapse, and never pushes out an existing
  schedule.
- **Completion RPC is idempotent** — a second call is a no-op.
- **Privilege assertions** — the two new functions reachable by `service_role`
  alone; `anon`, `authenticated` and `PUBLIC` all false; no table privilege
  granted anywhere.
- **B-23 STRUCTURAL DELTA, COMMITTED BEFORE ANY DEPLOY:** columns **+2**,
  functions **+2 new and 1 modified**, function_grants **+2**;
  `constraints`, `policies`, `rls_enabled`, `triggers`, `table_grants`,
  `column_grants` and `storage_buckets` all **IDENTICAL**. Scored at U7d P2.

**Production touched: NO.**

**STOP:** local suite green, B-23 delta prediction committed, rollback baseline
regenerated and rehearsed. **Do not deploy.** U7b's deploy happens inside U7d,
after U7c is green — deploying a selector whose only consumer does not yet exist
would be deploying an unproven interface.

### 9.2 U7c — THE WORKER. LOCAL ONLY

**Mutation surface — repository only:**

| | |
|---|---|
| New Edge Function | `supabase/functions/membership_cleanup_v1/index.ts` |
| Config | a `[functions.membership_cleanup_v1]` block, `verify_jwt = false` plus its **own** constant-time service-role comparison, mirroring `appstore_reconcile_v1` exactly |
| Reused, not rewritten | `_shared/appstore` for the Apple read. **No second implementation of the most dangerous call in the system** — that instruction is `appstore_reconcile_v1`'s own |
| Acceptance | `supabase/tests/u7/acceptance-worker.sh`, driven by the programmable Apple stub already at `supabase/tests/u5/applestub.ts` |

**Prediction-first acceptance — the whole of §8's battery except the U7b rows:**
**N1a/b/c** (three failure modes, zero writes and zero deletions),
**N2** (entitled → self-eliminates, QA **C5**), **N3**, **N4** (Sandbox schedule
with live Production → nothing deleted), **N5** (multi-environment refresh),
**N9–N17** (the matrix and third-party blast radius), **N18–N21** (failure,
idempotency, avatar ordering).

**Two things happen here and nowhere else:**

- **The `storage.remove` absent-key measurement** — decision 5, taken once, at the
  point the retry path is built, recorded in the unit's README. Not a research
  unit.
- **The dry-run output format is FIXED**, because U7d depends on it being able to
  serve as a prediction (§9.3).

**Production touched: NO.**

**STOP:** full local battery green, storage behaviour measured and recorded, dry
run and execute proven to agree on the same fixture.

### 9.3 U7d — DEPLOY, DRY RUN, AND THE FIRST REAL EXECUTION. PRODUCTION

**COMBINES the expected "deploy" and "manual behavioural acceptance" units**, so
that one procedure carries the deploy, the dry run and the first execution with
explicit stops between them.

**CORRECTED 2026-09-02. THIS SECTION PROPOSED USING THE DRY RUN AS THE PREDICTION
ORACLE, AND THAT IS NOT PREDICTION-FIRST:**

> *"the dry run's own output IS the prediction the execution is scored against —
> committed before the execution, produced by the code under test, at production
> scale. That is a stronger prediction than any figure written by hand."*

**It is a WEAKER one, and the error is that both modes are the same
implementation.** Dry run and execute share the candidate selection, the Apple
read, the authority evaluation and the doomed-set computation; they differ only in
whether the removals are issued. **A defect in anything they share appears
identically in both**, so agreement between them proves the two modes are
consistent and proves nothing about correctness. A wrong doomed set would be
predicted wrongly and then executed wrongly, in perfect agreement, scoring a pass.

**THE CORRECTED PROCEDURE — three artefacts, and the independent one comes
first:**

1. **An INDEPENDENT prediction**, derived by hand from the production state and
   the §3 retention matrix — which rows, which objects, which retentions — written
   down and committed **before** the worker is invoked in any mode.
2. **The DRY RUN**, scored against that independent prediction. A disagreement
   stops everything and is a finding, not a reconciliation exercise.
3. **AUTHORISATION**, then **live execution scored against BOTH** — the
   independent prediction and the accepted dry run.

**The dry run remains a valuable gate.** What it is not is the oracle.

| Step | Action | Reversible |
|---|---|---|
| **P0** | Pre-flight: production baseline, B-23 capture, confirm `enforcement_enabled = true`, record the candidate row's exact state | read-only |
| **P1** | Apply U7b's SQL. **Guard inside the transaction, ending in a `SELECT` that returns a row** — the standing rule, so "no rows returned" is the symptom and not the disguise | yes, regenerated baseline |
| **P2** | Score the structural delta against U7b's committed prediction; B-23 recapture → **GATE MET** | — |
| **P3** | Deploy `membership_cleanup_v1`. Verify the **deployed bundle** — SHA against source, `verify_jwt: false` — not the tree | yes |
| **P4** | **DRY RUN against production.** Emits the exact rows and objects that would be affected. **No deletion is possible in this mode** | n/a |
| — | **AUTHORISATION POINT 1.** Commit P4's output as the prediction. Nothing has been deleted | — |
| **P5** | `mode: "execute"`, **ONE identity**, bounded | **NO** |
| **P6** | Score against P4 exactly, plus a full blast-radius count on a control identity | — |
| — | **AUTHORISATION POINT 2** before any second identity | — |

**Prediction-first acceptance:** P2 against U7b's committed delta; **P6 against P4,
row for row and object for object**; the §3.2 retentions each asserted positively;
the control identity's every count unchanged; `auth.users` unchanged;
`membership` and `membership_binding` both surviving (**QA A24's behavioural
half**); `cleanup_completed_at` set and `pending_cleanup_at` cleared.

**Production touched: YES.** P1 and P3 are deploys, and both are inert — the SQL
has no path to a deletion and the function will not run itself. **P5 is the first
irreversible act in the whole of U7.**

**STOP:** two, both explicit and both named above.

**THE PRODUCTION ACCEPTANCE FIXTURE — AUTHORISED IN PRINCIPLE 2026-09-02,
CONDITIONS ATTACHED.** Production holds exactly one candidate, due **2026-11-01**.
The account holder is willing, **when U7d is reached and under explicit
authorisation at that time**, to advance Device A's disposable Sandbox
`pending_cleanup_at` so it is due, rather than waiting sixty real days.

**DO NOT MUTATE IT NOW.** Three conditions, all of which belong to U7d:

- **P0 must first capture the genuine original scheduled value**
  (`2026-11-01 15:16:44+00`) as recorded evidence, before anything changes it.
- **The fixture mutation is an explicit, separately-recorded operator act**, never
  folded into a deploy step, and **reversible where practical** — the original
  value is restorable from P0's capture.
- **It is scored as a fixture, not as evidence.** What it tests is *worker
  execution*; it tests nothing about the quarantine arithmetic.

**The 60-day arithmetic already has its evidence and does not need re-earning.**
Device A's genuine lapse produced `entitlement_ended_at 2026-09-02 15:16:44+00` →
`pending_cleanup_at 2026-11-01 15:16:44+00`, observed in production from a real
Apple notification. **Waiting sixty real days would re-observe a calculation
already witnessed**, which is why the fixture advance costs nothing that matters.
N22/N23 cover the floor; this covers the worker.

### 9.4 U7e — SCHEDULER ACTIVATION AND UNATTENDED ACCEPTANCE. PRODUCTION

**Deliberately alone. This is the unit that makes deployment sufficient for
unattended destruction**, and it is the only place in U7 where a kill mechanism is
earned rather than copied.

**Mutation surface:** a scheduling mechanism, its credential handling, the cron or
equivalent entry invoking the worker with an explicit `mode: "execute"`, and the
**conscious amendment of `A57f`** to assert the expected schedule rather than the
absence of one.

**THE MECHANISM IS NOT PRE-DECIDED HERE, AND ONE CONSTRAINT IS ALREADY BINDING —
see §10(b).**

**RATIFIED 2026-09-02: no service-role credential may be silently stored in or
exposed from PostgreSQL.** `pg_cron` + `pg_net` is the shortest route precisely
because it puts the key where cron can read it — a credential-at-rest regression
on the one key that can do everything, reachable by anything that can read a
table or a setting. An external scheduler holding the key outside the database is
the alternative.

**The invocation route and the credential boundary are resolved explicitly before
U7e, and the rejected route is recorded** — the discipline D4 applied when it
rejected an allowlist inside the entitlement predicate. **This question does not
block U7b or U7c**, neither of which touches scheduling or credentials.

**Prediction-first acceptance:** the schedule fires when predicted; an unattended
run with **zero** candidates is a no-op that writes nothing; an unattended run with
one candidate performs **exactly** what a dry run predicted immediately before it;
and the **lease becomes non-inert** — a deliberately overrun run is proven to skip
a claimed identity rather than double-process it (`cleanup_claimed_at`, §4.5).

**Production touched: YES, and this is the only unit whose effect is unattended.**

**STOP:** **AUTHORISATION POINT 3**, explicit, before enabling. The kill mechanism
is disabling the schedule entry — one act, reversible, and it stops future
unattended runs without touching a single row of membership state.

---

## 10. REMAINING QUESTIONS

**The three from the accepted scope are closed.** (a) The comment cascade is
**ratified** — §3.5. (b) `storage.remove` is **measured inside U7c**, not promoted
to a unit — §4.5. (c) Scheduling is **required and sequenced last** — §7.

**The production-fixture question is ANSWERED IN PRINCIPLE** — §9.3. The account
holder will authorise advancing Device A's disposable Sandbox
`pending_cleanup_at` when U7d is reached, subject to P0 capturing the genuine
original value first, the mutation being an explicit and separately-recorded
operator act, and it being scored as a fixture rather than as evidence. **The
authorisation is given in principle now and must be given again at the time.**

**ONE GENUINE QUESTION REMAINS, and it belongs to a unit that has not started.**

**U7e's scheduling mechanism and its credential boundary.** One constraint is
already binding — **no service-role credential silently stored in or exposed from
PostgreSQL**, which rules out the `pg_cron` + `pg_net` route in its obvious form.
What is undecided is what replaces it: an external scheduler holding the key
outside the database, or some other invocation route. **Resolved explicitly
before U7e, with the rejected route recorded. It does not block U7b or U7c**,
neither of which touches scheduling or credentials.

**Not a question, recorded so it is not mistaken for one:** Device A's Sandbox row
is beta data requiring no preservation, and no preservation machinery is built for
it.

