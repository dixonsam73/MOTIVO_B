# CP-3 — REMAINING ACCEPTANCE MATRIX. 2026-09-08

Written after Gate (C) was accepted as hardware-verified. Repo `9cf2cf9`,
local == origin, tree clean. **Nothing here has been executed.**

## 0. WHAT IS NOW SETTLED, so it is not re-litigated below

| | |
|---|---|
| session-management defect | **device-verified** for the behaviours exercised |
| resubscription/hydration regression | **device-verified** — hydration begins with an already-valid token |
| Gate (C) | **device-verified** — 10 preflights, 4 hydrations, **0** rotations |
| hydration runs ~2× per foreground | **recorded only.** Not to be acted on |
| criterion 3, directory publication | **unscored / structurally unavailable** on a Sandbox fixture. **Not failed.** `enforcement_gate` is not to be weakened, Production entitlement not manufactured, the deferred tester carve-out not implemented |

---

## 1. APPLE'S CACHING — VERIFIED, AND IT IS NOT WHAT WE MIGHT HAVE ASSUMED

Checked against Apple's own material rather than inferred.

**What Apple states:**

- **Responses are cached, and the cache SYNCS ACROSS DEVICES.** People manage
  cached responses in Settings. So the cache is an account-level artefact, not a
  device-local one — a device wipe or reinstall would not obviously clear it.
- **The Sandbox test path is** Settings → Developer → **Sandbox Apple Account** →
  *account* → **Manage** → **Age Assurance**, with **Revoke App Consent** offered
  as a *separate control on the same screen*.
- Sandbox age-assurance testing requires **iOS 26.2+**; the **Simulator is not
  supported**, so this is physical-device-only.
- Documented sandbox scenarios include 16-17 `guardianDeclared`, 18+
  `selfDeclared` and 18+ `confirmed`.

**What Apple does NOT state, and therefore what we must not assume:**

> **Nowhere does Apple say that changing the Age Assurance fixture invalidates a
> previously cached response.** The testing documentation goes no further than
> *"the settings change itself appears to trigger updated API responses"* — a
> hedge, not a guarantee.

**The consequence is a real trap.** If the fixture switch is inert for an app
that already holds a cached answer, then a teen or under-13 test would run
against **the cached adult answer** while we believed we had changed it — and it
would *pass* by producing adult behaviour we misread as correct. **That is the
over-determined-zero failure mode again**, in its most expensive form.

**`Revoke App Consent` is the documented lever most likely to clear it**, and its
exact effect on `requestAgeRange` is also undocumented.

**So the first action of any teen/under-13 work must be a probe that establishes
how the fixture behaves for THIS app. Everything else depends on it.**

## 1.1 AND OUR OWN CODE ASKS APPLE FAR LESS OFTEN THAN ONE MIGHT THINK

**With a band row present, Apple is never asked at all on the recovery path.**
`AgeBandRecoveryCoordinator.recoverIfNeeded` returns on `fetchSelf` `.success`
**before** `requestRange` (`:84-91`), and `ensureAgeBandEstablished` returns on
the same branch before `upsertBand`. Measured repeatedly this morning: 10
preflights, `band_updated_at` never moved.

**Exactly one path asks Apple unconditionally:** `ConnectedIntroductionView`'s
**Continue** → `requestDeclaredAgeRange()` (`ProfileView:389`). That single fact
is what makes anything in category A below testable at all.

---

## 2. THE MATRIX

**A** = achievable now on Device A · **B** = partial, limitation stated ·
**C** = blocked until a fresh / Production-entitled fixture exists.

