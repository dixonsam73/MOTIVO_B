# P5-G / CP-4 — DECISION REGISTER

**Opened 2026-09-08. DECISIONS RECORDED 2026-09-08 — see §A.** This is the decision
surface for the DPIA and the legal confirmations, not a design and not an
implementation plan.

**READING ORDER: §A** the decisions · **§0-§2** the evidence each rests on ·
**§B** the Q6 reachability analysis · **§C** what LEGAL still owes · **§D** the
minimum work before P5-G closes.

**STATE OF CHANGE, kept accurate rather than aspirational.** This document opened
saying no code change was proposed and none made. **That is no longer true and is
corrected here rather than left to mislead.** Two things changed under explicit
account-holder authorisation on 2026-09-08: the two `insert-if-absent` comment
corrections identified in Q1 (**comments-only — no non-comment line moved — Debug
and Release both build clean**), and the §8 P5-B label reconciliation in
`docs/phase-5-scope.md`. **§D1 additionally PROPOSES a behavioural change** —
Q1's periodic re-derivation — **which is not written.**

**NO PRODUCTION MUTATION HAS BEEN MADE.** Q6/A is authorised and **not executed**.

**THE ONE RULE THIS DOCUMENT EXISTS TO ENFORCE: what the implementation
currently DOES is not what has been DECIDED.** Several of the questions below
have a current behaviour that is an artefact of implementation order rather than
a choice anybody made. Q2 is the worked example — a writer exists, has never been
called, and that silence is not a policy. Q1 is the one most likely to be assumed
rather than decided, because its current behaviour looks like a deliberate design
and is not.

---

## A. DECISIONS OF RECORD — ACCOUNT HOLDER, 2026-09-08

**All six questions are decided by the account holder. Two carry a remaining
LEGAL confirmation, and one carries a deliberately UNDECIDED sub-part.** Nothing
below is implemented; no production mutation has been made.

| Q | AH decision | still needs LEGAL | still undecided |
|---|---|---|---|
| **Q1** reclassification | **A, refined — bidirectional periodic re-derivation, prospective only** | no | refresh cadence/opportunity — **deliberately deferred to implementation** |
| **Q2** teen inbound requests | **A — teens cannot enable inbound follow requests. Deliberate policy.** | no | — |
| **Q3** `communicationLimits` | **A — do not consult, consequent on Q2** | no | — |
| **Q4** declined / unavailable | **A — fail-closed, persist nothing, retryable** | **yes — final wording + jurisdictional adequacy** | — |
| **Q5** device-bound age source | **A, amended by Q1 — minimisation kept** | **yes — DPIA adequacy** | — |
| **Q6** legacy directory row | **A authorised (not yet executed). B NOT authorised** | no | whether B is ever justified — **analysis delivered in §B** |

### A1 — Q1 AS DECIDED, with the refinement

Études **periodically re-derives** Apple's declared age range for Connected
identities and applies a changed band **prospectively**, to the surfaces the band
actually governs (§1: discovery, inbound follow requests).

**Explicitly BIDIRECTIONAL:**

- **adult → 13-17** activates the effective child-safety overrides;
- **13-17 → adult** removes those overrides, and the **persisted underlying
  preferences become effective again**.

**The persisted preferences are NEVER destructively rewritten merely because an
override applies.** The deployed read-time override already has exactly this
shape — it withholds effect and destroys no history — so the server semantics
needed for both directions are in place. `*_set_under_band` is what makes the
upward direction computable without having stored a second copy of the
preference.

**CADENCE DECIDED 2026-09-08: 30 DAYS.**

**Its purpose is NOT to approximate Apple's declaration anniversary — which we
cannot know (§E5) and must not try to model.** It is to **bound the lag between
Apple beginning to return a changed range and Études observing it**, without
needless API activity. Thirty days gives a reasonable bound at negligible cost,
given that Apple anticipates frequent calls (§E1) and a change can surface at most
once a year anyway (§E2).

**Store only the minimum operational timestamp needed to enforce the throttle,
scoped to the Études identity. No DOB, no declaration anniversary, no
`ageRangeDeclaration` provenance.** The timestamp records *when Études last
asked*, which is neither an age nor provenance.

**The DPIA describes the protection and the 30-day bound — never Apple's internal
cache policy as if it were ours.**

### A2 — Q2 AS DECIDED

A **13-17 member cannot enable inbound follow requests**. Relationship
*initiation by another member* stays closed; **the young member may initiate
relationships themselves**. **No follow-request control is to be added.**

**This is recorded as deliberate product and privacy policy, NOT as an accidental
absence of UI.** `AccountPrivacyService.setFollowRequestsEnabled`
(`AccountPrivacyService.swift:77`) and the deployed
`account_privacy_set_follow_requests_v1` therefore have **no client caller by
decision**. That reason must be recorded at both sites so a later reader does not
"finish" the wiring.

### A3 — Q3 AS DECIDED

**Do not consult `activeParentalControls.communicationLimits`** for the current
feature set. The teen inbound-contact rule (A2) already supplies the relevant
protection, so the additional Apple signal **changes no behaviour** and adds
complexity and data surface for nothing. **Reopen only if Q2 is ever revisited.**

### A4 — Q4 AS DECIDED, LEGAL OUTSTANDING

Declined, unavailable and error all remain **fail-closed**, **persist nothing**,
and are **retryable with no persisted refusal count and no backoff**. Current
neutral wording is kept **provisionally**.

**CARRIED TO LEGAL:** final wording and jurisdictional adequacy. **The wording
must continue to describe Apple sharing an age range, never Études asking for an
age.**

### A5 — Q5 AS DECIDED, LEGAL OUTSTANDING

**Minimisation is kept: no DOB, and `ageRangeDeclaration` provenance is still
never stored.**

The DPIA must state plainly that the range comes from **the Apple Account active
on the device at request time** and is **not independently bound or verified
against the Études/SIWA identity**.

**AMENDED BY Q1 — this supersedes the wording the register opened with.** Because
Q1 now requires periodic re-derivation, the band must **NOT** be described as
permanently "point-in-time" or "not revisited". Describe the **residual assurance
after periodic refresh** accurately instead: a repeated, still-unverified
assertion from whichever Apple Account is active at each refresh.

**CARRIED TO LEGAL:** DPIA adequacy of that characterisation.

### A6 — Q6 AS DECIDED

**Option A is authorised and NOT YET EXECUTED.** Before release, establish a
genuine age band for Samuel (`dfaf8d18`) **through the ordinary client/Apple
path**, so the sole legacy pre-CP exception is removed **without manufacturing
age state**.

**RESOLVED 2026-09-08 ON THE §B ANALYSIS: Q6 IS A ONLY. B IS REJECTED, NOT
MERELY UNAUTHORISED.** `tg_directory_requires_band` **is not to be widened to
`UPDATE`.** The reasons of record, both measured in §B:

- **No supported post-CP lifecycle can independently remove `account_privacy`
  while retaining `account_directory`.** Both tables cascade from `auth.users`;
  no function, Edge Function or client-reachable statement deletes a privacy row;
  `account_privacy` has RLS on, zero policies and no client grants.
- **Widening the trigger would introduce a REAL cleanup-worker failure mode** —
  `membership_cleanup_v1`'s `avatar_key` UPDATE (`:463`) sits inside `must(...)`
  and would abort an otherwise-correct expiry run against a band-less row.

**IF AN INDEPENDENT PRIVACY-ROW DELETION LIFECYCLE IS EVER INTRODUCED, RECONSIDER
THE INVARIANT STRUCTURALLY AT THAT POINT** — a real FK from `account_directory`
to `account_privacy`, not a trigger.

**EXECUTION OF A IS DEFERRED, 2026-09-08.** Samuel's genuine band establishment
**waits until the final re-derivation behaviour is known**, so production state is
not established immediately before its lifecycle changes.

---

## 0. STATE AT OPENING — MEASURED 2026-09-08 17:31 UTC, NOT CARRIED FORWARD

Verified against production `rlwtqxumfobakvdueugm`, confirmed to be the same ref
the app's `Info.plist` carries.

| measure | value |
|---|---|
| `auth.users` | 2 |
| `account_privacy` | 1 |
| `account_directory` | 1 |
| `membership` | 1 (Sandbox) |
| `posts` / `post_comments` / `follows` | 6 / 1 / 0 |
| `storage.objects` | 8 |

Every figure matches the handover's 17:25 census. Repository: branch
`feature/solo-connected`, tree clean, **HEAD `e2d9397` is 1 ahead of origin** —
the handover commit itself, which the handover correctly predicted it could not
record.

**The two identities, and the fact the handover does not record:**

| identity | created | privacy row | directory row | posts |
|---|---|---|---|---|
| `dfaf8d18` — "Samuel Dixon", the control | 2026-07-23 | **0** | **1** | 6 |
| `6fd0a833` — surviving CP-3 test identity | 2026-09-08 | 1 (`band_18_plus`) | 0 | 0 |

**SO PRODUCTION CONTAINS ONE PUBLISHED DIRECTORY ROW WITH NO AGE BAND.** That is
Q6. `6fd0a833` carries `lookup_enabled = false`, `lookup_set_under_band =
band_18_plus`, stamped 17:15:05 — **the surviving evidence of an explicit user
preference, and it must not be restored to `true`.**

---

## 1. WHAT THE BAND ACTUALLY GOVERNS — measured, and narrower than it reads

**Exactly three database objects consult `account_privacy`**, established by
sweeping every function definition in `public` rather than by reading the design:

- `search_account_directory` — discovery
- `follow_requests_open` — inbound follow requests
- `tg_account_directory_requires_band` — the band-before-directory trigger

**Nothing else.** No post visibility, no feed, no comment, no attachment and no
storage path consults the age band. This is load-bearing for Q1 and Q5: the band
governs **discoverability and inbound contact**, and governs **nothing about
content already published or relationships already approved.**

---

## 2. THE REGISTER

Six questions. Each separates **current behaviour (measured)** from **what is
undecided**, then gives options, a recommendation, and the decision owner.
Owners are **AH** (account holder) or **LEGAL** (external confirmation).

