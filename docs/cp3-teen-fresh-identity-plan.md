# CP-3 — TEEN FRESH-IDENTITY RUN: PLAN AND PREDICTIONS. 2026-09-08

**NOTHING HAS BEEN EXECUTED. NO DELETION IS AUTHORISED.** This is the scoping
the account holder asked for, to be reviewed before any destructive action.
Repo `6da6f01`.

---

## 1. DOES `9c5385f6` HAVE ANY REMAINING CP-3 VALUE?

**Discharged, and nothing is left in these:**

| duty | status |
|---|---|
| Gate (C) — no refresh↔hydration loop | **device-verified** (10 preflights → 0 rotations, plus later repeats) |
| Resubscription/hydration regression | **device-verified** |
| Discriminator 4 — under-13 refusal | **device-verified, twice** |
| Discriminator 5 | **closed as device-unreachable** |
| Finding-A **short-circuit half** (band present ⇒ Apple not asked, nothing written) | **verified repeatedly** |
| Adult defaults at establishment | **already observed**: `lookup_enabled` true / `follow_requests_enabled` true, both `set_under_band` = `band_18_plus`, both `changed_at` **NULL** |
| Criterion 3 — directory publication | **structurally unavailable** on a Sandbox membership |

**ONE DUTY REMAINS, AND IT IS WORTH TAKING BEFORE DELETION.**

**`account_privacy_set_lookup_v1` — the discovery writer — HAS NEVER BEEN
CALLED.** Its `pg_stat_statements` entry is **null**, and `lookup_changed_at` is
**NULL**, which agrees.

The teen run's "explicit discovery opt-in and persistence" test **depends
entirely on that writer**. If it is broken, we would discover it *during* the
teen run and could not tell a teen-specific defect from a plumbing defect.

> **RECOMMENDATION: toggle `Let other members find you` once on the adult
> identity before deleting it** — proving the writer, the RPC, the
> `lookup_changed_at` stamp and the `lookup_set_under_band` stamp end to end on
> an identity that is about to be discarded anyway. **It costs nothing, because
> the row is about to be deleted.**

**This needs Connected mode** (both privacy controls sit inside
`canShowConnectedAccountManagement`), so it needs a purchase — see §4.0.

---

## 2. WHICH TEEN FIXTURE — **13–15**, and why

Both teen fixtures derive to `band_13_17`, so for **our** arithmetic they are
equivalent (`derive` maps 13-15 and 16-17 identically, and the unit suite already
asserts both).

**Recommend `13 - 15, significant change approved`.**

| | |
|---|---|
| **13-15** | `guardianDeclared`, significant change **approved** |
| 16-17 | `guardianDeclared`, significant change **DECLINED** |

**The 16-17 fixture carries a declined significant-app-update permission**, which
is a PermissionKit concern Études does not use — but it introduces a variable
that could plausibly affect app access and would sit in the middle of a run
whose results we need to attribute cleanly. **13-15 has no such rider.**

Secondary: 13-15 sits **further from the 18 boundary**, so a derivation defect
that only misfires near the boundary is more likely to show.

---

## 3. PREDICTED DELETION BLAST RADIUS

Measured inventory of what `9c5385f6` owns **now**:

| object | count | disposition on **Delete Account & All Études Data** |
|---|---|---|
| `auth.users` | 1 | **removed, strictly last** |
| `account_privacy` | **1** | **removed by FK cascade** — `account_privacy_user_id_fkey … ON DELETE CASCADE`. **Not by an explicit step**: the Edge Function never names the table |
| `membership` | **1** | removed by the `auth.users` cascade (retention matrix) |
| `membership_binding` | **1** | removed by the same cascade |
| `account_directory` | **0** | nothing to remove — **never published** |
| `posts` / `post_comments` / `follows` / `post_comment_views` | **0 / 0 / 0 / 0** | nothing |
| `connected_attachments` | **0** | nothing |
| storage objects matching the uid | **0** | nothing |
| `auth.sessions` / `auth.refresh_tokens` | **2 / 43** | removed with the user |

**Predicted post-deletion totals:** `auth.users` **2 → 1**, `account_privacy`
**1 → 0**, `membership` **1 → 0**, `membership_binding` **1 → 0**,
`account_directory` **1 → 1 (Samuel only)**.

**MUST NOT MOVE:** `dfaf8d18` — 248 tokens, 19 sessions, its directory row,
`posts` 6, `post_comments` 1. **`membership_notification` stays 104**; deletion
does not remove notification history.

**THE BLAST RADIUS IS UNUSUALLY SMALL** because this identity never published a
directory row, never posted, never followed and never sent an attachment. **It is
close to the cheapest possible identity to retire** — which is precisely why it
is the right one.

**One genuine unknown, flagged rather than predicted:** whether Apple's SIWA
credential revocation succeeds during deletion (C-44's path). It has failed
benignly before (`1001`, cancelled) and the deletion continued regardless, which
is the settled semantics. **Either outcome is acceptable and neither blocks.**

---

## 4. THE TEEN ACCEPTANCE SEQUENCE

### 4.0 Before deleting — the one remaining adult duty (§1)

Purchase Monthly → Connected → toggle **`Let other members find you`** OFF then
ON (or ON then OFF) → confirm `lookup_enabled` flips, `lookup_changed_at` is
**stamped**, and `lookup_set_under_band` reads **`band_18_plus`**. **Proves the
writer before the teen run depends on it.**

### 4.1 Delete

**Delete Account & All Études Data.** Measure §3's blast radius.

### 4.2 Set the fixture to `13 - 15, significant change approved`

### 4.3 Sign in via the ***returning*** path — NOT Continue. THIS IS THE KEY STEP

**Explore Connected → "Already have a Connected account?" → Sign In.**

**Why this and not Continue:** the `.returning` path **never calls
`requestAgeRange` and never sets `pendingAgeBand`** (§9 of the matrix;
`ProfileView:380`). So it creates a **fresh identity with NO band and nothing
pending** — which is *exactly* Finding-A's precondition, manufactured by the
product's own path rather than by contrivance.

**Continue would spoil it**, because it acquires the range *first* and hands the
band to the join flow.

**Measure:** `auth.users` **1 → 2** (new uuid, same Apple `sub`),
`account_privacy` **0 rows**. That zero **is** the Finding-A precondition.

### 4.4 Background → foreground: FINDING-A RECOVERY ESTABLISHES THE TEEN BAND

`AgeBandRecoveryCoordinator` runs on launch and every foreground, gated only on
`hasConnectedIdentity` + `backendConfigured` — **not** on Connected mode. With no
band, `fetchSelf` returns `.noBandEstablished`, so it **calls Apple**, gets
13-15, and writes via `upsertBand`.

**Predicted row:**

| column | predicted |
|---|---|
| `age_band` | **`band_13_17`** |
| `lookup_enabled` | **FALSE** — the protective default |
| `lookup_set_under_band` | **`band_13_17`** |
| `lookup_changed_at` | **NULL** |
| `follow_requests_enabled` | **FALSE** — protective |
| `follow_requests_set_under_band` | **`band_13_17`** |
| `follow_requests_changed_at` | **NULL** |

*(Adult comparison, measured: both `true`, both `set_under_band` `band_18_plus`,
both `changed_at` NULL.)*

**This single step scores THREE things at once: Finding-A recovery, 13–17
discovery default OFF, and the band-establishment path.**

### 4.5 Share default OFF — local, no server

Create a new session. **Share initialises OFF**, because
`shareDefaultOn(band: .band13to17, …)` returns false for any non-adult band.
Purely local (`ProfileStore.lastKnownAgeBand()`), so it needs **no entitlement**
and can be checked immediately.

### 4.6 Purchase → Connected → explicit discovery opt-in

Both privacy controls live inside `canShowConnectedAccountManagement`, so this
step **requires entitlement**. Toggle **`Let other members find you` ON**.

**Predicted:** `lookup_enabled` **true**, `lookup_changed_at` **stamped**,
`lookup_set_under_band` **still `band_13_17`** — it records the band the
preference was set *under*, and the band has not changed.

### 4.7 Persistence

Background → foreground → re-read. **`lookup_enabled` stays true and
`lookup_changed_at` does not move.** A teen's explicit choice must survive
hydration, which is the whole point of the column.

---

## 5. WHAT REMAINS BLOCKED AFTER ALL OF THIS

| discriminator | status after the teen run |
|---|---|
| **Strong band-before-directory ordering** | **STILL BLOCKED — and doubly.** The directory INSERT is gated by `enforcement_gate`, which is **false** for any Sandbox-only membership, so no row can publish on a Sandbox teen identity either. And even if one could, a refusal could not be attributed: the CP-1 trigger and the enforcement gate would **both** be refusing, and the two are indistinguishable from outside |
| **Criterion 3 — directory publication** | **STILL BLOCKED**, same cause |
| `.declinedSharing` and the other two branches of discriminator 5 | **closed as unreachable** — unchanged |

**Both remaining blocks need a Production entitlement, or the tester carve-out
D4 deliberately deferred. Neither is proposed, and enforcement is not to be
weakened.**

---

## 6. WHAT I AM ASKING FOR

**Nothing yet.** Review §1's recommendation (exercise the discovery writer before
deletion) and §2's fixture choice. **The deletion happens only on explicit
authorisation**, and I will take a fresh census immediately before it — the
inventory in §3 is dated the moment anything else happens.

