# CP-3 §10 — SESSION DISCRIMINATOR. PRE-DEVICE BASELINE, 2026-09-07 20:35 UTC

Measured read-only against production `rlwtqxumfobakvdueugm` — **the same ref the
app's `Info.plist` `SUPABASE_URL` points at**, verified rather than assumed.
Nothing was mutated. Repo at `96b14f0`, tree clean, local == origin.

---

## 1. TWO CORRECTIONS TO THE HANDOVER, BOTH MATERIAL

### (a) THE UUIDs IN §2 AND §9 ARE WRONG. The live ids are different values.

| Handover says | Production actually holds | Which one |
|---|---|---|
| `1fbf664a` (Samuel) | **`dfaf8d18-ca27-4e5a-b46f-3c75801492f0`** | holds the only `account_directory` row, `samueldixon` |
| `96a3cb7b` (fresh CP-3) | **`9c5385f6-7bb6-4044-b252-ffe841626b62`** | holds the only `account_privacy` row, `band_18_plus`, **no** directory row |

**This is not a formatting artefact** — neither handover prefix occurs anywhere
in either live UUID. `1fbf664a` is the id Phase 4's documents use for
`samueldixon`, so it was most likely carried forward from a pre-CP-0 record.

**The mapping is nonetheless unambiguous, established on 9 of 9 matching
counts** — users 2, account_privacy 1, account_directory 1, posts 6,
post_comments 1, follows 0, membership 1, membership_binding 1,
shadow_enforcement_stat 34 — plus both qualitative properties (`band_18_plus` on
the identity with no directory row; Samuel holding the only directory row).

**§9's prohibitions are stated BY ID, and a wrong id is exactly how the wrong
row gets deleted.** Read §9 as: do not delete/reset **`9c5385f6`** or its
`band_18_plus` row; do not touch **`dfaf8d18`**.

### (b) THE SANDBOX SUBSCRIPTION EXPIRED AT 19:43:57 UTC — after §2 was written

```
renewal_date        2026-09-07 19:43:57+00     derived_entitled  FALSE
entitlement_ended_at 2026-09-07 19:43:57+00    pending_cleanup_at 2026-11-06 19:43:57+00
```

The 60-day quarantine scheduled itself exactly as designed, and **no worker will
act on it** — U7's earliest candidate date is 2026-11-01 and selection is empty
until then. Nothing to do; recorded because it changes what §10 can measure.

---

## 2. WHAT THIS MEANS FOR THE §10 DISCRIMINATOR — HALF IS UNREACHABLE

`AppMode` resolves from **local StoreKit entitlement**, and there is now none, so
Device A will sit in **Solo even after a successful sign-in**.

**Reachable in Solo — gate (A), unconditional rotation.**
`AgeBandRecoveryCoordinator` runs at launch (`MOTIVOApp:283`) and on **every
foreground** (`:350`), gated only on `hasConnectedIdentity` and
`backendConfigured` — deliberately **not** on Connected mode. It calls
`fetchSelf` → `preflight` → `ensureValidBackendSession` → `refreshSupabaseSession`.
So each attempt past the coordinator's 60 s cooldown drove exactly one
unconditional rotation before the fix, and must drive **none** after it.

**NOT reachable in Solo — the hydration loop, gate (C).**
`scheduleDirectoryHydrationIfNeeded` returns early on
`guard BackendEnvironment.shared.isConnected`, and `AppModeManager.applyMode`
sets `.localSimulation` in Solo. **The refresh↔hydration cycle therefore cannot
close at all without an entitlement**, and acquiring one means a repurchase or
Restore Purchases, both prohibited by §9.

**So a clean result here scores (A) and says NOTHING about (C).** Recording that
distinction now, before the run, so a green measurement cannot later be read as
the whole loop having been verified on hardware.

---

## 3. THE BASELINE — READ FROM TOKEN TIMESTAMPS, NOT THE SESSION ROW

§6 records that the previous session got this wrong by taking its window from
the `auth.sessions` row. These are `auth.refresh_tokens.created_at`.

**`9c5385f6` (the identity under test)**

| | |
|---|---|
| tokens | **38** (37 revoked, **1 live**) |
| window | 13:34:54.311 → 13:44:08.197 |
| **gaps < 1 s** | **34 of 37** |
| median gap | **0.14 s** |
| max gap | 321.37 s (ordinary pre-burst activity) |
| live token | 13:44:08.197 |

The burst tail is uniform 0.12–0.13 s spacing — a machine, not a user.

