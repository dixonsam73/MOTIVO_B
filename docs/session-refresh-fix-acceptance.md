# SESSION MANAGEMENT FIX — ACCEPTANCE. 2026-09-07

Implements handover §7/§7.1/§7.1a and the §8 regression coverage. **Client only;
zero production mutation; no schema, RPC or Edge Function change.**

**NOT DEVICE-VERIFIED.** Debug and Release both compile clean, `MOTIVOTests` is
**81 passed / 0 failed** (65 before, +16 here) and the new structural suite is
**27/27** — but every one of those is a simulator or a source-text result. Per
handover §10 this must be rebuilt onto Device A and the Connected identity
restored before CP-3 device acceptance resumes. **Do not close on this file.**

---

## 1. What was wrong — two independent defects on one line

**(i) THE FEEDBACK LOOP.** `refreshSupabaseSession` rotated the refresh token
**unconditionally**. A successful refresh schedules directory hydration; CP-3
made hydration read `account_privacy`; that read preflights through
`ensureValidBackendSession`, which lands back in the refresh. Measured on
Device A: **34 rotations in 20.5 s**. It closed only for the fresh identity
because `lastHydratedDirectoryUserID` is assigned **only in the row-exists
branch**, and `96a3cb7b` has no directory row.

**THE MEASURED LOOP ENTRY IS `AuthManager:595`, NOT `:611`.** The handover named
`AccountPrivacyService.fetchSelf` at `:611` as the edge CP-3 added. That call is
real, but it sits in the **row-exists** branch of
`hydrateDirectoryStateFromBackend` — and the identity that actually looped has
**no directory row**, so it takes the `guard let row else` branch and never
reaches `:611` at all. The edge it does take is:

```
hydrateDirectoryStateFromBackend  (row == nil)
  └─ ensureAgeBandEstablished          AuthManager:595
       └─ AccountPrivacyService.fetchSelf   AuthManager:177
            └─ preflight → ensureValidBackendSession → refreshSupabaseSession
```

**Both doors reach the same loop, so the diagnosis and the fix are unaffected**
— which is precisely why the wrong one could stand unchallenged. Recorded
because a future reader checking `:611` on a no-row identity would find the
cited call unreachable and could conclude the loop was never real.

**(ii) THE CONTENT-LOSS DEFECT, WHICH IS THE WORSE ONE.** The failure branch was
a **boolean** — offline, or `signOut()`. `signOut()` removes the per-user
attachment **title** mappings: content the user typed. So a *superseded* refresh
token — a lost race, not a dead credential — could destroy a live session and
user content. `AuthManager` already stated the rule ~100 lines below the
violation, in `clearConnectedIdentity`'s own doc comment: *"PREFER THIS OVER
`signOut()` FOR ANY NON-USER-INITIATED WITHDRAWAL."*

---

## 2. What was built

| | |
|---|---|
| `SessionRefreshPolicy.swift` | New. **Pure** — no Keychain, network, `UserDefaults` or Supabase types, asserted (S-11) |
| **(A)** `shouldRefresh(accessTokenExpiry:now:skew:)` | A still-valid token is not rotated. Unknown expiry → refresh (fails toward a redundant round trip, never a dead token) |
| **(B)** `refreshFailureDisposition` | **Four-way**: `ignore` · `recoverWithNewerSession` · `withdrawIdentity` · `terminal` |
| **(C)** `directoryHydrationInFlightUserID` | Re-entrancy guard. Cuts the cycle's edge |
| Five `signOut()` calls → `clearConnectedIdentity` | `self.signOut()` calls in `AuthManager`: **5 → 0** |

**Recovery is conditional on evidence, never on hope.** A concurrent refresh that
won the race consumed our token and wrote its own, so a persisted refresh token
that is **no longer the one we presented**, whose access token is **usable now**,
is positive evidence. Absent that, the disposition is `withdrawIdentity` — never
success, because reporting success with no valid session is the zombie state
`signOut()` was originally written to prevent.

---

## 3. TWO CORRECTIONS TO THE HANDOVER

**(a) §7's "(A) alone fixes both symptoms … (C) unnecessary" IS WRONG.** The gate
removes **rotation** from the loop; it does not remove the **loop**. A re-entrant
pass still returns success and re-schedules hydration, and the scheduler used to
*cancel the running task and start another* — so it would spin without rotating,
and keep producing the "Already Used" collisions. **(C) is required, not
optional.** It is also the more robust cut: it does not depend on which session
helper the privacy preflight happens to call, so re-pointing that preflight
cannot silently restore the loop.

**(b) A DEFECT THE GATE ITSELF INTRODUCED, caught on review rather than by a
test.** A token can be **rejected while unexpired** — server-side revocation, a
signing-key rotation, clock skew. The 401 auth challenge fires precisely then,
and the gate would have seen an unexpired token, rotated nothing, and handed the
retry **the very token that was refused**: a guaranteed second 401 and the 401
recovery path silently dead. `onAuthChallenge` now passes `force: true`, which
also bypasses in-flight coalescing (a coalesced attempt may have begun *before*
the rejection, so its success would not clear the challenge). Pinned by S-8b/c/d.

---

## 4. Evidence

**Non-vacuity, measured not asserted.** S-1 counts `self.signOut()` in
`AuthManager`: **5 against the pre-fix tree at HEAD, 0 after.** Comments are
stripped before counting — this file's subject is a function whose doc comment
names `signOut()` four times, which is exactly how U5d lost three assertions.

**Neighbouring suite unmoved, measured by stashing.** `u5-client-acceptance`
reports **28 passed / 2 failed identically with and without this change** (same
two assertions, same counts) — a pre-existing pinning failure, not a regression.

**Two `PublishServiceConnectedDeleteTests` intermittently `XCTSkip`** when the
local Supabase stack is unreachable. Observed 79/0/2 once and 81/0/0 on the
re-run. Environmental; this change touches no local-stack path.

---

## 5. What is NOT established

- **Nothing is device-verified.** The terminal failure of §5 was never observed
  directly — its confirming log line is `#if DEBUG` and Device A runs Release —
  so the "Already Used" attribution remains **best-fit**, exactly as the handover
  scored it. This fix is correct for *all four* dispositions, which is why it does
  not depend on that attribution being right.
- **Finding A** (`AgeBandRecoveryCoordinator`) is still device-unverified.
- **A hung hydration now blocks re-scheduling for that identity** until the task
  exits or the identity is withdrawn, where before a re-schedule would cancel and
  restart. Bounded by `URLSession`'s own timeouts, and stated rather than glossed.
