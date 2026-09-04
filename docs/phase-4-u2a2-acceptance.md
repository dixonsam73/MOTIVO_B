# P4-U2a-2 / C-61 — ACCEPTANCE

**Executed 2026-09-04. Prediction committed beforehand at `e13663f`.**
**Every behavioural prediction matched. ONE STRUCTURAL PREDICTION WAS WRONG and
is corrected below rather than quietly re-scored.**

---

## 1. THE CHANGE

Three source files. **Neither `shouldPublish` literal was touched.**

| file | change |
|---|---|
| `SessionSyncQueue.swift` | `enum PostOp { publish, unshare }`; `op` on the payload, defaulted; **hand-written `init(from:)`** so legacy files decode; **last-intent-wins** merge; `flushNow` dispatch that dequeues an `.unshare` **only on convergence** |
| `BackendShim.swift` | `unsharePost` on the protocol + both services; **demote (`is_public = false`) then `deletePost`**; object deletion treats **already-absent as success** |
| `PublishService.swift` | both entry points **enqueue an `.unshare` intent** before the network is trusted |

**No SQL, no policy, no migration, no project file** (`U2a2-20/21`).

---

## 2. THE PREDICTION THAT WAS WRONG — AND WHY IT MATTERS

**Predicted (§0.2):** `NoSuchKey` is indistinguishable from RLS denial, so
requirement 8 would force `testConnectedModeFailClosedWhenObjectCannotBeDeleted`
to be re-expressed against a transport failure.

**Measured: FALSE, and the fail-closed test needed no change at all.**

The original probe deleted a foreign path where **no object existed**. Deleting
an object that **genuinely exists** under another user's prefix returns something
different:

```
absent object (any prefix)          -> 400  {"statusCode":"404", … "NoSuchKey"}
PRESENT object, not permitted       -> 400  {"statusCode":"403","error":"Unauthorized",
                                             "message":"Access denied","code":"AccessDenied"}
```

**`NoSuchKey` and `AccessDenied` are distinct.** So "already gone" is separable
from "exists but refused", and **fail-closed survives intact**: a real
undeletable object still blocks the row deletion.

**The lesson is the one this project keeps re-learning.** The first probe tested
*absence at a foreign path* and the conclusion was generalised to *denial*, which
is a different condition. The generalisation was checked only because the test it
predicted would break **passed instead** — and a passing test was investigated
rather than accepted. Had it been waved through, the record would carry a false
claim about Storage semantics **and** a weakened fail-closed argument.

**Confirmed in the same measurement:** the diagnostic returned
`isPublic=Optional(false)` alongside the `AccessDenied` failure — **the demotion
had already landed before the destructive step failed**, which is precisely the
ordering U2a-2 exists to guarantee.

---

## 3. BEHAVIOURAL EVIDENCE — LOCAL STACK, 10 NEW CASES, ALL PASS

`MOTIVOTests/UnshareDurabilityTests.swift`:

| requirement | test | result |
|---|---|---|
| 1 — backward-decodable | `testLegacyQueueFileDecodesAsPublish` — a queue JSON with **no `op` key** decodes and every entry is `.publish` | **PASS** |
| 2 — `.publish` unchanged | `testOrdinaryPublishStillWorks` | **PASS** |
| 3 — persisted before network | offline unshare retains an `.unshare` item | **PASS** |
| 4 — demote before delete | `U2a2-11` (structural) + §2's measurement | **PASS** |
| 5 — A: demotion unreachable | `testDemotionUnreachableKeepsIntentQueued` — row untouched, **intent retained** | **PASS** |
| 6 — B: private + retained | `testPrivateRowWithRetainedIntentConverges` — private, **still queued**, later flush **converges** | **PASS** |
| 7 — C: partial deletion converges | `testPartiallyDeletedObjectsStillConverge` | **PASS** |
| 8 — already-absent is success | `testAlreadyAbsentObjectIsSuccessNotPoison` | **PASS** |
| 9 — dequeue only after removal | asserted in every convergence case | **PASS** |
| 10 — last intent wins, **both** | `testPublishThenUnshareResolvesToUnshare`, `testUnshareThenPublishResolvesToPublish` | **PASS** |
| 11 — process reconstruction | `testOfflineUnsharePersistsSurvivesReconstructionAndConverges` — the **on-disk file** is decoded through the real `PostPublishPayload` decoder, exactly as `load(from:)` does, and yields `.unshare` | **PASS** |
| 12 — existing flush trigger | convergence is driven by `flushNow()` **alone**, no new trigger | **PASS** |
| 13 — preview / Solo | `testLocalSimulationDoesNotReachTheServer` + `testPreviewModeStillDeletes` | **PASS** |

