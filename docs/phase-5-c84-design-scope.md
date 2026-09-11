# C-84 — DESIGN SCOPE FOR PRESERVING AN UNSAVED PRACTICE TIMER SESSION. 2026-09-11. NOT IMPLEMENTED.

**Status: scope only.**
- No code has changed.
- **C-84 reproduced on device** (`phase-5-c84-prediction.md` §4).
- **C-3 is held** until this is settled.

**The account holder's provisional rule:** an in-progress session and its staged
recordings **survive an involuntary process termination and relaunch**. Because a
pid cannot tell that from a deliberate force-quit, **preserve in both cases**,
unless a reliable distinction is found.

**None was found.**
- A suspended app killed for memory and a suspended app swiped away both receive
  SIGKILL and run no code.
- `willTerminate` arrives only for an app that is still running.
- **Neither signal separates "iOS reclaimed it" from "the member meant it".**

---

## 1. Can the existing storage support it? **Yes — no new persistence architecture.**

**S2 proved it:** after SIGKILL, everything a restore needs was intact on disk.

| Needed | Already persisted | Where |
|---|---|---|
| Timer state | `PracticeTimer.startedAtEpoch`, `accumulated`, `isRunning`, `activityRaw`, `activityDetail` — written on start and pause, and snapshotted on background | `UserDefaults` |
| Staged media files | Files under `Application Support/MOTIVO/Staging/<date>/`, with posters for recorded video | `StagingStore` |
| Staged media references | `staged.json` refs, including audio titles and durations; plus `stagedAudioIDs`, `stagedVideoIDs`, `stagedImageIDs`, `videoTitles` and `selectedThumbnailID` | `StagingStore` and `UserDefaults` |
| Tasks pad | `PracticeTimer.taskLines`, `autoTaskTexts`, `showTasksPad` | `UserDefaults` |
| **NOT persisted** | score-usage and page tracking (`usedScoreIDsThisSession`, meaningful pages, dwell, current page), `provisionalThreadLabel` | memory only — **lost on restore** (D4) |

**The defect is not missing storage.** It is two things:
- a **deletion policy** that treats every new process as a discard;
- a **hydration** that reads every staged file wholesale into memory.

## 2. What deletes a session today

| Path | Trigger | Deliberate? | Under the rule |
|---|---|---|---|
| **Quit / Discard** (`PracticeTimerView:1930–1967`) | the member discards | **Yes** | **Keep** |
| **Review sheet closed without saving or cancelling** (`:2130–2158`) | the member dismisses | **Yes** | **Keep** |
| **Save** (`+Sheets:184–196`) | the session is saved | **Yes** | Keep. Files are removed at the next appearance by the `!sessionActive` launch block |
| **`reset()`** (`:3830`) | — | Yes | Keep, but **it clears the id lists and not `StagingStore`'s files or refs**. The reconciliation can resurrect them, so the design must make it complete |
| **New-pid launch block** (`:1691–1714`) | **any new process** | **No** | **Change: restore instead of delete** |
| **`handleAppTerminationCleanup`** (`:5049`) | `willTerminate` while running | **No** — a termination, not a choice | **Change: stop deleting** |

## 3. The smallest safe design

**Four parts, sized from source.** Each is needed for safety, not for tidiness.

**P1 — the policy.**
- The new-pid block stops deleting. It restores through the existing hydration.
- `handleAppTerminationCleanup` stops deleting.
- `reset()` becomes a complete deliberate end.
- **Deleters are then exactly** Discard, review-dismiss, Save (via the
  `!sessionActive` block) and `reset()`.

**P2 — restore without loading large blobs: file-backed staged VIDEO.**
- Timer-staged video is held by file URL, not `Data`.
- Thumbnails come from the stored poster, or from a decode of the staged **file**,
  with no `tmp` copy.
- Playback and trim open the staged file.
- **The bytes load only at the hand-off to post-record details** — the one place
  that needs `Data`, and exactly what happens today at Save.
- **About 9 sites:** hydrate, mirror, `stageVideoURL`, `playVideo`, the size sum,
  the store re-key, two trim paths, and the hand-off.
