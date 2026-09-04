# P4-U2c COMPLETION AMENDMENT — ACCEPTANCE

**Executed 2026-09-04. Prediction committed beforehand at `b9002eb`.**

**The invariant now achieved:**

> A payload with `op == .publish` and `isPublic == false` **cannot be
> constructed through production API — it does not compile** — and **cannot
> arrive from a file on disk**, because the decoder normalises the
> contradiction to `.unshare`.

This is **option 1** of the brief's preference order. **No runtime choke-point
guard was added**, because option 2 applies only *"otherwise"*.

---

## 1. THE GAP THAT WAS CLOSED — IT WAS CONCRETE

U2c proved the two shipping call sites do not construct the forbidden pair. It
did not prove the pair cannot reach the door. **It could, by a real route:**

`PublishService.publish(objectID:)` (`:360`) → `publishIfNeeded(shouldPublish:
true)` → the payload at `:167` built with `isPublic: sIsPublic` read straight
from Core Data. **On a session whose local `isPublic` is false that produced
`.publish + isPublic:false`, enqueued it, and it reached `uploadPost` — a
private row with its attachments uploaded.** No callers today; production API
nonetheless.

`SessionSyncQueue`'s merge (`:185`) was a second site — it recombined `op` and
`isPublic` from two independently-merged values — and `init(from:)` a third.

## 2. THE FIX

**`op` is derived from `isPublic` and is no longer an initialiser parameter.**

```swift
public let op: PostOp                     // let: cannot be reassigned
self.op = isPublic ? .publish : .unshare  // DERIVED, never supplied
```

**They were always the same bit.** `.publish` means the post must exist *and* be
visible — a private post must not exist at all (invariant 2). `.unshare` means it
must not exist, so its visibility is meaningless. **The forbidden state was
exactly the case where two redundant fields disagreed.**

**Why derive `op` from `isPublic` rather than the reverse:** removing `isPublic:`
instead would be equally sound and would have **destroyed the U2c-9/U2c-10
call-site symmetry assertions** the brief requires preserving. The chosen
direction leaves `AddEditSessionView` and `PostRecordDetailsView` **completely
untouched**, so those assertions still pass unchanged.

### 2.1 The decoder makes it a runtime property too

Removing a parameter cannot police a file on disk. `init(from:)` normalises:

| file | decodes as |
|---|---|
| no `op`, `isPublic` true/absent | `.publish` — unchanged |
| no `op`, **`isPublic: false`** | **`.unshare`** — the migration, §3 |
| `op` present and agreeing | as written |
| **`op: publish` + `isPublic: false`** | **`.unshare`** — the safe reading, never "upload it" |

## 3. THE ONE BEHAVIOUR CHANGE, DECLARED IN THE PREDICTION

**A legacy queued item with `isPublic: false` now converges to DELETION rather
than demotion.** It meant *"publish this and demote it to private"* — the pre-U2b
Share-OFF behaviour. Deletion is the member's original Share-OFF intent under
Phase 4's rule that private content does not belong on Supabase, and is strictly
safer than leaving a private row. Decoding it as `.publish` would either upload a
private row or leave it stuck in the queue for ever.

Asserted by `testLegacyQueueFileDecodesWithPrivateEntriesMigrated` and
`testDecoderNormalisesContradictoryQueueFile`.

## 4. THE DISCRIMINATOR — IT DOES NOT COMPILE

A structural assertion that a parameter is absent is not proof the state is
unreachable. So the forbidden construction was written into a test file and
compiled:

```
UnshareDurabilityTests.swift:354:18: error: extra argument 'op' in call
UnshareDurabilityTests.swift:354:18: error: cannot infer contextual base in reference to member 'publish'
```

Then removed, with `git diff` empty afterwards. **The forbidden state is not
merely unlikely; it is not expressible.**

## 5. THREE EXISTING TESTS ASSERTED THE PRE-AMENDMENT WORLD

**All three failed on correct code, and none was deleted to make the suite
green.** Two now assert something *stronger*.

