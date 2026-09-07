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
