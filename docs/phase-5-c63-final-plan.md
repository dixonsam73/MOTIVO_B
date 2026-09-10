# C-63 / C-74 / 50 MB — FINAL BOUNDED PLAN. NOTHING IMPLEMENTED.

**Measured 2026-09-10 at `a86f860`. No production mutation, no bucket widened.**
Audio and derivative numbers are **measured**; video numbers are **derived from
the app's own writer settings**; HEIC/HEIF is **unmeasured and needs a device**.

> **HEADLINE: this is materially larger than one unit, and §18 proposes a
> three-way split.** Audio optimisation is cheap and decisive. Video is not.

---

## 1. Deliberate supported-format matrix

| | Deliberate | Origin | Local decode |
|---|---|---|---|
| **Audio** | M4A · WAV · AIFF/AIF · MP3 · **FLAC** | recorder / import | **all measured OK** |
| **Images** | JPEG · PNG · HEIC · HEIF | camera, PhotosPicker, import | yes |
| **Video** | MOV · MP4 | recorder / picker | yes |
| **Documents** | PDF | deliberate import | yes |
| **Dropped** | GIF · BMP · TIFF/TIF · CAF · M4V · AVI | accidental extension breadth | — |

## 2. Storage allow-list — current vs proposed

**Current, 13 values:** `application/pdf` · `audio/aac` · `audio/m4a` ·
`audio/mp4` · `audio/mpeg` · `audio/wav` · `audio/x-m4a` · `image/heic` ·
`image/heif` · `image/jpeg` · `image/png` · `video/mp4` · `video/quicktime`.

**Every deliberate format is already covered EXCEPT AIFF and FLAC.**

**TWO POLICIES — and the smaller one needs NO production mutation at all:**

- **Policy A — "the Connected audio representation is always M4A/AAC."**
  Lossless and non-native sources are always converted for Connected; the local
  original is untouched. **Bucket change: NONE.** Uniform, always truthful, and
  it removes the AIFF-refusal coupling entirely. Cost: a small WAV is transcoded
  unnecessarily (measured sub-second), and Connected carries a lossy
  representation — acceptable on a *listening* surface.
- **Policy B — pass through when already ≤50 MB, convert only when oversized.**
  Preserves lossless fidelity for small files. **Requires adding `audio/aiff`
  and `audio/flac`** — exactly two values, and nothing else.

**RECOMMENDATION: Policy A.** It is smaller, needs no production change, and
follows the derived-representation model you set out in §1 of your instruction.
**Policy B is entirely reasonable** if lossless-on-Connected matters to you.

## 3. Raw AAC — MEASURED, and the answer is "no benefit"

A real ADTS `.aac` fixture **opens in `AVAudioPlayer` and is readable by
`AVURLAsset`**. So it *could* be supported. **But it adds nothing M4A does not
already give** — same codec, less metadata capacity, and no musician tool
exports bare ADTS by default. **Recommend: leave `.aac` OUT of the deliberate
import set.** M4A is sufficient, as you suspected.

## 4. HEIC/HEIF — the one thing I cannot measure here

**Smallest Device-B check** (Release; no account state, no destructive action):
1. Add an **ordinary iPhone photo** to a session via the photo picker.
2. Open the session's debug sheet (long-press the content) and read the
   attachment's stored `fileURL` — **report the extension**.
3. Confirm the photo **displays** in the attachment viewer.
4. Report whether the file on disk is HEIC (the debug sheet's byte size vs a
   known JPEG is a weak signal; the extension is the real answer).

**Prediction from source, to be falsified or confirmed:** it is stored
`<uuid>.jpg` with HEIC bytes and would upload as `image/jpeg`. **The `heic`/
`heif` asymmetry** — `contentType` has a `heic` branch and **no `heif` branch**
— is dispositioned by §5's change either way, because format identity then comes
from the validated source rather than from a fabricated extension.

## 5. The staged-attachment format-identity change — THE ROOT FIX

`StagedAttachment` currently holds `(id, data, kind)` and discards the source
extension; `commitStagedAttachments` and `surrogateURL` then fabricate one from
the kind, and the MIME follows from that fabrication.

