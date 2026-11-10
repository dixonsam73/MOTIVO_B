# Private iCloud sync — production configuration

Written 2026-11-04 for the internal TestFlight trial of the private sync on
the shipping configuration (Release, bundle `com.sdsongs.etudes`). **State
2026-11-10:** the App ID capabilities and the schema in Production are done
(sections 2 and 4), and the Release enablement patch is applied (section
3). Not done: any TestFlight upload, and anything in App Store Connect. The
trial configuration (SyncTest, bundle `com.samueldixon.motivo.synctest`,
development container `iCloud.com.samueldixon.motivo.synctest`) is
unchanged and stays the trial's.

Sync stays **off by default** with explicit opt-in on every configuration.

## 1. What is already in the repo (commit of this document)

- **The container identifier is a build setting**, `ETUDES_CLOUDKIT_CONTAINER`,
  carried into the bundle as the Info.plist key `EtudesCloudKitContainer`
  (both `Info.plist` and `Info-SyncTest.plist` hold
  `$(ETUDES_CLOUDKIT_CONTAINER)`; Xcode expands it at build time).
  `JournalSyncCapability.containerIdentifier` reads it; `buildSupportsSync`
  is "the identifier is set". Only the SyncTest app configuration sets it
  (to the trial container). Debug and Release leave it unset, so the key
  expands to "" and those builds never offer the control and never build an
  engine — exactly as before, now with one mechanism instead of a compile
  flag. `SyncOffByDefaultTests.testDebugAndReleaseCarryNoCloudKitContainerOrPush`
  checks, from `project.pbxproj` and the entitlements files, that a
  configuration which sets the identifier carries the matching entitlements,
  push and `remote-notification`, and that one which does not carries none
  of them; and, from the running bundle, that the build resolved the
  expected identifier.
- `docs/sync-trial/production-configuration.patch`: the Release enablement as
  a patch (section 3). **Applied 2026-11-10** in one commit, after the App
  ID and schema steps; the file is kept as the record of exactly what
  enablement is (reverse it with `git apply -R` only with section 3's
  warning about withdrawing the capability in mind).

## 2. Apple Developer and App Store Connect (Samuel)

In [developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list)
for the App ID `com.sdsongs.etudes`:

1. **iCloud** → tick, select **CloudKit** (Include CloudKit support), and
   under Containers create a **new** container `iCloud.com.sdsongs.etudes`
   and assign it. Do not assign the trial container.
2. **Push Notifications** → tick. No APNs key is needed: CloudKit sends the
   silent pushes for the app's own database subscription
   (`etudes-journal-app-wake`) itself.
3. Save. With automatic signing, Xcode regenerates the provisioning
   profiles on the next build; nothing to download.