---

# 7. REVISED PER ACCOUNT-HOLDER DIRECTION. 2026-09-08 10:04

## 7.1 The pre-qualification purchase is DROPPED

§1's recommendation is **withdrawn**. **The teen explicit-opt-in test is itself
the intended device exercise of `account_privacy_set_lookup_v1`.** If the writer
fails there it is a **CP-3 finding to be diagnosed**, not a reason to have spent
an extra purchase and lifecycle beforehand. Recorded so the earlier
recommendation is not re-proposed later.

## 7.2 UI gating for the discovery control — CHECKED IN SOURCE, to be confirmed on device

Not assumed:

```swift
public var canShowConnectedAccountManagement: Bool { mode == .connected }

static func resolve(auth: AuthManager, isEntitled: Bool) -> AppMode {
    guard BackendConfig.isConfigured else { return .solo }
    guard isEntitled          else { return .solo }      // ← entitlement required
    guard auth.hasConnectedIdentity else { return .solo }
    return .connected
}
```
`AppModeManager:109`, `:124-129`

Both privacy controls sit inside `canShowConnectedAccountManagement`, and
`applyDiscoverability` → `setLookupEnabled` has **exactly one call site**
(`ProfileView:742`, the toggle's `onChange`) — **there is no second surface**.

**So source says an entitlement is required.** Per direction this is **not
treated as settled**: after teen establishment, **look at Profile first**. If the
controls are visible in Solo, no purchase is needed and the source reading is
wrong. **Only if they are absent does a purchase enter the plan**, and it is
scoped then, not now.

## 7.3 THE MIDPOINT IS THE LOAD-BEARING MEASUREMENT — accepted, and it is the right one

**Stop after Sign In, before ANY background/foreground.** This is what proves we
**created** `identityWithoutBand` rather than **reconstructed** it after recovery
— a distinction that would be unrecoverable once the coordinator has run.

| midpoint check | predicted |
|---|---|
| **M-1** | `auth.users` **1 → 2**, and the new row's `id` is **NOT** `9c5385f6…` and **NOT** `dfaf8d18…` |
| **M-2** | `account_privacy` **0 rows for the new id** (and **0 rows total**, since the adult row is gone) |
| **M-3** | `account_directory` **1 row — Samuel only**; none for the new id |
| **M-4** | `membership` **0**, `membership_binding` **0** — nothing manufactured |
| **M-5** | `account_privacy_upsert_v1` **unchanged from the pre-deletion value** — no band writer call attributable to the new identity |

**M-5 is the sharpest of the five**: M-2 shows no row *now*, while M-5 shows none
was ever *attempted*.

## 7.4 PREDICTIONS FOR THE ONE TRANSITION

Background → foreground, exactly once, with the **13–15** fixture:

| | prediction |
|---|---|
| **T-1** | Apple's range is requested on real hardware — the coordinator reaches `requestRange` because `fetchSelf` returns `.noBandEstablished` |
| **T-2** | `account_privacy` **1 row**, `age_band` = **`band_13_17`** |
| **T-3** | `lookup_enabled` = **false** |
| **T-4** | `follow_requests_enabled` = **false** |
| **T-5** | `lookup_set_under_band` = **`band_13_17`** and `follow_requests_set_under_band` = **`band_13_17`** |
| **T-6** | `lookup_changed_at` **NULL** and `follow_requests_changed_at` **NULL** — defaults, not choices |
| **T-7** | **no directory publication** — `account_directory` stays **1**, `dir_ins` unchanged |
| **T-8** | **no pathological session/token behaviour** — a small bounded number of tokens, **zero sub-second gaps**, no ≥5 in any 10 s window |
| **T-9** | `account_privacy_upsert_v1` **+1 exactly** — one establishment, not a retry storm |

**Adult comparison, measured, so the teen values are read against something
real:** `band_18_plus` · both `enabled` **true** · both `set_under_band`
**`band_18_plus`** · both `changed_at` **NULL**.

**T-3/T-4 are the protective inversion** — the same columns that read `true` for
an adult must read `false` for a 13–17 band, from the same writer, with no client
involvement.

## 7.5 Then, separately: Share default OFF

Local only. Create a new session; **Share initialises OFF** because
`shareDefaultOn(band: .band13to17, …)` returns false for any non-adult band,
reading `ProfileStore.lastKnownAgeBand()`. **No entitlement, no server call.**

## 7.6 Then: the discovery opt-in chain

**OFF by default → explicit ON → `lookup_changed_at` stamped → survives
foreground/profile hydration → still ON.** Route determined by §7.2's on-device
check, not by assumption.

---

# 8. FRESH CENSUS — 2026-09-08 10:04:37 UTC

| measure | value |
|---|---|
| `auth.users` | **2** |
| `account_privacy` / `account_directory` | **1 / 1** |
| `membership` / `membership_binding` | **1 / 1** |
| `posts` / `post_comments` / `follows` | **6 / 1 / 0** |
| `membership_notification` | **104** |
| `9c5385f6` sessions / tokens | **2 / 43** |
| `dfaf8d18` sessions / tokens | **19 / 248** |

## 8.1 DELETION PREDICTION

| measure | before | **after** |
|---|---|---|
| `auth.users` | 2 | **1** |
| `account_privacy` | 1 | **0** — by FK cascade, not an explicit step |
| `membership` | 1 | **0** |
| `membership_binding` | 1 | **0** |
| `account_directory` | 1 | **1** (Samuel) |
| `posts` / `post_comments` / `follows` | 6 / 1 / 0 | **6 / 1 / 0 — UNCHANGED** |
| `membership_notification` | 104 | **104 — deletion does not remove history** |
| `dfaf8d18` sessions / tokens | 19 / 248 | **19 / 248 — UNCHANGED** |
| `9c5385f6` sessions / tokens | 2 / 43 | **0 / 0** |

**Device-side:** the app returns to Solo with no identity; Profile's destructive
action reverts to **"Erase All Études Data"**; the local journal is **untouched**
(invariant 1).

**Flagged, not predicted:** Apple SIWA credential revocation during deletion may
or may not succeed (C-44). It has previously failed benignly as `1001` cancelled
with the deletion continuing regardless, which is the settled semantics.
**Either outcome is acceptable and neither blocks the run.**

## 8.2 PHYSICAL STEPS — DELETION ONLY, ON EXPLICIT AUTHORISATION

1. **Tell me immediately before.** I take a final census; §8's numbers are stale
   the moment anything else happens.
2. Études → Profile → **Delete Account & All Études Data** → confirm.
3. **Stop.** Report what the app shows and whether an Apple re-authorisation
   sheet appeared. I measure §8.1.
4. **Only then** the fixture change, and the returning-path sign-in, and the
   midpoint measurement of §7.3 — each as its own step.

**NOT AUTHORISED AND NOT TO BE EXECUTED UNTIL THE ACCOUNT HOLDER SAYS SO.**

---

# 9. FINAL PRE-DELETE CENSUS — LOCKED 2026-09-08 10:09:05 UTC

**Deletion authorised by the account holder. I do not execute it.**

## 9.1 The two identities

| id | created | last sign-in | |
|---|---|---|---|
| `dfaf8d18-ca27-4e5a-b46f-3c75801492f0` | 2026-07-23 13:42:16 | 2026-09-02 11:14:38 | **Samuel — CONTROL, must not move** |
| `9c5385f6-7bb6-4044-b252-ffe841626b62` | 2026-09-07 13:34:54 | 2026-09-07 20:49:09 | **to be deleted** |

## 9.2 The orphan check is SYSTEMATIC, not a hand-picked list

**16 foreign keys reference `auth.users`, and every one is `ON DELETE CASCADE`:**
`account_directory`, `account_privacy`, `follows` (both columns), `membership`,
`membership_binding`, `membership_binding_conflict`, `shadow_enforcement_stat`,
and nine `auth.*` tables including `identities`, `sessions` and
`one_time_tokens`.

**`posts`, `post_comments`, `connected_attachments` and `post_comment_views` have
NO foreign key to `auth.users`** — consistent with the record that
`sender_user_id` is NOT NULL with no FK. **They do not cascade** and are the only
places a genuine orphan could arise. For this identity they are all **zero**, so
nothing should change; they are checked anyway, because "nothing to remove" and
"removed correctly" are different claims.

## 9.3 What `9c5385f6` holds, per cascade table

| table | rows |
|---|---|
| `account_privacy` | **1** |
| `membership` | **1** |
| `membership_binding` | **1** |
| `membership_binding_conflict` | **0** |
| **`shadow_enforcement_stat`** | **4** |
| `account_directory` | **0** — never published |
| `follows` | **0** |
| `auth.identities` | **1** |
| `auth.sessions` | **2** |
| `auth.refresh_tokens` | **43** |

**`shadow_enforcement_stat` was NOT in the earlier prediction and is added here.**
It cascades, so **4 of its 38 rows will disappear**. Precedent exists: CP-0 took
that table 79 → 75 for the same reason.

## 9.4 Totals to compare against

| measure | locked value |
|---|---|
| `auth.users` | **2** |
| `account_privacy` / `account_directory` | **1 / 1** |
| `membership` / `membership_binding` | **1 / 1** |
| **`shadow_enforcement_stat`** | **38** |
| `posts` / `post_comments` / `follows` | **6 / 1 / 0** |
| `connected_attachments` / `post_comment_views` | **25 / 3** |
| `storage.objects` | **8** |
| `membership_notification` | **104** |
| `dfaf8d18` sessions / tokens | **19 / 248** |
| `account_privacy_upsert_v1` / `set_lookup_v1` / `self_v1` | **2 / never called / 46** |
| `account_directory` INSERT | **2795** |

## 9.5 PREDICTED POST-DELETION STATE

| measure | before | **predicted after** |
|---|---|---|
| `auth.users` | 2 | **1** |
| `account_privacy` | 1 | **0** — FK cascade, no explicit step |
| `membership` / `membership_binding` | 1 / 1 | **0 / 0** |
| **`shadow_enforcement_stat`** | 38 | **34** |
| `account_directory` | 1 | **1 — Samuel only** |
| `posts` / `post_comments` / `follows` | 6 / 1 / 0 | **6 / 1 / 0 — UNCHANGED** |
| `connected_attachments` / `post_comment_views` | 25 / 3 | **25 / 3 — UNCHANGED** |
| `storage.objects` | 8 | **8 — UNCHANGED** |
| `membership_notification` | 104 | **104 — history is not deleted** |
| `dfaf8d18` sessions / tokens | 19 / 248 | **19 / 248 — UNCHANGED** |
| `9c5385f6` identities / sessions / tokens | 1 / 2 / 43 | **0 / 0 / 0** |

**Writer counters may move** — deletion runs through the Edge Function, and any
foreground before it can preflight. **They are not assertions here**; the
assertion is that `account_privacy` reaches **0 rows**.

## 9.6 THE LOCAL/CLIENT ASSERTION IS CORRECTED

**Per direction: do NOT require the client to land in Solo.** Onboarding has been
observed after this destructive lifecycle before (C-49's shape), and either is
legitimate.

> **The load-bearing client assertion is that the Connected identity and
> account-management state are GONE** — no Connected account management, no
> Connected identity. **Whatever screen Études lands on is RECORDED, not scored.**

## 9.7 SIWA REVOCATION IS RECORDED SEPARATELY FROM DELETION SUCCESS

**These are two different outcomes and must not be merged.** Apple's
revocation/re-authorisation may appear and may succeed, or may fail benignly —
the documented precedent is `1001` **cancelled**, after which **the account
deletion continued regardless**, which is the settled semantics.

**Deletion success is judged on §9.5's server state alone.** The revocation
outcome is recorded as its own fact, whichever way it goes, and **a failed or
cancelled revocation does not make the deletion a failure.**

**CENSUS LOCKED. Awaiting the account holder's execution.**

---

# 10. DELETION VERIFIED — 2026-09-08. ALL PREDICTIONS MATCH

**Reported by the account holder:** Apple's sheet **appeared and completed**;
Études landed on **onboarding**.

## 10.1 Every predicted number matched, nothing repaired forward

| measure | locked | predicted | **observed** | |
|---|---|---|---|---|
| `auth.users` | 2 | 1 | **1** | PASS |
| `account_privacy` | 1 | **0** | **0** | PASS — by FK cascade |
| `membership` | 1 | 0 | **0** | PASS |
| `membership_binding` | 1 | 0 | **0** | PASS |
| **`shadow_enforcement_stat`** | 38 | **34** | **34** | **PASS** |
| `account_directory` | 1 | 1 | **1** | PASS |
| `posts` / `post_comments` / `follows` | 6 / 1 / 0 | unchanged | **6 / 1 / 0** | PASS |
| `connected_attachments` / `post_comment_views` | 25 / 3 | unchanged | **25 / 3** | PASS |
| `storage.objects` | 8 | unchanged | **8** | PASS |
| `membership_notification` | 104 | unchanged | **104** | PASS |
| `dfaf8d18` sessions / tokens | 19 / 248 | unchanged | **19 / 248** | PASS |

**`shadow_enforcement_stat` 38 → 34 is the sharpest of these.** It was **absent
from the first blast-radius prediction** and added only when the FK enumeration
surfaced it; it then landed on the predicted value exactly. **A count that was
nearly missed and then matched is better evidence than one that was obvious.**

## 10.2 The identity is gone, and the residue sweep is systematic

`auth.users` holds **only** `dfaf8d18`. Every cascade table returns **zero** rows
for `9c5385f6`: `account_privacy`, `membership`, `membership_binding`,
`membership_binding_conflict`, `account_directory`, `shadow_enforcement_stat`,
`follows`, `auth.identities`, `auth.sessions`, `auth.refresh_tokens`.

**The four NON-cascading tables were swept separately by prefix**, because they
would not have cascaded and are the only place an orphan could live:
`posts.owner_user_id` **0**, `post_comments.author_user_id` **0**,
`connected_attachments` (sender or recipient) **0**,
`post_comment_views.viewer_user_id` **0**, and `storage.objects` names containing
the uid **0**.

**No orphan or residual state attributable to the deleted identity.**

## 10.3 Samuel is untouched, verified on content not just counts

`dfaf8d18`: **19** sessions, **248** refresh tokens — both unmoved — and his
directory row reads **byte-identical**: `Samuel Dixon | samueldixon | London`.

## 10.4 The two client facts, recorded separately as required

| | |
|---|---|
| **Apple SIWA revocation** | **appeared and completed.** Recorded as its own fact. Unlike the documented `1001` benign-cancellation precedent, this one succeeded |
| **Études landed on** | **onboarding** — **recorded, not scored**, exactly as directed |

**The load-bearing client assertion holds:** the Connected identity and
account-management state are gone. Onboarding is a legitimate post-destructive
landing and matches the C-49 shape observed before.

**Deletion success was judged on server state alone**, and the revocation outcome
did not enter that judgement — it simply happens to have succeeded this time.

## 10.5 STATE NOW

**Production holds exactly one identity — Samuel — and no `account_privacy` row
at all.** The Device A Apple Account has no Études backend identity, and the
Age Assurance fixture is still **Under 13**.

**The `identityWithoutBand` fixture has NOT yet been created.** The next step is
the fixture change to **13–15**, then the **returning-path** sign-in, then the
**midpoint measurement of §7.3 before any foreground**. **Not started, and not to
be started without direction.**

---

# 11. MIDPOINT BASELINE — LOCKED 2026-09-08 10:15:19 UTC

| measure | locked value |
|---|---|
| `auth.users` | **1** — `dfaf8d18…` only |
| **`account_privacy`** | **0 rows** |
| `account_directory` | **1** (Samuel) |
| `membership` / `membership_binding` | **0 / 0** |
| `shadow_enforcement_stat` | **34** |
| `posts` / `membership_notification` | **6 / 104** |
| `auth.sessions` / `auth.refresh_tokens` **totals** | **19 / 248** — all Samuel's |
| **`account_privacy_upsert_v1` (writer)** | **2** |
| `account_privacy_set_lookup_v1` | **never called** |
| `account_privacy_self_v1` | **48** |
| `account_directory` INSERT / SELECT | **2795 / 3366** |

**Totals equal Samuel's**, so any session or token appearing is unambiguously the
new identity's — no attribution work needed.

## 11.1 A RISK TO THE MIDPOINT, AND THE INSTRUCTION IT FORCES

**`AgeBandRecoveryCoordinator` fires on EVERY foreground** and is gated only on
`hasConnectedIdentity` (`:50`). **Before** sign-in that guard is false, so
returning from Settings after the fixture change is **safe**. **After** sign-in
it is true — and the coordinator would immediately call Apple and **write the
band**, destroying the midpoint before it can be measured.

> **AFTER SIWA COMPLETES, DO NOT LEAVE ÉTUDES.** No backgrounding, no switching
> to Settings, no locking the screen, until I confirm the midpoint is measured.
> Navigation *inside* the app is fine — `scenePhase` does not change for that.

**A residual risk I cannot exclude:** Sign in with Apple presents a system sheet,
and I cannot prove from here whether its dismissal produces a `scenePhase`
transition. If it does, recovery may fire before I measure.

**That is a named alternative outcome, not a failure.** It would show as
`account_privacy` already holding **1 row** at the midpoint. If so I will record
that the platform pre-empted the midpoint, and Finding-A's *recovery* would still
be evidenced — only the *"created rather than reconstructed"* proof would be lost.
**I will report it as such rather than presenting a pre-empted midpoint as a
clean one.**

## 11.2 MIDPOINT PREDICTIONS

| | prediction | falsifier |
|---|---|---|
| **M-1** | `auth.users` **1 → 2**; the new `id` is **neither** `dfaf8d18…` **nor** `9c5385f6…` | a reused uuid — which would contradict the D15 precedent and be a finding in its own right |
| **M-2** | `account_privacy` **0 rows** — none for the new identity, none at all | any row ⇒ midpoint pre-empted (§11.1) |
| **M-3** | `account_directory` **1** — Samuel only | any second row |
| **M-4** | `membership` **0**, `membership_binding` **0** | anything manufactured |
| **M-5** | **`account_privacy_upsert_v1` still exactly 2** | any increase ⇒ a band write was attempted |
| **M-6** | sessions/tokens rise by a **small bounded** amount for the new identity; **no sub-second gaps**, no ≥5 tokens in any 10 s window | a burst |

**M-5 is the sharpest.** M-2 shows no row exists *now*; **M-5 shows none was ever
attempted** — together they establish `identityWithoutBand` was **created**, not
reconstructed after the fact.

**`account_privacy_self_v1` is expected to MOVE** (sign-in and any preflight read
it) and is **not** an assertion — reading is not writing.

## 11.3 PHYSICAL STEPS

1. **Settings → Developer → Sandbox Apple Account → Manage → Age Assurance →
   `13 - 15, significant change approved`.** *(Returning to Études afterwards is
   safe: no identity yet, so the coordinator's first guard fails.)*
2. **Open Études; complete onboarding if it asks.** Local only — no identity, no
   server effect.
3. **Profile → Explore Connected → "Already have a Connected account?" → Sign In.**
   **NOT "Continue"** — `.returning` never calls `requestAgeRange` and never sets
   `pendingAgeBand` (`ProfileView:380`), which is what leaves the identity
   band-less.
4. **Complete SIWA.**
5. **STOP. Stay in Études.** Do not background, do not open Settings, do not lock
   the screen. Tell me what screen Études shows.
6. I measure the midpoint and report. **Only then** the single
   background → foreground.

**The midpoint and the recovery measurements are kept separate, as directed.**

---

# 12. MIDPOINT ESTABLISHED — 2026-09-08 10:20:23 UTC

**`identityWithoutBand` is CREATED, not reconstructed.** All six predictions pass,
with independent corroboration.

**The new identity is `c584db5b-5648-4755-9063-5c24763f8819`**, created
2026-09-08 10:19:33.729844, first sign-in 10:19:33.779196.

| | prediction | observed | |
|---|---|---|---|
| **M-1** | `auth.users` 1 → 2, new id ≠ `dfaf8d18` and ≠ `9c5385f6` | **2**, `c584db5b…` | **PASS** |
| **M-2** | `account_privacy` **0 rows** | **0** | **PASS — midpoint NOT pre-empted** |
| **M-3** | `account_directory` 1, Samuel only | **1** | **PASS** |
| **M-4** | `membership` 0, `membership_binding` 0 | **0 / 0** | **PASS** |
| **M-5** | writer still exactly **2** | **2** | **PASS** |
| **M-6** | small bounded, no sub-second gaps, no ≥5 per 10 s | **1 token, 1 session** | **PASS** |

## 12.1 A PREDICTION OF MINE WAS WRONG, AND BEING WRONG STRENGTHENS THE RESULT

**I predicted `account_privacy_self_v1` would move.** It did **not** — still
**48**. *(It was explicitly recorded as not an assertion, so nothing is being
reinterpreted after the fact.)*

**The reason matters.** `supabaseSignIn` schedules hydration, but
`scheduleDirectoryHydrationIfNeeded` guards on `isConnected`, which is **false**
in Solo — so `fetchSelf` was never called. **The recovery coordinator has
provably not run at all.**

**Three independent statements, not one:**

- **M-2** — no `account_privacy` row exists;
- **M-5** — no write was ever *attempted*;
- **flat read counter** — nothing even *looked*.

## 12.2 The §11.1 residual risk did NOT materialise — now measured

Dismissing Apple's SIWA sheet produced **no `scenePhase` transition**, so recovery
did not pre-empt the midpoint. **Measured, where §11.1 could only flag it as
unexcludable.**

## 12.3 D15's precedent confirmed a second time

The **same primary Apple Account**, after a real account deletion, produced a
**brand-new backend identity** — `9c5385f6` → `c584db5b` — exactly as `cfadb7cb`
→ `5ae3faab` did on 2026-08-15. **Deletion frees the `sub`; revocation alone does
not.** The account holder's correction to the matrix is now twice-measured.

## 12.4 Minimum-possible footprint

Exactly **1 refresh token** and **1 session** for the new identity, both stamped
at the sign-in instant. **No gaps exist to be pathological.** Samuel unchanged at
**248 / 19**.

## 12.5 Client state — recorded, not scored

Études landed on **PracticeTimerView**. Same shape as the previously logged
post-sign-in deviation (`ProfileView:1975`'s gate branch returning early before
the `.returning` unwind at `:2005`). **Out of scope, unchanged, still logged.**

## 12.6 NEXT — one transition, nothing else

Predictions T-1…T-9 (§7.4) stand unmodified, with the writer's baseline now
pinned: **`account_privacy_upsert_v1` must go 2 → 3, exactly +1.**

**Not started. Awaiting the account holder.**

---

# 13. RECOVERY MEASUREMENT — 2026-09-08 10:24:44. NO BAND WAS ESTABLISHED

One background → foreground. Deltas from the midpoint:

| measure | midpoint | **after** | Δ | |
|---|---|---|---|---|
| `account_privacy` rows | 0 | **0** | **+0** | **T-2…T-6 NOT MET** |
| **`account_privacy_self_v1`** | 48 | **50** | **+2** | the coordinator **did run and did read** |
| **`account_privacy_upsert_v1`** | 2 | **2** | **+0** | **T-9 NOT MET — no write attempted** |
| `account_directory` rows / INSERT | 1 / 2795 | **1 / 2795** | +0 | **T-7 PASS** |
| tokens / sessions (new identity) | 1 / 1 | **1 / 1** | +0 | **T-8 PASS** |
| `membership` / `binding` | 0 / 0 | **0 / 0** | +0 | PASS |
| Samuel tokens | 248 | **248** | +0 | PASS |

**The recovery path executed and declined to write.** Reads moved; the writer did
not. That is the coordinator behaving **correctly for some input it received** —
`bandToEstablish` maps `.ineligible` and `.unavailable` to **nil**, and a nil band
returns without writing. **Only a derived band may ever be written**, which is the
protective design working, not failing.

**So the question is not "why did the writer not fire" — it is "what did Apple
return".**

## 13.1 T-1 IS THE ONE THAT MATTERS AND IT IS UNRESOLVED

**T-1 predicted "Apple's range is requested on real hardware."** Whether
`requestRange()` was reached at all cannot be settled from the server:

- **one** attempt that got a nil band returns **before** `ensureAgeBandEstablished`, costing **1** read;
- **two** attempts of that shape cost **2** reads;
- **one** attempt that reached `ensureAgeBandEstablished` also costs **2** reads — but that path would then have called `upsertBand` unless its own `fetchSelf` returned a non-`noBandEstablished` failure.

**+2 is consistent with more than one story, and I am not going to pick one.**

## 13.2 CANDIDATE CAUSES — NONE EXCLUDED, AND ONE IS OUR OWN DOING

1. **The Age Assurance fixture is still `Under 13`.** Then `.ineligible` → nil
   band → no write, and the coordinator is simply correct.
2. **Apple presented its system sheet and it was not completed.** `Share with
   Apps` is on **Ask First**, and **our own discriminator-5 excursion set it to
   `Never` and back** — which the account holder observed *"turns off the Études
   sharing state"*. If Études' per-app consent was cleared by that excursion,
   Apple **must prompt again**, and a prompt arriving during a
   background→foreground is easy to miss or dismiss. **That would be
   cross-contamination from our own earlier test**, and it is the hypothesis I
   consider most likely.
3. **`fetchSelf` returned a transport failure** rather than `.noBandEstablished`,
   so the coordinator returned early — deliberately, since *"transport or session
   trouble is NOT no band"*.

**This is not diagnosable from the server. The decisive facts are on the device.**

## 13.3 WHAT I NEED BEFORE ANY FURTHER DEVICE ACTION

**No instruction to act — three observations only:**

1. **Did an Apple system sheet appear at any point** during or after the
   background→foreground, and if so what did it say and what happened to it?
2. **What does Settings → Developer → Sandbox Apple Account → Manage → Age
   Assurance read right now?** — confirming whether it is `13 - 15, significant
   change approved` or still `Under 13`.
3. **What does Apple Account → Personal Information → Age Range for Apps show
   for Études now?** — is it still listed as **Shared**, or has our `Never`
   excursion left it unshared?

**Observation 3 is the sharpest**, because it would confirm or kill hypothesis 2
outright — and hypothesis 2 is a defect in **our test sequencing**, not in the
product.

## 13.4 WHAT IS ALREADY SAFE TO SAY

- **The midpoint stands.** `identityWithoutBand` remains established and
  **undisturbed** — still 0 privacy rows, still writer at 2. Nothing about this
  result weakens §12.
- **T-7 and T-8 pass:** no directory publication, and **no token rotation at
  all** — the expiry gate held on a five-minute-old token, so Gate (C) is
  incidentally reconfirmed once more.
- **No protective default was written on a doubtful input**, which is the
  behaviour CP-3 wants: an unresolved age answer must establish **nothing**.

---

# 14. FINDING: THE RECOVERY PATH'S `requestAgeRange` IS READ FROM `App` SCOPE

## 14.1 The trace, step by step

**Was `requestAgeRange` reached? YES, necessarily — established, not assumed.**

`account_privacy_self_v1` is `STABLE SECURITY DEFINER`, plain SQL, **no guards
and no enforcement gate**, and for an identity with no row it returns **zero
rows**. The client maps an empty row set to **`.noBandEstablished`**
(`AccountPrivacyService`: `isEmptyRowSet(data) ? .noBandEstablished : …`). And
`pg_stat_statements` proves the statement **executed twice**.

So `fetchSelf` returned `.noBandEstablished` → the switch **breaks** → **`requestRange()` is called.** The three candidates resolve:

| candidate | verdict |
|---|---|
| `fetchSelf` → `.noBandEstablished`, proceeds to Apple | **THIS ONE** |
| transport/read failure → early return **before** Apple | **excluded** — the RPC is guard-free, executed, and returns `[]`, which maps to `.noBandEstablished`, not to a failure |
| Apple called, returned a non-band | **the observable**, and the question becomes *why* |

**And any band result would have written.** `bandToEstablish` maps `.band(x)` → x,
`pendingAgeBand` is set, and `ensureAgeBandEstablished` would `upsertBand`.
**Writer +0 ⇒ no band came back.** With the fixture at **13-15** and Études
listed **Shared**, a correct action should have returned bounds — from cache if
need be, **which is also why no sheet is expected**.

## 14.2 THE TWO CALL SITES READ THE ACTION FROM DIFFERENT SCOPES

| call site | declares at | scope | on device |
|---|---|---|---|
| `AgeBandRecoveryCoordinator` | `MOTIVOApp:87` | **`struct MOTIVOApp: App`** (`:67`) — **an App, not a View** | **no sheet, no band, silent** |
| `ProfileView`'s Continue | `ProfileView:327` | **a `View`** | **works — the under-13 alert fired twice, and the fixture change was honoured** |

**`requestAgeRange` presents system UI and needs a presentation context.**
`@Environment(\.scenePhase)` resolves in `App` scope; **a presentation-requiring
action is a different matter.** A throw is caught at `MOTIVOApp:461` and mapped
to `.unavailable` — **silently**, which is exactly the observable: no sheet, no
band, no write, no error surfaced.

## 14.3 CERTAINTY, STATED HONESTLY

**Established:** the RPC executed twice; the writer never ran; no sheet appeared;
the fixture is 13-15; Études is `Shared`; the two call sites read the action from
different scopes; **the View-scope one demonstrably works on this device.**

**Inferred, not proven:** that the App-scope action *throws*. I have not observed
the throw — the `catch` is silent and the build is Release. What is shown is that
the observable is **consistent with it and inconsistent with every alternative I
can check**: a band would have written, a decline contradicts `Shared`, and an
`.ineligible` contradicts the 13-15 fixture.

## 14.4 WHY NO TEST CAUGHT THIS, AND IT IS A KNOWN FAILURE MODE

`recoverIfNeeded(auth:reason:now:requestRange:)` takes the range provider **as a
parameter**, and the five unit tests pass a **stub**. The defect is in the
**wiring at the call site**, which no unit test touches — the suite validated the
coordinator's logic and could never validate where its input comes from.

**This project has already recorded this exact lesson**, from C-44:

> *"A probe validates a mechanism, not the presentation context it ships in.
> Where a probe's environment differs from the shipping call site, that
> difference is untested surface."*

**Finding-A was `fixed locally, NOT device-verified` in the handover, and this is
what that gap was hiding.**

## 14.5 CONSEQUENCE

**As shipped, Finding-A's recovery cannot establish a band.** An
`identityWithoutBand` would stay band-less across every launch and foreground —
which is precisely the state Finding-A exists to repair. **The short-circuit half
works** (verified extensively on the adult identity); **the recovery half does
not.**

**Recorded as a CP-3 finding to be diagnosed, exactly as directed for
writer-class failures. Not fixed here.**

**Likely shape of the fix, not implemented:** read `requestAgeRange` in a **View**
and hand it to the coordinator, rather than reading it in the `App`. `ProfileView`
already demonstrates the working pattern.

## 14.6 THE MINIMUM NEXT OBSERVATION — and what it costs

**The fixture's purpose was to test Finding-A recovery. It has now done that, and
the answer is that recovery is broken.** Preserving it further protects a test
whose result is already in.

| option | what it settles | cost |
|---|---|---|
| **A. Cold launch** (force-quit, reopen) | fires the **launch** site (`:283`) — but that reads the **same App-scope action**, so it should fail identically. Strengthens the pattern; **cannot prove the diagnosis** | free; fixture preserved |
| **B. Explore Connected → Continue** | uses **ProfileView's View-scope action** with the *same* fixture and consent. **If a band comes back, the contrast is decisive**: the same request succeeds from a View and fails from the App | it **writes `band_13_17`** via the join path, so the teen band is established by a working route — and Finding-A's recovery is not demonstrated by the coordinator, **which it already cannot be** |

**Recommendation: B.** It is the only option that *discriminates* rather than
repeats, and it simultaneously unblocks the teen sequence — teen defaults, Share
default OFF, and the discovery opt-in — all of which need a band that the
coordinator cannot currently write.

**Not executed. No device action requested until the account holder decides.**

---

# 15. THE WIRING FIX — IMPLEMENTED, NOT DEVICE-VERIFIED. 2026-09-08

## 15.1 Mechanism wording, kept honest

**What is established:** the shipped recovery wiring **does not establish a band
on-device**. Reads moved `48 → 50`, the writer stayed at **2**, no sheet
appeared, with the fixture at 13-15 and Études `Shared`.

**What is the leading source-level explanation, not a direct observation:**
`@Environment(\.requestAgeRange)` read from **`App` scope** lacks a presentation
context. **The thrown error was never directly observed** — the `catch` is silent
and the device runs Release. That wording is carried into the source comment
itself, so the code does not overclaim either.

## 15.2 The architecture, verified before changing anything

`requestAgeRange` is a SwiftUI **environment action that presents system UI**.
`ProfileView` already demonstrates the working pattern: declare it in a **View**
(`:327`) and call it there (`:1116`). **The fix reuses exactly that**, rather
than introducing a second mechanism.

**`AgeBandRecoveryTrigger`** — a `ViewModifier` that declares its own
`@Environment(\.requestAgeRange)`, owns the launch and foreground triggers, and
hands the action to the coordinator. Attached to the root view via
`.ageBandRecovery(coordinator:auth:)`.

**Against each constraint:**

| constraint | how it is met |
|---|---|
| recovery still belongs to the coordinator | the modifier only calls `coordinator.recoverIfNeeded`; **all** policy stays inside it |
| action from a valid View presentation context | declared in a `ViewModifier`; the App declares **none** |
| nothing persisted | no `UserDefaults`, `Keychain`, `ProfileStore`, Core Data, and it never touches `pendingAgeBand` |
| existing-band short-circuit unchanged | untouched in the coordinator |
| unavailable/ineligible/error fail-closed | unchanged: `catch → .unavailable`, and only `bandToEstablish` may yield a band |
| single-flight / cooldown unchanged | untouched in the coordinator |
| no new UI | the modifier renders nothing; asserted for `Text`, `Button`, `.sheet`, `.alert`, `NavigationStack` |

**One deliberate detail:** the coordinator is held as a plain `let`, **not** an
`@ObservedObject`. The modifier only calls a method, and subscribing would add a
re-render source to the root view for no benefit — **which is the shape of
C-55**.

## 15.3 THE REGRESSION IS STRUCTURAL, AND THAT IS THE POINT

`supabase/tests/p5/cp3-agerange-wiring.sh` — **35 assertions**.

**A stubbed provider cannot catch this defect, by construction: it replaces the
very thing that was broken.** Five coordinator unit tests passed throughout while
the shipped path could not establish a band. So the regression asserts the
**wiring** — which scope reads the action, which types may call it, and that
nothing was smuggled in to work around it. Same idiom as C5f-12.

**Non-vacuity, measured against the pre-fix tree:**

| assertion | pre-fix | post-fix |
|---|---|---|
| **W-1** `@Environment(\.requestAgeRange)` in `MOTIVOApp` | **1** | **0** |
| W-1b any `requestAgeRange` reference in the App | **3** | **0** |
| W-1d the App-scope bridge `recoverAgeBandIfNeeded` | **3** | **0** |
| **W-3** files calling `requestAgeRange(` | `MOTIVOApp.swift ProfileView.swift` | **`AgeBandRecoveryTrigger.swift ProfileView.swift`** |

**W-3 is the durable one:** it pins that every caller is a View-layer type, so a
future call added from `App` scope — the exact defect — fails immediately.
W-4b/W-4c additionally forbid "fixing" it by moving the environment read *into*
the coordinator, which would restore an App-shaped problem and destroy its
testability.

## 15.4 Evidence

- **Debug and Release both build clean.**
- **`MOTIVOTests` 87 passed / 0 failed / 0 skipped** — unchanged; the coordinator's
  logic was not touched.
- **`cp3-agerange-wiring` 35/35**; **`session-refresh-acceptance` 34/34.**

## 15.5 THE FIXTURE IS EXACTLY PRESERVED — verified read-only after the work

| | |
|---|---|
| fresh identity | **`c584db5b-5648-4755-9063-5c24763f8819`** present |
| `account_privacy` | **0 rows** |
| `account_privacy_upsert_v1` | **2** |
| `membership` / `membership_binding` | **0 / 0** |
| `account_directory` | **1** — Samuel only |
| `auth.users` | **2** |

Device untouched: no Explore Connected, no purchase, no deletion, no band
manufactured. Age Assurance remains **13-15**; Études remains **`Shared`**.

## 15.6 NOT DEVICE-VERIFIED

**This fix has not been run on hardware.** The decisive test is installing it
over the top and letting **this same untouched `identityWithoutBand`** take one
background→foreground — the exact experiment that failed at `d03324f`. **A
structural suite proves the wiring changed; only the device can prove the band
gets written.**

---

# 16. FINDING-A HARDWARE VERIFICATION — BASELINE LOCKED 2026-09-08 12:23:50 UTC

Repo `792bfbc`, local == origin, tree clean.

## 16.1 FA-BASE

| measure | value |
|---|---|
| `auth.users` | **2** |
| **`account_privacy`** | **0 rows** |
| `account_directory` | **1** (Samuel) |
| `membership` / `membership_binding` | **0 / 0** |
| `shadow_enforcement_stat` / `membership_notification` | **34 / 104** |
| **`account_privacy_upsert_v1` (writer)** | **2** |
| `account_privacy_self_v1` | **51** |
| `account_directory` INSERT | **2795** |
| `c584db5b` tokens | **1**, last **10:19:33**, **age 124.3 min** |
| `dfaf8d18` tokens | **248** |

**This is the SAME identity and the SAME server state that failed at `d03324f`** —
not a recreated fixture. That is what makes the comparison decisive.

**Two changes since the failure, both consequential:**

**(a) `account_privacy_self_v1` moved 50 → 51.** A *third* recovery attempt has
happened during ordinary phone use, and it **read and did not write** — the same
broken signature again. Unasked-for corroboration of the defect.

**(b) The access token is now 124 minutes old — EXPIRED.** At the failure it was
five minutes old and the expiry gate correctly held. **So this run should rotate
exactly once**, and my earlier "no rotation" expectation would now be wrong.

## 16.2 THE INSTALL ITSELF WILL FIRE THE LAUNCH TRIGGER

Installing from Xcode **launches the app**, and `AgeBandRecoveryTrigger`'s
`.onAppear` runs at launch. **So the band may be established by the install
itself, before the deliberate background→foreground.**

**Both are passes** — launch and foreground go through the same View-scoped
wiring — but they are different observations, and the failure at `d03324f` was on
a *foreground*. **So measure after the install-launch, then again after the
transition.** One extra round trip buys clean attribution; without it a pass
cannot be assigned to a trigger.

## 16.3 PREDICTIONS

| | prediction | falsifier |
|---|---|---|
| **FA-1** | Apple's real action is reached and **returns a band** — evidenced by the writer moving, **not** by any sheet appearing | writer flat |
| **FA-2** | **`account_privacy_upsert_v1` 2 → 3, exactly +1** | 2 (no write) or ≥4 (retry storm) |
| **FA-3** | `account_privacy` **0 → 1**, `user_id` = `c584db5b…`, `age_band` = **`band_13_17`** | absent, or `band_18_plus` |
| **FA-4** | `lookup_enabled` = **false** | true — a minor defaulted discoverable |
| **FA-5** | `follow_requests_enabled` = **false** | true |
| **FA-6** | both `*_set_under_band` = **`band_13_17`** | `band_18_plus` |
| **FA-7** | both `*_changed_at` = **NULL** | stamped — a default recorded as a choice |
| **FA-8** | `account_directory` **1**, `dir_ins` **2795** — no publication (hydration is `isConnected`-gated and the client is Solo) | a second row |
| **FA-9** | `membership` **0**, `membership_binding` **0** | anything manufactured |
| **FA-10** | tokens **1 → 2**, exactly **+1** (the 124-minute token ages out once). **Zero sub-second gaps**, no ≥5 in any 10 s window | a storm |
| **FA-11** | Samuel **248** tokens, directory row unchanged, `auth.users` **2** | any movement |

**The signature to look for.** The failing runs were **reads up, writer flat**.
A success is **`privacy_read` +2 with `writer` +1** — the coordinator's own
`fetchSelf`, then `ensureAgeBandEstablished`'s check, then the write. *(The read
delta is corroboration, not an assertion.)*

**FA-4 through FA-7 are the protective inversion**, read against the measured
adult row from the deleted identity: `band_18_plus`, both **true**, both
`set_under_band` `band_18_plus`, both `changed_at` NULL.

## 16.4 PHYSICAL SEQUENCE

0. **Confirm the scheme's Run action is Release** before installing. Debug uses a
   different bundle id, which is a *different app* with no identity — it would
   look like the fixture had vanished. *(Verified in the project earlier; worth
   one glance.)*
1. **Install the current build over the existing installation.** **No delete, no
   reset** — the identity lives in the Keychain and the container must survive.
2. **Age Assurance stays at `13 - 15, significant change approved`.** Change
   nothing in Settings.
3. **Let the app finish launching, then STOP and tell me.** I measure — this
   attributes any result to the **launch** trigger.
4. **One controlled background → foreground.**
5. **Stop and tell me.** I measure again.

**If Apple presents system UI:** stop and **describe it before interacting**. If
it is plainly the standard *"share your age range with Études"* prompt, sharing
is the intended flow and consistent with Études already being listed `Shared`;
**anything else, do not tap.** **Presentation is not success** — success is the
writer moving, and a sheet could appear and still yield nothing.

**Not to be followed by Share-default or discovery-opt-in testing.** Measure,
stop, report.

---

# 17. RESULT — 2026-09-08 12:31. THE WIRING FIX IS DEVICE-VERIFIED. THE BAND VALUE IS NOT WHAT WAS PREDICTED

## 17.1 THE DECISIVE COMPARISON PASSES

**Same identity, same server state, same trigger, one code change:**

| | before the fix (`d03324f`) | **after the fix** |
|---|---|---|
| `account_privacy_self_v1` | 48 → 50 (**+2**) | 51 → **54** (+3) |
| **`account_privacy_upsert_v1`** | 2 → **2 (+0)** | **2 → 3 (+1)** |
| `account_privacy` rows | **0** | **1** |

**FA-1 and FA-2 PASS.** Reading `requestAgeRange` from a **View** reached Apple
and established a band where the App-scope read never did. **The band was written
by the LAUNCH trigger** — row `band_updated_at` **12:30:51.055**, 1.6 s after the
token rotation at 12:30:49.444, on the install-launch.

**That is the whole point of the fix, and it is now hardware-verified on the very
fixture that failed.**

## 17.2 BUT THE BAND IS `band_18_plus`, NOT `band_13_17`

```
age_band                        band_18_plus     ← predicted band_13_17
lookup_enabled                  true             ← predicted false
follow_requests_enabled         true             ← predicted false
lookup_set_under_band           band_18_plus     ← predicted band_13_17
follow_requests_set_under_band  band_18_plus     ← predicted band_13_17
lookup_changed_at               NULL             ← predicted NULL  ✓
follow_requests_changed_at      NULL             ← predicted NULL  ✓
```

**FA-3 fails on the VALUE** (the row exists, for the right identity, but with the
wrong band). **FA-4, FA-5 and FA-6 fail — but only as CONSEQUENCES of the band,
not as independent defects.**

**Given `band_18_plus`, every one of those values is CORRECT.** They match the
adult row from the deleted identity **exactly**: both flags `true`, both
`set_under_band` `band_18_plus`, both `changed_at` NULL. **The defaults logic
behaved correctly for the band it was handed.**

**So the protective inversion was NOT tested — not because it is broken, but
because no teen band was ever produced.** Those three must be recorded as
**untested**, not as failed.

## 17.3 WHY APPLE RETURNED 18+ IS UNKNOWN, AND I AM NOT GOING TO GUESS

The Sandbox fixture is **13-15**. Apple returned **18+**.

**This is in tension with §7.2**, where the **Under-13** fixture *did* govern,
returning an under-13 range despite the same cached adult record — so the fixture
demonstrably overrode the cache **then**.

**One difference worth naming, as a hypothesis and nothing more:** the under-13
observations came through **`ProfileView`'s Continue — an explicit, interactive
user action**. This one came through the **recovery coordinator at launch — a
non-interactive request, with no sheet presented**. It is *possible* that
interactive requests re-evaluate while non-interactive ones are served from the
cached share (**"Last shared: 18 or older on 7 September 2026"**, still the
account-level record). **That is untested speculation and must not be recorded as
a finding.**

## 17.4 THE REMAINING FA PREDICTIONS ALL PASS

| | prediction | observed | |
|---|---|---|---|
| FA-7 | both `*_changed_at` NULL | **NULL / NULL** | **PASS** |
| FA-8 | directory 1, `dir_ins` 2795 | **1 / 2795** | **PASS** — no publication, as Solo requires |
| FA-9 | membership 0, binding 0 | **0 / 0** | **PASS** |
| FA-10 | tokens 1 → 2 exactly, no sub-second gaps | **2**, single gap **7875.66 s** | **PASS** |
| FA-11 | Samuel untouched | **248 tokens**, name unchanged, shadow **34**, users **2** | **PASS** |

**FA-10 is a clean confirmation of the expiry gate in both directions once more:**
a 124-minute-old token rotated **exactly once**, 1.6 s before the write.

## 17.5 THE COST: THE `identityWithoutBand` FIXTURE IS NOW SPENT

**A band now exists for `c584db5b…`, so recovery will short-circuit forever on
this identity.** `upsertBand` is insert-if-absent, and no client path rewrites an
established band — by design.

**Finding-A's recovery half is verified and needs this fixture no longer.** But
the **teen** discriminators — 13–17 Share default OFF, discovery default OFF,
explicit opt-in and persistence — now require **another fresh identity**, i.e.
**another deletion**, and their blocker is no longer wiring but **getting Apple to
return a teen range at all**.

**Nothing further has been done.** No foreground transition was performed after
the measurement; with a band present it would now only exercise the
short-circuit. Device untouched otherwise: Age Assurance still 13-15, Études
still `Shared`, no purchase, no deletion.

---

# 18. CORRECTED SCORING — the fixture was NOT set. 2026-09-08

**The account holder checked Device A directly: there is currently NO Age
Assurance developer fixture selected at all.** FA-3's precondition was therefore
absent, and `band_18_plus` is exactly what the device's ordinary state should
produce — the account-level record still reads *"Last shared: 18 or older on
7 September 2026"*.

## 18.1 THE INTERACTIVE/NON-INTERACTIVE HYPOTHESIS IS WITHDRAWN

**I invented a mechanism to explain a symptom without first checking the
premise.** The premise — that 13-15 was active — was false, and once it is
corrected the observation needs no special mechanism at all.

**This is C-47's recorded lesson, repeated:** *"Check the premise before
explaining the symptom. An attachment title appeared to vanish and produced a
confident, fully-reasoned, wrong mechanism — including an exhaustive proof that
nothing had deleted it, which was true and beside the point."* **Withdrawn, and
not to be researched or designed around on the basis of this run.**

## 18.2 RE-SCORED

| | scoring |
|---|---|
| **Finding-A View-context wiring** | **HARDWARE-VERIFIED.** Same genuine `identityWithoutBand`, same server state: writer **flat at 2** before the fix, **2 → 3** after. **Unaffected by the fixture question** — the discriminator was *whether a band was written at all*, which does not depend on which band Apple returned. Had the fixture been unset at `d03324f` too, a working wiring would still have produced `band_18_plus`; it produced nothing |
| **`band_18_plus`** | **CONSISTENT with the actual device configuration.** Not an anomaly |
| **FA-3 … FA-6** | **PRECONDITION ABSENT — NOT FAILED PREDICTIONS AGAINST THE PRODUCT.** The intended 13-15 fixture was never active, so the protective inversion was never presented to the code. Recorded as **untested** |
| **FA-1, FA-2, FA-7 … FA-11** | **PASS**, unchanged |
| **Teen defaults** | **UNTESTED** |

**FA-7's pass survives and is worth keeping:** both `*_changed_at` are NULL, so
the adult defaults were written **as defaults, not as choices** — correct
regardless of band.

## 18.3 WHAT CAN AND CANNOT BE SAID ABOUT THE FIXTURE UNSETTING

**Apple documents nothing about persistence.** The Sandbox testing page covers
the procedure and the six test cases, and says **nothing** about whether a
selection survives an app reinstall, a device restart, a Sandbox Apple Account
sign-out, or an Xcode build. There is no documented prerequisite tying the
selection to the account being signed in beyond the setup steps.

**It has now been observed unset at least twice.** The 2026-09-07 handover
recorded *"its Age Assurance fixture is currently UNSET and must be re-set before
any teen/under-13 work"* — so this is a **recurrence, not a one-off.**

**Temporal correlation, offered as such and NOT as a mechanism:** the selection
was confirmed as `13 - 15` at roughly 10:30, and the only intervening device
events before it was found unset at ~12:35 were **the Xcode install of the fixed
build and the app launch**. **The install is the prime suspect on timing alone. I
cannot show a mechanism, and I am not going to assert one** — that is the mistake
§18.1 just withdrew.

**The selection lives under `Sandbox Apple Account → Manage`**, so it is
plausibly bound to that account's session state. **Whether the Sandbox Apple
Account is still signed in is the first thing to look at**, and it is an
observation, not a mutation.

## 18.4 THE CHEAPEST RELIABLE PLAN FOR THE TEEN RUN

**Two realisations make this much cheaper than the last attempt.**

**(1) The teen tests do not need the recovery coordinator.** Finding-A is
verified and needs no re-run. The teen discriminators are about the **defaults
the server writer applies for a teen band**, and `account_privacy_upsert_v1` is
the single writer **whatever route reaches it**.

**(2) `ProfileView`'s Continue is the route with demonstrated fixture-honouring
behaviour** — the Under-13 refusal fired through it **twice**, interactively and
visibly. For a band-less identity it calls `requestAgeRange`, then
`ensureAgeBandEstablished`, which writes the band. **So Continue can establish
the teen band directly**, and we would then back out of the membership screen
without purchasing.

**The verification discipline that was missing last time: check the fixture at
every step, because it has now vanished at least twice.**

| step | action | why |
|---|---|---|
| **0** | **Observation only** — is the Sandbox Apple Account still signed in, and does Age Assurance show unset? | the selection lives under that account |
| **1** | Set the fixture to **`Under 13`**, then Explore Connected → **Continue** | **the free pre-flight.** The refusal alert proves the selection is being **honoured right now**. It writes nothing — proven twice — and `.ineligible` refuses before any server contact |
| **2** | Set the fixture to **`13 - 15`** and **re-open Settings to confirm it reads back** | a selection that does not read back is not set |
| **3** | **Install nothing.** No Xcode build between here and the end | the install is the prime suspect |
| **4** | Delete the identity, **re-confirm the fixture**, sign in (returning path), **re-confirm the fixture** | catches a mid-sequence reset before it costs the run |
| **5** | Establish the band via **Continue** (proven route), then back out **without purchasing** | avoids depending on the coordinator, and on the unanswered non-interactive question |
| **6** | Measure the teen row, then Share-default OFF locally | the actual discriminators |

**Step 1 is the whole improvement.** Last time the fixture was trusted on a
single reading taken two hours and one app install earlier. **A pre-flight that
costs nothing and writes nothing removes the failure mode that spent the last
fixture.**

**Nothing has been mutated. No deletion is proposed here** — this is the
investigation that was asked for, and the plan waits on the account holder.
