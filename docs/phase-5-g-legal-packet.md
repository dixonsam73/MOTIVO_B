# P5-G / CP-4 — LEGAL REVIEW PACKET

**For deciding HOW to obtain confirmation, and for briefing whoever gives it.
2026-09-09. This is a checklist and a fact base, not a memo and not legal
analysis.**

**Five questions, Q1–Q5, plus one subsidiary yes/no (Q3a).** They are split by
**mediation, not geography**: **A** — duties falling on Études directly, whatever
Apple does; **B** — additional duties mediated through Apple's App Store
framework. Each gives the **current behaviour** (measured, not described from
intent), the **question**, and **exactly what we need confirmed**.

**Two framing rules, both load-bearing:**

1. **Études never asks anyone their age.** Apple presents its own system sheet and
   returns a *range*. Nothing in the product, the policy or this packet may imply
   otherwise.
2. **Do not ask counsel to design.** Every question below is answerable as
   *confirm / correct / insufficient*, against behaviour that already exists.

---

## 0. THE FACT BASE counsel needs first

**The product.** Études is an iPhone journal for musicians. **Solo is entirely
account-free and uploads nothing.** An optional paid tier, **Connected**, adds a
social layer: profile discovery, follows, shared posts and comments.

**Not yet released.** No public release has occurred; there are **no production
customers**. Production today holds **2 identities, 1 directory row, 6 posts,
1 comment, 0 follows** — the account holder's own and one test identity.

**Minimum age for Connected is 13.** Under-13 is refused, **before any server
contact and before an account is created**.

**How age is determined.** **Études requires iOS 26.4 or later** and uses Apple's
**Declared Age Range** framework, called as `requestAgeRange(ageGates: 13, 18)`. Apple returns a **range**, never a
birth date. Études derives exactly **two values**:

| stored | meaning |
|---|---|
| `band_13_17` | Apple's lower bound is ≥ 13 and < 18 |
| `band_18_plus` | Apple's lower bound is ≥ 18 |

**What Études stores about age: those two values and nothing else.** **No date of
birth. No age. No `ageRangeDeclaration` provenance** — Apple can say whether a
range was self-declared, guardian-declared or ID/payment-confirmed, and **Études
deliberately never reads or stores it.**

**What the band controls — exactly three things, verified by sweeping every
database object:** directory **discovery**, **inbound follow requests**, and a
rule that a directory row cannot be created before a band exists. **It controls
nothing about published content or existing relationships.**

**Under-18 defaults (`band_13_17`):** discovery **OFF**, inbound follow requests
**OFF**, sharing a session **defaults OFF**. A 13-17 member **may** turn discovery
on; **inbound follow requests cannot be enabled at all** — the reason is recorded
at **Q2.3**. They may still follow others themselves.

**A protection that withholds effect rather than destroying data:** a preference
set as an adult stops taking effect if the band later reads `band_13_17`, and
takes effect again if it returns to `band_18_plus`. **No preference is ever
overwritten.**

**Lifecycle, as decided 2026-09-09:** the band is **established once** and
**retained**. **There is no automatic or periodic re-checking.** It may be
re-derived **only if the member deliberately asks** (a control offered only to a
13-17 member; scoped, not yet built).

## 0b. THE OPERATIVE ARCHITECTURE — GLOBALLY UNIFORM, NOT JURISDICTION-DRIVEN

**This is the single most important fact for counsel, and it makes several
questions easier than they first appear.**

**Études applies age establishment and the 13-17 protections UNCONDITIONALLY,
everywhere it is distributed, to every member.** The flow is:

> establish Connected → request Apple's age range → **under-13 refused** →
> 13-17 protections applied — **globally, with no regional test anywhere.**

**Études does not determine jurisdiction.** It does not geolocate for regulatory
purposes, does not store a territory, and holds no rules table or effective dates
for any regime.