Verify: the App ID page lists iCloud (CloudKit, 1 container) and Push
Notifications as enabled; [icloud.developer.apple.com](https://icloud.developer.apple.com)
lists `iCloud.com.sdsongs.etudes` with empty Development and Production
environments.

App Store Connect needs **no change for the trial**: TestFlight builds use
the container's **Production** environment, which is why the schema must be
deployed (section 4) before the first TestFlight build is opened with sync
on. The privacy labels and the policy text are a separate item (section 6).

## 3. The Release entitlements, Info.plist and build setting (patch)

`docs/sync-trial/production-configuration.patch` does exactly this:

- New file `MOTIVO/MOTIVO-Release.entitlements`: `MOTIVO.entitlements` plus
  `aps-environment` (`development` in the source; App Store and TestFlight
  signing rewrites it to `production`), the container
  `iCloud.com.sdsongs.etudes` under `com.apple.developer.icloud-container-identifiers`,
  and `CloudKit` under `com.apple.developer.icloud-services`. Release gets
  its own file because Debug shares `MOTIVO.entitlements` and must stay
  without iCloud or push (its App ID has neither).
- `MOTIVO/Info.plist`: `remote-notification` added to `UIBackgroundModes`
  (shared with Debug, where it is inert: nothing registers for pushes
  without an engine).
- `MOTIVO.xcodeproj/project.pbxproj`, Release configuration of the app
  target only: `CODE_SIGN_ENTITLEMENTS = MOTIVO/MOTIVO-Release.entitlements;`
  and `ETUDES_CLOUDKIT_CONTAINER = iCloud.com.sdsongs.etudes;`.

Apply with:

```bash
git apply --check docs/sync-trial/production-configuration.patch && git apply docs/sync-trial/production-configuration.patch
```

Then build Release once (`xcodebuild … -configuration Release build`) and run
`SyncOffByDefaultTests` in Debug and in SyncTest: the guard test's "set"
branch must pass for Release and the "unset" branch for Debug. A device
build of Release (Xcode, Device A) must sign without a provisioning error —
that is the proof the App ID step took.

**Recommendation on Release's flag (one line):** flip it **at the TestFlight
checkpoint, by applying this patch in one commit**, not now — the identifier,
the entitlements and the background mode must land together (an engine built
without the entitlement fails at the first CloudKit call), the guard test
enforces exactly that pairing, and until the schema is in Production a
Release build that could sync would meet an empty container.

**Withdrawing the capability is not a free rollback.** Removing the
`ETUDES_CLOUDKIT_CONTAINER` line from the Release configuration makes
Release build no engine again and hides the Profile section; a person who
had turned sync on keeps their journal and their state file. The hazard
(Codex, 2026-11-05; C-181) is the sequence *synced install → capability
withdrawn → the person erases the journal ("Remove Études Data" / Delete
Account) → a later build restores the capability*: the erase's batch
deletes are in persistent history, and a build that can sync reads history
from the state file's token. Protected since `C-181`: the coordinator opens
the state store for the erase bracket even when the build cannot sync, so
the erase is recorded as a local removal (marker before the first row goes,
history token fast-forwarded past the deletes, server knowledge forgotten,
sync off until re-enabled) and a later capable build queues nothing from
it. `SyncOffByDefaultTests.testEraseAfterCapabilityWithdrawnIsRecordedAsLocalRemovalNotCloudDeletion`
runs in every configuration, and continues through the set-up screen that
follows: a build that cannot sync offers no "Restore from iCloud", and its
`reenable` builds no engine (C-182). Local-only deletion never becomes
cloud deletion. If the capability is withdrawn for good, the person's iCloud copy
stays until they remove it from iCloud themselves (the policy says so).

## 4. The CloudKit schema for the production container

The engine never queries (no `CKQuery`): it fetches zone changes, records by
id and database changes, so no field needs an index for the app to work.
Production refuses just-in-time schema, so every record type and field the
engine writes must exist there before a Production build sends anything.
The trial's development container holds every record TYPE (each was written
by the populated upgrade trial) but **not necessarily every field**: the
Development environment creates a field only when a non-nil value is saved,
and a journal that never held some optional value leaves that field out
(C-184, below). So the export is checked against the code with
`docs/sync-trial/check_schema.py`, the gaps are added by hand in the new
container's Development environment, and only then is the schema deployed
to Production in the Console (`cktool` has no deploy command).

**Done 2026-11-10 (Samuel, checked by Codex and by `check_schema.py`).**
App ID `com.sdsongs.etudes`: iCloud/CloudKit with only
`iCloud.com.sdsongs.etudes` assigned, and Push Notifications. Management
token in the Keychain (team `K352DG4UJA`). The trial export
(`etudes-journal-schema.ckdb`, sha256 `59985fc7…`) lacked three fields the
code writes — `Session.userInstrumentLabel`, `Session.userActivityLabel`
and `Score.sourceAttachmentID`, all STRING: the trial journal has no custom
instrument or activity label on a session and no score made from an
attachment, so no non-nil value was ever saved. They were added in the new
container's Development environment (no index; the engine never queries)
and the corrected schema deployed to Production. The corrected Development
export (`etudes-journal-schema-prod-dev.ckdb`) and the Production export
(`etudes-journal-schema-prod.ckdb`) are byte-for-byte identical (sha256
`6a67d77f…`), and `check_schema.py` reports 15 record types, 73 fields, 0
gaps on both and exactly those three gaps on the original. The Production
export is the schema of record; the three files are on Samuel's Desktop.
The trial container itself still lacks the three fields in its schema,
which is harmless there (Development creates them on first use).

