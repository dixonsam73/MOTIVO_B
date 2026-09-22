# Founding 500 — proposed design and scope

> **RETIRED 21 September 2026. HISTORICAL RECORD ONLY — NOT AN ACTIVE REQUIREMENT.**
>
> Samuel chose Apple's one-year introductory free trial instead. **The custom grant
> described below is not being built**: no `founding_place` ledger, no allocation
> protocol, no second entitlement source, no grant-only cleanup. See
> `docs/pricing-launch-model.md` for the current direction.
>
> It is preserved unedited because its reasoning is what produced the decision — in
> particular §5's grant-only cleanup problem, which is the largest thing the Apple
> route removes, and the reconciled Codex corrections in §§10–12. Nothing here may be
> cited as a requirement.

**21 September 2026. RECONCILED PLANNING SCOPE AND PRODUCT DECISIONS APPROVED BY SAMUEL.**

**Samuel's decision after independent review:** agreed to all three recommendation
groups. Former beta testers use the ordinary public App Store activation path;
**no special code, reserved places, migration or operator exception for them**.
Samuel will notify the handful of active testers before launch himself. No outreach
by either agent is requested.

No retrospective grant for already-paying subscribers; deleted accounts never
replenish capacity. Retaining a minimal pseudonymous identifier to prevent repeat
grants is approved in principle, with its exact form, retention period and privacy
position still to be settled. Conversion is offered at expiry; no extra introductory
trial on the in-app route; stop before payment if the signed option cannot be
prepared, and honour valid external Apple purchases.

This approves the planning scope and product direction, not unresolved technical
claims or a cleanup exception. F1 evidence, the separate cleanup protocol review,
adult-only assurance and server trust, and privacy-retention gates remain open.
No implementation, deployment, commit or push was performed for this decision.
Earlier proposal and pending-decision wording below records the review history;
this decision supersedes it.

**Nothing here is implemented or deployed.** No SQL was run,
no secret read, no App Store Connect setting inspected, no device driven, no build
or test executed for this document. Every claim about current behaviour comes from
reading the repository at the checkpoint below; every claim about Apple comes from
Apple's own documentation fetched on 21 September 2026 and is cited. Where I have
not established something, it is labelled **NOT ESTABLISHED** rather than softened.

Claude proposed the design; Codex independently reviewed it; both reconciled it
before Samuel approved the planning scope and product decisions above.

---

## 0. Checkpoint

| | |
|---|---|
| Repo | `/Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO` |
| Branch | `feature/solo-connected` |
| Local HEAD | `15af5c9` — *Record the release priorities and the Founding 500 handover* |
| Remote | `git ls-remote origin feature/solo-connected` → `15af5c9beb852c0d7638141cc97ed0a4836aeab2` |

Local and remote agree, which matches Codex's independently verified checkpoint. The
tree advanced from `1a4c09f` to `15af5c9` during this session; my earliest reads in
this window were at `1a4c09f` and none of them touched a file changed by `15af5c9`
(that commit adds two documents).

**REVISION 3 — Codex's final consistency corrections applied (§11). REVISION 2
reconciled against Codex's full review including R1–R7**
(`docs/founding-500-codex-review-2026-09-21.md`). Revision 1 addressed only that
review's earlier sections; this one answers all seven proposal-review findings.
**All seven are agreed, several of them as defects in my design rather than as
refinements of it** — contention reported as exhaustion, a quarantine conjunct
failing *open* on NULL, eligibility resting on screen order, and a silent fail-open
on trial suppression are the four that would have shipped wrong. §12 carries the
point-by-point dispositions, and §11 lists every correction so none is quietly
absorbed. Two Apple claims Codex raised I re-verified directly rather than adopting,
because the design turns on them; both held, and neither makes the design safe.

---

## 1. What the current mechanism actually is

Measured from `supabase/schema/` (the committed production capture), the deployed
function bodies, the cleanup worker source and the client.

### 1.1 Entitlement has exactly two server-side axes, and they are not the same axis

**The actor gate.** 23 policies and `search_account_directory` call
`enforcement_gate(surface)`, which returns `connected_member_self()` when
`enforcement_active()` is true. `connected_member(uuid)` reads `public.membership`
and nothing else:

```sql
select coalesce((select bool_or(
     m.environment in ('Production','Sandbox')
     and coalesce(m.apple_status,0) <> 5
     and (coalesce(m.renewal_date > now(), false)
          or coalesce(m.is_in_billing_retry and m.grace_period_expires_date > now(), false)))
   from public.membership m where m.user_id = target_user_id), false);
```

**The subject-visibility axis.** Four tables carry a denormalised
`*_entitled_until` column — `posts.owner_entitled_until`,
`post_shares.owner_entitled_until`, `follows.followed_entitled_until`,
`account_directory.entitled_until` — written by `tg_set_entitled_until` (BEFORE
INSERT OR UPDATE on all four) and refreshed by `tg_membership_propagate` (AFTER
INSERT/UPDATE/DELETE on `membership`). Both call `membership_entitled_until(uuid)`.
`posts_select_public_or_owner`, `post_shares_select_recipient`,
`attachments_select_via_visible_post`, `avatars_select_owner_or_approved_follower`
and `search_account_directory`'s D-U6-1 clause all test `... > now()`.

**These are independent and a Founder needs both.** Satisfying only the actor gate
gives a member who can act but whose posts, avatar and directory row are invisible
to everyone else. Satisfying only the visibility axis gives a member whose own
requests are all denied. Any design that touches one and not the other is wrong.

### 1.2 `public.membership` is structurally Apple's, and deliberately so

`original_transaction_id NOT NULL`, `product_id NOT NULL`,
`renewal_info_signed_date NOT NULL`, `binding_method NOT NULL` with
`CHECK (binding_method IN ('purchase','legacy_claim'))`, `bound_at NOT NULL`,
`UNIQUE (environment, original_transaction_id)`, `CHECK (environment IN
('Sandbox','Production'))`.

`membership_establish_v1` is the only INSERT into it anywhere and **derives**
`binding_method` from which artefact carried the binding token. There is no value
in that CHECK a Founder could honestly take, and inventing one is precisely B-24's
correction applied one level down in U4. **FM-1 is enforced by the schema, not by
anybody remembering it.**

### 1.3 Cleanup authority, read from the worker rather than the summary

`membership_cleanup_v1/index.ts` does, per identity: select → refresh **every** row
of that identity through a live Apple read applied via
`membership_apply_reconciliation_v1` → call `membership_cleanup_authorised_v1` →
destroy → `membership_cleanup_complete_v1` last.

```sql
-- membership_cleanup_authorised_v1
v_member := public.connected_member(p_user_id);
select exists (select 1 from public.membership m
                where m.user_id = p_user_id
                  and m.pending_cleanup_at is not null
                  and m.pending_cleanup_at <= now()) into v_due;
return ... 'authorised', (not v_member) and v_due ...
```

Three properties that matter to this design:

1. **Candidates come only from `public.membership`.** `membership_cleanup_eligible_v1`
   selects `from public.membership m where m.pending_cleanup_at is not null and ...`.
   An identity with no membership row is never a candidate, ever.
2. **Authority already consults `connected_member()`.** Any new entitlement source
   that reaches that predicate automatically protects its holders from cleanup. That
   is inherited, not added.
3. **A failed or ambiguous Apple read is never a deletion**, and the worker's
   step 2 iterates the identity's Apple rows. An identity with zero Apple rows would
   pass step 2 vacuously — which is the single most dangerous thing in this design
   and is treated as such in §5.

### 1.4 The client

`ProductionAppModeActivation.resolve` = `BackendConfig.isConfigured ∧ isEntitled ∧
auth.hasConnectedIdentity`, where `isEntitled` is local StoreKit
(`Transaction.currentEntitlements` filtered to the two Connected product ids).
**A Founder is not locally entitled and would sit in Solo with a fully working
server-side membership.**

The join sequence is: `ConnectedIntroductionView` → `requestAgeRange` (gates 13, 18)
→ SIWA → `ensureAgeBandEstablished` → `MembershipSelectionView` (fetches the binding
token on appear) → `product.purchase(_:appAccountToken:)` → `.verified` →
`attestIfNeeded(force: true)` → `onJoinComplete`.

