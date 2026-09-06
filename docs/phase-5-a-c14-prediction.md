# P5-A / C-14 — PREDICTION AND DISCRIMINATOR. 2026-09-06

**COMMITTED BEFORE ANY MUTATION. `MOTIVO/FollowStore.swift` is UNCHANGED at
this commit.** The measurement that scoped this unit is
`docs/phase-5-a-c14-measurement.md`.

**Scope, as accepted: the measured 8-site `FollowStore` fix ONLY.**
`AuthManager` and the rest of the `NSLog` population are deliberately untouched.

---

## 1. THE DISCRIMINATOR

`scripts/c14-discriminator.py`, run from the repository root. It is
**re-runnable** and it is a **discriminator, not a checker**: it is built to
produce a *different, predicted* result before and after the fix, so a run that
cannot tell the two apart is a failed instrument rather than a pass.

It lives outside `MOTIVO/`, so the `fileSystemSynchronizedGroups` root group
cannot compile it into the app target.

### Detection rules, declared rather than buried in a regex

- **DEBUG-only** = inside a `#if DEBUG` region; the `#else` branch of such a
  region counts as **shipping**.
- **Identifier argument** — two match rules, because one was not enough:
  - `NAMED_IDENT_ARGS` (`targetUserID`, `requesterUserID`, `displayName`,
    `handle`, `email`, …) match as a token anywhere in the expression;
  - `EXACT_IDENT_ARGS` (`id`) must be the **whole** argument expression.
- **`ownerKey` is an explicitly DECLARED EXCLUSION**, counted separately as
  **A3b** and **not fixed by this unit**. Its only writer,
  `PublishService.setOwnerKey`, has only DEBUG-only callers, so in Release
  `ownerKey` resolves to its literal fallback `"local-device"`. The exclusion is
  visible in the output, not silent.

### The detector was wrong on its first run, and running it is what found that

The first version put `id` in the token-matched set. It reported **A3a = 15**,
flagging `payload.id.uuidString` in `SessionSyncQueue` and `PublishService` —
which are **post** identifiers, not user identifiers, and outside C-14 entirely.
The rule was split into token-match and whole-expression-match and the count
fell to the correct **8**.

**A detector broad enough to be safe was broad enough to be wrong**, and no
amount of reading it would have shown that; only running it against real source
did. It is recorded because the same shape — a check that passes by flagging
things it should not — is how a green gate stops meaning anything.

---

## 2. MEASURED PRE-FIX STATE, AND THE PREDICTED POST-FIX STATE

**The PRE column is measured at this commit, not predicted.** It is what
establishes, against pre-fix code, that the eight targeted calls really do carry
the backend-user identifier argument.

| # | assertion | PRE (measured) | POST (predicted) |
|---|---|---|---|
| **A1** | targeted `FollowStore` sites passing an identifier argument | **8** | **0** |
| **A2** | targeted diagnostic events still present | **8** | **8** |
| **A3a** | SHIPPING sites passing a backend user ID / handle / name / email | **8** | **0** |
| **A3b** | SHIPPING sites passing `ownerKey` (declared exclusion) | **2** | **2** |
| **A4** | DEBUG-only `NSLog` sites | **43** | **43** |
| **A5** | SHIPPING `NSLog` call sites, total | **60** | **60** |

### What each assertion is for

- **A1 → 0** and **A3a → 0**: the identifier argument is gone, both at the eight
  targeted sites and anywhere else in the shipping surface.
- **A2 stays 8**: **the diagnostic event REMAINS.** This is the assertion that
  forbids "fixing" C-14 by deleting the logging.
- **A5 stays 60**: the same guard at whole-file scope. A5 falling to 52 would
  mean the events were removed, not redacted — a different change that happens
  to score zero on A1.
- **A4 stays 43**: **DEBUG-only logging is unchanged.** The fix must not reach
  into the Debug diagnostics, which are not a C-14 exposure and are load-bearing
  for development.
- **A3b stays 2**: the declared exclusion is still declared and still excluded —
  it did not silently get fixed, and it did not silently grow.

### The eight targeted sites

`MOTIVO/FollowStore.swift` lines **201, 224, 256, 290, 316** (real-UI,
local-simulation branch) and **368, 382, 393** (`simulate*`, DEBUG-only callers).

---

## 3. PREDICTED CHANGE SHAPE

- **Exactly one file changes: `MOTIVO/FollowStore.swift`.** Eight lines.
- Each `%@` format specifier is removed **together with** its argument. A `%@`
  left behind with no argument would be a format-string defect, so the two must
  move as one.
- The replacement text keeps the event name and its direction marker and
  substitutes a literal `<redacted>` — which contains no `%`, so it cannot
  itself be interpreted as a format specifier.
- **No behavioural change.** `NSLog` has no return value in use at any of the
  eight sites; every one is a bare statement.

## 4. BUILD PREDICTION

**Debug and Release both compile clean, 0 errors.** CLAUDE.md's standing rule is
that Release is verified as well as Debug, and this file is compiled into both.
