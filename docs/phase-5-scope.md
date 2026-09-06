# PHASE 5 — SCOPE AND UNIT ORDER. 2026-09-06

**Phase 5 now carries two bodies of work:** the **children's privacy
workstream (CP-0…CP-5)**, moved here from its own pre-release track, and the
**existing Phase 5 client backlog** — 19 register rows plus the playback-speed
product work. **Nothing below is implemented.**

**The detailed CP design and measurements live in
`docs/childrens-privacy-workstream-scope.md`.** This document is the unit order.

---

## 1. STATUS BOUNDARIES — KEPT EXPLICIT

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
| **P5-A** | **C-14** | stop logging backend user IDs and handles via `NSLog` in release builds | **none** — small, and should not ship alongside a published privacy policy. **NOT a CP dependency** |
| **P5-B** | **CP-1 — design** | design and predict the clean schema and semantics: `age_band` **NOT NULL**, `lookup_enabled` default and meaning | **none.** Its purpose is to design the clean state that CP-0 makes possible, so it **must not depend on CP-0** |
| **P5-C** | 🔴 **CP-0 — reset** | delete **15** dormant beta identities **by explicit id**; retain the two development identities and their mutual follow | P5-B accepted; **retained-pair guard** above |
| **P5-D** | 🔴 **CP-1 — apply** | apply the schema designed in P5-B, against the clean population | P5-C |
| **P5-E** | 🔴 **CP-2 — server** | discovery clause on **`search_account_directory` only** | P5-D |
| **P5-F** | **CP-3 — client** | band question at sign-up; Share default derived from the **server-side** band; discoverability control; neutral just-in-time explanation; no nudging | P5-D, P5-E |
| **P5-G** | 👤🚪 **CP-4** | **DPIA** and legal confirmations | designs P5-B…P5-F settled; **runs in parallel** |
| **P5-H** | 👤🚪 **CP-5** | resolve `[AGE]` → publish `etudes.app/privacy` → **then** publish the ASC labels | P5-G |
| **P5-I** | **C-34 — TTL half** | avatar cache TTL; completes the work whose version-signal half shipped in Phase 4 | none |
| **P5-J** | **Correctness / safety** | **C-6** `fatalError` on store load · **C-16** `try!` on directory creation · **C-20** main-actor isolation · **C-21** discarded status reads | none |
| **P5-K** | **Behavioural defects** | **C-43** one unfollow destroys both directions · **C-10** `.file` uploads as octet-stream and is rejected · **C-27** location does not carry to Solo · **C-56** Core Data fetches inside `body` · **C-50** idle lock mid-recording · **C-5** duplicate Score adoption | none |
| **P5-L** | **Investigations** | **C-37**, **C-39**, **C-40**, **C-42**, **C-47** — all *Unverified*; each needs measurement **before** any fix | none |
| **P5-M** | **Product** | **playback-speed control** (AttachmentViewerView only, local and remote audio/video, discrete 50/75/100%, pitch preserved, no looping, no `PracticeTimerView` changes, no `MediaTrimView` carry-over, TestFlight soak) · **C-3** staged-video work **only if measurement justifies it** | none |
| **P5-N** | **Accessibility & polish** | **C-11** VoiceOver mislabel, and remaining polish | none |

### The critical ordering point

**CP-1 design → CP-0 reset → CP-1 apply → CP-2 → CP-3.**

The design comes **first** because it is what establishes that a clean
population makes `age_band NOT NULL` achievable without backfill. **The reset is
justified by the design, not the reverse.** Applying the schema then happens
against the population the reset produced.

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
