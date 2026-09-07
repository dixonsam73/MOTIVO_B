# PHASE 5 — SCOPE AND UNIT ORDER. 2026-09-06

**Phase 5 now carries two bodies of work:** the **children's privacy
workstream (CP-0…CP-5)**, moved here from its own pre-release track, and the
**existing Phase 5 client backlog** — 19 register rows plus the playback-speed
product work. **Nothing below is implemented.**

**The detailed CP design and measurements live in
`docs/childrens-privacy-workstream-scope.md`.** This document is the unit order.

---

## 1. STATUS BOUNDARIES — KEPT EXPLICIT

- **REPOSITORY STATE, established 2026-09-06 from FETCHED REMOTE AUTHORITY.**
  After `git fetch origin`, `origin/feature/solo-connected` was **`5cfcd58`**,
  equal to `HEAD`, **0 ahead / 0 behind** — measured *before* P5-A's first
  commit. **Nothing was outstanding to push.** A handover into this date
  asserted "7 commits are UNPUSHED"; every one of them (`8df9cc9` through
  `5cfcd58`) was already an ancestor of the remote branch, as were the four
  named in `supabase/sql/README-u7e-preflight.md` §14, now corrected in place.
  **A local `origin/...` ref is a cache, not authority** — it equals `HEAD` both
  when a push landed and when nobody has fetched since — so re-establish it with
  a fetch rather than reading the stale ref or trusting a handover.

- **Phase 4 is IMPLEMENTATION-COMPLETE and EXIT-INCOMPLETE.** Conditions **2**,
  **6** (ASC privacy-label half) and **8** are outstanding, plus the carried
  **C-34 avatar-replacement device verification**. Nothing in Phase 5 changes
  that. See `docs/phase-4-exit-assessment.md`.
- **The privacy policy and the ASC labels remain UNPUBLISHED.** The policy is a
  draft carrying an open `[AGE]`; the nine ASC data types are entered and saved
  but not published.
- **Children's-privacy architecture is Phase 5 PRE-RELEASE work**, not Phase 4.
- **CP-0 is a PRODUCTION MUTATION.** It must receive a **fresh prediction and a
  fresh census immediately before execution** — the census recorded in
  `d5d6d27` is dated and **must not be reused as authority**.
- **THE RETAINED-PAIR GUARD.** `samueldixon` (`1fbf664a`) and `steveckeabuo`
  (`64ffb132`), and their mutual approved follow, **must not be touched by CP-0
  until Phase 4's outstanding physical-device verification has been explicitly
  dispositioned.** They are the only fixture that can exercise conditions 2 and
  8 and C-34's avatar test, which need **two** Connected identities with an
  approved follow.

---

## 2. UNIT ORDER

**Legend — 🔴 production mutation · 👤 human/legal action · 🚪 release gate**

