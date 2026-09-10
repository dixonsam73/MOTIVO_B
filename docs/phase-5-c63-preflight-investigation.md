# C-63 + 50 MB PREFLIGHT — INVESTIGATION. STOPPING BEFORE IMPLEMENTATION.

**Traced at `93a25c1`, 2026-09-10. No code changed.** Scoped, per the corrected
model, to **attachments explicitly marked for Connected sharing** —
`AttachmentPrivacy.isPrivate == false`. A private local attachment of any size is
outside every question below.

---

## 1. C-63 — where `.file` actually comes from

**Two producers, and only two:**

| Site | Path | When |
|---|---|---|
| `AddEditSessionView+Attachments:433` — `kindForURL`'s fallback | **file import**, `.fileImporter(allowedContentTypes: [.item])` — i.e. **anything the system can offer** | any extension outside the recognised lists |
| `AddEditSessionView:727`, `:731` | **PhotosPicker** fallback when the item's UTType conforms to neither `.image` nor `.movie`, or exposes no content type | edge case; the picker is `matching: .any(of: [.images, .videos])` |

## 2. Is a SUPPORTED format being collapsed to `.file`? NO — measured

`kindForURL` recognises: **image** png/jpg/jpeg/heic/heif/gif/bmp/tiff/tif ·
**audio** m4a/aac/mp3/wav/aiff/caf · **video** mov/mp4/m4v/avi · **pdf** pdf.

The deployed bucket allows exactly: `application/pdf`, `audio/aac`, `audio/m4a`,
`audio/mp4`, `audio/mpeg`, `audio/wav`, `audio/x-m4a`, `image/heic`,
`image/heif`, `image/jpeg`, `image/png`, `video/mp4`, `video/quicktime`.

**Every bucket-allowed type already maps to an extension `kindForURL`
recognises.** So `.file` genuinely means *arbitrary unsupported file*, and
**C-63 is branch (b)**: refuse honestly at selection/import. **No
misclassification to correct, and no new format to invent support for.**

## 3. BUT THE COMPARISON FOUND THE OPPOSITE DEFECT — filed as C-74, not fixed here

`contentType(for:ext:)` (`BackendShim:1514`) falls back **within** each
recognised kind, so several extensions upload with a **content type that is not
what the bytes are**:

| Extension | Classified | Declared on upload | Bucket verdict |
|---|---|---|---|
| `gif`, `bmp`, `tiff`, `tif` | `.image` | **`image/jpeg`** | accepted — **mislabelled** |
| **`heif`** | `.image` | **`image/jpeg`** | accepted, though the bucket explicitly allows `image/heif` |
| `aiff`, `caf` | `.audio` | **`audio/m4a`** | accepted — **mislabelled** |
| `m4v`, `avi` | `.video` | **`video/mp4`** | accepted — **mislabelled** |

**These do not fail; they succeed while lying.** That is the inverse of C-63 —
`.file` can never upload, whereas these upload with a false `Content-Type` —
and `heif` is the sharpest case, because it is a format the bucket genuinely
supports and we declare it as something else. **Reachable only through file
import**, since the photo picker maps by UTType conformance. **Filed, not fixed:
it is a different defect from C-63 and must not be absorbed into it.**

## 4. The smallest common pre-publish boundary — IT EXISTS, and it is TWO call sites

**`PublishService.shared.publish(payload:objectID:shouldPublish:)` has exactly
two callers:** `AddEditSessionView:2105` and `PostRecordDetailsView:1840`. Both
are the moment the member commits the share, both are pre-queue, and both are
downstream of **every** acquisition path — camera, recordings, photo picker,
file import. **So one rule can own the decision without scattering size logic
across acquisition paths**, which was the stated goal.

The inclusion rule is already available client-side: the publish path decides by
`AttachmentPrivacy.isPrivate(id:url:)`, which the editor can evaluate over its
own attachments. **The preflight inspects only the explicitly-shared set.**

**Consent UI itself is modest** — an alert with Cancel / Share Without It at two
sites, plus a pure helper computing the oversized-and-shared set.

---

## 5. THE FORK I AM NOT CHOOSING ALONE

**Making `Share Without It` honest needs a decision, and both options have a
real cost.**

The publish path decides inclusion **solely** from `AttachmentPrivacy`. Consent
is a per-publish fact that nothing currently carries.

**Option A — carry an exclusion in the payload.** `PostPublishPayload` is
`Codable` and **persisted to disk**, so a new field is a **queue file-format
change**. It can decode with a default for legacy files — `op` set exactly that
precedent (P4-U2a-2/U2c) — but that record shows this project treats queue
format changes as declared migrations, not incidental edits.
*Buys:* consent is durable; a retry after a container rotation still excludes
exactly what the member authorised, and nothing else.

**Option B — consent is a UI gate only, and the existing skip proceeds.** No new
state anywhere. The member is told before queueing, so nothing is silent **at the
moment of consent**.
*Costs:* the consent is not recorded, so a later automatic retry re-skips
**without re-asking**. Defensible — they consented for this post — but it means
the queue itself still cannot distinguish an authorised omission from an
unauthorised one, which is the property C-73 exists to complain about.

**What I must NOT do, and did not:** flip the attachment's privacy flag to
achieve exclusion. That would rewrite the member's stated intent and persist it,
silently un-sharing the attachment forever.

## 6. What this means for C-73

**Under either option, ordinary oversize leaves C-73** — the member is told
before anything is queued, so no oversized attachment ever reaches the queue
uninvited. **Under Option B, C-73 keeps one thin remnant:** the queue still
cannot represent *"this omission was authorised"*, which matters only on retry.
**Under Option A it leaves cleanly**, and C-73 narrows exactly as intended to
corrupt / encrypted / permanently unrenderable supported content.

## 7. What I need

1. **Option A or Option B** for `Share Without It`.
2. Confirmation that **C-63's refusal belongs at import** — `.fileImporter`
   currently accepts `[.item]`, so honest refusal means either narrowing
   `allowedContentTypes` to the supported set (the system picker then greys
   unsupported files out) or accepting the pick and refusing it with a message.
   **The first changes what the member can even select locally**, which touches
   local-Journal capability — so I am reporting it rather than choosing, per
   instruction.
3. Whether **C-74** should be scheduled near this work (it shares
   `kindForURL`/`contentType`) or left to a later unit.

**Nothing implemented. No gate weakened, no production mutation, no picker
change, no format support invented.**
