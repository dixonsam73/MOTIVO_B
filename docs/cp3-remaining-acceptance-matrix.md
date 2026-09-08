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
