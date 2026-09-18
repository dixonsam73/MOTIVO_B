# Études — legal questions for confirmation

> **SUPERSEDED — 18 SEPTEMBER 2026. HISTORICAL AND LEGAL-WORKING RECORD.** These
> questions assume the former **13+ Connected** design. They are retained unchanged
> as a record. **The current target is adult-only Connected** (Solo unchanged, no
> Études-imposed age restriction). **Any future counsel brief must be built from
> `docs/adult-only-connected-rescope-2026-09-18.md`.** Whether this brief was sent to
> counsel is not recorded. If it was, counsel should be told that it describes a
> superseded design.

**SD Songs Ltd (UK) · 17 September 2026**

**A targeted confirm/correct review, not a general international survey of age-assurance
law.** If answering needs materially wider research, please tell us the scope and cost first,
and say whether any question needs a specialist adviser.

## Context

Études is a UK iPhone journal for musicians, not yet released. Solo is account-free and
uploads nothing. An optional paid tier, **Connected**, adds profile discovery, follows, shared
posts and comments, and is **13+**.

Connected uses **Apple's Declared Age Range**: Apple presents its own interface and supplies a
range, so **Études never asks anyone their age or date of birth**. We store only **13–17** or
**18+** — no date of birth, exact age, or record of Apple's assurance provenance — established
once, with no re-check. Under 13 is refused before any server contact or account creation.
**The range comes from the Apple Account on the device, which we do not verify against the
person's Études identity.**

For 13–17: sharing defaults private; discovery defaults off but may be turned on; **inbound
follow requests are off and cannot be enabled**; the member may follow others. These apply
**globally** — we do not determine jurisdiction. **We have no moderation, no reporting
surface, and no guardian channel.**

## A proposed change — please assess this too

Blocking all inbound requests also blocks a teen's **teacher and classmates**. We propose:
discovery stays off by default; someone the teen **already follows** may ask to follow back;
**private invitations** shared via the iOS share sheet let known classmates connect without
public discovery and **without Études reading contacts**; every direction still needs the
followed person's **explicit approval**, refusable and revocable; other unsolicited requests
stay blocked; **an invitation never itself grants access**. Invitation forwarding, confirming
who receives one, expiry and reuse, and abuse controls are **unresolved on our side**.

## Questions

**1 — Online Safety Act.** We assume Connected is an in-scope user-to-user service
intentionally accessible to 13–17s. Please confirm or correct that and identify the
proportionate duties. Is **Apple's Declared Age Range adequate age assurance**? Does the
**absence of moderation and reporting** create a material duty gap? Anything else material
before launch? What **deadlines** apply to children's-access or risk assessments, statutory
as against voluntary?

**2 — UK GDPR / Children's Code / DPIA.** Please confirm or correct: storing only the
13–17/18+ classification; **not** storing date of birth, exact age or assurance provenance;
keeping it without refresh; describing it in the DPIA as a point-in-time, Apple-supplied
classification we do not independently verify; and the **lawful basis**. Are the **13–17
defaults adequate, as they stand and as proposed**, given no moderation, reporting or guardian
channel? If not, what mitigation is needed, and which unresolved invitation questions bear on
it? Please correct this refusal wording if needed — any alternative must describe **Apple
sharing** a range, never Études asking someone's age:

> *"Études Connected is for ages 13 and over."*
> *"Études needs Apple to share your age range before Connected can be set up. You can change
> this in Settings, under your Apple Account."*

**3 — Globally uniform protection.** We apply the age gate and child protections everywhere,
with no jurisdiction engine. Is that sufficient for the regional App Store age-assurance
regimes relevant to a globally distributed app, or is there a **concrete additional app-side
obligation** Apple's framework does not adequately mediate? Greater substantive protection
would not discharge a separate **procedural** duty — consent, notification, acknowledgement,
record-keeping — so please name any. **Under the proposed change, would we need to consult
Apple's `communicationLimits` or any other parental-control signal?** We consume none today.
*Not a country-by-country survey unless you identify a gap.*

  **3a — Consent revocation.** Apple provides a `RESCIND_CONSENT` notification and says it
  prevents launch when parental consent is withdrawn. We have no consent-gated capability and
  do not handle it. **Does Études need any additional server or account action on receiving
  it?**

**4 — Periodic re-assurance.** We do not re-request the range, reasoning that ageing only
moves someone 13–17 → 18+, so detecting it late leaves an adult under stricter protections
rather than exposing a child to adult defaults. **Does any obligation require it?** This most
affects our architecture.

**5 — An unexpected below-13 result.** If a voluntary re-check of an existing member returns
below 13 — changed device or account context, or corrected information — should we **withdraw
Connected access while preserving the account and data**, or **disregard the result**?

**Supporting evidence.** Apple's test environment has not let us obtain a reliable real 13–17
result on hardware, so teen behaviour rests on our automated tests and server logic rather
than device verification. **Is disclosing this in the DPIA sufficient, or is further evidence
or assurance needed before launch?**

**Priority:** Online Safety Act and UK GDPR / Children's Code / DPIA first, then narrow
confirmation that our uniform use of Apple's framework leaves nothing unmet. **Please do not
begin a broader international survey without checking with us.**
