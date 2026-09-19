# Phase 6 — overnight checkpoint (18–19 September 2026)

**Record only. Nothing in this file is committed, pushed or deployed.** Branch
`feature/solo-connected`, `HEAD` = `48cdce7` (R0, docs only). Workflow: Claude
implements, Codex reviews, Samuel approves commits, pushes and deploys. This is **not** a
Phase 6 closure or a release approval.

## Boundaries in force

- **R0 (`48cdce7`, `docs/adult-only-connected-rescope-2026-09-18.md`):**
  - Connected is to become adult-only. Solo is unchanged, local and account-free.
  - **Adult-assurance implementation is FROZEN** pending the Apple, HEAA and server-trust
    determinations. Generic `.confirmed` is **not** HEAA approval.
  - The existing 13+ code and B-40 stay in force until a reviewed replacement ships.
  - No unit below touches age, provenance, eligibility or enforcement placement.
- **Shared-server sharing protection is FROZEN:**
  - all six ordering and byte-cleanup blockers are OPEN;
  - the upload-lease proposal is withdrawn;
  - SU-478356 has been acknowledged only;
  - observing the first scheduled cleanup run after the deploy is still pending.
- **Protected dirty files, untouched throughout:**
  - `docs/connected-invitations-direction.md`
  - `docs/private-connection-invitations-scope-2026-09-17.md`
  - `AGENTS.md` (untracked)

## Accepted code units in the working tree (uncommitted)

Commit authority was specific to earlier checkpoints and is **not** blanket. These wait for
Samuel's separate authorisation.

### P6-I-05: attestation completion ownership. ACCEPTED

- **Change:** a generation-owned completion in `MembershipAttestationCoordinator`.
  - A run superseded by `reset()` publishes nothing, and returns `nil` to its starter and to
    any caller that joined it.
  - Triggers, guards, cooldown, forced joining, the C-55 reset guard and all service and call
    sites are unchanged.
- **Files:**
  - `MOTIVO/MembershipAttestationCoordinator.swift`
    `b986661300d9c9497ae6e8809b0ec832cc615c413c29524217999a82b171373c`
  - `MOTIVOTests/P6I05AttestationOwnershipTests.swift`
    `3387ef9d93a2fe1959dae0ebecd3a9ac5f01788c06bd9ad9e430a28353fcb19c`
- **Evidence:**
  - Focused 8/8 (after the harness correction, `p605-test2.log`).
  - The generation-check revert failed the 5 ownership tests.
  - Full suite 729 passed / 0 failed / 6 skipped
    (`Test-MOTIVO-2026.09.18_23-15-31-+0100.xcresult`). Release succeeded.
  - `supabase/tests/u5/client-structural.sh`: every C5f check passes. **C57-2 and C57-3 fail
    and pre-exist at HEAD** (on the unchanged `NetworkManager.swift`). They are recorded,
    **not green**, and not repaired.
- **Limits:**
  - This suppresses **client publication only**. Cancelling does not prove the server request
    stopped.
  - It does not fix every cross-identity purchase notice, because the purchase path reads the
    mutable `lastOutcome`.
  - **Separate, unverified candidate:** a forced purchase attestation can join a run that
    started before the purchase existed.
- **Device QA:** not essential for in-memory ordering.
- **Handover:** `claude-opus5-attestation-ownership-handover.md`

### PDFScoreView update-pass publishing. Source and tests ACCEPTED; manual runtime/device acceptance PENDING

- **Change:**
  - Page, count and failure effects are published through a FIFO gate: deferred while inside a
    view update, and immediate otherwise when nothing is pending.
  - Document epochs, and callbacks captured per event.
  - On close, pending effects are withdrawn **before** `onClose`. The practice timer's
    tracking flush moved into `onClose`.
  - After a close, reappearing republishes the current state.
  - Failure is reported once per document per visible lifetime, with a fresh report after
    reappearance.
- **Files:**
  - `MOTIVO/PDFScoreView.swift`
    `f95fd1d1d9fb5608bb4e6c331a39f516eb0b18f5e5eac1b6466cbc0cff593002`
  - `MOTIVO/PracticeTimerView.swift`
    `f5d09b88e18c298117defc041c577b159f36ebcaf14ba0c15cc5a9398d44ec45`
  - `MOTIVOTests/PDFScoreEffectOrderingTests.swift`
    `af58f3e8215b4e82966454f5e2617f3d72a7f5c05ab07f52d9bfa06704f32faa`