| # | unit | what | depends on |
|---|---|---|---|
| ~~**P5-A**~~ | **C-14** | **COMPLETE 2026-09-06 — 8 lines in `FollowStore` only.** The premise was wrong: **all 38 `AuthManager` sites are `#if DEBUG`, so it contributed ZERO shipping sites**, and the handles half had **no shipping instance at all**. Six assertions scored against a prediction committed before mutation; discriminator proven non-vacuous against pre-fix code; verified in the built Release binary as well as the tree. **Not device-verified.** Filed **C-62** on the way past | **none** — was small, and should not ship alongside a published privacy policy. **NOT a CP dependency** |
| **P5-B** | **CP-1 — design** | **DESIGNED, HELD FOR REVIEW 2026-09-06 — REVISION 2.** **The product-owned self-declaration assumption is SUPERSEDED** by Apple's first-party **`DeclaredAgeRange`** framework (iOS 26+): `requestAgeRange(ageGates: 13, 18)`, which can be guardian-declared or ID/payment-`confirmed` and which **handles ageing itself**. `docs/phase-5-b-cp1-design-r2.md` is authoritative **at revision 3**; `-design.md` (r1) is retained and banner-marked for the parts that survive. **r3 tightenings:** declined sharing is an **eligibility fact only** (retry/wording/jurisdiction → P5-G); the protective downgrade is **generalised** to discovery, **follow-requests** and Share posture via a read-time **child-safety override that destroys no preference history**; and **INVARIANT CP-OS-1** fixes that Connected requires iOS 26 **at all times**, not only at join, dropping non-destructively to Solo below it. **NO fallback self-declaration.** **SUPERSEDED 2026-09-07 by P5-A2:** rather than gating Connected join on iOS 26, **the whole app now requires iOS 26.2, including Solo**, so CP-OS-1 is preserved historically but no longer operative and S-B9/S-B9b are retired as impossible. `account_privacy` survives and now stores **less**: two bands, **no provenance** | **none** |
| ~~**P5-C**~~ | 🔴 **CP-0 — reset** | **EXECUTED AND VERIFIED 2026-09-06.** 15 dormant beta identities deleted by explicit id; 21 of 21 predicted figures matched, independently re-verified. `auth.users` 17→2, posts 101→7, comments 5→5, approved follows 2, storage 13→9 objects, **0 dangling references**. Samuel and Steve and their mutual approved follow intact. Storage needed a **retry**: the first pass deleted 3 of 4 while every operation reported HTTP 200 — a missing trailing newline in a staged file, recovered per procedure without touching the database transaction. `docs/phase-5-c-cp0-acceptance.md` | done |
| **P5-D** | 🔴 **CP-1 — apply** | apply the schema designed in P5-B, against the clean population | P5-C |
| **P5-E** | 🔴 **CP-2 — server** | discovery clause on **`search_account_directory`**, **and REQUIREMENT CP-2-R1 — binding**: `follow_requests_open`'s `coalesce(..., true)` must be changed so a **missing or unresolved row resolves CLOSED**, never open. Recorded in CP-2's predicted surface and acceptance criteria, not as an incidental finding | P5-D |
| **P5-F** | **CP-3 — client** | band question at sign-up; Share default derived from the **server-side** band; discoverability control; neutral just-in-time explanation; no nudging | P5-D, P5-E |
| **P5-G** | 👤🚪 **CP-4** | **DPIA** and legal confirmations | designs P5-B…P5-F settled; **runs in parallel** |
| **P5-H** | 👤🚪 **CP-5** | resolve `[AGE]` → publish `etudes.app/privacy` → **then** publish the ASC labels | P5-G |
| **P5-I** | **C-34 — TTL half** | avatar cache TTL; completes the work whose version-signal half shipped in Phase 4 | none |
| **P5-J** | **Correctness / safety** | **C-6** `fatalError` on store load · **C-16** `try!` on directory creation · **C-20** main-actor isolation · **C-21** discarded status reads | none |
| **P5-K** | **Behavioural defects** | **C-43** one unfollow destroys both directions · **C-10** `.file` uploads as octet-stream and is rejected · **C-27** location does not carry to Solo · **C-56** Core Data fetches inside `body` · **C-50** idle lock mid-recording · **C-5** duplicate Score adoption | none |
| **P5-L** | **Investigations** | **C-37**, **C-39**, **C-40**, **C-42**, **C-47**, **C-62** — all *Unverified*; each needs measurement **before** any fix. **C-62** was filed by P5-A: `PublishService:294` logs a session **title** in Release. It is **user content, not identity**, so it was deliberately NOT folded into C-14, and its **severity is unassigned** because the evidence establishes only that the value is written, never that any read path surfaces it | none |
| **P5-M** | **Product** | **playback-speed control** (AttachmentViewerView only, local and remote audio/video, discrete 50/75/100%, pitch preserved, no looping, no `PracticeTimerView` changes, no `MediaTrimView` carry-over, TestFlight soak) · **C-3** staged-video work **only if measurement justifies it** | none |
| **P5-N** | **Accessibility & polish** | **C-11** VoiceOver mislabel, and remaining polish | none |

### CP-1's AGE MECHANISM IS NOW APPLE'S, NOT ÉTUDES' — 2026-09-06

**Recorded because the superseded assumption is invisible once the design reads
naturally.** Every CP document before this date assumed Études would ask its own
age question and store a self-declared band. **Apple's `DeclaredAgeRange`
(iOS 26+) replaces that**, and the replacement is better on the axes that
matter: the declaration may be **guardian-declared** or **`confirmed`** by
credit card or government ID, and **Apple owns ageing across range boundaries**,
deliberately lagging disclosure to the anniversary of the original declaration so
a birth date is never revealed.

**Three consequences that change other units:**

- **P5-F (CP-3) no longer builds an age question or a promotion control.** It
  requests, derives and reconciles.
- **A new entitlement and Xcode capability** (`com.apple.developer.declared-age-range`)
  is a **project-file and provisioning change**, which on this project means the
  Release signing path is re-checked before anything is believed.
- **P5-G grows.** `activeParentalControls.communicationLimits`,
  `requiredRegulatoryFeatures`, PermissionKit and consent revocation are all now
  live questions. See `-design-r2.md` §11.

**One thing did NOT change, and it is the load-bearing half:** the storage
design. `account_privacy` separate and server-authoritative, absence
fail-protective with no `'unknown'` value, `lookup_enabled` a stored preference
rather than effective visibility, profile publication never mutating it, and
initial defaults separated from later choices — all survive, with **one
deliberate exception** for the protective adult→teen downgrade.

