# P5-B / CP-1 — DESIGN, REVISION 2. 2026-09-06

**SUPERSEDED IN PART 2026-09-07 BY THE iOS 26.2 PRODUCT BASELINE (P5-A2).**
Études now requires **iOS 26.2 for the whole app, including Solo**, so §2's
option C and **INVARIANT CP-OS-1** are **historically preserved and no longer
operative** — the app-wide floor subsumes them. **CP-OS-1's REASONING is retained
and still load-bearing**: below 26, `activeParentalControls` cannot be read and
reconciliation cannot run, which is *why* an app-wide floor is coherent rather
than merely convenient. Its billing edge is **dissolved**; acceptance cases
**S-B9 / S-B9b are retired as impossible**; and §10.2's planned
`@available(iOS 26.0, *)` gating is **removed as unnecessary**. See
`docs/phase-5-a2-baseline-acceptance.md`.

**AMENDED 2026-09-06 — REVISION 3, ON REVIEW OF r2. Three changes, all
tightenings, none reversing an accepted Apple finding:**

1. **§7.4 rewritten.** Declined sharing is no longer settled as a product rule.
   CP-1 now states only an **eligibility** fact and hands retry, wording and
   jurisdictional variation to P5-G/product.
2. **§7.3 replaced by §7.3′.** The protective downgrade is **generalised beyond
   `lookup_enabled`**, and it **no longer destroys preference history** — r2's
   "force false and clear `lookup_changed_at`" is withdrawn. A three-layer model
   replaces it, and **`follow_requests_enabled` joins the set** on a measurement
   r2 did not have.
3. **§2 gains INVARIANT CP-OS-1** — the iOS-26 gate is now precise about
   *continued* use, not only joining.

**SUPERSEDES `docs/phase-5-b-cp1-design.md` (r1) ON THE AGE-DECLARATION
MECHANISM ONLY.** r1 is retained, banner-marked, and still carries the four
measured facts and the storage design that survive unchanged.

**DESIGN ONLY. NOTHING IMPLEMENTED. NO PRODUCTION MUTATION. NO SQL EXECUTED.**
Every Apple fact below was read from Apple's current documentation on
2026-09-06 via the `developer.apple.com/tutorials/data/...json` route, not from
memory. Sources are listed in §12.

---

## 0. WHAT CHANGED, AND WHAT DID NOT

**SUPERSEDED — r1 §3's Études-owned age question.** r1 designed a product-owned
self-declaration: our own UI, our own question, our own band. **Apple now
provides a first-party mechanism and it is better on every axis that matters** —
it can be guardian-declared or payment/ID-confirmed, it handles ageing, and it
returns a *range* rather than a date. Building our own would mean asking a child
a question Apple has already asked their guardian.

**SURVIVES UNCHANGED, and this investigation strengthens rather than disturbs
it:**

- **`account_privacy` as a separate, server-authoritative table** — now carrying
  *less* than r1 proposed;
- **absence of a row is fail-protective**, with no `'unknown'` value;
- **`lookup_enabled` is a stored PREFERENCE, never effective visibility**;
- **profile publication never mutates that preference** — and r1's measured
  three-layer `lookupEnabled: true` hazard (r1 §1.3) stands exactly as recorded;
- **initial defaults are separated from later user choices** — with **one
  deliberate, reasoned exception** introduced in §7.3.

---

## 1. THE FRAMEWORK, AS DOCUMENTED

`DeclaredAgeRange`, **iOS/iPadOS/macOS 26.0+**. Entitlement
`com.apple.developer.declared-age-range` (Boolean, enabled as an Xcode
capability).

```swift
let response = try await AgeRangeService.shared.requestAgeRange(
    ageGates: 13, 18, in: viewController)
```

- **Up to three gates**, each resulting range **at least two years**. `13, 18`
  yields exactly three ranges — under-13, 13–17, 18+ — and 13–17 is five years,
  so the constraint is satisfied.
- `Response` is **`.sharing(AgeRange)`** or **`.declinedSharing`**.
- `AgeRange` carries `lowerBound: Int?`, `upperBound: Int?`,
  `ageRangeDeclaration: AgeRangeDeclaration?`, `activeParentalControls`.
- **`lowerBound == nil`** → below the lowest gate. **`upperBound == nil`** →
  meets or exceeds the highest gate.
- `AgeRangeDeclaration`: **`selfDeclared`**, **`guardianDeclared`**,
  **`confirmed`** (credit card or government ID). Six older, more granular cases
  are deprecated and consolidated into these three.
- `Error`: **`.invalidRequest`**, **`.notAvailable`**.
- `AgeRangeService.shared.isEligibleForAgeFeatures` and
  `requiredRegulatoryFeatures` (a `Set<RegulatoryFeature>`).
- `ParentalControls` option set: **`communicationLimits`**, plus a deprecated
  `significantAppChangeApprovalRequired`.

### 1.1 Two documented behaviours that drive the whole design

**(a) THE SYSTEM MAY OVERRIDE OUR GATES.** Apple's reference states the returned
range may reflect **regulatory requirements for the person's location rather than
the bounds we asked for**. So the client must **never assume the response
corresponds to 13 and 18**, and must derive from the bounds arithmetically. §5.

