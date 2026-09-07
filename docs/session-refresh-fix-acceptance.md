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

---

# 6. THE VALID-TOKEN HYDRATION FIX — 2026-09-08

## 6.1 What was wrong

§7.2/§9 of `docs/cp3-gate-c-directory-predictions.md` records it, measured on
hardware: **a foreground in Connected mode with a still-valid access token did
not schedule directory hydration.** The expiry gate returned early, and that
early return deliberately scheduled nothing.

**My reasoning when I wrote it — "nothing changed, so there is nothing new to
hydrate from" — was wrong.** Hydration is not a consequence of the *token*
changing. It is a consequence of the client needing its directory state, and
what changes is **eligibility** — Solo → Connected — which **no token event
reports**.

**The broken lifecycle:** a member signs in while unentitled, subscribes later
**without re-authenticating**, and holds a valid token throughout. Nothing
rotates ⇒ nothing schedules ⇒ no directory row is published until the token
happens to age out, up to a full token lifetime later. That is the
lapsed-member-returns journey U5's self-healing invariant exists to serve.

**Measured, T2→T3 on Device A:** `posts` SELECT **+3** (Connected and
authenticated, since the feed fetch sits behind `guard ok`), `account_directory`
SELECT **+0** (hydration never began — `fetchSelfRow` is its first act), refresh
tokens **+0** (the early return was taken).

## 6.2 The fix

**A usable session schedules hydration however it became usable.** The rule is a
pure decision — `SessionRefreshPolicy.schedulesDirectoryHydration(after:)` over
`.rotated | .alreadyValid | .recoveredNewerSession` — rather than an inline
condition, so the **lifecycle invariant** is unit-testable instead of merely
inspectable. `refreshSupabaseSession` now schedules on all three; call sites went
**3 → 5**.

**It is safe only because of the re-entrancy guard**, which is now also a pure
rule (`shouldBeginDirectoryHydration(inFlightUserID:targetUserID:)`) that the
scheduler consults, so the deployed condition and the tested rule cannot drift.
Hydration preflights a session refresh, so a refresh that schedules hydration can
be re-entered by it; the guard makes that a no-op instead of a
cancel-and-restart spin.

**This settles a question left open in §3 of this file.** The handover claimed
gate (A) alone sufficed and (C) was optional. The opposite is true: **(C) is what
makes (A) survivable.** Without the guard, this fix would reopen the
34-rotations-in-20.5 s defect.

## 6.3 Evidence

- Debug **and** Release build clean.
- `MOTIVOTests` **87 passed / 0 failed / 0 skipped** (81 before, **+6**).
- `supabase/tests/p5/session-refresh-acceptance.sh` **34/34**.
- **Non-vacuity, measured against the pre-fix tree:** schedule call sites
  **3 → 5**; `schedulesDirectoryHydration(after: .alreadyValid)` **0 → 1**.
- `u5-client-acceptance` **28/2, identical to its HEAD baseline** — unmoved.
- `u8-acceptance` **25/5, identical to its HEAD baseline.** Those 5 are D-series
  scope-containment assertions diffed against `57ab5fa`; they were already
  failing at HEAD and inflate with every later commit.

## 6.4 A TEST WAS RE-POINTED, AND IT IS DECLARED RATHER THAN BURIED

`U8-B5` and `U8-B6` pinned the **exact previous wording** of the two Profile
privacy helpers, which the account holder revised on 2026-09-08. Both literals
were re-pointed to the new text. **Re-pointed, not relaxed:** what they protect
is that the setting explains itself and that the Thoughts case is stated, and
both still hold. `U8-A1` — which forbids the false *"never shared"* framing —
was **not** touched and still passes, because the new wording says
*default*-private, which is what Thoughts actually are.

## 6.5 What is still NOT established

**Gate (C) remains untested on hardware.** Every token observation so far —
8→9, 9→10, 10→13, 15→16 — measures gate **(A)**. The hydration cycle has not run
once under Connected mode, because until this fix it was never scheduled.

**The no-directory-row state of `9c5385f6` is preserved and is the fixture for
that test.** Nothing in this unit touched the device or the server.