**Études consumes NEITHER of Apple's regulatory signals** —
`isEligibleForAgeFeatures` and `requiredRegulatoryFeatures` appear nowhere in the
source, verified by sweep. **This is deliberate and is not an omission to be
tidied up.** Those signals answer *"do additional regional obligations apply to
this person?"*, and Études' protections do not depend on the answer because they
are already applied to everyone.

**The inverse design was considered and rejected.** Études does **not need** a
regulatory or jurisdiction signal in order to decide whether to apply its age gate
or its teen protections, **because those protections are applied unconditionally
to everyone**. Replacing that with a jurisdiction-gated model — *ask whether
regulation applies, then apply child protections* — would be **less protective and
more complex**: it would introduce a decision point where none is needed, and
every failure of that decision would fail **open**.

**Consequence for this review:** where a regime's requirement is *"apply age
assurance and child protections"*, Études already does so for everyone. The live
question is only whether any regime requires **something additional** that
uniform protection does not satisfy.

---

## A — OBLIGATIONS THAT FALL ON ÉTUDES DIRECTLY, WHATEVER APPLE DOES

**The split below is by MEDIATION, not geography.** These are duties on SD Songs
Ltd as service provider; no Apple mechanism discharges them.

---

### Q1 — UK Online Safety Act. **ASK THIS FIRST**

**Why first:** it is **not mediated by Apple at all**, and it carries the largest
potential design impact of any question here. Ofcom's current position is that
**app stores have no direct OSA duties** — Ofcom is only now producing statutory
reports on whether such duties *should* exist — so OSA duties sit on the service
provider.

**Current behaviour.** Connected is a paid social layer: profile discovery,
follows, shared posts and comments between members. Minimum age 13. There is
**no content moderation, no reporting or flagging surface, and no guardian
channel**. Solo is account-free and uploads nothing.

**Question.** Is Études Connected an **in-scope user-to-user service likely to be
accessed by children**, and if so what duties apply to SD Songs Ltd — including
**what age-assurance standard is required for this feature set**?

**Confirm:** in-scope or not; the applicable duties; whether Apple's declared age
range meets the required assurance standard, or whether something stronger is
needed; and whether the absence of moderation/reporting is itself a duty gap.

**A TIMING DISTINCTION WE ARE DELIBERATELY NOT COLLAPSING.** Ofcom's guidance
appears to distinguish **launch** from the deadlines for statutory assessments,
including post-launch periods for children's-access and risk assessments. **This
packet therefore does NOT assert that every OSA assessment is a statutory
pre-launch condition** — we have not established that, and counsel should say what
the actual deadlines are.

**Two different things, and the record keeps them apart:** (a) the **statutory
deadline**, which is counsel's to state; and (b) **our own choice** to disposition
an issue before launch. **P5-G may elect to treat something as release-gating even
where the statutory deadline falls after launch** — that is a product decision,
not a legal conclusion, and it must never be written down as though it were one.

---

### Q2 — UK GDPR / Children's Code / DPIA

**Current behaviour** is set out in §0 and §0b. Six things to confirm:

1. **Lawful basis** for processing the stored age band.
2. **Adequacy of the DPIA's residual-assurance description** (§C2 wording below).
3. **Adequacy of the 13-17 defaults and interaction restrictions** — discovery
   off, inbound follow requests off and **not enableable**, sharing defaults off.
   Recorded reason for the inbound restriction: Études has **no moderation, no
   reporting surface and no guardian channel**, so inbound contact from a stranger
   to a minor would have no mitigating control behind it.
4. **Whether deliberate non-storage of Apple's assurance provenance is
   acceptable.** Note this cuts against data minimisation to reverse: storing it
   would mean holding *more* about minors.
5. **Whether the refusal wording is adequate for the relevant UK GDPR /
   Children's Code transparency requirements**, with corrections supplied if not.
   *(If some Apple-mediated foreign regime independently requires particular
   wording, that belongs in **Q3** as a concrete additional obligation, not
   here.)*
   > *"Études Connected is for ages 13 and over."*
   > *"Études needs Apple to share your age range before Connected can be set up.
   > You can change this in Settings, under your Apple Account."*
   **Constraint on any redraft: it must describe Apple SHARING an age range, never
   Études asking for an age.**