**THIS IS NOT HYPOTHETICAL, AND APPLE'S OWN SANDBOX PROVES IT.** The documented
sandbox test cases return **13–15** and **16–17** as separate ranges — not the
single 13–17 our gates request — alongside `(nil, 12)` and `(18, nil)`. **A
client that pattern-matched on the numbers 13 and 18 would misclassify two of
Apple's six official test cases**, and would do so in the *permissive* direction
if it fell through to an adult default. §5's arithmetic handles all four
shapes.

**(b) AGEING IS DELIBERATELY LAGGED.** When a person crosses into a new range the
API **keeps returning the previous range until the anniversary of their original
declaration** — explicitly to avoid revealing a birth date. A person may force a
refresh in Settings → *Age Range for Apps* → *Share Age Range again*.

**(b) is the single most important fact for Études**, because it means a
persisted band is *expected* to lag reality by up to a year, and the lag is
always in the **protective** direction (still 13–17 after turning 18). A design
that treated staleness as an error would be fighting a privacy feature.

---

## 2. THE DECISIVE COMPATIBILITY CONSTRAINT

**Études' `IPHONEOS_DEPLOYMENT_TARGET` is `18.5`. The framework is iOS 26.0+.**
Xcode is 26.6 with the iOS 26.5 SDK, so the SDK side is fine; the gap is
runtime availability.

Three options, and the recommendation is the third:

| | option | consequence |
|---|---|---|
| A | Raise the deployment target to **26.0** | Simplest code. **Drops every iOS 18–25 device, including for Solo**, which is a pure loss because Solo needs no age data |
| B | Keep 18.5, add a **fallback self-declaration** for < 26 | **Reintroduces exactly the mechanism Apple replaces**, and makes it *the weaker path a user could choose by staying on an old iOS*. Two age systems, one of them the one we set out to avoid |
| C | **RECOMMENDED — keep 18.5; gate Connected JOIN on iOS 26** | Solo unchanged for everyone on 18.5+. Connected join requires iOS 26+. **No fallback self-declaration exists at all** |

**Option C is available only because Études has never been publicly released and
has no production customers** (established on B-36 by the account holder). **There
is no existing Connected member on iOS < 26 to strand**, and there never can be
one, because joining will require 26 from the outset. A member who joins on 26+
cannot later downgrade iOS.

**So: NO FALLBACK SELF-DECLARATION IS NECESSARY, AND IT IS POSITIVELY
UNDESIRABLE.** That answers the question directly. A fallback would be a
second, weaker age path whose existence is discoverable and whose selection is
under the user's control — the opposite of raising the floor.

**On older iOS, "Explore Connected" states plainly that Connected requires iOS 26
or later.** Solo is untouched, unrestricted, and never asks anything.

### 2.1 INVARIANT CP-OS-1 — SUPERSEDED 2026-09-07, PRESERVED FOR ITS REASONING

**No longer operative: the whole app requires iOS 26.2, so there is no sub-26
state for this invariant to govern.** It is kept because the argument below is
exactly why the app-wide floor was chosen, and because a future decision to widen
Solo's reach would have to answer it again.

> **Connected requires iOS 26.0 or later AT ALL TIMES, not only at the moment of
> joining. On a supported OS below 26, the app presents SOLO, under the standing
> non-destructive semantics: local journal, Scores, media, profile and settings
> untouched; the Connected identity retained; nothing deleted; nothing scheduled
> for cleanup.**

**The choice is made now, deliberately, while it is free** — there are no shipped
members, so no behaviour is being taken away from anyone.

**Why continued use is gated too, and not only the join.** The weaker rule —
"join on 26, keep it anywhere" — is reachable in practice: a restore onto an
older device, or a second, older device on the same Apple Account. On such a
device:

- **`activeParentalControls` cannot be read at all.** It is device state
  available only through this framework, so Études could not know whether
  **`communicationLimits`** applies to a minor — and Études has directed comments
  and direct attachment sending (§8). **That is a live safety gap on the exact
  surfaces the control governs, not an edge case.**
- **Reconciliation cannot run**, so the protective adult→teen downgrade of §7.3′
  could never be detected on that device. A design whose safety rests on
  reconciliation must not run where reconciliation cannot.

**It costs nothing and it reuses proven machinery.** "Connected withdrawn,
identity and local data retained" is not new behaviour to build: it is exactly
the lapse path already implemented and device-verified under C-1/C-26, where a
genuine expiry withdrew Connected and deleted nothing. **CP-OS-1 adds an input to
that decision; it does not add a mechanism.**

**FLAGGED FOR P5-G/PRODUCT, NOT ENGINEERING:** a member who subscribes on iOS 26
and later runs a sub-26 device would be **billed while Connected is
unavailable**. Joining already requires 26, so this cannot arise at purchase —
only afterwards. **What the product owes that member (guidance, a prompt to
manage the subscription, or nothing) is a commercial and legal decision**, and
CP-1 does not take it.

---

## 3. WHERE THE REQUEST HAPPENS — SOLO IS NEVER ASKED

