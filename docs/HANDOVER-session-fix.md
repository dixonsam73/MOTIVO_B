# HANDOVER — resume immediately before the session-management fix

**Nothing is being implemented until this is read.** Written 2026-09-07.

---

## 1. REPO / REMOTE

Branch **`feature/solo-connected`** · HEAD **`0a08588`** · **ahead 2, behind 0** ·
tree clean.

**Two unpushed commits** (Samuel pushes from his own shell — `git push` fails from
this sandbox for environment reasons, not credentials; `fetch` works):

- `0aae02c` chronology correction
- `0a08588` feedback-loop mechanism

## 2. PRODUCTION STATE — measured 19:00 UTC

`auth.users` **2** — `1fbf664a` (**Samuel**) and `96a3cb7b` (**the fresh CP-3
identity**) · `account_privacy` **1** (`band_18_plus`, `96a3cb7b`) ·
`account_directory` **1** (Samuel only) · `posts` **6** · `post_comments` **1** ·
`follows` **0** · `membership` **1** (Sandbox, renewing, `renewal_date`
19:13:57) · `membership_binding` **1** · `shadow_enforcement_stat` **34**.

**Device A** (SD beta burner, iPhone 16e, iOS 26.6.1): Release build `f27e715`
installed; **stuck in Solo** because the local identity was signed out. Sandbox
Apple Account `sdsongsltd+devicec@gmail.com` signed in; **its Age Assurance
fixture is currently UNSET** and must be re-set before any teen/under-13 work.
**Device B untouched.**

## 3. CP-3 HARDWARE ACCEPTANCE — WHAT IS AND IS NOT ESTABLISHED

**Established:** `requestAgeRange` invoked on real hardware; Apple's system UI
appears on Continue (**10:46 run**); **nothing exists while SIWA is pending**
(interleaved measurement at a held pause); `requestAgeRange` **precedes SIWA**
(structural — SIWA is reachable only via `case .band`); bounds derivation →
`band_18_plus` on a genuinely new identity; **adult defaults** with
`lookup_changed_at` and `follow_requests_changed_at` both **NULL**; purchase
**bound at source** (`binding_method = 'purchase'`); and — most valuable —
**a band-write failure SUPPRESSES directory publication, observed twice under a
genuine failure, with no orphan directory row ever created.**

**NOT established:** **directory-publication ordering** (band → directory).
**Blocked, not failed:** `scheduleDirectoryHydrationIfNeeded` guards on
`isConnected`, and the client is in Solo, so the publish is never attempted.
**Teen / under-13 / decline / recovery discriminators: not started.**

**Apple caches its age answer** and re-prompts only on the declaration
anniversary. *"Apple's UI precedes SIWA"* is therefore unobservable once cached;
*"`requestAgeRange` precedes SIWA"* is the claim that matters. **Do not merge
them.**

## 4. FINDING A — fixed locally, NOT device-verified

`identityWithoutBand` had **no automatic recovery**: `pendingAgeBand` is in-memory
and no launch/foreground retry existed, contrary to the design.

**Fixed** by `AgeBandRecoveryCoordinator` (launch + every foreground): re-acquires
the range from Apple rather than persisting it (**no band may be invented after
process death**), only `.band` establishes, single-flight + 60 s in-memory
cooldown, and an existing band short-circuits **before** Apple is called.

**Debug + Release build clean; `MOTIVOTests` 65 passed / 0 failed**, incl. 5
recovery tests. **Device verification pending — do not close CP-3 on unit tests.**

## 5. FINDING B — FINAL MECHANISM (this is the one to fix)

**The app is in Solo because `hasConnectedIdentity` is FALSE** — `resolve()` fails
at that guard and never reaches entitlement. Established from the device UI:
`destructiveActionTitle` reads identity directly and showed *"Erase All Études
Data"*. Apple Settings and our server both said **entitled**; both are irrelevant.

**The loop:**

```
refreshSupabaseSession (SUCCESS)
  └─ scheduleDirectoryHydrationIfNeeded
       └─ hydrateDirectoryStateFromBackend
            └─ AccountPrivacyService.fetchSelf        ← ADDED BY CP-3 (AuthManager:611)
                 └─ preflight → ensureValidBackendSession
                      └─ refreshSupabaseSession (UNCONDITIONAL — always rotates)
                           └─ success → schedules hydration again …
```

**Why it closes only for the fresh identity:**
`scheduleDirectoryHydrationIfNeeded` short-circuits on
`lastHydratedDirectoryUserID == bid`, and that field is assigned **only in the
row-exists branch**. `96a3cb7b` has **no directory row**, so it is never set and
**every refresh restarts full hydration.**

