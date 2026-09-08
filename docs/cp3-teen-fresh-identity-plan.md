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
