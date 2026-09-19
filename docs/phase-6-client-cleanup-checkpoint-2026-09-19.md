# Phase 6 — client clean-up checkpoint (19 September 2026)

**Status:** all three units below were reviewed and accepted by Codex. **Samuel explicitly
approved committing this clean-up checkpoint** (the ten reviewed Swift files, this record, and a
link from the overnight record). It was committed on 19 September 2026 on top of `707b1fb`, and
Samuel pushes. Nothing was deployed.
- **Base:** `707b1fb` (pushed), on `feature/solo-connected`.
- **Workflow:** Claude implements, Codex reviews, Samuel approves commits and pushes.
- **Commit authority is specific to each checkpoint, including this one, and is not blanket.**
- **Scope:** dead or unreachable client code only. There is **no behaviour change, and no
  backend, age, sharing or invitations work**. The protected dirty files are untouched:
  `docs/connected-invitations-direction.md`,
  `docs/private-connection-invitations-scope-2026-09-17.md`, and the untracked `AGENTS.md`.

## Units

| Unit | Change | Status |
|---|---|---|
| **Dead state (F-8, plus the decoder)** | Removed the never-read `shouldResumeAfterRouteChange` and its two writes (`VideoRecorderView`), and the caller-less `decodeTypedTaskPresetLines` (`PracticeTimerView`; `SerializedTaskTemplateLine` kept). −19 lines. **This route-change handler has no automatic resume path, before or after.** Nothing more is claimed about lifecycle or device outcomes | **Accepted** |
| **F-7, file-scoped UI batch** | 10 private or file-private unused SwiftUI types removed from 6 files: `StatsBannerView`, `BackendPostRow`, `PeoplePlaceholderView` (`ContentView`); `VideoPreview` (`MediaTrimView`); `ResponsesPostDetailHost` (`PeopleView`); `VideoPlayerSheet`, with its `#if canImport(UIKit)` block (`PostRecordDetailsView+Attachments`); `StatChip`, `FlexibleChipsView` and the knock-on `TagChip` (`ProfilePeekView`); `SettingRow` (`ProfileView`); plus two orphaned headings. −285 lines | **Accepted** |
| **Internal UI batch** | 3 internal unused types removed: `CommentContinuationMetaRow` (nested in `CommentsView`), and `VideoOrIconTile` and `NonImageTile` (`ContentViewRowSupport`, with `NonImageTile`'s heading). The neighbours `SingleAttachmentPreview` and `FeedRowAttachmentThumb` are kept. −141 lines | **Accepted** |

**Independent review (Codex, 19 September 2026): all three units ACCEPTED.** For the
internal-UI batch, Codex checked:
- the full 141-line diff;
- all ten source hashes and the protected-file hashes;
- that the removed names are absent everywhere;
- the Debug and Release logs, and the xcresult (764 passed, 0 failed, 6 skipped).

Codex also confirmed that the recovered overnight record differs from `HEAD` only by the
intended link section.

**Method, for every unit:**
- a fresh whole-word search before and after, across the app, unit tests, UI tests, project
  file, Supabase tests and resources;
- pure deletions only, and `git diff --check` clean;
- **Debug and Release builds.** They corroborate the search; they are **not** a universal proof
  of dynamic use. The reasoning holds for plain Swift types;
- the full unit suite;
- **no new deletion-only tests and no device QA** (the code was unreachable).

## Reviewed file hashes (verified before the checkpoint commit)

| File | SHA-256 | Unit |
|---|---|---|
| `MOTIVO/VideoRecorderView.swift` | `6d9b7fa80b046dacb1db9a9fe9d6ebf1c785b335916e4bb4bf6a9c2240a9a75a` | dead state |
| `MOTIVO/PracticeTimerView.swift` | `80528f66d7e1b5cc8ea7afad3e2071adc222744621048e3b886c744ed034c367` | dead state |
| `MOTIVO/ContentView.swift` | `cae85bb69f84fbea18747823ea89bdde5fdab4ad7dba44415014706782da46f5` | F-7 |
| `MOTIVO/MediaTrimView.swift` | `a02ed683dd6bf25ce9cd2e214cbfbcd9738c585db87e85807e936dc66a0139ca` | F-7 |
| `MOTIVO/PeopleView.swift` | `be5046622bda180e0e840569346afd69fb7787680233bd4bca1b15c3a7bb1823` | F-7 |
| `MOTIVO/PostRecordDetailsView+Attachments.swift` | `ed5572d77f1e242c35a6f6e02a5e9bc05232f198a91b75ab21a6b1cb3a3c7f75` | F-7 |
| `MOTIVO/ProfilePeekView.swift` | `669dd3de60b02efc3c8333e8741b5f0fd2e63fed40e2360344494044f60d0ca6` | F-7 |
| `MOTIVO/ProfileView.swift` | `cad37089792b63524f97c821fca8011682d30cd438bd10479d83aba9c79abb85` | F-7 |
| `MOTIVO/CommentsView.swift` | `714dbe1486eced9064a487e3b982e2e545dc57b3ac9ad0935bf7e848dc5cdac4` | internal UI |
| `MOTIVO/ContentViewRowSupport.swift` | `43810752cdabb6511a12367063b54b0b0ccf17138118acd55366d8e0a5685ae7` | internal UI |

## Final tests (this tree: all three units applied)

- **Full `MOTIVOTests`: Passed; 764 passed, 0 failed, 6 skipped, 770 total.** The skips are the
  existing opt-in reproduction and local-stack suites.
- **Debug and Release: BUILD SUCCEEDED.**
- **Result bundles are local and temporary (in the Claude scratchpad):**
  - dead state: `Test-MOTIVO-2026.09.19_10-51-41-+0100.xcresult`;
  - F-7: `…_11-21-14-+0100`;
  - internal UI: `…_11-45-29-+0100`.

## Remaining inventory (not started; each needs its own scope or gate)

- **Deferred clean-up:**
  - `TasksManagerImportLauncherSheet`, together with the Lists manager's unreachable import
    scaffolding (`taskImportPasteSheet`, and the save-current prompt paths);
  - `AttachmentSharePageScope`: public, and in the sharing area, which is under the freeze;
  - `SimulatedPostCommentService`, together with **F-9** (`SimulatedPublishService`'s live
    delete).
- **Optional clean-up:**
  - **C-22**, the AVFoundation deprecation sweep, bounded by F-3;
  - **C-12**, the unreachable deletion UI, whose dependencies need checking first.
- **Needs evidence or a decision:**
  - **F-3**, media sizing on a device (`xctrace`);
  - **F-6**, delivery reconciliation, deferred: no validated client-only option;
  - **F-10 to F-12**, record drift (`AGENTS.md` is protected);
  - the three dead `membership_control` columns (production DDL, separate authorisation);
  - **C-97** induced faults, and the drone unplug check (device);
  - the forced purchase attestation joining older work (an unverified candidate);
  - the reverse instrument transition is **resolved** by the explicit-default rule in `707b1fb`.
- **Frozen by gate:**
  - R0 adult assurance;
  - the sharing server ordering and byte-clean-up blockers (six OPEN), and SU-478356.

**No further optional clean-up is started from this record.**