- **Audio and images stay `Data` (D2).** Timer audio is AAC and small.
- **This subsumes the important part of C-3:**
  - no wholesale video read or `tmp` rewrite on any hydration, warm or cold;
  - no video bytes resident while suspended, **which also lowers the chance of
    the very termination this unit guards against.**

**P3 — a crash-loop guard.**
- Set a `restoring` marker before hydration and clear it once hydration has
  completed.
- If the marker is found set at launch, **do not auto-hydrate media.** Keep the
  files; the timer and refs load, and the session stays discardable.
- **This is the safety net for "preserve" being wrong for a particular file.**

**P4 — clean up only what is genuinely abandoned.** At launch, remove:
- files under `Staging/` that no `staged.json` ref names;
- refs whose file is missing;
- empty dated folders (118 on Device B).

**A referenced recording is never deleted automatically (D3).**
- Optionally, the per-session `currentSessionStartTimestamp.<UUID>` keys (486 on
  Device B) can be removed when a session ends.

**What P1 alone would be — and why it is not enough.** P1 is the smallest diff,
but a restore would then read every staged video wholesale on relaunch. That is
C-3's regime: about 560 MB per capped clip, and a double footprint during
hydration. **If that is what killed the app, it would crash-loop.** P1 is safe
only together with P2 and P3.

## 4. Decisions required

| # | Decision | Options | Recommendation |
|---|---|---|---|
| **D1** | Restored timer state | **(a)** running, with elapsed computed from the persisted start, **exactly what happens today when iOS suspends but does not kill the app**; **(b)** paused at the last background time | **(a)** — the same behaviour whether or not iOS killed the app. **(b)** would need a new `lastBackgroundedAt` and would behave differently from the non-kill case |
| **D2** | What becomes file-backed | **(a)** video only; **(b)** all kinds | **(a)** — the smallest change that meets "no wholesale blobs"; audio and images are bounded and small |
| **D3** | Expiry of a preserved session | **(a)** none: only Discard, Save or reset deletes; **(b)** auto-expire after N days | **(a)** — never delete a member's recording automatically |
| **D4** | In-memory-only extras (score tracking, thread label) | **(a)** accept their loss on restore; **(b)** persist them | **(a)** for this unit. The impact is fewer suggestions in post-record details after a kill, never lost media |
| **D5** | Force-quit | **preserve**, per the provisional rule, since no reliable distinction exists | Confirm |

## 5. Evidence required for closure

**Automated:**
- **a pure restore-decision table, tested:**

  | Condition | Outcome |
  |---|---|
  | new pid + active session + refs | restore |
  | `sessionDiscarded` | clean |
  | `!sessionActive` | clean |
  | `restoring` marker set | safe mode |
- orphan cleanup tested against a temporary directory: referenced files kept,
  unreferenced files and empty folders removed;
- **structural guards:**
  - no deletion call in the new-pid branch or in `handleAppTerminationCleanup`;
  - no `Data(contentsOf:)` on a staged video in hydration;
  - `reset()` removes the staging refs.
- the full census, with Debug and Release warning sets unchanged.

**Device, Études Dev, repeating the C-84 procedure:**
- **audio:** after SIGKILL and relaunch, **the clip is present and playable, the
  file is intact, and the timer is running with the correct elapsed time** — R4
  and R5 inverted;
- **video (a short clip):** the same, **without a wholesale load**. Optionally
  `phys_footprint` via a temporary probe;
- **deliberate endings still delete:** Discard, review-dismiss and Save each leave
  `Staging/` without that session's files;
- **an app-switcher force-quit preserves** (D5);
- **Save of a restored session** publishes or saves with the clip — the hand-off
  still works.

**C-3** is re-dispositioned afterwards. Whatever P2 does not cover (the audio and
image re-reads, and the background purge that clears thumbnails) is re-measured,
not assumed.

---

## 6. REVISION 2026-09-11 — decisions, three tightenings, and the verified destructive paths

**The sections above are kept as first written. Where this section differs, this
section governs.**

### 6.1 Decisions recorded (account holder)

