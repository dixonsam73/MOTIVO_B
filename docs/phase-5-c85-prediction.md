# C-85 — A TRIMMED VIDEO IS MP4 BUT WAS HANDED OFF AS `.mov` / `video/quicktime`. PREDICTION, COMMITTED BEFORE THE FIX. 2026-09-11

**Provenance:**
- **Pre-existing** at `ce1c38c`, before C-84.
- **Made more reachable by C-84** (`e75a443`): Trim → Save as new now survives
  hydration and relaunch, so more trimmed clips reach Save.
- **Found during C-84's device step 7.** The staged trim was
  `1EF1B2C2-….mp4` where `.mov` had been predicted.

**The account holder's decision, 2026-09-11:**
- **Fix it now, inside C-84's device run, but file it as C-85** so the defect and
  its provenance stay explicit.
- **No transcoding.**
- The **recorder's `.mov` behaviour must stay unchanged.**

## 1. The defect, measured in source

**The trim tool always exports video as MP4**
(`MediaTrimView:1197`, `outputFileType = .mp4` at `:1240`).

**The hand-off (`makeReviewPrefill`) passes a video with no `sourceFormat`.**
So post-record details persists it with the default extension, **`.mov`**
(`AttachmentImportPolicy.defaultExtension`). The upload then declares
**`video/quicktime`** over MP4 bytes (`BackendShim.contentType` →
`MediaFormat.mimeType`).

**The playback surrogate is forced to `tmp/<id>.mov`** in four live places:
- playback (`:4675`);
- the background purge (`:4278`);
- the temp sweep pattern `(mov|m4a|jpg)` (`:4294`);
- the trim-replace cleanup (`:5053`).

The attachment tile's delete removes only `tmp/<id>.mov`. The unreachable Quit
(`:2014`) is untouched.

**Found while scoping — "Trim → Replace original" on a RECORDED video.**
`StagingStore.replace` writes the MP4 into the existing `.mov` file. Its rename
branch compares `abs` with itself and so never runs. **The staging file keeps
`.mov` while holding MP4 bytes.**

## 2. The fix

**`TimerStagedVideo.format(forFile:)`** — a video's format **from its own file
extension**:
- an `.mp4` file → `.mp4`;
- **a recorder `.mov` → `.mov` (unchanged)**;
- an unknown extension → `.mov`, the recorder's container.

**The hand-off** passes `sourceFormat: TimerStagedVideo.format(forFile: <the
staged file>)`. **Post-record details then persists `.mp4` and uploads
`video/mp4`** through its existing single decision
(`AttachmentImportPolicy.fileExtension` → `MediaFormat.mimeType`). **No
transcoding.**

**`videoSurrogateURL(for:)`** = `tmp/<id>.<truthful ext>`, used by:
- playback;
- the background purge — **it also removes a legacy `.mov` copy**;
- the trim-replace cleanup — **it removes both the old and the new
  extension's copies**.

**Also:**
- the temp sweep pattern gains `mp4`;
- the attachment tile's delete also removes `tmp/<id>.mp4`;
- **the surrogate log line gains `ext=`.**

**`StagingStore.replace` adopts the source's container** when the extensions
differ:
- the new file goes to `<stem>.<newExt>` → the ref is updated → the old file is
  removed.
- **No step can leave the recording without a referenced file.** A death between
  steps leaves either:
  - the old ref and file intact, plus an unreferenced new file; or
  - the new ref and file, plus the old file.
- **Unreferenced media is kept (C-84 P4).**
- **Same extension:** the existing atomic `replaceItemAt`, unchanged.

## 3. Tests — `C85FormatIntegrityTests`, 6 of them

**Stand-in:** `TimerStagedVideo.format(forFile:)` returns `.mov` for every file —
today's behaviour. It has no caller.

| # | Test | Pre-change |
|---|---|---|
| 1 | a trimmed `.mp4` is identified as MP4 through the hand-off: `format` `.mp4` → persisted extension `mp4` → MIME `video/mp4` | **FAIL** |
| 2 | **control:** a recorder `.mov` is unchanged (`.mov`; no source format → `mov`; `video/quicktime`) | **PASS** |
| 3 | `replace` with an `.mp4` over a `.mov` → the ref names `<stem>.mp4`, holding the new bytes; **no stale `.mov`** | **FAIL** |
| 4 | **control:** `replace` with the same container keeps its path | **PASS** |
| 5 | the hand-off passes `sourceFormat: TimerStagedVideo.format(forFile:` | **FAIL** |
| 6 | playback, the purge and the trim replace use `videoSurrogateURL(for:`; no forced `"mov"`; the sweep matches `mp4` | **FAIL** |

## 4. PREDICTION

