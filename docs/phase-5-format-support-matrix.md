# ÉTUDES FORMAT SUPPORT MATRIX — MEASURED. REPORT BEFORE MUTATION.

**Established 2026-09-10 at `a05f130`. No code changed, no bucket widened, no
production mutation.** Audio decodability is **measured** on the simulator with
real fixtures; image acquisition behaviour is **source-derived and explicitly
not measured**, because it needs a real photo library.

---

## 0. THE ROOT CAUSE IS ONE MECHANISM, NOT EIGHT SPECIAL CASES

**The source file's extension is DISCARDED at staging and regenerated from the
KIND alone.**

`stageData(_:kind:displayName:)` takes only bytes and a kind —
`StagedAttachment` holds `(id, data, kind)` and **never the source URL,
filename or extension**. Then both `commitStagedAttachments` (`:484`) and
`surrogateURL(for:)` (`:699`) rebuild an extension from a per-kind default:

```
image → "jpg"   audio → "m4a"   video → "mov"   pdf → "pdf"   file → "dat"
```

and `contentType(for:kind:ext:)` (`BackendShim:1514`) derives the MIME **from
that fabricated extension**.

**So the declared MIME describes the KIND'S DEFAULT, never the bytes.**

**And those defaults are exactly right for Études' own capture** — the audio
recorder writes `motivo_rec_*.m4a` with `kAudioFormatMPEG4AAC` (`AudioRecorderView:213`,
`:301`), the video recorder writes `motivo_vid_*.mov`. **That is why this has
never caused a visible problem: the defaults encode the assumption that every
attachment came from Études' own recorders.** Everything imported is
renamed and relabelled to match an assumption that is false for it.

**This subsumes C-74.** An imported **PNG** is stored `<uuid>.jpg` and declared
`image/jpeg` — not an exotic case at all. So is every imported WAV, MP3 and
AIFF, as `<uuid>.m4a` / `audio/m4a`.

**Nothing breaks locally**, which is the other half of why it went unnoticed:
`AVAudioPlayer` and `UIImage` sniff content and ignore the extension. **Measured,
see §2.**

---

## 1. Audio — MEASURED with real fixtures

`afconvert` from a `say`-generated AIFF; `AVAudioPlayer(contentsOf:)` on the
iPhone 17 Pro simulator (iOS 26.5). A non-vacuity control proves the probe can
fail (`MOTIVOTests/AudioFormatSupportProbe.swift`).

| Format | Picker can select? | Classified | **Decodes locally** | Truthful MIME | Bucket allows? | Origin |
|---|---|---|---|---|---|---|
| **M4A / AAC** | yes | `.audio` | **YES (measured)** | `audio/m4a`, `audio/aac` | **YES** | **Études' own recorder** |
| **WAV** | yes | `.audio` | **YES (measured)** | `audio/wav` | **YES** | deliberate import |
| **MP3** | yes | `.audio` | not measured (no encoder to hand) | `audio/mpeg` | **YES** | deliberate import |
| **AIFF / AIF** | yes | `.audio` | **YES (measured)** | `audio/aiff` | **NO** | deliberate import |
| **CAF** | yes | `.audio` | **YES (measured)** | `audio/x-caf` | **NO** | accidental breadth |
| **FLAC** | yes | **`.file`** ← not recognised | **YES (measured)** | `audio/flac` | **NO** | deliberate import |

**THE SHARPEST CONSEQUENCE IN THIS DOCUMENT:** today an imported **AIFF** uploads
successfully *because it is mislabelled* as `audio/m4a`. **Telling the truth
about it would get it REFUSED by the bucket.** So C-74's fix and the bucket
policy are **coupled** — truthfulness alone would break a currently-working
import.

### FLAC status and cost

**Not supported today**: `kindForURL` does not list it, so a `.flac` import
becomes `.file` — inert in the viewer (`AttachmentViewerView` breaks out of every
playback path for `.file`) and unable to upload.

**Decoding is NOT the obstacle — measured, it works.** The cost is four items,
three of them one-liners:
1. `kindForURL`: `flac` → `.audio`;
2. `contentType`: `flac` → `audio/flac`;
3. **extension preservation** (§0) — without it a FLAC is written as `.m4a` and
   the mapping never fires;
4. **bucket policy: add `audio/flac`** — a **production mutation needing explicit
   approval**.

**No new player, no new viewer path, no new UI.** Item 3 is shared with C-74 and
is the real work.

## 2. Images — SOURCE-DERIVED, NOT MEASURED

| Format | Picker | Classified | Local display | Truthful MIME | Bucket | Origin |
|---|---|---|---|---|---|---|
| **JPEG** | PhotosPicker / camera / import | `.image` | yes | `image/jpeg` | **YES** | **Apple-native** |
| **PNG** | import | `.image` | yes | `image/png` | **YES** | deliberate import |
| **HEIC** | **PhotosPicker (iPhone default)** | `.image` | yes | `image/heic` | **YES** | **Apple-native** |
| **HEIF** | PhotosPicker | `.image` | yes | `image/heif` | **YES** | **Apple-native** |
| GIF, BMP, TIFF/TIF | import only | `.image` | yes | `image/gif` etc. | **NO** | **accidental breadth** |

