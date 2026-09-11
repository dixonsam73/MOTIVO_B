# C-84 — DEVICE ACCEPTANCE (M4). IN PROGRESS — NOT CLOSED.

**The build under QA:**
- commit **`e75a443`**, built as Debug for device;
- executable SHA-256 `e408b784b8dbc074…`;
- **installed on Device B as an in-place update of Études Dev**
  (`com.samueldixon.motivo.dev`), via `devicectl`, after all three gates were
  green.

**Evidence the update is in place and the data survived:**
- the install folder changed from `5ED9CE86-…` to `EE910B82-…`;
- the data container carried over — `bootID`, the timer keys and the staging
  folder were all present at A0;
- **the Release app (`com.sdsongs.etudes`) was not touched.**
- **The shared scheme stayed on Release throughout.**

**Method:**
- read-only snapshots (`c84-snap.sh`, which resolves the install folder each run);
- the account holder drove the device;
- Console.app filtered on `Practice Timer`.

**Stop rule:** stop at the first deviation from prediction, and diagnose before
continuing.

**Automated / source-verified only:** failed-Save preservation. There is no safe
deterministic device trigger.

## Results

| Step | Prediction | Observed | Verdict |
|---|---|---|---|
| **1 · First launch of the new build** (A0 held O2's paused 8 s session, O1's stale `sessionDiscarded = true`, and 119 empty dated folders) | 00:08 paused, restored; the stale flag consumed with no deletion; `Staging/` only `staged.json`; `bootID` = the new pid; a restore log line | Screen 00:08, no clips. A1: pid 33251 = `bootID`; `sessionDiscarded = false`; **`Staging/` 1 entry, 0 folders**; session id kept. Console, twice: `Practice Timer restore • videos=0 • audio=0 • images=0 • ms=0 • headroomMB≈3350` | **PASS** — the old build would have zeroed that session |
| **2 · Reset with nothing to discard** | immediate, no dialog, idle | no dialog; unstarted timer with the green Start. A2: timer keys and session id removed; `Staging/` unchanged; `sessionActive` still `true`; same pid | **PASS** |
| **3 · Kill and relaunch with audio and video** (the original C-84) | B1 = staged; B2 = B1 after SIGKILL; relaunch restores both, the timer running from the same start, the video thumbnail, a restore line of `videos=1 • audio=1` | B1: `19E75D01-….mov` (14,868,684 B) + `_poster.jpg` (25,780 B) + `2026sep11_16:10.m4a` (378,911 B); refs `92BA1F55` audio and `19E75D01` video (with poster); timer running. **The staging file is named by the ref id — the id passed through, no re-key.** Guarded SIGKILL of pid 33251. B2 identical, process gone. Relaunch: timer running, both clips, video thumbnail present. B3: new pid 33264 = `bootID`; **every file and ref byte-identical**; the same `startedAtEpoch` and session id. Console: `restore • videos=1 • audio=1 • images=0 • ms=3 / ms=1 • headroomMB 3354 / 3350` | **PASS** — **the relaunch loss is fixed on device** |

| **4 · Play the restored clips** | the video plays through its surrogate; `video surrogate • bytes=14868684`; the audio plays | **Both played.** Console: `Practice Timer video surrogate • ms=1 • bytes=14868684` — **exactly the staged file's size, created in 1 ms** (an APFS copy, not a read into memory) | **PASS** |

| **5 · Swipe-down of the review sheet** (the inverse of O1) | both clips stay; the timer paused at Finish; files and refs intact; `sessionDiscarded` false, `sessionActive` true; the same pid | Screen: **10:02, paused, both clips present.** C1: all three files and both refs byte-identical; `accumulated = 602`; `sessionDiscarded = false`, `sessionActive = true`; pid 33264 | **PASS** — O1 deleted the clip here |

| **6 · "Back to Timer", then leave and return** (the inverse of O2) | after the chevron: clips present, files and refs intact; after leave/return: unchanged | Screen: **10:02 paused, both clips present, after the chevron AND after leave/return.** D1mid (straight after the chevron — **the snapshot O2 missed**): all three files and both refs present. D1post: unchanged. Same pid 33264 throughout | **PASS** — O2 had the file and ref deleted at the chevron |

