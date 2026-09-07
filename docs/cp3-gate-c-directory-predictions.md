# GATE (C) + CP-3 DIRECTORY PUBLICATION — PREDICTIONS. 2026-09-07, PRE-PURCHASE

**Recorded BEFORE any purchase.** No-repurchase is lifted for Device A by
explicit instruction; it was a diagnostic preservation constraint, not a CP-3
requirement. Repo `c579af8`, local == origin, tree clean.

---

## 0. TWO DIFFERENT CLAIMS. ONE RUN SUPPLIES EVIDENCE FOR BOTH; THEY ARE SCORED APART

| | **Gate (C) hardware verification** | **CP-3 directory-ordering verification** |
|---|---|---|
| question | does the refresh↔hydration cycle recur once Connected is live? | is the age band established **before** a directory row is published? |
| scored on | `auth.refresh_tokens` rotation behaviour | the CP-1 trigger invariant + the code path taken |
| status now | untested on hardware — unreachable in Solo | publication itself never attempted (Solo); ordering never observed |
| **this run** | **can settle it** | **can only WEAKLY support it — see §5** |

**Do not let one run's success be reported as both.** They fail for different
reasons and a pass on one is not evidence for the other.

---

## 1. BASELINE — immediately pre-purchase, 2026-09-07 ~20:57 UTC

| measure | value |
|---|---|
| `auth.users` | **2** |
| `9c5385f6` refresh tokens | **39** (2 live), last **20:49:10.037** |
| `dfaf8d18` refresh tokens | **248**, last **2026-09-05 16:44:36**, 19 sessions |
| `account_privacy` | 1 row · `band_18_plus` · `band_updated_at` **13:40:16.675419** · `lookup_enabled` true · both `*_changed_at` NULL |
| `account_directory` | **1** row — `dfaf8d18`, "Samuel Dixon", `samueldixon` |
| `membership` | 1 row · Sandbox · otid **2000001228947923** · `binding_method` **purchase** · **EXPIRED** 19:43:57 · `pending_cleanup_at` 2026-11-06 |
| `membership_binding` | 1 row · `created_at` == `updated_at` == **13:40:16.990315** |
| `pg_stat_statements` | `account_privacy_self_v1` **9** · `account_directory` INSERTs **2795** |

---

## 2. TWO HARD PRECONDITIONS, both established by reading source rather than assumed

**(a) THE AGE ASSURANCE FIXTURE MUST BE SET TO 18+, OR THE PURCHASE IS
UNREACHABLE.** `ConnectedIntroductionView`'s **Continue** calls
`requestDeclaredAgeRange()` **unconditionally and first** (`ProfileView:389`),
and `continueToConnectedJoin()` has **exactly one caller** — that `.band` case
(`:393`). §2 of the handover records the fixture as currently **UNSET**, which
returns `.unavailable` and shows *"Études needs Apple to share your age range…"*.
`MembershipSelectionView` is then unreachable by any route.

It must be a range with **`lowerBound >= 18`** — `DeclaredAgeRangeService.derive`
returns `.band18Plus` only then, and that keeps the fixture consistent with the
existing row.

**(b) THE SANDBOX APPLE ACCOUNT MUST REMAIN `sdsongsltd+devicec@gmail.com`.**
A different tester means a different `originalTransactionId` and therefore a
**second `membership` row**, at which point the U6b re-bind guard correctly
refuses because it requires exactly one live Sandbox row.

---

## 3. THE GATE (C) WINDOW IS NARROW, AND THE NO-ROW BRANCH IS SINGLE-USE

The loop's richest path is the **first hydration after Connected activates,
while `9c5385f6` still has no directory row** — the `guard let row else` branch
that reaches `ensureAgeBandEstablished` (`:595`) → `fetchSelf` → preflight →
refresh. That is the exact shape that produced 34 rotations in 20.5 s at 13:44.

**Once the directory row is published that branch is gone for this identity**,
and re-reaching it would need the row deleted, which is forbidden. The row-exists
branch still preflights twice (`:611`, `:640`), so relaunches remain a weaker
re-test — but **the strongest observation is available once**, and the procedure
below is built around not wasting it.

---

## 4. PREDICTIONS

### Q1 — the purchase legitimately restores entitlement