```
Solo                        NO age request, ever. No account, no processing.

Explore Connected  (iOS 26+ only; older iOS shows a plain requirement notice)
  ├─ requestAgeRange(ageGates: 13, 18)      ◄── BEFORE SIWA
  │    ├─ .declinedSharing ─────────► Connected NOT available. Nothing stored.
  │    ├─ throws / unavailable ─────► Connected NOT available. Nothing stored.
  │    └─ .sharing(range) → derive band (§5)
  │           └─ under-13 ──────────► Connected NOT available. NOTHING STORED.
  │                                    NO SIWA. NO identity minted.
  ├─ SIWA                             auth.users row now exists
  ├─ account_privacy_upsert_v1(band)  ◄── FIRST authenticated call
  ├─ ensure_membership_binding()
  ├─ purchase(appAccountToken:)
  ├─ attestation
  └─ AppSetUpView → first account_directory row
```

**The request precedes SIWA deliberately**, unchanged from r1's reasoning: an
under-13 is turned away **without an identity being minted**, so no account
exists that would then need deleting. It also means a decline costs the user
nothing and leaves no trace.

**Calling it at app launch would be wrong** and is rejected explicitly: it would
subject every Solo user — who has no account and shares nothing — to age
processing they have no need of, which fails data minimisation. Apple's sample
shows a `.task` on view appearance; **for Études the correct view is the
Connected join flow, not the app**.

---

## 4. WHAT IS PERSISTED — STRICTLY LESS THAN r1

```sql
create table public.account_privacy (
  user_id                       uuid primary key
                                  references auth.users(id) on delete cascade,
  age_band                      text        not null,
  band_updated_at               timestamptz not null default now(),

  -- Preference 1: discoverability.
  lookup_enabled                boolean     not null,
  lookup_set_under_band         text        not null,
  lookup_changed_at             timestamptz,          -- null while still the initial default

  -- Preference 2: may strangers request to follow. LIVE -- see 7.3'.
  follow_requests_enabled       boolean     not null,
  follow_requests_set_under_band text       not null,
  follow_requests_changed_at    timestamptz,

  constraint age_band_values
    check (age_band in ('band_13_17', 'band_18_plus')),
  constraint lookup_set_under_band_values
    check (lookup_set_under_band in ('band_13_17', 'band_18_plus')),
  constraint follow_requests_set_under_band_values
    check (follow_requests_set_under_band in ('band_13_17', 'band_18_plus'))
);
```

**Two bands only. There is no `'under_13'` value and no `'unknown'` value.**
An under-13 result and a decline both mean **no row is ever written**, so the
table cannot become a register of children who tried to join. Absence remains
the protective state (§6), so the safe case needs no representation.

### 4.1 Provenance is deliberately NOT stored

`ageRangeDeclaration` tells us whether the range was `selfDeclared`,
`guardianDeclared` or `confirmed`. **Études does not store it, and r1's
`band_declared_at` / `band_promoted_at` columns are dropped.**

**The test is whether it changes a decision, and it does not.** Share and
discovery defaults derive from the band alone; a `confirmed` 13–17 member and a
`selfDeclared` 13–17 member get identical treatment. Storing provenance would be
**additional personal data about a child, retained for no operative purpose** —
which is the thing a children's-privacy workstream exists to avoid, and which
would be conspicuous in a DPIA.

**FLAGGED FOR P5-G, DEFAULTING TO NOT STORING:** if the DPIA concludes Études
must *evidence* the quality of its age assurance, an aggregate or per-decision
audit record may be required. **That is a legal determination, not an
engineering preference**, and the design's default is to store nothing until
P5-G says otherwise. Adding a column later is cheap; deleting data already
collected is not.

---

## 5. DERIVING THE BAND — BOUNDS ARITHMETIC, FAIL-CLOSED ON UNDER-13

**Because Apple may override our gates (§1.1a), the client must never pattern-
match on 13 and 18.** The derivation is:

```
guard case .sharing(let r) = response      else  → BLOCK (declined)
if let lo = r.lowerBound, lo >= 18         then  → band_18_plus
if let lo = r.lowerBound, lo >= 13         then  → band_13_17
otherwise                                        → BLOCK
```

**`lowerBound == nil` BLOCKS.** It means "below the lowest gate the system
used", which **cannot affirmatively establish 13 or over**. Blocking is
fail-closed on the one question with the sharpest legal consequence.

**The over-blocking case is real and is accepted with its reasoning.** If a
regulator requires a higher bottom gate — say 16 for digital consent — then a
13–15-year-old returns `lowerBound == nil` and is blocked from Connected. **That
is the correct outcome in that jurisdiction anyway**, since they could not
consent there; the derivation happens to align with the regulation rather than
having to model it.

**Nothing infers an exact age, and no arithmetic is done on a birth date,
because none is available.**

---

## 6. NO INTERVAL OF ADULT DEFAULTS — PRESERVED FROM r1

Unchanged, and now with fewer ways in. **Discovery**, CP-2's clause on
`search_account_directory`:

```sql
and exists (select 1 from public.account_privacy p
             where p.user_id = ad.user_id and p.lookup_enabled)
```