| # | discriminator | class | why |
|---|---|---|---|
| 1 | **13–17 default Share OFF** | **C** | `shareDefaultOn` reads `ProfileStore.lastKnownAgeBand()`, a mirror of the **server** `account_privacy.age_band`. Producing `band_13_17` means a teen identity or mutating the existing row — both excluded. **The rule itself is already pure and unit-tested**; what is missing is only device wiring |
| 2 | **13–17 discovery default OFF** | **C** | The defaults are written **server-side at band establishment**, so it needs an identity whose band is established as teen. Same blocker |
| 3 | **Explicit teen discovery opt-in + persistence** | **C** | Needs a teen band row before the toggle means anything, plus `lookup_changed_at` stamping. Same blocker. *(The adult half of this control is already exercised: the toggle renders and `lookup_changed_at` is NULL, i.e. untouched)* |
| 4 | **Under-13 refusal** | **A** | `onContinue` → `.ineligible` → alert *"Études Connected is for ages 13 and over."*, and **`continueToConnectedJoin()` is never called** — so **no server write, no identity minted, no purchase, no entitlement consumed**. Needs only a sub-13 fixture. **Subject to §1's cache probe** |
| 5 | **Unavailable / declined / error refusal** | **A/B** | Same shape: `.unavailable` → *"Études needs Apple to share your age range…"*, refusing before any write. **A** if `Revoke App Consent` (or a decline on the sheet) reliably produces it; **B** if the cached answer keeps being served, in which case only the *error* branch is reachable — `requestDeclaredAgeRange` maps **any thrown error** to `.unavailable`, so the mapping is already unit-tested and only the device wiring would be unverified |
| 6 | **Finding-A `identityWithoutBand` recovery** | **B** | **The short-circuit half is already verified** — with a band present Apple is not asked and nothing is written, observed across 10 preflights today. **The recovery half — no band row, launch/foreground re-acquires and establishes — is unreachable**, because the only identity available has a band. **C for the half that matters** |
| 7 | **Strong band-before-directory ordering** | **C** | **Doubly blocked.** It needs (i) a fresh identity so CP-1's trigger refusal is actually reachable — on this identity the band predates the row by ~17h and the trigger passes trivially — **and** (ii) a directory INSERT that is *permitted*, which `enforcement_gate` refuses for a Sandbox-only membership. Also unavailable: `account_directory` has **no timestamp column**, so no transaction evidence exists regardless |

**Four of seven are C, and they share one root cause: every remaining teen-side
discriminator needs an identity whose SERVER BAND IS TEEN, and we have exactly
one identity, whose band is adult and must not be rewritten.**

---

## 3. RECOMMENDED MINIMUM SEQUENCE

**Two device actions, both free: no purchase, no server write, no identity
created or deleted, no entitlement consumed, and the `band_18_plus` row and the
no-directory-row fixture both preserved.**

### Step 1 — the cache probe and the under-13 refusal, in ONE action

1. Settings → Developer → Sandbox Apple Account → *account* → Manage → **Age Assurance** → a **sub-13** fixture.
2. Études → Profile → **Explore Connected** → **Continue**.

| observed | means |
|---|---|
| *"Études Connected is for ages 13 and over."* | **discriminator 4 PASSES**, and the fixture switch is proven live for this app — which validates every later teen test |
| `MembershipSelectionView` appears instead | the **cached adult answer was served**. Back out **without purchasing**. The fixture switch is inert; go to `Revoke App Consent` and repeat |

**Both outcomes are informative and neither mutates anything.** The refusal
happens before `continueToConnectedJoin()`, and the fallback outcome is a screen
Samuel backs out of.

### Step 2 — unavailable / declined refusal

Using **Revoke App Consent** (or declining on the sheet if it presents), then
Continue again. Expect *"Études needs Apple to share your age range…"*. Refuses
before any write, as above.

### Step 3 — restore the adult fixture

Return Age Assurance to **18+, age confirmed**, so the device fixture and the
server band agree again. Hygiene, not correctness: with a band row present
nothing can be written whatever the fixture says.

**Expected yield: discriminator 4 scored, discriminator 5 scored or precisely
bounded, and §1's cache question answered — which is the precondition for all
future teen work.** Cost: zero.

### What would unblock the four C items — stated, NOT proposed

**CORRECTED 2026-09-08. My first version said this needed "a different Apple ID,
so SIWA returns a new `sub`". THAT IS WRONG, and this project had already
measured the opposite.**

**Revocation and deletion are different lifecycles, and only one of them frees
the `sub`:**

- **Credential revocation alone re-authenticates the EXISTING identity.** SIWA
  returned the **same `sub`** after a manual revocation and `auth.users` **did
  not grow** (`CLAUDE.md:625`).
- **Deleting the backend row frees it.** After D15 deleted `cfadb7cb` through
  the real account-deletion path, a subsequent SIWA **on the same Apple Account**
  minted a **new** backend identity `5ae3faab…` (`CLAUDE.md:2350`).

