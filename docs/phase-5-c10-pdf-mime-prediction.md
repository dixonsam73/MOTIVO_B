# P5-K / C-10 — PDF MIME MAPPING: PREDICTION

**Committed BEFORE any mutation, 2026-09-09.** A narrow correctness unit.

## 1. The defect, as measured

`BackendShim.contentType(for:ext:)` switches on `kind` and handles only
`"image"`, `"video"` and `"audio"`. **`AttachmentKind` has five cases** — `audio,
video, image, file, pdf` — so **`pdf` and `file` both fall to `default:` and
return `application/octet-stream`**.

The `attachments` bucket's `allowed_mime_types` **permits `application/pdf`** and
does **not** permit `application/octet-stream`. **Measured byte-identical in local
and production on 2026-09-09**, so the local stack is a faithful rig.

**Therefore a PDF attachment — an intentionally supported type — is refused by
storage purely because of a client mapping bug.**

## 2. SCOPE — deliberately narrow

**In scope:** the `pdf` case of `BackendShim.contentType(for:ext:)`.

**Out of scope, explicitly:** widening the storage bucket; changing generic
`.file` behaviour (**C-63**, a product decision); any other MIME support; the
viewer's separate map at `AttachmentViewerView:467`; and the indefinite
no-cap retry of a permanently-failing queued post (**noted on C-10, not fixed
here**).

## 3. THE CONTROL MUST RUN FIRST

**The behavioural control runs against the PRE-FIX code and must FAIL**, or the
test is vacuous. This is P4-U6's lesson in its own words: its positive control
failed first, and *that* was the unit's real finding.

**If the pre-fix control does NOT reproduce the failure, STOP and report** rather
than forcing the implementation.

## 4. PREDICTIONS

| # | prediction |
|---|---|
| P1 | **Pre-fix**, uploading a `.pdf` attachment through the real upload path is **REFUSED by local storage** with a MIME/type error (expected 415 `InvalidMimeType`) |
| P2 | **Pre-fix**, `contentType(for: "pdf", ext: "pdf")` returns **`application/octet-stream`** |
| P3 | **Post-fix**, it returns **`application/pdf`** |
| P4 | **Post-fix**, the upload **succeeds** |
| P5 | **Post-fix**, the STORED OBJECT's recorded content type is **`application/pdf`** — not merely that the upload was accepted |
| P6 | **Post-fix**, the post row publishes with a **non-empty** attachment reference |
| P7 | image / video / audio mappings are **unchanged**, asserted case by case |
| P8 | `.file` still returns `application/octet-stream` — **unchanged by this unit** |
| P9 | Debug and Release both build clean |
| P10 | full `MOTIVOTests` suite passes |
| P11 | **zero** new warning kinds against a captured baseline |
| P12 | **zero** production state change |

## 5. HOW P5 IS TO BE EVIDENCED, AND THE HONESTY RULE

The authoritative record of a stored object's type is
`storage.objects.metadata->>'mimetype'` (with `content_type` as the alternative
key depending on the Storage version). **The claim to prove is what the SERVER
RECORDED, not what the client sent.**

**IF THE LOCAL STORAGE TOOLING DOES NOT EXPOSE AUTHORITATIVE STORED-OBJECT MIME
METADATA AS PREDICTED, THAT MUST BE REPORTED AS SUCH** — not silently replaced
with the weaker claim that the upload was accepted. A 2xx is not evidence of the
recorded content type.

## 6. PREDICTED DIFF

| file | change |
|---|---|
| `MOTIVO/BackendShim.swift` | one `case "pdf":` arm in `contentType(for:ext:)` |
| `MOTIVOTests/…` | new mapping tests |

**No other source file. No SQL. No configuration. No production mutation.**
