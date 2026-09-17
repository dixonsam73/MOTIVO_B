# Études — independent Phase 6 audit

17 September 2026 · baseline `2fd0f63fe8b13eb8d7be72027ec83b55e78f7584`

## Executive assessment

**Five findings: three P1 release-blocking recommendations and two P2 defects.** The most consequential is a local save failure that can discard a recorded take. The other P1 findings concern pending sharing intents: they have no account ownership, and a failed disk write can leave an older publish durable after the member chose Unshare. These are failure-path findings, not reversals of accepted ordinary-use QA.

**No P0 defect was found in the reviewed scope. This is not whole-app safety certification.** The Release simulator build succeeded with zero errors. Four disposable source-based probes reproduced the narrow failures described below; neither production nor physical devices were exercised. No fixes, repository tests, commits, pushes or deployments were made.

Phase 6 should retain its bounded cleanup remit, with separate, small correctness batches for these findings before release. Legal/DPIA/publication gates and launch configuration remain separate. QA1–8, the CM-15 checks, Lists delivery/adoption, duplicate-save prevention and compact Send appearance remain accepted.

**Independence and authorship:** the requested `claude-phase-6-*` filenames are used, but this independent pass was performed by the current Codex agent. It is not a claim that Claude executed it or that two different models have now independently audited the app. No other new Phase 6 audit was read; only the shared brief, existing guidance, historical records and source were consulted. The comparison document leaves the other auditor's conclusions blank.

## 1. Baseline and scope

Branch `feature/solo-connected`; HEAD remained the hash above. At start and finish, the only dirty tracked paths were `docs/connected-invitations-direction.md` and `docs/private-connection-invitations-scope-2026-09-17.md`; `AGENTS.md` was untracked. Their content hashes remained unchanged. The scope document and [baseline.json](</Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/claude-phase-6-evidence/baseline.json>) record SHA-256 values, including `CLAUDE.md`. No reset to the brief's baseline was performed.

The two current invitation documents record approved scope and a proposed two-choice refinement, with legal/protocol/release dependencies. They do not establish shipped invitation behavior, and they give this audit no implementation authority. The operative B-40 rule remains in force. Historical Phase 3 counts and enforcement descriptions in guidance were not treated as current live evidence.

| Workstream | Actually reviewed | Limits |
|---|---|---|
| Local integrity | Both editor attachment-commit paths and callers; AttachmentStore; StagingStore save/replace/index locking/removal; SavedListLibrary and TasksManagerView loader; queue persistence; backup policy; reset coordinator | No personal records opened. No populated-store migration or genuine backup/restore rerun. No complete sweep of every editor |
| Connected security/privacy | Client publish/unshare, attachment upload/delivery/adoption; NetworkManager bearer selection; committed post/follow/storage RLS; teen request predicates; directory RPCs; deletion/expiry source | No live catalog capture, authenticated denial test, storage download, private-record query or full security review of every RPC |
| Membership/lifecycle | Attestation coordinator/service, StoreKit refresh/purchase shape, sign-out and app identity observers; cleanup live-read→writer→gate→delete ordering; B-39/B-40 source/snapshot | Cryptographic implementation and Apple responses not independently revalidated; no real purchase/lapse/revocation |
| Audio/video | Video capture notification and writer paths; DroneEngine and both start controls; timer observer; accepted CM-15 record | No microphone, route, interruption or media-services fault operated. Audio pitch was user-reported, not measured here |
| Sharing/UX | Lists bounds, provenance, duplicate adoption, owner check, loader and scoped existing tests; send retry shape; source-level accessibility limits | No visual, VoiceOver, Dynamic Type or complete navigation audit; network ambiguity not injected |
| Cleanup/release | Dead deletion handler reachability, misleading backup helper, PDF page metadata, Release/None scheme, manifest/bundle exclusions, build warnings, limited C-14 logging discriminator | No dependency vulnerability survey or device archive/signing/App Store validation; no full Debug/unit-suite rerun |

The committed schema was parsed as complete JSON arrays, preserving all rows rather than constructing a name-keyed map that could discard overloads. Inventory: 41 function records, 123 function-grant records, 33 policies, 12 triggers, 144 columns, 71 constraints, 562 column grants, 102 table grants, 15 RLS records and two buckets. Hashes are in [schema-inventory.json](</Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/claude-phase-6-evidence/schema-inventory.json>). **This is snapshot inspection, not a new B-23/live parity result.** JSON escaping was decoded before inspecting SQL definitions.

