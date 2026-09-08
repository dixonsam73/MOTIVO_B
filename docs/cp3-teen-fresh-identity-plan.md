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
