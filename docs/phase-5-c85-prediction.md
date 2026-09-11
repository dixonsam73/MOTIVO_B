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
