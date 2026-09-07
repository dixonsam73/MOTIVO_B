# P5-E / CP-2 — LIVE IN PRODUCTION AND VERIFIED. 2026-09-07

**Child-privacy discovery and contact filtering are enforced server-side.**
Applied exactly the corrected `ca31fc3` design. **The binding invariant holds,
demonstrated rather than argued: `enforcement_enabled` relaxes entitlement
gating and does NOT relax age/privacy protection.**

---

## 1. THE BINDING INVARIANT, DEMONSTRATED

**With the kill switch flipped OFF inside a rolled-back transaction:**

| discriminator | result |
|---|---|
| **D14** — 13–17 opted out, enforcement **OFF** | **0 rows — NOT discoverable** |
| **D15** — 18+ opted out, enforcement **OFF** | **0 rows** |
| **D16** — no privacy row, `follow_requests_open`, enforcement **OFF** | **FALSE** |
| **D17** — 13–17 opted **IN**, enforcement **OFF** | **1 row — still discoverable** |
| **D17b** — 13–17 opted **IN**, requests, enforcement **OFF** | **TRUE** |

**D14–D16 prove the switch cannot expose a protected member. D17/D17b prove it
does not over-restrict an opted-in one either** — the counter-control, without
which "everything is closed" would score as a pass.

## 2. FULL BEHAVIOURAL MATRIX — EVERY DISCRIMINATOR MATCHED

| # | scenario | result | predicted |
|---|---|---|---|
| **D1** | no privacy row → search | **0** | 0 ✅ |
| **D2** | 18+ default (`lookup_enabled=true`) | **1** | 1 ✅ |
| **D3** | 13–17 default | **0** | 0 ✅ |
| **D4** | 13–17 explicit opt-in | **1** | 1 ✅ |
| **D5** | 18+ opt-out | **0** | 0 ✅ |
| **D6** | adult-set preference under a teen band — **the override** | **0** | 0 ✅ |
| **D7** | no privacy row → `follow_requests_open` | **FALSE** | FALSE ✅ |
| **D8** | 13–17 default → requests | **FALSE** | FALSE ✅ |
| **D9** | 13–17 opted in → requests | **TRUE** | TRUE ✅ |
| **D11** | attribution for an undiscoverable subject | **1 row** | unchanged ✅ |
| **D12** | Samuel ↔ Steve approved follow | **2** | 2 ✅ |
| **D13/D13b** | helpers executable by `authenticated` | **FALSE / FALSE** | ungranted ✅ |

**D5 is the proof that `lookup_enabled` became operative at all** — before CP-2 no
deployed code read that column. **D6 is the only one separating r3's override
from a naive "band decides" implementation.**

### The fixture actually defeated the over-determination

**This is the check that makes every row above meaningful**, and its absence is
what made the Phase 4 "Find People returns nothing" observation unusable:

| fixture diagnostic | value |
|---|---|
| viewer entitled (`connected_member_self`) | **TRUE** |
| subject entitled (`entitled_until > now()`) | **TRUE** |
| acting as the viewer (`auth.uid()`) | **TRUE** |
| kill switch actually off during D14–D17 | **TRUE** |

**So a `0` in the table means the privacy clause denied it — not the viewer gate,
not D-U6-1.** Without these four, every zero would have been over-determined.

## 3. NOTHING PERSISTED FROM THE TEST SUITE

The suite ends in `raise exception`, so the transaction **cannot** commit. Verified
afterwards:

| measure | after | expected |
|---|---|---|
| `enforcement_enabled` | **true** | true ✅ |
| `membership_control.updated_at` | **2026-09-02 15:30:20.83726+00** | **unchanged** ✅ |
| `account_privacy` rows | **0** | 0 ✅ |
| `membership` rows / Production rows | **1 / 0** | 1 / 0 ✅ |
| ephemeral fixture rows left | **0** | 0 ✅ |
| directory rows with `entitled_until` | **0** | 0 ✅ |
| `shadow_enforcement_stat` | **75** | 75 ✅ |

**`updated_at` unmoved is the strong form of the check** — a row written and
rewritten would still read `true` while having been changed. **And the shadow
count is unmoved even though `enforcement_gate` writes telemetry on every call
the suite made**, which is precisely why the suite had to be transactional.

**Samuel and Steve hold NO `account_privacy` row.** None was manufactured; every
band existed only inside the rolled-back transaction.

## 4. SCHEMA DELTA — 10/10 SURFACES

| surface | before | after | predicted |
|---|---|---|---|
| `functions` | 39 | **41** | +2 new, **2 modified** ✅ |
| `function_grants` | 117 | **123** | +6 ✅ |
| columns · constraints · policies · triggers · rls_enabled · table_grants · column_grants · storage_buckets | — | **unchanged** | 0 ✅ |

Two files moved, **54 insertions and 2 deletions** — the deletions being the two
replaced definitions.

## 5. ROLLBACK REHEARSED, NOT ASSERTED

Run in a non-committing transaction: restoring the two definitions from the
committed snapshot and dropping the helpers returns

- `search_account_directory` → **`077f73f28c5d5c47…`** — **byte-identical** to
  pre-CP-2;
- `follow_requests_open` → **`15d41bc79ce8250c…`** — **byte-identical**;
- `functions` → **39**.

**Order confirmed by construction: restore the definitions FIRST, drop the
helpers SECOND.** The reverse leaves a deployed function referencing a missing
one. CP-2 remained deployed after the rehearsal, verified.

## 6. THE SAME TRAP, FOUR TIMES, AND THE FIX THAT FINALLY GENERALISES

**The migration aborted TWICE on its own post-guards, applying nothing.**

1. A guard grepped the source for `true`; **my comment said "carried true"**.
2. Re-scoped to `coalesce`; **my comment said "the former coalesce(..., true)"**.
   The `account_directory` guard was defeated the same way.

**Contorting the comment was the wrong fix and I stopped doing it.** The guards
now strip line comments — `regexp_replace(prosrc, '--[^\n]*', '', 'g')` — before
matching, which is **U5d's stated lesson applied instead of re-learned**: *a
source-text assertion must target code, and a well-commented file is exactly the
one most likely to defeat it.* This is the **fourth** instance in this session
(the C-14 detector, the `#available` comment, and both of these).

**Both aborts were the guards working.** Nothing was applied either time, verified
by re-reading `functions` (39) and the unchanged `follow_requests_open` md5.

**One error was mine and caught only because the guard failed closed:** I wrote
full md5 literals into the pre-guard from **16-character prefixes I had truncated
myself** — invented values. The guard would have refused the migration; I
replaced them with the measured hashes before running.

## 7. WHAT CP-2 DID NOT CHANGE

`get_account_directory_by_user_ids` **untouched** — attribution resolves for an
undiscoverable member (D11). **No policy added, removed or modified.** No client
code. `account_directory.follow_requests_enabled` and `lookup_enabled` are now
both **dead columns**, consulted by nothing.

## 8. STATUS

**CP-2 complete and verified. CP-3 / P5-F NOT started.**