| Decision | Choice |
|---|---|
| **D1** | Running. Restore a running timer as running, with elapsed time from the persisted start — exactly as when the process survives. **No separate killed-vs-suspended semantics** |
| **D2** | **Video only** becomes file-backed |
| **D3** | **No automatic expiry.** A session is preserved until an explicit session-ending action |
| **D4** | Accept the loss of the in-memory score/page tracking and the provisional thread label on recovery. **The consequence is reduced post-record suggestion context, not lost media** |
| **D5** | **Force-quit preserves** |

**Boundary, recorded explicitly.** File-backed video **still loads its bytes at the
hand-off to post-record details** (`prefillAttachments`). That is existing
behaviour, it is outside the relaunch-loss mechanism, and **it is not changed in
C-84.**

### 6.2 P4 — NARROWED

**Automatic cleanup removes only two things:**
- **empty dated folders**;
- **refs whose backing file is already absent.**

**Unreferenced media is RETAINED.**
- **Verified in source:** `StagingStore.saveNew` moves the media into
  `Staging/` (`:87`) **before** writing its ref to `staged.json` (`:113–115`).
- A process death between the two leaves a real recording that no ref names.
- **Deleting unreferenced media at launch would make that partial commit
  permanent.**
- **Orphan-media cleanup is dispositioned separately, not in C-84.**

### 6.3 P3 — REPLACED by decode-free hydration (no marker)

**Why the marker is not needed.** P2 removes the one known hydration crash cause —
reading staged video wholesale. **The smaller safe path is to take all decoding
out of hydration**, rather than detect a crash after the fact. After P2, hydration:
- builds video items from refs only (file URL and poster path) and **reads no video
  bytes**;
- shows the stored **poster JPEG** as the thumbnail — every in-app recording gets
  one at staging (`stageVideoURL`, `:4616–4627`) — **with no `AVAssetImageGenerator`
  decode**, and a placeholder tile if a poster is missing;
- reads audio and image bytes as today (D2). These are bounded and small;
- **does not probe audio with `AVAudioPlayer`.** The duration comes from the stored
  ref; if absent, none is shown.

**The account holder's four questions, answered for this design:**
- **What the Practice Timer shows after a relaunch:** the restored timer and its
  attachments, as before. A video with no stored poster shows a placeholder tile.
  **No new UI.**
- **How and when the marker clears:** there is no marker.
- **Whether and how the member can retry:** there is nothing to retry. Hydration
  performs no decode, so there is no failure mode to fall back from.
- **How preserved recordings reach Save:** unchanged. Finish → review → Save. The
  hand-off loads the video bytes (§6.1).

**Residual.** A media file that crashes AVFoundation deterministically can still
crash when the member **plays** it, or when post-record details decodes it for
display. **That is member-triggered, not a launch loop, and the item can be
removed on its own** (`+Sheets:366`).

**If defence in depth is wanted anyway,** the earlier marker can be layered on
later. **It is not proposed for C-84.**

### 6.4 DESTRUCTIVE PATHS — VERIFIED IN SOURCE (not yet device-observed)

| Action | What the member does | Today | Under the rule |
|---|---|---|---|
| **Save, success** | Taps Save | `onSaved` clears the session; the `!sessionActive` launch block removes staging at the next appearance | **Keep** — the canonical end |
| **Save, FAILURE** | Taps Save; Core Data throws | `saveToCoreData`'s `catch` rolls back without `onSaved`; `commitSaveAndDismiss` **still dismisses** (`:433`); the timer's no-flag branch runs → **recordings deleted** | **Change:** preserve. Do not dismiss on failure; nothing is deleted |
| **Swipe the review sheet down** | A gesture — **no `interactiveDismissDisabled` on this sheet** (the only two in the app are `AppSetUpView`, `:1590`, and `MediaTrimView`) | The timer's "Intentional discard" branch (`:2130–2158`) → **recordings deleted** | **Change: preserve** — not an explicit Discard |
| **"Back to Timer" chevron** (post-record details, `:1280`) | Taps back | Post-record details takes the timer's attachments **with the same ids** (`:1386`), then calls `StagingStore.removeMany(ids:)`, which **deletes the files and refs** (`:429`). The timer keeps its in-memory copies, so the clips look present **until the next hydration**, when they vanish | **Change: preserve** — remove the deletion |
| **Reset** (TimerCard, paused state, beside Resume/Finish; **no confirmation**) | Taps Reset | `reset()` (sole caller `:2729`) clears the timer, tasks and persisted id lists — **not** the files, refs or in-memory arrays; the reconciliation can resurrect them | **Decision D7** |
| **Quit** (toolbar) | — | **Unreachable.** Shown only when `!isHomePresentation`, and the only instance is `.home` | Leave untouched. A Phase 6 cleanup candidate |
| **New process** | None | **Deleted** (C-84, reproduced) | **Change: restore** |
| **`willTerminate`** | None — a termination | Deleted when `ephemeralSessionHasMedia_v1` is set | **Change: preserve** |

