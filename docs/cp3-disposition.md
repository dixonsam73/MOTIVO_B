# CP-3 — DISCOVERY-WRITER ACCEPTANCE AND PROPOSED DISPOSITION. 2026-09-08

Repo `5839ab0`. **Nothing executed. This is a scope and a proposal.**

---

# 1. THE TEEN HARDWARE GAP — RECORDED AS AN APPLE SANDBOX TEST LIMITATION

**It is not a product failure, and the record must not read as one.**

- **No end-to-end device observation of a real Apple 13-17 range establishing
  `band_13_17`.** Three disposable identities were spent; **the teen band was
  never produced once**, in any attempt, by either call site.
- **Therefore no literal on-device observation** of the teen default row, or of
  the teen discovery opt-in chain.
- **Teen derivation and default behaviour remain covered** by the client unit
  suite and by the deployed server expression — **whose adult half is
  hardware-verified three times**, and which has **no teen branch** to diverge.

**Cause, established in §24:** Apple documents **no** reset, re-arm or
force-re-evaluation procedure for the Age Assurance fixture, **no** way to prove
its returned value, and **no** propagation statement. Independent developer
reports describe the same nondeterminism, **including for `child 13-15`
specifically**, with an Apple engineer unable to reproduce and no resolution.
**Seeing a fixture selected is not evidence it will be returned.**

**Closed to further experimentation by instruction.**

---

# 2. SCOPE — THE ONE REMAINING DETERMINISTIC DEVICE GAP

`account_privacy_set_lookup_v1` has **never been called**
(`pg_stat_statements` = **null**). Zero coverage, unit or device. **It is the
only client writer of the discovery preference** (`ProfileView:742`, one call
site).

## 2.1 Current state — 2026-09-08 17:04:31

| | |
|---|---|
| identity | `6fd0a833-9e12-4dbb-a8e4-b4b01f706ea2` |
| `age_band` | **`band_18_plus`** |
| `lookup_enabled` / `lookup_changed_at` / `lookup_set_under_band` | **true / NULL / `band_18_plus`** |
| `follow_requests_enabled` / `follow_requests_changed_at` | **true / NULL** |
| `membership` / `membership_binding` | **0 / 1** |
| `account_directory` / `dir_ins` | **1 / 2795** |
| **`set_lookup_v1`** | **never called** |
| writer / `privacy_read` | **5 / 63** |
| tokens / sessions | **249 / 20** |

## 2.2 A PRECONDITION RISK, AND A HYGIENE FIX FOR IT

**The control is Connected-only** — `canShowConnectedAccountManagement` is
`mode == .connected`, and `resolve()` requires **both** `isEntitled` and
`hasConnectedIdentity` (`AppModeManager:109`, `:124-129`). **So a Sandbox
purchase is required.**

**The only route to Membership Selection is `Continue`**, which calls
`requestDeclaredAgeRange()` first — and **the fixture currently displays
`Under 13`**, whose returned value is nondeterministic. If it happens to be
honoured, Continue refuses and the run is blocked.

> **Set the fixture to `18+, age confirmed, significant change not applicable`
> first.** This aligns it with the established band, removes a nondeterministic
> blocker, and is **hygiene, not teen-fixture work**.

## 2.3 ONE REQUESTED ASSERTION IS STRUCTURALLY GUARANTEED — say so rather than stage it

*"Ordinary profile republish does not overwrite the explicit preference."*

**A republish cannot touch `account_privacy` at all.** `upsertSelfRowOnce` writes
to **`account_directory`** and **deliberately omits both privacy columns** —
CP-3's own change, commented *"the two privacy columns are NOT sent … Omitting
them is what makes 'profile publishing does not mutate a privacy preference'
structural rather than remembered."* **Different table, columns absent.**

**And it could not be attempted anyway:** the directory INSERT is
`enforcement_gate`d, false for a Sandbox membership.

**So the device-testable form is HYDRATION, not republish:** after the toggle,
foreground the app and confirm hydration **re-reads** without changing the row
and the control still renders the explicit value.

## 2.4 PREDICTIONS