6. **Whether C3 may proceed with the testing limitation stated exactly** — see
   §C3.

---

## B — ADDITIONAL OBLIGATIONS MEDIATED THROUGH APPLE'S FRAMEWORK

**Scope of this section: determine only what, if anything, Études must do
ADDITIONALLY, beyond its globally uniform age protections.**

**Do not commission territory-by-territory surveys unless Q3 identifies a concrete
gap.**

---

### Q3 — Is globally uniform protection sufficient?

**Current behaviour.** As §0b: protections applied to everyone, no jurisdiction
determination, no Apple regulatory signal consumed.

**Question.** Is that **globally uniform approach sufficient** for the regional
App Store age-assurance regimes relevant to a globally distributed Études launch?

**And:** is there **any concrete, currently relevant regime** that requires
additional app-side behaviour **not adequately mediated by Apple's framework**?

**This is deliberately not a request to design or approve a jurisdiction engine.**
We are asking whether Études' globally uniform age gate and child-protective
defaults satisfy the **substantive** age-gating and default requirements of the
Apple-mediated regimes — **subject to any separate PROCEDURAL obligation**, such
as consent, notification, acknowledgement or record-keeping, which greater
substantive protection would **not** automatically discharge. **Q3a is one such
procedural question**; if there are others, name them.

---

### Q3a — Subsidiary, narrow, yes/no: consent revocation

**Current behaviour.** Études has **no parental-consent-gated capability** and no
significant-change flow. Apple states that when a parent or guardian revokes
consent, **Apple itself prevents the app from launching**. Apple's
`RESCIND_CONSENT` notification is not handled by Études' notification endpoint.

**Question.** Apple's guidance is stronger than merely publishing a notification
type: Apple states that when consent is revoked it **prevents the app from
launching**, *and* instructs developers to use `RESCIND_CONSENT` **to handle
consent revocations**.

**Given that platform enforcement and that instruction, what action — if any —
must Études take on receipt of the notification, beyond Apple's prevention of
launch?** And **does that require any change to Connected entitlement, account
state, or other server-side state?**

**We presume nothing** — not suspension, not deletion, not entitlement removal,
not any other behaviour. **We are asking counsel to identify the obligation if one
exists**, and none is proposed or implemented.

---

### Q4 — Establishment-only sufficiency

**Current behaviour.** The band is established once and **retained**. **No
periodic re-checking.** A member-initiated teen → adult recheck is scoped but not
built.

**Our reasoning, offered for confirmation or correction:** age moves one way.
Under-13 never establishes Connected; 13-17 may become 18+; 18+ does not become a
child by ageing. So the only ordinary reclassification is **13-17 → 18+**, and
observing it late leaves a member **more** protected, not less.

**Question.** Does any applicable obligation require **periodic re-assurance or
re-checking** despite that?

**This is the only question that should be allowed to reopen the rejected
continuous-polling architecture.**

---

### Q5 — The below-13 anomaly

**Question.** If a future **deliberate** recheck of an already-established 13-17
or 18+ member unexpectedly returns **below 13**, what legal disposition is
required?

This is an Apple-Account or corrected-data anomaly rather than ageing. **We have
deliberately invented no behaviour.** Candidate dispositions: ignore it; withdraw
Connected access while preserving all data; something else.

**This is the one place we ask counsel to help choose rather than confirm.**

---

## §C2 — THE RESIDUAL-ASSURANCE WORDING WE PROPOSE FOR THE DPIA

**An earlier draft said "a single unverified assertion". THAT WAS WRONG AND IS
WITHDRAWN** — it conflated *"we did not retain the provenance"* with *"there was
no provenance"*. Proposed replacement:

> Études retains a **point-in-time, Apple-supplied age-range classification**,
> derived from the Apple Account signed in to iCloud on the device at the moment
> of the request. Apple's underlying assurance may be **self-declared,
> guardian-declared, or confirmed by other means** (for example an identity
> document or a payment method). **Études deliberately does not read or retain
> that provenance**, and does not independently bind or verify the supplying
> Apple Account against the Études (Sign in with Apple) identity. The
> classification is **retained**, and is re-derived only on deliberate member
> action.

