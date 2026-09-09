# P5-K / C-10 — STOPPED ON THE CONTROL. THE PREDICTED DEFECT DOES NOT EXIST

**2026-09-09. Scored against `docs/phase-5-c10-pdf-mime-prediction.md`, committed
at `cc6c5e6` before any mutation.**

**NO PRODUCT CODE WAS CHANGED.** `BackendShim.swift` is untouched. The unit
stopped at the control, exactly as the instruction required.

## 1. What the control did

**Prediction P1: "pre-fix, uploading a `.pdf` attachment is REFUSED by local
storage with 415 `InvalidMimeType`."**

**FALSIFIED.** The upload **succeeded**, an object **was** stored, and its
**server-recorded content type was `image/jpeg`**.

## 2. Why — the mechanism, read after the measurement, not before

`contentType(for: "pdf", ext:)` really does return `application/octet-stream`;
`pdf` is not a case and falls to `default:`. **That was the whole basis of the
prediction, and it is not sufficient**, because the value is **discarded**:

```
prepareAttachmentForRemoteUpload(item)
  → isPDFAttachmentKind("pdf") == true
  → preparePDFThumbnailForRemoteUpload(item)
      → renders the PDF to a JPEG
      → returns contentType: "image/jpeg", remoteKind: "image"
```

**A `.pdf` attachment is never uploaded as a PDF.** It is published as a rendered
thumbnail. So the octet-stream value for `pdf` is **dead code on the publish
path**, and there is **no PDF defect to fix**.

## 3. THE FIRST CONTROL FAILED FOR THE WRONG REASON, AND THAT IS THE REAL LESSON

The first fixture was a hand-written PDF stub with `/Count 0` — **no pages**. It
could not be rendered, so `preparePDFThumbnailForRemoteUpload` returned `nil`,
the attachment was **silently skipped**, nothing was uploaded — **and
`uploadPost` still returned SUCCESS.**

**That looked exactly like the predicted defect and was not.** Had I accepted it,
I would have "fixed" a mapping that is never used, watched a green test, and
recorded a false result.

**This is P4-U6's lesson repeating within one phase:** its positive control failed
because the fixture set `kind: "photo"`, and *the fixture was the finding*. Here
the fixture was an unrenderable PDF. **A control that fails is not yet evidence;
you have to establish WHY it failed.**

**A second observation worth keeping, independent of C-10:** an attachment that
cannot be prepared is **skipped silently and the publish still reports success**.
That is the same shape as C-51's silent skip. It is **not** filed as a new defect
here because it is the documented behaviour of `loadIncludedAttachments`, but it
is why the false positive was so convincing.

## 4. Register consequences

**C-10's `.pdf` half is withdrawn — it was my own error, introduced earlier the
same day, and it is corrected in place rather than quietly dropped.** What remains
of C-10 is the **generic `.file`** case, which is **untested by me** and is now a
**product decision under C-63**, not a mapping bug. C-10 therefore has **no
remaining code fix**.

The **"wedges the sync queue permanently"** withdrawal stands — that one was
verified from the flush loop and is unaffected.

## 5. What was kept

`MOTIVOTests/PdfAttachmentMimeTests` is retained as a **characterisation test**,
converted from asserting the prediction to asserting the **measurement**:

- a real renderable PDF publishes successfully;
- the **server-recorded** content type is **`image/jpeg`**;
- the post row carries a non-empty attachment reference;
- the image mapping is unchanged (`image/jpeg`).

**It pins behaviour that previously had no test at all**, so a future change to
PDF publishing cannot pass silently. Both tests pass.

## 6. Evidence quality

**The strong assertion is the server-recorded content type**, read back from
Storage's own object metadata — not that the upload returned 2xx. The prediction
required exactly that distinction, and it is what made the false positive
detectable: in the first run the upload *was* accepted and **no object existed**.

Local and production `attachments` allow-lists were measured **byte-identical**,
so the local stack is a faithful rig for this question.

## 7. Recommendation

**Close C-10 without a code change**, dispositioned against **C-63**. The next
unit should be chosen afresh — C-43, C-6, C-20 and C-62 remain the leading
independent candidates.