- **Evidence:**
  - Focused 23/23: gate G1–G8; coordinator K1–K8 with a real `PDFView` and generated PDFs;
    reappearance R1–R6; structural S1.
  - Reverts: always-synchronous failed 12 tests; the reappearance revert failed 5.
  - Full suite 752 passed / 0 failed / 6 skipped
    (`Test-MOTIVO-2026.09.19_00-10-19-+0100.xcresult`). Release succeeded.
- **Runtime:** the device checks are user-reported green (see below). The supplied console
  excerpt contained no "Publishing changes" warning. It is an excerpt, not an exhaustive log.
- **Handover:** `claude-opus5-pdfscore-update-handover.md`

Evidence paths are temporary local files in the Claude scratchpad
(`/private/tmp/claude-501/-Users-samueldixon-Documents-Xcode-projects-MOTIVO-B-MOTIVO/d9d4fc7d-cd76-4fdf-a378-c352abfe0694/scratchpad/`).
The handovers are in `/Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/`.

## Device checks: USER-REPORTED GREEN (19 September 2026)

**Samuel reports every requested device check below GREEN, for both Lists and PDFScoreView.**
- This is **user-reported device acceptance of these listed checks only**. It is not a
  sign-off of any unrelated gate: R0 adult assurance, the sharing server freeze, SU-478356,
  F-3 device sizing, or commit authorisation.
- **The console excerpt Samuel supplied** contained no "Publishing changes from within view
  updates" warning. It also showed handoff markers 0 and queue 0, authorised auth checks, and
  successful follow refreshes, alongside assorted networking, keyboard and UIKit warnings and
  socket timeouts.
- That is **an excerpt, not a complete log**, and it is recorded as such.

### OPEN: suspected Lists regression on instrument transition (separate from the green checks)

- **Reported by Samuel:** starting with one saved instrument, adding a second instrument
  introduces the instrument selector for preset Lists in the Lists manager, and **appears to
  wipe the existing saved Lists**.
- **Status: suspected, not reproduced or explained.**
  - Nothing in the supplied console excerpt establishes that a List was deleted.
  - **Codex is investigating personally.** Claude is not implementing or investigating in
    parallel.
- **Codex finding** (recorded in `docs/phase-6-lists-instrument-transition-2026-09-19.md`):
  - **Confirmed from source and an isolated Foundation probe:** after the transition to more
    than one instrument, the manager looks for an instrument-specific default key that does not
    exist, so `selectedTaskSetID` is nil. `loadAll` then writes the autofill compatibility flag
    as `false`.
  - The timer treats that instrument-level `false` as a hard stop, before any activity
    fallback. **So opening the manager disables the old default for the selected instrument**,
    while the old default stays stored.
  - **Deletion of named Lists is NOT reproduced:** the real `SavedListLibrary`, in an isolated
    suite, kept the List, and its canonical bytes were byte-identical.
  - The probe mirrors the manager's and timer's selection conditions. It is not a SwiftUI
    reproduction.
  - **Awaiting Samuel:** did named rows vanish, or was it the default that was lost?
- **Samuel's clarification:** the apparent disappearance was on **Device A**; the console
  excerpt came from an attempted reproduction on **Device B**. He cannot reproduce it again, and
  it may have been instrument selection. **The apparent loss of named Lists is NOT REPRODUCED
  and is not confirmed data loss.**