**So the fresh identity needs a backend DELETION, not a different Apple
Account.** The recorded option is therefore:

> **Once the current adult fixture has discharged its remaining duties**,
> deliberately delete/reset that disposable beta identity **through the real
> account-deletion lifecycle**, then reuse **Device A's existing primary Apple
> Account** with a **teen** Age Assurance fixture to establish a fresh Études
> identity.

**Do NOT change Apple's primary account merely to obtain another identity.**

That single fixture would make 1, 2, 3 and the recovery half of 6 achievable in
one run, and — **only if additionally Production-entitled** — discriminator 7.

**THIS IS NOT AUTHORISATION TO DELETE `9c5385f6` NOW**, and it is sequenced
strictly after the zero-cost tests below.

---

# 4. STEP 1 — NON-MUTATION BASELINE, captured 2026-09-08 07:03:16 UTC

Taken **before** the fixture is changed, so a refusal can be proved to have
written nothing.

| measure | S1-BASE |
|---|---|
| `auth.users` | **2** |
| `account_privacy` | **1** row · `band_18_plus` · `band_updated_at` **2026-09-07 13:40:16.675419** · `lookup_changed_at` NULL · `follow_requests_changed_at` NULL |
| `account_directory` | **1** row |
| `membership` | 1 row · `updated_at` **2026-09-08 06:53:03.488676** · `renewal_date` **07:14:29** |
| `membership_binding` | `updated_at` **2026-09-07 13:40:16.990315** |
| refresh tokens | `9c5385f6` **41** · `dfaf8d18` **248** |
| **`account_privacy_upsert_v1` (THE WRITER)** | **2** |
| `account_privacy_set_lookup_v1` (discovery writer) | **never called** (null) |
| `account_privacy_self_v1` (read) | **34** |
| `account_directory` INSERT / SELECT | **2795** / **3356** |

**The writer counter is the sharp instrument.** `account_privacy_upsert_v1` is
the only path that can write a band. If the under-13 refusal behaves as designed
it must stay at **2** — a value that cannot be argued with, unlike a row that
merely still looks the same.

## 4.1 THE FIXTURE, AND THE PREDICTION

**Select exactly: `Under 13, significant change approved`** — Apple's own label,
in Settings → Developer → Sandbox Apple Account → *account* → Manage → Age
Assurance. It returns **lowerBound —, upperBound 12, `guardianDeclared`**.

`DeclaredAgeRangeService.derive(lowerBound: nil, upperBound: 12)` → **`.ineligible`**,
which our unit suite already asserts. Samuel's current fixture is
*"18+, age confirmed, significant change not applicable"*, which is the same
picker — so the labels are known to be readable as written.

**Predicted, on Explore Connected → Continue:**

| | prediction |
|---|---|
| **P-A** | the alert **"Connected isn't available"** with the message **"Études Connected is for ages 13 and over."** |
| **P-B** | `continueToConnectedJoin()` is never called ⇒ **no `MembershipSelectionView`, no purchase sheet** |
| **P-C** | `account_privacy_upsert_v1` stays at **2** — nothing written |
| **P-D** | `auth.users` **2**, `account_privacy` 1 row, `band_updated_at` unchanged, `account_directory` 1 row, `membership_binding` unchanged |
| **P-E** | `dir_ins` stays **2795** |

**THE ALTERNATIVE OUTCOME IS ALSO INFORMATIVE AND IS NOT A FAILURE.** If
`MembershipSelectionView` appears instead, Apple served the **cached adult
answer** and the fixture switch is inert for this app — which is exactly the
§1 question, answered. **Back out without purchasing;** it still writes nothing.

**Not to be followed automatically by Revoke App Consent or Step 2.** Step 1 is
measured and reported first.

---

# 5. STEP 1 IS UNREACHABLE FROM THE CURRENT STATE — re-evaluated 2026-09-08 07:21

**The account holder is right, and it is an either/or in source, not a nuance:**

```swift
if appModeManager.canShowConnectedAccountManagement { appSettingsSection }  // Manage Membership
else { connectedPromoSection }                                              // Explore Connected
```
`ProfileView:353-358`