| | prediction | falsifier |
|---|---|---|
| **D-1** | **`set_lookup_v1` null → 1** — the writer provably called | still null |
| **D-2** | `lookup_enabled` **true → false** | unchanged |
| **D-3** | `lookup_changed_at` **NULL → non-NULL** | still NULL — a choice not recorded as one |
| **D-4** | `lookup_set_under_band` stays **`band_18_plus`**, copied from `ap.age_band` | any other value |
| **D-5** | **`follow_requests_enabled` stays true and `follow_requests_changed_at` stays NULL** — this writer must not touch the other preference | either moves |
| **D-6** | `age_band` and `band_updated_at` **unchanged** | any change |
| **D-7** | **persistence:** after one foreground, `lookup_enabled` still false, `lookup_changed_at` unchanged, control still renders OFF | reverts |
| **D-8** | `account_directory` **1**, `dir_ins` **2795** — no publication (enforcement-gated) | a second row |
| **D-9** | after purchase: `membership` **1** (Sandbox, `binding_method` `purchase`); `membership_binding` still **1**, `created_at == updated_at` | a re-bind |
| **D-10** | tokens bounded, **no sub-second gaps** | a storm |
| **D-11** | Samuel **248 / 19**, directory row unchanged, `auth.users` **2** | any movement |

**D-1 is the entire point** — a counter moving off `null` for the first time.
**D-5 is the sharpest correctness check:** the writer's `SET` list names only the
three lookup columns, so a follow-requests change would mean the deployed
function is not what was read.

## 2.5 SEQUENCE

1. Set Age Assurance to **`18+, age confirmed, significant change not applicable`** (§2.2).
2. Profile → **Explore Connected → Continue → Membership Selection → purchase Monthly.**
3. Wait for **Connected**; confirm the two privacy controls are visible and
   **`Let other members find you` renders ON**. Tell me — I measure the
   pre-toggle state.
4. **Toggle it OFF.** Stop. I measure D-1…D-6, D-8…D-11.
5. **One background → foreground.** I measure D-7.

**No deletion. No teen-fixture work. No enforcement change.**

---

# 3. PROPOSED CP-3 DISPOSITION

## 3.1 Hardware-verified

- **Band establishment** — three times, by **both** routes (the recovery
  coordinator post-fix, and Continue/join).
- **Adult default row** — three times, identical: `true / true /
  band_18_plus / band_18_plus / NULL / NULL`.
- **Finding-A recovery wiring** — the View-scope fix, on the *same* identity and
  server state that failed: **writer flat before, +1 after**.
- **Finding-A short-circuit** — band present ⇒ read, no Apple call, no write;
  observed many times.
- **Under-13 refusal** — twice, and proven to occur **before any server contact**
  (`privacy_read` and tokens both flat).
- **`identityWithoutBand` created, not reconstructed** — twice, by midpoint
  measurement.
- **Deletion lifecycle** — `account_privacy` and `membership_binding` cascade;
  blast radius predicted and matched **three times**, including a count that
  moved once and correctly did not the next time.
- **Gate (C)** and the session-management fix — verified earlier.

## 3.2 Covered structurally / unit / server-side

- **Derivation** — 16 unit tests over Apple's six documented fixtures, boundaries
  and the regulatory over-block.
- **Share default** — pure and explicit: teen and every unknown → **OFF**.
- **Server defaults** — **one deployed expression, no teen branch**; the teen half
  evaluated live (`false / false`), the adult half hardware-verified 3×.
- **Effective / child-safety override** — deployed and readable.
- **Age-range wiring** — 35 structural assertions, non-vacuity measured.

## 3.3 Blocked, and by what

| blocked | by |
|---|---|
| teen range → `band_13_17` end to end; teen default row on device; teen opt-in chain | **Apple's Sandbox fixture machinery** — no deterministic reset, nondeterministic honouring, corroborated by third-party reports |
| directory publication; **strong band-before-directory ordering** | **U6b enforcement + D4** — `connected_member()` is Production-only, so a Sandbox membership can never publish. Not to be weakened |

## 3.4 CAN CP-3 CLOSE?

**My assessment: yes — with these limitations explicitly recorded, and provided
§2's discovery-writer acceptance passes**, since that is the one gap that is both
deterministic and currently uncovered.

