# P5-A2 — iOS 26.2 PRODUCT BASELINE: PREDICTION. 2026-09-07

**COMMITTED BEFORE MUTATION. `project.pbxproj` and `DebugViewerView.swift` are
UNCHANGED at this commit.** Impact assessment: `docs/phase-5-os-baseline-impact.md`.

**Settled rationale: this is a capability / product / test invariant, NOT a
source-code simplification.** Études is pre-release, both physical devices are
already on 26.6.1, and the whole app — **including Solo** — will require 26.2+.

---

## 1. THE FOUR OCCURRENCES, MECHANICALLY ENUMERATED

Derived by parsing `XCBuildConfiguration` blocks, not by eye:

| # | line | configuration | owner | current |
|---|---|---|---|---|
| 1 | **377** | `Debug` | **PROJECT-LEVEL** | `IPHONEOS_DEPLOYMENT_TARGET = 18.5;` |
| 2 | **436** | `Release` | **PROJECT-LEVEL** | `IPHONEOS_DEPLOYMENT_TARGET = 18.5;` |
| 3 | **533** | `Debug` | `com.MOTIVOTests` | `IPHONEOS_DEPLOYMENT_TARGET = 18.5;` |
| 4 | **552** | `Release` | `com.MOTIVOTests` | `IPHONEOS_DEPLOYMENT_TARGET = 18.5;` |

**The app target and `MOTIVOUITests` carry NO explicit setting and inherit the
project-level value** — which is why editing 1 and 2 moves the shipping product,
and why 3 and 4 must move too or the unit-test target would keep a **lower floor
than its host app**.

**Mechanically checkable:** `grep -c 'IPHONEOS_DEPLOYMENT_TARGET = 18.5;'` is
**4** before and **0** after; `= 26.2;` is **0** before and **4** after.

## 2. THE `#available` BRANCH

`MOTIVO/DebugViewerView.swift`, `fileprivate struct ShareButton` — the **only**
availability branch in the app source, itself inside a `#if DEBUG` file:

```swift
if #available(iOS 16.0, *) {
    ShareLink(item: content) { Image(systemName: "square.and.arrow.up") }
} else {
    Button { presentActivityVC(text: content) } label: { … }
}
```

**At a 26.2 floor the `ShareLink` branch is the only reachable one**, so
collapsing to it **preserves effective behaviour exactly** — the `else` has been
unreachable on every device Études has ever run on.

**`presentActivityVC(text:)` has exactly ONE caller — the `else` branch being
removed** (`:1191` calls, `:1202` defines). It therefore becomes dead with the
branch and is removed **with** it, along with its now-empty
`#if canImport(UIKit)` wrapper. **That is a consequence of the change, not
scope creep**; leaving an uncalled `UIActivityViewController` helper behind would
be residue whose only purpose was the branch that no longer exists.

**The outer `#if canImport(UIKit)` / `#else` on `body` is RETAINED.** It is a
platform condition, not a version condition, and this unit does not touch it.

## 3. PREDICTED DELTA

| measure | before | **after** |
|---|---|---|
| `IPHONEOS_DEPLOYMENT_TARGET = 18.5;` in pbxproj | **4** | **0** |
| `IPHONEOS_DEPLOYMENT_TARGET = 26.2;` in pbxproj | **0** | **4** |
| `#available(iOS` in app source | **1** | **0** |
| `@available(iOS` in app source | **0** | **0** |
| `presentActivityVC` references | **2** | **0** |
| files changed | — | **2** + docs |

**Resolved build settings — the check that matters, because the app target has
no literal to grep:**

| target | configuration | predicted resolved value |
|---|---|---|
| `MOTIVO` (app) | Debug | **26.2** |
| `MOTIVO` (app) | Release | **26.2** |
| `MOTIVOTests` | Debug | **26.2** |
| `MOTIVOTests` | Release | **26.2** |
| `MOTIVOUITests` | Debug | **26.2** (inherited) |

## 4. BUILD AND TEST PREDICTION

- **Debug and Release both compile clean, 0 errors, and NO NEW WARNINGS.** The
  "condition is always true" warning that keeping the branch would introduce is
  the specific thing §2 avoids.
- **`MOTIVOTests` RUNS and passes its 7 tests** — executed, not merely compiled.
  **C-54's lesson is why this is a prediction rather than an afterthought:** that
  target was compile-clean and un-runnable for months because nobody executed it,
  and its second defect hid behind its first.
- **SPM resolution is unchanged.** All ten pins are minimum versions; raising our
  floor cannot conflict. AudioKit is a build-time observation, not a risk.

## 5. DEVICE VALIDITY

| device | model | iOS | ≥ 26.2 |
|---|---|---|---|
| **Device A** — SD beta burner | iPhone 16e | **26.6.1** | **yes** |
| **Device B** — SD iPhone | iPhone 17 Pro | **26.6.1** | **yes** |

**Both remain valid installation and test targets**, to be re-confirmed after the
change rather than assumed from this table.

## 6. DOCUMENTATION CHANGES

- **CP-OS-1 preserved historically, marked SUPERSEDED** by the app-wide floor.
  **Its reasoning is retained** — below 26 `activeParentalControls` cannot be
  read and reconciliation cannot run — because that is *why* an app-wide floor is
  coherent rather than merely convenient.
- **S-B9 / S-B9b RETIRED as impossible**, not left failing or skipped. Both
  require a pre-26 device, which no supported configuration can produce.
- **CP-OS-1's billing edge dissolved** and removed from the P5-G list.
- **CP-3's planned `@available(iOS 26.0, *)` gating removed** from the client
  delta.
- **§11.5's rig precondition closed as MET.**
- `CLAUDE.md` Environment: deployment target **18.5 → 26.2**.

## 7. OUT OF SCOPE

- **CP-0 and CP-1 architecture untouched.** No production object is read or
  written by this unit.
- **`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` deliberately NOT bundled**,
  though editing project settings is a natural moment for them.

## 8. STATUS

**NOTHING CHANGED AT THIS COMMIT.**
