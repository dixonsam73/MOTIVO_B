# ADULT GATE-C RUN — PREDICTIONS. 2026-09-08, PRE-RUN

Recorded before any physical action. Repo `c072ae5`, local == origin, tree clean.
**Gate (C) remains explicitly DEVICE-UNVERIFIED until this run is scored.**

---

## 1. CENSUS — T0 = 2026-09-08 06:29:41 UTC

| measure | T0 |
|---|---|
| `auth.users` | **2** · posts 6 · follows 0 |
| `account_privacy` | 1 row · `band_18_plus` · `band_updated_at` **2026-09-07 13:40:16.675419** |
| `account_directory` | **1** row (Samuel only) — **`9c5385f6` still has NO row** |
| `membership` | otid **2000001228947923** · **EXPIRED 03:10:28** · `entitled_now` **false** · `pending_cleanup_at` **2026-11-07 03:10:28** |
| `membership_binding` | `created_at` == `updated_at` == **13:40:16.990315** |
| `9c5385f6` tokens | **41** (2 live), last **06:28:32.385** |
| `dfaf8d18` tokens | **248**, last **2026-09-05 16:44:36** |
| counters | `posts` SELECT **19858** · dir SELECT **3348** · dir INSERT **2795** · `privacy_rpc` **18** |
| `stats_reset` | 2025-12-30 (**not reset**; deltas valid) |

**THE ENTITLEMENT LAPSED OVERNIGHT.** Purchased 21:09, expired 03:10:28 — about
six hours, consistent with Apple's documented sandbox cap of ~12 accelerated
renewals. `pending_cleanup_at` re-armed itself correctly. **Device A is
therefore in Solo, and a plain background→foreground cannot reach the fixed
path**, because both hydration entry points guard on `isConnected`.

**ONE UNATTRIBUTED OBSERVATION, recorded rather than explained away:** directory
SELECT moved **3347 → 3348** between 21:54:46 yesterday and now, with no token
rotation in that window and no feed fetch (`posts` SELECT flat at 19858). I
cannot attribute it. **It changes nothing material** — `dir_ins` is still 2795
and `dir_rows` still 1, so **no directory row has ever been published** and the
fixture is intact.

**A token was minted at 06:28:32**, one second before the census — the app was in
use. That token is **fresh until roughly 07:28**, which matters below.

---

## 2. PHYSICAL ACTIONS — three, not one, and why

The requested "single background → foreground while genuinely Connected" is the
*scoring* action, but two things must happen first.

| | action | why it is unavoidable |
|---|---|---|
| **A** | **Install the fixed Release build (`c072ae5`)** | the fix is not on the device; Device A still runs the pre-fix binary |
| **B** | **Repurchase Monthly** — Profile → Explore Connected → **Continue** → Monthly | entitlement expired at 03:10:28, so the device is in Solo and neither hydration entry point can be reached. Age Assurance must still read **18+** (Continue calls `requestDeclaredAgeRange` first and is refused otherwise) |
| **C** | **One background → foreground**, once Connected is showing | **the scoring action** |

**Repurchase is genuinely required, not convenience.** The no-repurchase lift
was granted yesterday for exactly this purpose and that purpose is unchanged —
flagged rather than assumed. Sandbox account must stay
`sdsongsltd+devicec@gmail.com`.

### TIMING MATTERS, AND IT IS THE WHOLE POINT OF CRITERION 1

The token minted at 06:28:32 is valid for about an hour. **If step C happens
before ~07:28, the foreground exercises the fix in its purest form**: a valid
token, no rotation, and hydration scheduled anyway. After ~07:28 the token ages
out, a rotation occurs, and hydration would have been scheduled **even by the
pre-fix build** — criteria 2–6 still score, but **criterion 1 loses its
discriminating power**.

**So do step C promptly after Connected appears.**

---

## 3. PREDICTIONS, SCORED SEPARATELY

**Measurement points: M1** immediately after Connected appears, **M2** after the
single background→foreground.