**The reasoning, and its precedent:** the teen residue is a **test-environment**
limitation with strong compensating coverage — a server writer with **no teen
branch**, whose adult half is hardware-verified three times, and a unit suite over
Apple's own fixtures. **This project has closed a phase carrying named, owned
obligations before** — Phase 3 closed carrying four, on the stated rule that
forcing an obligation to fit a phase boundary is the opposite of the discipline
that says no obligation may be ownerless.

**What must NOT be claimed at closure:** that teen defaults are device-verified.
They are not, and §1 is the wording to carry.

**The decision is the account holder's.** This is a proposal.

---

# 4. DISCOVERY-WRITER ACCEPTANCE — PASSED. 2026-09-08 17:15–17:16

## 4.1 Pre-toggle: hydration/UI correctness with NO write

Server held `lookup_enabled = true`; the control rendered **ON**; and
**`account_privacy_set_lookup_v1` was still never-called.** Read-path
correctness established **before** anything mutated — the redundant ON write
avoided, per the account holder's sequencing.

Purchase integrity at that moment: `membership` **1** (Sandbox,
`binding_method` **`purchase`** — bound at source, no legacy claim);
**`membership_binding` reused, not re-bound** (`created_at == updated_at` =
16:57:34.469118); `upsert_v1` **unchanged at 5** — the purchase wrote no band.

## 4.2 The single ON → OFF transition — all eleven pass

| | prediction | observed | |
|---|---|---|---|
| **D-1** | `set_lookup_v1` **never-called → exactly 1** | **1** | **PASS** |
| D-2 | `lookup_enabled` true → false | **false** | PASS |
| D-3 | `lookup_changed_at` NULL → non-NULL | **17:15:05.447486** | PASS |
| D-4 | `lookup_set_under_band` stays `band_18_plus` | **`band_18_plus`** | PASS |
| **D-5** | follow-requests trio **byte-identical** | **true / NULL / `band_18_plus`** | **PASS** |
| D-6 | `age_band`, `band_updated_at` unchanged | **`band_18_plus` / 16:54:51.48418** | PASS |
| D-7 | `upsert_v1` stays 5 | **5** | PASS |
| D-8 | no directory publication | **1 / 2795** | PASS |
| D-9 | binding not re-bound | **unchanged** | PASS |
| D-10 | tokens/sessions bounded | **249 / 20**, no rotation | PASS |
| D-11 | Samuel untouched | **248 / 19**, `Samuel Dixon` | PASS |

**D-1 is the headline: a counter that had never moved in this project's history
went from `null` to exactly 1.** One call, no retry.

**D-5 is the sharpest correctness result.** The deployed writer's `SET` list
names only the three lookup columns, and the follow-requests trio came back
byte-identical; `set_follow_requests_v1` also remains **never called**.

**D-7 and D-4 together:** a preference change did not touch the band writer, and
`lookup_set_under_band` was **copied** from `ap.age_band` rather than recomputed
— exactly as the deployed SQL reads.

## 4.3 Persistence — the explicit choice is read back, not re-asserted

After one background→foreground: `lookup_enabled` still **false**,
`lookup_changed_at` **unmoved** at 17:15:05.447486, and **`set_lookup_v1` still
1 — no second write.** Directory, binding, band, tokens and Samuel all unchanged.

**No second write is the load-bearing part.** A client that re-asserted what it
had just read would be the exact shape of the hard-coded `lookupEnabled: true`
literal CP-3 removed. It did not recur.

## 4.4 What this run does NOT establish

**It is an ADULT-band exercise.** `lookup_set_under_band` was verified to copy
`ap.age_band`, but the value copied was `band_18_plus`. **The teen literal
`band_13_17` is copied, not computed** — so the mechanism is verified and the
teen value is not device-observed.

---

# 5. A FURTHER SANDBOX OBSERVATION, AND IT IS THE CLEANEST ONE

**2026-09-08 ~17:08–17:12.** The fixture was set to `18+, age confirmed`,
**verified by leaving and re-entering the screen**, measured server-side at
17:10 — and found **unset** at ~17:12.