---

### Q1 — Adult → 13-17 reclassification. **DECIDED: A, refined (§A1).** OWNER: AH

**CURRENT BEHAVIOUR, AND IT IS NOT A DECISION.** A downward reclassification is
**unobservable by construction**. Measured in the source, not inferred:

- `AuthManager.ensureAgeBandEstablished` fetches first and, **on success, returns
  before writing anything**.
- `AgeBandRecoveryCoordinator.recoverIfNeeded` short-circuits **before any Apple
  call** when a band exists — hardware-verified during CP-3.
- Those are the only two paths to `account_privacy_upsert_v1`
  (`ProfileView:1138`, `AgeBandRecoveryCoordinator:103`).

**So once a band is established, Études never asks Apple again, ever.** Apple may
reclassify; Études will not hear about it.

**THE SERVER IS ALREADY BUILT FOR THE CASE THE CLIENT NEVER RAISES.**
`account_privacy_upsert_v1` is **not** insert-if-absent: its `on conflict` clause
sets `age_band = excluded.age_band` and stamps `band_updated_at` only on a real
change. And the read-time child override then withholds effect from adult-set
preferences automatically. **The mechanism works; nothing triggers it.**

> **A DOCUMENTATION DEFECT — CORRECTED 2026-09-08 under explicit authorisation.** `AuthManager.swift:172` and
> `AgeBandRecoveryCoordinator.swift:67` both describe that writer as
> **"insert-if-absent"**. The behavioural claims they draw from it are true (no
> second row; an unchanged band moves nothing), but the characterisation is
> false — it is upsert-with-band-update. This is exactly B-33's shape: a
> correct-sounding claim that cannot be falsified by reading the file it sits in.
> **Both comments are now corrected** (`AuthManager.swift`,
> `AgeBandRecoveryCoordinator.swift`). The change is **comments-only — verified by
> a diff in which no non-comment line moved — and Debug and Release both build
> clean.** The corrected text also records that the server CAN move a band, which
> is what Q1/A1 now requires it to do.

**UNDECIDED:** what happens to already-published posts, and to existing approved
follows, when an identity reclassifies downward.

| option | consequence |
|---|---|
| **A — re-derive periodically** (e.g. on the declaration anniversary Apple already re-prompts on) and apply the override going forward. Published content and existing follows untouched | Protection applies to discovery and new contact only. Cheapest; matches what the band actually governs (§1). **Recommended.** |
| B — re-derive, and additionally retract discoverability and suspend existing follows on downgrade | Strongest, but suspends relationships a member may have held legitimately for years, on an Apple signal Études cannot audit |
| C — leave as-is: never re-derive | The status quo. **Must not be adopted by silence.** Defensible only if stated as a decision with a reason |

**DECIDED: A, with the refinement in §A1** — re-derivation is **bidirectional**
(downgrade activates the overrides; upgrade releases them and lets the persisted
preferences become effective again), applies **prospectively only**, and
**never destructively rewrites a preference**. **The cadence is deliberately left
open to implementation and is NOT "declaration anniversary" by default.**

The DPIA cannot describe protections that depend on a re-derivation the client
never performs — which is precisely why the current short-circuit had to be
decided against rather than inherited.

**EVIDENCE:** the two call sites above; the deployed `on conflict` clause; §1's
three-object sweep.

---

### Q2 — May a 13-17 member opt INTO inbound follow requests? **DECIDED: A (§A2).** OWNER: AH

**CURRENT BEHAVIOUR, AND IT IS AN IMPLEMENTATION STATE, NOT A POLICY.**
`AccountPrivacyService.setFollowRequestsEnabled` exists at
`AccountPrivacyService.swift:77` and has **zero call sites in the entire client**
— verified by sweep. `account_privacy_set_follow_requests_v1` is deployed and has
never been called. Meanwhile `follow_requests_open = enforcement_gate AND
account_privacy_requests_open`, with the privacy conjunct **unconditional**: the
kill switch may relax entitlement, never child safety. CP-2-R1 made a missing or
unresolved row resolve **CLOSED**.

**UNDECIDED:** whether a teen should ever be able to turn inbound requests on.

| option | consequence |
|---|---|
| **A — no, permanently. Teens cannot open inbound requests** | Simplest to defend in a DPIA; no new surface. Must be recorded **as a decision with a reason**, not left as an absence. **Recommended.** |
| B — yes, teen-openable with the same override semantics as discovery | Requires a client control that does not exist, and a defensible argument that a 13-year-old opening inbound contact is proportionate |
| C — yes, but guardian-gated | Études has no guardian relationship and `ageRangeDeclaration` is deliberately never read. **Not available without abandoning a settled invariant.** |

**DECIDED: A.** Recorded reason: Études has no moderation, no reporting surface
and no guardian channel, so inbound contact from strangers to a minor has no
mitigating control behind it. **A young member may still initiate relationships
themselves** — what is closed is initiation *by another member*.

**NO FOLLOW-REQUEST CONTROL IS TO BE ADDED.** The never-called writer is dead code
**by decision, not by omission**; the reason must be recorded at both sites so a
later reader does not "finish" the wiring. See §D2.

---

### Q3 — `activeParentalControls.communicationLimits`. **DECIDED: A (§A3).** OWNER: AH

**CURRENT BEHAVIOUR: nothing.** `communicationLimits`, `activeParentalControls`
and `ParentalControl` appear **nowhere** in the client — verified by sweep. Added
to scope by CP-1 r3 and never worked.

**UNDECIDED:** whether Études consults it at all, and what it changes.

| option | consequence |
|---|---|
| **A — do not consult it. Record why** | The band already closes discovery and inbound requests for teens (Q2/A). Reading a second Apple signal that can only close what is already closed adds an API dependency and a data-protection surface for no behavioural gain. **Recommended for the current feature set.** |
| B — consult it and treat a restriction as a further close | Meaningful only if Q2 resolves to B — i.e. only if teens can open inbound contact at all |
| C — consult it and surface it to the member | New UI, new copy, new failure modes |

**DECIDED: A, consequent on Q2 = A.** The teen inbound-contact rule already
supplies the protection, so the extra Apple signal changes no behaviour and adds
complexity and data surface for nothing. **Reopen only if Q2 is ever revisited.**

---

### Q4 — Declined / unavailable age sharing. **DECIDED: A (§A4). LEGAL OUTSTANDING.** OWNER: AH, then LEGAL

**CURRENT BEHAVIOUR:** an eligibility fact only. `.declinedSharing` and any
unrecognised response map to `.unavailable`; `.unavailable` and `.ineligible`
both refuse Connected **before any server contact**, so no identity is minted.
Copy today: *"Études needs Apple to share your age range before Connected can be
set up. You can change this in Settings, under your Apple Account."* Nothing is
written. Under-13 refusal is hardware-verified, twice.

**UNDECIDED:** retry policy, final wording, and jurisdictional variation.

| option | consequence |
|---|---|
| **A — unlimited retry, no persistence, current neutral wording** | Matches "fails closed, records nothing". A member who changes their Apple setting simply tries again. **Recommended.** |
| B — persist a refusal count / back off | Creates a record of a refusal — a data-protection surface for no product gain |
| C — jurisdictional wording variants | Needed only if LEGAL says a specific jurisdiction requires a specific disclosure |

**DECIDED: A** — fail-closed, persists nothing, retryable with **no persisted
refusal count and no backoff**. Current neutral wording kept **provisionally**;
**final wording and jurisdictional adequacy carried to LEGAL** rather than
re-drafted here. **Note the wording must not imply Études asked the member their
age** — Apple asked; Études received a range.

---

### Q5 — The band is tied to the DEVICE'S Apple Account, not to the Études identity. **DECIDED: A, amended by Q1 (§A5). LEGAL OUTSTANDING.** OWNER: AH, then LEGAL

**CURRENT BEHAVIOUR — this is a structural fact, not a defect.** `DeclaredAgeRange`
answers for the Apple Account signed in on that device. A different Apple Account
on the same device, or the same Apple Account on another device, is a different
age source. Études binds the band to the **Études/SIWA identity** at first
establishment and — per Q1 — never revisits it.

**Compounding it: `ageRangeDeclaration` (`selfDeclared` / `confirmed` /
`guardianDeclared`) is deliberately never inspected and never stored.** So Études
does not know, and cannot later say, whether a given band was self-asserted by a
teenager or confirmed by ID. That was a sound minimisation choice; it also caps
how much assurance the band carries.

**UNDECIDED:** how the DPIA states the residual assurance honestly.

| option | consequence |
|---|---|
| **A — state it plainly: the band is a point-in-time assertion from the signed-in Apple Account, of unrecorded provenance, not revisited** | Honest, and consistent with the project's evidence discipline. **Recommended.** |
| B — begin storing `ageRangeDeclaration` to strengthen the claim | Reverses a deliberate minimisation decision and stores more about minors. **Not recommended.** |
| C — re-derive per device / per session | Multiplies Apple prompts and still cannot bind an Apple Account to a person |

**DECIDED: A, amended by Q1.** Minimisation is kept — no DOB, no stored
provenance. **The DPIA must not overstate this** and must not imply the band is
verified identity.

**THE OPENING WORDING OF THIS QUESTION IS SUPERSEDED.** Because Q1 now requires
periodic re-derivation, the band must **NOT** be described as permanently
"point-in-time" or "not revisited". State the **residual assurance after periodic
refresh**: a repeated, still-unverified assertion from whichever Apple Account is
active on the device at each refresh. **DPIA adequacy carried to LEGAL.**

---

### Q6 — The pre-CP directory row with no band. **DECIDED: A authorised, B NOT authorised (§A6). Analysis in §B.** OWNER: AH

**NOT IN THE HANDOVER. FOUND BY MEASUREMENT TODAY.**

`tg_directory_requires_band` is **`BEFORE INSERT` only** — read from the deployed
trigger definition. `dfaf8d18` has a published `account_directory` row created
2026-07-23, before CP-1, and **no `account_privacy` row at all**. Its directory
row is therefore reachable by ordinary profile-publish **UPDATE**s without ever
acquiring a band.

