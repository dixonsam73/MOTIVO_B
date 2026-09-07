# HANDOVER — resume immediately before the session-management fix

**Nothing is being implemented until this is read.** Written 2026-09-07.

---

## 1. REPO / REMOTE

Branch **`feature/solo-connected`** · origin at **`0a08588`** · tree clean.

**HEAD is this handover's own most recent commit**, so do not expect the sha
below to be the tip — check with `git log --oneline origin/feature/solo-connected..HEAD`
rather than trusting this line. **This file cannot record its own commit sha, and
a handover that asserts a repository fact is not evidence of that fact** (C-52).

**Unpushed at the time of writing: the two handover commits** — `c95ee42` (this
document) and the reconciliation revision that follows it. Everything else
(`0aae02c` chronology correction, `0a08588` feedback-loop mechanism) is **already
on origin**.

Samuel pushes from his own shell — `git push` fails from this sandbox for
environment reasons, not credentials; `fetch` works.

**No source file has been modified.** Every commit in this series is
documentation. The implementation described below has NOT begun.

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

**(B) Treat "Already Used" as a RECONCILIATION CONDITION** — **not automatic
success, and not automatic sign-out.** Re-read persisted session state and
recover **only if a newer usable token/session is actually present**.

**Both failure directions are real, and the earlier phrasing only guarded one:**

- **automatic sign-out** destroys a live session (the observed defect);
- **automatic success** leaves the client believing it is authenticated with no
  valid session — the **zombie state** `signOut()` was originally written to
  prevent. Recovery must be conditional on *evidence*, not on a retry hopefully
  succeeding.

**When NO newer token is present, do NOT call `signOut()`.** Use
**`clearConnectedIdentity`**.

> **`signOut()` is `clearConnectedIdentity` PLUS deletion of the per-user
> attachment *title* mappings (`AuthManager:880-883`) — content the user typed.**
> `AppleCredentialStateMonitor` already refuses `signOut()` for exactly this
> reason, citing **invariant 1**: *the local journal is never deleted by any
> Connected action.*
>
> **So the current refresh-failure path can cause SILENT LOSS OF USER-TYPED
> CONTENT in response to a superseded token.** That is a second, independent
> defect on the same line, and it is worse than the sign-out itself. The
> distinction already exists in the codebase as a deliberate primitive — the
> refresh path simply does not use it.

**A superseded token must never delete an identity, and must never delete
content.**

**Optional (C):** stop scheduling hydration from the refresh success path, or make
`AuthManager:611` non-refreshing. (A) makes this unnecessary; it removes the
coupling.

## 8. REQUIRED REGRESSION TESTS (land WITH the fix; coverage today is ZERO)

1. **`refreshFailureDisposition(_:) -> {retryWithNewerToken, withdrawIdentity, ignore}`**
   — a three-way classification, not a boolean, because the boolean is what
   forced the false choice between "carry on" and "destroy everything":
   - "Already Used" 400 → **`retryWithNewerToken`** (*fails today; this is the bug*)
   - `URLError.notConnectedToInternet` → **`ignore`**
   - genuine `invalid_grant` / revoked → **`withdrawIdentity`**
2. **No path from a refresh failure calls `signOut()`** — assert
   `clearConnectedIdentity` is the withdrawal primitive, so attachment titles
   survive (invariant 1).
3. **`shouldRefresh(accessTokenExpiry:now:skew:)`** — still-valid token → **false**.
4. **Re-entrancy** — a refresh whose success schedules hydration must produce
   **no second rotation**.
5. **Reconciliation** — "Already Used" with **no** newer persisted token must
   **not** report success, and must **not** destroy content.

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
