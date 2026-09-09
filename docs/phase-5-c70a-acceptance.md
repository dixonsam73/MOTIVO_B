# C-70(a) — ACCEPTANCE. A DIRECTORY FAILURE NO LONGER BLAMES THE ACCOUNT ID.

**Prediction:** `docs/phase-5-c70a-prediction.md`, committed at `50cec77`
**before** any product change. **Scope held:** `ProfileView.swift`, one new pure
file, one new test file. No backend, migration, production, ASC, enforcement,
device or age-state mutation.

## 1. Result against the committed prediction

| | Prediction | Outcome |
|---|---|---|
| **P1** | exactly two outcomes; collision copy verbatim | **MET** — `testCollisionKeepsItsOwnCopy` |
| **P2** | generic message names no field | **MET** — `testGenericCopyNamesNoField` checks all five field words |
| **P3** | decision moves to a pure type; helper relocated, not duplicated | **MET** — `DirectorySyncFailure`; zero second copy |
| **P4** | no behaviour change beyond the text | **MET by diff** — triggers, clearing and the red colour untouched |
| **P5** | rename `directorySyncMessage` / `directorySyncIsError` | **MET** — 10 sites, compiler-proven complete |
| **P6** | focused tests, Debug+Release, structured suite, zero warning delta | **MET** — see below |

**Builds:** Debug and Release both `BUILD SUCCEEDED`.
**Warning delta: ZERO** — 187 Debug / 175 Release, identical to `50cec77`
measured in an isolated worktree with its own derived data, rather than assumed.
**Suite: 130 of 130 passed**, structured census, `missing=none` on every named
suite. Console `passed` counts were not used.

## 2. Non-vacuity — the test can fail, and it was made to

Restoring the old string as the generic message failed **exactly** the two
load-bearing tests and nothing else:

```
testGenericCopyNamesNoField()                  failed
testNoNonCollisionFailureNamesTheAccountID()   failed
```

The assertion is the **absence of the defect** — no non-collision failure may
name the Account ID — not the presence of one particular replacement string.

## 3. What the inspection changed about the finding itself

C-70(a) was filed from one call site. The inspection found **five** entry points
into `syncDirectoryFromCurrentState()`, and **three never touch the Account ID**:
a `name` edit, a `location` edit, and the instrument manager closing. The defect
was therefore reachable from ordinary profile editing, not only from the Account
ID field — wider than filed, and the same shape as C-56 an hour earlier.

## 4. Deliberately not done

**Two further attributable errors exist and are not handled.**
`account_id_format` and `account_id_lowercase` are CHECK constraints that name
themselves on the wire, so field-aware attribution *is* cheaply available for
them. They are **unreachable through the shipping UI** — `normalizeAccountID`
sanitises the field and the caller sends `account_id` only at three characters
or more — so copy for them would be handling for a case nobody has observed.

**The message's PLACEMENT is unchanged.** A generic failure still renders
beneath the Account ID field. The text no longer *asserts* a false field; the
position still *hints* at one. Fixing that needs a second presentation surface
in `ProfileView` — the broad error-handling redesign this unit was told not to
attempt. **Named as a residual rather than absorbed into a claim of completion.**

**Not device-verified.** Source and simulator evidence only.