- **Fix authorised by Samuel (default selection only). Implemented and FROZEN for Codex
  review, uncommitted.**
  - The manager's reads no longer write preferences, and the inherited activity default is
    shown without being assigned.
  - Hashes: `TasksManagerView` `bc2f950b…`, `ListsDefaultResolution` `d94a03f3…`, tests
    `da6f39f8…`.
  - Handover: `claude-opus5-lists-instrument-default-handover.md`.
  - **CODE REVIEW ACCEPTED by Codex.** Evidence:
    - focused 37/37 on the final source;
    - **full 761 passed / 0 failed / 6 skipped (767 total) before the decoder fix**, and only
      focused tests re-run after it;
    - Release succeeded after the fix.
  - **New device QA is pending:**
    - start from a fresh context with an activity default and no earlier explicit OFF;
    - add a second instrument, then inspect Lists and start sessions on both;
    - deselect one; the other is unaffected;
    - renaming or deleting an inherited List does not reassign it.
    - **An existing `false` is not repaired automatically.**
  - **The earlier green checks remain accepted.**
  - **NEW DEVICE RESULT, 19 September 2026: FAIL/OPEN.**
    - Samuel reports that adding a new instrument makes the selected default List for an
      activity, and the original default instrument, disappear. Deleting the new instrument
      brings the default back in the Lists manager.
    - **Data deletion is not established.**
    - **Pending clarification** (Codex is asking): whether the latest rebuilt app was
      installed, and whether the original instrument was explicitly selected.
    - A read-only diagnosis is in `claude-opus5-lists-instrument-diagnosis.md`. The hypotheses
      are a pre-fix build, a historical instrument OFF or typed override, and the manager
      starting on the alphabetically first instrument where the timer uses the primary one.
      **None is established.**
    - **The Lists code is not changed.**
- **OPEN defect, not fixed.** No fix and no independent work have been started. The previous
  user-reported QA acceptance stands for the listed checks.
- **So the green checklist is NOT overall Lists sign-off** while this is open.

The checks as they were specified:

**Lists (`90ab06e`):**

**No-downgrade warning:** older builds cannot read the canonical envelope, and they may
overwrite migrated preferences. Device QA must not install an older build over migrated data.

1. Existing Lists are all present.
2. Create a List and delete it; reopen the timer in two activity/instrument contexts and in
   the import picker. The List does not return, and the picker is alphabetical.
3. Save from the timer pad; it appears in the manager.
4. Adopt a received List; it survives a save from an already-open manager.

**PDFScoreView** (under Xcode; simulator with a synthetic score, or device):
1. Opening a score in the practice timer shows no "Publishing changes from within view
   updates" warning.
2. Swipe, close and reopen restores the last page.
3. A quick open-then-close behaves normally.
4. A missing or corrupt PDF attachment shows its failure message once.
5. Backgrounding, or covering the viewer, and returning reports the current page.

## Deferred with limits

- **F-3 media (M1, simulator only).**
  - Fresh-asset `duration` repeats were sub-millisecond for synthetic AAC (0.3–44 MB) and WAV
    (26 MB).
  - The surrogate `.atomic` write is a **measured main-thread cost**: up to **22.3 ms** at
    44 MB, in the body, when the file is absent.
  - There is no device-direction claim. MP3, body frequency and device cost are unmeasured.
  - **F-3 stays OPEN.** Sizing needs a device `xctrace` run with Samuel (0 against 8 audio
    attachments). No implementation.
  - Handover: `claude-opus5-media-performance-handover.md`
- **F-6 delivery reconciliation: DEFERRED (P3).**
  - **No validated client-only clean-up has been identified.** A final `42501`/`23514` does
    not exclude an earlier committed execution while replay remains possible.
  - The sender cannot read delivery rows.
  - The blanket clean-up stays withdrawn.
  - The B-8 operator sweep is an existing avenue.
  - Scope: `claude-opus5-delivery-reconciliation-scope.md`

## Remaining unaffected Phase 6 inventory

From the agreed order in `docs/phase-6-audit-2026-09-17/phase-6-reconciled-synopsis.md`:
attachment preservation; queue ownership, durability and withdrawal; Lists; attestation;
then media, delivery, and cleanup/documentation.