**Two earlier tests were re-expressed, and this was declared in the prediction.**
`testFailedUnshareLeavesRowStillPublic_C61` measured the defect; it now measures
the repair (**row PRIVATE, intent retained**). `testUnsharePathLeavesNoDurableIntentWhenOffline`
asserted that nothing was enqueued; it now asserts that reconnect + flush **alone
converges**. Both are inverted in place, with their history in the comments,
rather than deleted.

**On case B's construction, stated rather than glossed.** A true "demote 200 then
object-delete fails" is not constructible from the client for the reason §2
gives, so case B builds the *state* — row already private, intent queued, flush
fails — and proves convergence from there. **It does not prove that the deletion
specifically was the failing step.**

---

## 4. GATES

| gate | result |
|---|---|
| Debug / Release build | **BUILD SUCCEEDED**, 0 errors |
| `MOTIVOTests` | **33 of 33** (15 pure + 8 + 10 new) |
| `u5/client-structural.sh` | **60 / 60** |
| `p4/u2a2-acceptance.sh` | **22 / 22** |
| `p4/u2a-acceptance.sh` | **18 / 18** |
| `p4/u1-baseline.sh` | 14 pass / **the same 2 U2a flips**, unchanged |

**`u2a-acceptance.sh` U2a-12/13/14 were re-pinned to `f12330e..9f1498e`.** They
asserted "since the U1 baseline", true only while U2a was the tip; U2a-2
legitimately touches three files, so as written they would have decayed into
permanent noise. **The claim worth keeping is historical and exact — U2a itself
changed one Swift file — and it is now expressed that way.** Not a relaxation:
the range is narrower than the original open-ended one.

---

## 5. PRODUCTION CENSUS — ZERO DELTA, AS PREDICTED

| measure | U1 | after U2a-2 |
|---|---|---|
| `total_posts` / `public_posts` | 101 / 101 | **101 / 101** |
| `private_false` / `private_null` | 0 / 0 | **0 / 0** |
| `owners` | 9 | **9** |

**No production fixture was created at any point.** All behavioural work ran on
the local stack with explicit fixture ids.

**Local stack restored:** posts back to **2**, attachment objects back to **5**
(the pre-existing U7f `.pdf` fixtures), **zero `.jpg` leftovers**.

**A hygiene defect was found and fixed.** Two foreign-prefix objects survived an
earlier run because this suite's teardown deleted everything **as `ownerUID`**,
which cannot remove an object under another user's prefix. They were removed by
explicit path, and teardown now authenticates as **the owner encoded in each
object's own path**.

---

## 6. TERMINOLOGY CORRECTED, AND WHAT WAS DELIBERATELY NOT BUILT

- **No retry cap, no backoff** (`U2a2-15` asserts their absence). Exhausting a
  finite count and silently abandoning an owed privacy withdrawal is the wrong
  failure.
- **"Bounded reconciliation state" is withdrawn as a description.** A demoted row
  is a **pending reconciliation state, bounded by CONVERGENCE, not by an attempt
  limit.** It is not a settled result, and the queue is what makes that true.
- **Backoff and scheduling are recorded as future operational hardening**, to be
  driven by measured need rather than anticipated.
- **Phase 2's backup exclusion is untouched.** A device restore still loses
  pending intents; **the immediate demote is what keeps the worst survivor
  private rather than public.** Out of scope by instruction.

---

## 7. WHAT U2a-2 DOES NOT DO

- **U2b is not started.** Both `shouldPublish: true` literals remain
  (`U2a2-16/17`), so **the whole of U2a-2 is unreachable from the shipping UI** —
  which is what makes it independently reviewable and revertible.
- **U2c is not started** — `loadIncludedAttachments` untouched (`U2a2-19`).
- **U2s is not started** — `posts_insert_owner` still has no `is_public`
  predicate (`U2a2-21`, `P4U1-15` = 0). **U2a-2 makes no old-client durability
  claim.**
- **C-31 untouched.**

## 8. CARRIED TO U2b

**The copy constraint.** No UI state may assert *completed* removal while an
`.unshare` is pending — "removing" is honest, silence is acceptable, "removed"
is not. Owned jointly with **U8**.

**The immediate attempt still calls `deletePost`, not `unsharePost`,** at the
C-60 gate. Harmless today — the queue flush that precedes it already performs
the demote-then-delete — but it is a redundant second call, and U2b should route
that gate through `unsharePost` or drop it in favour of the queue.
