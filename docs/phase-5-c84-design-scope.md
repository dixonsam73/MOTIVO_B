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