Expected record types and fields, derived from `JournalRecordMapping`,
`JournalMetadataSync`, `JournalProfileSync`, `JournalScoreSync`,
`JournalSettingsSync` and `JournalSavedListSync` (zone `Journal`, private
database; record names as noted):

| Record type | Record name | Fields (CloudKit type) |
|---|---|---|
| `Session` | `<uuid>` | title, notes, activityDetail, threadLabel, userInstrumentLabel, userActivityLabel, ownerUserID, instrumentName: STRING · timestamp, userModifiedAt: TIMESTAMP · durationSeconds, activityType, mood, effort, areNotesPrivate, isPublic, isSaved: INT64 · instrumentRef: REFERENCE |
| `Attachment` | `<uuid>` | kind, fileExt, fileHash: STRING · createdAt, userModifiedAt: TIMESTAMP · session: REFERENCE · file: ASSET · (legacy, written by pre-stage-G builds and still read: displayName, selectedPages: STRING · isThumbnail, isPrivate: INT64) |
| `AttachmentMeta` | `<uuid>-meta` | displayName, selectedPages: STRING · isThumbnail, isPrivate: INT64 · userModifiedAt: TIMESTAMP |
| `Instrument` | `<uuid>` | name: STRING |
| `UserInstrument` | `<uuid>` | displayName, normalizedName, instrumentName: STRING · displayOrder, isVisibleOnProfile: INT64 · instrumentRef: REFERENCE |
| `UserActivity` | `<uuid>` | displayName, normalizedName: STRING · coreActivityCode: INT64 |
| `SavedList` | `<uuid>` | name: STRING · items: BYTES |
| `Profile` | `profile` | name, location, instrumentName: STRING · instrumentRef: REFERENCE · userModifiedAt: TIMESTAMP |
| `ProfileAvatar` | `profile-avatar` | file: ASSET · fileHash: STRING · userModifiedAt: TIMESTAMP |
| `Score` | `score-<uuid>` | file: ASSET · fileHash, fileExt, fileName, sourceAttachmentID, initialTitle: STRING · pageCount: INT64 · createdAt: TIMESTAMP |
| `ScoreMeta` | `score-<uuid>-meta` | title: STRING · isFavourite, thumbnailPage: INT64 · userModifiedAt: TIMESTAMP |
| `ScorePosition` | `score-<uuid>-position` | lastViewedPage: INT64 · userModifiedAt: TIMESTAMP |
| `Setting` | `setting-<key>` | value: STRING · userModifiedAt: TIMESTAMP |
| `ListContext` | `listctx-<hash>` | activityRef, instrumentName, defaultListID: STRING · autofill: INT64 · preset: BYTES · userModifiedAt: TIMESTAMP |
| `TintMap` | `tint-instrument` | map: BYTES |

Not schema: the zone `Journal` (created per user by the engine's
`saveZone`) and the database subscription `etudes-journal-app-wake` (saved
per user at the first activation; a `CKDatabaseSubscription` needs no
record type). Both work in Production without preparation.

Steps (Samuel; each with what to verify):

1. **A management token.** CloudKit Console → the trial container →
   Settings (gear) → Tokens → *Create management token*; copy it. Then

   ```bash
   xcrun cktool save-token --type management --method keychain
   ```

   (paste at the prompt). Verify: `xcrun cktool get-teams` lists team
   `K352DG4UJA`.

2. **Export the trial container's development schema.**

   ```bash
   xcrun cktool export-schema --team-id K352DG4UJA --container-id iCloud.com.samueldixon.motivo.synctest --environment development --output-file ~/Desktop/etudes-journal-schema.ckdb
   ```

   Verify: open the file; it must contain `RECORD TYPE` blocks for every
   type in the table above, with the fields listed (names and types). Fields
   the table does not list are fine (the development environment also
   recorded anything an earlier trial build wrote). Do not check by eye:

   ```bash
   python3 docs/sync-trial/check_schema.py ~/Desktop/etudes-journal-schema.ckdb
   ```

   Each GAP it prints is a field the code writes that no trial record ever
   carried a value for; add it in the new container's Development
   environment (step 3) before deploying, and run the checker again on the
   Production export (step 4), which must report 0 gaps.

