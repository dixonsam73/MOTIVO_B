# CP-3 — EXTERNAL CONTEXT FOR STOPPING THE SANDBOX TEEN-FIXTURE CHASE

**Engineering / test-evidence record. 2026-09-09.**

**THIS DOES NOT BELONG IN THE DPIA, AND MUST NOT BE COPIED INTO IT.** The DPIA
needs the **measured limitation** (C3), not a vendor bug history. A catalogue of
third-party reports dates the moment Apple ships a fix, and importing unverified
evidence into a compliance document weakens the document.

## 1. What this file is for

It records **why the fixture chase was stopped**, which is an engineering
judgement. It is **not** evidence about Études' implementation, **not** evidence
that Apple's Sandbox is defective, and **not** an explanation of our own fixture
failure.

## 2. OUR MEASURED EVIDENCE — authoritative, and unchanged

- The Apple teen fixture was **configured and observed**.
- It later became **unset** without the actions we would expect to reset it.
- **Three disposable identities** were tried.
- **No real 13-17 result was ever obtained.**
- Teen derivation and defaults are covered by the **client unit suite** and the
  **deployed branchless server expression** — one expression decides both bands,
  so there is no teen-specific branch to go untested.
- **That coverage is NOT hardware verification.**

## 3. THIRD-PARTY, UNVERIFIED CORROBORATIVE CONTEXT

**Every item below is a report by another developer on Apple's Developer Forums.
None was reproduced by us. Some reports in this area have identifiable
configuration causes — a missing entitlement, or a Sandbox account signed into
the wrong account context — so this material must not be read as proof of a
general Sandbox defect.**

Contemporaneously reported limitations around the new age-assurance Sandbox:

- `isEligibleForAgeFeatures` returning **false** despite a configured Sandbox
  age-assurance scenario, including a production report that it *"consistently
  returned false for users in regulated regions"* after an enforcement date.
- `isEligibleForAgeFeatures` calls **hanging** / not responding.
- `requestAgeRange` throwing **`notAvailable`** despite a configured child
  scenario.
- Generic `AgeRangeService.Error` responses.
- **`RESCIND_CONSENT` apparently triggered from Sandbox UI but never reaching the
  developer's Sandbox notification endpoint.**
- Sandbox consent flows returning **mocked** responses, preventing the real
  end-to-end parental-consent UI from being exercised.
- Production/local testing of that real UI refused because the tester is **not in
  a supported regulatory region**.
- **Cached or stale age ranges** persisting after account age changes.

## 4. THE NARROW CONCLUSION, AND IT IS THE ONLY ONE DRAWN

**There is independent contemporary evidence that other developers are also
encountering limitations and gaps in end-to-end testability in Apple's new
age-assurance Sandbox. Our inability to obtain the teen fixture should therefore
NOT automatically be treated as evidence of an Études implementation defect.**

Nothing stronger follows. In particular this does **not** establish the cause of
our own fixture failure.

## 5. STANDING INSTRUCTION

**Do not reopen the Sandbox teen-fixture chase** merely because Apple's
documentation says the scenarios should work. C3 stands as measured, and the
question is closed to further experimentation.

## 6. One correction of the record, made here rather than quietly

An earlier framing suggested Apple **DTS** guidance directs developers to use
`isEligibleForAgeFeatures` to determine regulatory applicability. **That is not
established.** What exists is:

- **Apple documentation** — authoritative — stating the property indicates
  *"whether associated laws or regulations may apply to your app based on the
  person's location and account settings"*;
- **developer interpretation on the forums**, explicitly not Apple guidance, in
  threads whose own conclusion is that *"Apple's docs simply describe what the
  APIs do with no guidance on what the overall flow is meant to look like."*

**No Apple/DTS endorsement of an overall implementation flow was found.**
