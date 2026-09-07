# FINDING B — MECHANISM ESTABLISHED. 2026-09-07

**It is NOT a StoreKit or entitlement problem.** It is loss of the **local
Connected identity**.

---

## 1. THE MEASURED CHAIN

`ProductionAppModeActivation.resolve` returns `.solo` if **either** guard fails:

```swift
guard BackendConfig.isConfigured else { return .solo }
guard isEntitled            else { return .solo }
guard auth.hasConnectedIdentity else { return .solo }   ← FAILS HERE
```

**`hasConnectedIdentity` is FALSE, established from the device UI rather than
inferred:** `destructiveActionTitle` reads
`auth.hasConnectedIdentity ? "Delete Account & All Études Data" : "Erase All Études Data"`,
and Device A shows **"Erase All Études Data"**.

**The missing Account ID row was NOT usable evidence** — it is gated on
`canShowConnectedAccountManagement`, which is `mode == .connected`, so it merely
restates the symptom. The destructive title is the only surface that reads the
identity directly.

## 2. WHAT THIS DISPLACES

| surface | says | relevance |
|---|---|---|
| Apple Settings → Sandbox Subscriptions | **active, renews 7 Sept, 30-min rate** | **irrelevant** |
| our server `membership` | active, `renewal_date` 14:13:57 → **14:43:57**, renewing | **irrelevant** |
| client `resolve()` | **fails on identity, before entitlement** | decisive |

**Both "authorities" were right and neither was consulted**, because the guard
that failed sits earlier. **The subscription had not expired** — it renewed
during the investigation, which is why Sandbox timing is excluded as the cause.

## 3. THE PROXIMATE CAUSE

The identity was **cleared locally by `signOut()`**. `refreshSupabaseSession`
calls `signOut()` on a **non-transient** refresh failure — it explicitly spares
offline/transient errors (`isOfflineOrTransientNetworkError`), but **not** a
`400 Invalid Refresh Token: Already Used`.

**Measured symptom, for identity `96a3cb7b`:**

| | |
|---|---|
| sessions | **1** |
| refresh tokens | **38** |
| **revoked** | **37** |
| window | 13:34:54 → **13:44:08**, then nothing |

**37 rotations in ~9 minutes, stopping dead at the moment the app went
permanently Solo.** Supabase rotates and revokes on every use, so this is heavy
contention on a single-use rotating token.

**Causation is NOT inferred from the count.** The count is the observed symptom;
the mechanism is the `signOut()` on a non-transient refresh failure, and the two
are consistent in shape and timing. **Whether a collision actually produced the
terminal failure is not yet proven** — see §5.

## 4. CORRECTION — CP-3 WAS NOT RULED OUT, AND I SAID IT WAS

**I previously recorded "RULED OUT — CP-3's changes". That was TOO BROAD and is
withdrawn.**

What I actually ruled out was **two specific mechanisms**: that
`connectedSetupIncomplete` is consumed outside `AuthManager` (it is not), and
that the early return changes `backendBootstrapState`'s value (it does not).
**Both remain true.**

**What I did not consider is that CP-3 ADDED CALLERS TO THE SESSION-REFRESH
PATH.** `AccountPrivacyService.preflight` calls `ensureValidBackendSession` on
**every** RPC — `fetchSelf`, `upsertBand`, both setters — and `AuthManager`'s
hydration now calls `fetchSelf`, as does the recovery coordinator.

**So CP-3 is a plausible contributor to the contention and cannot be excluded.**
**It is equally not established as the cause:** 37 rotations far exceeds what
CP-3's handful of calls would produce alone, which points at pre-existing churn
that CP-3 may have aggravated rather than created.

**Ruling out two mechanisms is not ruling out a component.** That is the error,
and it is the same shape as every over-determination trap in this project.

## 5. THE OBSERVABILITY LIMIT

The decisive evidence would be
`[Auth] refreshSupabaseSession FAILED … signing out` — **but that line is
`#if DEBUG` only, and Device A runs RELEASE.** It cannot be captured on the only
build that can execute this path.

**This is CLAUDE.md's own recorded lesson repeating:** *"`#if DEBUG` diagnostics
do not exist in the only build that can execute these paths."*

## 6. OWNERSHIP AND STATUS

**Owner: session management** — `refreshSupabaseSession` / `ensureValidSession`,
pre-existing code, with CP-3's added callers an **open contributory question**.
**Not StoreKit. Not entitlement. Not CP-3's privacy model.**

**No fix proposed here.** **Restore Purchases was deliberately NOT run** — it
restores purchases, not identities, and would have perturbed the state while
telling us nothing.

**Server state intact:** identity `96a3cb7b` and its `band_18_plus` row survive;
only the **local** session was lost. Samuel untouched. No production mutation.
