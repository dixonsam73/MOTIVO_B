# C-3 — INVESTIGATION, 2026-09-11. NO CODE CHANGED.

**Scope, as set by the account holder:**
- Investigation only.
- **No `PracticeTimerView` refactor just because the register calls for one.**
- Measure before any design choice.
- Close or defer is an acceptable outcome.

**Out of scope, not touched:** C-34/B1, C-69, C-80, C-81, B-38, C-75, C-76 and
C-83.

**What this record rests on:** every statement below is read from source at
`913a34d`, or comes from the 2026-08-14 device measurement. **Nothing new was
measured on device in this investigation.** Where a claim is inferred rather
than read or measured, it says so.

---

## 1. What the current code does, and how often

### 1a. Foreground hydration — the C-3 mechanism, unchanged since 2026-08-14

**Where it runs:** `PracticeTimerView.onChange(of: scenePhase)` → `.active`
(`:1823–1849`), and also the view's `.onAppear` (`:1779`). Both call
`hydrateTimerFromStorage()` (`:4007`) synchronously on the main actor.

**What each hydration does:**
- It reads the timer fields from `UserDefaults`. Cheap.
- For **every** staged audio, video and image ref, it reads the whole file into
  memory with `Data(contentsOf:)` (`:4034`).
- For each video, `generateVideoThumbnail(from:id:)` (`:4715`) **writes those
  bytes back out** to `tmp/<id>.mov` (`:4719`, atomic) and runs a synchronous
  `copyCGImage`.
- For audio with no stored duration, it opens `AVAudioPlayer(data:)`.
- It builds complete new arrays and only then assigns them. **Until the
  assignment, the old and new copies of every staged byte are alive together.**
  That transient double footprint is inferred from the code structure and was
  not measured.
- **It ignores the poster JPEG `StagingStore` already keeps for each recorded
  video.** `mirrorFromStagingStore` uses that poster; hydration re-decodes a
  frame instead.

**What runs on the way out:** `.inactive` **and** `.background` share one branch
(`:1850`). It calls `purgeStagedTempFiles()` (`:4222`), which deletes every
staged `tmp` surrogate **and clears `videoThumbnails` outright**.

**Cadence:**

| Trigger | Status |
|---|---|
| **Every return to the app** | Source-established |
| **Every return from `.inactive`** — pulling down Control Centre or Notification Centre, or opening the app switcher mid-practice | Source-established. **Not framed by the 2026-08-14 run** |
| **Every `onAppear` of the timer's content view** | Source-established that it hydrates. **Unmeasured:** whether `onAppear` fires again when the video-recorder, attachment-viewer or score-viewer full-screen cover is dismissed. These covers hang off the same view (`:2110`, `:2223`, `:2247`) |

**How the cost is bounded:**
- **A recording is capped at 15 minutes** (`VideoRecorderView:684`).
- It records **1080p at 5 Mbps** (`:948`), about **37 MB per minute**. That
  matches the measured 185 MB for 5 minutes.
- **One clip therefore peaks at about 560 MB.**
- **Several clips can be staged, and nothing blocks it.** An existing warning
  appears above 500 MB of staged video (`stagedSizeWarning`, `:4281`).

### 1b. The UI ticker — not C-3

**What it does:** `Timer.publish(every: 1.0, on: .main, in: .common)` (`:3894`)
sets `elapsedSeconds` from the persisted start time and running total
(`trueElapsedSeconds`).

- **No drift.** It is compute-on-resume.
- **No per-tick persistence.**
- It is restarted on every `.active` and `onAppear`, so it also ticks while the
  timer is idle.
- **Its cost is unmeasured and not part of C-3.**

### 1c. What does NOT depend on the per-foreground rewrite

The viewer paths write their own `tmp` copy when they open: `playVideo`
(`:4654`), `openAudioViewer` (`:4682`) and `openImageViewer` (`:4700`).

