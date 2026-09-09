# C-64 PHASE 1 — STRUCTURED TEST CENSUS. CLAIM REFUTED. 2026-09-09

**Measurement only. No configuration was changed, no test or product code was
touched, and `parallelizable` was deliberately left exactly as it was.**

## 1. The question

**Are tests genuinely failing to execute intermittently, or were the previous
counts distorted by log parsing, skips, XCTest/swift-testing reporting
differences, or parallel-run presentation?**

## 2. Method

Six runs of `MOTIVOTests`, each into its **own result bundle** — **3 parallel, 3
serial** (`-parallel-testing-enabled NO`). Every bundle read with
`xcrun xcresulttool get test-results tests --format json`, enumerating **every
test node and its outcome**. Declared tests parsed from source: `func test…` in
`XCTestCase` subclasses plus `@Test` cases.

**No console text was parsed.** The tool is committed as
`scripts/test-census.py`, so the method is reproducible rather than described.

## 3. Result

**118 tests declared. Every run reported 118. All passed. Nothing missing.**

| bundle | reported | outcomes |
|---|---|---|
| parallel 1 / 2 / 3 | 118 / 118 / 118 | all **Passed** |
| serial 1 / 2 / 3 | 118 / 118 / 118 | all **Passed** |

**Declared-vs-executed membership, the three named suites:**

| suite | declared | missing, any of six runs |
|---|---|---|
| `AgeBandRecoveryGateTests` | 5 | **none** |
| `SessionRefreshPolicyTests` | 22 | **none** |
| `SharedOnlyUploadTests` | 5 | **none** |

**`AgeBandRecoveryGateTests` is the decisive one.** I reported it running **4 of
5** in two consecutive runs. Structured data says **5 of 5, six times out of six.**

## 4. THE CLAIM IS REFUTED, AND THE FAULT WAS MINE

**C-64 was built on grepping `Test case '…'` lines from xcodebuild console
output.** That does not enumerate tests reliably: the target mixes **XCTest and
swift-testing**, and parallel runs present results **per simulator clone**. The
totals I quoted — 87/86/86, 116/114, 115/116/117, and the serial 103 — were
**artefacts of the grep**, not properties of the suite.

**I repeated this across three documents and escalated it into a leading
candidate.** It has been corrected in each, in place, rather than deleted.

**This is the same failure the project keeps meeting from a new angle: the
instrument was wrong before the conclusion was.** It sits beside the U6b
telemetry blind spot, the 401-versus-RLS-denial confusion, and the comment that
defeated its own assertion. **The habit that caught it is the one that mattered —
measure with a structured instrument before believing a count.**

## 5. What survives

**A narrower, genuine observation.** Two real *failures* occurred earlier in
**local-stack** suites — `SharedOnlyUploadTests` and
`PublishServiceConnectedDeleteTests` — each passing on retry.

**They were structurally reported, not silent**, and they are ordinary
environment-dependent flakiness in tests sharing one local database. **That is a
different claim from non-execution and does not mean the suite hides work.** None
of the six census runs produced a failure or a skip, so the local stack was
healthy throughout and this residual was not exercised here.

## 6. Disposition

**C-64 is CLOSED — primary claim refuted.** No configuration change is proposed
or made; the stopping rule agreed beforehand applies exactly as written.

**"Full suite green" is now a trustworthy claim** — provided it is measured with
`scripts/test-census.py` and not with a grep.
