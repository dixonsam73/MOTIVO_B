# C-84 — IMPLEMENTATION PREDICTION, COMMITTED BEFORE THE STRUCTURAL CHANGES. 2026-09-11

**At `a69a3f0`.**

**The design is `phase-5-c84-design-scope.md` §6, with the decisions of
2026-09-11:**
- D1 running; D2 video only; D3 no expiry; D4 accept the loss of the in-memory
  extras; D5 force-quit preserves;
- D6 swipe-down preserves;
- D7 (a): Reset is the one confirmed whole-session discard, shown while idle too
  when there is content;
- D8 a failed Save stays in review;
- both trim defects are in scope;
- the file-backed change is video only.

**Before-state on device:**
- O1 (swipe-down) and O2 (Back to Timer) are **§6.7 of the design scope**;
- the relaunch loss is **`phase-5-c84-prediction.md` §4**.

**No existing test touches the code being changed.** `MOTIVOTests` was searched
for every identifier involved, with no match. **So no existing test is predicted
to change its result.**

---

## 1. THE POLICY, as recorded by the account holder

> **Whole-session staged data is removed only after a successful Save, or after
> an explicit, confirmed session discard.** Explicit member removal of an
> individual attachment is still allowed, and is not whole-session cleanup.
> **Dismissal without explicit destructive confirmation preserves the session.**

## 2. What changes

**P1 — policy**

**The new-pid block (`.task`)** keeps only its `bootID` write. It no longer:
- clears staging;
- clears the timer or the tasks;
- sets `sessionActive = false` — which would let the `!isActive` block that
  follows wipe the session;
- removes the session id.

**The existing hydration then restores the session.**

**`handleAppTerminationCleanup`** only persists the timer snapshot. It deletes
nothing.

**`.onChange(of: showReviewSheet)`** — a dismissal without Save preserves, the
same as the back chevron.

**`sessionDiscarded` at `onAppear`** — the flag is consumed and **deletes
nothing**. The O2-found stale flag becomes harmless. Device B currently carries
one.

**The review sheet's back chevron** no longer calls `StagingStore.removeMany`.

**`saveToCoreData` returns `Bool`**, and **`commitSaveAndDismiss` dismisses only
on success.**

**Reset:**
- `onReset` becomes `requestReset()`.
- It builds a `SessionDiscardSummary`. **If confirmation is needed, it shows the
  alert. Otherwise it runs the existing `reset()`.**
- The alert's **Delete and Reset** calls **`discardSessionCompletely()`**, which
  runs, in order:
  1. `StagingStore.removeMany` over the ids in memory;
  2. `clearAllStagingStoreRefs()` — **this also removes refs that are no longer
     in memory**, O2's zombie case;
  3. purge of the temp surrogates;
  4. `reset()`;
  5. clearing the in-memory media, titles and thumbnails;
  6. `resetTasksForNewSessionContext()`;
  7. `sessionActive = true` (**a fresh session, never `false`** — see §4 R-8),
     `sessionDiscarded = false`, `ephemeralSessionHasMedia_v1 = false`.

**`TimerCard`** gains `showsIdleReset` and `resetRequiresConfirmation`:
- the idle layout offers Reset when there is content;
- **when confirmation is required, Reset calls `onReset` without the control
  transition**, so a Cancel leaves the controls correct.

**The Quit toolbar and its cleanup are unreachable and untouched.**

**P2 — file-backed staged video**

**`@State var stagedVideos: [TimerStagedVideo]`**, holding an id and a file URL.
The same type goes into `AttachmentsCard`, whose visual tiles merge by id.

**`stageVideoURL`:**
- **no `Data(contentsOf:)`**;
- the thumbnail comes from the recorder file (a staging-time decode, triggered by
  the member);
- then `StagingStore.saveNew(…, id: id)`, so there is **no re-key**. The item's
  file URL follows the store's file.

**Playback:** `ensureVideoSurrogate(id:)` clones the staging file to
`tmp/<id>.mov` with `FileManager.copyItem`, **then opens the viewer. No bytes
are read.** Surrogate time and size are logged:
`Practice Timer video surrogate • ms=… • bytes=…`. **Its cost is measured on
device, not assumed.**

**The hand-off:** `finish()` materialises `reviewPrefill` **once** — the images,
the audio, and each video read from its staging file — and the review sheet
takes `prefillAttachments: reviewPrefill`. **Reading the video bytes here is the
recorded boundary:** existing behaviour, outside the relaunch loss.

**The staged-size warning** sums file sizes, not `Data`.

**P3 — decode-free hydration**

`hydrateTimerFromStorage` and `mirrorFromStagingStore`:
- build videos from refs;
- take thumbnails from **`posterPath`** via `UIImage(contentsOfFile:)`;
- make **no `generateVideoThumbnail` call and no `AVAudioPlayer` duration
  probe**.