| | prediction | falsifier |
|---|---|---|
| Q1.1 | `membership` stays **1 row**, otid **2000001228947923** reused (observed for tester 1 across lapse-and-resubscribe) | **2 rows / a new otid is NOT a failure** — record which; the standing rule forbids depending on otid survival |
| Q1.2 | `renewal_date > now()`, `entitlement_ended_at` **NULL**, `is_in_billing_retry` false | still expired |
| Q1.3 | `pending_cleanup_at` → **NULL** (resubscription cancels pending cleanup) | 2026-11-06 persisting |
| Q1.4 | `binding_method` stays **`purchase`** | `legacy_claim` — would mean the token was not carried |
| Q1.5 | **`membership_binding` UNCHANGED** — `created_at` == `updated_at` == 13:40:16.990315 | any movement: a resubscribe must never re-bind |
| Q1.6 | device shows Connected; Profile's destructive action reads **"Delete Account & All Études Data"** | still "Erase All Études Data" |

### Q2 — Gate (C): the loop does not recur  ·  Q7 — no pathological burst

| | prediction | falsifier |
|---|---|---|
| Q2.1 | tokens rise by a **small bounded number — predict ≤ 6** across purchase, activation and five foregrounds | **≥ 15** |
| **Q2.2** | **ZERO gaps < 1 s** among new tokens | **any sub-second gap** (baseline: 34 of 37 were, median 0.14 s) |
| Q2.3 | no **≥ 5 tokens inside any 10 s window** | any such cluster |
| Q2.4 | `account_privacy_self_v1` calls **increase** — proving the path ran | no increase ⇒ the zero is over-determined again and Q2 is **unscored, not passed** |

**Q2.4 exists because of the 8→9 lesson.** A quiet token table is only evidence
if the code that would have rotated actually executed.

### Q3 — the band is not rewritten by hydration

| | prediction | falsifier |
|---|---|---|
| Q3.1 | `band_updated_at` **unchanged at 13:40:16.675419** | any change |
| Q3.2 | `age_band` still `band_18_plus`; both `*_changed_at` still NULL | any change |
| Q3.3 | `account_privacy` still exactly **1 row** | 2 rows |

**This is structural, not hopeful.** `ensureAgeBandEstablished` returns on the
`fetchSelf` **`.success`** branch *before* reaching `upsertBand`
(`AuthManager:177-186`), so with a row present **no write is reachable** — on
either hydration branch, and even if the device fixture reported a different
range.

### Q4 — directory publication now occurs

| | prediction | falsifier |
|---|---|---|
| Q4.1 | `account_directory` **1 → 2** | still 1 ⇒ publication still blocked |
| Q4.2 | new row `user_id = 9c5385f6`, `display_name` = **"Device A"** (the local profile name) | absent/other |
| Q4.3 | `lookup_enabled` = **FALSE** — the column default; the client **does not send it** (CP-3 made it dead) | true |
| Q4.4 | `follow_requests_enabled` = **TRUE** (column default) | false |
| Q4.5 | `account_id` NULL at insert, then **backfilled non-NULL** by `scheduleAccountIDBackfillIfNeeded` | never populated |
| Q4.6 | `entitled_until` stamped by `tg_set_entitled_until` from `membership_entitled_until()`. **Non-NULL if membership was updated before the insert; NULL if the publish won the race** — both legitimate, record which; a later publish re-stamps (BEFORE INSERT **OR UPDATE**) | — |
| Q4.7 | directory INSERT calls **> 2795** | unchanged |

**Q4.3 is NOT a privacy regression** and must not be read as one:
`account_privacy.lookup_enabled = true` stays authoritative, and the directory
column is dead by CP-2.

### Q5 — band-before-directory ordering: WEAK HERE, AND SAID SO IN ADVANCE

**What this run CAN establish:**

- **Q5.1 structural, verified read-only TODAY before the run.**
  `tg_directory_requires_band` is deployed **BEFORE INSERT** on
  `account_directory` and raises `23514` — *"age band must be declared before a
  directory row is created"* — when no `account_privacy` row exists. It returns
  early when a row already exists for that `user_id`, so upserts are not blocked.
- **Q5.2 code path.** `hydrateDirectoryStateFromBackend`'s no-row branch guards
  publication behind `ensureAgeBandEstablished` and **returns on failure**
  (`AuthManager:595-598`), so publication is unreachable without a band.
- **Q5.3 consistency.** The insert succeeding proves a privacy row existed at
  that instant.

**What it CANNOT establish, stated now so a green result is not over-read:**

- **The trigger cannot discriminate on this identity.** The band was established
  at 13:40, hours before; the trigger passes trivially. A test whose negative
  branch is unreachable is a consistency check, not a discriminator.
