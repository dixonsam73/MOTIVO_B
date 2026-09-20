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
  - `SimulatedPostCommentService` (public, simulated backend family). **F-9 itself is now
    implemented; see below.**
- **Optional clean-up:**
  - **C-22**, the AVFoundation deprecation sweep, bounded by F-3;
  - **C-12**, the unreachable deletion UI, whose dependencies need checking first.
  - **C-15** (`PDFSelectedPagesStore`): **OPEN, P3 residue. Deferral is recommended; it is not
    closed, and it is not user-accepted.** The trace found:
    - the entries are UUID-to-page-number metadata, device-wide, cleared on removal inside an
      editor but **not** on journal session deletion, and wiped by Erase All;
    - **no document-content leakage was established**;
    - growth has not been measured.
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

## Later on 19 September 2026: F-9, implemented and ACCEPTED (uncommitted; awaiting Samuel's commit approval)

**Independent review (Codex, 19 September 2026): ACCEPTED.** Codex checked:
- the full source diff and the test;
- that the hashes match;
- that `HTTPBackendPublishService` through the end of the file, and the shared
  `isAlreadyAbsent`, are unchanged from `HEAD` (compared independently);
- the raw xcresult: **765 passed, 0 failed, 6 skipped, 771 total**;
- that the focused and full logs show F-9 and B19 passing;
- that Debug and Release succeed;
- that the protected-file hashes are unchanged.

**No device QA is required** for this scoped change.

**The accepted trace:** no Release caller of `SimulatedPublishService.deletePost` was found in
current source. A retained-token **Debug** path (the `#if DEBUG` Debug viewer, in local mode)
could issue **live, authenticated** deletes.

**The change** (`MOTIVO/BackendShim.swift` only):
- **`SimulatedPublishService.deletePost` performs no network deletion.** It records a simulated
  call and returns **`.failure(SimulatedPublishError.deletionNotPerformed)`**.
- The error renders as *"Not deleted: the simulated backend performs no network deletion."*
  through both `localizedDescription` and **`String(describing:)`, which the Debug viewer uses**.
  **No false "Deleted" is shown.**
- The class's nested, now-unused private helpers are removed (`PostAttachmentsRow`,
  `AttachmentsField`, `AttachmentRef`, `deleteStorageObject`).
- **`isAlreadyAbsent` and `HTTPBackendPublishService` are byte-identical.** Verified by comparing
  the preserved regions with the pre-edit file.
- **There is no Release behaviour change.**

**Evidence:**
- **`F9SimulatedDeleteTests`** (the held `QueueStubServer`; a configured backend; a retained
  synthetic token; local mode): the simulated service is selected, the delete fails with
  `.deletionNotPerformed`, the exact `String(describing:)` text matches, and **zero requests**
  are sent.
- **HTTP regression retained:** `P6I02BoundTransportTests.testB19_AmbientDeletePostIsUnbound`
  passed.
- Focused (F-9, `P6I02BoundTransportTests`, `P6I02WithdrawalOutcomeTests`): **46 passed, 0
  failed.**
- **Full suite: Passed; 765 passed, 0 failed, 6 skipped, 771 total**
  (`Test-MOTIVO-2026.09.19_12-42-36-+0100.xcresult`, local scratchpad). Debug and Release
  succeeded.
- **Hashes:** `BackendShim.swift` `7b34a06b05a7b50fc140a68c66d5aa09495d624e2e669d8d75c340baf2dee23b`,
  `F9SimulatedDeleteTests.swift` `78992f6b3deb74c72eddfbef656bf91efe9f2b12810f63d78a68e589f59d9b48`.
- No device QA is expected.

## Later on 19 September 2026: C-97 part (2), video-recorder capture disruption. Implemented; code review ACCEPTED for device QA; NOT committed

**Change** (`MOTIVO/VideoRecorderView.swift`, new `MOTIVO/CaptureDisruptionTracker.swift`,
tests in `MOTIVOTests/C97CaptureDisruptionTests.swift`):
- **After a capture runtime error or an audio media-services reset:**
  - an active take is finalised through the existing stop path;
  - capture is torn down **after** the writer completes;
  - the automatic playback resume is inhibited;
  - Record and flip are refused **until the recorder is closed and reopened**, the only
    recovery.
