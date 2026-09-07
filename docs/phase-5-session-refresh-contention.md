# SESSION REFRESH CONTENTION — DIAGNOSIS. 2026-09-07

**BLOCKING further CP-3 physical-device acceptance.** Another run while the
session can self-delete would contaminate the evidence.

**Diagnosis only. No session-management behaviour changed.**

---

## 1. CALLERS

| helper | callers |
|---|---|
| **`ensureValidSession`** (signs out on failure) | `MOTIVOApp:300` **launch** · `MOTIVOApp:393` **foreground** · `AuthManager:304` **network auth-challenge** |
| **`ensureValidBackendSession`** (F6; does not sign out) | `MembershipBindingService:65` · `MembershipAttestationService:116` · **`AccountPrivacyService:94` (CP-3)** · `AuthManager:983` (the deletion/revocation alias) |
| **`refreshSupabaseSession`** | private; reached only from the two helpers above |

**No other direct Supabase refresh path exists** — `refreshSession` is called in
exactly one place.

## 2. OVERLAP

Launch fires `ensureValidSession` **and** attestation; foreground fires
`ensureValidSession`, attestation, and — since CP-3 — **age-band recovery**.
Hydration calls `AccountPrivacyService.fetchSelf`; the join path calls
`upsertBand` and `ensureBindingToken`. **All of these can be in flight within the
same second of a foreground.**

## 3. SERIALIZATION — IT EXISTS, AND IT WORKS

Both helpers coalesce through one shared `sessionRefreshInFlight`:

```swift
if let existing = sessionRefreshInFlight { return await existing.value }
let task = Task { await self.refreshSupabaseSession(reason: reason) }
sessionRefreshInFlight = task
```

**The assignment precedes the `await`, and `AuthManager` is `@MainActor`**, so a
later caller joins the in-flight task rather than starting a second refresh.

> **So the 37 rotations were SEQUENTIAL, not concurrent. The count is not
> evidence of a coalescing failure**, and I am not treating it as one.

## 4. THE ACTUAL DEFECT — REFRESH IS UNCONDITIONAL

**`refreshSupabaseSession` never checks whether the existing access token is
still valid.** It reads the refresh token and calls
`supabase.auth.refreshSession(refreshToken:)` **every time**, and Supabase
**rotates and revokes on every use**. It also constructs a **fresh
`SupabaseClient` per call**, so there is no session caching either.

**Answering (4) directly: YES — `ensureValidBackendSession` rotates the token on
every call.** Its "does not sign out" description is about the *failure branch*,
not about rotation. **The name invites exactly the wrong inference**, and I made
it myself when I chose that helper for CP-3 believing it was the cheap one.

**So every RPC burns one refresh token.** One rotation per ~14 seconds over the
observed window is consistent with ordinary app activity under this design.

## 5. HOW "ALREADY USED" REACHES `signOut()`

```
refreshSession throws
  └─ catch
       ├─ isOfflineOrTransientNetworkError(error)?  →  return false   (no sign-out)
       └─ otherwise                                 →  signOut()      ← DESTRUCTIVE
```

**`isOfflineOrTransientNetworkError` only recognises `NSURLErrorDomain` codes.**
A `400 Invalid Refresh Token: Already Used` is an **HTTP/auth** error, not a
`URLError` — so it falls to the `else` and **deletes the local identity.**

## 6. SHOULD IT BE TERMINAL? **NO.**

**"Already Used" is close to the opposite of an invalid credential.** It means a
rotation *succeeded* — the session is alive; this caller merely presented a
superseded token. Treating it as authentication invalidation **destroys a valid
session.**

**And true concurrency is not required to produce it.** The rotation happens
server-side *before* the new token is written to the Keychain. **Any interruption
between those two steps — process death, suspension, a force-quit — leaves the
client holding a token the server has already consumed.** The next refresh then
returns "Already Used" **permanently**, because the stored token can never
succeed again.

**That fits the observed evidence exactly:** 37 rotations, a force-quit during
that window, then a hard stop at 13:44:08 and Solo from then on — with the
*server* session still intact.

**Not proven**, because the confirming log line is `#if DEBUG` and Device A runs
Release. **Stated as the leading mechanism, not a conclusion.**

## 7. CP-3's CONTRIBUTION — FREQUENCY, NOT CAUSE

**CP-3 materially increases rotation frequency.** It added
`AccountPrivacyService.preflight` to **every** privacy RPC (`fetchSelf`,
`upsertBand`, both setters), a `fetchSelf` in hydration, and another in the
recovery coordinator — each forcing a rotation.

**But the defect is pre-existing and would fail without CP-3:** unconditional
rotation, non-atomic persistence, and terminal treatment of a non-terminal error.
**CP-3 widened the window; it did not create it.**

## 8. EXISTING COVERAGE — NONE

**No test file references `refreshSession`, `ensureValidSession`,
`ensureValidBackendSession`, `signOut` or `refreshToken`.** The path that can
delete a member's local identity has **zero** regression coverage.

## 9. SMALLEST DETERMINISTIC REGRESSION TEST

**The failure is a classification decision, so make that decision pure and test
it.** No network, no Supabase, no device.

1. **`AuthManager.shouldSignOut(afterRefreshFailure:) -> Bool`** — extract the
   existing `isOfflineOrTransientNetworkError` branch. Assert:
   - a `URLError.notConnectedToInternet` → **false** (already true today);
   - **a 400 "Invalid Refresh Token: Already Used" → FALSE** — *fails today*, and
     is the whole bug;
   - a genuine `401 invalid_grant` / revoked credential → **true**.
2. **`AuthManager.shouldRefresh(accessTokenExpiry:now:skew:) -> Bool`** — a pure
   staleness gate. Assert a token valid for another 10 minutes → **false**, so an
   RPC does not rotate a live token.

**Test 1 alone reproduces the mechanism at its decision point** and would have
failed before the observation was ever made.

## 10. PROPOSED FIX — NOT IMPLEMENTED

In order of value:

1. **Stop rotating a valid token.** Gate `refreshSupabaseSession` on actual
   expiry with a skew. This removes most of the churn — including CP-3's.
2. **Reclassify "already used"/400-refresh as NON-terminal.** Re-read the
   Keychain and retry **once**; sign out only if the re-read token also fails.
   **A superseded token must never delete an identity.**
3. **Consider persisting before returning**, so an interruption cannot strand a
   consumed token — narrows but does not close the non-atomic window.
4. **Rename or re-document `ensureValidBackendSession`**, whose name implies
   cheapness and whose behaviour is a full rotation.

**Nothing above is implemented.** §9's two pure functions should land **with**
the fix, not after it.

## 11. STATUS

Mechanism and ownership established: **session management, pre-existing, with
CP-3 as an aggravating factor.** **CP-3 device acceptance stays BLOCKED.**

Server identity `96a3cb7b`, its `band_18_plus` row and Samuel are untouched. No
Restore Purchases, repurchase, deletion or manual repair was performed.