- **THERE IS NO TRANSACTION EVIDENCE TO BE HAD.** `account_directory` has **no
  `created_at` and no `updated_at` column** — confirmed against
  `information_schema` today. So the "transaction evidence" half of this
  criterion is **not meaningful here**, and none will be manufactured. The only
  stamped column is `entitled_until`, which orders membership-vs-directory, not
  band-vs-directory.
- **The strong ordering test needs a FRESH identity** establishing band and
  directory in one session, where the trigger's refusal is reachable. That is
  **deferred, not satisfied.**
- The negative direction is already observed: the handover records a band-write
  failure **suppressing** publication twice, with no orphan row.

**So CP-3 directory-ordering will remain PARTIALLY verified after this run.**

### Q6 — Samuel untouched

| | prediction | falsifier |
|---|---|---|
| Q6.1 | `dfaf8d18` tokens stay **248**, last **2026-09-05 16:44:36** | any movement |
| Q6.2 | sessions stay **19**, `last_update` 2026-09-05 | any movement |
| Q6.3 | his directory row unchanged — "Samuel Dixon" / `samueldixon` | any change |
| Q6.4 | `auth.users` stays **2** | a third identity |

---

## 5. EXACT PHYSICAL STEPS

**Pre-flight, both required (§2):**

- **A.** Settings → confirm the Sandbox Apple Account is **`sdsongsltd+devicec@gmail.com`**. Do not change it.
- **B.** Set the **Age Assurance fixture to an 18+ range** (`lowerBound >= 18`). Without this, Continue is refused and the purchase screen cannot be reached.

**Then:**

1. **Tell me before purchasing.** I take a fresh immediately-pre-purchase census — the §1 baseline will be stale by then, and a dated census must not be reused as authority.
2. Études → **Profile → Explore Connected → Continue**. *(Not "Sign In" — the identity is already authenticated.)* Apple's age sheet may or may not appear; it is cached and its absence is expected, not a fault.
3. On `MembershipSelectionView`, select the **Monthly** product and complete the purchase on Apple's **Sandbox** sheet.
4. **Then leave the app open and untouched for ~60 seconds.** This is the Gate (C) window (§3) — the first hydration while no directory row exists, the one-shot observation. Do not navigate.
5. **Tell me.** I measure immediately, capturing the no-row branch.
6. Background and foreground **five times**. Tell me. I measure again.

**Not in scope, deliberately:** teen / under-13 / decline / recovery; account
deletion or reset; any manual server repair; Device B; Restore Purchases.

---

# 6. FRESH PRE-PURCHASE CENSUS — T0 = 2026-09-07 21:07:10 UTC

**This supersedes §1 as the scoring authority.** §1 is retained as the earlier
reading, not deleted. Preconditions confirmed by the account holder: Sandbox
account `sdsongsltd+devicec@gmail.com`; Age Assurance **User 18+, age confirmed,
significant change not applicable**. Explore Connected not entered; nothing
purchased.

| measure | T0 value |
|---|---|
| `auth.users` | **2** |
| posts / comments / follows | **6 / 1 / 0** |
| `9c5385f6` refresh tokens | **39** (2 live), last **20:49:10.037** |
| `9c5385f6` sessions | **2**, last update **20:49:09.999** |
| `dfaf8d18` refresh tokens | **248** (19 live), last **2026-09-05 16:44:36.294** |
| `dfaf8d18` sessions | **19**, last update **2026-09-05 16:44:36.297** |
| `account_privacy` | 1 row · `band_18_plus` · `band_updated_at` **13:40:16.675419** · `lookup_enabled` **true** · `follow_requests_enabled` true · both `*_changed_at` **NULL** |
| `account_directory` | **1** row — `dfaf8d18` · `samueldixon` · "Samuel Dixon" · London · `lookup_enabled` true · `entitled_until` **NULL** · `avatar_version` NULL |
| `membership` | otid **2000001228947923** · Sandbox · `purchase` · `renewal_date` **19:43:57 (expired)** · `entitlement_ended_at` 19:43:57 · `pending_cleanup_at` **2026-11-06 19:43:57** · retry false |
| `membership_binding` | `created_at` == `updated_at` == **13:40:16.990315** |
| `pg_stat_statements` | `account_directory` INSERTs **2795** · `account_privacy_self_v1` **10** · `stats_reset` 2025-12-30 (**not reset**; deltas valid) |

## 6.1 AN UNPROMPTED THIRD CONFIRMATION OF GATE (A)

