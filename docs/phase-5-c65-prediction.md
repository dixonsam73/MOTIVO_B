# C-65 — PREDICTION, COMMITTED BEFORE PRODUCT MUTATION

**Inspected at `49e21be`, 2026-09-09.** Investigation:
`docs/phase-5-c65-investigation.md`.
**Invariant being implemented:** if a member explicitly selected an attachment
for sharing and it cannot be prepared for remote publication, Études must not
report complete success while silently publishing the post without it.
**Preparation must therefore complete before the post row is created.**

---

## 1. The oversize pre-queue check you asked me to look for — IT EXISTS, AND IT IS NOT SUFFICIENT

`AddEditSessionView+Attachments.handleFileImport` (`:412`–`:415`) already
preflights the 50 MB cap and shows *"This attachment is larger than 50MB and
will stay local (it won't publish)."*

**Two reasons it does not resolve the oversize case today:**

1. **It warns; it does not reject.** Its own comment says *"Preflight publish cap
   warning (do not block local attach)"*, and the attachment is staged anyway.
2. **Its coverage is one path of several.** It is the **only** reader of
   `publishUploadLimitBytes` (`AddEditSessionView:272`). The common staging
   funnel is **`stageData(_:kind:displayName:)` (`:344`), which has no size check
   at all** — so photo/camera/recording-produced attachments reach the queue
   with no warning whatever.

**Reported as the preferred smaller solution for the FOLLOW-UP, not built here:**
`stageData` is the single funnel where a complete pre-queue check would live.
**C-65 does not change oversize behaviour**, per your instruction that it belongs
to the permanent-failure follow-up unless a *clean* pre-publish rejection surface
already exists. It does not.

**Noted in passing:** the 50 MB limit is a duplicated literal in **three** places
— `BackendShim:898`, `ConnectedAttachmentSharing:172`,
`AddEditSessionView:272`. A drift hazard; not touched here.

## 2. Which preparation failures can safely stay in the retry path — IDENTIFIED, NOT IMPLEMENTED AS A DISCRIMINATOR

| Cause of `prepareAttachmentForRemoteUpload` returning nil | Retry converges? |
|---|---|
| local file missing / path unresolvable after a container rotation (P4-U6's condition) | **yes** |
| transient memory pressure during render | **yes** |
| corrupt PDF | **no** |
| encrypted / password-protected PDF | **no** |
| structurally unrenderable PDF (the C-10 control fixture, `/Count 0`) | **no** |
| JPEG encode or temp-file write failure (`:1284`, `:1300`) | usually transient |

**`AttachmentStore.generatePDFThumbnail` returns `UIImage?` with no error**, so
these are not distinguishable at that call site.

**DECISION: C-65 adds NO discriminator.** Every preparation failure returns
`.failure` and stays queued. A `fileExists` check would be, as you say, one
signal and not a classifier — adding a half-classifier now creates a second
thing to reason about without resolving the permanent class. **The permanent
class retrying indefinitely is the residual, and it goes to the follow-up.**

---

## 3. PREDICTION

**P1 — ordering.** `loadIncludedAttachments` and **all** preparation move
**before** the `rest/v1/posts` INSERT. After the change, no `POST rest/v1/posts`
can execute until every included attachment has been prepared successfully.

**P2 — atomicity on failure.** If any preparation fails: **no post row is
created, no storage object is uploaded, and every temporary file already created
by this attempt is deleted.** `uploadPost` returns `.failure`.

**P3 — the queue does not dequeue.** `SessionSyncQueue.flushNow` leaves the item
queued on `.failure` (`:299`), so it retries on the next launch/foreground —
existing semantics, no new architecture, no new state.

**P4 — success path unchanged.** A valid PDF still publishes through its JPEG
representation (`remoteKind: "image"`, `ext: "jpg"`,
`contentType: "image/jpeg"`); image, audio and video attachments are unaffected;
the `included.isEmpty` branch still PATCHes `refs: []` **after** the insert.

**P5 — retry stays idempotent.** The 409-as-created branch, `x-upsert: true` and
the idempotent attachment PATCH are all untouched, so a retry creates no
duplicate row and no duplicate object.

**P6 — the unreachable branch is removed.** After the hoist, the post-insert
`guard let prepared = … else { continue }` no longer exists. The non-PDF arm of
that guard was **already dead** (`prepareAttachmentForRemoteUpload` returns nil
only for PDFs), and it must not survive as dead code.

**P7 — oversize is untouched** and still skips, per §1. Its row is filed
separately.

### Evidence

**Pre-fix control, behavioural, against the local stack** — the harness
`SharedOnlyUploadTests` already uses (`XCTSkip` if unreachable; **the stack is
up, verified HTTP 200**). Against pre-fix code it must show: an unrenderable-PDF
attachment yields **`uploadPost` → `.success`**, a **post row present**, and
**`attachments` empty**. **If that does not reproduce, I stop and report** — it
would mean the finding's premise is wrong, as C-10's was.

**Post-fix:** the same fixture yields `.failure`, **no post row**, no storage
object; a valid PDF fixture still publishes with one attachment ref. Plus
Debug/Release clean, warning delta measured against `49e21be` in an isolated
worktree, and a structured full-suite census. **No production mutation** — the
local stack only.

---

## 4. Follow-up to be filed after C-65

**Permanent preparation failure has no representable state.** It will own:
non-retrying permanent failures; the member-facing explanation and action; the
queue representation; recovery/removal/replacement semantics; **and the
oversized-attachment case**, including whether the complete fix is a pre-queue
check in `stageData`.

**A permanently failed publish must NOT be silently dequeued to avoid retries.**