**CP-0's justification is unchanged by this and remains corrected:** it is data
minimisation and legacy-row reduction, **not** making `NOT NULL` achievable.

### The critical ordering point

**CP-1 design → CP-0 reset → CP-1 apply → CP-2 → CP-3.**

The design comes **first** because it is what establishes that a clean
population makes `age_band NOT NULL` achievable without backfill. **The reset is
justified by the design, not the reverse.** Applying the schema then happens
against the population the reset produced.

### CLARIFICATION 1 — P5-H MUST RE-DERIVE THE ASC MAPPING, NOT MERELY PUBLISH IT

**The nine categories currently entered in App Store Connect were derived
against the PHASE 4 BUILD. CP changes the shipped data flow**, so they must not
be assumed still sufficient.

**After P5-F and the P5-G legal/DPIA review, and BEFORE publishing either
`etudes.app/privacy` or the ASC labels:**

1. **Re-check the complete shipped data flow against Apple's taxonomy** — CP
   introduces a **server-side age band**, which is new collection, and changes
   privacy and discoverability defaults.
2. **Update `docs/app-store-privacy-disclosures.md`** as necessary, including
   whether the age band sits under an existing category or requires a new one.
3. **Only then publish** — policy first, ASC second.

**The final privacy policy must additionally describe:** the age-band data,
**why** it is collected, its **retention and deletion**, and the **distinct
13–17 privacy defaults**.

**Do not treat "the labels are already entered" as evidence they are still
correct.** They were correct for a build that no longer describes the product.

### CLARIFICATION 2 — P5-B MUST SETTLE CREATION SEMANTICS FOR `age_band NOT NULL`

**A `NOT NULL` column cannot be designed against a server state that must
transiently be null. P5-B must determine explicitly where the age-band question
occurs relative to creation of the Connected identity and the directory row.**

**Two measured facts the design must accommodate:**

1. **The identity and the directory row are created at DIFFERENT moments.**
   `AuthManager` publishes the directory row through
   `AccountDirectoryService.upsertSelfRow` **guarded on a non-empty display
   name** (`:596`). A sign-in with no local profile name therefore mints
   `auth.users` and **never creates a directory row** — an observed production
   state, not a hypothetical (the 2026-08-15 identity, and an earlier one).
   **So "the account exists" and "the directory row exists" are not the same
   event**, and an `age_band NOT NULL` on `account_directory` must be known
   **before** that upsert, or supplied **atomically with it**.

2. **`upsertSelfRow` is called with `lookupEnabled: true` HARD-CODED**
   (`AuthManager:618`). **Every profile publish rewrites discoverability to
   true.** Left alone, this would **silently overwrite an under-18 member's
   discoverability-off preference on the next profile publish** — the same shape
   as the `shouldPublish: true` literal U2b had to remove. **CP-3 cannot work
   until this literal is addressed**, and P5-B's design must say what replaces
   it.

**The principle to preserve:** **no unresolved-age account may accidentally
receive adult privacy defaults.** Acceptable designs are (a) the band is
established **before** first identity/directory creation, or (b) creation is
**atomic with** the band. A design that creates the row first and fills the band
later reintroduces exactly the unknown-age window the `NOT NULL` column exists
to prevent.

### What gates release

**P5-A through P5-H gate release. P5-I through P5-N do not** — they are quality
work that may proceed in parallel or slip. The one coupling is that **C-14
should not remain unfixed once a privacy policy is published**, which is why it
sits first; it is **not** a dependency of any CP unit.

---

## 3. NOTHING DROPPED

**All 19 Phase 5 register rows are placed:** C-34 (TTL half), C-37, C-39, C-40,
C-27, C-3 (fix half), C-20, C-21, C-5, C-6, C-10, C-11, C-14, C-16, C-50, C-47,
C-43, C-42, C-56.

**C-62 was added on 2026-09-06 by P5-A and is placed in P5-L**, so the count is
now **20 rows, one of them (C-14) Resolved**. It is called out here rather than
folded silently into the 19, because **a row filed by a unit is exactly the kind
of thing a later reader assumes was always there**.

**Plus two things that exist outside the register and are easy to lose:**

- **the playback-speed product work**, which appears only in CLAUDE.md's phase
  list and has no register row (**P5-M**);
- **C-41**, the vestigial `lookup_enabled` client plumbing, which is **revived by
  CP-3 rather than deleted** — the column turns out to be the discovery opt-out
  the children's work needs.

**One corroboration worth keeping:** **C-10**'s mechanism — a `.file` attachment
uploading as `application/octet-stream` and being refused by the bucket's
`allowed_mime_types` — is **exactly the failure P4-U6 hit in its own test
fixture** (`docs/phase-4-u6-acceptance.md` §4). The register row is confirmed by
an independent observation.