**The consequence.** **The app has no explicit, confirmed "discard this session"
action today.** The swipe-down is the de facto discard. Under D3 a session is
preserved until an explicit ending, so **exactly one explicit discard has to
exist.**

### 6.5 Decisions still required

| # | Decision | Options | Recommendation |
|---|---|---|---|
| **D6** | Swiping the review sheet down | preserve — the same as Back to Timer | **Preserve.** It is a gesture, not an explicit Discard |
| **D7** | The explicit whole-session discard | **(a)** Reset asks for confirmation when recordings are staged — *"Reset the timer and discard N recordings?"* — and discards on confirm; with nothing staged it behaves as today. **(b)** A "Discard session" button in review. **(c)** None: remove items one by one; Reset clears the timer only | **(a)** — one confirmation, on a control that already exists and already means "start over" |
| **D8** | A failed Save | keep the member in review, delete nothing | **Keep in review.** Whether an error message is shown is separate, and is not C-84 |

### 6.6 Final implementation shape (pending D6–D8)

| Part | Change |
|---|---|
| **P1** | New-pid block restores instead of deleting. `willTerminate` stops deleting. The swipe and "Back to Timer" preserve. A failed Save does not dismiss. **The only deleters: a successful Save** (via the `!sessionActive` block) **and the D7 discard** |
| **P2** | File-backed staged video, about 9 sites. The hand-off loads bytes (§6.1) |
| **P3** | Decode-free hydration (§6.3) |
| **P4** | Cleanup narrowed (§6.2) |

**Before-controls on device, before any change**, with a throwaway clip each:
- the swipe-down deletes;
- "Back to Timer", then background and return, loses the clip.

**Those, plus the C-84 kill procedure, are then repeated after the change,
inverted.** A failed Save cannot be induced on device, so it is covered by a unit
test and a structural guard.

### 6.7 PRE-CHANGE DEVICE OBSERVATIONS — 2026-09-11

**Rig:** Device B, Études Dev, throwaway clips only.

**Predictions:** source predictions committed at `7cb76eb` §6.4. **Both confirmed.**

**Method:** read-only snapshots with `c84-snap.sh`. **All in ONE process, pid
32736**, so neither result involves the relaunch wipe.

**O1 — swipe-down of the review sheet: CONFIRMED, the recording is lost.**
- **Before** (O1pre, 12:15:34Z):
  - `2026sep11_13:15.m4a` (166,581 B), ref `5922AB47`;
  - `stagedAudioIDs` names it; the timer is running.
- **The action:** Finish, then swipe the review sheet down.
- **Screen:** the timer reset, no clip.
- **After** (O1post, 12:16:18Z):
  - **the file is deleted; `staged.json` is empty;**
  - the timer keys and staged-id lists are removed;
  - `sessionDiscarded = true`, `sessionActive = false`.

**O2 — "Back to Timer", then leave and return: CONFIRMED, the recording is lost.**
- **Before-snapshot: MISSED.** The step was taken before it could be captured.
  Recorded as a gap. Recording writes the file and its ref together (O1pre, S1),
  so **an id with no file and no ref** at O2mid means both were removed after
  recording.
- **The action:** Finish, then the back chevron.
- **Screen:** the timer paused at 8 s; **the clip still shown.**
- **Mid** (O2mid, 12:17:48Z):
  - **no file, and no ref** for the clip;
  - `stagedAudioIDs = ["51F08534-…"]` still names it;
  - `accumulated = 8`, paused.
  - **The recording existed only in memory.**