**Each hydration logs:**
`Practice Timer restore • videos=… • audio=… • images=… • ms=… • footprintMB=…`.

**P4 — narrowed cleanup**

**`StagingStore.cleanupAbandoned()`**, called at launch, removes **empty
subdirectories** and **refs whose file is missing**. **Unreferenced media is
kept.**

**Additional defects found during C-84 — in scope, named, not absorbed**
- **Trim → Save as new** now stages the clip through
  `StagingStore.saveNew(…, id: newID)`. For video, the poster is written from the
  trimmed file.
- **Trim → Replace original** now uses **`StagingStore.replace`**, which is atomic.
  The surrogate is refreshed; for video the thumbnail is regenerated and
  **`StagingStore.writePoster`** updates the poster. **A failed replace deletes
  only the trimmed temp.**
- The trim helpers are keyed by **`(id, kind)`**. The `StagedAttachment`-typed
  trim sheet never receives a video: nothing sets `trimItem` to an item.

## 3. The Reset confirmation copy — LOCKED

**The inventory of what the complete discard removes:**
- the timer (elapsed, running);
- **staged recordings, videos and photos**, with their files, posters, titles and
  thumbnail choice;
- **the tasks pad** (task and context lines, and the linked saved-set state);
- the score and page tracking, the thread label, and the session id.

**Excluded from the copy:**
- **the activity and its detail** — `activityDetail` is set only by *choosing* a
  saved custom activity, so it is a selection, not member-created content;
- **the derived tracking** — D4.

**When confirmation is needed:** any staged recording, video or photo, **or
member task content**. A task line counts only if:
- its text was typed, or edited away from its auto/preset text; **or**
- a task was ticked.

Blank lines and untouched preset lines do not count.

**The timer's value alone never triggers it.**

**Title:** `Reset session?`

**Buttons:** `Delete and Reset` (destructive) · `Cancel`

**Message:** `This resets the timer and permanently deletes <list>. This can’t be
undone.`

**`<list>`:**
- items, in this order: `N recording(s)`, `N video(s)`, `N photo(s)`,
  `your tasks`;
- joined as `a` · `a and b` · `a, b and c`;
- singular at 1.

## 4. Tests — `C84SessionPreservationTests`, 20 of them

**Stand-ins, committed with this prediction.** They have no caller and change no
behaviour:
- `TimerStagedVideo` — the real type, unused;
- `SessionDiscardSummary` — says nothing needs confirmation;
- `StagingStore.saveNew`'s `id:` — accepted and **ignored**;
- `cleanupAbandoned()` — a no-op;
- `writePoster` — a no-op.

| # | Test | Pre-change |
|---|---|---|
| 1 | discard summary names exactly what is lost (counts, plurals, order, tasks) | **FAIL** |
| 2 | nothing to lose → no confirmation, no message | **FAIL** (the stand-in reports nothing even when there is content; the test covers both sides) |
| 3 | member task content: typed / edited / ticked yes; preset-untouched and blank no | **FAIL** |
| 4 | `cleanupAbandoned` removes empty folders and dangling refs, **keeps unreferenced media** and referenced media | **FAIL** |
| 5 | `saveNew(…, id:)` honours the caller's id | **FAIL** |
| 6 | **control:** `replace` with a missing source throws and **leaves the original intact** | **PASS** (before and after) |
| 7 | `writePoster` records a poster on the ref | **FAIL** |
| 8 | the new-pid block deletes nothing, and neither clears `sessionActive` nor the session id | **FAIL** |
| 9 | termination deletes nothing | **FAIL** |
| 10 | a review dismissal without Save deletes nothing | **FAIL** |
| 11 | back chevron: the review sheet's only `removeMany` is the successful-Save `consumedIDs` | **FAIL** |
| 12 | a failed Save stays in review (`guard saveToCoreData(…) else`; `-> Bool`) | **FAIL** |
| 13 | a stale `sessionDiscarded` deletes nothing | **FAIL** |
| 14 | restore neither loads nor decodes video (the `[TimerStagedVideo]` type; no thumbnail decode or `AVAudioPlayer` in hydrate/mirror) | **FAIL** |
| 15 | Trim → Save as new stages via `StagingStore.saveNew` | **FAIL** |
| 16 | Trim → Replace original uses `StagingStore.replace`, with no pre-delete | **FAIL** |
| 17 | Reset routes through `requestReset`; the confirmed discard is complete | **FAIL** |
| 18 | `TimerCard` offers Reset while idle when there is content | **FAIL** |
| 19 | the hand-off materialises video once (`reviewPrefill`, never the raw `stagedVideos`) | **FAIL** |
| 20 | **the whole-session deletion sites are pinned** — code-line counts of `StagingStore.remove(` / `removeMany(` / `deleteFiles(` / `clearAllStagingStoreRefs()`, per file | **FAIL** — today PTV **16**, PRDV **2** |