## 2. Ranked findings

IDs `P6-I-01`…`05` are temporary independent comparison IDs, not new allocations in the C-/B- register. Severity follows the brief: P1 proposed release blocker; P2 important. Confidence refers to the stated mechanism, not its frequency among users.

### P6-I-01 · P1 · Attachment-copy failure can become a successful save that deletes the staged recording

**Classification:** confirmed source defect, reproduced in a reduced synthetic harness. **Confidence: high.** No device occurrence asserted.

**Trigger:** any `saveDataWithRollback`/attachment-add failure while committing staged media, followed by a successful Core Data session save. An attachment filesystem failure need not make the separate metadata save fail. This also affects Solo.

**Call chain:** [MOTIVO/AttachmentStore.swift:150](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/AttachmentStore.swift:150>) throws on the permanent-media write. [MOTIVO/PostRecordDetailsView+Attachments.swift:826](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/PostRecordDetailsView+Attachments.swift:826>) catches it, rolls back previously created attachments, prints and `break`s; the function still returns normally at line 869. [MOTIVO/PostRecordDetailsView.swift:1872](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/PostRecordDetailsView.swift:1872>) then saves the session. Its success path removes **all staged IDs**, not only committed IDs, at [MOTIVO/PostRecordDetailsView.swift:1929](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/PostRecordDetailsView.swift:1929>), then signals `onSaved`. No error reaches the caller. The model permits sessions with no attachments.

**Observed probe:** the exact timer-review commit function, with metadata helpers stubbed and a deterministic failing filesystem writer, returned normally. A minimal in-memory Core Data session saved with zero attachments. The actual StagingStore removal code then changed the synthetic original's existence from `true` to `false`. The writer failure was an existing-directory destination, **not a claim to have reproduced an iPhone disk-full event**. [commit-result.txt](</Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/claude-phase-6-evidence/commit-result.txt>)

The sibling [MOTIVO/AddEditSessionView+Attachments.swift:546](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/AddEditSessionView+Attachments.swift:546>) also swallows the error and then clears its staged array at line 574, before [MOTIVO/AddEditSessionView.swift:2070](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/AddEditSessionView.swift:2070>) saves and cleans temporary media. That extension is source-confirmed, not separately runtime-probed.

**Existing IDs:** distinct from C-90 (writing *into staging*), C-99 (concurrent staging index work), and C-65 (remote preparation). Their fixes do not cover this transition from staged media to a saved journal session.

**Smallest remedy:** make attachment commit failure propagate to both save callers; abort the session save/success cleanup, preserve staged originals and metadata for retry, and roll back only this attempt's permanent copies. Clear draft/staging only after all attachment writes and the session save succeed. Validate first/nth attachment failure and metadata-save failure in both editors, with successful-save controls. No architecture rewrite needed.

### P6-I-02 · P1 · Pending publish/unshare work is not bound to the account that created it

**Classification:** confirmed source defect; queue behavior reproduced with a stub service, server consequence source-traced. **Confidence: high; full two-account HTTP reproduction outstanding.**

**Trigger:** account A has pending offline work; A signs out or loses its identity; account B later becomes Connected on the same installation and foregrounds.

**Call chain:** [MOTIVO/SessionSyncQueue.swift:71](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/SessionSyncQueue.swift:71>) stores no owner in the payload, and its single file is installation-wide at line 537. [MOTIVO/AuthManager.swift:1339](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/AuthManager.swift:1339>) and `clearConnectedIdentity` at line 1283 retain the queue. The identity observer at [MOTIVO/MOTIVOApp.swift:404](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/MOTIVOApp.swift:404>) resets feed/follows/attestation, not queue ownership. Foreground subsequently flushes at line 398. [MOTIVO/BackendShim.swift:961](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/BackendShim.swift:961>) assigns the **current** backend owner to the saved payload; line 1043 sends it as `owner_user_id`. Attachment lookup at line 1302 filters only the session UUID. [MOTIVO/NetworkManager.swift:225](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/NetworkManager.swift:225>) uses the current bearer.

**Consequence:** an A publish that never reached the server can be uploaded as B, to B's audience, with A's queued title/notes and eligible local attachments. RLS correctly checks that the new owner equals B's JWT, so it cannot recover missing original-owner provenance. No malicious server bypass is required. A second consequence is a queued A withdrawal: when B cannot see A's post, an empty SELECT plus zero-row PATCH/DELETE can be reported as success by [MOTIVO/BackendShim.swift:1653](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/BackendShim.swift:1653>) and line 1690, consuming the owed withdrawal while A's post remains.

