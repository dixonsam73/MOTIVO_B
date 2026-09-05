# PHASE 4 — EXIT ASSESSMENT. 2026-09-05

**PHASE 4 IS IMPLEMENTATION-COMPLETE AND EXIT-INCOMPLETE. IT IS NOT CLOSED.**

All eight units are implemented and accepted. **Three exit conditions are
outstanding, plus one carried obligation that post-dates the exit list.**

**The exit conditions below are quoted from `docs/phase-4-scope.md` §6 and are
neither reinterpreted nor relaxed.** Condition 8 forbids closure in its own
words — *"DEFERRED, NOT WAIVED"*, *"must not be called formally closed"* — so
this is the criteria applying themselves, not a judgement added on top.

---

## 1. THE EIGHT CONDITIONS

| # | condition (abbreviated from §6) | status | evidence |
|---|---|---|---|
| 1 | No path uploads a post with `isPublic == false`, asserted structurally | **MET** | `u2b`/`u2c` suites; U2c makes the state unrepresentable |
| 2 | Un-sharing deletes the row and its storage objects in `.backendConnected`, **device-verified** | **NOT MET** | logic proven by `UnshareDurabilityTests` and U2a; **the device half has never run** |
| 3 | Production census shows zero private posts, pre-change number recorded | **MET** | re-measured 2026-09-05: **101 posts, 101 public, 0 private**; U1 baseline recorded the same shape |
| 4 | **Durability** — no client of any build can create a private row, demonstrated **positively** by an observed rejected write | **MET LOCALLY**; production half carried under 8 | U2s A/B/C/D/E against a **byte-identical** local policy; production verified structurally (`with_check` md5) |
| 5 | Zero unreferenced attachment objects, or each survivor dispositioned | **MET** | U4/B-8: unreferenced 4 → 0; CA residue cleared at `4ee7a0b` |
| 6 | Onboarding, settings **and App Store privacy disclosures** describe the shipped upload behaviour | **PARTIALLY MET** | in-app copy done by U8 (`u8-acceptance` 29/0); **the ASC labels have NOT been entered** |
| 7 | `LocalFactoryReset.perform` still has exactly two callers | **MET** | re-verified 2026-09-05: `ProfileView:1733`, `:1806` — exactly two |
| 8 | U2b's device verification executed; **and** U2s's production authenticated behavioural observation | **NOT MET** | both outstanding; see below |

---

## 2. WHAT IS OUTSTANDING, AND WHY IT IS ONE BLOCKER RATHER THAN THREE

**Conditions 2 and 8 share a single measured cause**, re-confirmed 2026-09-05:

- `posts` **INSERT and SELECT are both gated** by `enforcement_gate`;
- enforcement is **live** in production;
- **all 17 identities are unentitled** — grandfathering is retired and the only
  `membership` row is Sandbox, so `connected_member` is false for every one.

So nothing can be shared, confirmed, or unshared from any device, and no
production JWT can exercise the U2s guard behaviourally. **A single legitimate
Connected path on Device A would discharge conditions 2, 4's production half and
8 together.**

**The two routes to that are both currently refused, deliberately:** weakening
U6b enforcement, and manufacturing production membership. That constraint has
governed since U2b and is not relaxed here.

**Condition 6's remainder is unrelated and cheap:** entering the App Store
privacy labels is an **account-holder action in App Store Connect**, which no
part of this work can perform. Content and behaviour mapping are ready in
`docs/app-store-privacy-disclosures.md`.

---

## 3. CARRIED, AND NOT AN ORIGINAL EXIT CONDITION

**C-34's avatar replacement / cache-invalidation device verification.** It
post-dates §6, because C-34's client half was scoped into Phase 4 after the exit
list was written. **It is blocked by the same cause** — `storage.avatars` INSERT
is gated, so no avatar can be replaced.

**C-34 fixes a CACHING defect, so the only observation that settles it is a
replacement under an unchanged storage key propagating to another member.** The
2026-09-05 device pass explicitly did **not** claim it.

**What Phase 4's device pass DID establish** (`docs/phase-4-device-qa-acceptance.md`):
U7/C-58 verified on hardware, and the C-34 **client-plumbing** smoke passed.

---

## 4. THE STANDING SUITES AT EXIT

| suite | result |
|---|---|
| `u8-acceptance` | 29 / 0 |
| `u7-acceptance` | 26 / 0 |
| `u6b/acceptance` | 64 / 0 |
| `u2a / u2a2 / u2b / u2c / u2s` | 16 / 22 / 16 / 20 / 12, all 0 failed |
| `MOTIVOTests` | 49 passed |
| Debug / Release | BUILD SUCCEEDED |
| `u1-baseline` | 10 / 6 — expected inversions; **16 of 16 at its own commit `f12330e`** |
| `u5-client-acceptance` | 28 / 2 — **time-scoping, not regression**; **30 of 30 at its own commit `7744027`** |

**Two suites report failures at HEAD and neither is a regression.** Both are
unit-specific assertions pinned to their own unit's baseline, and both pass
against their own commit. **Neither was weakened to make the number look
better** — that is the suite-pinning policy working, not being worked around.

---

## 5. THOUGHTS — PRODUCT DECISION, SETTLED 2026-09-05

**A Thought is primarily a diary/journal entry, so Share INITIALISES OFF. The
owner may deliberately enable Share to publish one** — a general update, a gig
announcement, an instrument for sale, or any other non-practice post.

**Thoughts are therefore DEFAULT-private and NOT structurally private, and must
never be described as "never shared".**

**Current behaviour matches the decision; no implementation change was
required.** Verified rather than assumed, and now pinned executably:

| | evidence | assertion |
|---|---|---|
| Share initialises OFF for a Thought | `isPublic = isThoughtMode ? false : …` (`:1829`) | `U8-F1` |
| the toggle is still **offered** in Thought mode | brace analysis: `:1123` is guarded by `canShareWithFollowers`, **not** `!isThoughtMode` | `U8-F2` |
| a shared Thought really does publish | `publish(…, shouldPublish: isPublic)` carries no Thought guard | `U8-F3` |

**One comment was corrected** — comment-only, asserted by `U8-D1b`. It had said
`isPublic` is *"unconditionally false in thought mode"*, which describes the
**initialiser** as though it were the state. Read literally it invites a future
"simplification" that removes the toggle and deletes an intended capability.
**The superseded sentence is quoted in place rather than deleted**, per the house
convention — which is also why `U8-F4` asserts the correction's presence instead
of the old phrase's absence.

---

## 6. THE CONDITION FOR CLOSING PHASE 4

Phase 4 closes when **2**, **6**'s ASC half and **8** are discharged. **C-34's
device verification is carried alongside them and should be taken in the same
window**, since it is blocked by the same gate and needs the same fixture.

**Nothing here waives anything.** An obligation that is deferred is open, and
this document exists so that "Phase 4 is done" cannot be read as "nothing is
left".
