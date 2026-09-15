# C-101 — U2c's enclosing-function detector ignores nesting. Prediction, before any change

2026-09-14. **Test instrument only.** Scope approved in Codex scope review 002
(coordination folder), with its fixture clarification. No `BackendShim.swift`
implementation edit, no other assertion or pin changed, no backend reset, no full
app suite. No deployment, push or commit.

## 1. The failure (measured)

`supabase/tests/p4/u2c-acceptance.sh`: **18 passed / 2 failed** — independently
reproduced by Codex. **U2c-2** (`uploadStorageObject\(from:`) and **U2c-4**
(`loadIncludedAttachments\(for:`) expect enclosing function `uploadPost` and get
`discardTemporaries`.

**Cause.** `enclosing()` strips comments by regex, finds the Nth match, then scans
**backwards to the nearest `func <name>` line**, ignoring brace depth. In
`MOTIVO/BackendShim.swift` (sha256 `9a111af3b467c07a30f721ee6c56dcde038121aea64bcc7aa8c1176aad2deac2`),
`uploadPost` opens at 956, C-65's nested `func discardTemporaries()` is at 981, and
the call sites follow at 989 and 1145. **Both call sites are inside `uploadPost`'s
body; the instrument is wrong, not the code.**

## 2. The change

- `supabase/tests/p4/u2c_enclosing.py` (new): the detector.
  1. **Mask non-code** with a character scanner — line comments, block comments
     (nested, depth-counted), `"…"` strings with escapes, `"""…"""` strings —
     replacing each masked character with a space and keeping every newline, so
     offsets and line numbers are preserved.
  2. **Scope stack by brace depth** over masked text: `func <name>` sets a pending
     name that the next `{` consumes; any other declaration keyword or `}` first
     discards it, so a body-less protocol requirement never captures a later
     brace.
  3. **Report the OUTERMOST enclosing function** at the Nth pattern match;
     `<none>` when the match is in no function, `<not-found>` when there is no Nth
     match.
- `supabase/tests/p4/u2c-acceptance.sh`: **only the body of `enclosing()`** now calls
  the module. U2c-2/U2c-4 keep their patterns and expected owner `uploadPost`.
- `supabase/tests/p4/u2c-detector-selftest.sh` (new): the controls below.

**Heuristic limitation, stated accurately:** a string literal is masked whole,
**including any `\( … )` interpolation**. Interpolation can contain executable
expressions (and closures), so masking it hides code inside it. The detector does
not model that, nor `#if` branches with unbalanced braces, nor a closure default
value inside a function signature. It is a bounded source-inspection heuristic,
not a Swift parser, and the privacy guarantee is exactly U2c's assertions plus
these fixtures — no broader.

## 3. Fixture discipline (from the scope review)

Every negative fixture is a disposable **copy** of `BackendShim.swift` in a temp
directory. It **replaces only the original call expression** with a placeholder —
`loadIncludedAttachments(for: sessionID)` → `[LocalAttachmentUpload]()`, so
`for item in … {` keeps its brace; the upload call → `c101Placeholder()` — and
inserts **one balanced statement** containing the protected call at its
destination. Each fixture asserts: the replaced expression occurred exactly once;
the destination anchor occurred exactly once; **exactly one live protected call**
remains (a pattern match not preceded by `func`); the Nth match U2c uses is that
call; the **expected destination scope is present**; and the masked copy's
**brace balance is valid** (never negative, ends at zero).

**Placement deviation from the scope, recorded.** U2c takes the FIRST textual
match, and each protected function's declaration also matches its pattern
(`loadIncludedAttachments` at 1279, `uploadStorageObject` at 1433). A destination
after a declaration would make U2c's comparison fail on the declaration — for the
wrong reason. So every destination precedes both declarations: **NEG-·1** a
sibling method inserted after `uploadPost` closes (before
`private struct PreparedAttachmentUpload`); **NEG-·2** a top-level free function
inserted before `public final class HTTPBackendPublishService`; **NEG-·3** a helper
nested inside `deleteFollowRow` (868, `HTTPBackendFollowService`) — instead of the
scope's "method around line 1910", which lies after both declarations.

## 4. Predictions

**U2c, by id:** before 18/2 (U2c-2, U2c-4 FAIL → `discardTemporaries`); **after
20/0** — U2c-2 and U2c-4 PASS, every other id's result unchanged.

**Self-test:**

| ID | Input | Predicted |
|---|---|---|
| OLD-S / OLD-L | the pre-C-101 helper on the real file | `discardTemporaries` (documents the defect) |
| POS-1 / POS-2 | new detector on the real file | `uploadPost` |
| POS-3 | call inside a helper nested two levels inside `uploadPost` | `uploadPost` |
| POS-4 | protocol requirement `func uploadPost` + `var … { get }`, then `realOwner()` holding the call | `realOwner` |
| DEC-1 | call text and unbalanced `{` in `//` and nested `/* /* */ */` comments inside `other()`, before `realOwner()` | `realOwner` |
| DEC-2 | `"{ } // func fake() {"` and a `"""` block with `func fake() {` and `{{` inside `other()`, before `realOwner()` | `realOwner` |
| DEC-3 | the pattern only inside a string literal | `<not-found>` |
| NONE-1 | the call at file scope, in no function | `<none>` |
| NEG-S1 / NEG-L1 | call moved to sibling `c101MovedOut()` | `c101MovedOut`; U2c comparison FAILS |
| NEG-S2 / NEG-L2 | call moved to free `c101FreeFunction()` | `c101FreeFunction`; U2c comparison FAILS |
| NEG-S3 / NEG-L3 | call moved to a helper nested in `deleteFollowRow` | `deleteFollowRow`; U2c comparison FAILS |

Plus each NEG fixture's structural assertions (§3), and **`BackendShim.swift` sha256
identical before and after** the self-test and U2c runs.

Any miss is recorded as a miss and diagnosed before a further run.

## 5. Results (2026-09-14) — every prediction met, no miss

Evidence: `/Users/samueldixon/Documents/Codex/2026-09-12/a/outputs/Etudes-Claude-Codex-overnight-2026-09-14/claude-evidence/c101/` (`before/`, `after/`).

| Check | Before | After |
|---|---|---|
| `u2c-acceptance.sh` | 18 passed / 2 failed (U2c-2, U2c-4 → `discardTemporaries`) | **20 passed / 0 failed** — the by-id diff shows **only U2c-2 and U2c-4** moved FAIL → PASS |
| `u2c-detector-selftest.sh` | — | **54 passed / 0 failed** |
| `MOTIVO/BackendShim.swift` sha256 | `9a111af3…` | `9a111af3…` **identical** (also asserted inside the self-test, GUARD) |

Self-test detail: OLD-S/OLD-L `discardTemporaries` (defect documented); POS-0 real
file balances; POS-1/POS-2 `uploadPost`; POS-3 `uploadPost`; POS-4 `realOwner`;
DEC-1/DEC-2 `realOwner`; DEC-3 `<not-found>`; NONE-1 `<none>`. **Each of the six
negative fixtures** passed all seven checks — expression once, anchor once, one
live call, first match is that call, braces balance, destination reported
(`c101MovedOut` / `c101FreeFunction` / `deleteFollowRow`) — and **U2c's own
comparison FAILED on every one**, so the corrected detector still catches a
protected call moved outside `uploadPost`.

The `u2c-acceptance.sh` diff is confined to the `enclosing()` helper (8 insertions,
18 deletions); no assertion, expected value or historical pin changed.
