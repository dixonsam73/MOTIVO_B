# C-65 — ACCEPTANCE. PREPARATION IS NOW ATOMIC WITH RESPECT TO PUBLICATION.

**Prediction:** `docs/phase-5-c65-prediction.md`, committed at `1d291eb` before
any product change. **Investigation:** `docs/phase-5-c65-investigation.md`.
**Local Supabase stack only — no production mutation.**

## 1. The pre-fix control reproduced the defect on all four assertions

Run against unmodified code at `1d291eb`, on the local stack:

```
test1_ValidPDFPublishesThroughTheJPEGRepresentation   PASSED   ← positive control
test2_UnpreparableAttachmentDoesNotPublishAPartialPost FAILED
test3_FailedPreparationLeavesTheItemQueued             FAILED
test4_RetryOfAValidPublishIsIdempotent                 PASSED
```

with exactly these messages:

- *C-65: a publish that could not prepare a selected attachment reported SUCCESS*
- *C-65: no post row may be created when preparation fails*
- *C-65: a failed publish must stay queued, not dequeue as success*
- *C-65: and still no post row*

**The positive control passing is what makes the negatives evidence.** P4-U6
recorded the trap where an unusable fixture made a negative assertion pass for
the wrong reason; here a **valid** PDF is proven to publish through the JPEG
representation — one ref, `kind: "image"`, one storage object — with the same
wiring, before anything is asserted absent.

## 2. Result against the prediction

| | Prediction | Outcome |
|---|---|---|
| **P1** | loading + preparation move before the INSERT | **MET** — preparation `:974`, INSERT `:1048` |
| **P2** | on failure: no row, no object, temp files cleaned | **MET** — `test2` |
| **P3** | the queue does not dequeue | **MET** — `test3` |
| **P4** | valid PDF/image/audio/video unchanged | **MET** — `test1`, plus `SharedOnlyUploadTests` 5/5 |
| **P5** | retry stays idempotent | **MET** — `test4`: one row, one object, one ref after two publishes |
| **P6** | the unreachable post-insert guard is removed | **MET** |
| **P7** | oversize untouched | **MET** — the diff contains no change to that path |

**Debug and Release clean. Warning delta ZERO** — 187/175, matching the pre-fix
baseline. **151 of 151 tests pass**, structured census.

## 3. One thing the compiler caught that review would not have

Hoisting made `guard let sessionID = payload.sessionID` an unused binding, and
the honest-looking fix — delete the guard — **would have been a behaviour
change**. The guard still distinguishes two different outcomes: a payload with
**no session reference** returns without patching, while a session with **no
included attachments** falls through and explicitly PATCHes `refs: []`.
Only the binding was dropped; the guard and its comment stay.

## 4. What C-65 does NOT fix — both go to the follow-up

**A permanently unpreparable attachment retries forever.** Every preparation
failure returns `.failure`, which the queue means as "try again". That is right
for a file temporarily unresolvable after a container rotation and wrong for a
corrupt or encrypted PDF, and the queue has no third state for
*"blocked, member action required"*. **No discriminator was added**: `fileExists`
is one signal, not a classifier, and a half-classifier would add a second thing
to reason about without resolving the permanent class.

**Oversized attachments still skip silently.** Unchanged deliberately, per
instruction. The pre-queue check that exists (`handleFileImport:412`) **warns
rather than rejects** and is the only reader of `publishUploadLimitBytes`, so
the common staging funnel `stageData(:344)` — photos, camera, recordings — has
no size check at all.

**Neither is silently dequeued to avoid retries.**
