# C-82 + C-73 TYPE 1 — IMPLEMENTATION COMPLETE. DEVICE CHECK OUTSTANDING — NOT CLOSED.

> **Neither row closes until the Device B check in §4 passes.** Nothing below is
> device evidence. A successful server post is **not** required and **not**
> claimed — `posts` INSERT is gated; the end-to-end publish stays with the
> Production Connected fixture.

Prediction and guards: `docs/phase-5-c82-c73-prediction.md`, committed at
`e1dde65` **before mutation**. C-82 and C-83 filed there. C-3, C-69, C-75, C-76,
C-80, C-81 and B-38 not touched. No production, ASC, enforcement or age-state
mutation.

## 1. Result

| | Prediction | Outcome |
|---|---|---|
| **K1** | the seven named tests FAIL pre-change; legacy-reachability and preparable-control PASS; locked-PDF parity recorded | **MET** — structured *10 reported, 7 Failed, 3 Passed*. The C-82 guard named **exactly the rebuild and the merge**; the pinned count (9) held; the merge test failed on **both** halves |
| **K1 — measurement** | locked PDF: parity with the upload renderer | **PDFKit renders a password-locked PDF's page.** Parity passed pre-change because the upload renderer produced a thumbnail — so **a locked PDF is NOT a permanent preparation failure**, and the Save check correctly does not treat it as one: it asks the renderer, not whether the file is locked |
| **K2** | all pass | **MET** |
| **K3** | Debug 177 / Release 165, set unchanged | **MET** — both, warning set identical |
| **K4** | 248 / 248 | **MET** — **248 declared, 248 passed**, structured census |

## 2. What changed

- **C-82:** `PublishService.publish` now carries `payload.authorisedOmissions`
  into the queued payload, and the queue's same-operation merge keeps the newer
  non-nil set or else the existing one. **`PublishConsentCarriageTests` covers all
  nine `PostPublishPayload(` constructions**, pins the count, and exempts the
  unreachable legacy `publishIfNeeded` payload only while a second test proves no
  caller reaches it.
- **C-73 Type 1:** `ConnectedSharePreflight` gives an unpreparable share-enabled
  attachment `needsConsent` — a PDF whose selected page the upload renderer
  cannot render, or derivative audio `AVAudioPlayer` cannot open — through the
  **existing** dialog and durable omission. Staged and persisted candidates both
  come from `ConnectedSharePreflight` (the inline persisted copy in
  `AddEditSessionView` is gone).
- **Copy:** the dialog title is now **"Attachment can't be shared"** (was "…too
  large to share"); the message is unchanged.
- **`markForPublish`:** removed from `PostRecordDetailsView` as a redundant
  timing-risk stub — not a reproduced public-post defect.
- **Unit 1b's acceptance record is corrected in place**, its original text kept.

## 3. Residuals, stated not absorbed

- **Audio parity is approximate.** Audio that opens in `AVAudioPlayer` but still
  fails the flush-time conversion remains a retry.
- **C-73 Types 2 and 4 are left as they were** (the post-save privacy-toggle
  bypass shows the "Publish limit" alert; a derivative beyond prediction is
  near-theoretical). **Type 3 is C-83.**

## 4. Device check (Device B; Études Dev suffices, no purchase)

1. Attach a **27+ minute WAV**, private-eye **off**, Share **on**, Save →
   choose **Share Without It**.
2. In the Debug queue view the item carries the omission; **relaunch** — it still
   does.
3. On the retries that follow, **no `Connected audio derivative` log line
   appears** — the omitted attachment is never converted or uploaded.
4. Attach a **zero-page PDF** (or any PDF that will not render), share-enabled,
   Save → the dialog appears with the new title.