**Observed probe:** the unchanged queue control flow, with its file redirected and transport replaced by an owner-recording stub, submitted the old payload under B and removed it. This proves the missing queue boundary; it is **not** a claim that A's real data was sent or that production RLS was exercised. [queue-result.txt](</Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/claude-phase-6-evidence/queue-result.txt>)

**Existing IDs:** distinct from C-98's late credential refresh and C-87's per-post ordering guard. The queue's `generation` changes on factory reset, not an ordinary identity transition.

**Smallest remedy:** persist the originating backend account with each intent, verify it before dispatch and after suspended work, and partition/hold work on sign-out so A's withdrawals survive for A. Do not simply discard privacy withdrawals. Explicitly decide safe migration for legacy ownerless items: ambiguous items must not upload as the newly signed-in account. Validate A→B→A with queued publish/unshare and an identity change during a request on disposable local fixtures. Legacy disposition needs Samuel's agreement.

### P6-I-03 · P1 · A failed queue write can restore an older publish after Unshare

**Classification:** confirmed defect, reproduced with actual filesystem permission failure and the current queue. **Confidence: high.**

**Trigger:** an older publish is durable; an Unshare replacement cannot be written; its network attempt also does not converge before process death.

**Call chain:** enqueue updates memory and invokes `persist`, including the operation-replacement path at [MOTIVO/SessionSyncQueue.swift:247](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/SessionSyncQueue.swift:247>). [MOTIVO/SessionSyncQueue.swift:503](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/SessionSyncQueue.swift:503>) catches the write failure and only logs it. The API cannot report failed durability. The editors have already saved Share OFF locally, while [MOTIVO/PublishService.swift:338](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/PublishService.swift:338>) launches the queued withdrawal without a durability result. Relaunch loads the older file at queue line 210, and upload takes `isPublic` from that old payload rather than reconciling it from the saved session.

**Observed probe:** create a real durable publish; make only the disposable parent directory unwritable; enqueue Unshare. Enqueue returned normally, memory said `unshare`, the previous bytes were unchanged, and decoding the actual file still yielded `publish`. Permissions were restored after the check. No real user queue or network was used. [queue-result.txt](</Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/claude-phase-6-evidence/queue-result.txt>)

**Consequence:** the next process can publish again despite a saved withdrawal, or lose a newly queued withdrawal altogether. The direct successful unshare accepted on 16 September did not test this path. Atomic file replacement prevents torn writes; it does not make a failed replacement successful.

**Existing IDs:** C-61/C-87 are related durability/order protections, not this disk-error case. This is not a recurrence of the old stale-acknowledgement race.

**Smallest remedy:** make persistence success part of enqueue's contract and propagate a failure that the save/publish flow can act on. Preserve an authoritative pending withdrawal or visibly report that it was not secured; reconcile stale durable publish intents against saved current intent on recovery. Do not silently roll back the memory state to Publish as a “fix”. Validate failed replacement, relaunch, offline retry, and failed dequeue persistence. Batch with P6-I-02 but test the mechanisms separately.

### P6-I-04 · P2 · Opening Lists overwrites an unreadable library

**Classification:** confirmed defect, reproduced. **Confidence: high.**

**Trigger:** the current owner's v2 Lists value exists but has invalid JSON, a wrong stored type or an unsupported future shape.

**Call chain:** the adoption API deliberately throws `damagedLibrary` in [MOTIVO/SavedList.swift:114](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/SavedList.swift:114>). However, the normal screen uses a separate loader at [MOTIVO/TasksManagerView.swift:1063](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/TasksManagerView.swift:1063>). Its two `try?` decodes at line 1128 fall through; line 1151 unconditionally writes the accumulated legacy merge, including `[]`, over the unreadable v2 value. Merely loading the screen destroys the original bytes. Some legacy templates might be recovered, but adopted copies are deliberately not mirrored there.

**Observed probe:** the exact screen loader, with an isolated defaults suite and no legacy keys, replaced damaged bytes with `[]`. The SavedListLibrary reader correctly refused the same bytes; a valid-library control remained intact. [list-result.txt](</Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/claude-phase-6-evidence/list-result.txt>)