| Item | Status |
|---|---|
| P6-I-01 attachment preservation | **Done**, `22e5af6` |
| P6-I-02 queue ownership and durability; withdrawal reporting (F-2); sharing-choice persistence | **Done**: `cf8193e`, `9aa3338`, `fd6c22c`, `e6d2fc2`, `325a27f`. Cross-device/server ordering is frozen (the six blockers) |
| P6-I-04 Lists (and F-1) | **Done**, `90ab06e`. The listed device checks are user-reported green. **A suspected instrument-transition regression is OPEN** (Codex investigating) |
| P6-I-05 attestation ownership | **Accepted, uncommitted** |
| PDFScoreView warning | **Accepted, uncommitted**. The listed runtime/device checks are user-reported green; the console excerpt showed no warning |
| F-3 media | **Deferred**; needs device evidence |
| F-6 delivery reconciliation | **Deferred**; no validated client option |
| F-5 dead AudioServices path; F-7 fifteen unreferenced types; F-8 dead resume flag; backup-helper naming | **Optional cleanup**. "Zero behaviour change" is a **target** that needs fresh call-site checks at the time; it is not verified for any future deletion |
| C-22 AVFoundation deprecations | **Optional cleanup**, bounded by F-3; not swept |
| C-12 unreachable deletion UI | **Optional cleanup**, with dependencies to check first |
| F-9 `SimulatedPublishService` | **Needs a decision/evidence**: confirm nothing relies on delete in `.local` mode |
| Three dead `membership_control` cutover columns | **Needs a decision**: production DDL; separate guarded authorisation |
| F-10 / F-11 / F-12 record drift (`AGENTS.md` against `CLAUDE.md`, the C-22 count) | **Needs a decision**: `AGENTS.md` is protected and untracked |
| C-97 induced faults (capture errors, interruption, missing-audio watchdog); drone unplug discriminator | **Needs device evidence** |
| Forced purchase attestation joining older work | **Unverified candidate**; not scoped |

**No further unit is started.** What remains is gates (device, legal and adult-assurance,
provider, production authorisation), decisions, or optional cleanup. Per instruction, work stops
here.

## F-5 clean-up: CODE REVIEW ACCEPTED (19 September 2026)

- **Codex's code review accepted it.** Dead `AudioServices` recording and video-preview branches
  and helpers were removed. Live playback is unchanged, and a doc comment on
  `RecordingInputPolicy.preferred` states the live input policy.
- **Hashes:** `MOTIVO/AudioServices.swift` `340b3f72d1c278d09dd6a8cef90b7839cae1526e51f542d1e316cca9ba88d08a`,
  `MOTIVO/RecordingInputPolicy.swift` `3ed253bac745a3409eb617bf13d756e57050e405169c787a1b2112ee2031fcab`.
- **Evidence:**
  - `RecordingInputPolicyTests` 12 passed, 0 failed.
  - **Full suite 762 passed, 0 failed, 6 skipped, 768 total**
    (`Test-MOTIVO-2026.09.19_09-05-03-+0100.xcresult`), which also covers the Lists decoder
    delta.
  - Debug and Release succeeded. No device QA is needed.
- **Ten reviewed source and test files are now frozen, uncommitted:**
  - P6-I-05 (2);
  - PDFScoreView (3);
  - the Lists instrument default (3);
  - F-5 (2).
- **Lists device acceptance remains OPEN.** Samuel has not yet answered about the build or the
  original instrument.
  - **No further changes and no new clean-up** until the device symptom is resolved.
  - **No device data extraction and no reset.**
  - Codex's heartbeat is paused.

## Lists instrument transition: new-build observation (19 September 2026), FAIL/OPEN

- **On the new build**, starting from one instrument (Bass) with a Practice default selected,
  Samuel added Piano. Piano:Practice shows the default. **Bass:Practice, selected explicitly
  without tapping, shows no default.**
- **Bass sorts first**, so an alphabetical-selector explanation alone is insufficient.
- **The source trace points to Bass's own instrument keys:** a historical `false`, or a typed
  override from earlier multi-instrument use. Which one, and whether it was accidental, **is not
  established**.
- **Not declared:** transfer, deletion, or OFF repair.
- A revised diagnosis, with a no-code check and an optional temporary Release-visible probe (for
  review), is in `claude-opus5-lists-instrument-diagnosis.md`.
- **No changes have been made.**
- **Update:** Bass remains the primary instrument with Piano present.
  - **The source establishes the single/multi key inconsistency. Stale device keys are an
    unmeasured hypothesis.**
  - A pad check alone is not decisive. No probe, and no Release logging.
  - **Codex is recommending a product rule to Samuel, pending confirmation:** defaults belong
    to instrument plus activity whatever the instrument count; Bass:Practice keeps its choice;
    Piano does not inherit it.
  - **Code is on hold.** Once the rule is agreed, the implementation and a separate legacy
    migration (preserving history, no automatic OFF repair) will be scoped.
  - **No commit, push or deploy.**