**So the hydration's `tmp/<id>.mov` rewrite exists only to feed the thumbnail
decode.** Playback does not rely on it.

## 2. Later work — did it change the finding or add dependencies?

**None of these touched a C-3 line** (hydration, `scenePhase`, thumbnail,
`videoThumbnails`, `Data(contentsOf:)`, staged persistence), checked hunk by
hunk:
- C-50 (`9632117`, recording Auto-Lock — the recorder views only);
- P5-M playback speed (`dda4d3b`, `2983102` — `AttachmentViewerView`, not this
  view);
- C-56 (`3edf5fb`);
- P5-N accessibility (`71703bf`);
- C-79 (`dc5effd`);
- P5-K′ (`7091ba3`);
- Phase 2's backup-policy commits.

**The dependency that does exist is older and wider.** Staged media travels as
in-memory `Data` (`StagedAttachment.data`) into:
- the hand-off to post-record details (`prefillAttachments`, `+Sheets:181`);
- trim (`:5012–5027`);
- the viewers;
- the staged-size warning.

Any change to how bytes are held reaches those sites. **A change limited to
when hydration re-runs reaches none of them.**

## 3. Is there a measurable problem today?

| Cost | Evidence | Verdict |
|---|---|---|
| **Main-thread stall per return** | **Measured 2026-08-14, Device A:** 53 ms at 19 MB; 121 ms at 94 MB; 323 ms at 279 MB (medians); worst 473 ms; about 35 ms plus 1 ms per MB, with a first-return penalty that grows with size | **The measured regime is P3.** Short clips stay below Apple's 250 ms hang threshold |
| **The capped regime: one 15-minute clip, about 560 MB** | **Not measured.** Extrapolated: about 0.6–1 s per return | **Unmeasured. Plausibly a perceptible hang on every return, including every Control Centre pull** |
| **Several capped clips** | Not measured. Staged bytes scale linearly, and the transient footprint is double | Unmeasured |
| **Thumbnail flash** | Observed on every 2026-08-14 rung | **Cosmetic, recurring.** The mechanism is corrected below |
| **Flash wear and energy** | The staged video bytes are rewritten on every return | **Small in practice.** A session's worth of returns is a few GB against endurance measured in hundreds of TB. **The 2026-08-14 record over-weighted this argument** |
| **Memory residency** | All staged bytes are held in `@State` for as long as they stay staged, including while suspended | **Real but unmeasured.** Its consequence is §4 |
| **Timer drift or per-tick persistence** | Not present (§1b) | None |

**Correction to the C-3 row — its text is kept, and corrected here.** The flash
is **not** "empty for exactly as long as the synchronous regeneration takes".
**The background purge empties the square on the way out (`videoThumbnails.removeAll()`
in `purgeStagedTempFiles`), and hydration refills it on return.**

## 4. ADJACENT FINDING, OUTSIDE C-3 AS FILED — an unsaved timer session does not survive a process relaunch

**Status:** source-established, **not device-observed**. It is a product
decision, and **no register row has been filed**.

**The mechanism:**
- `currentBootID` is `String(getpid())` (`:499`). Its own comment: *"detect cold
  launches (force quit / crash relaunch)"*.
- On any new process, the timer's `.task` (`:1691–1714`) runs
  `clearAllStagingStoreRefs()`. That calls `StagingStore.remove`, which **deletes
  each staged media file and its poster**, and then `clearPersistedTimer()`.
- It came in with `f72a8a2` (2025-11-04, "harden resume/cleanup"). **No doc or
  register row records it.**
- **`TimerStateRecovery.swift`**, which claims to *"persist + restore timer
  state across app kills/crashes"*, **has no callers.** It is dead code.

**Why it matters:**
- iOS routinely **terminates suspended apps to reclaim memory**, and the
  relaunch has a new pid.
