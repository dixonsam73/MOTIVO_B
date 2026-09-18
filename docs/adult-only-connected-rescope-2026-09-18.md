# Adult-only Connected — re-scope record

**18 September 2026. PRODUCT DECISION OF RECORD. DOCUMENTATION ONLY. NO
IMPLEMENTATION IS AUTHORISED BY THIS RECORD.**

This is the authoritative record of the pivot from 13+ Connected to adult-only
Connected. It records Samuel's decision and what it supersedes. It makes **no legal
finding**, designs **no mechanism**, and describes **nothing as implemented**. It was
preceded by a read-only audit of the repository at `90ab06e`; that audit was not
written to the repository.

---

## 1. The decision

**Solo** stays generally available, local and account-free, with **no age
restriction imposed by Études**. **This decision does not make the Études app 18+.**

**Connected** becomes an **18+ service only**. Connected account establishment and
Connected access must ultimately require that adulthood has been established through
an **Apple-provided age-assurance mechanism that SD Songs Ltd has determined adequate
for the applicable assurance requirement**.

**Fail closed to Solo.** An under-18, declined, unavailable, unrecognised or
insufficiently assured result makes Connected unavailable. The member stays in Solo,
and their local data is untouched.

**No particular Apple result is adequate yet.** That includes a generic
`AgeRangeDeclaration.confirmed`. **It has not been established that any Apple result
satisfies Ofcom's highly effective age assurance (HEAA) requirement.** That
determination is an open evidential and legal gate (§5), not an engineering
assumption.