An `EXISTS`, never a `coalesce(..., true)` — absence returns **false**, the
protective answer. D4's lesson (an empty set falling through to a permissive
clause) is reused rather than repeated. `get_account_directory_by_user_ids`
stays **unchanged**: attribution remains independent of discoverability (G10).

**Share** — the rule is unchanged from r1 §4.2 and still closes r1's measured
**three** windows (two `@State … = true` declarations plus two derivation sites,
with `fetchDefaultPostingIsPrivate()` returning `false` on both a missing profile
and a fetch error):

> **Share defaults ON only when the client holds a server-confirmed
> `band_18_plus`. Unknown, unfetched, failed and `band_13_17` all default OFF.**

**This governs defaults, not capability.** A 13–17 member may still deliberately
share a session; the Share toggle stays offered.

---

## 7. RECONCILIATION AS THE MEMBER AGES

**Apple owns ageing; Études reconciles.** No promotion control, no
member-initiated transition, and r1's `account_privacy_promote_band_v1` is
withdrawn.

### 7.1 When Études re-requests

On the Connected path only, at launch and foreground, subject to Apple's own
caching — which the documentation says makes repeated calls cheap and
non-prompting, revealing new information only on the declaration anniversary.
**Études therefore does not implement its own cadence, throttle or anniversary
clock**, because doing so would duplicate a system behaviour and drift from it.

This mirrors **U5f's attestation invariant** deliberately: it runs on the
Connected path regardless of whether Connected is already active, and a previous
success is never permanent authority.

### 7.2 `band_13_17` → `band_18_plus`

Accept. Write `age_band` and `band_updated_at`. **Touch no preference** — the
initial-defaults separation holds exactly as in r1 §6.

### 7.3′ `band_18_plus` → `band_13_17` — THE PROTECTIVE DIRECTION, GENERALISED

**r2's rule is WITHDRAWN.** It forced `lookup_enabled := false` and **cleared
`lookup_changed_at`**, which destroyed preference history, and it addressed only
one of the three pieces of state that carry child-safety consequences.

**This can genuinely happen**, by at least four routes: the person corrects their
range in Settings; a guardian changes it; *Share Age Range again* returns a
corrected value; or **a different iCloud account is signed in on the device**
(§9.2).

#### The three layers, kept strictly apart

| layer | where it lives | who writes it | destroyed on downgrade? |
|---|---|---|---|
| **Persisted user preference** | the stored column / local `Profile` | only an explicit user action | **NEVER** |
| **Initial default** | materialised into the preference once, at creation, from the band | `account_privacy_upsert_v1` on first insert | never rewritten |
| **Effective child-safety override** | **computed at read time, stored nowhere** | nobody — it is a function | n/a |

**The override may only ever make behaviour MORE protective, and it is never
written back.** That is what lets preference history survive a downgrade
untouched while effective behaviour is unquestionably child-safe.

#### The rule

Each preference records **the band in force when it was last written**:

```
effective(pref) = pref
              AND NOT (current_band = 'band_13_17'
                       AND pref_set_under_band = 'band_18_plus')
```

**A permissive choice made while classified as an adult does not carry into a
child classification.** Standard 7 expects a child's data to be visible to others
**only if the child changes the setting**, and a setting inherited from a
mistaken adult classification is not a change the child made. The member may set
it again as a teen, which updates `pref_set_under_band` and makes it take effect
— which is precisely what Standard 7 contemplates.

**Nothing is cleared, nothing is overwritten, and the history remains
auditable.** A later teen→adult reclassification restores the adult-set
preference automatically, because the override simply stops applying. **Under r2's
withdrawn rule that value would have been gone for good.**

#### The complete set of state returned to child-safe defaults

| # | state | kind | on downgrade |
|---|---|---|---|
| **1** | **`lookup_enabled`** — discoverability | server preference | override → **not discoverable** |
| **2** | **`follow_requests_enabled`** — may strangers request to follow | server preference | override → **requests closed** |
| **3** | **Share default posture** | local `Profile.defaultPrivacy` | override → **default OFF** |

**(2) IS NEW IN r3 AND RESTS ON A MEASUREMENT r2 DID NOT HAVE.** `lookup_enabled`
has **zero** references anywhere in the deployed schema, but
**`follow_requests_enabled` is LIVE**: `follow_requests_open(target_user_id)`
reads it, and the **`follows_insert_requester` INSERT policy calls that
function**. It genuinely gates who may create a follow request — a **contact
vector into a minor**, and therefore squarely in scope. r2 treated the two
columns as equivalent; they are not.

**A HAZARD IN THAT FUNCTION — NOW A HARD CP-2 REQUIREMENT, NOT AN INCIDENTAL
FINDING.** `follow_requests_open` ends `coalesce(..., true)`, so **a missing or
unresolved row falls through to PERMISSIVE**. That is the same shape as the D4
defect this design is otherwise built to avoid.

**It is tolerable today only because there are no minors.** Once minors are
supported, an identity whose row is missing or whose state is unresolved would
have follow requests **open by default** — a contact vector into a possible minor,
resolved permissively by absence. **That is exactly the failure direction CP
exists to eliminate.**

