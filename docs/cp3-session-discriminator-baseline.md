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
