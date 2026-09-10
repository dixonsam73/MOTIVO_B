# UNIT 1 — THE FIVE PRE-MUTATION ANSWERS. NOTHING IMPLEMENTED.

**Measured 2026-09-10 at `dc9388f`.** No production mutation, no bucket change.

---

## 1. The 256 kbps delta — MEASURED, and it is smaller than feared

**`AVAssetExportPresetAppleM4A` cannot set a bitrate.** An explicit target needs
`AVAssetReader` → `AVAssetWriter`. **I wrote it and ran it** rather than
estimating.

**Result: it works on every deliberate source, at both targets.**

| Source | 256 kbps request | 192 kbps request |
|---|---|---|
| WAV | **1.40 MB/min** (~195 kbps actual) | 1.10 MB/min (~154 kbps) |
| AIFF | 1.40 MB/min | 1.10 MB/min |
| FLAC | 1.40 MB/min | 1.10 MB/min |
| M4A/AAC | 1.37 MB/min | 1.07 MB/min |

*(Actual bitrate undershoots the request on a synthetic tone — AAC allocates by
content. Real music sits nearer the target, so budget **~1.9 MB/min at 256 k**.)*
**50 MB then covers ~26–36 minutes**, far beyond any realistic shared attachment.

**Exact code shape — ~50 lines, stock AVFoundation, no third party:**
`AVURLAsset.loadTracks` → read the source's `CMAudioFormatDescription` for
sample rate and channel count → `AVAssetReaderTrackOutput` (LPCM) →
`AVAssetWriterInput` with `AVFormatIDKey: kAudioFormatMPEG4AAC`, `AVSampleRateKey`,
`AVNumberOfChannelsKey`, `AVEncoderBitRateKey` → pump via
`requestMediaDataWhenReady(on:)` → `finishWriting`.

**Complexity, honestly:**
- **Off-main by construction** — the pump runs on its own queue; the publish path
  is already `async`.
- **Sample rate and channels are preserved from the source**, not hard-coded.
- **Failure modes are few and explicit:** no audio track · reader/writer refuses
  to start · writer error at finish. All map cleanly onto C-65's `.failure`.
- **In-repo precedent exists** — `VideoRecorderView` is already
  "`AVAssetWriter`-based" (`:302`). `MediaTrimView` uses only
  `AVAssetExportSession`, so the *reader→writer transcode* shape is new.
- **One risk checked and cleared:** the pattern produces Swift 6 `Sendable`
  notes for `AVAssetWriterInput`/`AVAssetReaderTrackOutput`. **The project builds
  at `SWIFT_VERSION = 5.0` with no `SWIFT_STRICT_CONCURRENCY` setting**, so these
  are warnings at most, not errors. *(It would need revisiting under Swift 6.)*

**RECOMMENDATION: take the 256 kbps path.** ~50 lines of stock API with three
explicit failure modes is **not** a disproportionate transcoding subsystem, and
the preset's ~128 kbps is a real quality compromise on a musician's product.
**I am not falling back to 128 kbps silently — this is the trade, stated.**

## 2. HEIC/HEIF — the Device-B test

**Use Device B / "Études Dev" (Debug).** No account state, no purchase, nothing
destructive, no production contact.

1. Create or open a session and **add a photo from the photo library** — an
   ordinary iPhone camera photo, **not** a screenshot (screenshots are PNG).
2. Save the session, reopen it.
3. **Long-press the session content** to open the debug sheet.
4. **Report the attachment's `fileURL` — specifically its EXTENSION.**
5. Confirm the photo **displays normally** in the attachment viewer.

**My prediction, to be confirmed or falsified:** the extension is **`.jpg`**
while the bytes are HEIC. **If it reads `.jpg`, the prediction holds.** If it
reads `.heic`, my §0 analysis is wrong about the photo path and I will correct it
before building anything.

*(A screenshot would be PNG and would also read `.jpg` under the current
mechanism, so it cannot distinguish the two hypotheses — hence "camera photo,
not screenshot".)*

## 3. Exact resulting Storage allow-list — UNCHANGED, 13 values

```
application/pdf
audio/aac   audio/m4a   audio/mp4   audio/mpeg   audio/wav   audio/x-m4a
image/heic  image/heif  image/jpeg  image/png
video/mp4   video/quicktime
```

Under **Policy A** the Connected audio representation is **always M4A/AAC**, and
`audio/m4a` / `audio/mp4` / `audio/x-m4a` are **already present**. WAV, MP3,
PNG, JPEG, HEIC/HEIF, M4A, MOV, MP4 and PDF are **all already covered**.

## 4. Is any production Storage mutation required? **NO.**

**None.** Policy A removes the AIFF/FLAC allow-list question entirely — those
formats never reach Connected as originals. **The bucket is not touched by
Unit 1.**

## 5. Persisted-payload backward compatibility — MEASURED BOTH DIRECTIONS

`MOTIVOTests/QueuePayloadCompatibilityProbe.swift`, with a non-vacuity control:

- **FORWARD** — a new build decoding a legacy file that lacks the key: **passes**.
- **ROLLBACK** — an older build decoding a file carrying an unknown
  `authorisedOmissions` key: **passes; the key is ignored.** *(Nothing had
  previously established this direction — `op`'s precedent covered forward only.)*
- **Non-vacuity** — the decoder still **rejects** a genuinely malformed payload,
  so the two passes above are not the decoder simply being permissive.

**Conclusion: the optional field is safe in both directions.**

---

## 6. Unit 1's scope, restated

Source-format preservation · deliberate picker narrowing · **Connected audio
derivative (M4A/AAC, Policy A)** · durable `Share Without It` · 50 MB preflight
**against the Connected representation, not the local original** · C-63/C-74
disposition.

**Out:** video optimisation (**filed as C-75**, with the *Optimise for Connected*
product direction recorded). Oversized video uses Unit 1's consent fallback.
**HEIC/HEIF closure** rides along **if** the device evidence lands cheaply;
otherwise it becomes its own tiny correction unit rather than blocking audio work.

**All five answers are bounded. Ready to proceed prediction-first on your word.**