`dfaf8d18` (Samuel, untouched): 248 tokens, last 2026-09-05 16:44:36. **This row
must not move.**

---

## 4. PREDICTIONS, COMMITTED BEFORE THE RUN

Scored on `auth.refresh_tokens`, never on the UI staying Connected.

| # | Prediction | Falsifier |
|---|---|---|
| P1 | `auth.users` stays **2**; no new identity | SIWA minting a third id |
| P2 | Sign-in adds a **small, bounded** number of tokens to `9c5385f6` (expect 1–2) | tens |
| P3 | **Five foregrounds add ZERO tokens.** The discriminator: pre-fix each foreground rotated once, so pre-fix predicts **+5** | any increase |
| P4 | **No gap < 1 s anywhere** in the new tokens | any sub-second gap |
| P5 | `dfaf8d18`'s token count stays **248** and its last token stays 2026-09-05 | any movement |
| P6 | `account_privacy` still exactly 1 row, `band_18_plus`, `band_updated_at` **unchanged** at 13:40:16.675419 | a rewrite |
| P7 | `account_directory` still exactly 1 row (Samuel). The fresh identity stays row-less **because hydration cannot run in Solo** | a new directory row |

**P3 is the whole discriminator.** P4 catches a slower loop that P3's window
might straddle.


---

## 5. TWO CORRECTIONS TO §2/§4 ABOVE, made before the run

### (a) THE SIWA ROUTE IS NOT ProfileView'S SIGNED-OUT GATE

Stated first as "Profile → Sign in with Apple button". **Wrong, and the device
disproved it**: in Solo, Profile shows the ordinary local profile card.
`signedOutGateView` is a **sheet** (`ProfileView:433`) raised only by
`showConnectedSignInSheet`, and its gate-presented branch (`:1975`) is the
fresh-install case.

**The correct route is the one the account holder identified:**

```
Profile → Explore Connected  (showConnectedIntroduction)
        → "Already have a Connected account?" → SIGN IN   (ConnectedIntroductionView:78)
        → connectedSignInIntent = .returning   (ProfileView:380)
        → SIWA sheet → on success, UNWINDS to Profile      (ProfileView:2005)
```

**TAKE "SIGN IN", NEVER "CONTINUE", and the difference is not cosmetic.**

| | `.returning` — "Sign In" | `.join` — "Continue" |
|---|---|---|
| after success | unwinds to Profile (`:2005`) | opens **MembershipSelectionView**, the purchase screen (`:1996`) |
| age range | **never requested** | `requestAgeRange` fires **before** SIWA (`:383-388`) |

So "Continue" would walk into both a purchase surface (§9 prohibits) and the
Age Assurance fixture (§10 defers). "Sign In" touches neither. The code says so
in its own words: *"Returning member: signing in IS the whole errand."*

### (b) THE 60 s COOLDOWN DOES NOT APPLY HERE, so P3 needs no spacing

`AgeBandRecoveryCoordinator.recoverIfNeeded` assigns `lastAttemptAt` **after**
its already-established short-circuit (`:84-91` returns; `:94` assigns). With
`band_18_plus` present, `fetchSelf` succeeds and it returns **before** the
cooldown is ever recorded — so `shouldAttempt` sees `lastAttemptAt == nil` on
every subsequent call.

**Every foreground therefore drives a `fetchSelf` → preflight →
`ensureValidBackendSession` → `refreshSupabaseSession`, with nothing throttling
it.** That strengthens P3 rather than weakening it: pre-fix, five foregrounds
give five rotations however closely spaced, and no spacing is required.

**It also confirms Apple is never asked while a band exists**, so this run
cannot disturb `band_18_plus` or consume the Age Assurance fixture.

---

# 6. RESULTS — measured 2026-09-07 20:52 UTC

Device A rebuilt at `445750f`-era HEAD, signed in via **Explore Connected →
Sign In** (`.returning`) at **20:49:10**, then foregrounded **five times**.