- **A capture interruption** stops an active take; its end never restarts capture.
- **Every queued delivery is bound to the recorder's presentation generation.**
- **The "kept" message** is given only after verified successful finalisation, and stronger
  messages win.
- **The alert title** is corrected from "Recording audio" to "Video recording".
- **Not touched:** the automatic audio configuration, the input logic, the writer. **No
  watchdog.**

**Device QA** (Samuel, the video recorder, the latest build; **the earlier audio-recorder trials
are excluded**, since the instructions for them were ambiguous):
1. **Idle, then Reset All Media Services:** the reopen alert; recovery worked as expected. **PASS.**
2. **A finished video playing in review, then a reset, then return:** the review-specific
   save/discard/reopen alert; paused state.
   - **Preservation and Save: PASS.** The saved video then played in full in the timer
     attachment viewer.
   - **In-recorder playback after the reset:** black and non-functional. **A CONFIRMED
     LIMITATION**, no longer merely unverified. The review player is not rebuilt.
3. **The first video after an app relaunch (claps):** the opening audio and A/V sync are
   **green**.

**Verification:**
- full `MOTIVOTests` **777 passed, 0 failed, 6 skipped** (783 total) before the title and comment
  corrections;
- Debug and Release succeeded;
- after the title change: a Release compile, and `git diff --check` clean.

**OPEN limitations (C-97 NOT closed):**
- **A pending start** (armed, before its first frame) during a reset or interruption proceeds on
  possibly unusable capture; safe cancellation needs a writer-setup audit;
- **no device coverage of an active-take failure** (Settings backgrounds the app, and resigning
  active stops the take first);
- **in-recorder review playback after a reset** (confirmed; Save works);
- no watchdog; interruption reasons are handled generically;
- part (1) is unchanged.

## Later on 19 September 2026: journal delete must not re-create a queued post. Code review ACCEPTED; NOT committed

**The defect.** A Connected journal delete (`ContentView.deleteSessionsWithBackendIfNeeded`)
deleted the backend post and then the local entry, but **never touched `SessionSyncQueue`**. A
same-owner publish still queued for that post stayed queued. On the next flush,
`loadIncludedAttachments` found no session and returned `[]`, and `uploadPostImpl` INSERTed the
post from the self-contained payload. **The result was a re-created, text-only post for an entry
the member had deleted, with no in-app route left to withdraw it.**

**Reproduced first, with synthetic fixtures only** (loopback `QueueStubServer`, a synthetic owner,
a disposable Session). The timeline:
1. POST 500 (the first attempt fails, so the publish stays queued);
2. the journal delete sends GET, then DELETE;
3. the next flush sends **POST 201**.

**The bounded fix (same owner only).**
- **`JournalDeleteBackendStep.run`** (new), called by ContentView:
  1. the existing backend delete, unchanged and fail-closed;
  2. then **`SessionSyncQueue.supersedeQueuedPublishForJournalDelete`**.
- **Local deletion happens only if both succeed.**
- **The owner is captured in `deleteSessions` before the `Task`.** An account switch across the
  backend await refuses.
- **The queue must be saved before it can answer.** A halted or diverged store gets one
  `recoverIfNeeded` attempt and refuses if that fails. **An in-memory `.unshare` from an earlier
  failed write does not bypass this.**
- **The replacement:** the captured owner's queued `.publish` is replaced by an owner-bound
  `.unshare` (C-61: last intent wins). **A non-durable enqueue refuses.**
- **With nothing queued, the requests and the queue are unchanged. Other owners' work is
  untouched.**

**Stated behaviour changes:**
- **A halted or unsaved queue now refuses a journal delete** unless recovery succeeds. The entry
  stays; the server post is already deleted.
- **An account switch during the backend delete now refuses.**

### Verification

