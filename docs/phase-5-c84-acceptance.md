# C-84 — DEVICE ACCEPTANCE (M4). COMPLETE — C-84 RESOLVED 2026-09-11.

*Previous heading, preserved:* "IN PROGRESS — NOT CLOSED."

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

**Resumed after C-85** (fixed as its own finding; build `47eb456`, executable
SHA-256 `7eca472997bf8f33…`, installed as an update). The C-85 device results —
relaunch, both surrogates, and Trim → Replace original on the recorded video —
are in `phase-5-c85-prediction.md` §6. **Step 7's never-run leave/return is
superseded by C-85 N4.1:** the trimmed MP4 survived a whole new process.

| Step | Prediction | Observed | Verdict |
|---|---|---|---|
| **10 · Normal Save** (Share with followers OFF, so no publish is queued) | a normal save and landing on the journal; staged files and refs removed; timer and staged-id keys cleared; `sessionActive = false` until the timer next appears | Landed on the journal. J1: **`Staging/` has no media, `staged.json` has no refs**; the timer and staged-id keys are absent; `sessionActive = false`; pid 33456. One empty dated folder remains — removed by the launch cleanup (P4) | **PASS** — the canonical deleter works |
| **9 · Kill and relaunch after all the trims** (a replaced `.mp4` recording, a saved-as-new `.mp4`, a replaced `.m4a`) | I2 = I1 after SIGKILL; relaunch restores all three with thumbnails; 10:02 paused; `restore • videos=2 • audio=1` | I1: both `.mp4`s, their posters and the 215,904 B `.m4a`, three refs. Guarded SIGKILL of pid 33433 at 16:21:29Z. I2 identical, process gone. Relaunch: **10:02 paused, both videos with thumbnails, the 9 s audio**; Console `restore • videos=2 • audio=1 • images=0 • ms=1 • headroomMB=3350`. I3: new pid 33456 = `bootID`; every file byte-identical | **PASS** — every trim output survives a new process |
| **8 · Trim → Replace original on the audio** (same container) | the same path, smaller; the ref keeps its path; the stored duration updates; everything else unchanged | Audio heard shorter; videos unchanged. H1: `2026sep11_16:10.m4a` **same path**, 378,911 → **215,904 B**; ref duration **13 → 9 s**, title unchanged; both `.mp4` videos, posters, ids, timer and pid 33433 unchanged | **PASS** |
| **11A · Reset while idle with content — the dialog** (one recording, `2026sep11_17:32.m4a`, timer never started) | Reset shown while idle; "Reset session?"; *"…permanently deletes 1 recording and your tasks…"*; Delete and Reset / Cancel | **First tap:** Reset shown while idle; the message read *"…permanently deletes 1 recording. This can’t be undone."* **Stopped.** The account holder had typed nothing in Tasks; K1 confirmed `taskLines = []`. **The dialog was right and my prediction assumed an input that was never given.** **Second tap**, after Cancel and one typed line: *"This resets the timer and permanently deletes 1 recording and your tasks. This can’t be undone."* K2 (dialog open): the audio file (395,054 B) and its ref unchanged — **Cancel deleted nothing**; `taskLines` held the typed `"Test"` with an empty `autoTaskTexts`, so it counted as member content; pid 33456 | **PASS** — both copy variants seen, each truthful for its state |
| **11B · Delete and Reset** | a fresh unstarted timer; no clips; Reset hidden; Tasks empty. L1: no staged media, no refs; the timer keys absent; staged-id lists empty; tasks saved empty; `sessionActive = true`, `sessionDiscarded = false`, the media flag false; same pid | Screen as predicted, and **"Test" gone** — but opening Tasks showed **the preset task set chosen in Settings**, not an empty pad. L1: **`Staging/` has no media, `staged.json` has no refs**; the timer keys absent; staged-id lists `[]`; `sessionActive = true`, `sessionDiscarded = false`, `ephemeralSessionHasMedia_v1 = false`; pid 33456. `taskLines` holds the four preset lines, **each id mapped in `autoTaskTexts` to its unedited text** | **PASS.** **The preset reload is by design and my prediction missed it:** `resetTasksForNewSessionContext()` clears the context flags so presets "load again when pad opens", exactly as for a new session. Untouched preset text is not member content, so Reset stays hidden |
| **11C · Leave and return after the discard** | unchanged: a fresh timer, no clips, no Reset, preset tasks only | **Exactly that on screen.** L2: no media, no refs, staged-id lists `[]`, pid 33456. The timer keys now read idle zeros (`isRunning = false`, `startedAtEpoch = 0`, `accumulated = 0`, absent at L1) — the background save of a zeroed timer, not a resurrection | **PASS** |
| **11D · SIGKILL and relaunch after the discard** | nothing returns; a new pid = `bootID`; `restore • videos=0 • audio=0 • images=0`; the empty dated folder removed at launch | Guarded SIGKILL of pid 33456 at 16:43:54Z (the running Études Dev pid checked first); L2k identical, process gone. Relaunch: **a fresh-start screen**; Console `restore • videos=0 • audio=0 • images=0 • ms=0 • headroomMB=3351`. L3: new pid 33479 = `bootID`; **`Staging/` 1 entry, 0 folders**, no refs; `taskLines` holds only the four preset lines | **PASS** — **the confirmed discard is complete and permanent; nothing is resurrected** |
| **12A · Stage a long video** (3:10, throwaway content, timer running) | one `.mov` named by its ref id, plus a poster; a video ref with `posterPath`; `stagedVideoIDs` 1; the timer running; pid 33479 | M1: **`72338C2D-….mov`, 122,753,168 B (~117 MB)**, plus `_poster.jpg` (18,158 B); one video ref; `isRunning = true`, `startedAtEpoch = 1789145162.25`; session id `A8BA7B78`; pid 33479 | **PASS** |
| **12B · SIGKILL with the long video staged** | M2 = M1, process gone | Guarded SIGKILL of pid 33479 at 16:50:06Z. M2 byte-identical to M1; not running | **PASS** |
| **12C · Relaunch — the restore does not load the video** | the timer running from the same start; the thumbnail present; `restore • videos=1`; **headroom about the empty launches' ~3350 MB, not ~117 MB lower** | Timer running; video tile with thumbnail (the panel started collapsed — the recorded UX point). Console, twice: `restore • videos=1 • audio=0 • images=0 • ms=1 • headroomMB=3354` / `3351`. **The empty launch at 11D read 3351.** M3: new pid 33484 = `bootID`; file, poster and ref identical; **the same `startedAtEpoch`**, so the running count spans the kill (337 s at M3) | **PASS** — **a 117 MB staged video restores in 1 ms with no measurable memory cost.** This is the stronger test step 3's 14.9 MB clip could not provide |
| **12D · Play the long video** | it plays; `video surrogate • ms=` single digits (an APFS clone, independent of size) `• bytes=122753168 • ext=mov` | Played. Console: `Practice Timer video surrogate • ms=2 • bytes=122753168 • ext=mov` | **PASS** — **the clone is measured, not assumed:** 2 ms for 117 MB against 1 ms for 14.9 MB at step 4; the bytes exact; the recorder's `.mov` unchanged |

