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

### THE 9/8 SPLIT IS AN ARTEFACT, NOT A PREFERENCE — MEASURED 2026-09-06

**No user has ever chosen a `lookup_enabled` value, because no control exists to
choose one** (C-41: the client plumbing is vestigial and read-only).

The split tracks **account age**, not intent: every identity whose last session
is 2026-07-01 or later is `true`; every identity before 2026-06-16 is `false`
(one boundary case, `felixbloxsom`). That is the signature of a **changed column
default**, not of seventeen privacy decisions.

**So preserving these values carries no privacy meaning at all**, and the
"eight members would silently vanish from search" hazard **disappears entirely
under the reset in §2b** — only two rows survive, both `true`, both the
developer's own.

**B-2's withdrawal reasoning no longer blocks this.** B-2 was withdrawn because
gating *both* directory RPCs on the column would blank names and avatars for
existing followers. **U7 proved the two RPCs are independently gateable** —
attribution has no subject-side filter (G10) and discovery does. **A
discovery-only clause on `search_account_directory` alone does not touch
attribution**, which is exactly the objection that killed B-2.

---

## 2b. CONTROLLED PRE-RELEASE RESET — MEASURED, NOT YET PERFORMED

**The production population is entirely pre-release beta/test data with no
continuity expectation.** Dormancy is measured on `max(auth.sessions.updated_at)`
per user — **B-35's rule, never `last_sign_in_at`** — and only two identities
have been active since 2026-08-30. The rest range from 2026-03-26 to 2026-08-12.

### RETAIN — TWO IDENTITIES, AND THE SECOND IS NOT OPTIONAL

| keep | md5[0:8] | why |
|---|---|---|
| `samueldixon` | `1fbf664a` | the active development identity; **holds the only retained avatar**, which C-34's replacement test needs |
| `steveckeabuo` | `64ffb132` | **Device A's own beta-burner identity — not a third-party tester** |

**RETAINING THE SECOND IDENTITY IS A DEPENDENCY, NOT SENTIMENT.** Phase 4's
outstanding exit conditions **2** and **8**, and **C-34's avatar verification**,
each require **two Connected identities with an approved follow between them** —
one member sharing or changing an avatar, another observing it. **A single
identity cannot exercise any of them.** This pair is exactly what made the
2026-09-05 U7 device verification possible, and their **mutual approved follow**
must be retained with them.

**Deleting it would destroy the fixture Phase 4 still needs and force it to be
rebuilt by hand.**

### THE MEASURED BLAST RADIUS

| | retain | delete |
|---|---|---|
| identities | **2** | **15** |
| posts | 7 | **94** |
| comments | **5 — all of them** | **0** |
| follows | 2 (the mutual pair) | 7 |
| avatars | 1 | 2 |

**All five comments sit wholly inside the keep set**, so **B-19's
retained-comment question never arises** — there is no comment authored by a
deleted identity on a surviving post, and none addressed to one. That is the
single largest source of deletion complexity, and it is absent.

`connected_attachments` holds 25 rows, all soft-deleted (the 2026-09-04
cleanup); attachment objects total 10.

**Nothing has been deleted.** When it is, it must be **by explicit id, with a
prediction committed first** — B-22's rule and this project's standing practice.

---

## 2c. WHAT THE RESET SIMPLIFIES

**Materially, and in the schema rather than merely in the data:**

1. **`age_band` can be `NOT NULL` from the start.** With two surviving rows, both
   under the developer's control, there is **no backfill, no nullable column, and
   no unknown-band population**. Without the reset the column must be nullable
   and every read site must implement fail-private.
2. **"Unknown fails private" stops being a migration surface** and becomes what
   it should be — a **runtime rule for the sign-up window only**, before the
   directory row exists.
3. **`lookup_enabled` needs no data decision.** No 8-row disposition, no
   by-id sweep, no risk of silently unlisting a real member.
4. **Migration option (a) — "prompt everyone at next launch" — collapses to
   two accounts the developer already controls**, so no prompting machinery,
   no gating-until-answered logic, and no partially-migrated state.

**This is the difference between a migration and a clean start.** The strongest
argument for the reset is that it removes work, not that it tidies data.

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

## 6. DEFAULT SEMANTICS — NO LONGER A MIGRATION PROBLEM

**Superseded by §2b/§2c.** An earlier revision of this document called migration
*"the hard part"* and set out three options for handling accounts with no age
band. **Under the reset that question does not arise**: two identities survive,
both the developer's own, and both are set explicitly.

**What remains is FUTURE-PRODUCT CORRECTNESS, which is a different thing and is
not negotiable:**

| rule | where enforced |
|---|---|
| **unknown age fails private** | runtime, during the sign-up window before a band is stored — **not** a migration path |
| **13–17: Share default OFF, discovery default OFF** | client default derived from the server-side band; discovery clause server-side |
| **18+ retains the intended adult defaults** | unchanged — D-1 survives for adults |
| **under 13 cannot enable Connected** | sign-up refuses before any identity or directory row is created |
| **attribution independent of discoverability** | `get_account_directory_by_user_ids` gains **no** clause — G10, U7 |

**Keep the two apart deliberately.** Beta-data migration compatibility is
disposable; the five rules above are permanent product behaviour and must be
asserted by tests regardless of what the beta population looked like.

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

## 9. DEPENDENCY-ORDERED IMPLEMENTATION PLAN

**Six units. Nothing implemented. Each ends in a committed prediction, a
verification and a stop, as every unit in this project has.**

| # | unit | depends on | notes |
|---|---|---|---|
| **CP-0** | **Pre-release reset** — delete 15 dormant beta identities and their server-side data by **explicit id**; retain `1fbf664a` and `64ffb132` and their mutual approved follow | nothing | Prediction committed **before** any deletion. **Ordering is now free** because the Phase 4 fixture is retained — had only one identity survived, CP-0 would have had to wait for conditions 2 and 8 |
| **CP-1** | **Schema** — `age_band` `NOT NULL`; `lookup_enabled` default and semantics settled | CP-0 (that is what makes `NOT NULL` possible without backfill) | No data decisions left after CP-0 |
| **CP-2** | **Server** — discovery clause on `search_account_directory` **only** | CP-1 | **Must not touch `get_account_directory_by_user_ids`** — G10 / U7. Its acceptance suite re-asserts the U7 invariant |
| **CP-3** | **Client** — band question at sign-up; Share default derived from the band; discoverability control (revives C-41); neutral just-in-time explanation; no nudging | CP-1, CP-2 | `defaultPrivacy` is **local Core Data**, so the under-18 default must derive from the **server-side** band or it will not follow the user across devices |
| **CP-4** | **DPIA and legal confirmations** | CP-1..CP-3 designs settled enough to assess | Runs **in parallel**; **blocks release, not implementation** |
| **CP-5** | **Publish** — resolve `[AGE]`, publish `etudes.app/privacy`, then publish the ASC labels | CP-4 | **Policy first, ASC second** — the URL must resolve before the labels go live |

**Relationship to Phase 4:** CP does **not** block Phase 4's remaining exit
conditions, and Phase 4 does not block CP. **Both block public release.** CP-0
retains the fixture conditions 2, 8 and C-34 need, so neither workstream has to
wait for the other.