| # | Prediction | Observed | |
|---|---|---|---|
| P1 | `auth.users` stays 2 | **2** | **PASS** — SIWA returned the same `sub`; no identity minted |
| P2 | sign-in adds 1–2 tokens | **+1** (20:49:10.037) | **PASS** |
| **P3** | **five foregrounds add ZERO tokens** | **ZERO** (38 → 39 total, the 1 being the sign-in) | **PASS — the discriminator.** Pre-fix predicted **+5** |
| P4 | no gap < 1 s | **25 501.84 s** (~7.08 h) from the previous token | **PASS** |
| P5 | `dfaf8d18` unmoved | **248 tokens, last 2026-09-05 16:44:36, 19 sessions, `last_update` 2026-09-05** | **PASS** — Samuel untouched |
| P6 | band unchanged | `band_updated_at` **13:40:16.675419**, identical to baseline; both `*_changed_at` still NULL | **PASS** |
| P7 | no directory row for the fresh identity | `account_directory` still **1** (Samuel) | **PASS** |

**The signature is gone.** Baseline: 34 of 37 gaps under 1 s, median 0.14 s,
uniform 0.12–0.13 s tail. This run: one token, next-gap seven hours. The old
sub-second gaps still visible in the table are **historical rows from 13:44**,
not new ones.

A new session `fa7c2149` was minted; the previous `88227e65` and its orphan
live token #38 remain. Expected — a fresh SIWA starts a session rather than
resuming one — and it is why `live` went 1 → 2 without a rotation.

## 6.1 THE ZERO IS OVER-DETERMINED, AND THAT IS NOT YET RESOLVED

**P3 passing is consistent with two different worlds**: the expiry gate saw a
fresh token and correctly rotated nothing, **or** the refresh path was never
entered on foreground at all. Both produce exactly zero.

Only the first is a pass. **Scoring P3 without separating them would repeat the
"Find People returns nothing" error** recorded in the Phase 4 device QA — a zero
read as evidence for one cause when two were sufficient.

`pg_stat_statements` shows `account_privacy_self_v1` at **8 PostgREST calls**
cumulative, which cannot be attributed to this run without a delta.
**RESOLUTION: record 8, foreground once more, re-read.** 8 → 9 proves the read
path executes on foreground, which makes the zero rotations a measured pass.
No change proves the coordinator never ran, and P3 is then unscored — not
failed, and certainly not passed.

**Gate (C), the refresh↔hydration cycle, remains unreachable in Solo and is
NOT addressed by any of this.**

## 6.2 THE ZERO IS NOW ATTRIBUTED — P3 IS A MEASURED PASS. 20:57 UTC

One further foreground:

| | before | after |
|---|---|---|
| `account_privacy_self_v1` PostgREST calls | 8 | **9** |
| `9c5385f6` refresh tokens | 39 | **39** |

**The chain is closed, and every link is verified in source rather than
assumed.** `AccountPrivacyService.call` runs `preflight` **first** and returns
early on its failure (`AccountPrivacyService.swift:100`), so the RPC is
unreachable unless preflight succeeded — and preflight *is*
`ensureValidBackendSession` → `refreshSupabaseSession`.

```
RPC executed (8 → 9)
  ⟹ preflight PASSED
      ⟹ ensureValidBackendSession returned true
          ⟹ refreshSupabaseSession was ENTERED and returned true
              ∧ no new token
                  ⟹ it returned true WITHOUT ROTATING
```

**Only the expiry gate returns true without rotating.** The one other
non-rotating success, `.recoverWithNewerSession`, requires a thrown error *and*
`persisted != attempted` — impossible when nothing rotated. So the early return
is the only path that fits.

**Pre-fix, this same foreground would have rotated once.** The zero is therefore
the gate working, not the path being skipped. **P3 PASSES AS MEASURED.**

### It also retires the build-identity caveat

Step 1 warned there is no way to tell which commit is installed — both
configurations report `1.0 (131)` and `devicectl` exposes no hash. **The
behaviour settles it after the fact:** "RPC executed **and** no rotation" is not
producible by the pre-fix binary, which rotated unconditionally on every entry.
The installed build is the fixed one, established by measurement rather than by
trusting the install step.

## 6.3 WHAT IS STILL NOT ESTABLISHED

- **Gate (C), the refresh↔hydration cycle, is untested on hardware.** It cannot
  close in Solo, and reaching it needs an entitlement (§9 prohibits). Gate (A)
  passing says nothing about it.
- **Directory-publication ordering** remains blocked for the same reason —
  `scheduleDirectoryHydrationIfNeeded` returns early on `isConnected`.
- **A deviation was observed and is NOT chased:** after `.returning` sign-in the
  app landed on **PracticeTimerView**, not Profile. That is `ProfileView:1975`'s
  gate branch, which returns early, so the `.returning` unwind at `:2005` never
  ran despite being the branch this path's comments describe. Cosmetic, no
  bearing on any measurement here, and recorded rather than fixed.
