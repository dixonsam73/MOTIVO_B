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

A **second, genuinely fresh identity** (a different Apple ID, so SIWA returns a
new `sub`) carrying a **teen** Age Assurance fixture. That single fixture would
make 1, 2, 3 and the recovery half of 6 achievable in one run, and — **only if
additionally Production-entitled** — discriminator 7.

**That is fixture manufacture and account creation, which the current
instruction excludes.** Recorded so the cost is visible when it is next weighed,
not as a recommendation.
