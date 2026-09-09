# PHASE 5 RE-BASELINE FROM HEAD — 2026-09-09

**Measured at `9cb14d7`.** Premises re-checked in source this pass are marked
**[RE-VERIFIED]**; rows carried on their filing evidence alone are marked
**[filed only]** and must not be read as re-confirmed. Nothing here is
implemented; this is a ranking document.

**Standing:** P5-G externally pending · P5-H held · Phase 4 explicitly
exit-incomplete · no production / ASC / enforcement / age-state mutation.

---

## 1. C-71 — THE INVENTORY, AND IT CHANGES THE UNIT

**The prerequisite is discharged. `SessionIdentityHeader`
(`SessionDetailView:1985`) carries NOTHING beyond attribution.**

| Element | Site | Interactive? |
|---|---|---|
| avatar image, or initials fallback | `:2043`–`:2064` | **no** |
| display name | `:2072` | **no** |
| optional **location** | `:2074`–`:2076` | **no** |
| `Spacer` | `:2078` | layout |

**No `Button`, no `NavigationLink`, no `onTapGesture`, no menu, no follow
state, no privacy indicator** — the source comment at `:2081` records that the
privacy icon was deliberately removed. **Location is the only content beyond
attribution**, and it is the member's own location on the member's own session.

### The decisive routing fact — the Feed does not use this view at all

`SessionIdentityHeader` is instantiated **exactly once**, at
`SessionDetailView:746`, and `SessionDetailView` is opened only from **local
Core Data sessions**: `ContentView:1661` and `MeView:466`. **The Connected Feed
opens `BackendSessionDetailView`** (`ContentView:1681`, `PeopleView:743`,
`:788`), which has its **own** identity header (`:415`) resolving the directory
account and avatar key.

**So the product rule's "Connected Feed → keep the identity row" half is already
satisfied by a different view, and hiding this row cannot affect Feed
attribution.** Corroborating: this header's `displayName` returns the literal
**`"User"`** for a non-current user (`:2023`) — a placeholder that would be
useless as attribution, and **probably unreachable**, since local `Session`
rows are the member's own. *Probably*, not certainly: I did not exhaustively
trace every `Session` creation path, and that trace belongs in the unit.

**Consequence: C-71 is smaller and safer than filed** — the two contexts the
rule says "hide" are the only two contexts this row appears in.

### One thing the inventory found in passing — FILED, NOT FIXED

**C-72:** `displayName` (`:2019`) runs a `Profile` fetch reached from `body`
**twice** per evaluation — directly at `:2072` and again via `initials`
(`:2034`). **Same class as C-56, different view.** Severity unassigned pending
measurement, exactly as C-56's was. **If C-71 hides the row, the fetch stops on
those paths as a side effect** — a reason to sequence C-71 first, never a reason
to call C-72 fixed.

---

## 2. Classification

### (1) Confirmed defects

| Row | Evidence | Note |
|---|---|---|
| **C-6** | **[RE-VERIFIED]** `Persistence.swift:43` — `fatalError` on store load | crash-on-launch shape |
| **C-16** | **[RE-VERIFIED]** `SessionSyncQueue.swift:396` — `try! fm.url(…)` | one site, not the "directory creation" plural implied |
| **C-21** | **[RE-VERIFIED] — AND MATERIALLY NARROWED** | see below |
| **C-62** | **[RE-VERIFIED]** `PublishService:294` `NSLog` with `title=%@`, **no enclosing `#if DEBUG`** — Release-reachable | register said *Unverified*; the write is now confirmed. **What no evidence supports is that any read path surfaces it** |
| **C-5** | **[filed only]** duplicate Score adoption | not re-checked this pass |
| **C-27** | **[filed only]** location does not carry to Solo | confirmed by trace at filing |
| **C-34 (TTL half)** | **[filed only]** | version-signal half shipped in Phase 4 |

