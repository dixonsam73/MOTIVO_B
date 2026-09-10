# UNIT 1 — PREDICTION, COMMITTED BEFORE MUTATION

**At `d031c91`, 2026-09-10.** Policy A · 256 kbps AAC · deliberate import set ·
no production or bucket mutation. Video optimisation is **out** (C-75).

---

## 0. HEIC prediction CONFIRMED on device — and it settles the root cause

Device B, ordinary iPhone camera photo through the normal photo workflow: the
stored `fileURL` extension is **`.jpg`**. **So HEIC bytes are written under a
`.jpg` name and would upload as `image/jpeg`** — the fabricated-extension
mechanism (§0 of the matrix) confirmed on the most common path in the product,
not on an exotic import. **HEIC/HEIF closes inside Unit 1**, since format
identity now comes from the validated source rather than from the kind default.

## 1. A TIMING MEASUREMENT CHANGED THE DESIGN — the preflight is ARITHMETIC, not transcoding

Measured on the host (Apple silicon Mac; **a device will be slower**):

| Source | Derivative | Elapsed | Speed |
|---|---|---|---|
| **5 min** WAV (50.5 MB) | 7.3 MB | **2.59 s** | 116× realtime |
| **10 min** WAV (100.9 MB) | 14.8 MB | **6.92 s** | 87× realtime |

**Ten minutes takes ~7 seconds on a Mac, so expect roughly 15–30 s on device.
That is NOT instant** — and if the preflight had to transcode before queueing to
learn the derivative's size, **the member would wait at Save**.

**CORRECTED 2026-09-10, BEFORE IMPLEMENTATION — MY UPPER-BOUND CLAIM WAS WRONG.**
I wrote that `duration × 256 kbps` is a safe upper bound because every
measurement undershot the request. **That was measured only on a synthetic tone,
which is trivially encodable.** Re-measured with **white noise — the maximally
incompressible signal — the encoder EXCEEDS the request: 263 kbps actual for a
256 k ask, a ratio of 1.0257.** So the theoretical figure is **not** a ceiling,
and the account holder was right to refuse it as one.

**Chosen margin: 1.10×**, roughly four times the measured worst-case excess —
conservative without being excessive, and real music is far more compressible
than white noise.

| | Budget | Max duration |
|---|---|---|
| no margin (**wrong**) | 50 MB | 27.3 min |
| **1.10× (adopted)** | **45.5 MB** | **≈24.8 min** |
| 1.05× (considered) | 47.6 MB | 26.0 min |

**The margin costs ~2.5 minutes of allowed duration.** And it is an optimisation,
never a substitute for validation: **the ACTUAL derivative is still checked
against the real 50 MB limit before upload** — if it exceeds, it must not upload
and must not silently disappear.

**It does not have to.** AAC at a requested bitrate is predictable:
`bytes ≈ duration × bitrate ÷ 8`. Every measurement **undershoots** the request
(195 kbps actual for a 256 k request), so **duration × 256 kbps is a safe UPPER
BOUND**. So:

- **Preflight computes the predicted derivative size from DURATION** — no
  transcode, no wait, no progress UI.
- **Only if the prediction exceeds 50 MB** (≈26 minutes of audio) does the
  consent dialog appear.
- **The actual conversion happens inside `uploadPost`**, which runs in the queue
  flush — **asynchronous and off the member's save path entirely**.

**Consequence: no progress UI in Unit 1.** The member never waits for a
conversion. **The device timing still matters** — it tells us how long a
background conversion occupies the device — and §6 says how it will be captured.

## 2. PREDICTION

**P1 — validated source-format identity.** `StagedAttachment` carries an
optional validated format, set by the importer only for deliberate formats and
`nil` for Études-generated media. `commitStagedAttachments` and `surrogateURL`
consult it instead of fabricating from the kind. **No source URLs or filenames
are retained.**

**P2 — truthful local extension and MIME.** An imported WAV persists as `.wav`,
PNG as `.png`, FLAC as `.flac`, HEIC as `.heic`. `contentType(for:ext:)` gains
the deliberate mappings, **including the missing `heif` branch**.

**P3 — Policy A.** The Connected representation of **any** deliberate audio
source is **M4A/AAC at 256 kbps**, built by `AVAssetReader`→`AVAssetWriter`
preserving the source's sample rate and channel count. **The local original is
never mutated, renamed or replaced.** Remote metadata describes the
**derivative**: `<attachmentID>.m4a`, `audio/m4a`.

**P4 — the 50 MB ceiling applies to the CONNECTED REPRESENTATION.** A 200 MB WAV
is not rejected for being 200 MB; its predicted derivative decides. Preflight
runs **only over explicitly share-enabled attachments** — a private attachment of
any size is never inspected, never warned about, never blocks.

**P5 — consent only when nothing else works.** Predicted derivative > 50 MB, or
conversion fails, or no derivative applies (video): *Cancel* / *Share Without
It*. **Cancel shares nothing. Share Without It persists the exclusion** in the
payload's new optional field. **The private-eye state is never mutated.**

**P6 — the picker narrows** to `[.pdf, .wav, .aiff, .mp3, .mpeg4Audio, .png,
.jpeg]` plus a FLAC UTType. The PhotosPicker branch conforming to neither
`.image` nor `.movie` **refuses honestly** rather than creating `.file`.
**`.file` becomes unreachable from the shipping importers.**

**P7 — regenerate, never persist.** The derivative is rebuilt at publish time
from the untouched original. Deterministic object path + `x-upsert` means a retry
creates no duplicate; temp files are cleaned on both paths (C-65).

**P8 — no bucket mutation, no schema change**, one optional payload field, and
**no third queue state** (C-73 keeps only genuinely unexpected permanent
failures).

**P9 — historical attachments are NOT migrated.** Prospective only.

### Anti-prediction

If truthful MIME turns out to make a **currently-working upload fail** for a
deliberate format, **stop** — that would mean the allow-list analysis (§3 of the
preflight report) is wrong, and the answer is a bucket decision, not a code
workaround.

## 3. Evidence

Pre-fix controls proving: an imported non-JPEG image currently persists as
`.jpg`; imported audio persists as `.m4a` regardless of source. Post-fix: each
deliberate format round-trips truthfully; the derivative is M4A/AAC with truthful
MIME; the oversized path consents rather than omitting; retry stays idempotent.
Debug and Release clean on **clean derived data**; warning delta measured;
structured full-suite census.

## 4. What Unit 1 does NOT close

**C-75** (video optimisation) · **C-73's remainder** · **historical
attachments** · **the derivative's device conversion time**, which needs §6.

## 5. Deliberate scope boundary

No video transcoding · no image optimisation (nothing in the deliberate image set
approaches 50 MB) · no attachment-management subsystem · no generic document
support · no progress UI.

## 6. How the device conversion time will be captured

The conversion runs inside the queue flush, which **already** reports through
`BackendLogger.notice`. Unit 1 adds **one permanent operational line** — source
duration, derivative bytes, elapsed milliseconds — in the same family as the
C-28/C-48 wipe-outcome lines, which the standing removal rule explicitly does not
cover. **No temporary instrumentation, so nothing to remove later.** It carries
numbers only, never file names or member content.

**Device acceptance for the derivative is not claimed until that line has been
read from a real Device-B conversion of a multi-minute source.**