| test | was | now |
|---|---|---|
| `testLegacyQueueFileDecodesAsPublish` | every legacy entry defaults to `.publish` | **renamed**: public entries keep their meaning, **private entries migrate to `.unshare`** |
| `testTodaysUnshareDemotesRowToPrivate` | documented the pre-U2b demote-and-keep | **`testPrivatePayloadUnsharesEvenWhenCallerAsksToPublish`** — **the payload's privacy wins over a contradictory caller**: asking to publish something marked private *removes* it |
| `testTodaysOfflineUnshareIsQueuedAndConvergesOnReconnect` | pre-U2b offline demotion | **`testOfflinePrivatePayloadIsQueuedAndConvergesOnReconnect`** — same durability property, current semantics |

**The second is a genuinely new guarantee** and worth stating on its own:
`shouldPublish` and `payload.isPublic` can still disagree at the `PublishService`
boundary, and **the private reading wins**. The historical pre-U2b results those
tests recorded are preserved in `docs/phase-4-u2a2-durability.md` and C-61.

## 6. PRESERVED, AS REQUIRED

| | evidence |
|---|---|
| backward decoding of legacy files | `testLegacyQueueFileDecodesWithPrivateEntriesMigrated` — decodes, with §3's migration |
| `.unshare` durability | offline → persisted → reconstruction → converges, all green |
| **last-intent-wins** | the merge's `payload.op != existing.op` branch is **untouched**; both directions still pass |
| ordinary `.publish` | `testOrdinaryPublishStillWorks`, `testShareOnStillPublishes` |
| **call-site symmetry assertions** | **U2c-9/U2c-10 unchanged and passing** — both views untouched |

## 7. ASSERTIONS — `u2c-acceptance.sh` 20/20

U2c-1..14 keep their values. Added:

| id | asserts |
|---|---|
| U2c-15 | the memberwise init declares **no `op:` parameter** |
| U2c-16 | `op` is **derived** from `isPublic` |
| U2c-17 | `op` is a `let` |
| U2c-18 | the decoder **normalises** the contradiction |
| U2c-19 | **no production site passes `op:` at all** |
| U2c-20 | the merge computes visibility once and lets `op` follow |

## 8. SUITE PINNING — FOUR ASSERTIONS MOVED, NONE DROPPED

The amendment legitimately supersedes constructs that `u2a2` and `u2b` assert:
`U2a2-4/5` (the `op:` default and the plain decoder default), `U2b-13` (`op:
.unshare` in `PublishService`), and `U2b-5` (an open-ended "since U2a-2" file
count). Per the policy adopted in U2b, each is now evaluated against **its own
unit's commit**.

**The live guard was not dropped — it MOVED.** The current queue contract is
asserted by `u2c-acceptance` U2c-15..20 plus the behavioural decoder test, which
are strictly stronger than what was pinned.

## 9. GATES

| gate | result |
|---|---|
| Debug / Release build | **BUILD SUCCEEDED**, 0 errors |
| *(a Release run first reported* `BUILD FAILED` *— `unable to attach DB … database is locked`, my own parallel xcodebuild holding the build database. Not a source error; it succeeded on a clean re-run. Recorded because a bare "BUILD FAILED" in a log is exactly what gets mistaken for a regression.)* | |
| `MOTIVOTests` | **40 of 40**, exit 0 |
| `u5/client-structural.sh` | **60 / 60** |
| `p4/u2c-acceptance.sh` | **20 / 20** |
| `p4/u2b-acceptance.sh` | **16 / 16** |
| `p4/u2a2-acceptance.sh` | **22 / 22** |
| `p4/u2a-acceptance.sh` | **16 / 16** |
| `p4/u1-baseline.sh` | 11 pass / its 5 documented flips |

## 10. UNCHANGED

- **Production untouched** — read-only checks only.
- **No membership state, no U6b enforcement change, no Device A action.**
- **U2s NOT started** — `posts_insert_owner` still has no `is_public` guard.
- **U2b remains device-verification-pending** — Phase 4 exit condition 8.
