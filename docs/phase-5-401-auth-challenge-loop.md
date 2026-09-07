# THE REFRESH BURST — MECHANISM. 2026-09-07

**Diagnosis only. Nothing implemented.** It is **not** a 401 retry loop. It is a
**feedback loop between refresh and hydration, which CP-3 closed.**

---

## 1. PROVEN SOURCE BEHAVIOUR

### 1a. The 401 retry is strictly bounded — it is NOT the cause

`NetworkManager.request`: one attempt; on **401 only** (403 was removed by C-57)
call `onAuthChallenge` → `ensureValidSession` → **retry exactly once**. **The
retry is not re-challenged.** So **one request can cause at most one refresh**,
and no per-request loop exists.

**The bearer token IS updated after a refresh** (`setBearerToken(accessToken)`),
and headers are built per request, so the retry uses the new token. **Both
hypotheses I brought to this investigation are therefore false.**

### 1b. A SUCCESSFUL refresh schedules more authenticated work

```swift
// refreshSupabaseSession, on success:
NetworkManager.shared.setBearerToken(accessToken)
await MainActor.run {
    self.scheduleDirectoryHydrationIfNeeded(reason: "refreshSupabaseSession")
    self.scheduleAccountIDBackfillIfNeeded(reason: "refreshSupabaseSession")
}
```

### 1c. Before CP-3 that work could not refresh — after CP-3 it can

**Measured:** `AccountDirectoryService.fetchSelfRow` and `upsertSelfRowOnce` call
`NetworkManager` **directly** and contain **zero** `ensureValidSession` /
`ensureValidBackendSession` calls. **The loop did not close.**

**CP-3 inserted `AccountPrivacyService.fetchSelf` at `AuthManager:611`, inside
`hydrateDirectoryStateFromBackend`.** That call goes through
`AccountPrivacyService.preflight` → **`ensureValidBackendSession`** →
`refreshSupabaseSession`.

```
refreshSupabaseSession (success)
   └─ scheduleDirectoryHydrationIfNeeded
        └─ hydrateDirectoryStateFromBackend
             └─ AccountPrivacyService.fetchSelf        ← ADDED BY CP-3
                  └─ preflight → ensureValidBackendSession
                       └─ refreshSupabaseSession (success)
                            └─ … repeats
```

**Nothing bounds it.** Refresh is **unconditional**, so each pass genuinely
rotates. Single-flight coalescing does **not** help: these calls are
**sequential**, not concurrent, so each finds the slot empty.

### 1d. Why the short-circuit never engaged

`scheduleDirectoryHydrationIfNeeded` short-circuits when
`lastHydratedDirectoryUserID == bid`. That field is assigned **only in the
row-exists branch** of hydration. **Our identity had no directory row**, so it was
never set — **every refresh restarted full hydration.** The loop is therefore
specific to the **new-identity / no-directory-row** case, which is exactly the
state under test.

## 2. MEASURED TOKEN CHRONOLOGY

| tokens | window | duration |
|---|---|---|
| 1 | 13:34:54 | — |
| 3 | 13:40:15–13:40:16 | 1.2 s |
| **34** | **13:43:47–13:44:08** | **20.5 s** |

Last token **13:44:08 — UNREVOKED**; no rows after. Inter-token gaps in the burst
are **0.1–0.6 s**, consistent with refresh + one authenticated round trip.

## 3. BEST-FIT MECHANISM

**The burst is §1c's loop**, triggered when purchase/attestation activity caused a
refresh, which scheduled hydration, whose CP-3 privacy fetch refreshed again.

It terminated at 13:44:08 when a refresh **failed**. A failed refresh **creates no
token row**, which is why the record stops rather than tapering. The most likely
failure is an **"Already Used"** collision — `scheduleDirectoryHydrationIfNeeded`
**cancels the previous hydration task** on each pass, and a cancelled task's
in-flight refresh can still have consumed a token. That reaches the
`else` branch (only `NSURLErrorDomain` counts as transient) and calls
**`signOut()`**, which is exactly the observed terminal state.

**Token #38 being unrevoked fits a client stranded on #37**: the server minted
#38, but if the cancelled/racing path never persisted it, the Keychain still
holds the revoked #37 and every later refresh fails permanently.

## 4. REMAINING UNCERTAINTY

**The failing refresh is not directly observed.** The confirming line is
`#if DEBUG` and Device A runs **Release** — CLAUDE.md's own recorded lesson.

**Other mechanisms producing the same terminal shape**, not excluded:
`signOut()` from `BackendConfig` momentarily unconfigured; a missing refresh
token read while `isSigningIn` was false; or a non-transient non-auth error from
Supabase. **All three end in the same `signOut()` and leave no row.**

**So §3 is best-fit, not proven.** What *is* proven is §1: the loop is
structurally present, unbounded, and CP-3 closed it.

## 5. CORRECTING MY OWN CORRECTION

**I have now been wrong twice in opposite directions, and both are recorded.**

1. *"CP-3 materially increases rotation frequency"* — right conclusion, **wrong
   mechanism** (I said call volume).
2. *"Only 3 of 38 tokens are attributable to CP-3; withdrawn"* — **wrong
   conclusion**, reached by attributing the burst to the purchase path because it
   fell in that time window. **Time-window attribution is not causal
   attribution**, and the burst is the loop CP-3 closed.

**The correct statement: CP-3 did not add load — it closed a feedback loop.** The
loop needs three pre-existing conditions (refresh schedules hydration; refresh is
unconditional; the short-circuit never engages for a row-less identity) **and one
CP-3 edit**. Ownership is **shared**, and the CP-3 edit is the removable half.

## 6. SMALLEST COMBINED FIX — PROPOSED, NOT IMPLEMENTED

Two changes address both the needless rotation and the pathological behaviour:

**(A) Gate refresh on actual expiry.** Return early when the current access token
is valid beyond a skew.
*Kills unconditional rotation, and **breaks the loop by starving it** — a
re-entrant pass finds a valid token and performs no rotation. **One change fixes
both symptoms.***

**(B) Reclassify "Already Used" / 400-refresh as NON-terminal.** Re-read the
Keychain and retry once; sign out only if the re-read token also fails.
***A superseded token must never delete an identity.***

**Optional third, smaller:** stop scheduling hydration from inside the refresh
success path, or make `AuthManager:611`'s privacy fetch non-refreshing. (A) makes
this unnecessary for the loop, but it removes the coupling entirely.

### Tests to land WITH the fix

- **`shouldSignOut(afterRefreshFailure:)`** — "Already Used" 400 → **false**
  (*fails today; this is the bug*); `URLError.notConnectedToInternet` → false;
  genuine `invalid_grant` → true.
- **`shouldRefresh(accessTokenExpiry:now:skew:)`** — valid token → **false**.
- **A re-entrancy test**: with (A) in place, a refresh whose success schedules
  hydration must not produce a second rotation.

## 7. STATUS

**CP-3 device acceptance remains BLOCKED.** Identity `96a3cb7b`, its
`band_18_plus` row and Samuel are untouched. No production mutation.
