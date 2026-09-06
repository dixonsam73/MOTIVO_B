# P5-A / C-14 — ACCEPTANCE. 2026-09-06

**COMPLETE. All six assertions match the predicted POST column exactly.**
Prediction: `docs/phase-5-a-c14-prediction.md` (committed at `7a087e2`, with
`FollowStore.swift` provably unchanged). Measurement:
`docs/phase-5-a-c14-measurement.md`.

**Scope delivered, as accepted: the measured 8-site `FollowStore` fix only.**
`AuthManager` and the remaining `NSLog` population are untouched.

---

## 1. RESULT

| # | assertion | PRE | predicted POST | **actual POST** | |
|---|---|---|---|---|---|
| **A1** | targeted sites passing an identifier argument | 8 | 0 | **0** | ✅ |
| **A2** | targeted diagnostic events still present | 8 | 8 | **8** | ✅ |
| **A3a** | SHIPPING sites passing a user ID / handle / name / email | 8 | 0 | **0** | ✅ |
| **A3b** | SHIPPING sites passing `ownerKey` (declared exclusion) | 2 | 2 | **2** | ✅ |
| **A4** | DEBUG-only `NSLog` sites | 43 | 43 | **43** | ✅ |
| **A5** | SHIPPING `NSLog` call sites, total | 60 | 60 | **60** | ✅ |

**The four requested properties are each carried by a named assertion:** the
diagnostic event remains (**A2**, reinforced by **A5** at file scope), the
identifier argument is gone (**A1**), no shipping site logs a backend user ID,
handle, display name or email (**A3a**), and DEBUG-only logging is unchanged
(**A4**).

**Change shape as predicted:** one file, `MOTIVO/FollowStore.swift`, eight lines
plus a header block. Each `%@` was removed together with its argument; the
replacement literal `<redacted>` contains no `%`.

**Debug and Release both compile clean, 0 errors**, as predicted.

---

## 2. THE DISCRIMINATOR IS PROVEN NON-VACUOUS

**The final detector was re-run against PRE-FIX code in a detached worktree at
`7a087e2` and returned A1 = 8, A3a = 8.** That matters more than the post-fix
zeros: it establishes that these assertions **fail against pre-fix code**, so
the zeros mean something. A check that cannot fail is not evidence.

The PRE column in the prediction was originally measured with an earlier
revision of the detector. **It was re-established with the final one** rather
than carried forward, because a prediction scored by a different instrument than
the one that measured it is not scored at all.

---

## 3. VERIFIED IN THE BUILT ARTEFACT, NOT ONLY THE TREE

Source assertions cannot see what the compiler emitted, so the Release binary
was read directly:

- **All eight events are present** as format strings.
- **Not one of them carries `%@`.** Every remaining `%@` under `[FollowStore]`
  belongs to a `backend … failed:` error log.
- **`<redacted>` is present.**
- **`debugReload` is ABSENT.** That string exists only inside `#if DEBUG` in
  `FollowStore.swift`, so its absence is an **empirical confirmation of the
  DEBUG-gating analysis in the artefact itself** — the same analysis A4 and the
  whole measurement rest on. It was not predicted and is recorded as a free
  corroboration.

---

## 4. THE DETECTOR WAS WRONG TWICE, IN OPPOSITE DIRECTIONS

**Both were found by running it, neither by reading it, and the second was found
only because the tree was cross-checked with a raw `grep` instead of trusting
the script.**

1. **False positives.** A bare token match on `id` flagged
   `payload.id.uuidString` — a **post** id — reporting **A3a = 15**. Fixed by
   requiring `id` to be the *whole* argument expression.
2. **A false negative, then more false positives.** A fixed token list missed
   `currentUserID` at `FollowStore:415`. Generalising to a pattern then matched
   `uuidString` via an unanchored `uid`, taking A3a back to **13**. Fixed by
   anchoring the pattern to a whole token.

**`FollowStore:415` turned out to be inside `#if DEBUG` (410–417), so nothing
shipping was ever missed** — but the detector could not have told us that, and
that is the point. **A gate is only as good as its worst blind spot, and the
blind spot was invisible from the gate's own green result.**

## 5. WHAT THIS UNIT DOES NOT CLAIM

- **No device verification.** The fix is a source change verified by assertion,
  build and binary inspection. No on-device log capture was performed.
- **The redaction behaviour of `%@` is inherited evidence**, taken from this
  project's earlier recorded TestFlight measurement, and **was not re-measured**
  here. It is background to *why* C-14 was P3 rather than higher; the fix does
  not depend on it.
- **`ownerKey` (A3b) is not fixed** and remains a declared exclusion.
- **`PublishService:294` is not fixed.** It logs a session **title** in Release —
  user content, not identity, outside C-14 as filed. It is now **C-62**,
  Unverified, investigation placed in **P5-L**.
