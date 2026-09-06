# CHILDREN'S PRIVACY WORKSTREAM (CP) — SCOPE. 2026-09-06

**A SEPARATE PRE-RELEASE WORKSTREAM. NOT PHASE 4, and not to be implemented
inside it.** Phase 4 remains implementation-complete / exit-incomplete
(`docs/phase-4-exit-assessment.md`); nothing here changes its status.

**Product direction approved in principle:** Études Connected should support
musicians aged **13–17** rather than excluding them. **Nothing is implemented.**

---

## 1. A CORRECTION RECORDED BEFORE ANYTHING ELSE

**Performance of contract is NOT the settled lawful basis for children's
Connected processing, and my earlier assessment asserted it too confidently.**
ICO guidance requires consideration of a **child's contractual capacity** where
contract is relied upon. Article 8's parental-consent rule engages only where
**consent** is the basis — that part stands — **but which basis actually applies
to under-18 Connected processing requires professional confirmation before it
appears in the privacy policy or is designed into the architecture.**

**Everything scoped below is deliberately independent of that determination.**
Each item is privacy-preserving under any lawful basis, so the work can proceed
while the legal question is settled in parallel.

---

## 2. WHAT IS ALREADY BUILT — AND A LATENT HAZARD

**Measured 2026-09-06, and it changes the size of this work.**

**`account_directory.lookup_enabled` ALREADY EXISTS.** It is populated —
**9 rows `true`, 8 rows `false`, 0 null** — and it is consulted by **NOTHING**:
no deployed function, no policy. Client plumbing is partially present and
decoded (`AccountDirectoryService`, the vestigial half filed as **C-41**).

**So the discovery opt-out is mostly built and entirely dormant.** The work is to
*use* the column, not to add one.

### THE HAZARD, STATED LOUDLY

**Eight existing members carry `lookup_enabled = false` and are nevertheless
fully discoverable today, because nothing reads the column.** Wiring it up
naively would **silently remove eight real members from search** — a behaviour
change nobody asked for, arriving as a side effect of a children's feature.