**Existing IDs:** new; not the accepted duplicate-adoption behavior or C-5. `ConnectedListAdoptionTests.testUnreadableLibraryIsNeverOverwritten` tests only the adoption API, so its passing result does not protect this screen path.

**Smallest remedy:** use one throwing read/migration path for both callers. Distinguish absent from unreadable; preserve bytes and show a recoverable error, preventing edits from overwriting the damaged state. Validate valid/legacy/corrupt/wrong-type values through the actual screen loader, including an adopted list with no legacy mirror.

### P6-I-05 · P2 · An old attestation completion can undo a coordinator reset

**Classification:** confirmed coordination defect, reproduced under forced overlap. **Confidence: high for state corruption; real interaction frequency unmeasured.**

**Trigger:** reset while attestation A is suspended; B starts; A subsequently returns, including by cancellation handling.

**Call chain:** [MOTIVO/MembershipAttestationCoordinator.swift:136](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/MembershipAttestationCoordinator.swift:136>) cancels and clears the slot, but the awaiting owner at line 116 has no task-identity/generation check. It unconditionally sets `inFlight = nil`, `isAttesting = false` and `lastOutcome = outcome` at lines 117–119. Reset is reachable from the app's identity-withdrawal observer, [MOTIVO/MOTIVOApp.swift:422](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/MOTIVOApp.swift:422>). Cancellation is not proof that the awaiting owner cannot resume; the service also converts request errors into an ordinary outcome.

**Observed probe:** unchanged coordinator with a continuation-controlled service: A suspended → reset → B suspended → finish A. While B was still pending, `isAttesting` became false and `lastOutcome` was A's. A third forced call entered the service, giving three invocations before B completed. [coordinator-result.txt](</Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/claude-phase-6-evidence/coordinator-result.txt>)

**Consequence:** stale diagnostic state and broken single-flight ownership across an identity reset. This does **not** establish a membership-authority bypass, account binding error, token resurrection, or a device-visible wrong alert. Those stronger claims are not made.

**Existing IDs:** separate from C-55 (redundant publication loop), C-23 (StoreKit refresh ownership), and C-98 (auth refresh ownership).

**Smallest remedy:** generation/task ownership guard before publishing or clearing the slot; invalidate ownership on reset. Test A→reset, A→reset→B, cancelled late completion, and concurrent forced callers. Preserve server authority and in-memory-only cooldown.

## 3. Findings not promoted to new defects

- **C-97 remains a fault-recovery gap.** [MOTIVO/VideoRecorderView.swift:1616](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/VideoRecorderView.swift:1616>) registers AVAudioSession interruption and route notifications. Thus “no interruption handling” is too broad. The absent capture-session runtime-error/session-interruption and media-services-reset recovery, plus missing-audio detection, remain the appropriate target. QA7 gives ordinary first-video/input evidence, not induced-fault evidence. No new P1 recording failure is inferred.
- **C-96 automatic recovery remains unexplained, not refuted.** [MOTIVO/DroneEngine.swift:247](</Users/samueldixon/Documents/Xcode projects/MOTIVO_B/MOTIVO/MOTIVO/DroneEngine.swift:247>) invalidates on relevant configuration/reset events; route handling is conditional on output identity/engine state. Only two source `start` calls were found, both user controls in DroneControlStripCard. A USB input event need not take the same path as an output/configuration change. Framework recovery within the existing run is a possible explanation, not a measurement. Keep Samuel's automatic-recovery observation and the historical explicit-restart design separate until a trace/binary provenance resolves them. No loop was reproduced; the equality guard remains optional defensive work.
- **Send response-loss ambiguity:** upload allocates a fresh asset; delivery POST has no client-supplied delivery ID. A committed send followed by a lost response and a new Send action may create a separate delivery. Existing UNIQUE(asset_id, recipient) protects one asset, not a new upload. This is a **risk requiring a focused lost-response check**, not a claim that accepted duplicate Save is broken. Check the actual share-sheet retry behavior before assigning severity or changing product semantics.
- **C-99 residuals remain open.** The refs lock protects read/modify/write, not same-ID file/index transactions, destination allocation or main-thread I/O latency. No real-interaction overlap frequency was measured here; do not relabel all staging concurrency “fixed”.
- **C-3 remains a measured performance concern**, not a new memory-loss allegation. In-memory staged Data and synchronous work still merit a separately measured scope, but the earlier device result must not be replaced by simulator speculation.

