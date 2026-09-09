# PHASE 5 — RE-BASELINE. 2026-09-09

**Premises verified in source or by measurement today. Stale register severity was
not trusted — C-10 and C-20 already showed why.**

## 1. AUTHORITATIVE REMAINING PHASE-5 WORK

| unit | state |
|---|---|
| P5-A, P5-A3, P5-B…P5-F | **complete** |
| **P5-M — playback speed** | **complete, device-verified 14/14** |
| P5-G (CP-4) | **externally pending** — counsel |
| P5-H (CP-5) | **held** behind P5-G |
| P5-I (C-34 TTL), P5-J, P5-K, P5-L, P5-N | not started |

### 1.1 IS THERE ANY PLANNED PRODUCT WORK LEFT? **NO — AND THAT IS THE HONEST ANSWER**

**Playback speed was the only planned product feature in Phase 5, and it is
done.** Everything remaining is correctness, investigation, performance or
accessibility. **Nothing feature-shaped is being buried under C-numbers.**

**The inverse risk is real, though: P5-N (accessibility) is planned work**, it now
carries **two** findings (C-11 and C-67), and it has no advocate. **It is the item
most likely to be squeezed out**, not a feature.

## 2. VERIFIED EVIDENCE — leading candidates

| finding | verified today | verdict |
|---|---|---|
| **C-64** suite integrity | **measured, see §3** | **confirmed, and my instrument is inadequate** |
| **C-56** Core Data in `body` | `requiresAppSetUpNow()` runs a `Profile` fetch **plus** `fetchInstruments()`; reached from `body` at `:1572` **and** `:1901` — **two call sites per evaluation** | **CONFIRMED at HEAD** |
| **C-62** title logged in Release | line 294 measured at `#if DEBUG` **depth 0 → SHIPS IN RELEASE**; 12 `NSLog` sites in that file | **CONFIRMED it ships**; exposure still unmeasured |
| **C-5** duplicate Score adoption | `savedToScoresAt` appears **only** as a model property and coding key — **zero UI reads anywhere** | **CONFIRMED, and sharper than the row** |
| **C-65** silent partial publish | deliberate skip + `print`, caller cannot distinguish partial from complete | confirmed earlier |
| **C-66** unfollow no-refresh | asymmetry confirmed; newly reachable since C-43 | confirmed earlier |
| **C-67** transport a11y | all 12 `accessibilityLabel`s are top-toolbar; both `mediaControlButton` helpers add none | confirmed earlier |
| **C-68** review-player teardown | `onDisappear` never pauses/releases the player | confirmed earlier |
| **C-69** remote-audio rate | rate arrives only by change-notification | confirmed earlier |
| **C-3** foreground hydration | mechanism unchanged; P3; sibling of C-56 | confirmed earlier |
| **C-20** main-actor isolation | **premise does not reproduce at HEAD** | **already demoted** |

## 3. C-64 — MEASURED TODAY, AND THE RESULT CUTS BOTH WAYS

### 3.1 The sharpest single fact

**`AgeBandRecoveryGateTests` declares FIVE tests. Two consecutive parallel runs
executed FOUR.** `testRequiresAnIdentityAndAConfiguredBackend` was **absent
entirely — not passed, not failed, NOT SKIPPED.** It ran in an earlier run of the
same commit.

**It is a pure unit suite with no local-stack dependency**, so reachability and
`XCTSkip` cannot explain it. That is the second test to show this, after
`SessionRefreshPolicyTests.testStillValidTokenDoesNotRefresh`.

### 3.2 A CORRECTION TO MY OWN EARLIER EVIDENCE

**I previously cited differing totals (87/86/86, 116/114) as evidence of silent
variance. Much of that was NOT silent.** Local-stack tests emit explicit
`Test case '…' skipped` lines when the stack is unreachable, and the arithmetic
closes: run 1 = 117 names = 115 passed + 2 skipped; run 2 = 117 = 115 + 1 failed +
1 skipped.

**So C-64's "wildly varying counts" evidence is weaker than I stated, while its
core — specific pure tests vanishing — is stronger and now reproduced.**

