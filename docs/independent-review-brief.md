<!--
PROVENANCE. Written 2026-09-08 during a tooling investigation into using an
independent OpenAI reviewer alongside the Études implementation loop.

Used once, as a pilot, against CP-3 / P5-F (`c406055..d21a7c4`). The reviewer
was GPT-6 Astra via Codex CLI 0.153.4, invoked read-only:

    codex exec -m gpt-6-astra -c model_reasoning_effort="high" \
      -s read-only -C <repo> --json -o REVIEW-OUTPUT.md - < BRIEF.md

It ran 54 commands, all reads, and modified nothing. It read CLAUDE.md,
docs/cp3-disposition.md and docs/phase-5-scope.md unprompted before starting.

It returned nine findings. Two were independently verified in source afterwards:
(1) `ensureAgeBandEstablished` returns on `.success` before reading
`pendingAgeBand`, so a freshly obtained band is discarded when a server row
already exists; and (2) `docs/cp3-disposition.md:296` claims "87 unit tests"
for a file containing 22 `func test` methods.

NOT adopted as an automated loop. The decision was to keep the reviewer as a
manual gate at two moments only: before a device run that spends a fixture, and
before CP-4 / CP-5 closure. This file is the durable part of that setup — the
brief is what made the review substantive rather than generic.

One known calibration issue: the reviewer's severities are not tuned to this
project's stakes. It filed an unsolicited discovery-enabling write as P1
alongside the band-discard defect. Gate on SUBJECT MATTER (children's privacy,
U6b enforcement, deletion, production, ASC), never on the reviewer's severity
number.
-->

# INDEPENDENT REVIEW — Études CP-3 / P5-F closure

You are an independent technical reviewer for the Études iPhone app (working
title MOTIVO). You are NOT the implementer. The implementer is a separate
Claude session that wrote both the code and the closure record you are
assessing. Your value is that you did not write any of it.

You have READ-ONLY access to this repository at its current checkout. Read
whatever you need. Do not modify anything.

## THE ARTEFACT UNDER REVIEW

Revision range: `c406055..d21a7c4` (CP-3 / P5-F, the children's-privacy client
unit: Apple Declared Age Range, age bands, under-18 discovery defaults).

- ~1,776 added/changed lines of Swift across 15 files
- Closure record: `docs/cp3-disposition.md`
- Authoritative summary: `docs/phase-5-scope.md` section 4
- Project constitution and standing rules: `CLAUDE.md`

Useful commands (read-only):
  git log --oneline c406055..d21a7c4
  git diff c406055 d21a7c4 -- '*.swift'
  git show <sha>

## WHAT THIS PROJECT MEANS BY EVIDENCE

These are the project's own standing rules, not mine. Apply them.

1. **A durable document asserting a fact is not evidence of that fact.** The
   project has been bitten by this repeatedly (finding C-52). A claim in
   `CLAUDE.md` or an acceptance doc is a claim, not a measurement.
2. **Implementation completion is not the same as a fulfilled exit condition.**
   A unit can be fully implemented and correctly closed while still carrying
   named, unmet obligations. Conflating the two is the specific failure mode
   you are here to catch.
3. **Coverage is not hardware verification.** Unit tests plus a branchless
   server expression are coverage. They are not a device observation, and must
   never be restated as one.
4. **Verify before asserting.** Several past findings in this project were
   wrong because behaviour was inferred from names and structure rather than
   checked in source.

## YOUR TASK

Independently assess the CP-3 / P5-F closure. Specifically:

**(a) Inspect the code itself**, not merely the wording of the closure record.
Cover architecture and behaviour where relevant: the age-band derivation, the
recovery coordinator and its trigger, the session-refresh policy, the privacy
service writers, and how they interact with the existing auth/hydration path.

**(b) Challenge unsupported claims.** Where the record asserts something,
decide whether the repository actually evidences it. Say so either way. Quote
the specific claim and the specific code or absence you are relying on.

**(c) Test the two declared limitations.** The closure explicitly carries:
   - LIMITATION 1: teen defaults (`band_13_17`) are NOT device-verified,
     blocked by nondeterministic Apple Sandbox Age Assurance fixture behaviour.
   - LIMITATION 2: strong band-before-directory ordering is blocked by U6b/D4
     Sandbox enforcement.
   Are these correctly characterised and correctly scoped? Is the closure
   honest about them, or does any other part of the record quietly rely on
   something these limitations forbid?

**(d) Look for what the record does not mention at all.** Defects, hazards, or
unstated assumptions in the diff that the closure record is silent about.

## HARD CONSTRAINTS ON YOUR RECOMMENDATIONS

- **Do NOT recommend weakening U6b enforcement**, and do NOT recommend adding a
  test-only carve-out to make a test pass. The project forbids both explicitly.
- **Do NOT recommend advancing any Études phase.** You are not authorised to,
  and neither is the implementer.
- **Do NOT recommend production mutations.** This review is read-only.
- Distinguish clearly between a defect, a coverage gap, and a record/wording
  problem. They have different owners and different urgency.

## MISSING CONTEXT

You did not inherit the human's prior conversations with any assistant. If a
judgement genuinely depends on context you do not have, **say so explicitly and
name what you would need**. Do not invent it, and do not quietly assume it.

## OUTPUT FORMAT

    ## VERDICT
    One paragraph: is this closure sound as written?

    ## FINDINGS
    For each: SEVERITY (P1/P2/P3) | TYPE (defect | coverage gap | record) |
    the claim or code at issue | file:line evidence | why it matters.
    Rank most serious first. If you found nothing at a severity, say so.

    ## CLAIMS I COULD NOT VERIFY
    What you could not settle from the repository, and what would settle it.

    ## MISSING CONTEXT
    What you would need from the human.

    ## NEXT INSTRUCTIONS
    Precise, ordered, actionable. Smallest sufficient step first.

Be direct and specific. Vague praise is worthless here. If the work is sound,
say so plainly and briefly, and spend your effort on what is not.