**Account deletion must never depend on age eligibility.** An identity refused as
not adult must still be able to delete its account (C-35's principle).

The invariant expressing this is recorded in `CLAUDE.md` as architectural invariant 5.

## 2. The previous model — the 13+ Connected design

From 2026-09-06 to 2026-09-18 the target was **13+ Connected**, with protective
defaults for **13–17**. The children's-privacy workstream (CP-0…CP-5) built it in
Phase 5:

- Apple's `requestAgeRange(ageGates: 13, 18)` is reduced to a server-held band,
  `band_13_17` or `band_18_plus`, in `account_privacy`. No date of birth and no
  provenance are stored. Under 13, a decline or an error stores nothing and refuses
  Connected.
- 13–17 members get these defaults: discovery off, Share default off, and inbound
  follow requests closed (Q2, enforced server-side by B-40, deployed 2026-09-16).
- A directory row cannot be created before a band exists (`tg_directory_requires_band`).
- P5-G (CP-4) was to carry the DPIA and legal confirmations for a 13–17 population.
  P5-H (CP-5) was to publish a privacy policy describing 13–17 defaults.

**These records are accurate as records of that design and are not rewritten.** See
`docs/childrens-privacy-workstream-scope.md`, `docs/phase-5-b-cp1-design-r2.md`,
`docs/cp3-disposition.md`, `docs/phase-5-g-decision-register.md`,
`docs/phase-5-g-legal-packet.md` and `docs/phase-5-g-legal-questions-2026-09-17.md`.

## 3. Why this is a re-scope, not a correction

The 13+ design was not wrong for the product it described. **The product decision
changed.** Completed units stay closed as historical work, even though the
architecture they produced will later be superseded. That covers CP-0 (P5-C), CP-1
(P5-B/P5-D), CP-2 (P5-E), CP-3 (P5-F) and the B-40 deployment. Their evidence and
limitations keep their original wording.

## 4. What changes status

### Superseded as target direction

- 13–17 access to Connected, and every 13–17 protective default as a *product
  requirement*: the Share, discovery and inbound-request defaults.
- The teen inbound-contact replacement proposal (decision register §A2′) and the
  reopened `communicationLimits` dependency (§A3′).
- The teen-only member-initiated recheck (§J), the refusal copy "Études Connected is
  for ages 13 and over", and the DPIA teen-limitation wording (§4 of the register).
- The 13+ framing of every question in the P5-G legal packet and the 2026-09-17
  counsel brief.
- The requirement that the final privacy policy describe distinct 13–17 defaults.
- The teen stages of the invitation work. The invitation documents themselves are
  **not** edited by this record.

### Superseded as direction, but still live in code and production

Superseded direction does **not** mean removed code. The current code and schema
still implement the 13+ design, including B-40 and `tg_directory_requires_band`.
**They stay in force until a reviewed replacement ships.** Nothing is rolled back
by this record.

### Current implemented state

The next four bullets come from the read-only source audit, not from device or
production evidence.

- The in-app join path asks Apple for the age range **before** Sign in with Apple
  and purchase, with gates 13 and 18.
- The returning-member Sign In route and the signed-out gate ask for **no** age
  range before sign-in.
- Client Connected mode depends on entitlement, identity and a configured backend.
  **It has no age term.**
- Server membership and enforcement predicates contain **no age term**. The band
  is written by an `authenticated` RPC that accepts the band value the client sends.

The last recorded production figures are records, not a fresh measurement: 2 adult
privacy rows and 0 teen rows (B-40 deployment, 2026-09-16).

### Remains valid, independent of the age change

- Phase 3's membership, enforcement and cleanup architecture, and B-39 / scope 011.
- All Phase 5 work outside CP.
- The Phase 6 reliability and Lists work recorded in
  `docs/phase-6-checkpoint-2026-09-18.md`.
- **These principles carry forward:**
  - fail closed on declined or unavailable results;
  - data minimisation;
  - describe Apple *sharing* an age range, never Études *asking* for an age;
  - child-safety or eligibility clauses must not be relaxed by the membership kill
    switch;
  - account deletion is independent of entitlement and eligibility.

## 5. Unresolved gates. None is resolved here

1. **Apple result and provenance adequate for HEAA.** Which Apple response, if any,
   SD Songs Ltd determines adequate. Generic `.confirmed` stays a *candidate input*
   to that determination, not an accepted result. Whether minimisation can still
   exclude provenance storage depends on this answer.
2. **Local Apple result vs server-side trust and enforcement.** The Apple result is
   delivered to the app. The repository contains no evidence of an Apple artefact
   the server can verify. What the server may rely on, and where enforcement sits,
   are undecided.
3. **iOS 26.4 vs 26.5.** In the iOS 26.5 SDK installed on the development Mac,
   `.confirmed` requires iOS 26.5, and `ageRangeDeclaration` is optional. The app's
   deployment target is 26.4. The older granular provenance cases are deprecated.
   What a 26.4 device returns in practice is not established.
4. **Returning members and existing identities**, including identities that already
   hold a band derived under the 13+ design, identities with no band, and existing
   sessions.
5. **Changed Apple Account, new device and re-assurance.** The band comes from the
   Apple Account active on the device at request time and is not bound to the Études
   identity. The device age cache is not per identity. When and how adulthood is
   re-established is undecided.
6. **Where eligibility is enforced, relative to membership and payment.** **Settled:
   Connected establishment requires adequate adult assurance, and so does Connected
   access.** A subscription can exist without the in-app age check: a restore,
   another device, a purchase outside the join flow. **Undecided is only the
   implementation and enforcement placement:** whether the purchase screen is
   reachable, the StoreKit purchase itself, membership attestation and establishment,
   client mode activation, server enforcement, and the order of these.
7. **App Store age rating and privacy-policy consequences** (P5-H), including the
   `[AGE]` value and the privacy-label re-derivation.
8. **`RESCIND_CONSENT` and regional app-store age-assurance laws**: whether any
   obligation remains for an adult-only service (formerly register C4 / §K).
9. **Status of the 2026-09-17 counsel brief.** Whether the 2026-09-17 brief was sent is not
   recorded. Any future brief must use this record, not the 13+ packet.

## 6. Placement

This re-scope lives in **Phase 5**, as a re-scope of the open **P5-G** (legal and
evidential determination) and **P5-H** (publication) units, which already own the
children's-privacy workstream. `docs/phase-5-scope.md` records the re-scoped units.
`docs/phase-6-checkpoint-2026-09-18.md` authorises no age work in Phase 6. No new
numbering is introduced.

## 7. Next step

The next task is a human-reviewed counsel brief for adult-only Connected, built on
§5. **No implementation unit is authorised by this record.** Any later unit needs its
own scope, prediction and approval.