**Smallest change: carry a VALIDATED format, not the source URL or filename.**
Add one optional field — a small enum or a validated extension string — set only
when the importer recognises the bytes' format as a deliberate one, and `nil`
for Études-generated media (which keep their known formats). Both extension
sites consult it, and `contentType` maps from it.

**No source URLs or filenames are retained**, per your instruction.

## 6. Historical attachments — NO MIGRATION

Existing attachments keep their fabricated extensions. They decode locally
regardless (players sniff content), and **no concrete compatibility requirement
has emerged**. Any already-uploaded object keeps whatever MIME it was given;
re-uploading is out of scope.

## 7. Narrowed picker types

`.fileImporter` moves from `[.item]` to the deliberate set:
`[.pdf, .wav, .aiff, .mp3, .mpeg4Audio, .png, .jpeg]` **plus a FLAC UTType**
(`UTType(filenameExtension: "flac")`). The PhotosPicker branch that conforms to
neither `.image` nor `.movie` **refuses honestly** instead of creating `.file`.

## 8–9. Audio optimisation — FEASIBLE, CHEAP, DECISIVE (measured)

**Existing machinery is reusable:** `MediaTrimView` already exports through
`AVAssetExportSession` with `AVAssetExportPresetAppleM4A` and a preset ladder
(`:1205`–`:1232`).

**Measured, 60 s 44.1 kHz stereo source, all three lossless sources exporting
successfully to M4A:**

| | Size |
|---|---|
| WAV / AIFF source (44.1 kHz stereo 16-bit) | **10.1 MB/min** → 50 MB at **~5 minutes** |
| `AVAssetExportPresetAppleM4A` output | **0.75 MB/min, ~105 kbps** *(on a synthetic tone; real music sits nearer the preset's ~128 kbps target, so budget **≈0.95 MB/min**)* |

**At ~1 MB/min a 50 MB ceiling is ~50 minutes of audio** — so an M4A derivative
effectively never breaches it for realistic material.

**Quality recommendation — and I am NOT choosing a low bitrate to force files
under the limit.** Two options:

| | API | Bitrate | Size | 50 MB at |
|---|---|---|---|---|
| **Simplest** | `AVAssetExportPresetAppleM4A` (already used) | ~128 kbps | ~0.95 MB/min | ~52 min |
| **Musician-grade** | `AVAssetReader`/`AVAssetWriter` with explicit AAC settings | **256 kbps** | ~1.9 MB/min | ~26 min |

**RECOMMENDATION: 256 kbps AAC**, 44.1 kHz, stereo preserved — near-transparent
for reference mixes and bounces, and 26 minutes of headroom is far beyond any
realistic shared attachment. It costs an explicit writer path rather than the
one-line preset. **Your call; I will not pick the quality target.**

Off-main-thread: `AVAssetExportSession` is asynchronous by construction and the
publish path is already `async`. Sample rate and channels are preserved by the
settings; duration is unchanged; existing `temporaryFileURL` cleanup (extended
by C-65) already covers the temp lifecycle.

## 10. Video optimisation — FEASIBLE BUT MATERIALLY RISKIER. RECOMMEND SPLITTING

**Current recording characteristics, read from source:** `AVAssetWriter`, **HEVC,
1080p**, `AVVideoAverageBitRateKey: 5_000_000` (`VideoRecorderView:938`–`:942`),
session preset `.hd1920x1080` (`:702`).

**So Études' own video crosses 50 MB at ≈ 5.06 Mbps → ~83 SECONDS.** A
one-and-a-half-minute clip already exceeds the Connected ceiling.

`MediaTrimView`'s ladder (`HEVC1920x1080`, `1920x1080`, `1280x720`,
`MediumQuality`) is reusable, so the API is not the problem. **The risk is:**
transcode time and battery on a foreground publish path, A/V sync, orientation
and rotation metadata, and the fact that a retry would re-transcode. **This is a
different size of problem from audio and should not ride along with it.**

## 11. Image optimisation — NOT NEEDED

An iPhone HEIC photo is ~2–4 MB and a PNG screenshot far less. Nothing in the
deliberate image set realistically approaches 50 MB. **Build nothing.**

## 12. The 50 MB flow after optimisation

Over the **explicitly share-enabled set only** — a private attachment of any size
is never inspected, never warned about, never blocks:

```
for each explicitly shared attachment:
    ≤ 50 MB and a supported Connected MIME  → publish as-is
    > 50 MB and audio                       → build M4A derivative → ≤50 MB → publish derivative
    > 50 MB and video                       → (Unit 3) derivative; until then → consent
    derivative still > 50 MB, or none exists, or it fails → CONSENT
```

**Consent, only then:** *"Attachment too large to share — This attachment can't
be included in this Connected post. It will remain in your Journal."* ·
**Cancel** / **Share Without It**. Multiple oversized attachments are named
compactly in one alert; **no attachment-management subsystem.**

## 13. Durable `Share Without It`

`PostPublishPayload` gains **one optional field** carrying the attachment ids the
member authorised omitting. Optional with a `nil` default — the `op` precedent
(P4-U2a-2) — so **legacy queue files decode unchanged**; an older build ignores
an unknown key, so **rollback is safe**; the exclusion travels with the item, so
**a retry omits exactly what was authorised**. **The private-eye state is never
mutated.** **Measured: production holds no pending items**, and a device may, which
is precisely why the field must decode as `nil` rather than be required.

## 14. Derivative persistence — REGENERATE, DO NOT PERSIST

**The derivative is NOT stored in the queue.** It is rebuilt at publish time from
the local original, which is stable and untouched. This satisfies all five of
your invariants without a media-processing queue:

- **retry cannot change what was authorised** — consent is in the payload (§13);
- **no duplicates** — the object path is `users/<owner>/<postID>/<attachmentID>.<ext>`,
  deterministic and independent of the bytes, and upload sends `x-upsert: true`;
- **no needless transcoding in the ordinary case** — a successful publish
  dequeues, so regeneration happens only on a retry. **CORRECTED 2026-09-10:
  that omitted the case that matters — a publish which keeps failing stays
  queued and RECONVERTS ON EVERY FLUSH, with no cap and no backoff. Filed as
  C-76**; not established as a shipping defect, since a real member's publish
  succeeds, but the original wording read as a guarantee it is not;
- **no leak** — the existing `temporaryFileURL` cleanup covers both the success
  and (since C-65) the failure path;
- **relaunch is safe** — everything needed is the payload plus the untouched
  local original.

**This is the reason to prefer audio-only first:** re-transcoding a minute of
audio on a retry is trivial; re-transcoding a video is not.

## 15. Expected changes

**Files:** `AddEditSessionView+Attachments` (format identity, extensions, picker,
import refusal) · `AddEditSessionView` + `PostRecordDetailsView` (preflight and
consent at the two publish call sites) · `BackendShim` (`contentType`, derivative
hook) · `SessionSyncQueue` (one payload field) · one new pure type for the
derivative decision · one new type for the audio derivative.
**Schema:** none. **Payload:** one optional field. **Production:** none under
Policy A; two MIME values under Policy B.

## 16. Required Storage mutation

**Policy A: NONE. Policy B: add exactly `audio/aiff` and `audio/flac`.**
Either way I will produce the exact before/after policy and a read-only
verification before proposing any change, and **will not mutate the bucket
without explicit approval.**

## 17. What remains C-73

Corrupt PDFs, encrypted PDFs, and supported media that is present but
**permanently undecodable/untranscodable**. **Oversize leaves C-73 entirely** —
it is either optimised automatically or consented to before queueing.

---

## 18. PROPOSED SPLIT — say so, rather than force one unit

**Unit 1 — Format identity & truthfulness (C-74 + C-63's generic half).**
Preserve validated source format, truthful extension and MIME, narrow the picker,
refuse `.file` and the PhotosPicker edge case honestly. **No 50 MB work, no
derivative, no bucket change.** Self-contained and independently verifiable.

**Unit 2 — Audio Connected derivative + 50 MB preflight + durable consent.**
Depends on Unit 1's format identity. Oversized *video* uses the consent fallback
here.

**Unit 3 — Video Connected derivative.** Separate and later, on its own
evidence. **Do not fold it into Unit 2.**

**If you would rather not split, Unit 1 + Unit 2 together is still coherent** —
it is Unit 3 that must stay out.

**Standing:** measurement artefacts `AudioFormatSupportProbe` and
`ConnectedDerivativeProbe` (plus their fixtures) are retained while these
decisions are open; if a decision makes one moot it should be retired rather
than left asserting a world we did not choose.