## CLOSURE — 2026-09-11

**Every M4 item in `phase-5-c84-implementation-prediction.md` is met on device:**

| M4 item | Discharged by | Verdict |
|---|---|---|
| 1 · Kill with audio + video, timer running → both present and playable, timer correct | steps 3, 4 | **MET** |
| 2 · O1⁻¹ — swipe-down preserves | step 5 | **MET** |
| 3 · O2⁻¹ — Back to Timer, then leave and return, preserves | step 6 | **MET** |
| 4 · Reset — the exact copy; Cancel keeps; Delete and Reset clears with nothing returning after leave/return or relaunch; immediate when empty | 11A, 11B, 11C, 11D; step 2 | **MET** |
| 5 · Idle Reset offered with content | 11A | **MET** |
| 6 · Trim — Save as new and Replace original (with thumbnail) survive a relaunch | step 7, C-85 N4.1 and N4.4, step 9 | **MET** |
| 7 · Measurement — a ≥ 3 min video restored after SIGKILL without memory growing by its size; the clone's `ms` and `bytes` | 12A–12D | **MET** — measured as `headroomMB`, the recorded deviation from `footprintMB` |
| 8 · Hand-off — Save a restored session with its media | step 10 (the session restored at step 9), C-85 N4.5 | **MET** |

**Deviations, all recorded where they happened:**
- **Step 7 — `.mp4`, not `.mov`.** A pre-existing mislabel, filed and resolved as **C-85**.
- **11A — the missing "and your tasks".** The prediction assumed a typed task that was never entered; the dialog was right.
- **11B — the pad was not empty.** Presets reload by design.

**None was an app defect in C-84's scope.**

**Failed-Save preservation (D8) stays automated/source-verified only**, as agreed. There is no safe deterministic device trigger.

**Carried for decision, not C-84 defects:**
- the collapsed attachments panel after restore;
- the sub-second window while staging a recorded video;
- the viewer-trim `Documents/` leak, **proposed as C-86**.

**C-84 is RESOLVED.**

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

**FOUND AT STEP 10 — the viewer's trim leaves an unreferenced copy of every
timer-staged trim in `Documents/`.** Pre-existing, not C-84 or C-85.
**No loss — a leak.**

**The mechanism, read from source:**
- The viewer's **Save as new** calls `AttachmentStore.adoptTempExport`, which
  moves the trim into `Documents/<source stem>.<ext>`.
- Its **Replace original**, under the default `.immediate` strategy (the timer
  passes none), calls `AttachmentStore.replaceAttachmentFile`. That writes
  `Documents/<source stem>.<ext>` — for a timer clip the source is a `tmp`
  surrogate, so this is a **new** file.
- The timer's handlers then stage a **disposable copy** (`+Sheets:22`). **Nothing
  removes the viewer's persisted copy.** It is included in backup and removed
  only by Erase All.
- `AttachmentViewerView` and `MediaTrimView` are **unchanged since `5713222`**.

**Observed:**
- `Documents/19E75D01-….mp4` — 3,240,162 B, written at 15:23Z (step 7's Save as
  new);
- `Documents/19E75D01-…-1.mp4` — 2,243,607 B, written at 16:16:10Z (C-85 N4.4's
  Replace original).

Core Data references neither. **They also shadow later saves:** step 10's real
recording landed at `-2`.

**Proposed as a separate finding (C-86), for decision.**

**TOOLING LIMITATION — `devicectl device info files` returns NO entries for this
container's `Documents/`**, even after a successful Save.
- `Library/` lists normally.
- **Its empty answers are not evidence.**
- Saved attachments were attributed from a **read-only copy of Core Data**
  (`Attachment.fileURL`), plus read-only `copy from` of the named files.

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