> **REQUIREMENT CP-2-R1 — BINDING ON P5-E.** `follow_requests_open` must be
> changed so that a missing or unresolved row resolves **closed**, never open.
> It is **not** optional, **not** deferred to a later tidy-up, and it appears in
> CP-2's predicted surface and acceptance criteria (§10.1, §11.5) rather than as
> a note.

**It carries a behaviour change that must be predicted, not discovered:** every
identity with no `account_directory` row moves from *follow-requests open* to
*follow-requests closed*. At the CP-0 population that is a small, enumerable set,
and P5-E must **count it before applying** and state the number.

**(3) settles the Share posture.** For `band_13_17` the Share default is **OFF**,
and per the settled product decision it is **not user-configurable at the default
level** — the per-session Share toggle remains fully available, so a teen may
still deliberately share. `Profile.defaultPrivacy` is **preserved untouched** and
simply does not apply while the band is `band_13_17`; it applies again if the
member is later classified adult.

**The asymmetry with discovery is inherited, not invented:** the settled
decisions say *"Share default OFF"* and *"discovery default OFF (independently
opt-in)"*. Discovery is opt-in for teens; the Share **default** is not. **If
product wants a teen-configurable Share default, that is a P5-G/product change,
not an engineering one.**

#### What is deliberately NOT reverted, and why

- **Existing published posts are NOT retroactively unshared.** They were the
  member's deliberate act; Études has **no public feed**, so they are visible only
  to **already-approved followers**; and retroactively destroying a member's own
  published record would cut against the fundamental rule that no Connected or
  membership action deletes the local journal or the member's work.
- **Existing approved follows are NOT severed.** Severing established
  relationships is destructive and irreversible.

**BOTH ARE EXPLICITLY OPEN, AND NEITHER RETENTION NOR DESTRUCTIVE ROLLBACK IS
YET DEFINED AS CORRECT.** The paragraph above describes **what the CP-1
mechanism does not currently reach** — it is a statement of scope, **not a
finding that retention is the right answer**. A child-protective regime might
require retrospective unsharing, or might not; that is a legal determination
about what such a regime owes retrospectively, and **P5-G/DPIA owns it
outright**.

**Do not read "not reverted" as "settled as retained."** If P5-G determines that
existing posts or approved follows must be withdrawn on a protective downgrade,
that is a **new unit with its own prediction**, and it is a destructive path, so
it would carry the full ceremony this project applies to those. **CP-1 neither
implements nor forecloses it.**

### 7.4′ DECLINE, ERROR OR UNAVAILABILITY — AN ELIGIBILITY FACT ONLY

**r2 settled this as a product rule. That was out of CP-1's remit and is
withdrawn.** CP-1 states only the engineering invariant:

> **A `.declinedSharing` response, a thrown error, an unavailable service, or a
> range whose lower bound is insufficient (§5) DOES NOT ESTABLISH CONNECTED
> ELIGIBILITY. No Connected identity and no `account_privacy` row is created,
> and no existing row is created, promoted or modified.**

**Stated as create/promote/modify — not as "blocks" or "refuses forever".** The
same sentence therefore covers both directions without smuggling in a product
decision: nothing is brought into existence, and **nothing existing is destroyed
or demoted either**. An established member who later declines keeps their band,
because a decline is an absence of fresh evidence, not evidence of change — the
same principle that makes "absence of a membership record can never schedule
cleanup" structural, and consistent with invariant 3, since a client-side read
may not drive an irreversible change.

**EXPLICITLY NOT SETTLED BY CP-1, and owned by P5-G / product / legal:**

- whether the UI offers a **retry**, and how many times;
- the **wording** shown after a decline;
- whether a decline is **remembered locally** or re-asked each time;
- whether **any jurisdiction** requires different handling — including whether a
  decline may be refused as an answer at all, given Apple's documented behaviour
  that **declining is impossible in regulated regions**;
- whether a decline by an **established** member has any product consequence.

**CP-1 must not be read as having decided any of these.**

## 8. `activeParentalControls` — FLAGGED, DELIBERATELY NOT DESIGNED HERE

`AgeRange.activeParentalControls` may contain **`communicationLimits`**,
indicating the system limits the minor's communication features. Apple's stated
expectation is that apps honour this.

**Études has two directed-communication surfaces this touches:** comments
addressed to a specific member, and **direct attachment sending** — a Connected
attachment sent to a named recipient, which is the most communication-shaped
thing in the product.

**Three reasons it is flagged and not designed in CP-1:**

1. **It is device/session state, not member state.** It reflects controls active
   on *this device now* and can change without any Études event. **Persisting it
   server-side would store a stale copy of a live parental control**, which is
   both wrong and a new category of retained data about a child.
2. **It arrives only with an age-range response**, so it is available exactly
   where the client already is — arguing for a client-side gate consulted at the
   point of action, refreshed with the range.
3. **A server-side rule would need its own unit**, because directed comments and
   attachment sends are currently gated by follow relationships and enforcement,
   not by any age concept, and widening those predicates is not a CP-1 change.

**Recommendation to carry into P5-F and P5-G, not decided here:** CP-3 consults
`communicationLimits` client-side to withhold directed-send affordances, and
**P5-G determines whether a server-side control is legally required**. Recorded
so it cannot be lost, and explicitly **not** scoped into CP-1.