**C-21 is not what the row says.** It reads *"the shape of a dropped check"*.
Measured: at `:260`, `:526`, `:577` the binding is unused **because the status is
re-tested inline as `http.statusCode` on the very next line** — the check is
present, only the binding is dead. `:859` uses its binding properly. **These
three are literally compiler warnings today** (*"initialization of immutable
value 'status' was never used"*, 6 of the 175 Release warnings). **C-21 is dead
code, not a missing status check**, and its severity should fall accordingly.

### (2) Unverified / investigation-only

**C-37, C-39, C-40, C-42, C-47** — the standing P5-L set; each needs measurement
before any fix.
**C-65** (a publish reports success while silently omitting an attachment),
**C-66** (`unfollow`'s failure branch does not refresh), **C-68** (video review
player never released on disappear), **C-69** (a fresh `RemoteAudioPlayerController`
ignores the session rate), **C-72** (above). All source-identified; **none has an
observed user consequence**, and C-69's path is currently unreachable.
**C-65 is the one with real user-facing weight** — silent data loss on a publish
that reports success.

### (3) Product / UI decisions, not defects

**C-63** — arbitrary `.file` attachments can never upload; choose (a) restrict
selection or (b) map specific types. **Do not widen the bucket to
`application/octet-stream`.**
**C-71** — the presentation rule above; now de-risked by the inventory.
**H-1** — ProfileView "Connected" section grouping (logged only).
**H-2** — C-70(a)'s residual: a generic directory-sync failure still renders
beneath the Account ID field (logged only, not a reopening).

### (4) Release-gating vs ordinary quality work

**Nothing in this backlog gates release.** `docs/phase-5-scope.md` is explicit:
*"P5-A through P5-H gate release. P5-I through P5-N do not."*

**Release-gating housekeeping, tracked separately and NOT part of this ranking:**
Q6/A execution; the **Production ASSN Server URL** plus
`APPLE_ASSN_ALLOWED_ENVIRONMENTS`; P5-G's external legal return; P5-H (held);
and Phase 4's own exit conditions 2, 6-ASC and 8 plus the C-34 avatar device
verification. **C-30, C-31, C-32 are RC-owned, not Phase 5.**

The one soft coupling already recorded: **C-14 should not remain unfixed once a
privacy policy is published** — relevant to P5-H, not to any unit below.

---

## 3. (6) Grouping — YES, four finishing units instead of one C-number at a time

The remaining rows fall into four coherent shapes. This regroups what exists; it
adds no new work.

| Unit | Contents | Shape | Why grouped |
|---|---|---|---|
| **P5-J′ — correctness & hygiene** | **C-6**, **C-16**, **C-21**, **C-20** (re-verify then most likely close) | small, mechanical, all source-verifiable | one build, one census, one warning delta. C-21 and C-20 may resolve to *no code change* and *close as not-reproducing* |
| **P5-K′ — reliability defects** | **C-65** first, then **C-66**, **C-69**, **C-68** | behavioural, each needs a pre-fix control | all four are failure-path or teardown defects in code P5-M and C-50 just touched; the fixtures overlap |
| **P5-P — product & UI decisions** | **C-63**, **C-71** (+ **C-72** as its measured side effect), **H-1**, **H-2** | needs *your* decision before any code | none can start without a product answer; batching the questions costs one round trip instead of four |
| **P5-L — investigations** | **C-37**, **C-39**, **C-40**, **C-42**, **C-47**, **C-62** | measurement-only, no fix authorised | already a unit in the scope doc; unchanged |

**C-3** and **C-34 (TTL)** stay on their own — C-3 is a measured performance
refactor of `PracticeTimerView`'s foreground hydration with a real design
question, and C-34's TTL half is already P5-I.

---

## 4. (5) Recommended next unit — **P5-K′, opening with C-65**

**Why C-65 over everything else.** It is the only open row where the product
**loses member data and reports success**: a `.pdf` whose thumbnail cannot be
rendered is skipped, no storage object is created, and `uploadPost` still
returns `.success`, so the post publishes without its media and **the member is
never told**. Every other open row is dead code, a cosmetic redundancy, an
unmeasured cost, or a decision waiting on you.

**Why not the alternatives.** **P5-J′** is cheaper but two of its four rows may
evaporate on contact (C-20 not reproducing, C-21 being dead bindings), so it is
tidying, not risk reduction. **P5-P** cannot start without your decisions.
**C-3** is a genuine refactor with a design question and no user-visible symptom
beyond a cosmetic thumbnail flash the row itself says should not be fixed
separately.

**Second choice, and it is close: P5-J′**, precisely *because* it may shrink —
closing C-20 and C-21 honestly would remove two rows that currently overstate
the backlog's risk.

**If you would rather unblock the batch, P5-P's four questions are cheap to
answer and would let product work run alongside.**

---

## 5. What I did NOT do

No implementation. No production, ASC, enforcement, device or age-state
mutation. **Tier 2's ~49 accessibility candidates are untouched and remain an
unverified candidate inventory** — not a defect count, not a quality metric, and
not part of Phase 5 unless you put them there.
