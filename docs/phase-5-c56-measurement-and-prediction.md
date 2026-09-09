# C-56 — MEASUREMENT AND PREDICTION, COMMITTED BEFORE IMPLEMENTATION

**Unit:** P5 / C-56 — `PracticeTimerView` performs Core Data fetches from inside `body`.
**Measured at:** `8cc8e1c`, 2026-09-09, before any product mutation.
**Rule this file exists to satisfy:** the prediction is written down before the
code changes, so the acceptance is binary rather than a reading of the aftermath.

---

## 1. The census — what `body` actually reads, and it is MORE than the row said

C-56 was filed naming **one** function and **one** fetch pair. At HEAD the
body-reachable read set is **three Profile fetches and two unbounded Instrument
fetches per evaluation**, across **three** sites, not one.

| # | Body entry | Path | Reads | Guards |
|---|---|---|---|---|
| 1 | `body:1572` `if shouldRenderAppSetUpRoot` | `:1256` → `requiresAppSetUpNow()` `:1234` | `Profile` (`fetchLimit 1`, `:1244`) + `fetchInstruments()` (ALL instruments, sorted, `:3618`) | `isHomePresentation` short-circuits `&&`; and the `signedIn ∧ configured ∧ .existingAccount` early return |
| 2 | `body:1898` `.task(id: launchGateEvaluationKey)` | `:1276` → `appSetUpCompletenessKey` `:1212` | `Profile` (`fetchLimit 1`, `:1222`) + `fetchInstruments()` `:3618` | **NO presentation guard.** Only the same signed-in early return |
| 3 | `body:1601` `homeTopBar` | `:1325` → inline `initials` closure `:1357` | `Profile` (`fetchLimit 1`, `:1360`) | Only when no avatar image; inside the home region |

**Site 2 is the one the filed row missed, and it is the worse of the two.**
A `.task(id:)` key expression is evaluated **during body evaluation**, so the
fetch pair runs whether or not the task body ever executes — and unlike site 1
it carries **no `isHomePresentation` guard**, so it runs on every evaluation in
every presentation. **The fetches ARE the change detector**: the key is a string
built by reading Core Data, and the task re-fires when it changes.

**The early return is not the common case.** `requiresAppSetUpNow` and
`appSetUpCompletenessKey` return early only on
`auth.isSignedIn ∧ BackendConfig.isConfigured ∧ auth.backendBootstrapState == .existingAccount`.
**A Solo user never satisfies it**, and Solo is the default mode — so for the
ordinary user the fetches run on **every** body evaluation, not on an edge case.

---

## 2. The cost of one evaluation's read set — MEASURED

`MOTIVOTests/AppSetUpGateFetchCostTests.swift`, iPhone 17 Pro simulator (iOS
26.5), 2000 iterations per test, three runs, in-memory store, main actor.
The reported figure is XCTest's own test duration against a control that runs
the identical loop and store construction with the fetches removed.

| Fixture | Run 1 | Run 2 | Run 3 | Median | Per evaluation | Net of control |
|---|---|---|---|---|---|---|
| control, no fetches | 0.015 | 0.020 | 0.017 | **0.017 s** | 8.5 µs | — |
| 1 instrument | 0.265 | 0.378 | 0.264 | **0.265 s** | 132 µs | **≈124 µs** |
| 8 instruments | 0.286 | 0.297 | 0.291 | **0.291 s** | 146 µs | **≈137 µs** |
| 40 instruments | 0.385 | 0.378 | 0.359 | **0.378 s** | 189 µs | **≈181 µs** |

**≈125 µs fixed + ≈1.4 µs per instrument, on the main actor, per body
evaluation.**

**THIS IS A FLOOR, NOT A CEILING, AND MUST NEVER BE QUOTED AS DEVICE
EVIDENCE.** Three reasons, each pushing the real number up: the store is
in-memory at `/dev/null`, not device SQLite; the simulator runs on desktop
silicon; and the harness is a **transcription** of the statements, not an
evaluation of the view — it excludes SwiftUI's own overhead in reaching them.
**No claim is made about how often `body` is evaluated.** Nothing offline can
supply that term, and it is the term C-55 showed can be unbounded.

**What the number does and does not settle.** It confirms the row's own
disposition — **latent, not currently user-visible**: at a normal handful of
evaluations per second this is invisible, which is why C-55's two-guard fix took
the same screen to 0.1% with these fetches untouched. It also confirms why the
row was filed rather than ignored: **125 µs × an unbounded invalidation rate is
unbounded**, and under C-55's loop this function held 47 of 50 samples.

---

## 3. PREDICTION — committed before implementation

**P1.** The fix removes **all three** body-time Core Data read sites. After it,
a comment-stripped scan of `PracticeTimerView`'s body-reachable declarations
finds **zero** `viewContext.fetch` calls.

**P2.** The gate's *decisions* are unchanged. `requiresAppSetUpNow` continues to
return `true` for: no `Profile` row; a `Profile` with an empty/whitespace name;
a `Profile` with a name but no `Instrument` whose `profile` is that profile. It
continues to return `false` on the signed-in-existing-account early return, and
when name and instrument are both present. **No new state is invented and no
gate is loosened.**

**P3.** The AppSetUp gate still opens and closes at the same moments. In
particular, completing set-up must still reveal the timer without a relaunch —
so whatever replaces the body-time fetch must be invalidated by the same Core
Data writes that the current live read would have seen.

**P4.** `homeTopBar`'s initials fall back to the same string for the same
`Profile.name`, and to the same placeholder when no profile or no name exists.

**P5.** The structural control **fails against pre-fix HEAD**, naming the three
sites, and passes after. A control that cannot fail on `8cc8e1c` is vacuous and
is not evidence.

**P6.** Zero backend change, zero migration, zero production mutation, no change
to `PracticeTimerView`'s public behaviour beyond removing body-time I/O. **C-3
is NOT in scope** — it is the same file and a different mechanism (foreground
staged-video hydration), and this unit does not touch it.

### Anti-prediction — what would falsify the approach

If removing the body-time reads requires caching gate state in `@State` that is
refreshed by anything other than a Core Data change signal, **stop**: that
reintroduces the class of defect C-55 was, a view whose correctness depends on
somebody remembering to invalidate it. The gate must remain derived, not
mirrored.

---

## 4. Method note — why the measurement tests are not kept as assertions

`AppSetUpGateFetchCostTests` transcribes the **pre-fix** statements. Once the
fix lands, those statements no longer exist in the product, so a test asserting
"one evaluation issues three Profile fetches" would be asserting the shape of
the defect forever. The numbers are recorded above with the method, and the
file is recoverable from `8cc8e1c`; the durable gate is the structural control
of P1/P5, not the timing.