**So the invariant "no directory row exists without an age band" is FALSE in
production today, by exactly one row.** Going forward it holds for every INSERT.

**UNDECIDED:** whether this is closed before release, and how the DPIA states it.

| option | consequence |
|---|---|
| **A — establish a band for `dfaf8d18` through the ordinary client path** before release, making the invariant true with no schema change | Cheapest and needs no production DDL; it is the account holder's own identity, so the band would be genuinely derived rather than manufactured. **Recommended.** |
| B — extend the trigger to `BEFORE INSERT OR UPDATE` | Makes the invariant structural, but would **block the existing row from ever being updated again** until A is done anyway. A after B, not instead of it |
| C — accept and document the exception | Weakest; leaves a published profile with no age band in a released product |

**DECIDED: A is authorised and NOT YET EXECUTED. B is NOT authorised.**

**The opening "A, then B" recommendation is SUPERSEDED by the §B reachability
analysis**, which establishes that **no supported lifecycle can produce this state
after CP-1** — both tables cascade from `auth.users`, no function or Edge Function
deletes a privacy row, and `account_privacy` has RLS on with zero policies and no
client grants. **After A there is nothing left for B to close**, and §B4 shows B
would make the expiry worker's `avatar_key` UPDATE fail closed on exactly the
legacy row. **B stays recorded as defence-in-depth, not decided.**

**A is a production mutation and is NOT performed here.**

---

## B. Q6 REACHABILITY ANALYSIS — IS `BEFORE INSERT OR UPDATE` JUSTIFIED?

**THE QUESTION AS SET:** is there any *supported lifecycle* by which an
`account_directory` row can survive while its `account_privacy` row becomes
absent — i.e. a genuinely reachable **post-CP** invariant violation that UPDATE
protection would close?

**ANSWER: NO. No supported lifecycle can produce that state after CP-1.**
Measured against deployed production, not reasoned from the design.

### B1 — The four candidate lifecycles, each closed

**1. Identity deletion (`delete_account_v1`).** Both tables carry a FK to
`auth.users` with **`ON DELETE CASCADE`** — read from `pg_constraint`, both
confirmed. The function deletes `account_directory` explicitly
(`delete_account_v1/index.ts:392`) and then deletes the auth user
(`:401`), which cascades `account_privacy`. **Both rows go. Neither can outlive
the other.**

**2. Expiry cleanup (`membership_cleanup_v1`) — the one that looked dangerous,
and is not.** The retention matrix **RETAINS** the `account_directory` row on
expiry, so if the worker removed the privacy row this would be the violation.
**It does not: `account_privacy` appears NOWHERE in any Edge Function** — swept
across all six, zero hits. The worker touches `account_directory` only to read
`avatar_key` and to `update ... set avatar_key = null` (`:452`, `:463`). It
**retains both rows**. There is no `auth.admin.deleteUser` in that file and the
header forbids one.

**3. Direct client DML.** Impossible. `account_privacy` has **RLS ENABLED with
ZERO policies**, and **grants to `postgres` only** — no privilege for `anon`,
`authenticated` or `service_role`. Every access is through the six SECURITY
DEFINER RPCs, and **not one contains a DELETE**. There is no client-reachable
statement that removes a privacy row.

**4. Server functions.** Sweeping every `public` function: only
`follow_requests_open`, `search_account_directory` and
`tg_account_directory_requires_band` reference `account_privacy` at all, and all
three are read-only with respect to it. No `%delete%` or `%cleanup%` function
mentions either table.

### B2 — There is no FK between the two tables, and that is the real point

`account_directory` has **no FK to `account_privacy`** — its only FK is to
`auth.users`. So the tables are not *structurally* coupled; they are coupled by
the `BEFORE INSERT` trigger at creation, and by their **shared cascade parent**
thereafter. That shared parent is what makes the invariant hold: **the only way
to remove a privacy row is to remove the auth user, which removes the directory
row in the same statement.**

### B3 — The one residual, and it is not a lifecycle

An operator holding `postgres` credentials can delete a privacy row by hand.
**That is exactly how today's single exception arose** — `dfaf8d18` predates
CP-1, so its directory row was inserted when no trigger and no privacy table
existed. **A historical migration artefact is not a lifecycle**, and by the
account holder's own framing it does not justify production DDL.

### B4 — B is not free, and this is the strongest argument against it

**`BEFORE INSERT OR UPDATE` would make the expiry worker fail closed on exactly
the legacy row.** `membership_cleanup_v1` performs
`account_directory.update({avatar_key: null})` (`:463`) wrapped in `must(...)`,
which aborts the run on error. Against an identity with no privacy row that
UPDATE would raise `23514` and **abort a cleanup run that is otherwise correct**
— converting a dormant documentation exception into an active worker failure.

The coupling generalises beyond the legacy row: B makes **every** future
maintenance UPDATE on a directory row conditional on a privacy row existing,
including updates whose purpose is protective (clearing an avatar). **That is a
new failure mode introduced to defend against a state nothing can produce.**

### B5 — CONCLUSION

**Option A alone makes the population correct**, and after A there is **no
reachable post-CP state for B to close**. B would add production DDL, introduce
the §B4 failure mode, and defend an unreachable case.

**RECOMMENDATION: execute A; do NOT adopt B.** Keep B recorded as
defence-in-depth to be revisited **only** if a future change introduces a
privacy-row deletion path — at which point the correct fix is more likely a real
FK from `account_directory` to `account_privacy` than a trigger.

**This supersedes the register's opening "A, then B" recommendation**, which was
written before the reachability analysis existed.

---

## 3. DECISION ORDER — RESOLVED

**Q2 → Q3 was the only hard dependency and it is discharged:** Q2 resolved to A,
so Q3's A follows. Q1, Q4, Q5 and Q6 were independent. **Q4 and Q5 are the two
carrying external confirmation; Q6/A is the only decision that touches production
data, and it is authorised but not executed.**

---

## C. WHAT P5-G STILL REQUIRES FROM LEGAL / EXTERNAL CONFIRMATION

**Two items, both narrow. Neither blocks the implementation work in §D.**

**C1 — Q4: the refusal copy.** Confirm the wording shown when Apple declines or
cannot supply a range, and whether any jurisdiction requires a variant. Current
provisional text: *"Études needs Apple to share your age range before Connected
can be set up. You can change this in Settings, under your Apple Account."*
**Binding constraint on any redraft: it must describe Apple SHARING an age range,
never Études ASKING for an age.** The under-13 refusal reads *"Études Connected is
for ages 13 and over."*

**C2 — Q5: DPIA adequacy of the residual-assurance characterisation.** Confirm
that the DPIA may state, and that it suffices to state, that:

- the range comes from the **Apple Account active on the device at request time**;
- it is **not independently bound or verified** against the Études/SIWA identity;
- **no DOB and no provenance** (`ageRangeDeclaration`) is stored, deliberately;
- the band is **periodically re-derived** (Q1), so the assurance is a **repeated
  unverified assertion**, not a one-time one and not a verified identity.

**C3 — the DPIA as a whole**, including lawful basis, must carry §4's teen
limitation **verbatim**. **A DPIA implying teen protections are device-verified
would misstate the evidence.**

**C4 — scope and ongoing duty (added 2026-09-08, see §I).** Is Études in scope of
the app-store age-assurance laws (Texas SB2420 and successors)? If so, does any
impose an **ongoing** age-assurance duty beyond establishment? And does
`RESCIND_CONSENT` handling bind Études? **Apple explicitly refers this to counsel**
— *"For questions about your compliance obligations, consult your legal counsel."*
**Q1's periodic re-derivation is provisional pending this.**

**NOT required from LEGAL:** Q2, Q3 and Q6 are settled product/privacy policy
and need no external confirmation.

---

## D. MINIMUM WORK BEFORE P5-G CAN CLOSE

**Ordered. None of it is P5-H, and none of it is started.**

**D1 — Q1 re-derivation (the only real implementation). NOT STARTED, AND NOT TO
BE STARTED YET.** The supported-mechanism investigation is complete — **§E** — and
the recommended architecture is **§F**. **§F is a recommendation awaiting approval,
not a plan in flight.** The single behavioural
change these decisions require. Today `ensureAgeBandEstablished` returns on fetch
success before writing, and the recovery coordinator short-circuits before any
Apple call, so **no band is ever re-derived**. Needed:

- a refresh opportunity and cadence — **to be determined against what Apple
  actually supports, and NOT hard-coded to "declaration anniversary"**;
- a path that re-requests the range and calls `account_privacy_upsert_v1` when a
  band already exists. **The server half already works**: `on conflict` updates
  `age_band` and stamps `band_updated_at` only on a real change;
- **no new server work for the override**: the deployed read-time override
  already handles both directions and destroys no preference history;
- **the upward direction must be asserted**, not assumed — 13-17 → adult must
  release the overrides and let the persisted preferences become effective again.

**D2 — Q2's deliberate absence, recorded in code. DONE 2026-09-08,
DOCUMENTATION ONLY.** `AccountPrivacyService.setFollowRequestsEnabled` now carries
the decision and its reason, and says **do not "finish" this wiring**. No control
was added and no behaviour changed; Release builds clean.

**The server-side half is deliberately NOT done:** annotating the deployed
`account_privacy_set_follow_requests_v1` would be a production DDL change for a
comment, which is not warranted. The client site is where a reader would re-add
the control.

**D3 — Q6/A execution. DEFERRED BY DECISION, 2026-09-08 — it must come AFTER
D1.** Establishing Samuel's genuine band immediately before changing the band's
lifecycle would create production state whose semantics are about to move.
**Sequence: settle D1's behaviour, then execute D3.** It remains a production
mutation needing a prediction committed beforehand and a fresh census immediately
before. **Q6/B is rejected outright (§A6) and is not part of D3.**

**D4 — the DPIA**, carrying §4 verbatim and §C2's characterisation, then C1 and
C2 back from LEGAL.

**D5 — record the cadence chosen in D1** back into this register and into
`docs/phase-5-scope.md`, so the DPIA's description and the shipped behaviour
cannot drift apart.