---

## 8.5 CONSENT REVOCATION HAS A SERVER SIGNAL, AND OUR ENDPOINT ALREADY SURVIVES IT

**Found while establishing the sandbox cases, and not anticipated by the brief.**
Apple's sandbox documentation states that revoking app consent, where App Store
Server Notifications V2 is enabled, delivers a **`RESCIND_CONSENT`** notification
carrying an **`appData`** object with `bundleId` and `environment`.

**Études already receives App Store Server Notifications** at the deployed
`appstore_notifications_v1`, so this is not a new integration — it is existing
traffic Études has never seen.

**It is already handled safely, and this was verified by reading the deployed
source rather than assumed.** `_shared/appstore/derive.ts:130` contains:

```ts
if (payload.appData !== undefined) return na("appData notification");
```

so a `RESCIND_CONSENT` is signature-verified, recorded in
`membership_notification` as **`not_applicable`** with reason
`"appData notification"`, and changes no membership state. **It is not a reject,
not a failure, and not an attack** — which is precisely what **B-27** was filed
and fixed to achieve, one phase before anyone knew this notification type would
exist. **The generalisation earns its keep here: a vocabulary that separates
"routine traffic we do not act on" from "hostile traffic" degrades gracefully
against categories that did not exist when it was written.**

**Two consequences.** Engineering: **no change is required to accept
`RESCIND_CONSENT`**, and CP must not add one speculatively. Legal: the signal is
**available and durably recorded** should P5-G determine that Études must *act*
on a guardian withdrawing consent — which is question 5 in §11, and which §7.4
currently answers with "never unmakes a member". **P5-G owns whether that answer
is lawful; the engineering is ready either way.**

---

## 9. THE HONEST LIMITATIONS

**9.1 — THE BAND REMAINS CLIENT-ASSERTED. Apple's API improves the QUALITY of
the assertion, not its VERIFIABILITY.** The response is not signed and there is
no server-side counterpart Études can call — unlike a StoreKit transaction JWS,
which the server re-verifies against a pinned anchor. A modified client could
assert `band_18_plus`.

**This must not be overstated in either direction.** It is not a regression: a
self-declaration was equally client-asserted, and worse, it was *designed* to be
freely chosen. Apple's mechanism raises the floor substantially — guardian
declaration and `confirmed` ranges are unavailable to any self-declaration
scheme. But **the design must not be described as server-verified age
assurance**, and P5-G must assess it as what it is.

**9.2 — THE SUBJECT IS THE DEVICE'S iCLOUD ACCOUNT, NOT THE ÉTUDES IDENTITY.**
Apple's reference is explicit: the range is for *the person signed in to iCloud
on the device*. Études' identity comes from Sign in with Apple, which is usually
but **not necessarily** the same person — a shared or family device is the
obvious divergence.

The design binds the band to the Études identity **at the moment of the call**,
which is the best available association, and §7.3 makes the drift case
protective: if the iCloud user later reads as a minor, the Études account moves
to the protective band. **The residual — an adult's device used to establish an
adult band for a child's Études account — is not closable by this API** and is
recorded for P5-G rather than papered over.

**9.3 — A PERSISTED BAND IS EXPECTED TO BE STALE, BY UP TO A YEAR**, in the
protective direction, by Apple's deliberate design (§1.1b). A member who turns 18
keeps child protections until their declaration anniversary. **This is accepted,
not worked around**, and no Études clock may attempt to anticipate it.

---

## 10. PREDICTIONS

**To be re-derived and committed immediately before P5-D. Not authority for an
apply.**

### 10.1 Schema delta (B-23 surfaces)

| surface | predicted |
|---|---|
| `columns` | **+9** (`account_privacy`) — provenance dropped, but r3 adds a second preference and a `set_under_band` per preference (7.3′) |
| `constraints` | **+5** — pkey, FK to `auth.users`, and three band-value checks |
| `rls_enabled` | **+1**, with **zero policies** (U3 pattern) |
| `functions` | **+4 new** (`upsert_v1`, `set_lookup_v1`, `set_follow_requests_v1`, `self_v1`), **2 MODIFIED** — `search_account_directory` **and `follow_requests_open`**, which must now apply the 7.3′ override |
| `function_grants` | **+4**, `authenticated` only |
| `triggers` | **+1** on `account_directory` (band-precondition, r1 §3.2) |
| `table_grants` / `column_grants` | **ZERO** — all revoked per U3 |

`account_privacy_promote_band_v1` is **withdrawn**; `upsert_v1` replaces r1's
`create_v1` because reconciliation must be able to move an existing band (§7.2,
§7.3) while still never being able to *delete* one.

### 10.2 Client / project delta (CP-3)

- **New entitlement** `com.apple.developer.declared-age-range` and the Xcode
  capability — **a project-file and provisioning change**, which on this project
  means re-checking the Release signing path before anything else is believed.
