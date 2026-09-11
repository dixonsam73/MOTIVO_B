# C-82 + C-73 TYPE 1 — IMPLEMENTATION COMPLETE. DEVICE CHECK OUTSTANDING — NOT CLOSED.

> **CORRECTION 2026-09-12 — THE C-82 DEVICE CHECK FALSIFIED THE FIX (K5).** On
> Device B a 32-minute WAV saved from `PostRecordDetailsView` with Share on was
> converted at flush (`1904s • 61081909B • 15002ms`) and then failed on the size
> limit. **The consent list carries STAGED attachment ids, while saving gives
> each attachment a NEW id** (`AttachmentStore.addAttachment`), and neither editor
> translates the list — so the flush never matches it for a newly added
> attachment. The fix below made the list survive, in the wrong id space; its
> tests used arbitrary ids and checked carriage, not identity. **C-82 is OPEN.**
> **Also corrected:** §4 step 2 is wrong — the Debug queue view shows item ids
> only, never `authorisedOmissions`; the queue file is the evidence. The text
> below is kept as the record of what was believed.

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

> **§4 STEP 4 — FIXTURE AND CONTROL FIXED 2026-09-11, BEFORE THE RUN. The step
> text above is kept as written.**
>
> **Narrowed to the zero-page PDF.** "Or any PDF that will not render" is not a
> fixture. And the prediction's "zero-page *or locked*" is wrong for this check:
> K1 measured that PDFKit renders a locked PDF's page, so a locked PDF is
> preparable and correctly raises **no** dialog.
>
> **Fixture: `C73-zero-page.pdf`.**
> - 125 bytes, SHA-256 `79370862c6cb54e96ed3125464c11e4ce3e8b08fb5048723695b6b9e9728d701`.
> - **Byte-identical to `PreparabilityPreflightTests.zeroPagePDF()`**, the bytes
>   `testZeroPagePDFNeedsConsent` scored.
> - Import classifies by extension, and staging does not open PDFs, so it
>   attaches even though macOS PDFKit refuses to open it at all. The verdict is
>   the same either way: no renderable page.
>
> **Control: `C73-one-page-control.pdf`.**
> - 2161 bytes, SHA-256 `1e8be8f96443a7f79ab96a2ee04d8291d05804f8bc397fcc8a6c52d71547dbf7`.
> - One renderable page (macOS PDFKit: opens, 1 page).
>
> **Procedure** (Device B, Études Dev, `AddEditSessionView`, new session):
> 1. Attach both PDFs, set private-eye off on both, and turn Share on. Save.
>    - **PREDICTED:** a dialog titled exactly **"Attachment can’t be shared"**.
>      The title is singular, so exactly one attachment is flagged, not two.
>      Buttons: **Cancel** / **Share Without It**.
> 2. Tap **Cancel**, remove the zero-page PDF, and Save again.
>    - **PREDICTED:** **no dialog**, and the session saves with the control
>      included.
>
> **Any one of these falsifies:**
> - a plural title;
> - no dialog at the first Save;
> - a dialog at the second Save.

> **C-73 TYPE 1 DEVICE RESULT — 2026-09-11. PASS, as predicted at each step.**
> Device B, Études Dev, Force Connected. The account holder ran the device, using
> the two fixtures committed above (`e97a816`).
>
> - **With both PDFs attached, share-enabled, Save** raised the dialog titled
>   **"Attachment can’t be shared"**. The title was **singular**, so exactly one
>   attachment was flagged. Buttons: Cancel / Share Without It.
> - **After Cancel and removing the zero-page PDF, Save** raised **no dialog**, and
>   the session saved with the control included.
>
> **What this establishes on hardware:**
> - an unrenderable PDF is caught **at Save**, through the existing consent dialog,
>   under the neutral title;
> - a renderable PDF is not.
>
> **Not claimed:**
> - **Audio parity.** An audio file that `AVAudioPlayer` cannot open was not
>   exercised on device, and the §3 residual still stands.
> - **C-73 Types 2 and 4** are unchanged.
> - **Type 3 is C-83.**
>
> The session saved at the second step queues a publish that fails at the gated
> INSERT (403), like the other test items. That is expected residue.
