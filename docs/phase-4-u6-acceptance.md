# P4-U6 / C-51 — COMPLETE 2026-09-05. VERIFIED, NO PRODUCTION CHANGE

**Prediction `c09bcf1`, committed before the test was written.**
Client checkpoint `7744027`; server checkpoint `dfba1d8`, both untouched.

**C-51 is DISCHARGED as coverage.** The queued-publish/container-rotation route
is now exercised by fault injection and the attachment **survives**. Zero
production files changed — `git diff --name-only 7744027 -- MOTIVO/ supabase/`
is empty.

---

## 1. THE FAULT INJECTED

**The persisted `Attachment.fileURL` has its container UUID replaced while the
real bytes stay where they are, between enqueue and flush.**

```
before  …/Application/<containerA>/Documents/<attID>.jpg   (file present)
after   …/Application/<containerB>/Documents/<attID>.jpg   (file NOT there)
                                   ^^^^^^^^^^ rotated
```

That is exactly what an in-place app update does — established on Device A,
2026-08-15 — and it is injected at the one moment that matters: **while the
`.publish` intent is sitting in `SessionSyncQueue`.** The member never touches
the session again, so the editor's self-healing save cannot run, which is
precisely why this route is the only one that can reach upload selection with a
stale path.

**Sequence:** fixture → go offline → publish (enqueues) → assert queued →
**decode the real queue file from disk** → rotate the container → reconnect →
`flushNow()` only.

---

## 2. RESULT — ALL SIX PREDICTIONS HELD

| # | prediction | measured |
|---|---|---|
| **P1** | correct path → **1** object *(positive control)* | **1** |
| **P2** | **stale container path → 1 object — C-51's condition** | **1** |
| **P3** | file absent everywhere → **0** objects, row still created | **0**, row present |
| **P4** | pre-U2 semantics miss what the canonical resolver recovers | held |
| **P5** | the `.publish` survives decode from the real queue file | held |
| **P6** | no production change; gates green | held |

**P2 is the unit.** A shared publish queued before an app update still uploads
its media after it. The pre-U2 consequence — *post published, media silently
missing, no error anywhere* — does not occur.

---

## 3. THE PRE/POST DISCRIMINATOR

`P4` replicates the pre-Phase-2 semantics named in `resolveLocalFileURL`'s own
header — *any stored value containing a slash was returned verbatim* — and runs
both against the same rotated input:

| resolver | returns | file exists? | consequence |
|---|---|---|---|
| **pre-U2** (`stored.contains("/") ? URL(fileURLWithPath: stored) : nil`) | the stale path | **NO** | caller's `fileExists` fails → `continue` → **silently skipped** |
| **canonical** `AttachmentPathResolver.resolve` | the file in the CURRENT container | **YES** | uploaded |

**P3 is the second half of the discriminator, and it is what stops P2 being a
property of the harness.** When resolution genuinely fails the count really is
**0** — so P2's **1** is a measurement.

---

## 4. THE POSITIVE CONTROL FAILED FIRST, AND THAT IS THE UNIT'S REAL FINDING

**P1 was asserted before P2 deliberately, and it failed:** `attachments: []`,
0 objects, on a fixture with a **correct** path.

`SharedOnlyUploadTests` had recorded exactly this symptom and left the cause
**unestablished**, declining to call it a product defect. **Without P1 first,
P2 would have "passed" as 0 == 0 and C-51 would have been recorded as verified
on a harness that cannot upload anything.**

**The cause is now established, and it was the FIXTURE.** Diagnosed in stages
rather than guessed:

1. every stage of `loadIncludedAttachments` was replicated and **all passed** —
   session fetched, relationship cast, id present, path resolved, file exists,
   `isPrivate == false`;
2. the same stages **still passed immediately after a real publish**, while the
   row read `attachments: []` — so the fixture was sound;
3. the row carried `title: "u6"`, so `patchPostMetadata` had succeeded and
   `uploadPost` **had reached** the attachment block; and the item was **still
   queued**, meaning `uploadPost` returned *failure*, unlike the
   no-attachment control which dequeues;
