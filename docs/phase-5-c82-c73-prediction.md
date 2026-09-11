# C-82 + C-73 (TYPE 1) — PREDICTION, COMMITTED BEFORE MUTATION. 2026-09-11

**At `66db50e`.** Account-holder decisions the same day: **C-82 filed P2 and
fixed first**, with the Unit 1b acceptance record corrected; **C-73 Type 1 →
option (a)** — detect permanent preparation failures at Save and reuse the
existing omission consent; **Type 3 recorded separately (C-83)** and left
retryable; **the redundant `markForPublish` call removed** as a timing-risk stub,
not a reproduced defect. C-3, C-69, C-75, C-76, C-80, C-81, B-38 out of scope.

---

## 1. C-82 — the member's "Share Without It" never reaches the queue

`PublishService.publish(…)` rebuilds the payload it enqueues (`:278`) and passes
**no `authorisedOmissions`** — the identifier does not appear anywhere in
`PublishService.swift`. `SessionSyncQueue.enqueue`'s same-operation merge
(`:236`) rebuilds again and also drops it. **So both editors' consent is lost
before the item is queued.** Consequence, for a share-enabled attachment over
the ceiling where the member chose Share Without It: video/photo/PDF/M4A are
still left out, but only by the old upload-time fallback, with a redundant
"Publish limit" alert; an imported WAV/AIFF of **~24.8–27 min** is **shared
against the member's choice**; beyond **~27 min** the publish fails
permanently (`derivativeExceedsLimit`), retries forever and re-converts on every
flush, with nothing shown.

### The complete inventory — 9 `PostPublishPayload(` constructions in app code

| Site | Can it carry attachments? | Carries omissions today? |
|---|---|---|
| `AddEditSessionView:2096` (editor payload) | yes | **yes** |
| `PostRecordDetailsView:1883` (editor payload) | yes | **yes** |
| `PublishService:278` (`publish` rebuild) | yes | **NO — C-82** |
| `SessionSyncQueue:236` (same-op merge) | yes | **NO — C-82** |
| `PublishService:167` (`publishIfNeeded` legacy) | only if reachable — **it is not**: no caller outside `PublishService` reaches `publishIfNeeded`, `publish(objectID:)` or `unpublish(objectID:)` | n/a |
| `PublishService:193`, `:325` (unshare) | no — `isPublic: false` | n/a |
| `SessionSyncQueue:265` (`enqueue(postID:)` stub), `:410` (legacy decode) | no — `sessionID: nil` | n/a |

**The guard covers every site, not the two already found:** each construction
must pass a non-`nil` `authorisedOmissions`, **or** be provably attachment-free
(`isPublic: false` / `sessionID: nil`), **or** be the legacy site — which is
exempt **only while** a second guard proves it unreachable. The total (9) is
pinned, so a tenth construction forces a review.

**Fix:** `publish` passes `payload.authorisedOmissions`; the merge keeps the
newer non-nil set, else the existing one. Unit 1b's acceptance record is
corrected: its oversized-video device result was a **false positive** for
consent propagation — the old fallback omitted the video later.

## 2. C-73 Type 1 — detect permanent preparation failures at Save

**Parity, measured from source:** the upload renders a PDF with
`AttachmentStore.generatePDFThumbnail(url:, page: PDFSelectedPagesStore.pages(for: id)?.first)`.
The Save check calls the same renderer (`data:` variant for staged, `url:` for
persisted) with the same page — **the same `PDFDocument` → `page(at:)` test, so
the same verdict**. For audio that needs a derivative, the flush-time decoder
is too slow to run at Save (~16 s for 30 min); the Save check treats **"
`AVAudioPlayer` cannot open it"** as unpreparable. **That is the best cheap
signal, NOT exact parity** — an audio file that opens but still fails to
convert remains a retry, recorded as residual.

An unpreparable share-enabled attachment gets `needsConsent` and goes through
the **existing** dialog and durable omission. **The title changes from "Attachment
too large to share" to the neutral "Attachment can't be shared"** — Unit 1b called
the presentation cause-agnostic, but the title named a cause, and it would be
false for a locked PDF. The message is already neutral and is unchanged.
**Flagged for the account holder.**

**One-of-N:** `AddEditSessionView` built its persisted-attachment candidates
inline; both staged and persisted candidates now go through
`ConnectedSharePreflight` helpers, and a guard forbids inline construction.

## 3. C-83 — entitlement / server refusal (Type 3)

Filed separately and left retryable: the payload is valid and succeeds after
resubscription. Not C-73, and C-76 is not addressed here.

## 4. `markForPublish` — removed

`PostRecordDetailsView:1910` enqueued a session-less `isPublic: true` stub
**before** `publish(…)`'s asynchronous enqueue ran. The merge lets the real
intent replace it, so **no public post was ever reproduced**; the only other
effect is a preview-mode diagnostic print. **Removed as a timing-risk redundant
stub.**

## 5. PREDICTION

**K1 — pre-change:**
- `testEveryPayloadConstructionCarriesOmissionsOrCannotCarryAttachments` **FAILS**
  (the rebuild and the merge);
- `testLegacyPublishPathStaysUnreachable` **PASSES** (regression guard);
- `testQueueMergeKeepsAuthorisedOmissions` **FAILS**;
- `testPostRecordSaveQueuesNoStub` **FAILS**;
- `testZeroPagePDFNeedsConsent` **FAILS**; `testUndecodableDerivativeAudioNeedsConsent`
  **FAILS**; `testPreparableAttachmentsStillShare` **PASSES** (control);
- `testLockedPDFVerdictMatchesUploadRendering` — **a measurement of PDFKit, not a
  prediction**: it asserts parity with the upload renderer, so it FAILS pre-change
  only if PDFKit refuses to render a locked page. Its pre-change result is
  recorded either way;
- `testBothEditorsBuildCandidatesThroughSharedHelpers` **FAILS**;
- `testConsentTitleNamesNoCause` **FAILS**.

**K2 — after:** all pass.

**K3 — warnings unchanged: Debug 177 / Release 165.**

**K4 — census 248 / 248** (238 + 10).

**K5 — device (Device B; Études Dev suffices, no purchase):** attach a **27+
minute WAV**, private-eye off, Share on, **Share Without It** → the queued item
carries the omission (Debug queue view), it survives relaunch, and **no
`Connected audio derivative` line appears on retry**. Attach a zero-page or
locked PDF, share-enabled → the (neutral) dialog appears at Save. **A successful
server post is NOT required** — `posts` INSERT is gated; the end-to-end publish
stays with the Production fixture.