**Explore Connected exists only while NOT Connected**, and Device A is Connected
on the live Sandbox purchase. **Force-quitting would not help** — the StoreKit
entitlement is still live, so the app re-resolves Connected on relaunch. That
was correctly anticipated and is not worth spending an action to discover.

**MY STEP-1 INSTRUCTION WAS WRITTEN AGAINST YESTERDAY'S DEVICE STATE.** I scoped
the route while Device A was in Solo and did not re-check it after the
repurchase I myself asked for. The fixture change is harmless (see below), but
the route was wrong.

## 5.1 THE UNDER-13 FIXTURE IS INERT RIGHT NOW, AND THAT IS STRUCTURAL

With a band row present **Apple is never asked**: `AgeBandRecoveryCoordinator`
returns on `fetchSelf` `.success` before `requestRange` (`:84-91`), and
`ensureAgeBandEstablished` returns on the same branch before `upsertBand`. The
**only** unconditional caller is `ConnectedIntroductionView`'s Continue — which
is exactly the control that is currently hidden.

**So the under-13 fixture can sit where it is indefinitely without risk.** It
cannot reach a decision, and it cannot write a band. No hurry to revert it.

## 5.2 SOLO IS REQUIRED, AND THERE ARE TWO WAYS THERE

Entitlement at 07:21: **live**, `renewal_date` **07:44:29**, last renewed
07:18:23 — roughly 30-minute accelerated cycles. Purchase was ~06:40, so Apple's
~12-renewal sandbox cap puts the **natural lapse at roughly 12:40–13:00 UTC**.

| option | time to Solo | cost |
|---|---|---|
| **(a) Wait for the natural lapse** | **~5.5 hours** | none |
| **(b) Cancel the Sandbox subscription** | **~23 minutes** — access runs to the period end, **07:44:29** | writes ordinary membership lifecycle state |

**(b) is the project's own documented tool for this**, recorded in `CLAUDE.md`'s
Environment section: *"To observe a lapse rather than re-purchase, cancel the
subscription. Access runs to the period end."*

**What (b) mutates, stated plainly:** `membership.updated_at`, `renewal_date`,
`entitlement_ended_at` and `pending_cleanup_at` will move, and a
`DID_CHANGE_RENEWAL_STATUS` then `EXPIRED`/`VOLUNTARY` will ingest. **That is an
organic product-path lifecycle event, not manual repair** — and `membership` is
already being rewritten every ~30 minutes by renewals, so cancelling changes the
trajectory rather than introducing a new class of write. **`account_privacy`,
`account_directory`, `membership_binding` and both identities are untouched
either way.**

**Nothing remaining needs the entitlement.** Gate (C) is verified; criterion 3 is
structurally unavailable on a Sandbox membership; every remaining category-A test
requires **Solo**. The entitlement has discharged its duties and is now the
obstacle.

## 5.3 THE BASELINE STANDS

§4's S1-BASE (07:03:16) remains valid for the non-mutation proof — with one
expected exception to declare in advance: **if option (b) is taken,
`membership.updated_at`, `renewal_date`, `entitlement_ended_at` and
`pending_cleanup_at` WILL differ**, and that is the cancellation, not the
under-13 refusal. **The writer counter `account_privacy_upsert_v1` must still be
exactly 2**, and the band, directory, binding and identity counts unchanged.

---

# 6. S1-BASE2 — RE-BASELINE, 2026-09-08 08:09:46 UTC. Solo, Explore Connected visible

## 6.1 The lapse is GENUINE SERVER-SIDE, not a client mode flip

| | |
|---|---|
| `entitled_now` | **false** |
| `renewal_date` / `entitlement_ended_at` | **07:44:29** — exactly the predicted period end |
| `updated_at` | **07:45:00.732713**, ~31 s after it |
| `pending_cleanup_at` | **2026-11-07 07:44:29** — re-armed ~60 days out, as predicted |

**Checked deliberately**, because a client showing Solo while the server still
believed the identity entitled would be a different finding, and the probe must
not be scored on an unverified premise. Voluntary cancellation behaved exactly as
the subscription table specifies: entitled through the paid-through date, then
expired.