`account_privacy_self_v1` was **9** at 20:57 and is **10** at 21:07, while
`9c5385f6`'s refresh tokens stayed at **39** and its session `updated_at` stayed
at 20:49:09.999.

**Nobody asked for that foreground.** It arrived incidentally while the account
holder was checking Settings, and it reproduces the 8→9 result exactly: the
authenticated privacy preflight executed, and the expiry gate rotated nothing.
An unprompted repeat on a run nobody staged is stronger evidence than the
staged one.

## 6.2 ONE PREDICTION SHARPENED BY THE CENSUS

Samuel's directory row carries `entitled_until` **NULL** — he is unentitled,
consistent with CLAUDE.md's record that all identities are. So **Q4.6 has a
visible control**: if `9c5385f6`'s new row lands with a non-NULL
`entitled_until` while Samuel's stays NULL, the stamping trigger is
demonstrably reading live membership rather than defaulting.

---

# 7. T1 RESULTS — 21:10:04 UTC, ~1 min after purchase

## 7.1 Q1 PASSES IN FULL — the purchase legitimately restored entitlement

| | prediction | observed | |
|---|---|---|---|
| Q1.1 | 1 row, otid reused | **1 row, `2000001228947923` REUSED** | PASS |
| Q1.2 | `renewal_date > now`, `entitlement_ended_at` NULL | **21:38:54**, entitled **true**, ended **NULL** | PASS |
| Q1.3 | `pending_cleanup_at` → NULL | **NULL** (was 2026-11-06) | PASS |
| Q1.4 | `binding_method` stays `purchase` | **`purchase`** | PASS |
| Q1.5 | binding unchanged | `created_at` == `updated_at` == **13:40:16.990315** | PASS |

`membership.updated_at` **21:09:00.328936**. **Q3 PASSES** — band
`13:40:16.675419`, 1 row, both `*_changed_at` NULL. **Q6 PASSES** — users 2,
`dfaf8d18` still 248 tokens / 2026-09-05.

## 7.2 Q4 IS NOT MET, AND THE CAUSE IS A REGRESSION I INTRODUCED

`account_directory` is **still 1 row** and directory INSERT calls are **still
2795** — so no insert was even attempted.

**Hydration never ran.** It is scheduled from exactly three places
(`AuthManager:927`, `:1278`, `:1333`) — a **rotating** `refreshSupabaseSession`
success, the one-time `ensureBackendIdentityIfNeeded` handshake, and
`supabaseSignIn`. **`applyActivation` schedules nothing**, so *entering
Connected mode does not itself schedule hydration.*

**My expiry gate's early-return path deliberately does not schedule it.** I
wrote, in that very block: *"This path deliberately schedules NO hydration:
nothing changed, so there is nothing new to hydrate from."* **That reasoning was
wrong.** The *mode* changed — Solo → Connected — which is a new reason to
hydrate even though the token did not change. I flagged the risk at
implementation time as "a real, if minor, behavioural narrowing" and then
under-weighted it.

**THE AFFECTED JOURNEY IS NARROW BUT REAL, AND IT IS THE ONE THIS PROJECT CARES
MOST ABOUT:** sign in while unentitled, then become entitled **without
re-authenticating** — a lapsed member resubscribing, and the dormant subscriber
whose self-healing is U5's stated invariant. A brand-new join is unaffected,
because `supabaseSignIn` schedules hydration directly.

**It is a latency defect, not a permanent one.** The next *genuine* rotation
will schedule hydration and publish the row. The access token was minted
**20:49:10**; at Supabase's default 3600 s lifetime it expires **~21:49:10**,
and the gate's 60 s skew means a foreground from **~21:48:10** will rotate.

**THE FIX IS ONE LINE AND (C) ALREADY MAKES IT SAFE.** Scheduling hydration on
the early-return path cannot re-form the loop, because the re-entrancy guard
turns the re-entrant schedule into a no-op. **That makes (C) load-bearing rather
than belt-and-braces** — the opposite of §7's original claim that (A) alone
sufficed. **Not implemented now:** rebuilding mid-run would spend the one-shot
no-row window on a different binary.

## 7.3 GATE (C) IS STILL UNTESTED, AND ITS WINDOW IS STILL INTACT

Hydration has not run, so the refresh↔hydration cycle has **not** been
exercised. `9c5385f6` still has **no directory row**, so the single-use no-row
branch is **still available**.

