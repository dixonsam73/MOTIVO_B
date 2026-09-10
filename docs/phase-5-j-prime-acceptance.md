# P5-J′ — COMPLETE. C-6 · C-16 · C-20 · C-21. NO DEVICE ACCEPTANCE REQUIRED.

Prediction: `docs/phase-5-j-prime-prediction.md`, committed at `f00de97` **before
mutation**; its C-6 test correction at `6c3d60d`, also before any production
change. **C-80, the P5-K′ remainder and C-81's implementation were not touched.**
No production, ASC, enforcement or age-state mutation.

## 1. Dispositions

| Row | Disposition | Evidence |
|---|---|---|
| **C-6** | **CLOSED — accepted fail-closed behaviour under the current architecture; migration compatibility moved to release-time verification** | `StoreMigrationCompatibilityTests`: all **10** shipped model versions **positively observed** to migrate under production's options; positive control refuses a non-inferable change. **Empty stores only** — does not prove every populated-data case |
| **C-16** | **FIXED** — `URL.applicationSupportDirectory`, no `try!` | Path test: queue file URL identical to the old derivation; guard: no `try!` in app source |
| **C-20** | **FIXED** — redundant `performAndWait` wrapper removed; **the 2026-09-09 demotion was wrong** | Both diagnostics gone from both configurations; premises tested: `AuthManager` is `@MainActor`, `viewContext` is `.mainQueueConcurrencyType` |
| **C-21** | **CLOSED AS REFUTED** — no status check was dropped | Each binding was followed by the real `http.statusCode` check; the three dead bindings were deleted as **incidental warning cleanup, not as the fix** |
| **C-81** | **FILED, not fixed** | Compile-time only; see the register |

## 2. Predictions scored

| | Prediction | Outcome |
|---|---|---|
| **J1** | pre-change: two guards fail, two premises pass, migration passes for all versions | **Guards and premises MET.** Migration: **the inventory assertion failed — 10 found, 11 predicted.** My miscount (`MOTIVO V9.omo` is Xcode's optimised copy of V9). **No version failed to migrate.** Recorded under J1 without rewriting it |
| **J1′** | after tightening: positive observation of all 10 + a control that must refuse | **MET on the unchanged production source** — 2 of 2 |
| **J2** | all new tests pass; queue path identical | **MET** |
| **J3** | Debug 187 → **177**, Release 175 → **165**; no new warning; C-81 unchanged | **MET EXACTLY** — the warning-set diff against the morning's clean baseline is **precisely the 10 predicted lines removed** in each configuration, nothing added, C-81's lines unchanged |
| **J4** | 213 → corrected to 214 | **215 declared, 215 passed**, structured census, nothing missing. **Second arithmetic error, also mine:** C-20 has **three** tests (guard + two premises), not two. 208 + 2 (C-6) + 2 (C-16) + 3 (C-20) = 215 |
| **J5** | no device acceptance | **Holds** — every property here is compile-time, path identity, or a simulator-run migration test |

## 3. What this unit leaves behind

- **New warning baseline: Debug 177 / Release 165.**
- **C-6's residual, stated so it is not overread:** a populated store could still
  fail a migration that an empty store passes — for example an attribute made
  non-optional over existing nils. The trap remains fail-closed; nothing here
  makes store loading recoverable, and the 66-call-site recovery design stays
  out of scope.
- **The test's inventory assertion is deliberate friction:** adding an 11th
  model version fails it until someone confirms the new version is covered.
- **C-81** is open, P3, compile-time only.

## 4. Lessons worth keeping

**The positive control mattered more than the passing test.** "No version
failed" was true before the control existed, and would have been equally true
of a harness that could never fail. Absence of failure was not accepted as
evidence.

**Two predictions were wrong on arithmetic, and both were caught by structured
measurement rather than review** — the inventory assertion and the census. The
dispositions did not change, and neither was forced to fit.

**C-20's demotion was a record defect of the usual shape** — a claim ("the
premise does not reproduce") checked by reading the class declaration rather
than by asking the compiler, which reported the site the whole time.