**Incidental, recorded not chased: NO notification ingested for this
cancellation** — `membership_notification` has no row after 07:00. The state was
applied by **attestation's own live Apple read**, which is the designed
authority; notifications schedule and never execute. Sandbox delivers each
notification once with no retries, so a miss is unremarkable.

## 6.2 S1-BASE2 — the values the probe is scored against

| measure | S1-BASE (07:03) | **S1-BASE2 (08:09)** | |
|---|---|---|---|
| `auth.users` | 2 | **2** | unchanged |
| `account_privacy` rows / band | 1 / `band_18_plus` | **1 / `band_18_plus`** | unchanged |
| `band_updated_at` | 2026-09-07 13:40:16.675419 | **2026-09-07 13:40:16.675419** | **unchanged** |
| `lookup_changed_at` / `follow_requests_changed_at` | NULL / NULL | **NULL / NULL** | unchanged |
| `account_directory` rows | 1 | **1** | unchanged |
| `membership_binding.updated_at` | 2026-09-07 13:40:16.990315 | **2026-09-07 13:40:16.990315** | unchanged |
| **`account_privacy_upsert_v1` (WRITER)** | 2 | **2** | **unchanged** |
| `account_privacy_set_lookup_v1` | never called | **never called** | unchanged |
| `account_directory` INSERT | 2795 | **2795** | **unchanged — no row has ever been published** |
| `account_directory` SELECT | 3356 | **3364** | +8 hydrations |
| `account_privacy_self_v1` | 34 | **45** | +11 preflights |
| `posts` SELECT | — | **19870** | |
| tokens `9c5385f6` / `dfaf8d18` | 41 / 248 | **42 / 248** | **+1 / unchanged** |

**A FREE ELEVENTH CONFIRMATION OF GATE (C):** across that hour — 11 privacy
preflights and 8 directory hydrations — **exactly one token rotation**, an hour
after the previous one, i.e. ordinary expiry-driven renewal. **No burst, no
sub-second gap.** The pre-fix binary would have rotated on every one of those 11.

## 6.3 PREDICTIONS FOR THE UNDER-13 PROBE — restated against S1-BASE2

Fixture already set to **`Under 13, significant change approved`** (lowerBound —,
upperBound 12, `guardianDeclared`). Action: **Explore Connected → Continue**,
then stop.

| | prediction | falsifier |
|---|---|---|
| **P-A** | alert **"Connected isn't available"**, message **"Études Connected is for ages 13 and over."** | any other message |
| **P-B** | **no `MembershipSelectionView`, no purchase sheet** — `continueToConnectedJoin()` is never called on `.ineligible` | either appears |
| **P-C** | **`account_privacy_upsert_v1` stays exactly 2** | any increase — a band write |
| **P-D** | `auth.users` **2** · privacy **1** row · `band_updated_at` **2026-09-07 13:40:16.675419** · both `*_changed_at` NULL | any change |
| **P-E** | `account_directory` rows **1**, `dir_ins` **2795** | any increase |
| **P-F** | `membership_binding.updated_at` **2026-09-07 13:40:16.990315**; `auth.users` unchanged | any movement |
| **P-G** | `dfaf8d18` **248** tokens | any movement |

**THE ALTERNATIVE OUTCOME IS INFORMATIVE, NOT A FAILURE.** If
`MembershipSelectionView` appears instead, Apple served the **cached adult
answer** and the fixture switch is inert for this app — which is precisely the
§1 caching question, answered by measurement. **Back out without purchasing.**
P-C through P-G must hold in that case too, since `ensureAgeBandEstablished`
short-circuits on the existing row either way.

**Either result answers something worth knowing. Neither writes anything.**

---

# 7. STEP 1 RESULT — 2026-09-08 08:12:09 UTC. DISCRIMINATOR 4 PASSES

Device: alert **"Études Connected is for ages 13 and over."**

| | prediction | observed | |
|---|---|---|---|
| P-A | that exact refusal message | **as predicted** | **PASS** |
| P-B | no `MembershipSelectionView`, no purchase sheet | none appeared | **PASS — and see §7.1** |
| **P-C** | **`account_privacy_upsert_v1` stays 2** | **2** | **PASS** |
| P-D | users 2 · privacy 1 row · `band_18_plus` · `band_updated_at` 2026-09-07 13:40:16.675419 · both `*_changed_at` NULL | all as predicted | **PASS** |
| P-E | directory rows 1, `dir_ins` 2795 | **1 / 2795** | **PASS** |
| P-F | binding `updated_at` 2026-09-07 13:40:16.990315 | unchanged | **PASS** |
| P-G | `dfaf8d18` 248 tokens | **248** | **PASS** |