## 4. Carried findings and release position

| Existing issue | Independent disposition in this pass |
|---|---|
| C-87, C-88, C-90, C-91, C-98 | Current protections present; do not reopen their original mechanisms. New findings concern neighboring boundaries. Prior local/device evidence retains its original limits |
| C-89 | Prior local fix stands; no new device closure inferred merely from the brief's grouped QA acceptance |
| C-92/C-94/C-95 | QA7 supersedes historical “USB open” statements for the accepted cases; no regression evidence found here |
| C-96 | QA8 accepted; equality guard and mechanism/provenance question remain separate |
| C-97 | Part 1 has device evidence; narrower fault-handling gap remains open |
| C-99 | Partly fixed; R-a…R-f remain open, as explicitly recorded |
| C-61 | Ordinary entitled unshare device path accepted; later queued convergence/disk-failure coverage not established. P6-I-03 is additional |
| C-65/C-73/C-76/C-82 | Later implementations supersede several old state cells. Do not count stale state labels as outstanding original defects. Missing-file selection, permanent errors, retry cost and scoped device acceptance need their individual dispositions; this audit does not close them en bloc |
| C-52/C-53 | Current shared Run = Release, no StoreKit config. Built simulator app contains no Etudes.storekit or debug_upload_test asset; device-bundle verification not rerun |
| C-17/C-54 | “Empty/unrunnable test suite” is historical. There are 68 unit-test Swift files; that is an inventory, not a count of executed tests |
| C-12 | Source reachability supports dead-code cleanup: deletion handler is referenced only by an alert whose private show flag is never set. Not a reachable new deletion defect |
| C-15 | Unscoped, unreclaimed PDF page-selection metadata remains a cleanup candidate; UUID keys and full defaults reset limit claims. No cross-account disclosure established |
| C-22 | Current Release build confirms deprecation debt; severity remains P3 unless a concrete runtime consequence is demonstrated |
| C-4 | Backup inclusion policy remains; misleading `ScoreLibraryStore.excludeFromBackup` actually calls `BackupPolicy.include` and is naming cleanup, not a new exclusion bug |
| B-39 | Revoked status check present in current source/snapshot and deployment record. No fresh Apple or live verification here |
| B-40 | Teen false predicate present in helper and both mirrors; direct preference writer does not bypass the effective gate. Current invitations do not authorise weakening it |
| B-41/B-42, C-100/C-101 | Existing repair records stand; not rerun and not rediscovered as new defects |
| B-37/B-38 | Directory enumeration/product controls and own-avatar-version privilege remain bounded P3 work, not new findings |
| B-34, G7, C-31, B-11 Gate 6 part 3 | Keep owned obligations. This audit supplies no first naturally matured cleanup, Production Billing Grace or first Production subscription evidence |
| C-102/C-103 | Feed observations/hypothesis remain unassigned pending exact device ownership/routing evidence; no device inspected |

**Phase position:** Phase 3's closure does not make all release obligations complete. Phase 4's exit assessment still distinguishes the accepted owner-side share/unshare run from production U2s authenticated rejected-write evidence, publication and formal exit scoring. Phase 5 legal/DPIA/children's privacy and publication conditions are not discharged by the new device passes. The legal questions being committed does not show counsel delivery or approval. This report offers no legal opinion.

**Launch configuration:** the decision register records Production ASSN URL/environment allowlist as a separate gated sequence. The function's code default remains Sandbox. No live environment settings were read, so the September record is not asserted to be today's measured configuration. Confirm allowlist and URL in the authorised release unit. Preserve Production Billing Grace and real-subscription grant checks separately.

## 5. Proposed batches — no implementation authorised here

