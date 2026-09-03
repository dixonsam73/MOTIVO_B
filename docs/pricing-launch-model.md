# Pricing and launch model — PLANNED, NOT IMPLEMENTED

**Recorded 2026-09-03 as a product/pricing decision note.**

**NOTHING IN THIS DOCUMENT IS BUILT.** No code, schema, migration, Edge Function,
entitlement, cleanup, activation flow or App Store Connect configuration was
changed to record it, and none may be changed on the strength of it without an
explicit, separately authorised scoping step. **Phase 3's scope and
implementation are unaffected.**

This file exists because this project's standing rule is that the repository is
the state and no conversation is. A pricing direction held only in conversation
is not durable.

---

## 1. The model

- **Études Solo remains permanently free and functionally complete.**
- **Études Connected remains £4.99/month or £49.99/year.**

**The Founding 500.** To address Connected's cold-start / network-density problem
at public launch, the **first 500 unique production users who actually ACTIVATE
Connected** — activations, **not** downloads or installations — become **Founding
Members** and receive Connected **free for 12 months from their own individual
activation date**, granted by a **server-authoritative Études entitlement rather
than an Apple subscription**.

- On expiry a Founder may subscribe at the normal monthly or annual price. They
  **do not** receive an additional introductory trial.
- **From Connected member #501 onward**, new users receive a **one-month
  introductory trial through StoreKit**, then the normal subscription price.

**Allocation requirements.** Founding allocation must be **atomic and race-safe**,
**account-based**, and **unaffected by reinstall or device change**.

**Messaging.** Restrained mention of the first-500 offer in the App Store
description; explained clearly in Connected onboarding. **After activation** a
Founder is explicitly told they are a Founding Member and shown their **exact
entitlement expiry date**. Once all 500 places are allocated, Founding messaging
is removed and replaced with the normal one-month-trial messaging.
**No countdowns. No "places remaining" marketing.**

---

## 2. Product decisions — SETTLED

### FM-1 — A Founding membership is an explicit, time-bounded grant. It never impersonates a purchase

A Founding membership must ultimately be represented as a **legitimate, explicit,
server-authoritative, time-bounded entitlement or grant with a real expiry** —
`entitled_until` or whatever its eventual canonical equivalent is.

**It must NOT:**

- masquerade as an Apple purchase, nor be recorded as `binding_method =
  'purchase'` or `'legacy_claim'`;
- be implemented as a **bypass inside the entitlement predicate**.

**Why this is settled rather than a preference.** Both prohibitions restate rules
this project has already paid for. `binding_method` and `bound_at` record **how
ownership was proved**, and **B-24's correction** — applied again one level down
in U4 — is that a provenance value inferred from something that did not happen is
**provenance invented rather than established**. A Founding grant proves nothing
about Apple ownership, so claiming either value would be a lie the database is
specifically constructed to make impossible. And **D4 rejected an exception
inside `connected_member()`** on the grounds that an authority predicate must not
contain a branch whose safety rests on operational discipline.

**A Founding grant is NOT the grandfather mechanism returning.** U6b-4 retired
that arm precisely because the cutover snapshot **had no entitlement predicate** —
it granted Connected to every identity that existed rather than every identity
that qualified. A Founding grant is the opposite: an explicit, enumerable,
individually-dated entitlement with a real expiry. The distinction is the whole
of FM-1, and it is the sentence to re-read if anyone later proposes reusing the
retired arm.

### FM-2 — An expiring Founder follows the ordinary lapse policy. There is no Founder retention regime

When a Founding Member's 12-month entitlement expires **without conversion** to a
paid Connected subscription, they follow the **same existing Connected lapse
policy** as any other lapsed member:

1. **Immediate return to Solo**, with Connected access ending and their Connected
   presence becoming invisible to other members;
2. the **normal 60-day quarantine**;
3. **eventual cleanup** under the settled expiry retention matrix.

**There is no special indefinite-retention regime for Founders.** Resubscription
during quarantine cancels pending cleanup and restores their presence whole,
exactly as for anyone else.

**The fundamental rule applies unchanged: leaving Connected is not leaving
Études.** A lapsed Founder keeps their local journal, Scores, media, profile and
settings in full. Invariant 1 is untouched by any of this.

---

## 3. Implementation implications — IDENTIFIED, EXPLICITLY UNRESOLVED

**Each of these is a known consequence, not a design. All are left open for a
future, separately authorised scoping step.**

### 3.1 The deployed schema and predicate cannot yet express this grant

`public.membership` has `binding_method` and `bound_at` as **`NOT NULL`**, with
`constraint membership_binding_method_check check (binding_method in ('purchase',
'legacy_claim'))`. `membership_establish_v1` is the only INSERT into that table
anywhere, and it **derives** provenance from which artefact carried the token.
`connected_member()` reads **Production Apple dates only**.

**So a Founding entitlement has nowhere to live today**, and FM-1 forecloses the
two shortcuts — lying about `binding_method`, or branching inside the predicate.
Where it *should* live is **undecided**.

### 3.2 Founding expiry must eventually feed the canonical cleanup arithmetic

FM-2 requires the ordinary 60-day fuse. But `pending_cleanup_at` is computed by
`membership_apply_state_v1` **from Apple's own dates**, and a Founding grant has
none. **As built, U7's quarantine and cleanup path is not reachable for an
expiring Founder** — they would be denied by enforcement and never scheduled.

**FM-2 is therefore a requirement that the current implementation does not yet
satisfy.** Closing that gap is future work; how the founding expiry date reaches
the scheduling arithmetic is **undecided**.

### 3.3 Founding activation needs a non-purchase activation path

"Activate Connected" currently means: Sign in with Apple → `ensure_membership_
binding()` → `product.purchase(_:appAccountToken:)` → `.verified` → attestation.
**A Founder makes no purchase**, so U5f's flow does not describe them and the
binding token — which exists to bind an Apple subscription — has no subscription
to bind.

What "activation" means for a Founder, and how the **atomic, race-safe,
account-based** allocation of the 500 places is performed, are **undecided**.
One property is already inherited for free: Sign in with Apple returns a stable
`sub`, observed on 2026-08-25 to re-authenticate the **same** identity even after
the credential was manually revoked — so a grant keyed on `auth.users.id`
satisfies "unaffected by reinstall or device change" without new machinery.

### 3.4 The post-500 StoreKit introductory offer pairs naturally with C-31

Member #501 onward requires a **one-month introductory offer** configured in App
Store Connect. **C-31** — the outstanding Production Billing Grace promotion —
is also App Store Connect configuration. They are naturally considered together,
which is an observation about sequencing only. **Neither is scheduled here, and
C-31's disposition is unchanged.**

---

## 4. What this note does not do

It does not schedule work, enter any phase's scope, alter Phase 3, create a
register row, or authorise any change to code, schema, entitlement logic, cleanup
behaviour, activation flow or App Store Connect. **It records a direction and two
settled product decisions, and names four open questions as open.**