## 7.1 A RESULT STRONGER THAN PREDICTED: NO SERVER CALL AT ALL

**`account_privacy_self_v1` stayed at 45** and `9c5385f6`'s token count stayed at
**42**.

That is not merely "nothing was written". `continueToConnectedJoin()` calls
`ensureAgeBandEstablished`, which calls `fetchSelf`, which would have incremented
the read counter and preflighted a session refresh. **Neither moved, so the
refusal is proven to have occurred strictly before ANY server contact** — P-B is
established server-side rather than only from the screen.

**An under-13 answer costs Apple one call and stops. No identity is touched, no
session is spent, and nothing reaches the backend.** That is the behaviour CP-3's
design intends: turn the member away *without* minting anything that would then
need deleting.

## 7.2 THE CACHING QUESTION IS ANSWERED BY MEASUREMENT

**Apple returned the under-13 range despite this app holding a previously cached
ADULT answer, and `Revoke App Consent` was never used.**

So **changing the Sandbox Age Assurance fixture does change what
`requestAgeRange` returns**, live, for an app that already held a cached
response. §1's trap — a teen test silently scored against a stale adult answer —
**does not apply on this device with this Sandbox account.**

**RECORD THIS NARROWLY AND DO NOT GENERALISE IT.** The claim is exactly:

> *On **Device A**, with **this Sandbox account** (`sdsongsltd+devicec@gmail.com`)
> and **this app**, changing the Age Assurance fixture changed the value returned
> by `requestAgeRange` despite a previously cached adult response.*

It is **not** a claim about production devices, other Apple Accounts, other apps,
non-Sandbox accounts, or Apple's behaviour in general. Apple's documentation does
not promise it. It is one measurement in one test environment, and that is the
level at which it may be relied upon — enough to unblock teen fixtures **on this
rig**, and nothing wider.

**One thing is NOT established:** whether Apple re-presented its system sheet or
served the new fixture value without prompting. It was not observed and it
changes no conclusion — **the returned value tracked the fixture either way** —
but the distinction is not claimed.

## 7.3 STATUS CHANGES

| | was | now |
|---|---|---|
| **Discriminator 4 — under-13 refusal** | class **A**, untested | **PASSED, device-verified** |
| §1 fixture-vs-cache behaviour | unknown, flagged as a trap | **answered: the fixture governs** |
| Discriminator 5 — unavailable/declined | **A/B** | **still A/B, deliberately not pre-judged.** Apple's six documented fixtures all return bounds, so `.declinedSharing` may not be reachable by fixture switching at all; `Revoke App Consent` remains the candidate lever, and that is Step 2 |

**Stopping here as instructed. Step 2 not attempted. The Under-13 fixture is left
as-is — it is structurally inert while a band row exists.**

---

# 8. DISCRIMINATOR 5 — SCOPED. 2026-09-08 08:15

## 8.1 THREE INPUTS, ONE OUTCOME — and they are NOT equivalent

Études refuses all three identically, which is correct product behaviour and
**exactly why they must not be treated as one test**:

| input | source | maps to |
|---|---|---|
| **`.declinedSharing`** | Apple's own enum — the person declined to share | `.unavailable` (`DeclaredAgeRangeService:99-100`) |
| **`@unknown default`** | a response shape this OS/SDK does not know | `.unavailable` (`:103-105`) |
| **thrown error** | framework/transport failure | `.unavailable` (`ProfileView:1121-1123`, `catch`) |

All three surface the same alert. **So observing the alert proves only that
*one* of them occurred — it cannot say which.** Any claim about a specific branch
needs the branch to be independently forced.

## 8.2 `Revoke App Consent` DOES SOMETHING ELSE ENTIRELY. MY EARLIER GUESS WAS WRONG

I previously called it *"the documented lever most likely to clear the cached
consent"*. **It is not a client-side age-range control at all.** Per Apple's
Sandbox testing documentation it is a **server-notification simulator**:

- you enter **your app's Bundle ID** and tap **Revoke Consent**;
- the system confirms *"Notification Triggered — A notification will be sent to
  the developer server soon"*;
- with ASSN v2 enabled, the **server** receives a **`RESCIND_CONSENT`**
  notification carrying an `appData` object with `bundleId` and `environment`.

It simulates **a parent or guardian revoking access to the app on behalf of their
child**. It says nothing about, and does nothing to, what `requestAgeRange`
returns on the device.

**Two consequences.** It is **useless for discriminator 5**, and using it **would
write to the server** — our Sandbox notification URL is configured, so a
`RESCIND_CONSENT` row would land in `membership_notification` (currently **104**).
**It must not be used casually.** *(Separately: `RESCIND_CONSENT` handling is a
real, untested ingestion path and worth its own scoped unit later — recorded, not
proposed.)*

## 8.3 REACHABILITY OF EACH BRANCH

| branch | classification | why |
|---|---|---|
| **`.declinedSharing`** | **B — candidate route, unconfirmed** | **No documented Sandbox fixture produces it.** All six return bounds (under 13, 13-15, 16-17, 18+ ×3), and Apple's own table has no declined row. The genuine article needs the *user-facing* control — Apple states *"people can manage their cached responses in the Settings app"* — which is **distinct from** the developer fixture and from Revoke App Consent. **I cannot confirm from the documentation that such a per-app control exists or that withdrawing it yields `.declinedSharing`.** That is a question for the device, not for me to assert |
| **framework / transport error** | **DEVICE-UNREACHABLE** | Nothing supported makes `requestAgeRange` throw. Forcing it means removing the `com.apple.developer.declared-age-range` entitlement or otherwise breaking the build — **fixture manufacture, and it changes the binary under test**. Declared unreachable rather than simulated |
| **`@unknown default`** | **STRUCTURALLY UNREACHABLE** | It fires only if Apple adds a response case this SDK does not know. Unreachable by construction on a current OS, and correctly so |

**Two of the three branches are unreachable on this rig, and I am classifying
them as such rather than manufacturing an equivalent.** The mapping of all three
to `.unavailable` is already pure and unit-tested; what device testing could add
is only that the wiring carries a real Apple `.declinedSharing` through — and
only if the branch can be produced at all.

## 8.4 D5-BASE — fresh baseline, 08:15:30 UTC

| measure | value |
|---|---|
| `auth.users` | **2** |
| `account_privacy` | 1 row · `band_18_plus` · `band_updated_at` **2026-09-07 13:40:16.675419** · `lookup_changed_at` NULL |
| `account_directory` | **1** row |
| `membership_binding.updated_at` | **2026-09-07 13:40:16.990315** |
| **`membership_notification`** | **104** — the tripwire for any accidental `RESCIND_CONSENT` |
| tokens `9c5385f6` / `dfaf8d18` | **42 / 248** |
| **`account_privacy_upsert_v1` (writer)** | **2** |
| `account_privacy_self_v1` | **45** |
| `account_directory` INSERT / SELECT | **2795 / 3364** |

## 8.5 MINIMUM PHYSICAL ACTION — one look, no taps

**The strongest reachable case is `.declinedSharing`, and whether it is reachable
at all is currently unknown.** So the minimum action is **an inspection, not a
test**:

> **Look for a user-facing control that governs whether Études may receive the
> age range** — under Settings → *Apple Account* → the age-range / age-sharing
> section, or Settings → Études, or wherever this device surfaces the "manage
> your cached responses" Apple describes. **Do not change anything yet. Report
> what exists.**

- **If such a control exists** → withdrawing it, then Explore Connected →
  Continue, is the real `.declinedSharing` test, and I will predict it properly
  before you touch it.
- **If it does not exist** → `.declinedSharing` joins the other two as
  **device-unreachable on this rig**, discriminator 5 is closed as
  *unreachable rather than untested*, and no further device action is spent.

**Explicitly NOT the action:** `Revoke App Consent` (§8.2 — wrong mechanism, and
it writes to the server). **The Under-13 fixture stays as it is**, since it is
inert while a band row exists and would be the correct starting state for either
outcome.

---

# 9. DISCRIMINATOR 5 RE-EVALUATED FROM THE MEASURED UI. 2026-09-08 08:24