**No deletion. No install. No sign-in. No app interaction. Only time and a
screen re-entry.**

**This is cleaner than the three earlier clearings**, which each had a lifecycle
event to argue about. It has none. And it **retroactively explains the teen
failures without any of the hypotheses raised and withdrawn during this work**:
the 13-15 selections that "read back" had most likely unset again before
`requestAgeRange` was called, and both call sites returning adult is simply
consistent with **no fixture being set at request time**.

**Signing out of the Sandbox account was considered and rejected:** it risks the
`+devicec` tester carrying the subscription history and `originalTransactionId`
— a different tester yields a different otid and a second `membership` row —
for a fixture this run did not need.

---

# 6. FINAL CP-3 DISPOSITION

## 6.1 Hardware-verified

- **Band establishment**, three times, by **both** routes — the recovery
  coordinator (post-fix) and Continue/join.
- **The adult default row**, three times, identical:
  `true / true / band_18_plus / band_18_plus / NULL / NULL`.
- **Finding-A recovery wiring** — the View-scope fix, on the *same* identity and
  server state that had failed: **writer flat before, +1 after**.
- **Finding-A short-circuit** — band present ⇒ read, no Apple call, no write.
- **Under-13 refusal**, twice, proven to occur **before any server contact**.
- **`identityWithoutBand` created, not reconstructed** — twice, by midpoint.
- **The discovery writer, end to end** — never-called → 1, correct row delta,
  neighbouring preference untouched, and the choice **persisting across
  hydration without a second write**.
- **Hydration/UI read-path correctness** — the control rendered the server's
  value with the writer provably uncalled.
- **The deletion lifecycle** — `account_privacy` and `membership_binding`
  cascade; blast radius predicted and matched **three times**, including a count
  that moved once and correctly did not the next time.
- **Purchase integrity** — `binding_method` `purchase`, binding reused not
  re-bound.
- **Gate (C)** and the session-management fix.

## 6.2 Covered structurally / unit / server-side

- **Derivation** — 16 unit tests over Apple's six documented fixtures,
  boundaries, and the regulatory over-block.
- **Share default** — pure and explicit: teen and every unknown → **OFF**.
- **Server defaults** — **one deployed expression with NO teen branch**; the teen
  half evaluated live (`false / false`), the adult half hardware-verified 3×.
- **Child-safety effective override** — deployed and readable.
- **Age-range wiring** — 35 structural assertions, non-vacuity measured.
- **Session-refresh policy** — 87 unit tests, 34 structural.

## 6.3 Blocked, and by what

| blocked | by | proposed status |
|---|---|---|
| teen range → `band_13_17` end to end; the teen default row on device; the teen opt-in chain | **Apple's Sandbox fixture machinery** — no documented reset, nondeterministic honouring, corroborated by third-party reports **and by §5's clean observation** | **recorded limitation** |
| directory publication; **strong band-before-directory ordering** | **U6b enforcement + D4** — `connected_member()` is Production-only, so a Sandbox membership can never publish | **named blocked obligation** |

## 6.4 WHAT MUST NOT BE CLAIMED

> **Teen defaults are NOT device-verified.** No end-to-end observation of a real
> Apple 13-17 range establishing `band_13_17` exists, and therefore none of the
> teen default row or the teen discovery opt-in chain.
>
> **The teen behaviour is covered by the client unit suite and by a deployed
> server expression that has no teen branch and whose adult half is
> hardware-verified three times. That is coverage, not device verification, and
> the distinction must survive into the record.**

## 6.5 RECOMMENDATION

**CP-3 can reasonably close** with §6.3's two limitations recorded and §6.4's
wording carried verbatim.

The one gap that was **deterministic and uncovered** — the discovery writer — is
now closed on hardware. What remains is a **test-environment** limitation with
strong compensating coverage, and an **enforcement** boundary that is deliberate
and must not be weakened.

**Precedent:** this project has closed a phase carrying named, owned obligations
before — Phase 3 closed carrying four, on its own rule that forcing an obligation
to fit a phase boundary is the opposite of the discipline that says no obligation
may be ownerless.

**The decision is the account holder's.**