`account_privacy_self_v1` went **10 → 13 (+3)** while tokens stayed at **39** —
three further confirmations of gate (A), on the purchase path this time.

## 7.4 THE NEXT EVENT IS A SINGLE, HIGH-VALUE FOREGROUND

**Predictions for one foreground at/after ~21:50 UTC:**

| | prediction | what it settles |
|---|---|---|
| R1 | exactly **one** token rotation (39 → 40) | the expiry gate releases correctly at expiry |
| R2 | hydration runs — `account_privacy_self_v1` **+1 or more** | the no-row branch is reached |
| R3 | **`account_directory` 1 → 2**, `display_name` "Device A" | **Q4** |
| R4 | **no sub-second gaps, tokens ≤ 42** | **GATE (C)** — pre-fix this is exactly where 34-in-20.5 s occurred |
| R5 | `entitled_until` **non-NULL** while Samuel's stays NULL | the stamping trigger reads live membership |
| R6 | band still `13:40:16.675419` | hydration does not rewrite the band |

**R1–R3 also confirm the §7.2 diagnosis by prediction rather than by argument.**
And they discriminate: if a rotation happens, hydration runs, and there is
**still** no directory row, the cause is the display-name guard
(`AuthManager:739`) and **not** my regression.

---

# 8. T2 RESULTS — 21:51 UTC, after the expiry foreground. R3 FAILS, UNATTRIBUTED

| | prediction | observed | |
|---|---|---|---|
| R1 | exactly one rotation 39 → 40 | **40**, last **21:50:33.988** | **PASS** |
| R2 | privacy path runs | `account_privacy_self_v1` **13 → 15 (+2)** | ran |
| **R3** | **directory 1 → 2** | **still 1 row; `dir_ins` still 2795** | **FAIL** |
| R4 | no burst, tokens ≤ 42 | **40**, one token, no sub-second gap | **PASS** |
| R5 | `entitled_until` non-NULL | no row to carry it | not reached |
| R6 | band unchanged | **13:40:16.675419** | **PASS** |

**R1 is a genuinely useful positive:** the expiry gate **releases at expiry**.
It held for an hour, then rotated exactly once when the token aged out. The gate
is now verified in *both* directions — it does not rotate while valid, and it
does not fail to rotate when stale.

**Membership is live and reconciling:** `renewal_date` **22:08:56**,
`entitled_now` **true**, `updated_at` **21:50:35.450** — 1.5 s after the
rotation, so attestation ran against Apple.

## 8.1 THE §7.2 DIAGNOSIS IS NOT CONFIRMED, AND IS NOW IN DOUBT

§7.4 committed a discriminator: *"if a rotation happens, hydration runs, and
there is still no directory row, the cause is the display-name guard and not my
regression."* A rotation happened and there is still no row — **so the
early-return regression is NOT the whole story.** It may not be the story at all.

**But the discriminator's middle clause is unproven: I cannot show hydration
ran.** `+2` on `account_privacy_self_v1` is consistent with hydration having run
(directory read → `ensureAgeBandEstablished`) *and* equally with two
mode-independent `AgeBandRecoveryCoordinator` foregrounds. **Another
over-determined count** — the same trap as before, and this time I lacked the
baseline to escape it.

**The rotation itself does not prove Connected mode either.** It is fully
explained by mode-independent paths: the recovery coordinator and
`MembershipAttestationService` both go through `ensureValidBackendSession`, and
attestation demonstrably ran. `ensureValidSession` — the mode-gated one — would
have returned early in Solo without refreshing.

## 8.2 CANDIDATE CAUSES, NONE YET EXCLUDED

Both blocked functions guard on `BackendEnvironment.shared.isConnected` —
`scheduleDirectoryHydrationIfNeeded:519` and
`publishLocalProfileSnapshotToDirectoryIfPossible:702`.

1. **The client is still in Solo.** `AppMode` resolves from *local StoreKit*, not
   from the server, so a live server-side membership does not settle it. Would
   block both functions and explain everything.
2. **Hydration ran; `ensureAgeBandEstablished` returned false**, hitting the
   deliberate suppression path (`:595-598`, `connectedSetupIncomplete = true`,
   no publish). That is the designed band-before-directory behaviour **working**,
   triggered by transport rather than by a missing band.
3. **Hydration ran; the directory self-read failed**, taking the `.failure`
   branch which logs and returns without publishing.
4. **The display-name guard** (`:739`) — least likely, since the local profile
   name is visibly "Device A".