- **Focused `JournalDeleteQueuedPublishTests`:** 9 / 9 passed.
- **Mutation check:** with the supersession made a no-op, 5 cases fail (repro, owner switch,
  repeat durability, halted-then-recover, halted-unrecoverable). The 4 that assert unchanged paths
  pass. **The source was restored and its hash re-verified.**
- **`PublishConsentCarriageTests`:** the payload inventory count moved **9 → 10**, deliberately,
  because the new site is `isPublic: false` and cannot carry attachments. The first full run
  failed on exactly this assertion.
- **Full Debug suite (iOS 26.4 simulator): 787 passed / 0 failed / 9 skipped (796).**
- **Release build: succeeded.** `git diff --check` is clean.

**Skip accounting against the C-97 baseline** (777 / 0 / 6, 783):
- **No baseline case is missing, and no case changed result.**
- **The baseline's 6 skips are identical:** three `SyncQueueOrderingReproductionTests` sequences
  (not exercised in the run), and `P6I02WithdrawalLocalStackTests` TL5 to TL7 (isolated rehearsal
  modes only).
- **The +13 cases are:**
  - the 9 new tests;
  - **4 UI-test cases absent from the baseline bundle**: `testLaunch` passed, and three
    `AccessibilityAndPersistenceTests` skipped on their own preconditions (*"Timer not present"*,
    *"No sessions available to open"*, *"Activity Manager not available"*).
- **Why the baseline bundle has no UI-test cases is not established.**

**Device fault injection was not required** for this queue-only checkpoint (Codex): the synthetic
fault and retry tests cover the changed path.

### Limitations

- **Guarantee:** on this installation, after a Connected journal delete returns success, a
  same-owner publish for that post that was still queued, not dispatched, when the supersession
  was enqueued does not re-create the post.
- **A publish already in flight is NOT solved** (open sharing blocker 1).
- **The delayed `.unshare` is new.** When it runs, it deletes whatever row of that id this owner
  holds at that time. **A newer legitimate share of the same id published elsewhere in between
  would be withdrawn.** A restored backup bringing the session back on another device is one
  example; whether other routes exist is not established.
- **Core Data is not transactional with the backend or the queue.** If the final save fails, the
  entry reappears on relaunch while its post stays deleted. A refusal's early `return` also skips
  saving earlier rows in a multi-row delete (a pre-existing shape; current callers pass one
  index).
- **Not covered:**
  - other devices and restores;
  - the Solo / lapsed journal delete;
  - row-less or unreferenced bytes;
  - physical file deletion (API-reported only, subject to vendor unknowns);
  - `noRowMatched` ambiguity.
- **The six broader sharing and deletion blockers remain OPEN.**

### Agreed intended behaviour: cross-owner follow-up

**Samuel has agreed:** deleting a local journal entry should prevent pending shares under
**either** account on this installation from publishing later, and server withdrawal must remain
**authorised by the owning account**.
- **This is recorded intended behaviour, not a pending decision.**
- **It is deliberately outside this same-owner checkpoint.** It needs its own bounded scope and
  review, covering at least:
  - how another owner's queued publish is stopped without acting as that owner;
  - durability and recovery;
  - quarantined (unknown-owner) items;
  - what the member sees.

## Separate evidence: cleanup run #25 (USER-SUPPLIED, not independently fetched)

**Source.** Samuel supplied the invoke-step log of the first scheduled `membership_cleanup_v1`
run after the recorded 18 September deploy. Run `35431142646`, job `105865822133`, on
2026-09-19. Claude's sessions could not read the log; an anonymous API request returned 403.

**Supplied values:**
- mode `execute`;
- request body `{"mode":"execute","limit":25}` (29 bytes, sha256
  `1c1d0b8d3562235732a3b60ba5fd5ed13685c733ae14e9f0b0567cc07597b93a`);
- proxy env present `False`;
- HTTP 200;
- response `{"ok":true,"mode":"execute","identities":0,"results":[]}`.

**What this establishes, for this run only:** it ran in execute mode, **processed zero
identities**, returned an empty per-identity result list, and reported **no per-identity
failures**.

