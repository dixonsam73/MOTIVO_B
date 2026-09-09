# P5-G / CP-4 — LEGAL REVIEW PACKET

**For deciding HOW to obtain confirmation, and for briefing whoever gives it.
2026-09-09. This is a checklist and a fact base, not a memo and not legal
analysis.**

**Four questions, C1–C4.** Each gives the **current behaviour** (measured, not
described from intent), the **question**, and **exactly what we need confirmed**.

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

**How age is determined.** Apple's **Declared Age Range** framework (iOS 26+),
called as `requestAgeRange(ageGates: 13, 18)`. Apple returns a **range**, never a
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
on; **inbound follow requests cannot be enabled at all** (see C4/Q2 note). They
may still follow others themselves.

**A protection that withholds effect rather than destroying data:** a preference
set as an adult stops taking effect if the band later reads `band_13_17`, and
takes effect again if it returns to `band_18_plus`. **No preference is ever
overwritten.**

**Lifecycle, as decided 2026-09-09:** the band is **established once** and
**retained**. **There is no automatic or periodic re-checking.** It may be
re-derived **only if the member deliberately asks** (a control offered only to a
13-17 member; scoped, not yet built).

---

## C1 — Refusal wording

**Current behaviour.** When Apple reports below 13, or declines/cannot supply a
range, Connected is refused **before any server contact**; **nothing is written
and no account is created**. Two strings are shown:

> *"Études Connected is for ages 13 and over."*

> *"Études needs Apple to share your age range before Connected can be set up.
> You can change this in Settings, under your Apple Account."*

A refusal is **not** recorded — no counter, no history, no flag. The member may
retry at any time.

**Question.** Is this wording adequate, and does any jurisdiction we distribute in
require a variant?

**Confirm:** (a) both strings are adequate as written, or supply corrections;
(b) whether recording nothing about a refusal is acceptable, or whether any
obligation requires us to retain a record; (c) whether any jurisdiction requires
different or additional wording.

**Constraint on any redraft:** it must describe **Apple sharing an age range**,
never Études asking for an age.

---

## C2 — DPIA: how honestly the age signal is described

**Current behaviour, stated as we propose to state it in the DPIA:**

- The range comes from **the Apple Account signed in to iCloud on the device at
  the moment of the request**.
- It is **not bound or verified against the Études account** (which is a Sign in
  with Apple identity). The same person on another device, or a different Apple
  Account on the same device, is a different source.
- **No DOB and no provenance is stored**, so Études cannot say whether a band was
  self-asserted or ID-confirmed.
- The band is **established once, retained, and re-derived only on deliberate
  member action** — **there is no automatic periodic refresh**.
- Therefore the assurance is **a single unverified assertion**, refreshed only if
  the member chooses.

**Question.** Is that an adequate and accurate characterisation of the residual
assurance for a DPIA, given a 13+ social feature?

**Confirm:** (a) the characterisation is adequate; (b) the **lawful basis** for
processing the band; (c) whether the deliberate non-storage of provenance is
acceptable, or whether it must be stored to evidence the strength of assurance —
**note this cuts against data minimisation and would mean storing more about
minors**; (d) whether retention-without-refresh is acceptable, or whether some
periodic re-assurance is required. **(d) overlaps C4 and is the one that could
reopen a settled engineering decision.**

---

## C3 — A limitation the DPIA must carry verbatim

**This is not a question. It is a disclosure counsel must see and must not soften.**

> **Teen defaults are NOT device-verified.** No end-to-end device observation
> exists of a real Apple 13-17 range establishing `band_13_17`, and therefore none
> of the teen default row or the teen discovery opt-in chain. It is blocked by
> nondeterministic Apple Sandbox age-assurance fixture behaviour: the fixture was
> set and verified, then found unset roughly two minutes later with no deletion,
> install, sign-in or interaction; Apple documents no reset procedure; three
> disposable test identities were spent and the teen band was never produced once.
> Teen derivation and defaults are covered by the **client unit suite** and by the
> **deployed server expression**, which has no teen-specific branch — one
> expression decides both bands. **That is coverage, not hardware verification.**

**Confirm:** that the DPIA may proceed carrying this limitation as written, and
that it is disclosed in the right terms. **A DPIA implying teen protections are
device-verified would misstate the evidence.**

