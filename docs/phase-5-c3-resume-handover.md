# HANDOVER — RESUME AT C-3. Written 2026-09-11 at the close of the C-84/C-85 run.

**Read this first, then `docs/phase-5-c84-acceptance.md` (Decisions + Resume
boundary) and the C-3 row of `docs/audit-findings.md`.** No conversation is the
state; these documents are.

## 1. The first task — INVESTIGATION ONLY

**Re-assess C-3 against the POST-C-84 architecture and report a MEASURED
disposition before any implementation.** **Do not assume the old C-3 refactor is
still needed**, and do not start a `PracticeTimerView` refactor.

Establish:
1. what work still happens on active/resume;
2. whether audio/image rereads or thumbnail behaviour now cost meaningful
   latency, memory, CPU/energy or visible UX;
3. what of the original finding **C-84 has subsumed**;
4. whether anything remaining **warrants code at all**;
5. if so, the **smallest** option and its **before/after measurement**.

## 2. What C-3 measured ORIGINALLY (2026-08-14, Device A) — the baseline to beat

- Staged video held **wholly in memory**, re-read plus a **full temp copy on
  every foreground**, synchronously on the main actor.
- Three rungs: 19.1 MB → **53.2 ms**, 93.6 MB → **120.7 ms**, 278.7 MB →
  **322.9 ms** (medians; worst single foreground 472.7 ms). **~35 ms fixed +
  ~1 ms/MB.**
- **The P1 hypothesis was memory and it did not materialise** — same pid
  throughout, no jetsam. Downgraded to **P3**.
- The better argument for a fix was never latency: **~279 MB resident** while
  clips stay staged, and **the same bytes rewritten to `tmp` every foreground**
  (flash wear, battery).
- Supporting observation: the staged-video thumbnail briefly vanished on
  background/foreground.

## 3. What C-84 CHANGED — measure against this, not against the old code

- **Staged video is file-backed** (`TimerStagedVideo`), not `Data`.
- **Hydration decodes nothing**: posters via `UIImage(contentsOfFile:)`, stored
  durations, no `AVAudioPlayer` probe, no `generateVideoThumbnail`.
- **Playback uses an APFS clone** to `tmp/<id>.<ext>`, made on demand.
- Device evidence, 2026-09-11: a **122,753,168 B (117 MB)** staged video
  restored in **ms=1** with **headroomMB 3351 — identical to an empty launch**,
  and its playback clone took **ms=2**. A 14.9 MB clip cloned in **ms=1**.
- **So the residency and per-foreground-rewrite arguments must be RE-MEASURED,
  not inherited.** Audio and images are the parts C-84 did not restructure.
- The `restore` and `video surrogate` log lines already carry ms/bytes/headroom
  and are the cheapest instrument available.

## 4. State at the boundary

- Branch `feature/solo-connected`, **HEAD `58f20b9`**, tree clean.
- **The shared scheme is on Release — committed blob `013cc35`.** Never commit a
  Debug scheme state. `SchemeConfigurationGuardTests` enforces it.
- **C-84 RESOLVED** (device-accepted, M4 complete) and **C-85 RESOLVED**.
- **C-86 filed P3, fix deferred** — the viewer's trim leaves an unreferenced copy
  of each timer-staged trim in `Documents/`. A backup leak and filename-collision
  nuisance; **not data loss**.
- **Two recorded C-84 follow-ups, NOT implemented:** open the attachments panel
  automatically when a restored session has media (a product decision, taken);
  and the sub-second staging window (a narrow residual risk, deferred).
- **Out of scope** unless C-3 directly depends on it: C-34/B1 and C-69
  (Production fixture), C-80, C-81, B-38, C-75, C-76, C-83, C-86 and the two
  follow-ups above.
- **The account holder pushes.** Report the unpushed range after `git fetch`.

## 5. Gates and tooling

- **Suite census is 282.** Run it and score by **structured census**, never by
  grepping console counts:
  `xcodebuild test -project MOTIVO.xcodeproj -scheme MOTIVO -configuration Debug
  -destination 'platform=iOS Simulator,id=73EA3A14-B6FC-4C73-839D-55FF5190C5DA'
  -only-testing:MOTIVOTests -derivedDataPath <dd> -resultBundlePath <x.xcresult>
  -quiet`, then `python3 scripts/test-census.py <bundle>`.
- **Warning baselines: Debug 177 / Release 165, sets identical.** Normalise the
  appintents timestamp/pid prefix before diffing:
  `sed -E 's#^[0-9-]+ [0-9:.]+ [a-z]+\[[0-9:]+\] ##; s#:[0-9]+:[0-9]+:#:#'`.
- **Device B — "SD iPhone", `12BEF5FB-2FEF-5A56-8080-BFCC3E2C2492`.** Études Dev
  is `com.samueldixon.motivo.dev`, build `47eb456`, container folder
  `20222F1E-…`. **The Release app (`EE36AE2D-…`) stays untouched.** Install only
  as an in-place update; never uninstall or wipe the container.
- **`devicectl device info files` CANNOT list this container's `Documents/`** —
  its empty answers are not evidence. Attribute saved attachments from a
  read-only copy of Core Data (`Library/Application Support/MOTIVO.sqlite` +
  `-wal`/`-shm`, `sqlite3 mode=ro`, `ZATTACHMENT.ZFILEURL`).
- **Console.app must be streaming**; it stops when a reinstall ends the process,
  and the silence looks exactly like an app that logged nothing.
- **The snapshot script `c84-snap.sh` lived in the session scratchpad and is
  GONE with that session.** Rebuild it if needed: it resolves the app's container
  folder per run and prints pid, `Staging/` media, `staged.json` refs and the
  whitelisted `PracticeTimer.*` keys. **It never printed the task keys** —
  read `taskLines` / `autoTaskTexts` / `showTasksPad` from the prefs plist with
  `plistlib` (they are JSON `Data` blobs).

## 6. Working rules that produced this record

- **Re-measure every finding against current source.** Closure by evidence.
- **Commit the prediction and the failing guards BEFORE any mutation**, and prove
  the guards are non-vacuous.
- **Inventory every site** — the one-of-N lesson.
- **Stop at the first deviation from prediction and diagnose** before continuing.
- **Never present anything as device-verified without device evidence.**
- **Preserve history in corrections**; record prediction misses as misses.
- Stop and report product, UX or architecture choices with options and a
  recommendation.