**Whatever CP does with this column must decide those eight rows explicitly, by
id, and never by predicate sweep** (B-22's rule).

**B-2's withdrawal reasoning no longer blocks this.** B-2 was withdrawn because
gating *both* directory RPCs on the column would blank names and avatars for
existing followers. **U7 proved the two RPCs are independently gateable** —
attribution has no subject-side filter (G10) and discovery does. **A
discovery-only clause on `search_account_directory` alone does not touch
attribution**, which is exactly the objection that killed B-2.

---

## 3. DESIGN ASSUMPTIONS — APPROVED, AND INDEPENDENT OF THE LEGAL QUESTION

1. Connected minimum age **13**.
2. Identify only the **minimum age band** distinguishing `13–17` from `18+`.
3. **Ask the band directly** rather than collecting a full date of birth — see §4.
4. Under-18 **Share default OFF**.
5. Under-18 **directory discoverability default OFF**, independently opt-in.
6. **Attribution for established relationships unchanged.**
7. **Approved-follow restrictions on comments and direct sends retained.**
8. **Attachment privacy unchanged** (already private by default).
9. **Neutral, age-appropriate just-in-time explanation** when a young user
   enables sharing or discoverability.
10. **No nudging** toward lower privacy.
11. **DPIA required before launch.**

---

## 4. ASKING THE BAND DIRECTLY RATHER THAN COLLECTING DOB

**Recommended, and it is a data-minimisation point (Standard 8), not a
convenience.** A full DOB is more personal data than the decision needs: the
only question the product must answer is *"is this account 13–17 or 18+?"*

**Proposed:** a single question at Connected sign-up with three outcomes —
**under 13 → refused**, **13–17**, **18+** — storing a **band**, never a date.

**Open sub-questions for design, not settled here:** whether the question is
phrased as a birth year, an "are you 18 or over?" plus an "are you at least 13?"
pair, or a single banded picker; and how re-asking is handled when a 17-year-old
turns 18. **A stored band does not age; a stored DOB does.** That is a genuine
trade-off between minimisation and accuracy and must be decided explicitly.

---

## 5. CHANGES REQUIRED

### 5a. Schema (server)

| change | notes |
|---|---|
| **`account_directory.age_band`** (or equivalent), enum-like text or smallint | Must be **server-side and authoritative** — the discovery gate is server-enforced, so a client-only value cannot carry it |
| **`lookup_enabled`** — no schema change | Already exists. Semantics and the 8 existing `false` rows must be settled (§2) |
| Grants/RLS | The member must be able to read and set their own values; `account_directory_update_owner` is already ungated |

### 5b. Server behaviour

| change | notes |
|---|---|
| **`search_account_directory`** gains a discovery clause | **This RPC only.** `get_account_directory_by_user_ids` must NOT gain one — **G10**, and it would break U7/C-58 attribution |
| Nothing else | No policy changes, no membership changes, no enforcement changes |

### 5c. Client

| change | notes |
|---|---|
| Age-band question at Connected sign-up | Blocks Connected below 13 |
| **Share default derives from the band** | `AddEditSessionView:1829` currently `isPublic = isThoughtMode ? false : !fetchDefaultPostingIsPrivate()` |
| **`defaultPrivacy` is LOCAL Core Data**, default `NO` | So today's share default is **per-device and resets on reinstall**. An under-18 default must derive from the **server-side band**, not from a local flag, or it will not follow the user |
| Discoverability control in Profile | Revives C-41's vestigial plumbing rather than deleting it |
| Just-in-time explanation + no-nudge presentation | Standards 4 and 13 |

---

## 6. MIGRATION AND DEFAULT SEMANTICS — THE HARD PART

**Every existing account has no age band.** Three options, and the choice is a
product decision:

| option | effect | cost |
|---|---|---|
| **(a) Prompt everyone at next launch; Connected gated until answered** | No unknown-band accounts ever exist | one-time friction for all members |
| (b) Unknown → treat as 18+, prompt later | preserves current behaviour | **leaves a window in which an existing under-18 has Share ON** |
| (c) Unknown → treat as under-18 until answered | safest for children | **flips existing adults to Share OFF and undiscoverable** — a regression |

**Recommendation: (a).** Production holds **17 pre-release beta identities and no
public customers**, so the friction is nearly free *now* and becomes expensive
the moment the app is released. **This is the strongest argument for doing CP
before public release rather than after.**

**Separately and explicitly: the 8 `lookup_enabled = false` rows** must be
dispositioned by id — either reset to `true` (restoring today's observable
behaviour before the column becomes live) or confirmed as intended. **Not a
predicate sweep.**

---

## 7. TESTS AND RELEASE GATES

**Tests** — mirroring the Phase 4 pattern, each with a discriminator:

1. **Server**: an under-18 account with discoverability off is absent from
   `search_account_directory`, **while `get_account_directory_by_user_ids` still
   resolves it for an approved follower** — the U7 invariant, re-asserted.
2. **Server**: an 18+ account is unaffected.
3. **Client**: an under-18 account initialises Share **OFF**; an 18+ account is
   unchanged (the D-1 default survives).
4. **Client**: a Thought still initialises OFF for both bands, and remains
   shareable (`U8-F1`/`F2`/`F3` must keep passing).
5. **Structural**: `get_account_directory_by_user_ids` still carries **no**
   subject-side predicate (U6b-J3 / G10).
6. **Migration**: an account with no band cannot reach Connected under option (a).

**Release gates:**

- **DPIA completed and recorded** — an ICO requirement, not a recommendation.
- Legal confirmations in §8 obtained.
- App Store age rating consistent with 13+.
- Standing Phase 4 suites still green (u2*, u5-client, u6b, u7, u8).
- Privacy policy `[AGE]` resolved, and the policy published **before** the ASC
  labels are published.

---

## 8. REQUIRES EXTERNAL LEGAL CONFIRMATION

**Four. None is determinable from the code, and none should be inferred.**

1. **The lawful basis** for children's Connected processing — and, if contract,
   **the contractual-capacity implications** for 13–17s.
2. **Whether self-declaration is adequate** for Études' assessed risk. ICO says
   it *"may be suitable for low risk processing"*; whether Études *is* low risk
   is a judgement to be signed off, informed by the DPIA.
3. **DPIA review.**
4. **Final privacy-policy wording**, including the age statement.

---

## 9. DEPENDENCIES AND SEQUENCING

- **Blocks public release.** It does not block Phase 4's remaining exit
  conditions, which are unrelated.
- **Should precede public release**, per §6 — the migration is cheap now.
- **Depends on U7** having separated attribution from discovery. Before U7 this
  design was not cleanly available.
- **The privacy policy stays a DRAFT** and `etudes.app/privacy` is not published.
  **The ASC labels stay entered-but-unpublished.**