| **7 · Trim → Save as new (video)** — first half | a second video tile with a thumbnail; a **new `.mov`** in `Staging/` named by its id, plus its poster; a new video ref with `posterPath`; `stagedVideoIDs` 2; everything else byte-identical | Screen: two videos, one audio, 10:02 paused. E1: new ref **`1EF1B2C2`**, file **`1EF1B2C2-….mp4`** (3,240,162 B) + `_poster.jpg` (21,084 B), `posterPath` set; `stagedVideoIDs` 2; the original video, its poster and the audio byte-identical; pid 33264 | **STOPPED — the extension differs from the prediction (`.mp4`, not `.mov`); diagnosed below.** Everything the step tests matched |

**Diagnosis of the step-7 difference — a PRE-EXISTING mislabel, not introduced by
C-84.**

**The trim tool always exports video as MP4.** `MediaTrimView:1197` names the file
`.mp4`; `:1240` sets `outputFileType = .mp4`.

**`AttachmentImportPolicy.fileExtension(for:)` assumes otherwise.** It falls back,
for media with no source format, to the kind's default, `.mov`. Its doc comment
assumes "Études-generated media … the recorder writes `.mov`": **true of
recordings, not of trims.**

**The consequences:**
- The hand-off (`makeReviewPrefill`) passes a trimmed video with no
  `sourceFormat`, **exactly as the pre-C-84 save-as-new did**.
- So post-record details would persist **MP4 bytes as `.mov`**, and an upload
  would declare them `video/quicktime` — **C-77's class of mislabel**.
- The playback surrogate is likewise `tmp/<id>.mov`, holding MP4 bytes.

**The pre-C-84 code at `ce1c38c` did the same:**
`StagedAttachment(kind: .video)` with no source format, copied to
`surrogateURL(for:)`. The only difference: that clip never survived to be
saved, **unless it was saved in the same process**.

**What C-84 changed:**
- **Staging is now truthful (`.mp4`)**;
- **more trimmed clips reach Save**, so the mislabel is more reachable.

**The prediction's `.mov` was simply wrong.**

**Disposition pending the account holder:**
- **(a)** continue the acceptance on `e75a443`, and file it as **C-85**; or
- **(b)** fix it inside C-84, then rebuild, reinstall and re-run the affected
  steps.

**D1 observed on device.** The 602 s run from the original Start (15:09:54Z) to
Finish, **straight through the SIGKILL and relaunch of step 3**. A restored running
timer behaves exactly as one that was only suspended.

**On the headroom figure.** At step 3 it equals step 1's empty launch (3354 MB),
which shows restore did not load the video. **A 14.9 MB clip is too small to prove
that alone**; the longer-video step is the stronger test.

## Observations and boundaries (not C-84 defects; recorded for decision)

**The restored attachments panel starts collapsed.** The timer view's `onAppear`
sets `isAttachmentsVisible = false`, so after a relaunch the restored clips are
present but hidden. **The account holder's first reaction was that they might be
gone.**
- A UX question, not a loss.
- **For decision:** open the panel automatically when a restored session has
  media.

**The original reproduction is NOT affected by this.** C-84 R5 was scored on
storage — S3 showed the `.m4a` deleted and `staged.json` empty — not on the
screen.

**`ephemeralSessionHasMedia_v1` is reset at launch by
`MOTIVOApp.cleanupEphemeralMediaIfNeeded()`.** That explains the unpredicted
true→false at steps 1 and 3. **No deletion is tied to the flag.** The launch
also runs two sweeps, unconditionally:
- `tmp/motivo_rec_*.m4a` — the audio recorder's working files. **An unsaved take
  is swept**, including one cut off by a kill mid-recording, which is normally
  unfinished and unplayable. Staged audio is never named this way.
- `Documents/motivo_vid_*.mov` — abandoned video captures. **Staged files live in
  Application Support and are unaffected.**

**RESIDUAL — a short window when staging a video.**
- The recorder hands `Documents/motivo_vid_<timestamp>.mov` to `stageVideoURL`,
  which decodes the thumbnail, then `saveNew` moves the file into `Staging/`
  (a rename).
- **A kill inside that window, well under a second after tapping save in the
  recorder**, would leave the file where the launch sweep deletes it.
- **The pre-C-84 code had the same exposure**, via its temp copy, so this is **not
  a regression**.
- It can be closed by moving the file into staging before the thumbnail decode.
  **Not done — for decision.**