4. the Storage service log named it outright:

```
POST /object/attachments/users/<uid>/<postID>/<attID>.jpg
content-type: application/octet-stream
→ 415  InvalidMimeType: "mime type application/octet-stream is not supported"
```

**The fixture set `kind: "photo"`. `AttachmentKind` is `audio|video|image|file|
pdf`,** so `contentType(for:ext:)` fell to `default:` →
`application/octet-stream`, which is absent from the bucket's
`allowed_mime_types` → 415 → `uploadPost` failed → the row kept its **default**
empty `attachments`.

**`attachments: []` never meant "the selection was empty".** It is also the
column default, so it could not distinguish "nothing was selected" from
"the upload failed before the PATCH" — which is why step 3 above (title
written, item still queued) was needed to tell them apart.

**Production carries the IDENTICAL `allowed_mime_types`** — verified read-only
against production and against the committed snapshot — **so the local stack was
faithful throughout and the product is correct.** Corrected in both test files,
and `SharedOnlyUploadTests`'s comment is amended in place with the superseded
sentence quoted rather than deleted.

**One method error of my own is recorded rather than quietly dropped:** a manual
probe returned `NoSuchBucket` and I briefly took it as evidence the reset had
desynchronised Storage. It had not — I had omitted the bucket segment from the
path. The service log is what corrected me.

---

## 5. WHY NO FIX WAS MADE

**The measured failure was in the test fixture. There was no measured
production failure**, so the smallest fix required is none. The exposure was
already closed by Phase 2 U2, and U6's job was to prove it — which it now does,
by injection rather than inference.

**Two candidate residual defects were sought and both falsified by reading**
(recorded in `phase-4-u6-prediction.md` §2): `AttachmentPrivacy.isPrivate` is
consulted with the resolved URL, but `privacyKey` prefers `"id://<uuid>"` and
the publish route guards a non-nil id, so it is container-independent; and no
call site passes a nil id.

**U2b's interaction is noted, not claimed as the resolution:** a private session
no longer enqueues, so only a *shared* publish can carry a stale path into a
queued flush. That narrows the population; it does not close the route.

---

## 6. GATES

| gate | result |
|---|---|
| Debug / Release builds | **BUILD SUCCEEDED** / **BUILD SUCCEEDED** |
| `MOTIVOTests` | **TEST SUCCEEDED**, **49 passed**, 0 failed (45 + 4 new) |
| `u6b/acceptance.sh` | **64 passed, 0 failed** |
| `u2a / u2a2 / u2b / u2c / u2s / u5-client` | 16 / 22 / 16 / 20 / 12 / 30, **all 0 failed** |
| `u1-baseline.sh` | 10 passed, **6 failed — the standing expected inversions** |
| production delta | **zero files** under `MOTIVO/` or `supabase/` |

`u1-baseline`'s six failures are U2a/U2b/U2s's own successes; it returns
**16 of 16** against its own commit `f12330e`. None touches attachments.

---

## 7. WHAT THIS DOES NOT CLAIM

- **Not device-verified.** Simulator plus local stack. The rotation is injected
  by rewriting the persisted path, which reproduces the *condition* but not an
  actual iOS container migration.
- **The 415 path is now understood but is NOT separately covered.** An
  unrecognised `kind` still uploads as octet-stream and fails; no shipping code
  produces one, so no finding is filed.
- **Attachment identity is unchanged.** Path-as-identity remains M13/M14.

---

## 8. REMAINING PHASE 4 OBLIGATIONS

- **P4-U7 — C-58**, follower attribution for a lapsed viewer (P3, product/UX).
- **P4-U8 — D-1 and C-32** (C-32 jointly with RC).
- **The physical-device QA pass**, carrying **U2b's device verification** and
  **C-34's device verification**, both deliberately deferred to it.

B-37 is **Phase 6**. The five dangling `connected_attachments` references were
cleared by the U4 follow-on at `4ee7a0b` and are not outstanding.