**One precision the sources support and counsel should know:** Apple's more
granular assurance/provenance information is **itself region-dependent** — Apple
notes the specific declaration methods are *"only available in some regions"* —
so provenance would be partial even if Études did retain it.

---

## §C3 — A LIMITATION THE DPIA MUST CARRY VERBATIM

**Not a question. Counsel must see it and must not soften it.**

> **Teen defaults are NOT device-verified.** No end-to-end device observation
> exists of a real Apple 13-17 range establishing `band_13_17`, and therefore none
> of the teen default row or the teen discovery opt-in chain. The Apple teen
> fixture was configured and observed; it later became unset without the actions
> we would expect to reset it; three disposable identities were tried; no real
> 13-17 result was obtained. Teen derivation and defaults are covered by the
> **client unit suite** and by the **deployed branchless server expression**,
> which has no teen-specific branch — one expression decides both bands.
> **That is coverage, not hardware verification.**

**Confirm** the DPIA may proceed carrying this as written.

**External material is deliberately excluded from this packet and from the
DPIA.** Unverified third-party observations about Apple's age-assurance Sandbox
are kept in the engineering record at `docs/cp3-sandbox-external-evidence.md`,
where their only job is to explain **why the fixture chase was stopped**. **They
are not offered as evidence here, and nothing in this packet rests on them.**
**The DPIA needs the measured limitation above — our own evidence — and not a
vendor bug history.**

---

## HOW TO OBTAIN CONFIRMATION

| | needs | note |
|---|---|---|
| **Q1** OSA | UK online-safety specialist | **Ask first.** Not Apple-mediated; largest design impact; could change the feature set |
| **Q2** GDPR / Children's Code / DPIA | UK data-protection specialist | The substantial one. Q1 and Q2 may be the same adviser |
| **Q3–Q5** (incl. Q3a) | technology / privacy counsel familiar with **Apple's global age-assurance framework** | **Narrow confirmation only.** **No state-by-state or country-by-country survey** unless counsel identifies a concrete **unmediated** requirement |

**THE INTENDED COMMISSIONING MODEL, stated so it is not widened by accident:**

- **A — obligations falling directly on Études:** UK OSA (Q1) plus UK GDPR /
  Children's Code / DPIA (Q2).
- **B — Apple-mediated age-assurance obligations:** narrow confirmation of
  whether the globally uniform Études architecture is **sufficient**, and whether
  any concrete **additional procedural** behaviour is required (Q3, Q3a, Q4, Q5).

**DO NOT COMMISSION AN INTERNATIONAL AGE-LAW SURVEY** unless counsel identifies a
specific gap that genuinely requires one. Territory-by-territory analysis is the
expensive default this packet exists to avoid.

**One thing to know before commissioning:** **Q4 is the only question that can
reopen an engineering decision.** The rejected continuous-polling design is
preserved at `c5440d8` if it ever needs to return.

**What we do NOT need counsel for:** whether to build periodic re-derivation
(decided; reversible only via Q4); the App Store privacy labels (**P5-H**, which
must **re-derive** the mapping after this review, not republish the Phase 4 one);
and the release-gating notification configuration, which is technical.

---

## WHAT IS NOT IN THIS PACKET, DELIBERATELY

**No production identifiers**, no UUIDs, no account data. **No legal analysis** —
every "we decided" is a product decision offered for confirmation, not an opinion
about the law. **No draft privacy policy**: that is P5-H and must follow this
review.

**And no claim that Apple endorses our flow.** Apple's published materials
describe what its APIs do and stop there: Apple's own age-assurance developer
guidance states that *"developers are responsible for their own age
restrictions"* and, twice, that developers should *"consult your legal counsel"*
on compliance obligations. **We therefore make no claim that any Apple guidance
endorses Études' implementation** — which is precisely why this packet exists.