---

## C4 — Scope and ongoing obligations

**Framed narrowly and deliberately: this asks about APPLICABILITY, not
implementation.**

**Background.** App-store age-assurance laws — **Texas SB2420 (effective
2026-01-01)**, with Utah, Louisiana and Brazil following — prompted Apple's
Declared Age Range framework. Apple states developers must obtain the age
category, use its Significant Change API when an app changes materially, and
**receive App Store Server Notifications when a parent or guardian withdraws
consent** (`RESCIND_CONSENT`). **Apple twice refers compliance questions to
counsel:** *"For questions about your compliance obligations, consult your legal
counsel."*

**Current behaviour.** Études obtains the band at establishment; does **not**
re-check; does **not** consult Apple's parental-controls signal; has **no**
parental-consent flow and **no** significant-change flow; and its notification
endpoint **does not handle `RESCIND_CONSENT`**. Apple itself **prevents the app
from launching** when consent is revoked.

**Four questions:**

| | |
|---|---|
| **C4.1** | Is Études **within scope** of these laws — given it is unreleased, and depending on where we distribute? |
| **C4.2** | If so, does any impose an **ongoing** age-assurance duty **beyond establishment** — i.e. must we re-check periodically? **We have decided not to, on the basis that age moves one way: the only ordinary change is 13-17 → 18+, and observing it late leaves a member MORE protected, not less.** Confirm or correct that reasoning. |
| **C4.3** | Does **`RESCIND_CONSENT` handling** create an obligation for an app like Études, which has no parental-consent-gated capability, given Apple already blocks launch? **If yes, what must we do server-side** — Apple does not specify. |
| **C4.4** | Apple can report a **below-13** range for an account that previously established 13-17 or 18+ — an Apple-Account or corrected-data anomaly, **not** ageing. **What should that mean?** We have deliberately **not** invented behaviour. Options: ignore; withdraw Connected access while preserving all data; something else. **This is the only place we are asking counsel to help choose rather than confirm.** |

**Also confirm the settled product rule (Q2):** a 13-17 member **cannot enable
inbound follow requests** — relationship initiation *by another member* is closed,
though the young member may initiate. Recorded reason: Études has **no moderation,
no reporting surface and no guardian channel**, so inbound contact from a stranger
to a minor would have no mitigating control behind it. **Confirm this is
defensible, or tell us it is insufficient.**

---

## HOW TO OBTAIN CONFIRMATION — the actual decision

**These are not one instruction.** They differ in cost and in who can answer.

| | needs | plausible route |
|---|---|---|
| **C1** wording | UK/EU consumer-facing copy review | light — a privacy/consumer specialist, possibly alongside the privacy policy |
| **C2** DPIA | data-protection specialist, UK GDPR / children's data | the substantial one. Likely the same adviser who signs off the DPIA |
| **C3** disclosure | no new advice; must be **carried** into the DPIA | folds into C2 |
| **C4** scope | **US multi-state** app-store age-assurance, plus Brazil if distributing there | narrowest and most specialist. Could be deferred by **limiting initial distribution territories** — that is a commercial decision available to us |

**Two levers worth knowing before commissioning anything:**

1. **C4 can be reduced by scoping distribution at launch.** If Études does not
   initially distribute where these laws bite, C4.1 largely answers itself and
   C4.2/C4.3 become future work. **That is a product decision, not a legal one.**
2. **C2 is the only one that could reopen engineering.** C2(d) and C4.2 ask the
   same underlying question — whether retention-without-refresh is acceptable. If
   the answer is no, the reverted design becomes relevant again and is preserved
   at `c5440d8`.

**What we do NOT need counsel for:** whether to build periodic re-derivation
(decided, and reversible if C2(d)/C4.2 say otherwise); the App Store privacy
labels (**P5-H**, which must **re-derive** the mapping after this review, not
republish the Phase 4 one); and the release-gating notification configuration,
which is a technical matter.

---

## WHAT IS NOT IN THIS PACKET, DELIBERATELY

**No production identifiers**, no UUIDs and no account data. **No legal analysis**
— every "we decided" above is a product decision offered for confirmation, not an
opinion about the law. **No draft privacy policy**: that is P5-H and must follow
this review, not precede it.