3. **Validate, then import into the new container's Development environment.**

   ```bash
   xcrun cktool validate-schema --team-id K352DG4UJA --container-id iCloud.com.sdsongs.etudes --environment development --file ~/Desktop/etudes-journal-schema.ckdb
   ```

   ```bash
   xcrun cktool import-schema --team-id K352DG4UJA --container-id iCloud.com.sdsongs.etudes --environment development --validate --file ~/Desktop/etudes-journal-schema.ckdb
   ```

   Verify by exporting it back and comparing:

   ```bash
   xcrun cktool export-schema --team-id K352DG4UJA --container-id iCloud.com.sdsongs.etudes --environment development --output-file ~/Desktop/etudes-journal-schema-prod-dev.ckdb
   ```

   ```bash
   diff ~/Desktop/etudes-journal-schema.ckdb ~/Desktop/etudes-journal-schema-prod-dev.ckdb
   ```

   An empty diff (or only ordering) is the pass.

4. **Deploy to Production** in the CloudKit Console: container
   `iCloud.com.sdsongs.etudes` → Schema → *Deploy Schema Changes…* → review
   the list (every type above, no deletions) → Deploy. Verify: with the
   environment switch set to **Production**, the Schema page lists the
   record types; and

   ```bash
   xcrun cktool export-schema --team-id K352DG4UJA --container-id iCloud.com.sdsongs.etudes --environment production --output-file ~/Desktop/etudes-journal-schema-prod.ckdb
   ```

   matches the development export apart from ordering.

5. **A production build must now be able to write.** The TestFlight
   checkpoint's first "turn sync on" is that proof; the Console cannot read
   a user's private database, so the evidence is the app's status line
   reaching "Up to date" and a second device restoring the journal. The
   Console's *Telemetry* (Production) shows request counts and errors per
   record type: a schema mismatch shows there as `BAD_REQUEST` on the type.

Later schema changes follow the same path: Development first (the app
creates them just in time there), export, import, deploy. A field's type can
never change once deployed, and a deployed field cannot be removed.

## 5. Order of operations for the checkpoint

1. Section 2 (App ID), then section 4 steps 1–4 (schema in Production).
2. Apply the patch (section 3), commit on `feature/solo-connected`, build
   Release for Device A from that commit (development-signed: it talks to
   the container's **Development** environment — the right place for the
   first populated run with cable evidence). The populated runs use the
   **Release fixture** `~/Documents/Xcode projects/EtudesRelease-upgrade-fixture-2026-11-05`
   (the 2026-11-04 fixture with its preferences as
   `Library/Preferences/com.sdsongs.etudes.plist`, the Release bundle's
   domain; verified: 112 sessions, 83 attachments, 102 files, 7 scores,
   nothing missing), loaded with
   `load_container_copy.sh <udid> <fixture> com.sdsongs.etudes`, pulled
   with `pull_container_copy.sh <udid> <dest> com.sdsongs.etudes`, and
   compared with `compare_containers.py <fixture> <copy> --reference-plist
   com.sdsongs.etudes.plist --candidate-plist com.sdsongs.etudes.plist
   --role upgraded|receiver` — both plist arguments explicit, since the
   script's defaults are the trial's.
3. Archive the same commit and upload to TestFlight (Production environment).
4. Run the checkpoint script (`RELEASE.md`, "TestFlight checkpoint for the
   private sync"; the numbered device script is in the session notes).

## 6. Still Samuel's, outside this document

- Privacy policy and terms wording (`docs/sync-trial/policy-drafts-icloud-sync.md`).
- App Store privacy labels: whether data the app stores only in the person's
  own iCloud private database counts as "collected" under Apple's App
  Privacy Details — Apple's published FAQ should settle it before the labels
  are touched; nothing in the labels changes for this internal trial.
- The `os.Logger` subsystem for sync is still `com.samueldixon.motivo.synctest`
  on every configuration (cosmetic; filter Console on category `JournalSync`).
