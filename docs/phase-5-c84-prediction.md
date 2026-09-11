# C-84 — UNSAVED PRACTICE TIMER SESSION LOST AFTER PROCESS TERMINATION. REPRODUCTION PREDICTION, COMMITTED BEFORE THE RUN. 2026-09-11

**At `5713222`.** The account holder's decisions, 2026-09-11:
- **C-84 is filed at P2, pending this reproduction.** It is kept distinct from
  C-3.
- **Reproduce on Device B, in Études Dev, with a throwaway short recording
  only.**
- **Provisional product rule:** an in-progress Practice Timer session and its
  staged recordings should **survive** an involuntary process termination and
  relaunch. **Because a pid cannot distinguish that from a deliberate
  force-quit, preserve in both cases unless a reliable distinction is found.**
- **No recovery architecture is implemented yet.**
- **C-3 is held** until C-84 is settled.

The source analysis is in `docs/phase-5-c3-investigation.md` §4.

## 1. The mechanism under test (read from source at `5713222`)

**Path 1 — the relaunch wipe.** `PracticeTimerView.currentBootID` is
`String(getpid())` (`:499`), and it is compared with `PracticeTimer.bootID`. On a
mismatch, the timer's `.task` (`:1691–1714`) runs, among others:
- `clearPersistedStagedAttachments()`;
- `clearAllStagingStoreRefs()` → `StagingStore.remove` — **this deletes each
  staged media file and its poster** under
  `Application Support/MOTIVO/Staging/`, and empties `staged.json`;
- `clearPersistedTimer()`;
- a write of the new pid to `PracticeTimer.bootID`.

**Path 2 — the terminate cleanup, NOT under test.** `handleAppTerminationCleanup()`
(`:5049`) runs on `UIApplication.willTerminateNotification`. When
`ephemeralSessionHasMedia_v1` is set, it deletes the staged refs and files and
sets `PracticeTimer.sessionDiscarded`.
- **iOS does not deliver `willTerminate` to a suspended app it kills for memory.**
  Such a process receives SIGKILL and runs no code.
- **The run therefore uses `devicectl device process terminate --kill`
  (SIGKILL), to model that case**, and to keep Path 2 from confounding Path 1.

## 2. Procedure

**Rig:**
- Device B ("SD iPhone"), **Études Dev** (`com.samueldixon.motivo.dev`).
- The build is the C-82 retest build. The wipe code has been unchanged since
  `f72a8a2`.
- **Launched from the Home Screen, not from Xcode**, so no debugger is attached.
- The Release app may keep running under Xcode. The Études Dev process is told
  apart by its install path.

**Steps:**
1. **Start:** in Études Dev's Practice Timer, **start the timer** and record a
   **throwaway audio clip of a few seconds**. Leave it staged; do not save the
   session.
2. **Control:** go to the Home Screen and return to Études Dev.
3. **Suspend:** go to the Home Screen and leave Études Dev in the background.
4. **Snapshot S1** (read-only): the Études Dev pid; the listing of `Staging/`;
   `staged.json`; and the `PracticeTimer.*` keys from the preferences file.
5. **Fault:** `devicectl device process terminate --kill --pid <Études Dev pid>`.
6. **Snapshot S2** (read-only), before any relaunch.
7. **Relaunch:** open Études Dev from the Home Screen and go to the Practice
   Timer. **Record what the screen shows:** the timer value and running state,
   and whether the recording is present.
8. **Snapshot S3** (read-only).

## 3. PREDICTION

| # | Observation | Predicted |
|---|---|---|
| **R1** | Control (step 2) | Recording and timer **intact**. The pid is unchanged, so no wipe |
| **R2** | S1 | One audio file and its ref present; `stagedAudioIDs` names it; `isRunning` true; `bootID` = the S1 pid |
| **R3** | S2, after SIGKILL | **Identical to S1** — nothing is deleted by the kill itself |
| **R4** | Step 7, on screen | **The recording is gone, and the timer is reset** to 0 and idle |
| **R5** | S3 | **The audio file is deleted**; `staged.json` holds no ref for it; `stagedAudioIDs` is empty or absent; the timer keys are cleared; `bootID` = the **new** pid |

**How the result is read:**
- **R3 + R5 together attribute the loss to the relaunch wipe (Path 1), not to the
  termination.**
- **Any of R1–R5 failing is reported as observed, and not explained away.**
  - If R4 or R5 does not hold, C-84 does not reproduce as stated.
  - If R3 does not hold, something other than Path 1 deletes the staged session.

**Throwaway data only.** The kill ends Études Dev's process, and the only data at
risk is the few-second test clip and the test timer.

## 4. RESULT — 2026-09-11, Device B, Études Dev. **C-84 REPRODUCED. R1–R5 ALL MET.**

Read-only snapshots were taken with `c84-snap.sh`. The kill was guarded: it ran
only if S1 showed exactly one Études Dev pid, a staged media file, a staged
audio id and a running timer. SIGKILL went to that pid alone, matched by its
install path, so the Release app running under Xcode was never a target.

| # | Observed | Verdict |
|---|---|---|
| **R1** | The account holder backgrounded and returned **twice**: once with the recorder still open, and once after the clip was saved into the attachments. The clip and the running timer persisted both times | **MET** — stronger than predicted |
| **R2** | S1 (11:50:55Z): pid **32733**, `bootID` 32733. `Staging/2026-09-11/2026sep11_12:48.m4a` (202,777 B), ref `C4390E8E` (audio). `stagedAudioIDs = ["C4390E8E-…"]`. `isRunning = true`, `startedAtEpoch` set, `accumulated = 0`. `ephemeralSessionHasMedia_v1 = true` | **MET** |
| **R3** | SIGKILL pid 32733 at 11:50:56Z. S2: **process not running; file, ref and every key byte-for-byte as in S1** | **MET** — the kill deleted nothing |
| **R4** | Relaunched from the Home Screen straight onto the Practice Timer: **the timer was not running, and no audio clip was visible** | **MET** |
| **R5** | S3 (11:52:07Z): new pid **32736**, `bootID` rewritten to 32736. **The `.m4a` is deleted; `staged.json` holds no ref.** `stagedAudioIDs = []`. `isRunning`, `startedAtEpoch` and `accumulated` are all **absent**. `ephemeralSessionHasMedia_v1 = false` | **MET** |

**What R3 and R5 establish together:** the member-created recording and the
timer survived the termination intact, and were **deleted by the relaunch**,
through the pid boot-ID check (Path 1).

**What was not exercised:**
- **Path 2** (`willTerminate`) was deliberately excluded by using SIGKILL.
- **A real iOS memory kill was not induced.** SIGKILL is the signal such a kill
  delivers, and **the relaunch path cannot tell the two apart**, because it keys
  only on the pid.

**Incidental, for the cleanup scope.** Études Dev's `Staging/` holds **118–119
empty dated folders** going back to 2025-11-19: `StagingStore.remove` deletes
files but never folders. **No orphaned media was found.** The preferences file
carries **486–487 `PracticeTimer.currentSessionStartTimestamp.<UUID>` keys** that
are never removed.