### 3.3 Parallelisation is implicated, and serial behaves differently

The scheme sets **`parallelizable = "YES"` on both testables**, which is why runs
report *"Clone 1 of iPhone 17 Pro"*.

| mode | names | failures |
|---|---|---|
| **parallel** ×3 | 115 / 116 / 117 | 0 / 1 / 1 — both in **local-stack** suites |
| **serial** ×2 | **103 / 103** | **0 / 0** |

**Serial is perfectly stable and has zero failures.** That is consistent with
concurrent tests contending for one shared local database.

### 3.4 BUT MY INSTRUMENT IS NOT TRUSTWORTHY, AND THAT IS THE REAL FINDING

**Serial reports FEWER tests (103) than parallel (115-117).** I cannot explain
that from log text, and the likely reason is that **counting `Test case '…'` lines
does not capture swift-testing cases the same way in both modes** — the suite is a
mix of XCTest and swift-testing.

**So the two numbers are not comparable, and part of the "variance" I have been
citing all session may be an artefact of my grep rather than a property of the
suite.**

**THE FIRST TASK OF ANY C-64 UNIT IS THEREFORE MEASUREMENT, NOT A FIX** — a
structured census via `xcresulttool` on a result bundle, which enumerates every
test and outcome, instead of grepping console output. **This is the same lesson as
the U6b telemetry and the comment-defeated assertion: the instrument was wrong
before the conclusion was.**

## 4. RECOMMENDATION — **C-64**, and the grounds are today's measurements

**Not because it was highlighted.** The grounds are new: a declared test in a pure
suite silently not executing in two of three runs, reproduced on a second test,
plus the discovery that my own counting instrument is unsound.

**Criterion 7 is decisive.** Every remaining Phase-5 unit — C-56, C-5, C-62,
C-67, and P5-I — will be accepted partly on *"full suite green"*. **I can now
demonstrate that this claim can be silently incomplete.** Fixing the evidence
system first makes every later acceptance mean what it says; leaving it means each
subsequent unit inherits the doubt.

**It does not harm users**, and that is exactly why it needs arguing for rather
than assuming.

### 4.1 If you would rather ship user-facing work first

**C-56** is the strongest alternative — confirmed at HEAD, already *measured* (47
of 50 samples in one function, ~100% CPU on the onboarding screen), release-
relevant because it is the first screen a new member sees, and bounded.
**C-5** is next: confirmed, and the duplicate is user-visible.

**I would still do C-64 first**, but this is a close call and it is your decision,
not a technical one.

## 5. PROPOSED SCOPE — C-64, INVESTIGATION-FIRST

**Phase 1 — measure properly (no fix).**
Structured census via `xcresulttool get test-results tests` on a result bundle,
for **N parallel runs and N serial runs**, listing every declared test and its
outcome. **Establish whether tests genuinely fail to execute, or whether my
console counting was simply wrong.**

**Phase 2 — only if non-execution is confirmed.** Identify the mechanism
(parallelisation, clone result-merging, shared static/`UserDefaults`/local-DB
state) and propose the smallest change. **Candidate, not a decision:
`parallelizable = "NO"` for the suites that share the local stack.**

**Acceptance:** a reproducible census method committed as a script; a stated
answer to "does the full suite run every declared test, every time"; and, if a fix
lands, N consecutive runs with an identical complete census.

**Explicitly NOT in scope:** rewriting tests, changing product code, or
"fixing" flaky local-stack tests by weakening their assertions.

## 6. EXTERNAL REQUIREMENTS

**None.** No production, no ASC, no device, no enforcement change. Local stack and
simulator only.

## 7. DEMOTIONS AND CLOSURES FROM THIS RE-BASELINE

- **C-20 — stays demoted.** Premise does not reproduce at HEAD.
- **C-64 — evidence CORRECTED in both directions** (§3.2): the count-variance
  claim is weakened; the silent-non-execution claim is strengthened and
  reproduced.
- **Nothing else closed.** C-63, C-65, C-66, C-67, C-68, C-69, C-3, C-5, C-56,
  C-62 all remain open on verified premises.