- ~~`@available(iOS 26.0, *)` on the join path~~ — **REMOVED 2026-09-07: unnecessary under the 26.2 app-wide floor. `DeclaredAgeRange` is unconditionally available.**
- Age request + derivation + reconciliation on the Connected path.
- Share default: one shared derivation replacing 2 `@State` initialisers
  (`= true` → `= false`) and 2 derivation sites.
- `AccountDirectoryService`: remove 2 payload keys and 2 **dead parameters**
  (r1 §1.3); update 3 call sites.
- A discoverability control in settings. **No promotion control** — withdrawn.

### 10.3 Rollback

Unchanged from r1 §9.3: kill switch on the CP-2 clause **first**, drop the
additive objects, restore `search_account_directory` byte-compared to its
committed definition. **No data loss at P5-D because the table is empty; that
ceases to be true after the first band is written**, and after that a drop
destroys a declaration only Apple and the member can reproduce.

---

## 11. WHAT P5-G MUST NOW DECIDE

Materially larger than under r1, and all of it is legal rather than engineering:

1. **Is Apple's declared age range sufficient age assurance** for Études'
   assessed risk (§9.1)?
2. **Provenance** — must `ageRangeDeclaration` be recorded as evidence (§4.1)?
   Default: no.
3. **`communicationLimits`** — is honouring it client-side sufficient, or is a
   server-side control required (§8)?
4. **`requiredRegulatoryFeatures`** — whether
   `.significantAppChangeRequiresAdultNotification` (Apple's
   `showSignificantUpdateAcknowledgment`) and
   `.significantAppChangeRequiresParentalConsent` (**PermissionKit**) apply to
   Études, and **what counts as a significant update** for a product that adds
   social features incrementally.
5. **Consent revocation and decline** — §7.4′ says nothing is created, promoted,
   modified or destroyed. **P5-G owns the premise**, plus the whole product
   surface CP-1 deliberately left open: retry, wording, local memory of a
   decline, and jurisdictional variation — including Apple's documented
   behaviour that **declining is impossible in regulated regions**.
6. **Retrospective reach of a protective downgrade** — §7.3′ does **not**
   retroactively unshare existing posts or sever existing approved follows.
   **Whether a child-protective regime requires either is a legal judgement.**
7. **Teen-configurable Share defaults** — §7.3′ follows the settled decision that
   the Share *default* is OFF and not user-configurable for `band_13_17`, while
   discovery is opt-in. **If that asymmetry is wrong, it is a product change.**
8. ~~CP-OS-1's billing edge~~ — **DISSOLVED 2026-09-07.** A member cannot run
   Études on a sub-26 device at all, so "billed while Connected is unavailable"
   cannot arise.
9. **Lawful basis for children's processing**, carried unchanged from the
   existing scope.
10. **The iCloud/Études subject mismatch** (§9.2) — **carried as an explicit DPIA
    residual**, not closable by this API.

## 11.5 SANDBOX ACCEPTANCE CASES

**Testing is done from Settings → Developer → Sandbox Apple Account → Manage →
Age Assurance**, with Developer Mode enabled and a Sandbox Apple Account signed
in. Apple exposes **six** fixed test cases; Études' own cases add the ones Apple
does not simulate.

**RIG PRECONDITION — MET, MEASURED 2026-09-07.** Device A (iPhone 16e) and
Device B (iPhone 17 Pro) are **both on iOS 26.6.1**, above the 26.2 floor, so
every case below is runnable on the existing rig. The original wording is kept
below for its reasoning.

**ORIGINAL — A LATER TEST-RIG MATTER, AND EXPLICITLY NOT A BLOCKER TO CP-0.** Sandbox age-assurance testing was introduced in **iOS/iPadOS 26.2**
(reported by Apple's developer news, not by the framework reference — treat as
reported, and confirm before planning a run). **The iOS versions on Device A
(SD beta burner, iPhone 16e) and Device B (SD iPhone, iPhone 17 Pro) are NOT
recorded anywhere in this repository and must be measured before any run is
scheduled.** Anything below 26.2 makes the cases below unrunnable.

**This gates P5-F acceptance, not P5-C or P5-D.** CP-0 deletes dormant beta
identities and CP-1's apply is pure DDL; **neither touches the Declared Age Range
path**, so neither is held up by a device that cannot yet simulate an age
range.

**Anything involving Connected join must run on Release**, per the standing rule
that Debug's bundle id is unknown to App Store Connect.

### Apple's six simulated cases → Études' predicted outcome

| # | Apple case (lower, upper, declaration) | derived band | Connected join | server row |
|---|---|---|---|---|
| **S-A1** | `(nil, 12)` guardianDeclared | **BLOCK** | **refused** | **none written** |
| **S-A2** | `(13, 15)` guardianDeclared | `band_13_17` | allowed | band + `lookup_enabled=false` |
| **S-A3** | `(16, 17)` guardianDeclared | `band_13_17` | allowed | band + `lookup_enabled=false` |
| **S-A4** | `(18, nil)` selfDeclared | `band_18_plus` | allowed | band + `lookup_enabled=true` |
| **S-A5** | `(18, nil)` confirmed | `band_18_plus` | allowed | **identical to S-A4** |
| **S-A6** | `(18, nil)` confirmed, significant change | `band_18_plus` | allowed | **identical to S-A4** |

