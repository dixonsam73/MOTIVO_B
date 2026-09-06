# P5-B / CP-1 — DESIGN, REVISION 2. 2026-09-06

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
  user_id            uuid primary key
                       references auth.users(id) on delete cascade,
  age_band           text        not null,
  lookup_enabled     boolean     not null,
  band_updated_at    timestamptz not null default now(),
  lookup_changed_at  timestamptz,
  constraint age_band_values
    check (age_band in ('band_13_17', 'band_18_plus'))
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

### 7.3 `band_18_plus` → `band_13_17` — THE PROTECTIVE DIRECTION

**This can genuinely happen**, by at least four routes: the person corrects
their range in Settings; a guardian changes it; *Share Age Range again* returns a
corrected value; or **a different iCloud account is now signed in on the device**
(§9).

**Rule: accept it, and re-apply the teen defaults — including forcing
`lookup_enabled := false` and clearing `lookup_changed_at`.**

**THIS IS A DELIBERATE, NARROW EXCEPTION TO "NEVER OVERWRITE A PREFERENCE", AND
IT IS RECORDED AS AN EXCEPTION RATHER THAN ALLOWED TO ERODE THE RULE.** The
reasoning: a discoverability preference expressed while classified as an adult
was expressed under a classification now known to be wrong. The Children's Code's
Standard 7 expects a child's data to be visible to others **only if the child
changes the setting** — and a setting inherited from a mistaken adult
classification is not a change the child made. The member may of course turn it
back on, deliberately, which is precisely what Standard 7 contemplates.

**The exception is bounded in three ways:** it fires only on an
adult→teen transition, it only ever moves the preference to the *more* protective
value, and it never fires on the teen→adult direction. **A downgrade must never
silently widen exposure and this rule cannot do so.**

### 7.4 Decline, error or unavailability AFTER a band exists

**Never revokes an existing band, and never disables Connected for an existing
member.** A `.declinedSharing`, a `.notAvailable`, a thrown error or an
unreachable API leaves `account_privacy` exactly as it is.

**The reasoning is this project's own, twice over.** Absence of fresh evidence is
not evidence of change — the same principle that makes "absence of a membership
record can never schedule cleanup" structural. And a decline is a *reversible*
signal about a *client-side* read, so under invariant 3 it may withdraw nothing
irreversible. The persisted band is already the protective record; discarding it
would move the member from a known-safe classification to an unknown one, which
is strictly worse.

**Decline blocks JOINING. It never unmakes a member.**

---

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
| `columns` | **+5** (`account_privacy`) — one fewer than r1, provenance dropped |
| `constraints` | **+3** — pkey, FK to `auth.users`, `age_band_values` |
| `rls_enabled` | **+1**, with **zero policies** (U3 pattern) |
| `functions` | **+3 new** (`upsert_v1`, `set_lookup_v1`, `self_v1`), **1 MODIFIED** (`search_account_directory`) |
| `function_grants` | **+3**, `authenticated` only |
| `triggers` | **+1** on `account_directory` (band-precondition, r1 §3.2) |
| `table_grants` / `column_grants` | **ZERO** — all revoked per U3 |

`account_privacy_promote_band_v1` is **withdrawn**; `upsert_v1` replaces r1's
`create_v1` because reconciliation must be able to move an existing band (§7.2,
§7.3) while still never being able to *delete* one.

### 10.2 Client / project delta (CP-3)

- **New entitlement** `com.apple.developer.declared-age-range` and the Xcode
  capability — **a project-file and provisioning change**, which on this project
  means re-checking the Release signing path before anything else is believed.
- `@available(iOS 26.0, *)` on the join path; a plain requirement notice below.
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
5. **Consent revocation** — what happens when a guardian withdraws sharing, given
   §7.4 says it never unmakes a member. **That is an engineering rule with a
   legal premise, and P5-G owns the premise.**
6. **Lawful basis for children's processing**, carried unchanged from the
   existing scope.
7. **The iCloud/Études subject mismatch** (§9.2).

## 11.5 SANDBOX ACCEPTANCE CASES

**Testing is done from Settings → Developer → Sandbox Apple Account → Manage →
Age Assurance**, with Developer Mode enabled and a Sandbox Apple Account signed
in. Apple exposes **six** fixed test cases; Études' own cases add the ones Apple
does not simulate.

**RIG PRECONDITION, and it is not yet established.** Sandbox age-assurance
testing was introduced in **iOS/iPadOS 26.2** (reported by Apple's developer
news, not by the framework reference — treat as reported, and confirm before
planning a run). **The iOS versions on Device A (SD beta burner, iPhone 16e) and
Device B (SD iPhone, iPhone 17 Pro) are NOT recorded anywhere in this
repository and must be measured before any run is scheduled.** Anything below
26.2 makes every case below unrunnable.

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
| **S-B1** | **declined sharing** | *Age Range for Apps* → **Never Share** | `.declinedSharing` → join **refused**, **nothing stored** |
| **S-B2** | **Ask First, then decline** | *Ask First* + decline at the prompt | as S-B1 |
| **S-B3** | **API error / unavailable** | airplane mode; no Sandbox account | throws → join refused, nothing stored. **Must not crash and must not fall through to an adult default** |
| **S-B4** | **ageing 13–17 → 18+** | switch case S-A3 → S-A4, then *Share Age Range again* | band updated; **`lookup_enabled` UNCHANGED** (§7.2) |
| **S-B5** | **protective downgrade 18+ → 13–17** | switch S-A4 → S-A2 | band updated; **`lookup_enabled` FORCED false**, `lookup_changed_at` cleared (§7.3) |
| **S-B6** | **decline AFTER a band exists** | establish S-A4, then *Never Share* | **band retained, member stays Connected** (§7.4) |
| **S-B7** | **`communicationLimits` active** | a case reporting it | directed-send affordances withheld client-side (§8) |
| **S-B8** | **consent revocation** | *Manage* → *Revoke App Consent* → bundle id | `RESCIND_CONSENT` lands `not_applicable` / `"appData notification"`; **membership unchanged** (§8.5) |
| **S-B9** | **iOS < 26** | any pre-26 device | Solo fully functional; **Explore Connected shows the requirement notice** (§2) |
| **S-B10** | **Solo never asks** | fresh install, stay in Solo | **no age request is made at all** — assert by absence of the prompt and of any API call (§3) |

**S-B5 and S-B6 are the two most valuable cases**, because they exercise the two
rules that were *decided* rather than *observed*: the deliberate exception to
"never overwrite a preference", and the rule that a decline never unmakes a
member. **Neither can be established by reading the API documentation**, since
both are Études policy, so both must be behaviourally observed.

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