**Test 20's post-change pins:**

| File | Count | Why |
|---|---|---|
| **`PracticeTimerView.swift`** | **10** | 16 − 8 removed (the new-pid block 1, the stale flag 1, the review branch 3, termination 3) + 2 in `discardSessionCompletely` |
| **`+Sheets`** | **1** | the viewer's per-item delete |
| **`+AudioPlayback`** | **1** | per-item `deleteAudio` |
| **`AttachmentsCard`** | **2** | per-item trash buttons |
| **`PostRecordDetailsView`** | **1** | the successful-Save `consumedIDs` |

The PTV count keeps the `!isActive` post-Save block, the `clearAllStagingStoreRefs`
helper, and the unreachable Quit (5).

## 5. PREDICTION

**M1 — pre-change census:**
- **276 declared** (256 + 20);
- **exactly 19 new tests fail** (all but #6);
- **every other test passes, including the scheme guard** (Run is Release);
- **19 failed, 257 passed.**

**M2 — after:** **276 declared, 276 passed.**

**M3 — warnings:** **Debug 177 / Release 165, with warning sets identical**
(line numbers and log prefixes normalised). The deprecated `AVAsset.duration` /
`copyCGImage` calls are moved or converted, not multiplied. **An added warning is
a miss, recorded as such.**

**M4 — device (Device B, Études Dev). The inverse of each before-state:**
1. **Kill:** a staged audio clip plus a short in-app video, timer running →
   SIGKILL → relaunch. **Both present and playable; the files intact; the timer
   running with the correct elapsed time.**
2. **O1⁻¹:** Finish → swipe the review down. **The clip stays; the timer is
   unchanged.**
3. **O2⁻¹:** Finish → Back to Timer → leave and return. **The clip stays.**
4. **Reset:**
   - with a clip and typed tasks → **the exact copy** (for example "…deletes 1
     recording and your tasks…");
   - **Cancel** keeps everything;
   - **Delete and Reset** leaves `Staging/` without the session's files and
     `staged.json` empty — **and nothing reappears after leaving and returning,
     or after a relaunch**;
   - with nothing staged and no tasks, Reset is **immediate**.
5. **Idle Reset:** a clip staged with the timer never started → **Reset is
   offered.**
6. **Trim:**
   - **Save as new** → the new clip survives leaving and returning, and a
     relaunch;
   - **Replace original** → the trimmed clip, **with its thumbnail**, survives a
     relaunch.
7. **Measurement:**
   - a **longer in-app video** (≥ 3 min), restored after SIGKILL — the `restore`
     log's `footprintMB` **must not grow by the video's size**;
   - the `video surrogate` log gives the clone's `ms` and `bytes`.
8. **The hand-off:** Save a restored session → it saves with its media.

**Closure:** M1–M4 met, recorded, and **C-84 closed only on the device result.**

> **RESULT 2026-09-11 — M4 MET ON DEVICE.** Every item is mapped to its passing
> step in `phase-5-c84-acceptance.md` (Closure). Item 7 was measured as
> `headroomMB` — the recorded deviation from `footprintMB`. **A 117 MB video
> restored with headroom unchanged** (3351 against an empty launch's 3351), and
> **its playback clone took 2 ms.** **C-84 is RESOLVED.**

> **PREDICTION MISS — test 20's `PracticeTimerView` pin: predicted 10, actual 9.**
>
> **The cause is the baseline, not the code.** "PTV 16" came from a rough
> `grep -c` that also matched the helper's declaration line,
> `private func clearAllStagingStoreRefs() {`. The test's own rule excludes
> that line, so **the true pre-change count was 15**, and 15 − 8 + 2 = **9**.
>
> **Verified site by site against `ce1c38c`:**
> - **Every removed site is intended:** the new-process block, the stale flag,
>   the review dismissal (3) and termination (3).
> - **Every remaining site is intended:**
>   - the post-Save `!isActive` block;
>   - the unreachable Quit (5, untouched);
>   - `discardSessionCompletely` (2);
>   - the helper body.
>
> **Resolution:** the pin is re-pointed to 9, with the reason in its doc
> comment.
>
> **The rest of the first post-change run:** 276 declared, 275 passed — all 19
> previously failing C-84 tests passed, and no existing test changed.
>
> **Also recorded as a deviation:** the restore log reports **`headroomMB`**
> (`os_proc_available_memory`), not `footprintMB`. Reading `phys_footprint`
> needs `mach_task_self_`, which Swift's concurrency checking flags. The two
> measure the same thing: headroom = limit − footprint.

## 6. What this does NOT claim or change

- **A failed-Save error message** — preservation only (D8).
- **Orphan-media cleanup** — §6.2 of the design scope.
- **Audio and images** stay `Data` (D2).
- **C-3** stays held. It is re-measured afterwards.