**Measured:** **34 rotations in 20.5 s** (13:43:47–13:44:08), gaps 0.1–0.6 s.
Token **#38 unrevoked**; no rows after — a **failed** refresh creates no row.

**Not the loop, and proven so:** **single-flight coalescing WORKS** (shared
`sessionRefreshInFlight`, assigned before the `await`; the burst is *sequential*,
not concurrent), and **the 401 retry is bounded** (401 only since C-57, refresh
once, retry once, retry not re-challenged; bearer token *is* updated after
refresh).

**Remaining uncertainty:** the final failing refresh is **not observed** — the
confirming log line is `#if DEBUG` and Device A runs **Release**. Best fit is an
"Already Used" collision (hydration cancels the prior task; a cancelled task's
in-flight refresh may still have consumed a token) reaching the `else` branch —
`isOfflineOrTransientNetworkError` only matches `NSURLErrorDomain` — and calling
**`signOut()`**. **Three other paths reach the same `signOut()` and leave no row;
none is excluded.** So: mechanism of the *loop* is proven; the *terminal failure*
is best-fit.

## 6. SUPERSEDED — MUST NOT BECOME STATE AGAIN

| ❌ superseded | why |
|---|---|
| *"37 rotations in 9 minutes"* / **ordinary churn at ~1 per 14 s** | Artefact: I took the window from the `auth.sessions` row, never the token timestamps. Real signature is **34 in 20.5 s**. My "consistent with ordinary activity" was wrong **~24×** |
| *"CP-3 merely increased call volume / rotation frequency"* | Right that CP-3 is implicated, **wrong mechanism**. It **closed a feedback loop** |
| *"Only 3 of 38 tokens are CP-3's — CP-3 withdrawn"* | Wrong. Reached by **time-window attribution**, which is not causal attribution |
| *"Purchase/attestation 401 retry loop"* | **False.** The retry is bounded and the bearer token is refreshed |
| *"Sandbox subscription expired"* | **False.** It renewed during the investigation |
| *"Sandbox Apple Account signed out"* | **False.** Signed in throughout; Settings shows the subscription active |
| *"CP-3 ruled out"* (my earliest claim) | Too broad — it ruled out two *mechanisms*, not the component |

## 7. PROPOSED MINIMAL FIX — **NOT IMPLEMENTED**

**(A) Gate `refreshSupabaseSession` on actual token expiry** (return early if the
access token is valid beyond a skew). **This alone fixes both symptoms**: it ends
unconditional rotation *and* starves the loop, because a re-entrant pass finds a
valid token and rotates nothing.

**(B) Reclassify "Already Used" / 400-refresh as NON-terminal** — re-read the
Keychain and retry **once**; sign out only if the re-read token also fails.
**A superseded token must never delete an identity.**

**Optional (C):** stop scheduling hydration from the refresh success path, or make
`AuthManager:611` non-refreshing. (A) makes this unnecessary; it removes the
coupling.

## 8. REQUIRED REGRESSION TESTS (land WITH the fix; coverage today is ZERO)

1. **`shouldSignOut(afterRefreshFailure:)`** — "Already Used" 400 → **false**
   (*fails today; this is the bug*); `URLError.notConnectedToInternet` → false;
   genuine `invalid_grant` → true.
2. **`shouldRefresh(accessTokenExpiry:now:skew:)`** — still-valid token → **false**.
3. **Re-entrancy** — a refresh whose success schedules hydration must produce
   **no second rotation**.

## 9. CONSTRAINTS — PROHIBITED

**Do not** delete/reset identity `96a3cb7b` or its `band_18_plus` row · **do not**
touch **Samuel** (`1fbf664a`) · **do not** run Restore Purchases, repurchase, or
manually repair membership · **no production mutation** · **Device B untouched** ·
**no Apple Account changes**; keep `sdsongsltd+devicec@gmail.com`.

## 10. BEFORE CP-3 DEVICE ACCEPTANCE RESUMES

1. Land §7 with §8's tests; Debug + Release clean; `MOTIVOTests` green.
2. Rebuild, reinstall on Device A, **restore the Connected identity** by signing
   in again (SIWA re-authenticates `96a3cb7b`; its band already exists, so
   recovery should short-circuit).
3. **Re-set the Age Assurance fixture** — currently unset.
4. Then complete **directory-publication ordering**, and only after that proceed
   to teen / under-13 / decline / recovery.

**Do not run device acceptance before the fix** — a session that can self-delete
contaminates the evidence.