**ALREADY DONE, 2026-09-08:** the two `insert-if-absent` comment corrections
(comments-only; no non-comment line moved; Debug and Release both clean) and the
§8 P5-B label reconciliation.

---

## E. DECLARED AGE RANGE — WHAT APPLE ACTUALLY SUPPORTS AFTER ESTABLISHMENT

**Established 2026-09-08 from (i) the installed SDK interface and (ii) Apple's
own documentation and WWDC25 session 299. NO SANDBOX BEHAVIOUR IS USED AS
EVIDENCE HERE** — the CP-3 fixture was demonstrably unreliable and cannot
establish production API semantics. Our own device observations are quarantined
in §E8 and are not load-bearing.

**Sources.** `iPhoneOS26.5.sdk/System/Library/Frameworks/DeclaredAgeRange.framework/
Modules/DeclaredAgeRange.swiftmodule/arm64e-apple-ios.swiftinterface` (the complete
public surface — read in full, not sampled); Apple's `DeclaredAgeRange` framework
reference and the article *Requesting people share their age range with your app*;
WWDC25 session 299 *Deliver age-appropriate experiences in your app*. Xcode 26.6,
SDK 26.5. Our deployment floor is **iOS 26.2**.

### E1 — May an app call `requestAgeRange` again for an established identity? **YES, AND APPLE EXPECTS IT.**

Nothing forbids it, and Apple's own framing is the opposite of "call once":

> "Because the API will be called often, the system caches the responses so the
> user doesn't constantly have to answer prompts. Practically speaking, this
> means apps won't need to worry that calling the API will prompt the user too
> many times." — WWDC25 299

**This is the single most important finding: repeated calling is the anticipated
usage pattern, and the cache exists precisely to make it cheap.**

### E2 — The anniversary lifecycle. **DOCUMENTED. NO EVENT, NO SIGNAL, NO NOTIFICATION TO THE APP.**

Documented verbatim in the framework article:

> "The system protects privacy by caching age range responses. When a person's age
> crosses into a new range (for example, when they turn 13), the API continues
> returning the previous range **until the anniversary of their original
> declaration**."

WWDC25 299 adds that this applies under both sharing modes, and that the new value
surfaces **"upon request"**:

> "on the anniversary of the original age declaration, upon request, the API will
> then either automatically share or prompt to share."

**THE APP-FACING OBSERVATION SURFACE IS EMPTY.** The entire public interface is
`requestAgeRange`, `isEligibleForAgeFeatures`, `requiredRegulatoryFeatures`,
`showSignificantUpdateAcknowledgment`, and two SwiftUI environment actions.
**There is no notification name, no publisher, no `AsyncSequence`, no delegate and
no changed-value callback anywhere in the framework** — established by reading the
whole interface, not by searching for one. Under *Always Share*, "if new
information is revealed, a notification appears" — **that notification is shown by
the system to the person, not delivered to the app.**

**CONSEQUENCE: there is no push. Learning about a change REQUIRES asking.**

### E3 — Can repeated requests be non-interactive? **NO. `requestAgeRange` STRUCTURALLY REQUIRES A PRESENTATION CONTEXT.**

The signature is `requestAgeRange(ageGates:_:_:in viewController: UIViewController)`,
or the SwiftUI `DeclaredAgeRangeAction` read from `EnvironmentValues` — which
carries a View context. **There is no background or context-free variant.** The
documentation says the method "presents a system-provided interface".

**Two members ARE non-interactive** — `isEligibleForAgeFeatures` and
`requiredRegulatoryFeatures` are `get async throws` with no presentation context —
**but neither returns an age range and neither is a change signal.** See §E6.

**Whether a given call actually shows a sheet is governed by the person's sharing
setting**, not by the app: *Always Share* returns silently; *Ask First* prompts,
but "by default … only on the anniversary of the original response"; *Never Share*
"always declines to share. Nothing is shown." In some regulated regions "the
system automatically provides the person's age range — they can't decline."

### E4 — Caching and synchronisation. **DOCUMENTED, AND CROSS-DEVICE.**

> "Cached responses are synced across devices. For example, a cached age range
> shared on iPhone will sync to Mac." — WWDC25 299

The response changes only: **(a)** on the anniversary of the original declaration,
or **(b)** when the person clears it themselves — Settings → [name] → Personal
Information → Age Range for Apps, then "tapping Share Age Range again", which
"provides an app the updated age range response the next time the age is
requested."

**This sharpens Q5 for the DPIA:** the value is keyed to the iCloud/Apple Account
("the person signed in to iCloud on the device") and **syncs across that account's
devices** — so it is bound to the Apple Account, not to the device, and still not
to the Études identity.

### E5 — Can Études know a re-derivation is due without storing DOB or provenance? **NO — AND IT DOES NOT NEED TO.**

The anniversary is of **the person's original declaration to Apple**, a date
Études does not know, is not told, and must not store. **There is no "due"
signal and no way to compute one.**

**This is not a blocker, because asking is cheap by design (§E1).** The correct
shape is a coarse throttle over our *own* observations, never an attempt to model
Apple's clock. A timestamp of *when Études last asked* is neither a DOB nor
`ageRangeDeclaration` provenance, so it does not breach the minimisation
constraint.

### E6 — `significantChange` and related concepts. **UNRELATED TO AGE REFRESH — THIS IS THE INVERSE DIRECTION.**

`RegulatoryFeature.significantAppChangeRequiresAdultNotification` /
`…RequiresParentalConsent` (26.4+), the deprecated
`ParentalControls.significantAppChangeApprovalRequired` (26.2, deprecated 26.4)
and `showSignificantUpdateAcknowledgment` (26.4+) all concern **the APP changing
significantly** — age rating, features, data practices — and needing adult
notification or parental consent. **None of them signals that a person's age range
changed.** Anyone reaching for `significantChange` as a refresh trigger has the
direction backwards.

Two notes for later units, not for D1. Apple's own aside: *"Don't use
`significantAppChangeApprovalRequired`. Instead, use both `isEligibleForAgeFeatures`
and `requiredRegulatoryFeatures`."* And `requiredRegulatoryFeatures` is **26.4+**,
above our 26.2 floor, so it would need availability gating.

**The one genuine push signal in this area is `RESCIND_CONSENT` via App Store
Server Notifications** — parental consent withdrawal, **not** age change. Out of
scope here, and Q3 declined the parental-controls surface it belongs to.

### E7 — Is periodic app-driven polling recommended, merely possible, or contrary to the framework? **SUPPORTED AND ANTICIPATED — BUT PULL-ONLY AND FROM UI CONTEXT.**

Apple does not publish a cadence and does not describe a polling schedule, so
"recommended" overstates it. But E1 is explicit that the API "will be called
often" and that apps "won't need to worry" about over-prompting — so frequent
calling is **designed for, not tolerated**. Combined with E2's absence of any push
signal, **pull is the only mechanism Apple provides, and it is a supported one.**

**The real constraint is E3, not frequency:** every call needs a presentation
context, so refresh must happen at a UI-reachable moment, never from a background
task.

### E8 — QUARANTINED: our own device observations, which are NOT used above

`AgeBandRecoveryTrigger.swift` records that on 2026-09-08 a recovery attempt from
**App scope** read but never wrote and **"no system sheet appeared"**. **That is
the FAILURE case** — the absence of a presentation context — and it is **evidence
that the call failed, NOT evidence that repeat calls are silent.** It must never
be cited for the latter.

`AgeBandRecoveryCoordinator.swift` asserts that "Apple caches its answer and
re-prompts only on the declaration anniversary, so the usual case presents no UI
at all." **§E2 and §E4 now confirm the caching and anniversary halves from Apple's
own sources** — so the comment is substantially correct, and was previously
unsourced. The residual: it holds under *Always Share*, and under *Ask First* the
anniversary request **can** prompt. **Not a defect; a precision to carry into
§F.**

**The CP-3 Sandbox fixture is used for NOTHING in this section.**

---

## F. D1 RECOMMENDATION — THE LEAST INTRUSIVE SUPPORTED RE-DERIVATION

**A sound mechanism EXISTS. Q1 does NOT need to come back for reconsideration.**
It is pull-based rather than event-driven, which is a constraint on the design,
not an obstacle to it.

### F1 — The architecture, in one sentence

**Extend the existing View-scoped `AgeBandRecoveryTrigger` from "establish if
absent" to "establish if absent, else refresh if our own throttle says it is
due", write only on a successful band outcome, and change nothing on the
server.**

### F2 — Why this is the least intrusive option