5. **A stuck in-flight claim from my re-entrancy guard.** Unlikely — the `defer`
   releases on every exit path, including cancellation — but it is my change and
   it is not excluded by anything measured.

**Cause 1 would mean the run has not yet reached the state Gate (C) needs at
all.** Gate (C) is still **untested**, and `9c5385f6` still has **no directory
row**, so the single-use window remains **intact**.

## 8.3 COUNTER BASELINE FOR THE NEXT STEP — T2, 21:53:08 UTC

Captured because §8.1's ambiguity was caused by not having one.

| counter | value |
|---|---|
| `posts` SELECT | **19855** |
| `account_directory` SELECT | **3347** |
| `account_directory` INSERT | **2795** |
| `account_privacy_self_v1` | **15** |
| `9c5385f6` tokens | **40** |

**`posts` SELECT is the mode oracle.** The foreground path fetches the feed only
when the client considers itself Connected, so a rise proves Connected mode and
a flat count proves Solo — settling cause 1 without relying on a screenshot.
`account_directory` SELECT rising with INSERT flat separates causes 3 and 4 from
cause 2.

---

# 9. T3 — 21:54:46 UTC. §7.2 IS CONFIRMED BY MEASUREMENT

Deltas across one foreground, T2 21:53:08 → T3 21:54:46:

| counter | T2 | T3 | Δ | what it proves |
|---|---|---|---|---|
| `posts` SELECT | 19855 | **19858** | **+3** | **the feed was fetched ⇒ the client IS in Connected mode**, and `ensureValidSession` returned **true** (the fetch sits behind `guard ok`) |
| `account_privacy_self_v1` | 15 | **16** | +1 | the recovery coordinator ran |
| **`account_directory` SELECT** | 3347 | **3347** | **+0** | **hydration did NOT run** — `fetchSelfRow` is its first act |
| `account_directory` INSERT | 2795 | **2795** | +0 | no publish |
| `9c5385f6` tokens | 40 | **40** | **+0** | no rotation — the gate held |

## 9.1 THE CHAIN IS CLOSED

```
feed fetched          ⟹ Connected mode, and ensureValidSession returned TRUE
tokens flat           ⟹ refreshSupabaseSession took the EXPIRY-GATE EARLY RETURN
directory SELECT flat ⟹ hydration was never scheduled
```

**A foreground in Connected mode, with a valid token, does not schedule
directory hydration.** That is exactly the regression described in §7.2, now
measured rather than argued — and it is mine. **Cause 1 is excluded by the same
data** (the client is provably Connected), and causes 2, 3 and 4 are excluded
for this foreground because hydration never began.

**Cause 5 — a stuck in-flight claim — is NOT the explanation for T3**, since the
schedule was never reached: without a rotation, `scheduleDirectoryHydrationIfNeeded`
is not called at all. It remains unexcluded for the 21:50:33 event.

## 9.2 WHAT HAPPENED AT 21:50:33 IS STILL UNRESOLVED, AND MY BASELINE IS WHY

At 21:50:33 a rotation *did* occur, so hydration *was* scheduled. It may have
run and been suppressed at the band check (cause 2) or failed its directory read
(cause 3) — `privacy_rpc` 13 → 15 is consistent with that — or been blocked by a
stuck claim (cause 5).

**I cannot separate them, because I captured `dir_select` for the first time at
21:53, AFTER that event.** A directory read at 21:50:33 is already inside the
3347. That is a measurement failure on my part, not an ambiguity in the system.

## 9.3 THE RUN CANNOT PROGRESS ON THIS BINARY

Hydration is scheduled only by a **rotating** refresh, and the token minted at
21:50:33 stays valid until **~22:49**. Until then **every** foreground, and
**every relaunch**, takes the early return and schedules nothing. A force-quit
does not help: launch calls the same `ensureValidSession`.

So the options are to wait ~55 minutes for one more ambiguous single shot, or to
fix the regression — after which **every** foreground schedules hydration and
Gate (C) becomes **repeatably observable** instead of once-an-hour.

**The fix is the one already identified in §7.2** — schedule hydration on the
early-return path — and the re-entrancy guard (C) is what makes it safe, turning
the re-entrant schedule into a no-op instead of a spin.

**The one-shot no-row window is still INTACT:** `9c5385f6` has no directory row,
so nothing has been spent.

**Gate (C) remains UNTESTED.** Every token observation so far — 8→9, 9→10,
10→13, and now 15→16 — measures gate **(A)**. The hydration cycle has not run
once under Connected mode.