- **The action:** to the Home Screen and straight back — same pid, so no relaunch.
- **Screen:** paused at 8 s; **the clip gone.**
- **After** (O2post, 12:20:18Z): as O2mid. **The in-memory copy was dropped by
  hydration.**

**Found during O2 — a latent path, source-backed.** `PracticeTimer.sessionDiscarded`
was **still `true` at O2mid and O2post**, left over from O1's swipe discard, even
though a new session had been started since. It is consumed only by the timer
view's `onAppear` (`:1763`), where it runs `clearAllStagingStoreRefs()`. **A
leftover flag can therefore clear a LATER session's staging the next time the view
appears.** The implementation must not delete on this flag at a later appearance.

### 6.8 RESET — what it reaches and clears today

**Where it is reachable.** TimerCard offers:
- **idle:** Start;
- **running:** Pause, Finish;
- **paused:** Resume, Finish, **Reset**.

**Reset is not shown while idle.** A member who stages media without starting the
timer reaches it only through Start → Pause → Reset. **FLAGGED for decision.**

**What `reset()` clears:**
- pause, which also stops the drone and metronome;
- `clearPersistedTimer`;
- `clearPersistedStagedAttachments` — the staged-id lists, `videoTitles` and
  `selectedThumbnailID`;
- **`clearPersistedTasks`** — the task pad **on disk only**. The on-screen
  `taskLines` are untouched, so they disappear at a later relaunch;
- `resetUIOnly` — elapsed time, score/page tracking, the thread label, activity
  back to Practice, activity detail;
- the in-memory `videoTitles` and the session id.

**What it does NOT clear:** staged files, `staged.json` refs, or the in-memory
staged arrays. The reconciliation can resurrect them.

**The consequence for D7's copy and trigger.** **A Reset with nothing staged
already destroys member-typed task-pad content, without confirmation.**
FLAGGED — the account holder's assumption that such a Reset "may remain
immediate" holds only if the task pad is empty.

### 6.9 FOUND WHILE SIZING P2 — two trim paths and the attachments card (source-established, NOT device-observed)

**"Trim → Save as new" loses the new clip.**
- `handleTrimSaveAsNew` (`:4883–4966`) makes a new staged item under a new UUID
  **in memory only**.
- It seeds a `tmp` surrogate, persists the id list, and deletes its temp file.
- **It calls no `StagingStore` API, so there is no staging file and no ref.**
- The next hydration rebuilds from refs, so the new clip **vanishes on the next
  return to the app, or on relaunch** — O2's shape.
- **In scope of the invariant.** It is staged media removed without Save or a
  confirmed discard.

**"Trim → Replace original" can lose the original.**
- `handleTrimReplaceOriginal` writes over the staging file in place, **but calls
  `removeItem(at: finalURL)` BEFORE `moveItem`**. Its `catch` then deletes the
  trimmed temp as well.
- **A failed move leaves neither copy.**
- `StagingStore.replace` already does this atomically (`replaceItemAt`), and the
  timer does not use it.

**P2 reaches `AttachmentsCard`.**
- It takes `@Binding var stagedVideos: [StagedAttachment]` (`AttachmentsCard:21`)
  and merges images and videos into its visual tiles (`:55`).
- It calls `UIImage(data: att.data)` on each tile (`:62`), which for a video is an
  attempted decode over the whole file, falling back to the thumbnail.
- **A distinct file-backed video type** means about 5 line changes there. It is
  preferred over an empty-`Data` sentinel, because **the compiler then finds every
  video site**. A sentinel's one silent failure is the worst one: a 0-byte video
  handed to Save.

**The playback and trim constraint.** The viewer maps a URL to an id by file stem
("LOCKED: URL → UUID mapping is stem-only", `+Sheets:328`). A recorded video's
staging file is named after the **pre-store** temp UUID, not after its ref id.
- File-backed playback and trim therefore keep the `tmp/<id>.mov` surrogate.
- **They create it with `FileManager.copyItem`, which clones on APFS** — no byte
  load, and effectively no copy cost.
