# P5-A3 — iOS 26.4 PRODUCT BASELINE: ACCEPTANCE. 2026-09-09

**COMPLETE.** Études now requires **iOS 26.4** for the entire app, including Solo.
Scored against `docs/phase-5-a3-ios264-prediction.md`, committed at `769b6f8`
**before** any mutation.

**A discrete pre-launch baseline unit. NOT part of P5-G. No regulatory
implementation is inferred from it, and none was added.**

## 1. PREDICTED vs ACTUAL

| measure | before | predicted | **actual** | |
|---|---|---|---|---|
| `IPHONEOS_DEPLOYMENT_TARGET = 26.2;` | 4 | 0 | **0** | ✅ |
| `IPHONEOS_DEPLOYMENT_TARGET = 26.4;` | 0 | 4 | **4** | ✅ |
| `#available(iOS` in app source | 0 | 0 | **0** | ✅ |
| `@available(iOS` in app source | 0 | 0 | **0** | ✅ |
| `.swift` files changed | — | 0 | **0** | ✅ |
| entitlements / scheme / Info.plist changed | — | 0 | **0** | ✅ |
| `phase-5-a2-baseline-acceptance.md` | — | untouched | **untouched** | ✅ |
| Debug build | — | clean | **BUILD SUCCEEDED** | ✅ |
| Release build | — | clean | **BUILD SUCCEEDED** | ✅ |
| `MOTIVOTests` | 86 / 0 | pass | **86 passed, 0 failed, TEST SUCCEEDED** | ✅ |

**Resolved build settings — the check that matters, since the app target's value
is inherited in places. All six read `26.4`:**

| target | Debug | Release |
|---|---|---|
| `MOTIVO` (app) | **26.4** | **26.4** |
| `MOTIVOTests` | **26.4** | **26.4** |
| `MOTIVOUITests` | **26.4** (inherited) | **26.4** (inherited) |

**The diff is exactly 4 changed lines in `project.pbxproj`** — 4 insertions, 4
deletions, all the same literal — plus two operative documentation references.

## 2. THE WARNING DELTA — the prediction most likely to be wrong, and it HELD

P5-A2's equivalent prediction was falsified (17 kinds → 24). This one was not.

| | before (26.2) | after (26.4) |
|---|---|---|
| distinct warning kinds | **25** | **25** |
| **new kinds** | — | **0** |
| kinds eliminated | — | **0** |

**Method, not the guess, is what makes this evidence:** the pre-change and
post-change trees were each built **clean, Debug and Release, into their own
derived-data path**, warnings extracted and normalised (quoted symbols and
integers collapsed), and the distinct kinds diffed. **Zero new, zero eliminated.**

**So no classification of new warnings was required** — because there were none.

## 3. DEVICE COMPATIBILITY — measured, not assumed

| device | model | iOS | ≥ 26.4 |
|---|---|---|---|
| **Device A** — SD beta burner | iPhone 16e | **26.6.1** | ✅ |
| **Device B** — SD iPhone | iPhone 17 Pro | **26.6.1** | ✅ |

Read from `devicectl`. Samuel's iPad is 26.3.1 and is **irrelevant**: Études is
iPhone-only (`TARGETED_DEVICE_FAMILY = 1`).

## 4. AN OBSERVATION THAT IS NOT A REGRESSION, RECORDED RATHER THAN GLOSSED

**`SessionRefreshPolicyTests.testStillValidTokenDoesNotRefresh()` did not execute
in either controlled full-suite run**, before or after. It executed and passed in
an earlier full run (87 unique names), and **passes when run in isolation, twice**.

**It is NOT caused by this unit:** the before and after runs have **identical test
name sets** (86 each), so the change is scored like-for-like.

**What it is:** an intermittent non-execution in full-suite runs — a **reporting
or scheduling** effect, not a failure. **It is a coverage question with no owner
yet**, and it should not be forgotten merely because it is green: a test that
sometimes does not run is indistinguishable from a passing one in a summary count.

## 5. WHAT THIS UNIT DELIBERATELY DID NOT DO

- **No `isEligibleForAgeFeatures`, no `requiredRegulatoryFeatures`, no
  PermissionKit, no significant-change handling, no regulatory behaviour.**
  Verified: zero references in the source.
- **No change to the age architecture.** Establishment and the 13-17 protections
  remain **unconditional and globally uniform**; register §O2 governs.
- **26.4, not 26.5** — 26.5 adds only `AgeRangeDeclaration.confirmed`, assurance
  provenance Études deliberately never reads.

## 6. RATIONALE, RECORDED PERMANENTLY

**Pre-launch is the lowest-cost opportunity to establish the 26.4 floor, because
Études has no public installed base that can be stranded. Raising the floor later
remains possible, but could exclude existing users or devices from future
versions.**

**The rationale is prospective simplification:** if a concrete future obligation
requires the 26.4 regulatory APIs, **all supported installations can use them
without introducing OS-availability branching into child-safety or regulatory
code.** **It changes no current legal conclusion and enables no new behaviour
today.**