## Lists: explicit default per (instrument, activity), implemented and FROZEN for review (19 September 2026)

- **Samuel's rule:** a default List is explicit per (instrument, activity), whatever the number
  of instruments; nothing is inherited, assigned or transferred; new combinations have none.
- **This supersedes the inherited-display fix.** Its files were removed and never committed.
- **The manager and the timer share `ListsDefaultContext`** for keys, resolution (including an
  explicit OFF), and the instrument shown (primary, then first).
- **Legacy activity-only defaults are kept raw** and never applied to an instrument. **Bass's
  old default needs one explicit reselection; Samuel has been told.**
- **Evidence:** focused 39/0; full **764 passed / 0 failed / 6 skipped (770 total)**
  (`Test-MOTIVO-2026.09.19_09-56-12-+0100.xcresult`); Debug and Release succeeded.
- **Hashes:** `ListsDefaultContext` `aaa9c5c5…`, `TasksManagerView` `59f298fb…`,
  `PracticeTimerView` `30c6564d…` (a loader-only change against the prior frozen `f5d09b88…`),
  tests `5d693d33…`.
- **Device QA is pending.** No commit, push or deploy.
- **CODE REVIEW ACCEPTED by Codex; the files are frozen; device QA is PENDING.**
  - Codex independently checked the helper, manager and timer diff and the production tests.
    The 4 hashes match, `git diff --check` is clean, and the full suite gave 764 passed /
    0 failed / 6 skipped (770 total). Debug and Release succeeded.
  - There is correctly no cross-context fallback, and the superseded inheritance workaround is
    removed.
  - **Pending device QA (Samuel, after rebuilding):**
    - reselect Bass:Practice explicitly, once;
    - a fresh or re-added Piano has no default **unless a genuine earlier instrument-specific
      explicit assignment exists, which is preserved**;
    - set Piano:Practice and a different Bass activity independently;
    - sessions on fresh pads follow each combination's own choice, and no current pad is
      overwritten;
    - removing Piano leaves Bass unchanged.
  - No further edits or clean-up while waiting for Samuel's QA. No commit, push or deploy.
    Codex automation is paused.

## FINAL ACCEPTANCE AND CHECKPOINT COMMIT (19 September 2026)

- **Lists explicit defaults: device QA reported ALL GREEN by Samuel** on the rebuilt app:
  - Bass:Practice was reselected explicitly once, and each (instrument, activity) pair keeps its
    own default independently;
  - a new or re-added instrument has none;
  - adding or removing an instrument leaves the other instruments' choices unchanged;
  - sessions on fresh pads follow each pair's own choice, with no current pad overwritten.
- **The inherited-display workaround is finally superseded.** It was never committed, and its
  files were removed before the explicit-default implementation.
- **Reviewed, accepted work in this checkpoint commit:**
  - **P6-I-05** attestation completion ownership. Code accepted; no device QA needed for
    in-memory ordering.
  - **PDFScoreView** update-pass publishing. Code accepted; its device checks were earlier
    reported green by Samuel.
  - **F-5** dead `AudioServices` recording/preview removal. Code accepted; no device QA needed.
  - **Lists explicit default per (instrument, activity).** Code accepted, and device QA green.
- **Final verification:**
  - full `MOTIVOTests` **764 passed, 0 failed, 6 skipped, 770 total**
    (`Test-MOTIVO-2026.09.19_09-56-12-+0100.xcresult`);
  - Debug and Release **BUILD SUCCEEDED**;
  - frozen hashes re-verified before the commit.
- **Excluded from the commit, and untouched:** `docs/connected-invitations-direction.md`,
  `docs/private-connection-invitations-scope-2026-09-17.md`, and the untracked `AGENTS.md`.
- **Unchanged boundaries:**
  - the R0 adult-assurance freeze;
  - the sharing server freeze (six blockers OPEN);
  - F-3 and F-6 deferred;
  - optional clean-up continues one bounded unit at a time, **only after Samuel pushes**.
- **This commit permission is specific to this checkpoint.**