`MembershipAttestationCoordinator`'s invariant is `locally entitled ∧
hasConnectedIdentity ∧ BackendConfig.isConfigured`. A Founder fails the first term,
so **no attestation ever fires for a Founder** — which is correct (there is nothing
to attest) and has a consequence covered in §3.5.

There is **zero** introductory-offer plumbing in the client: no `isEligibleForIntroOffer`,
no `SubscriptionInfo`, no `PurchaseOption` beyond `.appAccountToken`. `Etudes.storekit`
carries `"introductoryOffers": []` on both products. The paywall renders
`product.displayPrice` only.

---

## 2. The five gaps, stated as gaps

| # | Gap | Why it exists |
|---|---|---|
| **G1** | A Founding entitlement has nowhere to live | `membership`'s NOT NULLs and CHECK are Apple-shaped (§1.2) |
| **G2** | Neither authority predicate can see a grant | `connected_member` and `membership_entitled_until` read one table (§1.1) |
| **G3** | There is no non-purchase activation path | The whole join flow terminates in `product.purchase` (§1.4) |
| **G4** | Client mode has no grant term | `resolve` requires local StoreKit entitlement (§1.4) |
| **G5** | FM-2 is unreachable for a grant-only Founder | Cleanup candidates come only from `membership` (§1.3) |

The pricing note named G1, G3 and G5. **G2 and G4 it did not name**, and G2 is the
one that decides whether the feature works at all rather than merely half-works.

---

## 3. Proposed design

### 3.1 One table, named for what it is

```sql
create table public.founding_place (
  place_number         integer primary key,
  -- NULL means "no live identity": either never claimed, or claimed by an account
  -- that has since been deleted. It is NOT the unclaimed test -- claimed_at is.
  user_id              uuid unique references auth.users(id) on delete set null,
  app_transaction_id   text unique,          -- erasable (Group B2)
  source_environment   text,                 -- erasable
  -- THE SPENT DISCRIMINATOR. Set at claim, and NEVER cleared, by anything.
  claimed_at           timestamptz,
  expires_at           timestamptz,          -- erasable
  cleanup_claimed_at   timestamptz,
  cleanup_completed_at timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint founding_place_number_range check (place_number between 1 and 500),
  -- Coherence is expressed ONLY against claimed_at, and only in the direction that
  -- survives anonymisation: an UNCLAIMED row carries nothing, a CLAIMED row may have
  -- had its attributes erased. The earlier biconditional form ("(claimed_at is null)
  -- = (app_transaction_id is null)") is WITHDRAWN -- it made the anonymised shape
  -- unrepresentable, which is how the recycling defect would have surfaced as a
  -- constraint violation at deletion time instead of being designed for.
  constraint founding_place_unclaimed_is_empty
    check (claimed_at is not null
           or (user_id is null and app_transaction_id is null
               and expires_at is null and source_environment is null
               and cleanup_claimed_at is null and cleanup_completed_at is null)),
  constraint founding_place_env check (source_environment is null
                                    or source_environment = 'Production'),
  constraint founding_place_expiry check (expires_at is null or expires_at > claimed_at)
);
```

Pre-seeded with 500 rows, all unclaimed (`claimed_at is null`). RLS on, **zero
privilege for `anon`, `authenticated` and `service_role`**, matching U3's rule that
every membership table is client-unreachable and every read goes through a
`SECURITY DEFINER` helper.

**`claimed_at` IS THE SPENT DISCRIMINATOR AND `user_id` IS NOT.** This is the
correction that makes `ON DELETE SET NULL` safe. With `user_id` as the test, a
Founder deleting their account would set it NULL and their place would be **recycled
into the pool** — silently issuing 501 grants against a 500-place promise. `claimed_at`
is written once at claim and is **never cleared by anything**: not by deletion, not by
cleanup, not by Group B2's anonymisation. Every "is this place available" test in the
design reads `claimed_at is null`, and `user_id is null` only ever means "no live
identity attached".

**Group B1 must therefore anonymise, not blank.** Erasing every field would return the
row to the *unclaimed shape* and reintroduce the same defect through the other door.
The permitted erasure is `app_transaction_id`, `source_environment` and `expires_at`;
`claimed_at` and `place_number` stay. The constraint above is written to allow exactly
that shape — a claimed row with nothing else — and to forbid an unclaimed row carrying
anything, which is the direction that actually needs enforcing.

**Why a pool rather than a counter — narrowed after Codex R1.** "How many places
exist" is data rather than a constant inside a function, "is the offer open" is an
ordinary `EXISTS`, and a spent place can stay spent without carrying any identifier
(Group B1). Those remain good reasons.

**What is no longer a reason:** I argued the pool also made allocation lock-free via
`FOR UPDATE SKIP LOCKED`, and disparaged "counting under a lock" as the thing this
project keeps getting wrong. **Both halves were wrong.** `SKIP LOCKED` produced the
contention-reported-as-exhaustion defect (§3.2), and at 500 lifetime claims a
serialised allocation is free — Codex is right that counting under a lock is not
generally incorrect. The pool survives on its remaining merits; allocation is now
serialised regardless, so the two choices are independent.

**Why one table rather than a `membership_grant` + `founding_place` pair.** The
handover's closing line — *"a launchable, maintainable offer, not a new general
promotions platform"* — argues against a generalised grant concept. If a second grant
kind is ever wanted, that is a reviewed migration, not a config value.

**`ON DELETE SET NULL`, not CASCADE, and this is a product decision — see Group B (§7).** It
means a deleted account's place is *spent, not returned*, and `app_transaction_id`
survives deletion. Both consequences are deliberate and both need Samuel's sign-off.

### 3.2 Allocation

**REWRITTEN AFTER CODEX R1. The first version had a real defect and this records it
rather than quietly replacing it.** I proposed claiming with `FOR UPDATE SKIP LOCKED`
and returning `pool_exhausted` on zero rows. `SKIP LOCKED` skips a row that is merely
**locked**, so a concurrent transaction holding the last place and later **rolling
back** would have made a rightful claimant see `pool_exhausted` and be sent to
payment while a place still existed. Contention was being reported as exhaustion.
A second defect sat beside it: two concurrent first attempts by the same identity
resolved by a `UNIQUE` violation and a rollback, so the loser received an **error**
where it should have received the winner's grant.

I also overstated the case against counting. With 500 lifetime claims, serialising
allocation costs nothing, and Codex is right that "counting under a lock is wrong" is
not a general truth.

**The corrected allocation.** `founding_claim_v1(p_user_id uuid, p_app_transaction_id
text, p_environment text) -> jsonb`, `SECURITY DEFINER`, granted to `service_role`
only, all inside one transaction:

0. **`pg_advisory_xact_lock` on one constant key.** Allocation is serialised
   project-wide. At 500 lifetime claims this is free, and it is what makes step 3's
   answer *durable* rather than *momentary*.
1. **Existing grant → idempotent SUCCESS.** `where user_id = p_user_id` → return
   `already_granted` with the original `place_number`, `claimed_at` and `expires_at`,
   unchanged. A lost response, a retry, and a second device all land here.
2. **Apple-account check.** `where app_transaction_id = p_app_transaction_id` held by
   a different identity → refuse (`already_claimed_by_other_identity`). Subject to
   Group B (§7).
3. **Allocate.** `select min(place_number) where claimed_at is null` — **never
   `where user_id is null`**, which is the recycling defect above. Because step 0
   serialises, "none" now means **durably exhausted**: no other allocator can be
   holding an uncommitted place.
4. **Claim and return.**

**`pool_exhausted` is only ever returned from step 3 under the lock.** Contention has
its own outcome: if the lock cannot be taken within a short `statement_timeout`, the
RPC returns **`busy`**, which the client retries and which never routes anyone to
payment. **Reporting contention as exhaustion is the specific defect this design is
now built to make unrepresentable**, and it is acceptance test 1.

**`auth.uid()` is NOT the caller here — Codex's catch, and it would have been a live
bug.** This RPC is invoked by the Edge Function under `service_role`, where
`auth.uid()` is NULL. The identity must be passed in as `p_user_id`, taken from the
Edge Function's own verified `auth.getUser`, exactly as `membership_establish_v1`
takes `p_user_id`. The earlier draft wrote `where user_id = v_uid`, implying
`auth.uid()`; that would have matched nothing and allocated against NULL.

The `user_id` and `app_transaction_id` UNIQUE constraints stay as **backstops**, not
as the mechanism. Under the advisory lock they should never fire; if one ever does,
the serialisation has been broken and stopping is correct.

**What starts the twelve months.** `claimed_at = now()`, server clock, UTC.
`expires_at = claimed_at + interval '12 months'`. Postgres calendar semantics: a claim
on 29 February expires on 28 February. Device time is never used.

**Allocation closing mid-flow.** The pre-flow eligibility probe (§3.5) is **advisory
only**; the claim is the decision. `pool_exhausted` routes the member to the ordinary
paywall having been promised nothing and charged nothing, so the introduction copy
must describe a limited offer subject to availability, never "you have a place".
Inverting that ordering — treating the probe as the allocation — remains the defect to
watch for in review.

### 3.3 The predicates

Both replacements are function bodies only; no policy changes at all.

```sql
-- connected_member(uuid): the existing Apple arm UNCHANGED, plus a second source.
select coalesce((select bool_or(<<existing Apple row expression, verbatim>>)
                   from public.membership m where m.user_id = target_user_id), false)
    or coalesce((select bool_or(/* [revoked_at is null and] -- optional, see below */
                       g.expires_at > now())
                   from public.founding_place g where g.user_id = target_user_id), false);
```

```sql
-- membership_entitled_until(uuid): greatest ignores NULLs unless all are NULL.
select greatest(
  (select max(<<existing Apple case expression, verbatim>>) from public.membership m
    where m.user_id = target_user_id and m.environment in ('Production','Sandbox')),
  (select max(g.expires_at)   -- [revocation variant below, if D7 is taken]
     from public.founding_place g where g.user_id = target_user_id and g.claimed_at is not null));
```

**Why this is not the bypass FM-1 forbids, argued rather than asserted.** D4 rejected
the `membership_sandbox_tester` allowlist because it put a *shippable exception* inside
the predicate whose safety rested on operational discipline. This is a different shape:
a second **row-derived, individually-dated, enumerable** source, OR'd with the first,
with no allowlist, no flag, no identity named in code, and an expiry the database
enforces. It is the same expression shape as the Apple arm. If Codex judges otherwise,
that judgement should land before anything is built — this is the load-bearing
architectural claim of the whole proposal.

**The grandfather hazard does not return.** U6b-4 removed the middle `coalesce` arm
whose NULL-means-fall-through behaviour created D4's inversion. Both terms here are
`coalesce(..., false)`, so the expression is strictly two-valued and there is no
fall-through to inherit.

**REVOCATION IS ILLUSTRATIVE AND OPTIONAL, NOT NORMATIVE — corrected for
consistency with §7.** §7 omits grant revocation by default as optional new scope, and
the first revision left `revoked_at` in the table, in both predicates, in the §4
combination table and in the §5.2 selector as though it were settled. **It is not part
of the proposed baseline.** The `revoked_at` column has been removed from §3.1's table
accordingly, and the bracketed terms above are shown only so the shape is visible if
Samuel asks for it; **the baseline design has no revocation column and no revocation
term in either predicate**, and a grant ends only by reaching its own `expires_at`.

**If revocation IS taken**, it carries more than a column: the terms above become
`g.revoked_at is null and g.expires_at > now()` and
`max(case when g.revoked_at is not null then g.revoked_at else g.expires_at end)`,
the §5.2 selector becomes `coalesce(g.revoked_at, g.expires_at)`, and client
invalidation and support semantics come into scope with it. Treated that way it would
mirror B-39 exactly: it never entitles, and `entitled_until` becomes the revocation
instant rather than
NULL — which is what makes the quarantine in §5.3 measure from the right moment.

**Propagation.** One new trigger on `founding_place` (AFTER INSERT OR UPDATE OR
DELETE) recomputing the denormalised columns for `old.user_id` and `new.user_id`
when they differ. Reusing `tg_membership_propagate_entitled_until` unmodified is
tempting and **wrong**: on a row whose `user_id` goes to NULL it would recompute for
NULL and update nothing, leaving the departed identity's columns stale. A six-line
dedicated function is the honest version.

**Expiry needs no job.** `expires_at > now()` in the predicate and `entitled_until >
now()` in the policies are both clock comparisons. Access ends at the right instant
with nothing scheduled. This falls out of a denormalised design built for Apple dates
and is, as far as I can tell, free.

### 3.4 Activation — proving "production account" without trusting the client

**The problem, restated.** A Founder makes no purchase, so there is no
`originalTransactionId`, no `environment` on a transaction, and nothing that
distinguishes an App Store install from TestFlight — *unless* something Apple-signed
says so.

**`AppTransaction` is that artefact, and it was built for exactly this.** Apple
documents `appTransactionID` as *"a single, globally unique `appTransactionID` for
each Apple Account that downloads your app"*, which *"remains the same for the same
Apple Account and app if the customer redownloads the app on any device, receives a
refund, repurchases the app, or changes the storefront"*, and which *"is available
even if a customer makes no Apple In-App Purchases."* The signed payload
(`JWSAppTransactionDecodedPayload`) carries `bundleId`, `appTransactionId` and
`receiptType` — the latter being *"the server environment, production or sandbox,
that signed the app transaction"*.

So one artefact answers three of the handover's questions at once:

| Question | Answered by |
|---|---|
| "production accounts only", without a trusted client flag | `receiptType` = Production, Apple-signed |
| "unaffected by reinstall or device change" | `appTransactionID` is stable per Apple Account |
| a key that could outlive a deleted Supabase account | `appTransactionID`, **if retained — Group B (§7)** |

**Server surface.** A new Edge Function `founding_claim_v1`, modelled exactly on
`membership_attest_v1`: `verify_jwt = false` plus its own `auth.getUser` (identity
from the verified session, never the body), a body carrying exactly one field (the
compact JWS), `verifyAppleJWS` against the already-pinned Apple Root CA G3, then
claim checks in a new `_shared/appstore/apptransaction.ts` mirroring `attest.ts`:

- `bundleId === APPLE_IAP_BUNDLE_ID`;
- `receiptType` **pinned to `Production` in code**, not in a secret. My first draft
  proposed a new `APPLE_FOUNDING_ALLOWED_ENVIRONMENTS`; **Codex R7 is right that this
  would be an environment-switch secret introduced for testing**, and `attest.ts`'s
  own reasoning applies against it — an environment variable is a *widening
  mechanism*, and widening who may take a Founding place should require a code change
  and a review, not a secret edit. Withdrawn. (The separate U5a rule against reusing
  `APPLE_ATTEST_ALLOWED_ENVIRONMENTS` or `APPLE_ASSN_ALLOWED_ENVIRONMENTS` still
  holds and is satisfied trivially by not having one.)
- then one RPC call to `founding_claim_v1(...)`.

**What the artefact does and does not say — corrected after Codex R7.**

A TestFlight install reports `receiptType` sandbox and is refused, which delivers
"beta QA never consumes a public place". **But it does not permanently exclude a
person who beta-tested:** the app transaction describes an Apple Account's *download*,
so the same person later installing the public App Store build supplies Production
evidence and qualifies like anyone else. My first draft conflated those two and filed
the conflation as a product decision; it is not one. See Group A (§7).

**I also over-claimed about Xcode.** I wrote that an Xcode run "produces a
locally-signed app transaction that cannot pass the pinned Apple anchor, so the
Founder path cannot be exercised from Xcode at all". **That categorical statement is
not established by anything I read** and is withdrawn as stated. What is supported is
weaker and still useful: a StoreKit-testing configuration signs locally, and anything
not signed by the pinned Apple Root CA G3 is refused by `verifyAppleJWS`. Whether
every Xcode-run configuration produces such an artefact is **unverified** and belongs
in unit F1.

**And the evidence is historical, not live.** `AppTransaction` records how this Apple
Account obtained the app. It is **not** proof of which binary is running now, and it
is not proof that the App Store account and the SIWA account are the same person (see
immediately below). It is the right evidence for "did this copy come from the
production App Store", and it must not be promoted into anything stronger.

**IT IS DISTRIBUTION EVIDENCE, NOT IDENTITY PROOF — Codex's R2, and it is right.**
`appTransactionID` names the **Apple Account signed into the App Store on that
device**. The Études identity comes from **Sign in with Apple**. Nothing requires
those to be the same person, and no Apple surface will tell us whether they are. Two
consequences, both bounded rather than eliminated:

- **Cross-account replay.** The JWS is a bearer artefact, exactly as U5's transaction
  JWS is (F3b/P2: valid for the life of the artefact, never logged, never persisted,
  never echoed — the same handling rules apply here and are not optional). Someone
  presenting another Apple Account's app transaction can claim a place. The bound is
  §3.2 step 2: **one place per `app_transaction_id`, ever**, so replay converts one
  Apple Account into at most one place — which is what it was worth anyway.
- **The dedupe key is an Apple Account, not a person.** Somebody with N Apple
  Accounts can take N places, and no available artefact changes that. The real
  bound is the pool: 500, finite, and each place worth twelve months of a £4.99
  subscription. **The honest claim is "one place per Apple Account", and the copy
  and any terms must say that rather than "one per person".**

This is the correct evidence for the question it is being asked — *was this app
obtained from the production App Store* — and it must not be quietly promoted into
an answer to *who is this*. Stating the boundary is the point; a later reader who
assumes the stronger claim is the failure mode.

**NOT ESTABLISHED.** Whether `AppTransaction.shared` resolves without a network
round trip on a fresh install that has never transacted, and what
`AppTransaction.refresh()` prompts for when it does not. Apple documents `shared` as
returning *cached* information and `refresh()` as going to the server. If `shared`
can fail on exactly the device state a first-time Founder is in, the claim flow needs
a refresh path and possibly an App Store authentication prompt. **This is the single
device fact I would want measured before implementation**, because it sits on the
activation path.

### 3.5 Client — rewritten after Codex R3

**A cached date is necessary and nowhere near sufficient, and my first draft implied
it was.** I wrote "cache the expiry date, never a boolean" as though that settled
offline and expiry behaviour. It does not: **nothing wakes SwiftUI at a date**, a
device clock is not trustworthy, and a cached date cannot know about server-side
revocation. Every one of Codex's five sub-points lands.

**1. The combined resolver must reach every activation path, and the literals are the
hazard.** `applyActivation(auth:isEntitled:)` has six production call sites, and two
of them pass **literals** — `MOTIVOApp.swift:481` passes `true` and `:495` passes
`false` from `handleMembershipState`. A Founder's StoreKit state is *always*
`.notEntitled`, so `:495` would knock them into Solo on every entitlement resolution,
however correct `ProductionAppModeActivation.resolve` was made.

This is the failure shape this project has already paid for three times — U2b's
`shouldPublish: true`, `AuthManager:618`'s `lookupEnabled: true`, and the
`DirectoryAvatarCircle` call site that silently passed no `version:` for eleven days.
So the fix must be **structural, not careful**: replace the `isEntitled: Bool`
parameter with a `ConnectedAccess` value carrying both terms, so that **the literal
call sites do not compile**. C-34's precedent is exact — the parameter was made a
non-optional `let` specifically so omission became a compile error, and dropping a
default from an `Optional var` would not have achieved it.

**2. Expiry while the app is open needs an event.** Schedule a one-shot task to the
grant's `expires_at` (and re-arm on foreground), which recomputes access on fire.
Without it a Founder whose year ends mid-session keeps a Connected UI until something
else happens to re-resolve.

**3. The cache is reversible UI evidence and is scoped and guarded as such.**
Identity-scoped (keyed to the backend user id, never global); cleared on sign-out and
on account deletion; invalidated on a `revoked` or absent server status; and late
responses suppressed by the same owner + generation discipline
`MembershipAttestationCoordinator` already uses, so a status reply arriving after an
identity change cannot publish under the new identity. **The server remains the
authority on every request** — the cache only ever decides UI, reversibly.

**4. What offline staleness actually means, stated honestly.** Offline, a cached
`expires_at` bounds *over*-entitlement by the date, subject to device clock accuracy —
so it is a bound, not a guarantee, and I should not have implied otherwise. It cannot
reflect a revocation issued while offline. The residual is a Connected UI whose
requests are refused the moment the device reconnects, which is the same worst case
U5f already accepts, and it is **not** a claim that the client is correct offline.

**5. F3 publication — two producers, and their sequences must not collide.**
A Founder never attests, so `DirectoryReconciliationPolicy.shouldReconcile`'s
`completion.establishesMembership` guard is never satisfied and **a Founder's
directory row would not publish on a fresh join** — the defect `b479487` has just
fixed for purchasers, re-entering through a new door.

The fix is a source-agnostic `ActivationCompletion` with the same
`sequence / owner / directoryGeneration / establishesMembership` shape, published by
either attestation or a successful claim, leaving `shouldReconcile` and the evaluator
unchanged. **Codex's addition is the part I had missed:** `sequence` is today a
per-coordinator counter, so two independent producers would collide and one
producer's completion could be mistaken for the other's already-consumed one. The
sequence must come from a **single shared monotonic source**, and the owner and
directory-generation checks stay exactly as they are. Do not fabricate an Apple
attestation to reuse the existing producer.

**6. Restore recovers, it never allocates.** `MembershipSelectionView:387` currently
treats "no StoreKit entitlement" as "no active membership" and says so. For a Founder
that sentence is false. Restore must consult grant status and **report** an existing
grant; it must never reach `founding_claim_v1`. Allocation happens once, on the join
path, and nowhere else.

**Server surface for the client**, both zero-argument, identity from `auth.uid()`,
granted to `authenticated` only — the narrowest shape the design admits and the same
shape U5b settled for `ensure_membership_binding()`:

- `founding_status_v1()` → `(has_grant, expires_at, place_number)` for the caller only;
- `founding_offer_open_v1()` → boolean, advisory (§3.2).

`founding_offer_open_v1` leaks one bit — whether the pool has emptied — which becomes
public information the moment the messaging changes, and it satisfies "no countdowns,
no places-remaining" by returning a boolean rather than a count.

**A `FoundingGrantCoordinator`** mirroring `MembershipAttestationCoordinator`:
single-flight, short cooldown, **in memory only** (persisted suppression would make
the client authoritative over server state), invariant `hasConnectedIdentity ∧
BackendConfig.isConfigured` — deliberately **without** a local-entitlement term,
because a Founder never has one. Triggers: launch, foreground, identity arriving,
claim, sign-in, and the scheduled expiry event from point 2.

## 4. Effective access — the combination table

| Situation | `connected_member` | `entitled_until` | Client mode |
|---|---|---|---|
| Live grant, no Apple subscription | true (grant arm) | grant `expires_at` | Connected, via the grant term |
| Live grant + live paid subscription | true (both) | max of the two | Connected |
| Live grant + lapsed/refunded Apple row | true (grant) | grant `expires_at` | Connected |
| Expired grant, no subscription | false | past grant expiry | Solo |
| Expired grant + live paid subscription | true (Apple) | Apple renewal | Connected |
| Revoked grant, no subscription *(only if D7 is taken — not in the baseline)* | false | revocation instant | Solo |
| Grant claimed on device A, signed in on device B | true | — | Connected after one `founding_status_v1` |
| Signed out | n/a | n/a | Solo (`hasConnectedIdentity` false) |
| Offline, cached grant still in date | server unreachable | — | Connected; requests succeed when reachable |
| Offline, cached grant past its date | — | — | Solo, with no network needed |

**Apple provenance is untouched in every row.** No Founder ever causes a write to
`public.membership`, `binding_method` is never invented, and `membership_establish_v1`
is not modified. A Founder who later subscribes goes through the ordinary bound
purchase and gets a genuine `binding_method = 'purchase'` row beside their grant.

---

## 5. Expiry, quarantine and cleanup

This is the part the pricing note called *"not yet satisfied"* and it is where I
propose the least new machinery and the most care.

### 5.1 What the date alone gives, and what it does not

**Server-side, this is free.** Loss of the actor gate and loss of subject visibility
are both clock comparisons against `expires_at`: `connected_member` stops returning
true and every `*_entitled_until > now()` test stops passing, with no job, no
notification and no code beyond §3.3.

**Client-side it is NOT free, and my earlier "needs no code beyond §3.3" was wrong on
both sides of the boundary.** It is corrected here rather than left to contradict
§3.5: nothing wakes SwiftUI at a date, so a Founder whose year ends mid-session keeps
a Connected UI until something else re-resolves. §3.5.2's scheduled expiry event, the
foreground recompute and the combined resolver are all required. The client's access
term is UI only and reversible; the server is unaffected by any of it.

### 5.2 Scheduling: do not write a `pending_cleanup_at` for grants

The handover is explicit that *"merely writing `pending_cleanup_at` is not sufficient
and must never authorise deletion."* The cleanest response is not to write one at all.
A grant-only identity's due-ness is **computed**, never stored:

```sql
-- added as a UNION branch inside membership_cleanup_eligible_v1
select g.user_id
  from public.founding_place g
 where g.claimed_at is not null
   and g.cleanup_completed_at is null
   and g.expires_at + interval '60 days' <= now()   -- coalesce(g.revoked_at, …) only if D7 is taken
   and (g.cleanup_claimed_at is null
        or g.cleanup_claimed_at < now() - public.membership_cleanup_lease_v1())
```

**A WEAKER CLAIM THAN I FIRST MADE, AND THE STRONGER ONE IS WITHDRAWN.** I wrote that
*"there is no timestamp an operator can hand-write to make a grant due"*. That is
false: `expires_at` is stored, and an operator with write access can move it into the
past and make a grant candidate due. What is true, and all that is claimed now, is
narrower — **no *separate scheduling* timestamp exists** whose only function is to
select for deletion, so there is no `pending_cleanup_at` analogue to hand-advance, and
one field carries both the member's real expiry and the selection input.

**The protection is unchanged and is where it always was: in the authority checks, not
in the absence of a writable field.** A hand-advanced `expires_at` still has to pass
`membership_cleanup_authorised_v1` — `connected_member` false, a schedule due, and
§5.3's fail-closed quarantine conjunct — after a live Apple read applied through the
canonical writer. That is exactly what the 2026-09-03 demonstration measured: a
hand-advanced schedule **REFUSED**, and reconciliation overwrote the artificial value.
**Selection is not authority**, for grants exactly as for Apple rows, and I should not
have dressed a design convenience as an additional safety property.

**Two structural consequences that must be named rather than glossed:**

1. `membership_cleanup_eligible_v1` and `membership_due_for_cleanup_v1` currently
   return `(user_id, environment, original_transaction_id)`, all non-null, and the
   worker builds `byUser` from those rows. A grant-only identity has no such row, so
   the return type must admit nullable `environment` / `original_transaction_id`.
   **That is a visible structural delta on two functions the destructive worker
   depends on**, and it must appear in the B-23 prediction.
2. The lease lives on `public.membership.cleanup_claimed_at`. A grant-only identity
   needs its own, hence `cleanup_claimed_at` / `cleanup_completed_at` on
   `founding_place`. Same design, same lease interval, same completion-last ordering.

### 5.3 Authority: one additive conjunct, and it must fail CLOSED

**Codex's hazard, restated so it is not lost.** A Founder who once had an Apple
subscription that lapsed long ago carries a `pending_cleanup_at` computed from *that*
lapse. If a grant then covers them for twelve months, the stored Apple schedule can be
months past due the instant the grant ends — and the existing authority gate would say
*"not entitled and a schedule is due"* immediately, with **no quarantine at all**.
That is U7b's born-lapsed hazard arriving through a door U7b could not have known about.

The fix is one conjunct in `membership_cleanup_authorised_v1`:

```sql
v_quarantine_elapsed :=
  coalesce(public.membership_entitled_until(p_user_id) + interval '60 days' <= now(), false);
...
'authorised', (not v_member) and v_due and v_quarantine_elapsed
```

**`false`, NOT `true` — corrected after Codex R2, and my first draft had this
backwards.** I wrote `coalesce(..., true)`, reasoning that NULL never arises for a
candidate because a candidate always has a membership row. That reasoning fails in
two places at once. A **grant candidate with missing end evidence** yields NULL and
would have been authorised; and an Apple row whose dates Apple omitted — B-25's exact
scenario, *"every renewal-info field is optional"* — also yields NULL. `false` means
**missing end evidence refuses cleanup**, which is the only defensible direction for
an irreversible path, and it is strictly safer than today's behaviour rather than a
regression of it.

**The conjunct is purely additive and monotone in the safe direction.** It can only
ever refuse a cleanup the current code would allow, never permit one it would refuse,
so it cannot regress the Apple path. For an ordinary Apple-only lapse it is equivalent
to the existing condition. For U7b's floored born-lapsed row it says "elapsed" while
`pending_cleanup_at` says "not yet", and the AND still refuses — U7b's protection
survives intact.

It also reuses the function that already defines subject visibility, so *"when did
access actually end"* has exactly one definition for both purposes.

### 5.3a Mixed-source leasing and completion — Codex R2

An identity holding **both** a membership row and a grant row has **two** lease sites,
`membership.cleanup_claimed_at` and `founding_place.cleanup_claimed_at`. Left as two,
two workers could each claim one source and hand the same identity to both — and the
destructive sequence is identity-scoped, so they would be deleting the same content
concurrently.

**The lease must be identity-scoped, not source-scoped.** Concretely:

- eligibility **excludes** an identity if *either* source carries a live lease;
- the claiming statement stamps **every** source row for that identity, in one
  statement, or stamps none;
- completion (`membership_cleanup_complete_v1` and its grant equivalent) clears and
  marks **every** source row for that identity, and stays last.

This is a change to the shape of the existing claim statement, not only an addition
beside it, and it belongs in the separately reviewed cleanup unit (§9).

### 5.4 The live Apple read — support established, safety NOT established

**What is settled.** Apple's reference for *Get All Subscription Statuses* states the
path parameter accepts *"Any `originalTransactionId`, `transactionId` or
`appTransactionId` that belongs to the customer for your app."* Codex raised it; I
verified it against Apple directly rather than adopting it. So the worker **can**
address a live Apple read for a grant-only identity using the `app_transaction_id`
stored on the grant row, and **D5 is withdrawn as a product decision** — there is no
fork for Samuel here.

**What is NOT settled, and Codex R2 is right that I let the first result carry more
weight than it can.** API support establishes that a call can be *made*. It does not
establish that the design is safe. Four things remain open, and **the cleanup protocol
must be reviewed separately, on its own evidence, before any executable cleanup change
ships**:

1. **The no-subscription response contract.** Apple does not document what is returned
   for a customer with the app and no subscription. **Never treat a 404, or a 200 we
   cannot parse, as proof of absence.** Only a well-formed, parseable Apple answer
   that positively reports no live Connected subscription may count as authority
   obtained; everything else aborts. Until measured, every non-affirmative answer
   aborts — which is what the worker already does with unexpected Apple responses, so
   **the unknown can defer a cleanup and cannot cause a wrong one.**
2. **Account association and coverage.** The `appTransactionId` names an Apple Account
   (§3.4). If the member's App Store account has changed since the claim, the stored
   identifier may no longer cover the subscription that matters. What that read
   actually proves about *this Études identity's* current entitlement is an open
   question, not an assumption.
3. **Pending purchase or pending attestation must VETO, and must not make U7 a
   writer.** If the read shows an active or ambiguous Connected subscription that has
   no established membership row, the worker **refuses and stops**. It must not
   establish the row: `membership_establish_v1` is the only establisher, ownership
   provenance is derived and not inferred, and U4's ingestion path was deliberately
   made UPDATE-ONLY for exactly this reason. **A second establishment writer inside
   the destructive worker would be the worst possible place to put one.**
4. **The race between the authority check and the later storage deletion** — §5.5.

**So the honest summary is: identifier support removes the need to bend the standing
rule; it does not by itself make grant-only cleanup safe.** The cleanup unit stays
gated behind a bounded protocol review whose scope is exactly the four items above.

**DISABLED IS AN INTERIM STATE, NOT A FULFILLED REQUIREMENT — corrected, and I
overstepped here.** I wrote that *"shipping with it disabled is an acceptable
outcome"*. That was me accepting a departure from FM-2 on Samuel's behalf, which is
not mine to do. FM-2 requires an expiring Founder to follow the ordinary lapse policy
including eventual cleanup, and **a permanent exemption for grant-only Founders
remains rejected.**

Shipping disabled is **safe** — it retains Connected content and destroys nothing —
and safety is not the same as fulfilment. So if activation is ever released with
grant-only cleanup disabled, that is a **staged-activation release exception** which
requires, together and not severally:

- **Samuel's explicit sign-off** on that specific exception;
- a **named owner and a dated completion gate**, falling **before the earliest
  natural Founder maturity** — twelve months plus sixty days from the first claim —
  so the gap closes before any Founder could have needed it rather than after;
- **grant-aware vetoes on every cleanup path meanwhile**, not only the grant-only one:
  the §5.3 conjunct and the `connected_member` grant arm must be live on the *Apple*
  path too, so that a live grant vetoes destruction wherever destruction can be
  reached. Disabling grant-only *selection* must never leave a grant-blind *authority*.

**None of that is recorded as agreed here.** It is the shape the exception would have
to take if Samuel chooses it.

**Two mitigations remain true whatever that review finds**, and neither is sufficient
alone: the sixty-day window is one in which a single app launch on any device holding
the entitlement heals the state through U5f's unattended attestation; and the grant
holder has been denied by enforcement for the whole of it, which is the condition most
likely to prompt that launch.

### 5.5 A purchase that races the worker — Codex R5, and it is not G7's

**No Apple row is not proof of no purchase.** A successful purchase creates no
`membership` row until the client attests, and U4's ingestion cannot create one
either. §5.4 covers the *static* case: Apple itself is asked. It does not cover the
*dynamic* one — the worker authorises at T0, then spends the rest of its storage
budget deleting objects and rows, and a purchase at T0+5s destroys a paying member's
content anyway.

**This hazard predates Founding 500**, which Codex and I agree on: the same race
exists today for an Apple-only identity whose owner resubscribes seconds after
authorisation. What this feature changes is its **likelihood**, in the worst
direction — a Founder's most probable moment to subscribe is exactly when their access
ends and the app begins refusing them.

- **In scope for the cleanup unit, additional DETECTION — not a smaller window.**
  Re-evaluate the authority gate immediately before the destructive phase, and abort
  if the identity has acquired any `membership` row or live grant since selection.
  **I previously described this as shrinking the window to "last check → first
  irreversible delete". That is wrong and is withdrawn.** A check before the *first*
  delete does nothing for the second and every subsequent one: the destructive
  sequence removes storage objects and rows over multiple seconds, and a purchase
  landing at any point after that check is still unprotected. The window is narrowed
  only at its front; **its tail is untouched**, and the residual is the whole of the
  deletion sequence.
- Interleaving the check between delete steps would raise detection probability and
  still not close it, because each check protects only what follows it, and by then
  earlier objects are already gone irreversibly.
- **It is NOT closed, and a short SQL lock cannot close it**, because the storage
  deletion sequence is multi-second and partly non-transactional. The full fix means
  making establishment and cleanup mutually exclusive across that sequence.

**I withdraw my earlier suggestion that G7 is where this lands.** That would have
loaded a newly expanded guarantee onto an obligation whose scope is fixed and whose
only remaining precondition is elapsed time. **G7's scope is unchanged by this
document.** The race is a **bounded U7 obligation in its own right**, owned by the
cleanup protocol review in §5.4, and it must be dispositioned there — either narrowed
and accepted with the residual stated, or closed — before any executable grant-aware
cleanup change ships. Naming it as a separate obligation is the point; quietly
attaching it to an existing one is how obligations become ownerless.

### 5.6 The converse direction, checked — Codex R4 (first pass)

The earlier review pass asked for both directions: an old Apple schedule must not become destructive the
instant a grant ends, **and** an expired grant must not shorten the quarantine after
later paid access ends. The §5.3 conjunct handles both because
`membership_entitled_until` is a **max over sources**, not a preference between them.
Grant expires at T, paid access ends at T+200d → the conjunct measures from T+200d and
refuses until T+260d. Grant expires at T, no later access → refuses until T+60d. One
expression, both directions, no ordering assumption.

### 5.7 Retention matrix addition

`founding_place` joins `membership` and `membership_binding` as **retained on
ordinary expiry cleanup** and removed on explicit account deletion — except that
§3.1 proposes `ON DELETE SET NULL` rather than CASCADE, which is **Group B** (§7).
Retaining
the row is not tidiness: `membership_entitled_until` reads it, so deleting it on
cleanup would make the §5.3 conjunct return NULL and re-open the very window it closes.

---

## 6. What StoreKit can and cannot enforce

**The requirement.** Founders converting after twelve months get **no additional
introductory trial**; members from #501 get a **one-month StoreKit trial**.

**My first reading was that this was impossible, and Codex corrected it.** Apple
documents `Product.PurchaseOption.introductoryOfferEligibility(compactJWS:)` and a
signed payload carrying:

| Claim | Value |
|---|---|
| `productId` | the product being purchased |
| `allowIntroductoryOffer` | *"A Boolean value, `true` or `false`, that determines whether the customer is eligible for an introductory offer"* |
| `transactionId` | *"You can use the customer's `appTransactionID`, **even for customers who haven't made any Apple In-App Purchases in your app**"* |

plus `iss`, `iat`, `aud: "introductory-offer-eligibility"`, `bid`, `nonce`. Signed
with the In-App Purchase key — the same key `credentialsFromEnv` already loads.

**So the requirement is enforceable on the purchase path we control, and only there.**
Precisely:

- **Enforceable:** a purchase initiated inside Études through `MembershipSelectionView`.
  We attach the option with `allowIntroductoryOffer: false` for any buyer who holds
  or has ever held a Founding place.
- **NOT enforceable:** subscriptions started outside the app — the App Store product
  page, Settings → Subscriptions, an offer-code redemption. Those are Apple's flows,
  carry no purchase option from us, and Apple's own eligibility rule applies: *"new
  and returning customers are only eligible to use one introductory offer per
  subscription group"*, and a Founder who never bought through Apple is a new customer.
  **Do not promise otherwise in terms or copy.**
- Promotional offers and win-back offers do **not** close that gap: Apple scopes them
  to *"existing and previously subscribed customers"*, and a Founder is neither.

**Design consequences — point 2 rewritten after Codex R5.**

1. A new Edge Function `founding_intro_eligibility_v1` signs a short-lived JWS per
   `(identity, productId)` with the In-App Purchase key, the feature-specific
   `aud: "introductory-offer-eligibility"`, a fresh `nonce` and `iat`. It is not the
   existing API bearer token and must not be confused with it.

2. **If the signed option cannot be prepared, STOP BEFORE PAYMENT. Do not purchase
   unsuppressed.** My first draft said the opposite — purchase anyway, unsuppressed,
   and record it — reasoning that blocking would mean refusing a member's money to
   avoid giving them a discount. **Codex is right that this was not my decision to
   make.** Samuel's requirement is that Founders receive no additional introductory
   trial; silently failing open is a *product change*, not an engineering fallback,
   and I had dressed one as the other. The default is now fail-closed: a calm,
   retryable message, nothing charged, and the member tries again — which is exactly
   the shape `purchaseReadiness` already uses for the binding token, so the two rules
   are now consistent rather than deliberately opposed. **If Samuel prefers fail-open
   discounting, that is Group C (§7) and he says so explicitly.**

3. **Freshness and account changes.** A signature fetched when the paywall appears can
   expire before the member taps, and the Apple Account can change in between. So the
   option is prepared (or refreshed) **immediately before the purchase call**, not
   only on appearance; a stale or unusable signature is handled by rule 2, not
   ignored. Keeping a round trip off the purchase path (C-13) argues for fetching on
   appearance *as well*, not instead.

4. The option is attached **only** for a buyer holding or having held a Founding
   place. Everyone else gets Apple's default eligibility, which is already what #501+
   should see. We never need `allowIntroductoryOffer: true`.

5. **Paid ownership binding stays mandatory and unchanged.** A Founder converting
   still purchases with `.appAccountToken`, still attests, and still gets a genuine
   `binding_method = 'purchase'` row. Nothing in §6 touches B-24.

6. **I withdraw the claim that App Store Connect has no introductory offer.** I
   inspected only the local `Etudes.storekit`, which shows `"introductoryOffers": []`
   — that is evidence about the local test configuration and **none at all** about
   ASC, which was not inspected. Whether the one-month offer exists, and on which
   products, is an **open item for the account holder**, configured per subscription
   product. Trial language must be shown only where an offer actually applies.

7. **Suppression is not demonstrated to consume Apple's lifetime intro eligibility.**
   An earlier draft implied that an early conversion would "consume the Founder's one
   suppressible slot". Nothing read here establishes that passing
   `allowIntroductoryOffer: false` spends Apple's per-group eligibility, and the claim
   is withdrawn.

8. **An external purchase must be honoured.** A subscription started from the App
   Store page or Settings carries no option from us and is a valid Connected
   subscription. What Apple actually does about a trial on that route is **an outcome
   to observe and record, not an assertion to test against** (§10).

## 7. Product decisions — three groups, not seven questions

**Consolidated after Codex R6, which was right that I had manufactured decisions.**
Five of my seven were not Samuel's to make: two were already settled by the pricing
note, two were routine design, one dissolved on evidence. Removed, with the reason
recorded so they are not silently reinstated:

| Withdrawn | Why |
|---|---|
| ~~D3 place number shown~~ | Routine design. Status plus exact expiry, no scarcity marketing, is already settled |
| ~~D6 pool size / seeding~~ | **Exactly 500 is settled.** Not a question |
| ~~D5 grant-only cleanup fork~~ | Dissolved on evidence (§5.4). It is an engineering gate, not a choice |
| ~~D7 grant revocation~~ | **Optional new scope. Omitted by default.** If Samuel wants it, client invalidation and support semantics come with it |
| ~~D1 as I framed it~~ | Conflated two different things — see Group A |

**And one I had omitted entirely, which Codex caught: existing paid subscribers.**

---

### Group A — Who qualifies

**A1. Beta testers.** Two questions I had collapsed into one, and only the second is
real. *Beta QA never consuming a public place* is a requirement, and the Apple-signed
`receiptType` delivers it automatically. *Permanently excluding people who
beta-tested* is a different proposition — and it does not follow, because the same
person installing the public App Store build later supplies Production evidence and
qualifies like anyone else. **No operator exception is required for that to work.**
*Recommendation: production evidence qualifies, whoever it belongs to; beta installs
never consume a place.* Samuel confirms or overrides.

**A2. Existing paying subscribers.** Omitted from my first draft. Someone already
paying for Connected when the offer opens: do they receive a Founding place?
*Recommendation: no retrospective grant.* If any benefit is intended for an
already-paying member, the rule must be explicit, and note that a grant running
beside a live paid subscription means paying and free access overlapping, with no
mechanism to pause Apple billing.

### Group B — What may survive account deletion, and for how long

Two things I had fused, which Codex separated correctly:

**B1. Never recycling a place.** A spent place can stay spent with **no retained
identifier at all** — the row keeps its number and non-null `claimed_at` spent
marker, while identifying attributes may be erased as defined in §3.1. It is never
returned to the pool. This needs no decision beyond confirming that deletion does
not replenish capacity. *Recommendation: it does not.*

**B2. Deduplication and offer eligibility after deletion.** Preventing
delete-and-reclaim, and keeping §6's suppression working for a returning Founder,
**both** require a retained pseudonymous identifier derived from the Apple Account.
`ON DELETE SET NULL` retaining `app_transaction_id` does it; an HMAC under a server
secret narrows it. **An HMAC is still a retained pseudonymous identifier and is not
automatically a legal resolution** — it changes the exposure, not the category.

*This is the one with a genuine legal component:* whether any identifier survives
deletion, which form, and for how long. It needs the retention and privacy-policy
position stated explicitly, not inferred. **B1 does not depend on B2**, so declining
B2 still leaves capacity protected — only repeat grants and post-deletion suppression
are lost.

### Group C — Conversion timing, and the scope of the no-extra-trial rule

**C1. When is conversion offered?** An early purchase **charges immediately under
Apple's terms**; it does not queue up behind the free year, and there is no mechanism
to make it. So offering conversion early means a member paying for months they
already have free. *Recommendation: offer conversion at expiry, not before.* If
Samuel wants it available earlier, the paid/free overlap must be stated plainly in
the copy.

**C2. What does "no additional introductory trial" mean, exactly?** It is
enforceable on the **in-app purchase route** and only there (§6). Purchases started
from the App Store page or Settings carry no option from us and cannot be suppressed.
*Recommendation: scope the promise to the in-app route, honour external purchases,
and never promise more in copy or terms than that.*

**C3. The fail-closed default (§6.2).** If the signed option cannot be prepared, the
purchase **stops before payment** and the member retries. *Recommendation: keep
fail-closed.* Samuel may prefer fail-open — a member is never blocked, some Founders
get an extra free month — **but that is a deliberate relaxation of his own
requirement and is his to make, not mine.**

---

## 8. External dependencies

### 8.1 Adult-only Connected — a SERVER prerequisite, not a screen order

**CORRECTED AFTER CODEX R4, AND THIS WAS THE WORST ERROR IN THE FIRST DRAFT.** I
wrote that the adult-eligibility dependency is *"satisfied by placement"*, because the
claim is the last step of a join sequence that already runs age assurance first. That
is wrong twice.

`founding_claim_v1` is a **directly callable authenticated endpoint**. Nothing
compels a caller to have seen the introduction screen, and a design whose safety
depends on which screen ran before it has no enforcement at all — it is precisely the
"safety resting on operational discipline" that D4 rejected. Worse, the rescope record
states plainly that the current access predicates **have no age term** and that the
band is **written by an `authenticated` RPC that accepts the value the client sends**.
So even a member who *did* pass through the screen has supplied a client value, not
settled server assurance.

**What replaces it.** The claim RPC consults a named server-side prerequisite —
`founding_eligibility_ok(p_user_id)` — which the adult-only work owns and defines.
Until that work lands, it returns **false**, so:

- **Founding allocation is closed at the server** until the adult-only contract
  exists, whatever the client does;
- the dependency is **structural and fail-closed**, not procedural;
- returning Founders need the equivalent **access** dependency, not only an
  establishment one, since a grant issued under one contract must not outlive it.

**The consequence Samuel needs to see plainly: Founding 500 cannot open to the public
before the adult-only determination is settled.** Its unresolved gates — which Apple
result is adequate for HEAA, what the server may trust, enforcement placement — are
listed in the rescope §5 and none is resolved by this document. **A Founder must never
be grandfathered past a future eligibility requirement**, and all existing 13–17
protections stay in force meanwhile.

### 8.2 Everything else

- **App Store Connect:** whether a one-month introductory offer exists, and on which
  products, is **unknown and uninspected** (§6.6); the App Store description's
  restrained mention of the offer and its removal once the pool empties. Pairs
  naturally with **C-31**.
- **Phase 3 carried obligations** — C-31, B-34, B-11 Gate 6 part 3 and **G7** — are
  untouched, and **none is closed, extended or re-scoped by this design**. G7's scope
  is unchanged (§5.5); it cannot be forced before natural maturity.
- **Sharing protocol** remains frozen and is not folded in.

---

## 9. Implementation units, if approved

**Adopting Codex's five-unit shape**, which is better than my eight: mine split work
that has to be reviewed together and implied a production test allowance that should
not exist.

| Unit | Content | Gate |
|---|---|---|
| **F1 — Evidence and interfaces.** No product code | (a) `AppTransaction.shared` behaviour on a first-install device; (b) the no-subscription response contract (§5.4.1); (c) the adult-eligibility interface (§8.1); (d) `introductoryOfferEligibility` availability and behaviour | **No live destructive experiment.** Outputs are measurements and one interface definition |
| **F2 — Ledger and claim** | `founding_place`, serialised allocation (§3.2), the two predicate replacements, propagation trigger, `founding_claim_v1` Edge Function and RPC | Allocation stays **closed** (§8.1, §9.1) |
| **F3 — Cleanup, separately reviewed** | Combined-source quarantine, fail-closed conjunct, mixed-source leasing, purchase races, recovery | **Behind the bounded protocol review of §5.4.** Shipping disabled is an **interim state needing Samuel's explicit exception**, an owned completion gate before first Founder maturity, and grant-aware vetoes on **all** cleanup paths (§5.4). **Not** a fulfilled FM-2 |
| **F4 — Client and conversion** | Combined resolver with the compile-enforced signature, expiry event, account-scoped status recovery, Founder status and exact expiry, F3 publication producer, signed trial suppression | |
| **F5 — Validation and launch config** | Isolated concurrency and lifecycle cases, real Apple/TestFlight behaviour per path, rollout and rollback, then **separately authorised** launch configuration and activation | **Beta QA must not consume public places** |

### 9.1 Rollout and rollback — Codex R7

- **Allocation stays closed** until the authority, cleanup and client prerequisites
  are ready. Opening it is a deliberate, separately authorised act.
- **Stopping new allocation and withdrawing existing grants are different switches**,
  and only the first is ever safe once a real award exists.
- **After a real award, restoring the old Apple-only predicate or a grant-blind
  cleanup worker is NOT a safe rollback.** It would revoke access that was promised,
  and a grant-blind worker would then be free to destroy a live Founder's content.
  Once F2 has issued one grant, F2's predicate and F3's worker are **forward-only**.
- **Unverified destructive behaviour ships disabled and fail-closed**, carrying a
  named release obligation. **A dry run proves blast radius and never proves deletion
  safety** — the worker's own contract says so.

### 9.2 QA consequences — no production test allowance

I withdraw my earlier suggestion of *"a reviewed, time-boxed environment allowance for
one verification run"*. Codex R7 is right: that is a production environment switch
introduced for testing, which is the mechanism this project refuses on principle, and
§3.4 has already dropped the secret that would have carried it.

Successful test grants go through **isolated fixtures or a staging stack**. Real
distribution behaviour — what a genuine production App Store install actually
produces — stays an **explicit verification gate** held until release, not something
manufactured early. Whether an Xcode-run configuration can exercise the path at all is
an F1 measurement, not the assumption I previously stated as fact (§3.4).

---

## 10. Acceptance tests that would actually discriminate

Not things that pass; things that fail if the design is wrong.

1. **Contention is not exhaustion.** Hold the last place in an open transaction,
   attempt a second claim, then **roll the first back**. The second must return
   `busy` or wait — **never `pool_exhausted`** — and a subsequent claim must succeed.
   *This is the R1 defect as an executable assertion.*
2. **Two concurrent first claims by one identity** → both return **success** with the
   same `place_number` and `expires_at`, and the pool falls by exactly one. *Fails if
   the loser gets an error or burns a place.*
3. **Claim, discard the response, claim again** → identical `place_number`,
   `claimed_at`, `expires_at`.
4. **The RPC is called under `service_role` with `p_user_id` supplied** and allocates
   to that identity. *Fails if anything reads `auth.uid()`.*
5. **Grant-only identity publishes a post; a follower reads it** → visible. *Fails if
   only the actor gate was wired.*
6. **Expiry in the past** → feed denied, undiscoverable, posts invisible, **and
   nothing deleted**.
7. **The quarantine conjunct with NULL end evidence** → cleanup **REFUSED**. Run it
   for a grant candidate with missing evidence *and* for a membership row whose Apple
   dates are absent (B-25's shape). *Fails against `coalesce(..., true)`, which is
   what the first draft had.*
8. **Mixed-source case:** `pending_cleanup_at` from a lapse eight months ago plus a
   grant expiring today → **REFUSED**, and refused for sixty more days.
9. **Mixed-source leasing:** an identity with both sources is handed to **one** worker
   only; the second finds it leased.
10. **Grant-only identity past quarantine, Apple returns 404 / an unparseable 200 /
    an active unestablished subscription** → `abort` in all three, nothing deleted,
    **and no membership row created by the worker**. *Fails if U7 became an
    establishment writer.*
11. **TestFlight app transaction** → refused, no place consumed. **And the same Apple
    Account's later production app transaction** → accepted. *Fails if beta testing
    was conflated with permanent exclusion.*
12. **A validly Apple-signed app transaction for a different bundle** → refused, using
    **genuinely signed** hostile fixtures as `attest.ts` does, so a regression makes a
    stranger's artefact *accepted* rather than making a legitimate one fail elsewhere.
13. **Fresh Founding join with Profile open** → directory row published without a
    second navigation; **and the two completion producers' sequences never collide**.
14. **StoreKit resolves `.notEntitled` for a live Founder** → stays Connected.
    *Structurally: the literal call sites must not compile after F4.*
15. **Grant expires while the app is open** → mode recomputes without a relaunch.
16. **Restore Purchases for a Founder** → reports the existing grant and **makes no
    claim call**.
17. **`binding_method` is never written by any Founding path** — asserted
    structurally: no INSERT into `public.membership` anywhere in these units.
18. **In-app conversion carries the signed option and applies no free month.** The
    external-route result is **observed and recorded, whatever Apple does** — it is
    not an assertion. *An earlier draft asserted the Settings route grants a trial;
    that was an expectation, not a testable Apple guarantee.*
19. **The signed option cannot be prepared** → the purchase **stops before StoreKit**,
    nothing is charged, the member can retry. *Fails against the withdrawn fail-open
    behaviour.*
20. **`founding_eligibility_ok` returns false** → every claim refused, whatever the
    client did. *Fails if eligibility rests on screen order.*

---

## 11. What this document does not establish

**Established during reconciliation and no longer open:** that *Get All Subscription
Statuses* accepts an `appTransactionId` (Apple's own reference — *"Any
`originalTransactionId`, `transactionId` or `appTransactionId` that belongs to the
customer for your app"*), which withdrew D5 as a product decision; and that
`introductoryOfferEligibility(compactJWS:)` exists with the claims §6 lists. Both were
raised by Codex and re-verified here against Apple directly. **Neither makes the
design safe** — §5.4 says why, and Codex R2's warning against exactly that inference
is accepted.

**Corrected in revision 3, on Codex's final consistency pass.** `user_id is null` as
the unclaimed test, which with `ON DELETE SET NULL` would have **recycled deleted
Founders' places** and issued more than 500 grants, plus the biconditional constraint
that made the anonymised shape unrepresentable (§3.1, §3.2); revocation left normative
in the schema and predicates while §7 omits it (§3.3, §4, §5.2); *"needs no code
beyond §3.3"* contradicting §3.5's expiry event (§5.1); *"no timestamp an operator can
hand-write"* when `expires_at` is stored and writable (§5.2); accepting
shipping-disabled cleanup as an outcome on Samuel's behalf (§5.4, §9); and describing
a pre-delete recheck as shrinking the race window when it only adds detection at the
front (§5.5).

**Corrected in revision 2 rather than defended.** Contention reported as
exhaustion (§3.2); the same-account loser receiving an error instead of a grant
(§3.2); `auth.uid()` under `service_role` (§3.2); the quarantine conjunct failing
**open** on NULL (§5.3); mixed-source leasing (§5.3a); eligibility resting on screen
order (§8.1); a silent fail-open on trial suppression (§6.2); five manufactured
product questions and one omitted real one (§7); a production test allowance (§9.2);
an unestablished categorical claim about Xcode (§3.4); an environment-switch secret
(§3.4); and loading a new guarantee onto G7 (§5.5).

**Still open:**

- No live database, App Store Connect, secret or device state was inspected. **No
  build or test was run.**
- `AppTransaction.shared` on a first-install device (F1).
- The no-subscription response contract, account association and coverage after an
  Apple Account change, and the purchase/cleanup race (§5.4, §5.5) — a **bounded
  protocol review**, and grant-only cleanup may legitimately ship **disabled**.
- `introductoryOfferEligibility` availability at the deployment target and its
  behaviour for an Apple Account with no purchase history. Codex reports the symbol at
  `:1648` of the installed StoreKit interface; **I have not opened that file.**
- Whether an introductory offer exists in App Store Connect, and on which products —
  **uninspected**. The local `.storekit` file is evidence about the local test
  configuration only.
- The adult-only contract (§8.1). **Founding 500 cannot open publicly without it.**
- The B-23 structural delta is described qualitatively and **has not been computed**.
- **The load-bearing judgement, offered for challenge rather than claimed:** that
  §3.3's second row-derived entitlement source is not the bypass FM-1 forbids. Codex
  accepts it as legitimate entitlement rather than a revived grandfather or test
  bypass. **That is agreement between two readers, not proof**, and it should be
  attacked once more before F2 is written, because most of §3 rests on it.

---

## 12. Dispositions on Codex R1–R7

| | Disposition | Where |
|---|---|---|
| **R1** Allocation contention ≠ exhaustion | **Agree — a real defect.** `SKIP LOCKED` replaced by a serialised advisory lock; `busy` separated from `pool_exhausted`; same-account loser now returns idempotent success; `p_user_id` passed from the Edge Function. Overstated claim about counting withdrawn | §3.2, tests 1–4 |
| **R2** Cleanup gate narrower and harder | **Agree in full.** Conjunct now fails **closed** on NULL — my error, and the sharpest catch in the review. Unestablished-subscription veto added *without* U7 becoming an establishment writer. 404 and malformed 200 never prove absence. Mixed-source leasing specified. Cleanup gated behind a bounded separate protocol review and may ship disabled | §5.3, §5.3a, §5.4 |
| **R3** Client needs recomputation | **Agree.** A cached date does not wake SwiftUI, does not survive an untrustworthy clock and cannot see revocation. Combined resolver made **compile-enforced** so the two literal call sites cannot survive; expiry event; identity scoping, late-response suppression, sign-out and invalidation; shared monotonic sequence for two F3 producers; restore recovers and never allocates | §3.5, tests 13–16 |
| **R4** Adult eligibility ≠ UI placement | **Agree — my worst error.** "Satisfied by placement" withdrawn. A server-side `founding_eligibility_ok` prerequisite that is **false until the adult-only work defines it**, covering access as well as establishment, so allocation is closed at the server | §8.1, test 20 |
| **R5** Do not relax no-extra-trial | **Agree.** Fail-open was a product change dressed as an engineering fallback and was not mine to make. Default is now stop-before-payment; fail-open is Group C for Samuel. Signature freshness and Apple Account change handled; ASC claim withdrawn; "consumes trial history" withdrawn; external-route test weakened to an observation | §6, Group C, tests 18–19 |
| **R6** Reduce and correct the questions | **Agree.** Seven → three groups. D3, D6, D7 and D5 withdrawn with reasons recorded; beta-tester conflation separated; spent-place-without-identifier separated from post-deletion dedup; **existing paid subscribers added**, which I had omitted entirely; early-purchase-defers-billing claim withdrawn | §7 |
| **R7** Production proof and rollback | **Agree.** Environment secret withdrawn and pinned in code; Xcode claim weakened to unverified; historical-download-not-current-binary stated; production test allowance withdrawn in favour of isolated fixtures; forward-only rule once a grant exists; dry run never proves deletion safety | §3.4, §9.1, §9.2 |

**One thing I would keep distinct rather than differ on.** On **R5**'s purchase/cleanup
race we agree it predates Founding 500. I have removed the G7 attachment entirely —
that would have expanded a fixed obligation — and made it a **bounded obligation of
the §5.4 cleanup protocol review**, to be dispositioned there with any residual stated
plainly. It is neither deferred silently nor declared safe because identifier support
exists.

**Revision 3 applied Codex's five final consistency corrections** (§11, first
paragraph). Three were latent defects rather than wording: place recycling on account
deletion, an expiry claim contradicting the client design, and a safety property that
did not exist. Two were me overstating — accepting a departure from FM-2 on Samuel's
behalf, and describing added detection as a smaller race window.

**Status: direction reconciled; scope not accepted.** Samuel decides Groups A, B and C
before F2 is written, and the adult-only contract (§8.1) gates public activation
independently of all three.