- **So an iOS memory kill is handled exactly like a deliberate force-quit.** A
  member who records, switches to another app, and returns to a killed app would
  find their **unsaved recordings deleted and the timer reset.**
- **C-3's memory residency plausibly makes this more likely**, because a
  suspended app holding hundreds of MB is a prime candidate for termination.
  That is inference: termination heuristics are not observable.

**Why the wipe may exist:** a relaunch that restored staged media could
**crash-loop** if hydration itself caused the kill. Restoring is only safe if
hydration is cheap and bounded. **That is where this finding and C-3 genuinely
couple.**

**Deterministic device reproduction** (needs the account holder's authorisation,
because it terminates the app process):
1. Stage a short recording in the timer and start it.
2. Background the app.
3. `xcrun devicectl device process terminate` the suspended process.
4. Relaunch.

**Predicted from source:** the staged item is gone and the timer is reset.

## 5. The design choice, and its options

| Option | What changes for the member | Cost and risk |
|---|---|---|
| **A. Close or defer C-3** as an accepted P3 | Nothing. The flash and the stall with long clips remain | None. Honest if §4 is decided as "discard on relaunch" and the capped regime is judged acceptable |
| **B. Stop redoing work within one process** — on `.active`, don't reload refs already in memory; don't purge surrogates or clear thumbnails on `.inactive`; use the stored poster instead of decoding | **Returning to the app costs a few ms instead of up to ~1 s. The flash goes. No rewrite on each return** | Small and contained in `PracticeTimerView`. **Does not reduce memory residency** while suspended. Cold launch unchanged |
| **C. Hold staged media by file, not by bytes** — `StagingStore` already has the files; load `Data` only at the hand-off, trim and the viewer | Also removes the resident footprint (roughly staged size down to thumbnails), so a suspended app is lighter and hydration is trivial even on cold launch | **Moderate:** about 15 sites in `PracticeTimerView` and `+Sheets`. The hand-off to post-record details can stay `Data`-based if bytes load at that moment. **Required if §4 is decided as "survive relaunch"**, to rule out a crash loop |
| **D. Move hydration off the main actor**, unchanged otherwise | Removes the stall only | **Not recommended.** It keeps the I/O, the rewrite and the double footprint, widens the empty-thumbnail window, and adds races with user actions |

**The smallest change for the measured problem is B.**

**C is justified only by §4's product decision, not by C-3's latency.**

## 6. Measuring before and after

**The instrument** (temporary, Release-readable, removed afterwards as in
2026-08-14):
- one `os.Logger` line per hydration, `privacy: .public`;
- fields: **trigger** (`active-from-background`, `active-from-inactive`,
  `onAppear`), `mainActorMs`, media bytes read, bytes written to `tmp`, and
  `phys_footprint` before and after;
- durations and byte counts only.

**The fixture:**
- **one 15-minute clip**, the cap and the unmeasured regime;
- optionally a second clip;
- on Device A, for comparability with 2026-08-14.

**The triggers:** home-screen background and return; a Control Centre pull; and
dismissing the video recorder and the attachment viewer. The last two settle
§1a's open cadence question.

**The prediction is committed before the run.** After a change, the same run is
repeated.

## 7. Evidence required for closure

**Of B:**
- **Automated:**
  - a pure helper deciding which refs need loading, tested;
  - structural guards that `.inactive` neither purges surrogates nor clears
    thumbnails, and that hydration consults the stored poster.
- **Device:**
  - the probe shows a warm return at a few ms, with **zero** `tmp` bytes written;
  - no thumbnail flash;
  - cold launch unchanged.
- **The full census, with Debug and Release warning sets unchanged.**

**Of C:**
- B's evidence, plus `phys_footprint` while suspended falls by roughly the staged
  size;
- the hand-off, trim and viewer each re-verified on device.

**Of §4 (if "survive relaunch" is chosen):**
- the deterministic termination reproduction passes;
- a crash-loop guard, exercised.