## 9.1 The real control exists, and it is per-app

Observed by the account holder:

```
Apple Account → Personal Information → Age Range for Apps
    Share with Apps : Ask First
    Études          : Shared
      → Age Range — Shared
        "Last shared: 18 or older on 7 September 2026"
```

**This is the user-facing surface Apple's documentation alludes to**, and it is
distinct from both the Sandbox developer fixture and `Revoke App Consent`.
`.declinedSharing` therefore moves from *"candidate route, unconfirmed"* to
**a reachable control**.

## 9.2 IT ALSO CORROBORATES §7.2, VISIBLY

**"Last shared: 18 or older on 7 September 2026" is still the ADULT value**,
while the Under-13 fixture is active and demonstrably returned an under-13 range
minutes ago.

So the **Sandbox developer fixture and the user-facing shared record are
decoupled**: the fixture governs what `requestAgeRange` returns without updating
the account-level record. That is exactly what §7.2 measured, now with a visible
corroboration rather than only an inference — and it further narrows the claim:
the fixture **overrides** the cached value; it does not **replace** it.

## 9.3 AGE CONFIRMATION IS IRRELEVANT — SOURCE-BACKED, NOT ASSUMED

The separate `Age Confirmation — Not Confirmed` control (the UK-law "Confirm You
Are 18+" flow) **must not be touched.**

`ageRangeDeclaration` — the field carrying `selfDeclared` / `confirmed` /
`guardianDeclared` — **appears nowhere in the app except the comment stating it
is never inspected** (`DeclaredAgeRangeService:30`). Every decision Études makes
comes from `range.lowerBound` and `range.upperBound` alone, via
`derive(lowerBound:upperBound:)`.

**So no evidence requires changing Age Confirmation, and it is a real Apple
Account change with real consequences. Leave it alone.** The account holder's
assumption was correct.

## 9.4 D5-BASE2 — 08:24:25 UTC

| measure | value |
|---|---|
| `auth.users` / `account_privacy` / `account_directory` | **2 / 1 / 1** |
| `band_updated_at` | **2026-09-07 13:40:16.675419** |
| `membership_binding.updated_at` | **2026-09-07 13:40:16.990315** |
| `membership_notification` | **104** |
| tokens `9c5385f6` / `dfaf8d18` | **42 / 248** |
| **`account_privacy_upsert_v1` (writer)** | **2** |
| `account_privacy_self_v1` | **45** |
| `account_directory` INSERT | **2795** |

## 9.5 ACTION 1 OF 2 — stop sharing, and nothing else

> **Apple Account → Personal Information → Age Range for Apps → Études.
> Use whatever control that screen offers to STOP SHARING the age range with
> Études. Change nothing else. Then report what the control was called and what
> the screen shows afterwards.**

**Do not tap Continue in Études yet. Do not touch `Share with Apps` (leave it on
Ask First). Do not touch Age Confirmation.**

**Predicted effect on the server: NONE.** This is an Apple Account setting; no
Études code runs. Every value in §9.4 must be unchanged when I re-measure —
**including `membership_notification` at 104**, which is the tripwire proving no
`RESCIND_CONSENT` was fired by mistake.

**Reversibility, stated plainly:** this changes a real privacy setting on the
primary Apple Account, scoped to Études alone. With `Share with Apps` on **Ask
First**, the next request should prompt again, so re-sharing restores it. It is
reversible, but it is not nothing, and it is the only way to reach the branch.

## 9.6 WHAT ACTION 2 WILL BE, so the destination is known

Explore Connected → **Continue**, with predictions recorded first. Two outcomes,
both informative:

- **Apple returns `.declinedSharing`** → alert *"Études needs Apple to share your
  age range before Connected can be set up…"* → **discriminator 5's strongest
  branch PASSES**, with the same no-server-contact proof as discriminator 4.
- **Apple re-prompts** (consistent with *Ask First*) → decline on the sheet to
  reach the same place. **If the prompt is accepted instead**, the Under-13
  fixture is still active, so the result is `.ineligible` — the already-passed
  refusal, harmless, and the test can simply be repeated.

**The other two branches remain classified device-unreachable (§8.3) and are not
being manufactured.**