**What it does NOT establish:**
- any real deletion;
- a global candidate census;
- which deployed function version answered;
- **G7, which remains OPEN** (the Phase 3 obligation, earliest 2026-11-01).

## Later on 19 September 2026 (overnight): U1, journal delete withdraws every queued publish and explains refusals. Code review ACCEPTED; NOT committed

**Samuel's decisions (recorded, not to be re-asked):**
- **D1:** deleting a journal entry withdraws its pending **and** already-published posts, including
  in Solo / lapsed, acting only as the owning account.
- **D2:** Erase All removes ALL local data, including any queue or cleanup records.
- **D3:** a refused deletion is explained.
- **The product model is one Connected account.**

**D1 is NOT fully met by U1:** posts already acknowledged (published and dequeued) need
ownership evidence, which is scoped separately (U3).

**What U1 changes** (it extends `a0313cb`'s same-owner fix):
- **`SessionSyncQueue.supersedeQueuedPublishForJournalDelete`:**
  - every queued `.publish` for the post, **of any owner**, becomes an `.unshare` owned by that
    same owner, sent only as that owner, when that owner is current;
  - a quarantined `.publish` becomes an unowned `.unshare` that stays quarantined;
  - **all of it is one write**; a non-durable write refuses, and an unsaved queue is recovered
    first or refuses;
  - **the C1 handoff ledger and markers are untouched** (the withdrawal carries no token), so a
    surviving marker is cleared rather than replayed over the withdrawal;
  - **no owner is ever invented.**
- **`JournalDeleteBackendStep`:**
  - `run` (Connected: backend delete first) and `runLocalOnly` (Solo, lapsed, signed out);
  - each runs the queue step and then, **in the same synchronous turn**, a `deleteLocally`
    closure;
  - `deleteSessionLocally` deletes the Session in its **own** background context and saves only
    that change. **Media files are removed only after the save succeeds.** On failure, the view
    context holds nothing pending and no unrelated edit is discarded. The view context learns of
    the deletion through its normal automatic merge.
- **`ContentView`:** every journal-delete branch goes through the helper. A refusal shows **"Session
  not deleted"** with one of three neutral messages:
  - "Études couldn’t confirm that this session’s shared post was removed, so the session has been
    kept. Try again."
  - "Your Études account changed while this session was being deleted, so it has been kept. Try
    again."
  - "Études couldn’t finish deleting this session, so it has been kept. Try again."

  **None of them promises anything about server state.**

### Verification

- **`JournalDeleteQueuedPublishTests`: 20 cases through the production helper and queue,** with
  synthetic fixtures only (a loopback stub, synthetic owners, disposable Sessions and files). They
  cover:
  - another owner's queued publish sent later as that owner, with no POST;
  - signed-out and Solo deletes;
  - an account switch;
  - quarantine;
  - several owners in one write, with no partial state on failure;
  - a failed write, a retry, and a relaunch;
  - a store halted at launch;
  - the handoff ledger untouched, a surviving marker cleared rather than replayed, and a marker
    that was never taken removed with its row;
  - a failed local save keeping the session and its files with nothing pending;
  - a successful delete removing the row through the normal merge, with unrelated unsaved edits
    surviving.

  **An immediate recovery was run while the view context was still stale**, and it re-enqueued
  nothing.
- **Four mutations were caught** (converting only the captured owner, no quarantine, a ledger
  entry removed, files deleted before the save), and the source was restored by hash.
- **Full Debug suite: 798 passed / 0 failed / 9 skipped (807).** The skips match the earlier
  accounting (6 baseline, 3 UI preconditions). **Release: build succeeded.**

### Limitations

- **Not covered:**
  - already-acknowledged posts (U3);
  - a publish already in flight;
  - other devices;
  - `noRowMatched` ambiguity;
  - row-less or unreferenced bytes;
  - physical deletion (API-reported only, vendor unknowns).
- **The delayed withdrawal now applies to every owner.** When it runs it deletes whatever row of
  that id its owner then holds. A newer legitimate share published elsewhere in between would be
  withdrawn (a restored backup on another device is one example).
- **If the local save fails after the queue step,** the entry is kept, but its pending shares are
  now withdrawals. **The entry still reads Share ON while its post will be withdrawn.** Saving the
  entry again re-shares it.
- **A withdrawal whose owner never returns is held indefinitely,** as its publish was.
  `handoffBlockedPosts` withholds a converted withdrawal until the next recovery recomputes it.
- **Device smoke test is pending for the morning** (Release: Connected and Solo swipe-deletes). No
  forced fault injection on Samuel's device.
- **The six broader sharing and deletion blockers remain OPEN.**

## Later on 19 September 2026 (overnight): U2 (erase copy) and U3 (withdrawal attempts for acknowledged posts). Reviewed; NOT committed

**U2, copy only (Codex ACCEPTED).** `ProfileView.eraseAllEtudesDataExplanation`:
- **The local erase explanation now adds:** *"This does not delete posts already shared with Études
  Connected. Any pending requests to remove shared posts will also be erased. To delete a Connected
  account and its posts, sign in to that account and use Delete Account."*
- **The account-delete explanation now adds:** *"This deletes only the Connected account you are
  signed in to. If you previously used another Connected account on this device, its shared posts
  are not deleted by this action."*

**No behaviour changed.** D2 already held: Erase All wipes the whole queue and ledger.

**U3: posts already acknowledged (no queue item left).** In the same single write as U1, the
journal delete also gives **candidate owners** a durable, owner-bound **withdrawal attempt**:
- **every owner the durable C1 handoff ledger names for the post.**
  - The ledger survives acknowledgement and is cleared only by a factory reset.
  - It is **evidence that this install queued a saved choice as that owner, not proof of
    publication.**
  - Malformed, `~` and non-UUID keys are skipped, and the ledger is never modified.
- **the captured identity, only when the entry was shared.** This is a **self-scoped attempt, not an
  inference of ownership.**

**Why it is safe:** every request of a withdrawal is sent as its owner and filtered on
`owner_user_id`, so a candidate that does not own the post matches nothing. **No owner is invented.**

### U3 guarantee (bounded)

**U3 guarantees only durable, authorised withdrawal ATTEMPTS for the candidates it can name. It
guarantees removal for no post:**
- an owner may never return;
- a candidate may not be the owner;
- a publish may be in flight;
- other devices are not covered.

**The legacy gap stays OPEN as a product disposition for Samuel, and is NOT accepted:** a post
acknowledged before C1 (no ledger entry), then deleted while signed out, gets no attempt.
Unknown-owner (quarantined) withdrawals still cannot dispatch.

### U3 verification

- **Eight new cases through the production helper and queue** (synthetic, loopback stub):
  - a ledger owner's attempt is sent as that owner with its owner filter;
  - a signed-out ledger owner waits for that identity;
  - legacy attempts happen only when shared, and nothing is added when signed out (the gap);
  - a **non-owner candidate matches nothing**, and the owner's row, refs and objects are
    untouched (no storage call);
  - each candidate is sent only as its own owner;
  - malformed and unowned ledger keys are skipped, both in the parser and through a reloaded
    durable ledger;
  - conversion and appends go in one write: nothing partial on failure, durable after recovery
    and relaunch, and existing withdrawals unchanged.
- **The loopback stub gained an opt-in owner filter** (off by default, reset per test), in
  `SyncQueueOrderingTests.swift`, so the non-owner cases can see RLS-like owner scoping.
- **Full Debug suite: 806 passed / 0 failed / 9 skipped (815).** The +8 are exactly the U3 cases;
  the 9 skips are unchanged. **Release: build succeeded.**

## Later on 19 September 2026 (overnight): read-only findings (no code change)

- **Sharing blockers #2 (lifecycle release / epoch ownership) and #6 (refusal handling) are
  prospective only.**
  - Their constructs (`cleaned_through`, `satisfied_by_cleanup`, `refs_invalid`, `seq_reused`)
    exist nowhere in client or server code.
  - The only current analogue of #6, the flush's phase-blind "409 means success" heuristic, is
    **latent**. The POST 409 is already absorbed by typed status in `uploadPostImpl`; `posts`
    carries only its primary key; and no later-phase 409 trigger is established. It is **not**
    treated as a production defect. A stub-supplied-409 regression test would still test the
    failure-handling contract; any defensive fix awaits its own scope.
  - **No bounded local fix was identified in this limited pass. That is not a finding of
    impossibility. All six remain OPEN.**
- **B-38.** The client never writes `avatar_version`. **The register's candidate column revoke would
  not work,** because `authenticated` holds table-level INSERT/UPDATE on `account_directory`. The
  guard-trigger or privilege shape is to be chosen only after local proof. **Any production change
  needs Samuel's approval and deploy.**
  - **Local proof (overnight, revised on review):** the **exact** apply and rollback statement
    bodies, extracted verbatim, ran inside one outer rolled-back transaction on the positively
    identified local stack, with synthetic identities.
    - Each re-stamp or "unchanged" assertion first set a distinguishable old value (2000-01-01).
    - **14/14 passed:** a baseline defect reproduction, the guard behaviour, a same-value re-stamp,
      the cleanup re-stamp, and the rollback restoring grants, the stamping trigger and the
      original behaviour.
    - **Local DB unchanged:** 10 users, 0 directory rows, no guard, no synthetic rows.
  - **The guard applies to every role,** including `service_role` and `postgres`.
  - **Status: PROPOSED.** The SQL is prepared outside `supabase/migrations/`, **not applied**. It
    needs a fresh production-parity capture, the B-23 gate, and Samuel's approval.
- **B-37.** Its Phase 6 disposition is **unresolved, for Samuel** (what the directory publishes; any
  rate limiting). Enumeration affects adults too, so it is **not** folded into the frozen adult-only
  work.

## 20 September 2026 — Samuel's morning decisions, and what was committed

**Decisions (recorded; not to be re-asked):**
- **The U3 legacy gap is ACCEPTED as a stated limitation.** A post acknowledged **before** the C1
  handoff ledger existed, then deleted while signed out, leaves no local evidence of its owner, so
  **no withdrawal attempt is made for it**. No new bookkeeping is being built for it, because none
  could reach posts that are already acknowledged.
- **Beta and TestFlight accounts and their posts are expendable.** **Device B is valuable
  long-term**, and Samuel accepts collateral loss there if it is genuinely needed. **This is NOT an
  instruction to delete anything**, and nothing was deleted.
- **B-37 stays a Phase 6 product and search question**, unresolved: what the directory publishes,
  and whether any rate limiting is wanted. **This is not a closure, and no rate-limiting decision
  has been invented.** It is **not** transferred to the frozen adult-only work; enumeration affects
  adults too.
- **B-38 deployment is approved by Samuel**, with the reviewed SQL, a fresh production-parity
  capture and independent preflight review still required before the apply.

**Committed 2026-09-20 (`0b606dfb`, not pushed):** the reviewed U1–U3 unit, seven files —
`SessionSyncQueue.swift`, `JournalDeleteBackendStep.swift`, `ContentView.swift`,
`ProfileView.swift`, `JournalDeleteQueuedPublishTests.swift`, `SyncQueueOrderingTests.swift` and
this document. Full suite **806 passed / 0 failed / 9 skipped (815)**; Release build succeeded.
**The protected invitation documents and `AGENTS.md` were excluded.**

**Device smoke testing remains OUTSTANDING and is not green:** a journal swipe-delete while
Connected, and one in Solo. C-97's remainder (effective-route enforcement and the drone unplug
discriminator) and F-3 media sizing are carried, unchanged; **QA7 and QA1–8 stay green and are not
re-requested.**

**B-38's deployment artifacts are prepared in `supabase/sql/`** (the guarded apply, its rollback,
`README-b38-avatar-version-guard.md` and the local-proof evidence). **Nothing has been applied to
production.**