**N1 — pre-change census:** **282 declared** (276 + 6); **4 failed** (#1, #3, #5,
#6); **278 passed**.

**N2 — after:** **282 / 282.**

**N3 — warnings:** Debug 177 / Release 165, warning sets identical.

**N4 — device (Études Dev, rebuilt and reinstalled as an update).** Repeat only
the affected steps. The session currently staged on the device carries a recorded
`.mov`, a trimmed `.mp4` and an audio clip.
1. **Relaunch after the update** (a new process): all three clips restored. A
   repeat of C-84 step 3's claim, incidental.
2. **Play the trimmed clip:** `Practice Timer video surrogate • ms=… •
   bytes=3240162 • ext=mp4`, and it plays.
3. **Play the recorded clip:** `… bytes=14868684 • ext=mov`, and it plays —
   **unchanged**.
4. **Trim → Replace original on the recorded video:**
   - its staging file becomes **`19E75D01-….mp4`**, with the same stem;
   - **the old `.mov` is gone**;
   - the ref names the `.mp4`;
   - the poster is refreshed;
   - it plays with `ext=mp4`;
   - **and it survives leaving and returning.**
5. **The hand-off:** covered by C-84's normal-Save step, run next. The persisted
   files in `Documents/` must be **`.mp4` for the trimmed clips** and `.m4a` for
   the audio, and staging is cleaned.

**Not repeated:** C-84 steps 1–6, which touch no video extension. The recorder's
`.mov` is checked by N4.3.

**Closure:** N1–N4 met. C-85 closes with that evidence; **C-84's acceptance then
continues.**

## 5. RESULT — automated gates

| # | Predicted | Observed | Verdict |
|---|---|---|---|
| **N1** | 282 declared; exactly #1, #3, #5 and #6 fail; the controls pass | **282 declared, 278 passed, 4 failed** — exactly those four; each message names the defect, e.g. `"mov" is not equal to "mp4"`. Prediction committed first (`8c12ed1`) | **MET** |
| **N2** | 282 / 282 | **282 declared, 282 passed**, nothing else | **MET** |
| **N3** | Debug 177 / Release 165, sets identical | **Both clean builds succeeded, 177 and 165, both sets identical** | **MET** |

## 6. RESULT — device (N4)

**The build:** Études Dev at **`47eb456`**, executable SHA-256
`7eca472997bf8f33…`, installed as an in-place update — the folder moved from
`EE910B82-…` to `20222F1E-…`. **The Release app was untouched** (`EE36AE2D-…`).
F0, taken before relaunch, showed all five staged files, the three refs and the
602 s paused timer byte-identical.

| # | Predicted | Observed | Verdict |
|---|---|---|---|
| **N4.1 · Relaunch** | 10:02 paused; two videos and one audio with thumbnails; `restore • videos=2 • audio=1` | **Exactly that on screen.** F1: new pid 33433 = `bootID`; all files and refs byte-identical. Console was empty at first — **a CAPTURE gap, not the app:** Console.app had stopped streaming when the reinstall ended the process. With streaming restarted, a return to the app logged `restore • videos=2 • audio=1 • images=0 • ms=6 • headroomMB=3312` | **PASS.** The trimmed MP4 survived a new process — stronger than C-84 step 7's never-run leave/return |
| **N4.2 · Play the trimmed clip** | plays; `bytes=3240162 • ext=mp4` | played; `video surrogate • ms=2 • bytes=3240162 • ext=mp4` | **PASS** — the surrogate is now truthful |
| **N4.4 · Trim → Replace original on the RECORDED video** — first half | its staging file becomes `19E75D01-….mp4` (same stem); the old `.mov` gone; the ref names the `.mp4`; the poster refreshed; everything else unchanged | Screen: two videos (both shorter edits), one audio, 10:02. G1: **`19E75D01-….mp4` (2,243,607 B)**, **no `.mov` anywhere in `Staging/`**; the ref names the `.mp4`; **the poster rewritten** (25,780 → 26,935 B, the same mtime as the new file); `1EF1B2C2`, its poster and the audio byte-identical; ids, timer and pid 33433 unchanged | **first half MATCHES** — pre-C-85 this wrote MP4 into the `.mov` |
| **N4.4 · second half** — play it; leave and return | plays with `bytes=2243607 • ext=mp4`; survives leave/return | `video surrogate • ms=2 • bytes=2243607 • ext=mp4`; after Home and back both videos and the audio remain; `restore • videos=2 • audio=1 • images=0 • ms=5`. G2 byte-identical to G1; same pid | **PASS** |

**N4.5 (the hand-off) is exercised by C-84's normal-Save step.** The persisted
files must be `.mp4` for both videos and `.m4a` for the audio.

| **N4.5 · The hand-off, via a normal Save** (Share OFF) | the persisted files: `.mp4` for both videos, `.m4a` for the audio; sizes equal the staged sizes (no transcoding) | **Session 676** (read from a read-only copy of Core Data): row 769 video → `Documents/1EF1B2C2-….mp4` (3,240,162 B); row **770 video → `Documents/19E75D01-…-2.mp4` (2,243,607 B, written at Save)**; row 771 audio → `Documents/2026sep11_16:10.m4a` (215,904 B). **Both videos `.mp4`, `ftyp mp42`; no `.mov` exists; every size equals its staged size** | **PASS** — a trimmed MP4 stays MP4 through the hand-off |

**The first probe was misleading, and why.**
- `devicectl info files` **cannot list this container's `Documents/`**: it returns
  0 entries even after a successful Save. **That is a tooling gap, not evidence.**
- A read-only `copy from` of the base name `19E75D01-….mp4` returned a
  **different, older file** — 3,240,162 B, written at 15:23Z. The real saved
  recording is **`-2`**, because `uniqueFilename` suffixes on a name clash.
- **The attribution comes from Core Data's `Attachment.fileURL`, not from the
  folder.**
- The clash comes from **stray, unreferenced copies the viewer's trim writes into
  `Documents/`**, recorded separately.

## 7. CLOSURE — 2026-09-11

**N1, N2, N3 and N4.1–N4.5 all met**, which is this record's stated closure
condition:
- **A trimmed video stays identified as MP4** through staging, the playback
  surrogate and the hand-off, **with no transcoding**;
- **the recorder's `.mov` is unchanged** (N4.3).

**The one discrepancy on the way (N4.5's first probe) was explained by
measurement:** a pre-existing stray copy from the viewer's trim, plus
`uniqueFilename`'s suffixing. **It is not a C-85 defect** — see
`phase-5-c84-acceptance.md`, the proposed C-86.

**C-85 is RESOLVED.**
| **N4.3 · Play the recorded clip** | plays; `bytes=14868684 • ext=mov` — **unchanged** | played; `video surrogate • ms=3 • bytes=14868684 • ext=mov` | **PASS** — the recorder is unchanged |