**HEIC/HEIF needs your attention and I could not measure it here.** A modern
iPhone's PhotosPicker returns HEIC data; the code takes
`item.supportedContentTypes.first`, sees conformance to `.image`, and stages it
as `.image`. Per §0 it is then written as `<uuid>.jpg` and declared
`image/jpeg`. **The bucket allows `image/heic` and `image/heif`, so we are
declaring the wrong type for the most common iPhone photo format** — and
`contentType` has a `heic` branch but **no `heif` branch** at all.
**Unverified: I have no photo library here. It needs a device check.**

**GIF/BMP/TIFF are accidental breadth** — reachable only by file import, allowed
by no bucket policy, and part of no Études workflow.

## 3. Video

| Format | Classified | Truthful MIME | Bucket | Origin |
|---|---|---|---|---|
| **MOV** | `.video` | `video/quicktime` | **YES** | **Études' own recorder** |
| **MP4** | `.video` | `video/mp4` | **YES** | PhotosPicker / import |
| M4V, AVI | `.video` | `video/x-m4v`, `video/x-msvideo` | **NO** | **accidental breadth** |

An imported **MP4** currently gets the `.video` surrogate extension `mov` and
uploads as `video/quicktime`. Both are bucket-allowed, so it works — while
mislabelled.

## 4. Documents

**PDF only**, deliberately, for score/document import: classified `.pdf`,
`application/pdf`, bucket-allowed, and it publishes as a **JPEG thumbnail
representation** rather than the PDF itself. **No broadening** — MIDI, MusicXML,
Guitar Pro, Word, ZIP are not in scope.

---

## 5. Deliberate vs accidental — the answer to questions 2 and 3

**Deliberately supported (Études workflows):** M4A/AAC · MOV · JPEG · HEIC/HEIF ·
MP4 · PDF.
**Legitimate musician imports:** WAV · MP3 · AIFF · PNG · (**FLAC**, if approved).
**Accidental breadth, recognised only because an old extension switch lists
them:** GIF · BMP · TIFF/TIF · CAF · M4V · AVI. **None is bucket-allowed, none
belongs to a workflow, and none needs preserving.**

## 6. Proposed narrowed system-picker types

`.fileImporter` currently takes `[.item]` — anything. Proposed:

```
[.pdf, .wav, .aiff, .mp3, .mpeg4Audio, .audio (for m4a/aac), .png, .jpeg]
+ UTType(filenameExtension: "flac")  ← only if FLAC is approved
```

**Images stay selectable by import** (a scan or a chart is a plausible musician
case) but only PNG/JPEG. **This narrows what a member can pick locally**, which
is why it is proposed rather than done.

## 7. Bucket changes required — NONE without your approval

- **For the musician audio set as-is:** add **`audio/aiff`** (and `audio/x-aiff`)
  — otherwise truthful labelling refuses a currently-working import.
- **For FLAC:** add **`audio/flac`**.
- **Nothing else.** GIF/BMP/TIFF/CAF/M4V/AVI would be **refused honestly at
  import** instead, per the product model.

## 8. Smallest durable `Share Without It` representation

`PostPublishPayload` already persists as `Codable` JSON. The smallest honest
addition is **one optional field carrying the attachment ids the member
authorised omitting** — e.g. `authorisedOmissions: [UUID]?` — consulted by
`loadIncludedAttachments`' caller so those ids are excluded from the prepared
set.

- **Backward decoding:** optional with a `nil` default, exactly the `op`
  precedent (P4-U2a-2). Legacy files decode unchanged.
- **Retry semantics:** the exclusion travels with the item, so a retry after a
  container rotation omits **exactly** what was authorised and nothing else.
- **Rollback:** an older build ignores an unknown key; the field is additive and
  carries no behaviour of its own.
- **The privacy flag is NOT touched** — that would rewrite and persist the
  member's stated intent.

## 9. Currently persisted beta queue items

**Measured: none.** The queue is per-device local state, and production holds
**zero** posts pending from this work. The only queue readers are
`DebugViewerView` (absent from Release) and `flushNow`. **A device could still
hold a queued item**, which is exactly why the field must decode as `nil` rather
than be required — and it does.

---

## 10. What I recommend, and where I stop

**This is bounded, but it is NOT the small unit C-63 looked like**, and it has
one branch I will not take alone: **the extension-preservation fix (§0) is the
prerequisite for everything else**, and it changes what is written to disk for
newly imported attachments.

**I have implemented nothing.** I need:
1. **FLAC in or out**, given the cost is §1's four items.
2. **Approval, or not, for `audio/aiff`** — without it, truthful labelling must
   refuse AIFF at import instead.
3. **Confirmation of the narrowed picker list (§6)**, which reduces local
   selection.
4. **A device check on HEIC/HEIF**, which I cannot perform here.