- **No new mechanism and no new prompt surface.** `AgeBandRecoveryTrigger`
  already runs at launch and on every foreground, already holds a View-scoped
  `requestAgeRange` action (E3's hard requirement), and already routes through
  the single `DeclaredAgeRangeService.outcome(for:)` mapping. Adding a second
  age-range mechanism is exactly what that file says it must not do.
- **No server schema change and no production DDL.** The write path
  (`account_privacy_upsert_v1`) already updates `age_band` on conflict and stamps
  `band_updated_at` only on a real change.
- **No new prompts in the ordinary case**, because Apple caches (E1/E4) and
  explicitly designs for frequent calls.

### F3 — Bidirectionality needs ZERO new server work, and this was verified against the deployed predicates

The deployed override is
`enabled AND NOT (age_band='band_13_17' AND set_under_band='band_18_plus')`.
Walking all four transitions against it:

| transition | preference set as | effect |
|---|---|---|
| adult → 13-17 | adult | override matches → **withheld**. Correct. |
| 13-17 → adult | adult | `age_band` no longer `band_13_17` → **override evaporates, preference effective again**. Correct. |
| 13-17 → adult | teen | override never applied → **stays as set**. Correct. |
| adult → 13-17 → adult | adult | withheld, then **restored** — `set_under_band` was never rewritten | 

**So the upward direction releases the overrides automatically, and the
preference survives the round trip.** `*_set_under_band` is what makes this
computable without a second copy, and **nothing destructively rewrites a
preference** — the Q1 constraint is already structurally satisfied.

### F4 — THE ONE GENUINELY DANGEROUS PART: the refusal asymmetry

**Establishment and refresh must map `.ineligible` / `.unavailable` DIFFERENTLY,
and reusing the establishment mapping would be a serious defect.**

- **At establishment:** `.ineligible` and `.unavailable` refuse Connected. Correct
  and unchanged.
- **At refresh:** `.ineligible` and `.unavailable` **must be no-ops**. An
  established band is never erased or downgraded because Apple was momentarily
  unavailable, the person declined, or a region changed the gates.

**There is also a clean argument that a refresh `.ineligible` can never be
genuine: age only increases.** A member established at 13+ cannot later be under
13. So `.ineligible` at refresh is always a transient failure, a decline, or a
regional gate difference — **never real ageing** — which makes "no-op" not merely
safe but correct.

**Write only on `.band(...)`.** Assert this, and assert it against the *refresh*
path specifically; a unit test that only exercises establishment will pass while
the refresh path downgrades people.

### F5 — Why a downward change is worth honouring at all

Since age only increases, **adult → 13-17 is never real ageing — it is the
correction of an earlier over-permissive read**: a self-declared adult later
corrected by a guardian or a confirmed method, or a regional gate change. That is
precisely the case Q1's protective direction exists for, and it is why
bidirectionality is worth the work rather than being theoretical.

### F6 — Cadence: throttle on OUR observation, never model Apple's clock

Per E5 the anniversary is unknowable. **Do not try to compute "due".** Use a
coarse throttle — attempt at most once per N days, plus the existing in-memory
single-flight and cooldown. **Recommend a client-side throttle** (`UserDefaults`)
rather than a new `band_checked_at` column: it needs no production DDL, and a
reinstall merely causes one extra call, which E1 says is fine. A rate limit is
not authority over server state, so this does not offend the CP-3 rule that the
client must not be authoritative.

**N is a product choice, not a technical one, and it is still open.** Anything
from weekly to quarterly satisfies the constraints; the anniversary means a change
surfaces at most once a year anyway, so a short N buys little. **Record the chosen
N in this register and in `docs/phase-5-scope.md` (D5) so the DPIA and the shipped
behaviour cannot drift.**

### F7 — What NOT to do

- **Do not use `isEligibleForAgeFeatures` as a change signal.** It answers "is
  this person in a region requiring age assurance", not "has the band changed".
- **Do not reach for `significantChange`** — E6, wrong direction.
- **Do not refresh from a background task or App scope** — E3, and it is the exact
  defect CP-3 already found and fixed.
- **Do not persist the range, the bounds, or `ageRangeDeclaration`.**
- **Do not hard-code "declaration anniversary" as the cadence.** It is Apple's
  internal cache policy, not a date we know.

### F8 — Residual, stated rather than glossed

Under *Ask First*, an anniversary-crossing refresh **can** present a prompt. This
is Apple's own UX, is bounded to roughly once a year by the anniversary rule, and
cannot be avoided by any app that refreshes at all. **The alternative — never
refreshing — is what Q1 decided against.**

---

## G. THE MINIMAL D1 STATE MACHINE — PROPOSED 2026-09-08, NOT IMPLEMENTED

**Accepted in principle: View-scoped repeated `requestAgeRange`, coarse
per-identity local throttle, no server schema change, band updates only from
successful range results. Cadence 30 days.** This section refines the
refresh-result policy and the throttle semantics, and proposes the under-13
mechanism. **One item needs review before coding — §G6.**

### G1 — Refresh-result policy. `.ineligible` AND `.unavailable` ARE NOT COLLAPSED

**The existing enum already separates them and needs no change.**
`DeclaredAgeRangeOutcome` distinguishes `.ineligible` ("Apple told us, and the
answer is below our minimum") from `.unavailable` ("we were not told" — decline,
unknown response, or error). Establishment collapses them **in effect** because
both refuse Connected; **refresh must not.**

For an identity that ALREADY has a band:

| refresh result | band write | throttle stamp | Connected access |
|---|---|---|---|
| `.band(b)` — valid 13-17 or 18+ | **upsert `b`** — idempotent when unchanged | **STAMP** | unchanged by this term |
| `.unavailable` — declined, unknown, error | **none** | **NO STAMP** | **unchanged — band retained** |
| `.ineligible` — genuine under-13 bounds | **none** | **NO STAMP** | **WITHHELD — §G3** |

**`.unavailable` never erases or downgrades an established band.** Apple being
temporarily unavailable, or a person declining, is not evidence about age.

**Idempotency is a property of the deployed writer, verified not assumed:**
`on conflict` sets `age_band = excluded.age_band` and preserves `band_updated_at`
when the band is unchanged, and **`account_privacy` carries no triggers at all**,
so a repeat upsert of the same band changes no observable value.

### G2 — Why `.ineligible` must NOT be silently ignored, contradicting an earlier argument of mine

**§F4 argued a refresh `.ineligible` can never be genuine because age only
increases. THAT ARGUMENT IS WITHDRAWN — it is unsound, and Q5 is why.** The band
is an assertion about **the Apple Account signed in to iCloud on the device**, not
about the Études identity. **That Apple Account can change.** So an under-13
result is a real, reachable state and must be handled, not reasoned away.

**But it is AMBIGUOUS, and the ambiguity decides the design.** An under-13 refresh
means either *this member is a child* or *the device's Apple Account is now a
child's*. Études cannot tell which. **So it must fail closed for ACCESS while
refusing to record an age claim it cannot justify** — recording "this member is
under 13" on that evidence would be manufacturing age state.

### G3 — The under-13 mechanism: ONE non-persisted flag and ONE guard term

**The smallest mechanism that satisfies the constraints, with no persisted state
and no schema change.**

`ProductionAppModeActivation.resolve` is today a three-term AND. Add a fourth,
driven by a non-persisted `@Published` flag on `AuthManager` — the same shape as
the existing `connectedSetupIncomplete`, which already models "identity exists but
Connected setup is incomplete" without persistence:

```
guard BackendConfig.isConfigured else { return .solo }
guard !auth.ageEligibilityWithheld else { return .solo }   // NEW
guard isEntitled else { return .solo }
guard auth.hasConnectedIdentity else { return .solo }
return .connected
```

**It is NOT conflated with subscription lapse, on three counts.** The flag is a
*separate, directly inspectable* value from `connectedMembershipStore.isEntitled`,
so copy and support can distinguish them. It is placed **before** the entitlement
term, so when both hold the age reason is the operative one. And it must **never**
route to purchase copy — an age-withheld member must not be invited to subscribe.

**Name it for the access decision, not the age.** `ageEligibilityWithheld`, never
`isUnder13` — the flag records what Études *did*, which is all it can justify.

**Nothing is deleted and nothing is manufactured.** The identity, the membership
row, posts, follows, the directory row, the local journal and the established band
all survive untouched. Falling to Solo is the existing, settled withdrawal
semantics.

**C-35 IS NOT RE-CREATED, VERIFIED RATHER THAN ASSUMED.** Account deletion is
gated on `auth.hasConnectedIdentity` (`ProfileView:1828`, and the button label at
`:940`), **not** on `AppMode`, precisely because this trap has been sprung twice.
An age-withheld member therefore keeps the full "Delete Account & All Études Data"
route without re-subscribing and without regaining Connected.

**Refresh must NOT be gated on `AppMode`.** Gating it would make the withheld
state permanent — the member could never be re-evaluated back to Connected. This
is exactly the `C5f-12` lesson, and it must be asserted the same way.

### G4 — Throttle semantics, precisely

**What stamps.** Only a **conclusive** refresh — a `.band(...)` result, changed or
unchanged. That is the only outcome meaning "we now hold current information".

**What does not stamp.** `.unavailable`, `.declinedSharing`, unknown responses,
thrown errors, **and `.ineligible`**. All leave the previous stamp intact so the
next eligible opportunity retries. Hammering is prevented by the **existing**
in-memory single-flight and 60-second cooldown, not by a new mechanism.

**`.ineligible` deliberately does not stamp**, so a withheld member converges back
within one foreground once the Apple Account situation changes, rather than
waiting up to 30 days. Apple's own cache makes the repeated call cheap and silent.

**Reinstall / device change.** The stamp lives in `UserDefaults`, keyed per Études
identity, so it is per-install. Reinstall or a new device loses it and performs one
extra refresh on first launch. **That is a feature, not a cost:** a new device
re-derives promptly, which is the correct direction given Q5's device-bound
concern. Per-identity keying stops one identity inheriting another's throttle on a
shared device. **It must be cleared by account deletion and Erase All** — it is an
operational timestamp, not user content, and it contains no age data.

**Multiple devices for one identity: DO NOTHING.** No distributed coordination, no
shared cursor, no server column. Each device throttles independently and may call
Apple within 30 days of its *own* last call. Apple's cache is account-wide and
**synced across devices** (§E4), so the extra calls are cheap and return the same
value, and a duplicate write is value-idempotent (§G1). **Building coordination
here would add server state and complexity for no product benefit.**

### G5 — Reclassification stays prospective

Unchanged from §F3 and re-stated because it is the point of the unit: **adult →
teen** makes the child discovery/contact overrides effective; **teen → adult**
makes them evaporate and the preserved underlying preferences effective again;
**posts and approved follows are untouched** — measured in §1, only three database
objects consult `account_privacy`, and none of them governs content or
relationships. **No preference is ever destructively rewritten.**

### G6 — THE ONE ITEM FOR REVIEW BEFORE CODING

**An age-withheld member remains DISCOVERABLE server-side.** The flag is
client-side, so `account_privacy.age_band` still reads `band_18_plus` and
`search_account_directory` still returns them. Client access is withdrawn; server
visibility is not.

**Closing that would require persisting an age-derived state** — a third band
value or an `age_withheld_at` column — which is a schema change, changes CP-1's
`NOT NULL` domain and the branchless default expression, and **records a claim
about a minor that §G2 says we cannot justify.**

**RECOMMENDATION: accept the residual and do not persist.** The ambiguity is real,
the access control fails closed, and nothing is destroyed. **A tempting middle
path must be rejected explicitly:** calling the existing
`account_privacy_set_lookup_v1(false)` would need no schema change — but it
**destructively rewrites the member's own preference**, which Q1 forbids outright.
**Do not do it.**

**If the account holder wants server-side effect, that is a new persisted state
and returns for review as its own decision.**

### G7 — Scope of the change, if approved

One `@Published` flag, one guard term, one throttle key, and the refresh branch in
the existing `AgeBandRecoveryCoordinator` / `AgeBandRecoveryTrigger`. **No server
schema change, no new RPC, no new UI surface, no new prompt surface.** The
assertions that matter: refresh is not gated on `AppMode`; `.unavailable` and
`.ineligible` never write a band; only `.band(...)` stamps; and deletion remains
gated on identity.

---

## H. D1 DELTA AND TEST MATRIX — PROPOSED 2026-09-08, NOT IMPLEMENTED

**§G6's client-only residual is REJECTED by the account holder and is superseded
here.** Withholding becomes **server-persisted effective state**. Three required
changes are worked below, followed by the complete delta and the test matrix.

### H1 — Can an existing field carry this? **NO. Checked, not assumed.**

`account_privacy` has nine columns. Every candidate fails:

| candidate | why it cannot carry it |
|---|---|
| `age_band` | needs a third value — **excluded by decision**, and it would change CP-1's domain, the branchless default expression and both override predicates |
| `lookup_enabled` / `follow_requests_enabled` | **destructive preference rewrite — forbidden by Q1** |
| `lookup_set_under_band` / `follow_requests_set_under_band` | hold a band value; a sentinel would corrupt the override predicate that reads them |
| `band_updated_at` / `*_changed_at` | timestamps; cannot encode a two-valued safety state |

**A new column is required.** Proposed:

```sql
alter table public.account_privacy
  add column age_eligibility_withheld boolean not null default false;
```

**`NOT NULL DEFAULT false` is deliberate.** It is strictly two-valued, so it can
never introduce the NULL-resolves-permissive hazard CP-2-R1 was filed for, and the
default applies to the existing row with no backfill. **No timestamp column is
added** — minimisation; `band_updated_at` already records band movement, and when
withholding was set is not needed for any decision.

**WHAT THE COLUMN MEANS, and this wording is load-bearing.** It does **not** mean
"this Études identity is under 13". It means **the latest conclusive Apple result
does not currently establish Connected eligibility.** Q5's limitation stays
explicit: the result describes the Apple Account signed in to iCloud on the
device, which is not bound or verified against the Études identity.

### H2 — Predicate delta: TWO functions, and the consumers need no edit

**Verified by reading the deployed definitions:** `search_account_directory` calls
`account_privacy_discoverable(ad.user_id)`, and `follow_requests_open` calls
`account_privacy_requests_open(target_user_id)`. **Neither inlines the rule**, so
changing the two helpers propagates to both consumers with zero edits to them —
the payoff of CP-2's helper split.

Each helper gains one conjunct inside the existing sub-select:

```sql
select p.lookup_enabled
   and not p.age_eligibility_withheld            -- NEW
   and not (p.age_band = 'band_13_17'
            and p.lookup_set_under_band = 'band_18_plus')
```

**It inherits the right properties for free.** The `coalesce(..., false)` wrapper
is untouched, so a missing row still resolves CLOSED. And the discovery conjunct
in `search_account_directory` is deliberately **not** wrapped in
`enforcement_active()`, so **the kill switch cannot relax withholding** — the
existing comment already states the rule this change relies on.

### H3 — Write path: one line changed, one tiny RPC added

**`account_privacy_upsert_v1` — one line in the `on conflict` clause:**

```sql
on conflict (user_id) do update
   set age_band = excluded.age_band,
       age_eligibility_withheld = false,          -- NEW: a valid band clears it
       band_updated_at = case when ap.age_band = excluded.age_band
                              then ap.band_updated_at else now() end;
```

**`account_privacy_withhold_age_eligibility_v1()` — new, parameterless,
UPDATE-only:**

```sql
update public.account_privacy ap
   set age_eligibility_withheld = true
 where ap.user_id = auth.uid();
if not found then raise exception 'no age band declared' using errcode='23514'; end if;
```

**The asymmetry is the safety property.** A client can SET withholding but can
**never clear it** — clearing happens only as a side effect of presenting a
conclusive valid band. So no client call can restore eligibility without a real
Apple result. **UPDATE-only** means it can never create a row, mirroring U4's
canonical-writer discipline. It takes no parameter, so there is no value for a
caller to get wrong.

### H4 — `account_privacy_self_v1` gains a column, and this needs care

It must return the flag so the client can drive activation and UX. **`CREATE OR
REPLACE FUNCTION` CANNOT change a return type**, so this is a **`DROP FUNCTION`
then `CREATE`**, with the `GRANT EXECUTE` re-applied afterwards — a real
operational step, and exactly the kind of detail that is discovered at the wrong
moment if it is not written down first.

**B-23 FIDELITY: the change must land in `supabase/migrations/` as well as being
applied to production.** P4-U7 already recorded that U5's server half was applied
from `supabase/sql/` and never added to `migrations/`, so every local rehearsal
afterwards rehearsed the wrong object — a six-column RPC against production's
seven. **This change is the same shape and must not repeat it.**

### H5 — Client delta

- **`SelfState`** gains `ageEligibilityWithheld: Bool`, decoded from the new
  column.
- **`AccountPrivacyService`** gains `withholdAgeEligibility(auth:reason:)`, the
  wrapper for the new RPC.
- **`ProductionAppModeActivation.resolve`** gains one guard term, before the
  entitlement term:
  `guard !auth.ageEligibilityWithheld else { return .solo }`.
- **`AuthManager.ageEligibilityWithheld`** is **derived from
  `accountPrivacyState`, not a separate stored flag** — one source of truth, and
  it survives process death because the server holds it. No local persistence of
  an age-derived fact.

**`accountPrivacyState == nil` (unknown) resolves NOT withheld for the MODE
decision.** This is deliberate and is invariant 3 applied: mode is a **reversible
UI decision** and may rest on client-side evidence, whereas the irreversible
half — who is discoverable and who may be contacted — is now **server-enforced by
H2 regardless of what any client believes**. Resolving unknown as withheld would
drop every offline launch to Solo, which is a large regression for no safety gain.

**Residual, stated rather than hidden:** on an offline relaunch a withheld member
may see Connected UI until hydration completes. Bounded, reversible, and the
server refuses discovery and contact throughout. **Caching the flag locally to
close it is explicitly rejected** — it would persist an age-derived fact on the
device for a cosmetic gain.

### H6 — UX delta, after inspecting the actual routing

**INSPECTED, AND THE NAIVE FIX WOULD HAVE BEEN A DEFECT.** `connectedPromoSection`
is shown whenever `!canShowConnectedAccountManagement`, so a withheld member in
Solo **would be offered "Explore Connected"** — a purchase funnel that cannot
resolve age eligibility. That is the conflation to avoid.

**But `eraseAllEtudesDataButton` renders INSIDE that same section
(`ProfileView:879`).** Hiding the section would remove the member's
account-deletion route — **a third route to C-35**, arriving through the UI rather
than through a guard.

**So the minimal change is surgical: within `connectedPromoSection`, replace only
the "Explore Connected" button when withheld, and leave `eraseAllEtudesDataButton`
exactly where it is.**

**Reuse existing neutral wording — no new child-safety settings surface, no new
screen.** The replacement row carries the string already in the source at
`ProfileView:395`: **"Études Connected is for ages 13 and over."** It states the
product rule and asserts nothing about the member.

**The replaced row IS the explicit retry path**, so no extra control is invented:
it stays a `Button` whose action performs an immediate refresh bypassing the
automatic throttle. Same row, different label and action.

### H7 — Throttle: exactly two local timestamps

**Persisted-server withholding removes the earlier need for fast retry**, because
the state now survives relaunch on its own. So the coarse intervals are safe.

| key | stamped when | gates |
|---|---|---|
| `p5g.ageBand.refreshedAt.<uid>` | **only** on a conclusive `.band(...)` | the **30-day** product cadence |
| `p5g.ageBand.attemptedAt.<uid>` | on `.unavailable`, `.declinedSharing`, unknown, error, **and `.ineligible`** | the **24-hour** coarse retry |

An automatic refresh runs only when **both** are due. **No server refusal counter,
no history, no DOB, no provenance** — two local timestamps and nothing else.

**Explicit user-initiated retry (H6's row) bypasses both**, subject only to the
existing in-memory single-flight, and stamps whichever key its outcome implies.

**Deletion and reset:** both keys are per-identity and must be cleared by
`LocalFactoryReset` and on sign-out of that identity. They are operational
timestamps containing no age data. **They must be added to the erase sweep
deliberately** — this is the C-28/C-48 class of question, and a key that outlives
an erase is exactly what those findings were about.

**Reinstall / new device:** both keys are absent, so one refresh happens at first
launch. Harmless (§E1), and correct — a new device re-derives promptly, which is
the right direction under Q5. Hydration alone already restores the *withheld
state* from the server, independently of the timestamps.

**Multiple devices: still no coordination, and now genuinely unnecessary.** The
withheld state is server-side, so every device agrees on the state; only refresh
*timing* differs per device. Apple's cache is account-wide and synced, and a
duplicate write is value-idempotent.

### H8 — Rollback

Ordered, and it restores the pre-change world exactly:

1. restore the two helper bodies (`CREATE OR REPLACE`, no signature change);
2. restore `account_privacy_upsert_v1` (`CREATE OR REPLACE`, no signature change);
3. `DROP FUNCTION account_privacy_withhold_age_eligibility_v1()`;
4. `DROP FUNCTION account_privacy_self_v1()` and re-create the six-column form,
   **re-applying its GRANT**;
5. optionally `ALTER TABLE ... DROP COLUMN age_eligibility_withheld` — the column
   is inert once nothing reads it, so dropping it is cleanup rather than rollback.

**Step 4 is the one with a client dependency:** a shipped client expecting seven
columns must not meet a six-column function. **Roll the server back only with the
matching client, or leave `self_v1` at seven columns and roll back 1-3 only** —
which is a complete behavioural rollback on its own, since the flag then affects
nothing.

### H9 — TEST MATRIX

**Server — predicates (local stack, then production structural):**

| # | case | expect |
|---|---|---|
| S1 | `discoverable`, withheld **false**, adult, lookup on | **true** |
| S2 | `discoverable`, withheld **true**, adult, lookup on | **false** |
| S3 | `requests_open`, withheld **true**, adult, requests on | **false** |
| S4 | missing `account_privacy` row | **false** (CP-2-R1 unchanged) |
| S5 | withheld **true**, `enforcement_enabled = false` | **still false** — the kill switch must not relax it |
| S6 | `search_account_directory` for a withheld subject | **zero rows**, via the helper, with **no edit to the consumer** |
| S7 | teen override still applies independently of withholding | unchanged |

**Server — writers:**

| # | case | expect |
|---|---|---|
| W1 | `upsert_v1` with a valid band on a withheld row | band written, **withheld cleared** |
| W2 | `upsert_v1` with the **same** band | **idempotent** — `band_updated_at` unmoved, withheld cleared |
| W3 | `withhold_v1` on an existing row | withheld **true**, band and **all four preference columns byte-identical** |
| W4 | `withhold_v1` with **no** row | raises `23514`, **creates nothing** |
| W5 | `withhold_v1` twice | idempotent |
| W6 | no client role holds direct DML on the column | grants unchanged; RLS still on, zero policies |
| W7 | `self_v1` returns seven columns including the flag | and its GRANT survives the DROP/CREATE |

**Client — refresh state machine:**

| # | refresh outcome, band established | band write | withhold call | `refreshedAt` | `attemptedAt` |
|---|---|---|---|---|---|
| C1 | `.band` unchanged | upsert | — | **stamp** | — |
| C2 | `.band` changed | upsert | — | **stamp** | — |
| C3 | `.unavailable` | **none** | **none** | — | **stamp** |
| C4 | `.declinedSharing` | **none** | **none** | — | **stamp** |
| C5 | thrown error | **none** | **none** | — | **stamp** |
| C6 | `.ineligible` | **none** | **withhold** | — | **stamp** |

**Client — activation, UX and the traps:**

| # | case | expect |
|---|---|---|
| A1 | withheld true | mode **`.solo`** |
| A2 | withheld true **and** entitled | mode `.solo`, **and never purchase copy** |
| A3 | withheld true | **"Delete Account & All Études Data" still present and functional** — C-35 |
| A4 | withheld true | `eraseAllEtudesDataButton` **still rendered** in the promo section |
| A5 | withheld true | "Explore Connected" **replaced** by the neutral row |
| A6 | withheld true | refresh **still runs** — **not gated on `AppMode`**, or withholding is permanent (`C5f-12`) |
| A7 | `accountPrivacyState == nil` | **not** withheld for the mode decision; offline launch unaffected |
| A8 | explicit retry row | bypasses **both** throttles |
| A9 | `LocalFactoryReset` | **both** keys cleared |

**Reclassification (both directions, prospective):**

| # | case | expect |
|---|---|---|
| R1 | adult → 13-17 | adult-set preferences **withheld in effect**, values **unrewritten** |
| R2 | 13-17 → adult | overrides **evaporate**, preserved preferences **effective again** |
| R3 | adult → 13-17 → adult | **round-trips**; `set_under_band` never rewritten |
| R4 | any transition | **posts and approved follows untouched** |
| R5 | withheld → valid band | **withholding cleared**, preferences intact |

**Non-vacuity:** every server assertion must be run against the **pre-change**
functions and observed to fail, as U2c and P4-U2a did. An assertion that passes
before the change tests nothing.

---

## I. NECESSITY REVIEW — IS PERIODIC RE-DERIVATION NEEDED AT ALL? 2026-09-08

**Conducted from sources and the corrected age asymmetry, NOT from the
implementation.** `c5440d8` exists and works; **that is not evidence for shipping
it**, and it is deliberately given no weight below.

### I0 — THE ASYMMETRY, AND IT REFRAMES EVERYTHING

**Age moves in one direction.** Under-13 never establishes Connected; 13-17 may
become 18+; 18+ stays 18+. **So the only ORDINARY reclassification is
13-17 → 18+**, and the cost of observing it late is that a member keeps **more
restrictive** child protections for longer. **It does not expose a child to adult
defaults.**

**This inverts the case for polling.** The failure mode of never re-deriving is
**over-protection**, which is a PRODUCT defect, not a child-safety defect.

**18+ → child is not ageing at all.** It is an Apple-Account or
identity-assurance anomaly (Q5). §G2 was right that it is *reachable*; it must
not be the *primary justification* for permanent architecture unless a concrete
authority says Études must treat a changed Apple Account, or corrected Apple
data, as an age downgrade of an existing Études identity. **No such authority was
found — see I2.**

### I1 — What Apple REQUIRES after initial establishment

**Nothing about re-checking.** Apple's *Declared Age Range* reference, its
*Requesting people share their age range* article, and its dedicated
**Age assurance developer Q&A** are silent on re-checking or re-requesting after
an age range has been obtained. **This is absence of a stated requirement, not
proof that no obligation exists** — which is exactly why I4 exists.

**What Apple DOES require is push-shaped, not poll-shaped:**

- *"Developers must configure their apps to receive App Store server
  notifications when a parent or guardian withdraws consent"* — `RESCIND_CONSENT`.
- *"When a parent or guardian revokes consent for their child to access an app,
  **Apple will prevent the app from launching**."* — **the platform enforces
  access; the developer's duty is to receive and respond server-side.**
- Significant app changes require consent via PermissionKit; **age-rating changes
  are automatically significant**.

**And Apple twice refers the obligation question to counsel:** *"developers are
responsible for their own age restrictions… For questions about your compliance
obligations, consult your legal counsel."*

### I2 — What LAW requires. **NOT CONCLUSIVELY ANSWERABLE HERE**

The driver is the app-store age-assurance wave — **Texas SB2420, effective
2026-01-01**, with Utah, Louisiana and Brazil following; the categories are
under-13 / 13-15 / 16-17 / over-18. Apple's own material states **no periodic
re-check requirement**, and no source consulted imposes one.

**But whether Études is in scope, and what "reasonable" ongoing assurance means
for it, is a legal determination I am not in a position to make** — and Apple
explicitly declines to make it for us. **This is a LEGAL question (C4 below).**

### I3 — What Apple merely SUPPORTS

Repeated calls are anticipated and cheap: *"the API will be called often… apps
won't need to worry that calling the API will prompt the user too many times."*

**"Apple supports frequent calls" DOES NOT ENTAIL "Études must poll every 30
days."** That inference is invalid, and it is the one this review was asked to
refuse. Apple's model is **pull at the point of need**, plus **push for consent
events**.

### I4 — What is therefore OUR OWN CHOICE

Everything in CONTINUOUS. **No authority requires it.** It is defence-in-depth
against an anomaly class (I0), bought with permanent schema, predicate, RPC,
client and UX surface.

---

## I5 — THE COMPARISON

| | **MINIMAL** | **CONTINUOUS** |
|---|---|---|
| **Compliance risk** | No identified requirement is unmet. Residual: an unquantified "ongoing assurance" duty, which is **I2/LEGAL**, and which polling would not clearly discharge either | Discharges no cited requirement. **Buys no compliance certainty**, because the uncertainty is legal, not technical |
| **Child safety** | Under-13 refused at establishment; 13-17 protections server-enforced; **Apple blocks launch on consent revocation**. The un-covered case is the Apple-Account anomaly | Adds cover for the anomaly **only when a device happens to refresh**. A child using an adult's Études identity on a device where the adult's Apple Account is still signed in is **not** caught either way — so the protection is partial and somewhat arbitrary |
| **Data minimisation** | Best. No new column, no new persisted safety state, no local timestamps | Worse: a persisted eligibility-withheld flag, two local timestamps per identity, and a new client-callable RPC |
| **Product / UX** | **Real defect: a member who joined at 13-17 stays restricted after turning 18, indefinitely.** Discovery off, inbound requests closed, with no route out | Fixes that — but only after up to 30 days, and introduces a withheld state, a replaced purchase affordance, and a Check Again recovery path that must never reach purchase |
| **Cost** | Zero server delta. Zero new state | Column + 2 predicates + 1 RPC + `self_v1` DROP/CREATE with grant re-apply, client state machine, throttles, AppMode term, UX branch, erase-sweep change — **all permanently maintained** |
| **Authority making it necessary** | — | **NONE FOUND** |

### I6 — THE OPTION THAT DOMINATES BOTH, and it is nearly free

MINIMAL's only real cost is the **trapped 13-17 member**. That does **not** need
polling to fix:

**MINIMAL + MEMBER-INITIATED RE-DERIVATION.** Re-request Apple's range when the
member asks — at the natural moment, such as opening the discovery setting.
**Server delta: ZERO.** `account_privacy_upsert_v1` already updates the band on
conflict, and the read-time override already evaporates when the band leaves
`band_13_17`, restoring the preserved preference automatically. **Verified
against the deployed predicates, and it needs no withholding state**, because
teen → adult is a widening, not a restriction.

**It fixes the ordinary transition (I0), at the moment the member actually cares,
with no polling, no persisted safety state and no schema change.**

### I7 — RESCIND_CONSENT: a real obligation, and it is NOT polling

**This is the substantive finding of the review.** Apple states a developer duty
to receive consent-withdrawal notifications, and the platform blocks app launch
itself. It is **push-based** and arrives on the App Store Server Notifications
endpoint Études already operates.

**Études would currently see nothing and do nothing:** the **production**
notification URL is still unset, and `appstore_notifications_v1` **does not map
`RESCIND_CONSENT` at all** — verified by sweeping the function sources.

**So the genuinely evidence-backed gap is here, not in periodic re-derivation.**
It is also a better use of effort by every measure in I5. **Whether it binds
Études depends on scope, which is I2/LEGAL.**

---

## I8 — RECOMMENDATION: **MINIMAL** (adopting I6), with one narrow question to LEGAL

**Strongest evidence FOR MINIMAL:** no Apple or legal source found imposes
periodic re-derivation; the only ordinary reclassification fails
**over-protectively**; Apple enforces the severe case (consent revocation) at the
platform level; and it is the most data-minimising option, which is the correct
default for a children's-privacy feature.

**Strongest evidence AGAINST MINIMAL:** the absence of a stated requirement is not
a stated absence of requirement (I1), and pure MINIMAL leaves a member restricted
after turning 18 — which **I6 fixes at zero server cost**.

**Strongest evidence FOR CONTINUOUS:** it is the only option covering the
Apple-Account anomaly without member action.

**Strongest evidence AGAINST CONTINUOUS:** **no authority requires it**; it
addresses the direction age does not move; its protection is partial and arbitrary
even for the anomaly; and it is the least data-minimising option — permanent
safety state and local timestamps added to a children's-privacy surface **to
defend a case nobody has asked us to defend**.

**DO NOT SHIP `c5440d8`'s D1 half.** Retain **Finding A** — the
production-transcribed CP-1/CP-2 fidelity migration — which stands on its own and
is unrelated to this decision.

**TO LEGAL, added as C4:** is Études in scope of the app-store age-assurance
laws; if so, does any of them impose an ONGOING age-assurance duty beyond
establishment; and does `RESCIND_CONSENT` handling bind Études? **A "yes" to the
third would make I7 the next unit — still not periodic polling.**

---

## J. MEMBER-INITIATED RECHECK — SCOPE ONLY, NOT BUILT. 2026-09-08

**MINIMAL is adopted. CONTINUOUS is reverted (`cbaeeed`).** This replaces the
trapped-teen problem — the only ordinary reclassification, 13-17 → 18+ — with a
deliberate member action. **Scoped, deliberately not overbuilt.**

### J1 — What it is

One action, offered **only** to an identity whose stored band is `band_13_17`,
letting the member ask Apple for their current age range again. It re-uses the
existing View-scoped `requestAgeRange` and the existing
`DeclaredAgeRangeService.outcome(for:)` mapping. **No second age-range mechanism.**

### J2 — Semantics

| result | behaviour |
|---|---|
| **18+** | `account_privacy_upsert_v1` updates the band. The child override stops matching, so the **preserved adult-set preferences become effective automatically** — no preference is written, nothing is un-done by hand |
| **still 13-17** | idempotent. `on conflict` writes the same band, `band_updated_at` does not move, no behavioural change |
| **unavailable / declined / error** | **retain the teen band and every protection.** Apple being unreachable is not evidence about age |
| **Under-13** | **DO NOT INVENT BEHAVIOUR. Flagged to C4.** On a voluntary recheck by an established 13-17 member this is an identity/account anomaly, not ageing, and the right response is a legal/scope question rather than an engineering guess |

### J3 — Cost: ZERO server delta

**Verified against the deployed objects, not assumed.** `upsert_v1` already
updates `age_band` on conflict; the read-time override is already
`not (age_band='band_13_17' and set_under_band='band_18_plus')`, so it evaporates
the moment the band leaves `band_13_17`. **No new column, no new RPC, no
predicate change, no withholding state, no polling, no DOB and no provenance.**

Teen → adult is a **widening**, which is why it needs none of the machinery a
downgrade would.

### J4 — Placement: fold into H-1, do not create a surface

**H-1 is already logged** (`docs/phase-5-ui-housekeeping.md`): move *Default to
Private Posts* and *Let other members find you* out of the ordinary Settings list
into a **"Connected"** section above *Account*. **This action belongs there**, in
that same section, shown only when the band is `band_13_17`.

**That keeps the promise made when MINIMAL was chosen: no new settings surface and
no new child-safety vocabulary.** It also puts the action next to the two
preferences whose effectiveness it restores, which is where a member would look.

**H-1 was scoped as presentation-only with zero behaviour change.** Adding this
action changes that, so **H-1's acceptance score must be re-derived rather than
carried** — the same rule P5-H is already under for the ASC mapping.

### J5 — Explicitly NOT in scope

No automatic refresh on any schedule. No throttle timestamps. No withheld state.
No AppMode term. No change to `search_account_directory`,
`follow_requests_open`, or either helper predicate. **If any of those reappear,
this is no longer MINIMAL.**

---

## K. C4 — `RESCIND_CONSENT`: WHAT IS ESTABLISHED, AND WHAT IS NOT

**Investigated 2026-09-08 from Apple's documentation and this repository.
Applicability is NOT established and is deliberately left to LEGAL.**

### K1 — What it means and when Apple sends it. **ESTABLISHED**

`RESCIND_CONSENT` is a documented **App Store Server Notifications V2**
`notificationType`, read from Apple's own reference:

> *"A notification type that indicates the parent or guardian has withdrawn
> consent for a child's app usage."*

So it arrives on the **same V2 channel** Études already operates an endpoint for —
not a separate API and not a client callback.

### K2 — Is handling it mandatory for Études? **NOT ESTABLISHED — LEGAL**

Apple's requirement is stated **in the context of apps distributed in
jurisdictions with app-store age-assurance laws** — Texas SB2420 from
2026-01-01, with Utah, Louisiana and Brazil following: *"Developers must
configure their apps to receive App Store server notifications when a parent or
guardian withdraws consent."*

**Whether Études is within that scope is a legal and distribution question, not a
technical one**, and Apple explicitly refuses to answer it: *"For questions about
your compliance obligations, consult your legal counsel."*

**THE EXISTENCE OF A NOTIFICATION TYPE IS NOT AN ÉTUDES IMPLEMENTATION
REQUIREMENT**, and this section deliberately stops short of treating it as one.

### K3 — What Apple itself does. **ESTABLISHED**

> *"When a parent or guardian revokes consent for their child to access an app,
> **Apple will prevent the app from launching**."*

**The platform enforces access.** Any Études work would be about *server-side*
state (what remains visible to others), never about blocking the app.

### K4 — What further developer action is required. **PARTIALLY ESTABLISHED**

Apple says to use the notification to "handle consent revocations" and **does not
specify a server-side response**. What Études would do with it — for instance
withdrawing Connected visibility — is **our design decision, not an Apple
instruction**, and it only arises if K2 resolves in scope.

### K5 — The production URL claim, corrected and made precise

**My earlier phrasing conflated two different things, and the question was
fair.**

- **What exists and works:** the Edge Function `appstore_notifications_v1`,
  deployed and verified end to end — Apple's own test notification landed through
  it (U4/B-28). **That is the ingestion endpoint.**
- **What is recorded as unset:** the **App Store Connect** setting — *App
  Information → App Store Server Notifications (V2) → **Production Server URL***,
  as distinct from the **Sandbox Server URL**, which `CLAUDE.md` records as SET to
  that endpoint on 2026-08-20 (S2b).

**I did not measure the ASC setting and cannot: it is not readable from this
repository or from the database.** The claim rests on `CLAUDE.md`'s operational
table, dated 2026-08-16/20 — *"Production notification URL: Unset — Until its
later authorised step"*. **It is a project record, not an observation of mine, and
the account holder should confirm it in ASC before anything is built on it.**

**Why it matters if it is still unset:** Apple's documented rule is that a
Production URL set with no Sandbox URL sends **both** environments to production;
with **Production unset, production notifications are delivered nowhere.** So on
a released build, a `RESCIND_CONSENT` would not reach Études at all.

### K6 — Would our endpoint handle it today? **NO**

Swept the function sources: **`RESCIND_CONSENT` appears nowhere in
`supabase/functions/`.** The ingestion path maps subscription lifecycle types
only.

**One thing deliberately NOT claimed:** whether such a notification would be
recorded as `ignored`/unmapped or rejected structurally. Its payload shape is not
the subscription shape, and **I have not tested it** — asserting a behaviour I
have not observed is exactly what this project keeps filing findings about.

### K7 — Required Études work

**None is established.** *Contingent on K2 resolving in scope*, it would be:
(i) set the Production Server URL in ASC — an account-holder action, adjacent to
**C-31**; (ii) map `RESCIND_CONSENT` in `appstore_notifications_v1`; (iii) decide
the server-side response. **All three are gated on LEGAL and none is authorised.**

**This remains push-based. It is not, and does not become, an argument for
periodic re-derivation.**

---

## 4. WHAT THE DPIA MUST CARRY VERBATIM

**CP-3 closed with two limitations, and the DPIA must reflect the first as
written:**

**TEEN DEFAULTS ARE NOT DEVICE-VERIFIED.** No end-to-end device observation
exists of a real Apple 13-17 range establishing `band_13_17`, and therefore none
of the teen default row or the teen discovery opt-in chain. Blocked by
nondeterministic Apple Sandbox Age Assurance fixture behaviour; three disposable
identities were spent and the teen band was never produced once; closed to
further experimentation. **Teen derivation and defaults are covered by the client
unit suite and the deployed branchless server expression. That is COVERAGE, NOT
HARDWARE VERIFICATION, and must never be restated as hardware verification.**

**A DPIA implying that teen protections are device-verified would misstate the
evidence.**

The second limitation — strong band-before-directory publication ordering, blocked
by U6b/D4 Sandbox enforcement — is a **named carried obligation**. **Do not weaken
enforcement and do not add a test-only carve-out to discharge it.**

---

## 5. OUT OF SCOPE FOR P5-G, AND STAYING OPEN

Phase 4 is **exit-incomplete and is not closed**: condition 2 (U2b/U2s device
verification), condition 6's ASC half, condition 8 ("DEFERRED, NOT WAIVED"), and
C-34's avatar-replacement device verification. **C-31** and **B-34** remain open
Phase-3 obligations. **G7** — first naturally matured production cleanup —
earliest 2026-11-01. **H-1** is logged-only UI housekeeping.

**P5-H must RE-DERIVE the App Store Connect mapping after P5-G, not republish the
Phase 4 one.** "Already entered" is not evidence of "still correct": CP added a
server-side age band, changed defaults, and moved which columns are authoritative.
**Policy first, labels second.**
