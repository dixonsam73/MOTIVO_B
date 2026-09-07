# P5-A2 — iOS 26.2 PRODUCT BASELINE: ACCEPTANCE. 2026-09-07

**COMPLETE.** Études now requires **iOS 26.2 for the entire app, including Solo**.
Prediction: `docs/phase-5-a2-baseline-prediction.md` (`89689e9`, sources provably
unchanged there).

---

## 1. RESULT

| measure | before | predicted | **actual** | |
|---|---|---|---|---|
| `IPHONEOS_DEPLOYMENT_TARGET = 18.5;` | 4 | 0 | **0** | ✅ |
| `IPHONEOS_DEPLOYMENT_TARGET = 26.2;` | 0 | 4 | **4** | ✅ |
| `#available(iOS` in app source | 1 | 0 | **0** | ✅ |
| `@available(iOS` in app source | 0 | 0 | **0** | ✅ |
| `presentActivityVC` references | 2 | 0 | **0** | ✅ |
| Debug / Release build | — | clean | **clean, 0 errors** | ✅ |
| `MOTIVOTests` | — | runs | **49 tests, 0 failures** | ✅ |

**Resolved build settings — the check that matters, since the app target has no
literal to grep. All six read `26.2`:**

| target | Debug | Release |
|---|---|---|
| `MOTIVO` (app) | **26.2** | **26.2** |
| `MOTIVOTests` | **26.2** | **26.2** |
| `MOTIVOUITests` | **26.2** (inherited) | **26.2** (inherited) |

## 2. THE PREDICTION WAS FALSIFIED ON ONE POINT: NEW WARNINGS

**I predicted "no new warnings". That was WRONG, and it was wrong by exactly the
mechanism the impact assessment named as a risk.**

Measured by building the **pre-change tree at `89689e9`** and the changed tree
**both clean, with separate derived-data paths**, then diffing normalised warning
signatures:

| | baseline (18.5) | after (26.2) |
|---|---|---|
| distinct warning kinds | **17** | **24** |
| **new kinds** | — | **7** |
| kinds eliminated | — | **0** |

**All 7 new kinds are deprecations, and every one is `deprecated in iOS 26.0`** —
50 occurrences across 15 files:

| API family | examples |
|---|---|
| **AVFoundation** | `AVVideoComposition` / `…Instruction` / `…LayerInstruction` → `.Configuration` |
| **UIKit** | `UIScreen` via context, `effectiveGeometry.interfaceOrientation`, `init(windowScene:)` |
| **SwiftUI** | `Text` string interpolation |

Heaviest: `MediaTrimView` 10, `CommentsView` 8, `MeView` 6, `AboutEtudesView` 4.

**Why it happens, stated so it is not mistaken for a regression:** at an 18.5
floor an API deprecated in 26.0 emits nothing, because the app might still run on
a system where it is current. At a 26.2 floor it always warns. **The code did not
change; the floor did.** No behaviour changed and no error was introduced.

**They are NOT fixed here, deliberately.** CLAUDE.md already carries a Phase 6
*"AVFoundation deprecation sweep"*, and these are its population plus a UIKit and
a SwiftUI class. **Fixing 7 deprecation families inside a baseline unit would be
scope creep into a phase that already owns the work.** Recorded as a measured
consequence and handed to Phase 6.

**My first count was also misleading and is corrected:** an incremental build
reported 179 warnings against the baseline's 489, which looked like a large
*reduction*. **The builds were not comparable** — one incremental, one clean. Both
clean, the honest comparison is 17 → 24 distinct kinds. **A raw warning count
across differently-configured builds measures the build, not the code.**

## 3. THE `#available` BRANCH, AND A CHECK THAT DEFEATED ITSELF

`DebugViewerView`'s `ShareButton` collapsed to its `ShareLink` branch;
`presentActivityVC` removed with the `else` that was its only caller. **Effective
behaviour is unchanged** — the fallback was unreachable on every device Études
has ever run on. The outer `#if canImport(UIKit)` is **retained**: a platform
condition, not a version condition.

**My replacement comment quoted the availability syntax verbatim, and the
acceptance check greps for exactly that string** — so the measure read **1**
where it should have read 0. **The comment explaining the rule defeated the check
for the rule**, which is `U5c-34` and `U5d` a third time, and the C-14 detector a
fourth. The comment now names the construct without writing it, and says why.

## 4. TESTS — RUN, NOT COMPILED, AND MY PARSER WAS WRONG FIRST

**49 distinct tests, 0 failures** — 34 XCTest and 15 swift-testing.

**`** TEST SUCCEEDED **` was NOT accepted as evidence.** C-54's lesson is that
this target was compile-clean and un-runnable for months. On first parse I
extracted **0 test cases** — the C-54 signature exactly.

**It was my parser.** Xcode 26 reports as `Test case 'X' passed on 'Clone 1 of
iPhone 17 Pro'`, a parallel-clone format; my regex expected the older
`Test Case '-[Class method]'`. **A verification whose instrument is stale
produces the same output as the failure it is looking for**, and the only way to
tell them apart was to read the log rather than trust the parse.

**CLAUDE.md's "7 passing tests" was stale** — true at U5e, and the suite has since
grown to 49. Corrected in the same edit as the deployment target, since both sit
in the Environment section. **Flagged rather than silent: this was not part of
the requested scope.**

## 5. DEVICES — BOTH REMAIN VALID

Re-confirmed **after** the change, not carried from the assessment:

| device | model | iOS | ≥ 26.2 |
|---|---|---|---|
| **Device A** — SD beta burner | iPhone 16e | **26.6.1** | **yes** |
| **Device B** — SD iPhone | iPhone 17 Pro | **26.6.1** | **yes** |

Both remain valid installation and test targets. The simulator used for the test
run was an iPhone 17 Pro clone on the iOS 26.x runtime.

## 6. DOCUMENTATION

- **CP-OS-1 preserved and marked SUPERSEDED**, with its reasoning explicitly
  retained — below 26 `activeParentalControls` cannot be read and reconciliation
  cannot run, which is *why* an app-wide floor is coherent.
- **S-B9 / S-B9b RETIRED as impossible** — struck through and labelled
  unreachable, **not** left skipped or failing.
- **CP-OS-1's billing edge dissolved**, removed from the P5-G list.
- **CP-3's `@available(iOS 26.0, *)` gating removed** from the client delta.
- **§11.5 rig precondition closed as MET.**
- `CLAUDE.md` Environment: **18.5 → 26.2**, with the Solo-included split withdrawn.

## 7. UNTOUCHED

**CP-0 and CP-1 architecture unchanged** — no production object was read or
written by this unit. **`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` not
bundled**, as instructed.

## 8. STATUS

**P5-A2 complete. CP-2 / P5-E NOT started.**
