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