**S-A2 and S-A3 are the cases that falsify a naive implementation** — neither
returns the 13–17 bounds we asked for, and both must still resolve to
`band_13_17`.

**S-A4/A5/A6 must produce BYTE-IDENTICAL server state.** That is the executable
form of §4.1's decision not to store provenance: if `selfDeclared` and
`confirmed` ever diverge in `account_privacy`, provenance has leaked into
storage by accident. **A test that three different inputs produce one output is
the only way to assert an absence.**

### Études' own cases, which Apple's fixtures do not cover

| # | scenario | how | predicted outcome |
|---|---|---|---|
| **S-B1** | **declined sharing at join** | *Age Range for Apps* → **Never Share** | `.declinedSharing` → **Connected eligibility not established; no identity, no row** (§7.4′). **UI retry/wording is NOT scored here — P5-G/product** |
| **S-B2** | **Ask First, then decline** | *Ask First* + decline at the prompt | as S-B1 |
| **S-B3** | **API error / unavailable** | airplane mode; no Sandbox account | throws → join refused, nothing stored. **Must not crash and must not fall through to an adult default** |
| **S-B4** | **ageing 13–17 → 18+** | switch case S-A3 → S-A4, then *Share Age Range again* | band updated; **`lookup_enabled` UNCHANGED** (§7.2) |
| **S-B5** | **protective downgrade 18+ → 13–17** | set discovery ON and follow-requests ON as an adult, then switch S-A4 → S-A2 | band updated; **stored preferences UNCHANGED and still `true`**; **effective discovery and follow-requests both false**; Share default OFF (§7.3′) |
| **S-B5b** | **downgrade then teen re-affirms** | after S-B5, turn discovery on again | `lookup_set_under_band` becomes `band_13_17`; **effective discovery true** — Standard 7's "only if the child changes the setting" |
| **S-B5c** | **downgrade then re-upgrade** | after S-B5, switch back to S-A4 | **the adult-set preferences apply again with no rewrite**, because the override merely stops applying. **Falsifies r2's withdrawn rule, which would have destroyed them** |
| **S-B5d** | **follow request against a downgraded member** | S-B5 state, second identity attempts a follow request | **refused by `follows_insert_requester`** via `follow_requests_open` (§7.3′) |
| **S-B6** | **decline AFTER a band exists** | establish S-A4, then *Never Share* | **nothing created, promoted, modified or destroyed** — band retained, member stays Connected (§7.4′) |
| **S-B7** | **`communicationLimits` active** | a case reporting it | directed-send affordances withheld client-side (§8) |
| **S-B8** | **consent revocation** | *Manage* → *Revoke App Consent* → bundle id | `RESCIND_CONSENT` lands `not_applicable` / `"appData notification"`; **membership unchanged** (§8.5) |
| ~~S-B9~~ | ~~iOS < 26, never joined~~ | — | **RETIRED 2026-09-07 as IMPOSSIBLE.** No supported configuration can produce a pre-26 device: the app requires 26.2. **Not skipped, not failing — unreachable** |
| ~~S-B9b~~ | ~~CP-OS-1: established member on iOS < 26~~ | — | **RETIRED 2026-09-07 as IMPOSSIBLE**, with CP-OS-1 itself (§2.1) |
| **S-B10** | **Solo never asks** | fresh install, stay in Solo | **no age request is made at all** — assert by absence of the prompt and of any API call (§3) |

**S-B5c IS THE SINGLE MOST VALUABLE CASE IN THE SET.** It is the one that
**discriminates r3's override model from r2's withdrawn rule**: under r2 the
adult-set preferences were destroyed on downgrade, so a re-upgrade could not
restore them. If S-B5c shows them restored with no rewrite, the three-layer
model is doing exactly what it claims. **A test that only ever downgrades cannot
tell the two designs apart.**

**S-B5, S-B5d and S-B6 matter for the same reason**: they exercise rules that
were *decided* rather than *observed* — the child-safety override, its reach into
the live follow-request gate, and the rule that a decline creates, promotes,
modifies and destroys nothing. **None can be established by reading Apple's
documentation**, because all are Études policy, so all must be behaviourally
observed.

**S-B9b is the CP-OS-1 acceptance** and it must be scored on **non-destruction**
as much as on unavailability: the interesting failure is not "Connected still
worked" but "something was deleted on the way to Solo".

**S-B10 is an assertion of an absence** and needs a discriminator: a build that
requests at launch would pass every other case here. It should be scored by
instrumenting the call site, not by watching for a prompt that a cached response
would suppress anyway.

---

## 12. SOURCES

Read 2026-09-06: `developer.apple.com/documentation/declaredagerange`;
`.../declaredagerange/agerangeservice`;
`.../agerangeservice/requestagerange(agegates:_:_:in:)`;
`.../agerangeservice/agerange`; `.../agerangeservice/agerangedeclaration`;
`.../agerangeservice/parentalcontrols`;
`.../declaredagerange/requesting-people-share-their-age-range-with-your-app`;
`.../bundleresources/entitlements/com.apple.developer.declared-age-range`;
WWDC25 session 299, *Deliver age-appropriate experiences in your app*.