### Anti-over-determination gate — checked FIRST

**`posts` SELECT must increase above 19858.** The feed fetch sits behind
`guard ok` on the authenticated foreground path, so a rise proves the client was
genuinely **Connected and authenticated**. **If it is flat, every zero below is
unattributable and criteria 1–4 are UNSCORED, not passed.** This is the 8→9
lesson and the T2/T3 lesson, applied in advance.

### 1 — Resubscription/hydration regression: hydration begins with an already-valid token

| | prediction | falsifier |
|---|---|---|
| C1.1 | at some measurement, **`dir_select` increases while `tokens` does NOT** | dir SELECT flat while Connected and tokens flat |
| C1.2 | that increase is **> 3348** | — |

**This is the fix's discriminator and it is not producible by the old binary:**
pre-fix, no rotation ⇒ no schedule ⇒ `fetchSelfRow` never runs. Measured
yesterday in exactly this configuration: `posts` +3, dir SELECT **+0**, tokens
**+0**.

### 2 — Gate (C): the privacy preflight does not recreate the loop

| | prediction | falsifier |
|---|---|---|
| C2.1 | **ZERO gaps < 1 s** among new tokens | any sub-second gap |
| C2.2 | no **≥ 5 tokens in any 10 s window** | any such cluster |
| C2.3 | `privacy_rpc` **increases** — the preflight provably ran | flat ⇒ the loop's edge was never exercised ⇒ **UNSCORED** |

**This is the first time hydration runs under Connected mode on this identity
with the fix — the exact configuration that produced 34 rotations in 20.5 s at
0.12–0.13 s spacing.** Gate (C) is scored here or not at all.

### 3 — Directory publication

| | prediction | falsifier |
|---|---|---|
| C3.1 | `account_directory` **1 → 2**; `dir_ins` **> 2795** | still 1 |
| C3.2 | new row `9c5385f6`, `display_name` **"Device A"** | absent/other |
| C3.3 | `lookup_enabled` **FALSE** (column default — the client does not send it) | true |
| C3.4 | `follow_requests_enabled` **TRUE** (default) | false |
| C3.5 | `account_id` NULL at insert, later **backfilled** | never populated |
| C3.6 | `entitled_until` **non-NULL** while Samuel's stays NULL | both NULL ⇒ the publish beat the membership update; legitimate, record it |

**C3.3 is not a privacy regression** — `account_privacy.lookup_enabled` stays
authoritative and the directory column is dead by CP-2.

### 4 — Token behaviour bounded

| | prediction | falsifier |
|---|---|---|
| C4.1 | total tokens **≤ 45** (from 41) across install, purchase and the foreground | ≥ 50 |
| C4.2 | no sub-second gap anywhere | any |

### 5 — Band unchanged

| | prediction | falsifier |
|---|---|---|
| C5.1 | `band_updated_at` **2026-09-07 13:40:16.675419**, unchanged | any change |
| C5.2 | `age_band` `band_18_plus`; both `*_changed_at` NULL; exactly **1** row | any change |

Structural: `ensureAgeBandEstablished` returns on the `fetchSelf` `.success`
branch before reaching `upsertBand`, so with a row present no write is reachable.

### 6 — Samuel untouched

| | prediction | falsifier |
|---|---|---|
| C6.1 | `dfaf8d18` **248** tokens, last **2026-09-05 16:44:36** | any movement |
| C6.2 | his directory row unchanged — "Samuel Dixon" / `samueldixon` / London | any change |
| C6.3 | `auth.users` stays **2** | a third identity |

---

## 4. WHAT THIS RUN CANNOT SETTLE

**Band-before-directory ORDERING remains only weakly supported**, unchanged from
yesterday's §5: the band predates the run by ~17 hours so the CP-1 trigger passes
trivially, and `account_directory` has **no timestamp column**, so no transaction
evidence exists. The strong ordering test still needs a fresh identity and is
**deferred**.

**Teen / under-13 / decline / recovery are not in scope** until this adult run is
scored.