| Order | Bounded scope | Dependencies and validation | Decision |
|---|---|---|---|
| A | P6-I-01, both local attachment commit callers | Fault-inject first/nth media write and Core Data save; verify originals, retry, rollback and normal save in both editors; Release build | Agree this correctness unit before deprecation cleanup |
| B | P6-I-02 + P6-I-03, queue ownership and durable intent | Define legacy ownerless handling; isolated A→B→A tests, failed disk writes and relaunch, older in-flight completion, unshare preservation; local RLS positive/negative controls | Samuel decides ambiguous legacy intent disposition. Never silently discard withdrawals |
| C | P6-I-04, one Lists reader/migration contract | Corrupt/wrong-type/legacy/valid values; adopted copies; actual screen loading; preserve accepted duplicate Save | Small client-only unit |
| D | P6-I-05, attestation completion ownership | Forced reset overlap and ordinary coalescing; preserve cooldown and server authority | Small client-only unit; no backend delta |
| E | Phase 6 subtraction/naming and AVFoundation batches | C-12, backup-helper naming, page metadata policy, demonstrably unused code only; deprecations one subsystem at a time, preserve first-video audio timing; warning comparison | No bulk modernisation. Any metadata collection behavior needs explicit scope |
| F | Remaining QA/release gates | C-97 induced faults; provenance reconciliation; Lists Ensemble/deletion/re-adoption; queued unshare and U2s evidence; legal/publication and launch config | Separate device/legal/production authorisations; do not repeat accepted QA without regression reason |

A and B are my release-blocking recommendations because they can lose local recordings or contradict privacy intent. C and D are important correctness repairs. F includes existing external release gates; this audit does not invent approval or declare them closed. No batch requires changing the settled membership architecture.

## 6. Verification record and reproducibility

**Release build:** Xcode 26.6, build 17F113. Command, from the repository:

```sh
xcodebuild -project MOTIVO.xcodeproj -scheme MOTIVO -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/etudes-phase6-audit-derived \
  -clonedSourcePackagesDirPath /private/tmp/etudes-phase6-cached-packages \
  -disableAutomaticPackageResolution -skipPackageUpdates build
```

Result: **BUILD SUCCEEDED, zero errors, 155 warning emissions**: 154 app emissions (77 unique exact file/line diagnostics, all deprecations, emitted for two architectures), plus one App Intents metadata-extraction warning. Do not compare raw 155 against an older warning count as if toolchain, architecture and counting rules were identical. [release-build.log](</Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/claude-phase-6-evidence/release-build.log>) and [build-warning-summary.txt](</Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/claude-phase-6-evidence/build-warning-summary.txt>)

Initial isolated package resolution could not reach GitHub. A copy-on-write copy of the existing Xcode SourcePackages cache was used; package updates were disabled. The first cached attempt was denied compiler-cache writes by the sandbox. The same build then succeeded with reviewed execution access. No package/source change or user confirmation was needed. These were environment failures, not application compile failures.

**Four probe executables:** Foundation/Combine/Core Data macOS harnesses, compiled with `swiftc -module-cache-path /private/tmp/etudes-phase6-audit/swift-cache -parse-as-library <source pair> -o <executable>`. Source pairs: `Queue.swift QueueProbe.swift`; `SavedList.swift ListProbe.swift`; `Coordinator.swift CoordinatorProbe.swift`; `CommitProbe.swift ProbeStaging.swift`. Exact sources and outputs are in the accompanying evidence directory. Filesystem roots/defaults suites were disposable. The commit harness has a harmless unused-variable warning introduced by its root substitution; it is not an app-build diagnostic.

- Queue: current implementation with only Combine import/output-root adaptation; service is a stub. Real failed disk write retained old bytes; account transition consequence is source-traced beyond the stub.
- Lists: exact loader with defaults injection, identity normalization for the fixture and empty legacy-key inventory. Valid control passed. No claim that arbitrary malformed data is commonly generated by the current app.
- Coordinator: actual class, controlled service continuations ignoring cancellation to force late completion. Demonstrates an allowed completion ordering, not its device frequency.
- Commit: actual timer-review commit function, minimal in-memory model, metadata helpers stubbed, deterministic throwing writer; actual StagingStore removal with isolated root. The caller's save/cleanup sequence was reproduced; full SwiftUI interaction and real low-disk condition were not.

`python3 scripts/c14-discriminator.py` ran read-only: targeted identifier arguments 0, retained events 8, shipping identifier-pattern hits 0, declared ownerKey exclusions 2. This is the limited existing logging guard, **not a complete secret/content leakage scan**. [c14-result.txt](</Users/samueldixon/Documents/Codex/2026-09-17/pl/outputs/claude-phase-6-evidence/c14-result.txt>)

No full unit target, Debug build, populated migration, local backend suite/reset, live schema check, real StoreKit flow or physical-device QA was run. Existing accepted evidence is cited with its original limitations, not represented as rerun. No automated dependency advisory review was performed. Review depth was prioritized, not exhaustive across all 176 app Swift files.

**Stop point:** reports complete; comparison and any implementation await Samuel. Repository state and dirty-file hashes are unchanged.
