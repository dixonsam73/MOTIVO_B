//
//  SyncTestPopulatedEnableTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  C-197: turning sync on on a device that already holds the journal iCloud
//  holds (two devices restored from one backup, sync then turned on on both).
//  Assessed 2026-11-13 (`91cd021`, where these tests pinned the faults) and
//  corrected the same day; the tests now assert the corrected behaviour.
//
//  The rule (Samuel, 2026-11-13): the two journals are COMBINED. Entries only
//  one side holds are kept. Where both hold an entry and no trustworthy edit
//  order exists, the cloud copy stands and this device's version is kept
//  whole, to read back and restore. Nothing is erased to turn sync on. An
//  entry deleted on only one side before sync was on can come back, because
//  no record of the deletion survives.
//
//  The device is a temporary store with synthetic rows and a bootstrap
//  (`JournalChangeTracker.bootstrapIfNeeded`, what `activate` runs first).
//  iCloud is records built from those rows. Both orders a conflict can be met
//  in are driven through the engine's own paths:
//    fetch first → the zone arrives while the save is pending
//                  (`applyFetchedBatch`); the order the hold now enforces at
//                  the first activation;
//    send first  → the save is rejected (serverRecordChanged) and the engine
//                  calls `JournalImporter.resolveSendConflict` or
//                  `applyDeferredSendConflict`; still the order of an
//                  ordinary conflict later on.
//  The CloudKit calls themselves (`activate`, `sendChanges`, the zone read)
//  are not reachable in a test; the decisions they act on are.
//

#if SYNCTEST
import XCTest
import CoreData
import CloudKit
@testable import Etudes

final class SyncTestPopulatedEnableTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var store: JournalSyncStateStore!
    private var tempDir: URL!
    private var tracker: JournalChangeTracker!
    private var queues: [Step0Queue] = []
    private var defaults: UserDefaults!
    private var suiteName: String!
    /// Files a test put in the host's Documents or Application Support.
    private var cleanup: [URL] = []
    /// The clock both copies of an untouched row carry (one backup, two devices).
    private let backupClock = Date(timeIntervalSince1970: 1_760_000_000)

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-c197-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        container = NSPersistentContainer(name: "MOTIVO")
        let description = NSPersistentStoreDescription(url: tempDir.appendingPathComponent("store.sqlite"))
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        try XCTUnwrap(loadError == nil ? () : nil, "store failed to load: \(String(describing: loadError))")
        container.viewContext.transactionAuthor = JournalSyncAuthor.app
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("state"), withIntermediateDirectories: true)
        store = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("state/state.json"))
        tracker = JournalChangeTracker(container: container, store: store)
        suiteName = "synctest-c197-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        JournalUserEditStamp.installOnce()   // as every launch does, sync on or off
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.appendingPathComponent("state").path)
        for url in cleanup { try? FileManager.default.removeItem(at: url) }
        defaults.removePersistentDomain(forName: suiteName)
        queues.removeAll()
        container = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: helpers

    /// An engine as the coordinator builds it, never started (no CloudKit traffic).
    @MainActor
    private func makeEngine() -> JournalSyncEngine {
        let engine = JournalSyncEngine(containerIdentifier: JournalSyncCoordinator.containerIdentifier, persistence: container,
                                       store: store, status: JournalSyncStatus(), customOwner: nil)
        engine.importer.log = { [store] in store?.log($0) }
        engine.importer.changeTag = { $0["testTag"] as? String }
        store.update { $0.boundUserRecordName = "_user" }
        engine.assumeCurrentUserForTesting("_user")
        engine.holdMediaForTesting(.lowDataMode)   // a batch never ends in a CloudKit release here
        return engine
    }

    private func importer() -> (JournalImporter, NSManagedObjectContext) {
        let ctx = container.newBackgroundContext()
        ctx.name = "syncImport"; ctx.transactionAuthor = JournalSyncAuthor.sync
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy; ctx.stalenessInterval = 0
        let q = Step0Queue(store: store)
        queues.append(q)
        let imp = JournalImporter(context: ctx, store: store, customOwner: nil)
        imp.queue = q
        imp.log = { [store] in store?.log($0) }
        imp.changeTag = { $0["testTag"] as? String }
        return (imp, ctx)
    }

    /// A row as the store held it before sync was turned on, with the clock
    /// given (nil = never stamped). Written by a `sync`-author context so no
    /// observer, installed or not, can move the clock.
    @discardableResult
    private func seedSession(_ id: UUID = UUID(), title: String, notes: String, duration: Int64 = 600, clock: Date?) throws -> UUID {
        let ctx = container.newBackgroundContext(); ctx.transactionAuthor = JournalSyncAuthor.sync
        var failure: Error?
        ctx.performAndWait {
            let s = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
            s.setValue(id, forKey: "id"); s.setValue(title, forKey: "title"); s.setValue(notes, forKey: "notes")
            s.setValue(Date(timeIntervalSince1970: 1_750_000_000), forKey: "timestamp")
            s.setValue(duration, forKey: "durationSeconds"); s.setValue(clock, forKey: "userModifiedAt")
            do { try ctx.save() } catch { failure = error }
        }
        if let failure { throw failure }
        return id
    }

    @discardableResult
    private func seedAttachment(_ id: UUID = UUID(), session: UUID, file: URL, name: String, clock: Date?) throws -> UUID {
        let ctx = container.newBackgroundContext(); ctx.transactionAuthor = JournalSyncAuthor.sync
        var failure: Error?
        ctx.performAndWait {
            let r = NSFetchRequest<NSManagedObject>(entityName: "Session"); r.predicate = NSPredicate(format: "id == %@", session as CVarArg)
            let a = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: ctx)
            a.setValue(id, forKey: "id"); a.setValue("image", forKey: "kind"); a.setValue(name, forKey: "displayName")
            a.setValue(Date(timeIntervalSince1970: 1_750_000_100), forKey: "createdAt")
            a.setValue(file.path, forKey: "fileURL"); a.setValue(clock, forKey: "userModifiedAt")
            a.setValue((try? ctx.fetch(r))?.first, forKey: "session")
            do { try ctx.save() } catch { failure = error }
        }
        if let failure { throw failure }
        return id
    }

    private func file(_ name: String, _ text: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private enum Copy { case session, attachment(hash: String), meta }

    /// The record iCloud holds for a row: what the other device, restored from
    /// the same backup, uploaded. Built from the row as it is NOW, so call it
    /// before any local edit the test makes.
    private func cloudCopy(_ kind: Copy, _ id: UUID, tag: String) throws -> CKRecord {
        let ctx = container.newBackgroundContext()
        var record: CKRecord?
        ctx.performAndWait {
            let entity: String
            if case .session = kind { entity = "Session" } else { entity = "Attachment" }
            let r = NSFetchRequest<NSManagedObject>(entityName: entity); r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            guard let row = (try? ctx.fetch(r))?.first else { return }
            switch kind {
            case .session:
                record = JournalRecordMapping.record(for: row, base: nil)
            case .attachment(let hash):
                // As the records-only catch-up delivers it: the hash, no file.
                record = JournalRecordMapping.record(for: row, base: nil, includeAsset: false)
                record?[JournalRecordMapping.fileExtKey] = "jpg" as CKRecordValue
                record?[JournalRecordMapping.fileHashKey] = hash as CKRecordValue
            case .meta:
                record = JournalRecordMapping.metaRecord(for: row, base: nil)
            }
        }
        let out = try XCTUnwrap(record)
        out["testTag"] = tag as CKRecordValue
        return out
    }

    private func value(_ entity: String, _ id: UUID, _ key: String) -> Any? {
        let ctx = container.newBackgroundContext(); var out: Any?
        ctx.performAndWait {
            let r = NSFetchRequest<NSManagedObject>(entityName: entity); r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            out = (try? ctx.fetch(r))?.first?.value(forKey: key)
        }
        return out
    }

    private func exists(_ entity: String, _ id: UUID) -> Bool { value(entity, id, "id") != nil }
    private func pendingSave(_ name: String) -> JournalSyncPendingChange? { store.state.outbox.first { $0.recordName == name && $0.op == .save } }

    /// A value as a build before this one left it: changed with no clock moved.
    private func setUnclocked(_ entity: String, _ id: UUID, _ values: [String: Any?]) throws {
        let ctx = container.newBackgroundContext(); ctx.transactionAuthor = JournalSyncAuthor.sync
        var failure: Error?
        ctx.performAndWait {
            let r = NSFetchRequest<NSManagedObject>(entityName: entity); r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            guard let row = (try? ctx.fetch(r))?.first else { failure = NSError(domain: "test", code: 1); return }
            for (key, value) in values { row.setValue(value, forKey: key) }
            do { try ctx.save() } catch { failure = error }
        }
        if let failure { throw failure }
    }

    @MainActor
    private func firstFetch(_ engine: JournalSyncEngine, _ zone: [CKRecord], deleted: [(CKRecord.ID, CKRecord.RecordType)] = []) async -> Bool {
        await engine.applyFetchedBatch(modified: zone, deleted: deleted, newToken: nil, assetsFetched: zone.filter { $0[JournalRecordMapping.assetKey] != nil }.count,
                                       generation: engine.generationForTesting(), reason: "first fetch", writeFailuresBefore: store.writeFailures)
    }

    /// The person edits a row in the app: an ordinary save in the view context.
    private func editInApp(_ id: UUID, _ body: (NSManagedObject) -> Void) throws {
        let ctx = container.viewContext
        let r = NSFetchRequest<NSManagedObject>(entityName: "Session"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let row = try XCTUnwrap(try ctx.fetch(r).first)
        body(row)
        try ctx.save()
    }

    // MARK: 1. Every local edit has a clock, sync on or off

    /// The clock that decides a conflict is now kept from launch, with no
    /// state file and no engine. An edit made with sync off therefore beats an
    /// older cloud copy when sync is turned on, and the cloud's text is kept.
    @MainActor
    func testAnEditMadeWithSyncOffIsClockedSoItIsKeptOverAnOlderCloudCopy() throws {
        let stateURL = tempDir.appendingPathComponent("never-on/JournalSyncState.json")
        let coordinator = JournalSyncCoordinator(stateFileURL: stateURL)
        XCTAssertFalse(coordinator.startIfNeeded(persistence: container), "sync is off: nothing is started")
        defer { JournalMetadataMirror.container = nil }
        XCTAssertNil(coordinator.engine); XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))

        let sid = try seedSession(title: "Scales", notes: "as in the backup", duration: 600, clock: backupClock)
        let cloud = try cloudCopy(.session, sid, tag: "s1")
        try editInApp(sid) { $0.setValue("rewritten here, sync off", forKey: "notes"); $0.setValue(Int64(1800), forKey: "durationSeconds") }
        let clock = try XCTUnwrap(value("Session", sid, "userModifiedAt") as? Date, "the edit is clocked although sync is off")
        XCTAssertGreaterThan(clock, backupClock)

        tracker.bootstrapIfNeeded()   // sync is turned on
        let (imp, ictx) = importer()
        var imported = JournalImporter.Summary()
        ictx.performAndWait { imported = imp.importModifications([cloud]) }
        XCTAssertEqual(imported.received, 0, "the older cloud copy is not applied")
        XCTAssertEqual(value("Session", sid, "notes") as? String, "rewritten here, sync off")
        XCTAssertEqual(value("Session", sid, "durationSeconds") as? Int64, 1800)
        XCTAssertNotNil(pendingSave(sid.uuidString), "and the edit goes up")
        XCTAssertEqual(JournalRecovery.entries(store: store).first?.displaced["Notes (other device)"], "as in the backup")
    }

    // MARK: 2. Nothing is sent before the first fetch is applied

    /// The hold, and the first device ever: with no zone token of ours and no
    /// Journal zone, iCloud holds no journal. That is a complete answer, so
    /// the hold lifts and this device's send can create the zone.
    @MainActor
    func testNothingIsSentBeforeTheFirstFetchIsAppliedAndAnAbsentZoneCountsAsFetched() async throws {
        try seedSession(title: "Scales", notes: "slow", clock: backupClock)
        tracker.bootstrapIfNeeded()
        let engine = makeEngine()
        XCTAssertEqual(engine.sendDecision(), .heldForFirstFetch)
        let sent = await engine.performSend(userDriven: true, trigger: "test")
        XCTAssertFalse(sent, "a send asked for now does not run")
        XCTAssertTrue(store.state.log.contains { $0.text.hasPrefix("Nothing is sent until iCloud has been read once") })

        let next = await engine.catchUpFailed(code: .zoneNotFound, description: "Zone does not exist", hadZoneToken: false,
                                              generation: engine.generationForTesting(), reason: "first fetch", writeFailuresBefore: store.writeFailures)
        XCTAssertEqual(next, .settled(true))
        XCTAssertTrue(store.state.initialFetchComplete, "iCloud holds no journal: the first fetch is complete, with nothing in it")
        XCTAssertEqual(engine.sendDecision(), .noEngine, "the hold has lifted (this test has no CloudKit engine to send with)")
        XCTAssertEqual(store.state.outbox.count, 1, "and the journal still waits to go up")
        XCTAssertFalse(store.state.lastCatchUp?.contains("failed") ?? true, "an absent zone is not shown as a failed check")
    }

    /// A read that failed, a batch applied in part, and a zone that vanished
    /// after this device had a token all leave the hold in place.
    @MainActor
    func testAFailedOrIncompleteFirstFetchDoesNotReleaseTheHold() async throws {
        let sid = try seedSession(title: "Scales", notes: "slow", clock: backupClock)
        let cloud = try cloudCopy(.session, sid, tag: "s1")
        tracker.bootstrapIfNeeded()
        let engine = makeEngine()
        let generation = engine.generationForTesting()

        var next = await engine.catchUpFailed(code: .networkFailure, description: "offline", hadZoneToken: false,
                                              generation: generation, reason: "first fetch", writeFailuresBefore: store.writeFailures)
        XCTAssertEqual(next, .settled(true), "tried again later")
        XCTAssertEqual(engine.sendDecision(), .heldForFirstFetch)
        XCTAssertEqual(store.state.lastCatchUp, "Delta catch-up failed: offline")

        next = await engine.catchUpFailed(code: .changeTokenExpired, description: "expired", hadZoneToken: false,
                                          generation: generation, reason: "first fetch", writeFailuresBefore: store.writeFailures)
        XCTAssertEqual(engine.sendDecision(), .heldForFirstFetch)
        next = await engine.catchUpFailed(code: .zoneNotFound, description: "Zone does not exist", hadZoneToken: true,
                                          generation: generation, reason: "poll", writeFailuresBefore: store.writeFailures)
        XCTAssertEqual(next, .settled(false), "a zone this device had read before and no longer finds is not an empty first fetch")
        XCTAssertEqual(engine.sendDecision(), .heldForFirstFetch)

        // The zone is read but the batch cannot be recorded: applied in part.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: tempDir.appendingPathComponent("state").path)
        var complete = await firstFetch(engine, [cloud])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.appendingPathComponent("state").path)
        XCTAssertFalse(complete)
        XCTAssertEqual(engine.sendDecision(), .heldForFirstFetch, "an incomplete fetch releases nothing")

        complete = await firstFetch(engine, [cloud])
        XCTAssertTrue(complete)
        XCTAssertEqual(engine.sendDecision(), .noEngine, "the complete one does")
    }

    /// Everything the device holds is queued before anything is fetched, and
    /// the device knows no server copy and no server file hash, so a save
    /// built at that moment would carry every file (the engine asks the rule
    /// at JournalSyncEngine.swift, `record(for:)`). The hold is what stops it.
    @MainActor
    func testTheFirstBootstrapQueuesEveryRowAndKnowsNothingOfTheServerWhichIsWhyTheSendWaits() throws {
        let photo = try file("photo.jpg", "jpeg bytes")
        let sid = try seedSession(title: "Scales", notes: "slow", clock: backupClock)
        let aid = try seedAttachment(session: sid, file: photo, name: "take 1", clock: backupClock)
        XCTAssertEqual(tracker.bootstrapIfNeeded(), 3, "the session, the attachment and its metadata record")
        let st = store.state
        XCTAssertTrue(st.lastKnownRecords.isEmpty, "no server copy is known")
        XCTAssertTrue(st.assetHashes.isEmpty, "no server file is known")
        let localHash = try XCTUnwrap(JournalAssetHash.hash(of: photo))
        XCTAssertTrue(JournalAssetPolicy.includeAsset(hasServerCopy: st.lastKnownRecords[aid.uuidString] != nil,
                                                      serverHash: st.assetHashes[aid.uuidString], localHash: localHash,
                                                      assetFree: pendingSave(aid.uuidString)?.assetFree ?? false),
                      "a save built now would carry the file, although iCloud may hold the same bytes")
        XCTAssertEqual(makeEngine().sendDecision(), .heldForFirstFetch)
    }

    // MARK: 3. Identical records

    /// The journal iCloud holds is the journal here. The first fetch settles
    /// every pending save, learns each file's hash without the file, uploads
    /// nothing and writes no conflict entry.
    @MainActor
    func testIdenticalRecordsAreSettledByTheFirstFetchWithNoUploadAndNoConflictEntry() async throws {
        let photo = try file("photo.jpg", "jpeg bytes")
        let hash = try XCTUnwrap(JournalAssetHash.hash(of: photo))
        let sid = try seedSession(title: "Scales", notes: "slow", clock: backupClock)
        let aid = try seedAttachment(session: sid, file: photo, name: "take 1", clock: backupClock)
        let cloud = [try cloudCopy(.session, sid, tag: "s1"), try cloudCopy(.attachment(hash: hash), aid, tag: "a1"), try cloudCopy(.meta, aid, tag: "m1")]
        tracker.bootstrapIfNeeded()
        let engine = makeEngine()
        let complete = await firstFetch(engine, cloud)
        XCTAssertTrue(complete); XCTAssertTrue(store.state.initialFetchComplete)
        XCTAssertTrue(store.state.outbox.isEmpty, "every pending save was settled by the cloud copy, so nothing is uploaded")
        XCTAssertEqual(store.state.assetHashes[aid.uuidString], hash, "the same bytes: the server's hash is recorded for the file here")
        XCTAssertEqual(value("Attachment", aid, "fileURL") as? String, photo.path)
        XCTAssertEqual(value("Attachment", aid, "displayName") as? String, "take 1")
        XCTAssertTrue(store.state.conflicts.isEmpty, "nothing differed, so nothing is recorded as displaced")
    }

    /// The same by the other path (a save rejected because the server already
    /// holds the record): no entry, nothing sent again.
    func testIdenticalRecordsMetByARejectedSaveLeaveNoConflictEntryEither() throws {
        let photo = try file("photo.jpg", "jpeg bytes")
        let hash = try XCTUnwrap(JournalAssetHash.hash(of: photo))
        let sid = try seedSession(title: "Scales", notes: "slow", clock: backupClock)
        let aid = try seedAttachment(session: sid, file: photo, name: "take 1", clock: backupClock)
        let meta = JournalSyncRecordType.metaName(for: aid.uuidString)
        let cloud = [try cloudCopy(.session, sid, tag: "s1"), try cloudCopy(.attachment(hash: hash), aid, tag: "a1"), try cloudCopy(.meta, aid, tag: "m1")]
        tracker.bootstrapIfNeeded()
        let (imp, ictx) = importer()
        var resends: [Bool] = []
        ictx.performAndWait {
            resends.append(imp.resolveSendConflict(recordType: "Session", recordName: sid.uuidString, server: cloud[0]))
            resends.append(imp.resolveSendConflict(recordType: "Attachment", recordName: aid.uuidString, server: cloud[1]))
            resends.append(imp.resolveSendConflict(recordType: JournalSyncRecordType.attachmentMeta, recordName: meta, server: cloud[2]))
        }
        XCTAssertEqual(resends, [false, false, false])
        XCTAssertTrue(store.state.outbox.isEmpty)
        XCTAssertTrue(store.state.conflicts.isEmpty, "an attachment's name is not compared with a record that carries no name")
        XCTAssertEqual(value("Attachment", aid, "displayName") as? String, "take 1")
    }

    // MARK: 4. Divergent edits with no trustworthy order

    /// An edit made before this build has no clock, and a new clock cannot
    /// say which of two old edits came first. The cloud copy stands (ties go
    /// to the server), and this device's version is kept WHOLE: the text to
    /// read, the other fields by name, and a Restore that puts all of it back
    /// as a new edit. The same whichever path meets the conflict.
    @MainActor
    func testAnUnclockedEditThatLosesToTheCloudCopyIsKeptWholeAndCanBeRestored() async throws {
        let byFetch = try seedSession(title: "Scales", notes: "as in the backup", duration: 600, clock: nil)
        let byRejectedSave = try seedSession(title: "Arpeggios", notes: "as in the backup", duration: 600, clock: nil)
        let cloud = [try cloudCopy(.session, byFetch, tag: "s1"), try cloudCopy(.session, byRejectedSave, tag: "s2")]
        for id in [byFetch, byRejectedSave] {
            try setUnclocked("Session", id, ["notes": "rewritten here after the backup", "durationSeconds": Int64(1800), "mood": Int16(9)])
        }
        tracker.bootstrapIfNeeded()
        let engine = makeEngine()
        let complete = await firstFetch(engine, [cloud[0]])
        XCTAssertTrue(complete)
        let (imp, ictx) = importer()
        var resend = true
        ictx.performAndWait { resend = imp.resolveSendConflict(recordType: "Session", recordName: byRejectedSave.uuidString, server: cloud[1]) }
        XCTAssertFalse(resend)

        let shown = JournalRecovery.entries(store: store)
        XCTAssertEqual(shown.count, 2)
        for id in [byFetch, byRejectedSave] {
            XCTAssertEqual(value("Session", id, "notes") as? String, "as in the backup", "the cloud copy stands")
            XCTAssertEqual(value("Session", id, "durationSeconds") as? Int64, 600)
            let entry = try XCTUnwrap(shown.first { $0.recordName == id.uuidString })
            XCTAssertEqual(entry.displaced, ["Notes (this device)": "rewritten here after the backup", "Other details (this device)": "Duration, Mood"],
                           "every field that lost is named, not only the text")
            XCTAssertEqual(JournalRecovery.restore(entry, store: store, context: container.viewContext), .restored("Restored the whole entry as a new edit"))
            container.viewContext.refreshAllObjects()
            XCTAssertEqual(value("Session", id, "notes") as? String, "rewritten here after the backup")
            XCTAssertEqual(value("Session", id, "durationSeconds") as? Int64, 1800, "the duration comes back with the text")
            XCTAssertEqual(value("Session", id, "mood") as? Int16, 9)
            XCTAssertNotNil(value("Session", id, "userModifiedAt"), "and the restore is a clocked edit")
        }
        XCTAssertTrue(JournalRecovery.entries(store: store).isEmpty, "a restored entry leaves the list")
        XCTAssertEqual(Set(tracker.processHistory().map(\.recordName)), [byFetch.uuidString, byRejectedSave.uuidString], "both restores are queued to go up")
    }

    /// With a clock on both sides the newer edit is kept whichever side made
    /// it, and the losing text is readable.
    @MainActor
    func testDivergentEditsThatBothCarryAClockKeepTheNewerAndTheLosingTextIsReadable() throws {
        let localNewer = try seedSession(title: "Scales", notes: "written here", clock: backupClock.addingTimeInterval(600))
        let cloudNewer = try seedSession(title: "Arpeggios", notes: "written here", clock: backupClock)
        let older = try cloudCopy(.session, localNewer, tag: "s1")
        older["notes"] = "written on the other device" as CKRecordValue; older["userModifiedAt"] = backupClock as CKRecordValue
        let newer = try cloudCopy(.session, cloudNewer, tag: "s2")
        newer["notes"] = "written on the other device" as CKRecordValue; newer["userModifiedAt"] = backupClock.addingTimeInterval(600) as CKRecordValue
        tracker.bootstrapIfNeeded()
        let (imp, ictx) = importer()
        var resends: [Bool] = []
        ictx.performAndWait {
            resends.append(imp.resolveSendConflict(recordType: "Session", recordName: localNewer.uuidString, server: older))
            resends.append(imp.resolveSendConflict(recordType: "Session", recordName: cloudNewer.uuidString, server: newer))
        }
        XCTAssertEqual(resends, [true, false])
        XCTAssertEqual(value("Session", localNewer, "notes") as? String, "written here")
        XCTAssertNotNil(store.state.lastKnownRecords[localNewer.uuidString], "the resend goes on top of the server's change tag")
        XCTAssertEqual(value("Session", cloudNewer, "notes") as? String, "written on the other device")
        let shown = JournalRecovery.entries(store: store)
        XCTAssertEqual(Set(shown.flatMap { $0.displaced.keys }), ["Notes (other device)", "Notes (this device)"])
    }

    /// What counts as a difference: only fields the record type carries, and
    /// a side-store choice only when both records state it.
    func testOnlyFieldsBothRecordsCanStateAreComparedAndIdenticalOnesAreNoDifference() {
        func session(_ fill: (CKRecord) -> Void) -> CKRecord {
            let r = CKRecord(recordType: "Session", recordID: JournalRecordMapping.recordID(for: UUID()))
            r["title"] = "Scales" as CKRecordValue; r["timestamp"] = backupClock as CKRecordValue; r["durationSeconds"] = 600 as CKRecordValue
            fill(r); return r
        }
        let plain = session { _ in }
        XCTAssertEqual(JournalRecordMapping.differingContentKeys(local: plain, server: session { $0["notes"] = "" as CKRecordValue; $0["userModifiedAt"] = Date() as CKRecordValue; $0["ownerUserID"] = "owner" as CKRecordValue }), [],
                       "an empty text, the clock and the owner are not content")
        XCTAssertEqual(JournalRecordMapping.differingContentKeys(local: plain, server: session { $0["timestamp"] = backupClock.addingTimeInterval(0.0004) as CKRecordValue }), [],
                       "a date that differs by less than a millisecond is the same date")
        XCTAssertEqual(JournalRecordMapping.differingContentKeys(local: plain, server: session { $0[JournalMetadataKeys.isSaved] = 1 as CKRecordValue }), [],
                       "a favourite only one record states is no information")
        XCTAssertEqual(JournalRecordMapping.differingContentKeys(local: session { $0[JournalMetadataKeys.isSaved] = 0 as CKRecordValue },
                                                                 server: session { $0[JournalMetadataKeys.isSaved] = 1 as CKRecordValue; $0["durationSeconds"] = 1800 as CKRecordValue }).map(JournalRecordMapping.fieldLabel),
                       ["Duration", "Favourite"])
        let content = CKRecord(recordType: "Attachment", recordID: JournalRecordMapping.recordID(for: UUID()))
        content["kind"] = "audio" as CKRecordValue
        let named = CKRecord(recordType: "Attachment", recordID: content.recordID)
        named["kind"] = "audio" as CKRecordValue; named["displayName"] = "take 1" as CKRecordValue
        XCTAssertEqual(JournalRecordMapping.differingContentKeys(local: named, server: content), [], "a name is not compared with a record that carries none")
    }

    /// A custom activity has no clock: iCloud's name stands, and the name it
    /// replaces here is listed instead of vanishing.
    @MainActor
    func testACustomRowRenamedOnBothSidesKeepsTheCloudNameAndListsTheOneItReplaced() throws {
        let id = UUID()
        let ctx = container.newBackgroundContext(); ctx.transactionAuthor = JournalSyncAuthor.sync
        ctx.performAndWait {
            let row = NSEntityDescription.insertNewObject(forEntityName: "UserActivity", into: ctx)
            row.setValue(id, forKey: "id"); row.setValue("Sight-reading (mine)", forKey: "displayName")
            row.setValue(PersistenceController.normalized("Sight-reading (mine)"), forKey: "normalizedName"); row.setValue("k2-test", forKey: "ownerUserID")
            row.setValue(Int16(0), forKey: "coreActivityCode")
            do { try ctx.save() } catch { XCTFail("seed failed: \(error)") }
        }
        XCTAssertEqual(value("UserActivity", id, "displayName") as? String, "Sight-reading (mine)", "precondition: the row is here")
        store.update { JournalChangeTracker.merge([.init(recordName: id.uuidString, recordType: JournalSyncRecordType.userActivity, op: .save)], into: &$0) }
        let cloud = CKRecord(recordType: JournalSyncRecordType.userActivity, recordID: JournalRecordMapping.recordID(for: id))
        cloud["displayName"] = "Sight reading" as CKRecordValue; cloud["normalizedName"] = PersistenceController.normalized("Sight reading") as CKRecordValue
        let ictx = container.newBackgroundContext(); ictx.transactionAuthor = JournalSyncAuthor.sync
        let q = Step0Queue(store: store); queues.append(q)
        let imp = JournalImporter(context: ictx, store: store, customOwner: "k2-test"); imp.queue = q
        ictx.performAndWait { _ = imp.importModifications([cloud]) }
        XCTAssertEqual(value("UserActivity", id, "displayName") as? String, "Sight reading")
        let entry = try XCTUnwrap(JournalRecovery.entries(store: store).first, "conflicts: \(store.state.conflicts.map(\.displaced)) log: \(store.state.log.suffix(4).map(\.text))")
        XCTAssertEqual(entry.subject, "Activity"); XCTAssertEqual(entry.displaced, ["Name (this device)": "Sight-reading (mine)"])
    }

    // MARK: 5. A different file for the same attachment

    /// The other device replaced a recording after the backup. This device
    /// holds the old bytes and has never exchanged a hash. The cloud's file is
    /// put in place and its hash recorded for THOSE bytes; the old bytes are
    /// kept and listed, and Restore puts them back as a new edit.
    @MainActor
    func testADifferentCloudFileReplacesTheLocalOneWhoseBytesAreKeptAndCanBeRestored() async throws {
        let old = try file("recording.jpg", "the take as the backup held it")
        let trimmed = try file("trimmed.jpg", "the trimmed take")
        let oldHash = try XCTUnwrap(JournalAssetHash.hash(of: old)), trimmedHash = try XCTUnwrap(JournalAssetHash.hash(of: trimmed))
        let sid = try seedSession(title: "Recording", notes: "", clock: backupClock)
        let aid = try seedAttachment(session: sid, file: old, name: "take 1", clock: backupClock)
        let destination = JournalRecordMapping.materialisedURL(recordName: aid.uuidString, ext: "jpg")
        let kept = JournalImporter.displacedMediaDirectory().appendingPathComponent("\(aid.uuidString)-\(oldHash.prefix(12)).jpg")
        cleanup += [destination, kept]
        let recordsOnly = try cloudCopy(.attachment(hash: trimmedHash), aid, tag: "a2")
        recordsOnly["userModifiedAt"] = backupClock.addingTimeInterval(600) as CKRecordValue
        tracker.bootstrapIfNeeded()
        let engine = makeEngine()

        // The record without its file: nothing is applied and nothing is relabelled.
        let complete = await firstFetch(engine, [try cloudCopy(.session, sid, tag: "s1"), recordsOnly])
        XCTAssertTrue(complete, "the batch is complete: the record waits by name")
        XCTAssertEqual(store.state.awaitingMedia, [aid.uuidString])
        XCTAssertNil(store.state.assetHashes[aid.uuidString], "old bytes are never recorded under the cloud file's hash")
        XCTAssertEqual(value("Attachment", aid, "fileURL") as? String, old.path)
        XCTAssertNotNil(pendingSave(aid.uuidString), "and this device's copy is still pending, not dropped")

        // With its file (the release, or a catch-up that fetched it).
        let withFile = try cloudCopy(.attachment(hash: trimmedHash), aid, tag: "a2")
        withFile["userModifiedAt"] = backupClock.addingTimeInterval(600) as CKRecordValue
        withFile[JournalRecordMapping.assetKey] = CKAsset(fileURL: trimmed)
        let released = await engine.applyReleasedMedia(full: [withFile], gone: [], generation: engine.generationForTesting())
        XCTAssertEqual(released, [aid.uuidString])
        XCTAssertEqual(value("Attachment", aid, "fileURL") as? String, destination.path)
        XCTAssertEqual(try Data(contentsOf: destination), Data("the trimmed take".utf8), "the cloud's file is in place")
        XCTAssertEqual(store.state.assetHashes[aid.uuidString], JournalAssetHash.hash(of: destination), "and the recorded hash is the hash of the bytes here")
        XCTAssertEqual(try Data(contentsOf: kept), Data("the take as the backup held it".utf8), "this device's bytes are kept")
        XCTAssertNil(pendingSave(aid.uuidString))

        let entry = try XCTUnwrap(JournalRecovery.entries(store: store).first { $0.restore?.hasPrefix("media:") == true })
        XCTAssertEqual(entry.recordName, aid.uuidString)
        XCTAssertEqual(JournalRecovery.restore(entry, store: store, context: container.viewContext), .restored("Restored the file as a new edit"))
        let restoredPath = try XCTUnwrap(value("Attachment", aid, "fileURL") as? String)
        cleanup.append(URL(fileURLWithPath: restoredPath))
        XCTAssertNotEqual(restoredPath, destination.path, "a new file name, so the change travels with its file")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: restoredPath)), Data("the take as the backup held it".utf8))
        XCTAssertTrue(tracker.processHistory().contains { $0.recordName == aid.uuidString && $0.op == .save && !$0.assetFree },
                      "queued as a content change, which carries the file")
    }

    // MARK: 6. Entries only one side holds

    /// The journals are combined. An entry only iCloud holds arrives here; an
    /// entry only this device holds stays and goes up. That includes an entry
    /// deleted on the other device before sync was on, when the zone read
    /// brings no record of the deletion: nothing can tell it from an entry
    /// that was simply never uploaded, so it returns on every device. The
    /// person is told so where sync is turned on.
    @MainActor
    func testEntriesOnlyOneSideHoldsAreKeptSoADeletionThatLeftNoRecordComesBack() async throws {
        let kept = try seedSession(title: "Kept on both", notes: "", clock: backupClock)
        let deletedElsewhere = try seedSession(title: "Deleted on the other device", notes: "", clock: backupClock)
        let cloudOnly = UUID()
        let fromCloud = CKRecord(recordType: "Session", recordID: JournalRecordMapping.recordID(for: cloudOnly))
        fromCloud["title"] = "Only in iCloud" as CKRecordValue; fromCloud["timestamp"] = backupClock as CKRecordValue
        fromCloud["userModifiedAt"] = backupClock as CKRecordValue; fromCloud["testTag"] = "s9" as CKRecordValue
        tracker.bootstrapIfNeeded()
        let engine = makeEngine()
        let complete = await firstFetch(engine, [try cloudCopy(.session, kept, tag: "s1"), fromCloud])
        XCTAssertTrue(complete)
        XCTAssertNil(pendingSave(kept.uuidString), "the entry both hold is settled")
        XCTAssertTrue(exists("Session", cloudOnly), "an entry only iCloud holds arrives here")
        XCTAssertTrue(exists("Session", deletedElsewhere), "an entry only this device holds stays")
        XCTAssertNotNil(pendingSave(deletedElsewhere.uuidString), "and goes up once the fetch is applied")
        XCTAssertNil(store.state.lastKnownRecords[deletedElsewhere.uuidString])
        XCTAssertEqual(engine.sendDecision(), .noEngine, "the hold has lifted")
        XCTAssertTrue(store.state.conflicts.isEmpty)
    }

    /// Where the read does carry a deletion (the Production zone returned
    /// three to a fresh read on 2026-11-13), the hold guarantees it is applied
    /// before anything is sent: the entry goes from this device and nothing of
    /// it is uploaded.
    @MainActor
    func testADeletionTheFirstFetchCarriesIsAppliedBeforeAnythingIsSent() async throws {
        let photo = try file("photo.jpg", "jpeg bytes")
        let kept = try seedSession(title: "Kept on both", notes: "", clock: backupClock)
        let deletedElsewhere = try seedSession(title: "Deleted on the other device", notes: "", clock: backupClock)
        let aid = try seedAttachment(session: deletedElsewhere, file: photo, name: "take 1", clock: backupClock)
        let meta = JournalSyncRecordType.metaName(for: aid.uuidString)
        tracker.bootstrapIfNeeded()
        XCTAssertEqual(store.state.outbox.count, 4)
        let engine = makeEngine()
        XCTAssertEqual(engine.sendDecision(), .heldForFirstFetch, "nothing has left this device yet")
        let tombstones: [(CKRecord.ID, CKRecord.RecordType)] = [
            (JournalRecordMapping.recordID(for: deletedElsewhere), "Session"), (JournalRecordMapping.recordID(for: aid), "Attachment"),
            (CKRecord.ID(recordName: meta, zoneID: JournalRecordMapping.zoneID), JournalSyncRecordType.attachmentMeta)]
        let complete = await firstFetch(engine, [try cloudCopy(.session, kept, tag: "s1")], deleted: tombstones)
        XCTAssertTrue(complete)
        XCTAssertFalse(exists("Session", deletedElsewhere)); XCTAssertFalse(exists("Attachment", aid))
        XCTAssertTrue(exists("Session", kept))
        XCTAssertTrue(store.state.outbox.isEmpty, "nothing of the deleted entry is uploaded")
        XCTAssertTrue(FileManager.default.fileExists(atPath: photo.path), "a file outside Documents is never removed by a remote deletion")
    }

    // MARK: 7. Saved Lists: one result whichever arrives first

    /// A list both devices hold, changed on each, with no clock to order
    /// them. Whether the cloud copy arrives by the fetch or as the answer to
    /// this device's rejected save, the cloud's lines take the list and this
    /// device's are kept as a list of their own, which is then sent.
    @MainActor
    func testAListChangedOnBothSidesEndsTheSameWhicheverArrivesFirstAndTheLocalLinesAreKeptAsTheirOwnList() async throws {
        let scope = JournalSavedListSync.currentScope()
        let engine = makeEngine()
        defer {
            if let current = try? SavedListLibrary.read(ownerScope: scope) {
                try? SavedListLibrary.commit(snapshot: current, updated: current.filter { !$0.name.hasPrefix("C197 ") }, ownerScope: scope)
            }
        }
        func outcome(_ label: String, meet: (CKRecord, UUID) async -> Void) async throws -> [String: [String]] {
            let id = UUID()
            let name = "C197 \(label) \(id.uuidString.prefix(6))"
            let before = try SavedListLibrary.read(ownerScope: scope)
            try SavedListLibrary.commit(snapshot: before, updated: before + [SavedList(id: id, name: name, items: [SavedListLine(text: "edited on this device")])], ownerScope: scope)
            store.update { JournalChangeTracker.merge([.init(recordName: id.uuidString, recordType: JournalSyncRecordType.savedList, op: .save)], into: &$0) }
            let cloud = try XCTUnwrap(JournalRecordMapping.record(for: SavedList(id: id, name: name, items: [SavedListLine(text: "edited on the other device")]), base: nil))
            await meet(cloud, id)
            XCTAssertNil(pendingSave(id.uuidString), "\(label): the save of the list itself is settled")
            let lists = try SavedListLibrary.read(ownerScope: scope).filter { $0.name.hasPrefix(name) }
            XCTAssertEqual(lists.first { $0.id == id }?.items.map(\.text), ["edited on the other device"], "\(label): iCloud's lines take the list")
            return Dictionary(uniqueKeysWithValues: lists.map { ($0.name.replacingOccurrences(of: name, with: "list"), $0.items.map(\.text)) })
        }
        let fetchFirst = try await outcome("fetch") { cloud, _ in _ = await self.firstFetch(engine, [cloud]) }
        let sendFirst = try await outcome("send") { cloud, id in
            await engine.applyDeferredSendConflict(server: cloud, recordID: JournalRecordMapping.recordID(for: id), generation: engine.generationForTesting())
        }
        XCTAssertEqual(fetchFirst, sendFirst, "the same result by either order")
        XCTAssertEqual(fetchFirst, ["list": ["edited on the other device"], "list (kept from this device)": ["edited on this device"]],
                       "and this device's lines are kept as a list of their own")
        let keptIDs = try SavedListLibrary.read(ownerScope: scope).filter { $0.name.hasPrefix("C197 ") && $0.name.hasSuffix("(kept from this device)") }.map(\.id.uuidString)
        XCTAssertEqual(keptIDs.count, 2)
        let queued = Set(JournalSavedListSync.scan(store: store).filter { $0.op == .save }.map(\.recordName))
        XCTAssertTrue(queued.isSuperset(of: keptIDs), "the kept lists are new lists, sent to every device")
    }

    /// Two things that are not a conflict: the same lines on both sides, and
    /// this device's own accepted write coming back while a later edit waits.
    @MainActor
    func testAnIdenticalListOrThisDevicesOwnWriteComingBackKeepsNoCopy() throws {
        let scope = "device"
        let id = UUID()
        let local = SavedList(id: id, name: "Warm-up", items: [SavedListLine(text: "long tones")])
        try SavedListLibrary.commit(snapshot: [], updated: [local], ownerScope: scope, defaults: defaults)
        XCTAssertEqual(JournalSavedListSync.scan(store: store, defaults: defaults, scope: scope).count, 1)
        let same = try XCTUnwrap(JournalRecordMapping.record(for: local, base: nil))
        XCTAssertEqual(JournalSavedListSync.apply([same], store: store, defaults: defaults, scope: scope), 1)
        XCTAssertEqual(try SavedListLibrary.read(ownerScope: scope, defaults: defaults).count, 1, "the same lines: no copy")
        XCTAssertNil(pendingSave(id.uuidString), "and nothing is sent")

        // This device's write was accepted with tag "t1"; the person edits again; the catch-up hands "t1" back.
        store.update { $0.knownChangeTags[id.uuidString] = "t1" }
        var edited = local; edited.items = [SavedListLine(text: "long tones, then scales")]
        try SavedListLibrary.commit(snapshot: [local], updated: [edited], ownerScope: scope, defaults: defaults)
        XCTAssertEqual(JournalSavedListSync.scan(store: store, defaults: defaults, scope: scope).count, 1)
        XCTAssertEqual(JournalSavedListSync.apply([same], store: store, defaults: defaults, scope: scope, changeTag: { _ in "t1" }), 0)
        let after = try SavedListLibrary.read(ownerScope: scope, defaults: defaults)
        XCTAssertEqual(after.map { $0.items.map(\.text) }, [["long tones, then scales"]], "the later edit stands and no copy is made")
        XCTAssertNotNil(pendingSave(id.uuidString), "and still goes up")
    }

    // MARK: 8. Recovery: the whole losing version, through Restore

    /// A conflict on an attachment's METADATA record ("<id>-meta") restores to
    /// the attachment it belongs to, and puts back all four things the record
    /// carries: the name and the star on the row, the privacy choice and the
    /// page selection through their stores.
    @MainActor
    func testRestoringAMetadataConflictFindsItsAttachmentAndPutsBackNameStarPrivacyAndPages() throws {
        let sid = try seedSession(title: "Lesson", notes: "", clock: nil)
        let aid = try seedAttachment(session: sid, file: try file("score.jpg", "page images"), name: "bars 1 to 8 (mine)", clock: nil)
        let other = try seedAttachment(session: sid, file: try file("other.jpg", "jpeg bytes"), name: "other", clock: nil)
        let meta = JournalSyncRecordType.metaName(for: aid.uuidString)
        try setUnclocked("Attachment", aid, ["isThumbnail": true])
        AttachmentPrivacy.setPrivate(id: aid, url: nil, false, mirror: false)
        PDFSelectedPagesStore.setPages([2, 3], for: aid, mirror: false)
        defer { PDFSelectedPagesStore.setPages(nil, for: aid, mirror: false) }
        // What the other device made of the same attachment.
        let cloud = try cloudCopy(.meta, aid, tag: "m1")
        cloud["displayName"] = "theirs" as CKRecordValue; cloud["isThumbnail"] = 0 as CKRecordValue
        cloud[JournalMetadataKeys.isPrivate] = 1 as CKRecordValue; cloud[JournalMetadataKeys.selectedPages] = "[1]" as CKRecordValue
        tracker.bootstrapIfNeeded()
        let (imp, ictx) = importer()
        ictx.performAndWait { _ = imp.importModifications([cloud]) }
        XCTAssertEqual(value("Attachment", aid, "displayName") as? String, "theirs", "no order can be told: the cloud's metadata stands")
        XCTAssertEqual(value("Attachment", aid, "isThumbnail") as? Bool, false)
        XCTAssertTrue(AttachmentPrivacy.isPrivate(id: aid, url: nil)); XCTAssertEqual(PDFSelectedPagesStore.pages(for: aid), [1])
        try setUnclocked("Attachment", other, ["isThumbnail": true])   // meanwhile the star sits on the other attachment

        let entry = try XCTUnwrap(JournalRecovery.entries(store: store).first { $0.recordName == meta })
        let outcome = JournalRecovery.restore(entry, store: store, context: container.viewContext)
        guard case .restored = outcome else { return XCTFail("restore failed: \(outcome)") }
        XCTAssertEqual(value("Attachment", aid, "displayName") as? String, "bars 1 to 8 (mine)")
        XCTAssertEqual(value("Attachment", aid, "isThumbnail") as? Bool, true, "the star comes back")
        XCTAssertEqual(value("Attachment", other, "isThumbnail") as? Bool, false, "and stays the entry's only one")
        XCTAssertFalse(AttachmentPrivacy.isPrivate(id: aid, url: nil), "the privacy choice comes back")
        XCTAssertEqual(PDFSelectedPagesStore.pages(for: aid), [2, 3], "and the page selection")
        XCTAssertTrue(JournalRecovery.entries(store: store).isEmpty)
    }

    /// The losing edit CLEARED text. Nothing to read is not nothing to
    /// recover: the entry is listed, and Restore clears the text again.
    @MainActor
    func testAnEditThatClearedNotesOrANameIsStillListedAndRestoresAsCleared() throws {
        let sid = try seedSession(title: "Scales", notes: "notes the person then deleted", clock: nil)
        let aid = try seedAttachment(session: sid, file: try file("photo.jpg", "jpeg bytes"), name: "a name the person then removed", clock: nil)
        let meta = JournalSyncRecordType.metaName(for: aid.uuidString)
        let cloud = [try cloudCopy(.session, sid, tag: "s1"), try cloudCopy(.meta, aid, tag: "m1")]
        try setUnclocked("Session", sid, ["notes": ""])
        try setUnclocked("Attachment", aid, ["displayName": ""])
        tracker.bootstrapIfNeeded()
        let (imp, ictx) = importer()
        ictx.performAndWait { _ = imp.importModifications(cloud) }
        XCTAssertEqual(value("Session", sid, "notes") as? String, "notes the person then deleted", "the cloud copy stands")
        XCTAssertEqual(value("Attachment", aid, "displayName") as? String, "a name the person then removed")

        let shown = JournalRecovery.entries(store: store)
        XCTAssertEqual(Set(shown.map(\.recordName)), [sid.uuidString, meta], "both are listed although the losing text is empty")
        XCTAssertEqual(shown.first { $0.recordName == sid.uuidString }?.displaced, ["Notes (this device)": ""])
        for entry in shown {
            let outcome = JournalRecovery.restore(entry, store: store, context: container.viewContext)
            guard case .restored = outcome else { return XCTFail("restore failed: \(outcome)") }
        }
        XCTAssertEqual(value("Session", sid, "notes") as? String ?? "", "", "the notes are cleared again")
        XCTAssertEqual(value("Attachment", aid, "displayName") as? String ?? "", "", "and so is the name")
        XCTAssertEqual(value("Session", sid, "title") as? String, "Scales")
    }

    // MARK: 9. A deletion the first fetch carries, against content only this device holds

    /// An entry with a recording, in the host's Documents so a deletion really removes the file.
    private func seedEntryWithARecording() throws -> (session: UUID, attachment: UUID, file: URL, tombstones: [(CKRecord.ID, CKRecord.RecordType)]) {
        let sid = try seedSession(title: "Lesson with Anna", notes: "worked on bowing", duration: 2700, clock: nil)
        let recording = JournalRecordMapping.materialisedURL(recordName: "c197-test-\(UUID().uuidString)", ext: "jpg")
        try Data("the only copy of this recording".utf8).write(to: recording)
        cleanup.append(recording)
        let aid = try seedAttachment(session: sid, file: recording, name: "bowing exercise", clock: nil)
        try setUnclocked("Attachment", aid, ["isThumbnail": true])
        cleanup.append(JournalRecordMapping.materialisedURL(recordName: aid.uuidString, ext: "jpg"))
        let tombstones: [(CKRecord.ID, CKRecord.RecordType)] = [
            (JournalRecordMapping.recordID(for: aid), "Attachment"),   // the attachment first, as a batch may order it
            (CKRecord.ID(recordName: JournalSyncRecordType.metaName(for: aid.uuidString), zoneID: JournalRecordMapping.zoneID), JournalSyncRecordType.attachmentMeta),
            (JournalRecordMapping.recordID(for: sid), "Session")]
        return (sid, aid, recording, tombstones)
    }

    private func keptFiles(for attachment: UUID) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: JournalImporter.displacedMediaDirectory(), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(attachment.uuidString) }
    }

    /// The other device deleted an entry; this device still holds it, with a
    /// recording, and has sent none of it. The deletion is applied, but only
    /// after the entry, its attachment's details and the file's bytes are
    /// kept; Restore brings all of it back as a new entry that goes up.
    @MainActor
    func testADeletionInTheFirstFetchKeepsTheEntryAndItsRecordingAndRestoreBringsBothBack() async throws {
        let (sid, aid, recording, tombstones) = try seedEntryWithARecording()
        tracker.bootstrapIfNeeded()
        let engine = makeEngine()
        let complete = await firstFetch(engine, [], deleted: tombstones)
        defer { for url in keptFiles(for: aid) { try? FileManager.default.removeItem(at: url) } }
        XCTAssertTrue(complete)
        XCTAssertFalse(exists("Session", sid)); XCTAssertFalse(exists("Attachment", aid))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.path), "the deletion removed the file from the journal")
        XCTAssertTrue(store.state.outbox.isEmpty, "and nothing of the entry is uploaded")

        let shown = JournalRecovery.entries(store: store)
        XCTAssertEqual(shown.count, 1, "one entry for the deleted entry and its recording together")
        let entry = try XCTUnwrap(shown.first)
        XCTAssertEqual(entry.displaced["Notes (this device)"], "worked on bowing")
        XCTAssertEqual(keptFiles(for: aid).count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(keptFiles(for: aid).first)), Data("the only copy of this recording".utf8), "the bytes are kept")

        let outcome = JournalRecovery.restore(entry, store: store, context: container.viewContext)
        guard case .restored = outcome else { return XCTFail("restore failed: \(outcome)") }
        XCTAssertEqual(value("Session", sid, "title") as? String, "Lesson with Anna")
        XCTAssertEqual(value("Session", sid, "notes") as? String, "worked on bowing")
        XCTAssertEqual(value("Session", sid, "durationSeconds") as? Int64, 2700)
        XCTAssertEqual(value("Attachment", aid, "displayName") as? String, "bowing exercise")
        XCTAssertEqual(value("Attachment", aid, "isThumbnail") as? Bool, true)
        let restored = try XCTUnwrap(AttachmentPathResolver.resolve(value("Attachment", aid, "fileURL") as? String), "the attachment has its file again")
        cleanup.append(restored)
        XCTAssertEqual(try Data(contentsOf: restored), Data("the only copy of this recording".utf8), "with the same bytes")
        let queued = tracker.processHistory()
        XCTAssertTrue(queued.contains { $0.recordName == sid.uuidString && $0.op == .save })
        XCTAssertTrue(queued.contains { $0.recordName == aid.uuidString && $0.op == .save && !$0.assetFree }, "the recording goes up with its file")
        XCTAssertTrue(JournalRecovery.entries(store: store).isEmpty)
    }

    /// The other device deleted one recording from an entry both still hold.
    /// The attachment is kept on its own and Restore puts it back in its entry.
    @MainActor
    func testAnAttachmentDeletedOnItsOwnInTheFirstFetchIsKeptAndRestoredToItsEntry() async throws {
        let (sid, aid, recording, tombstones) = try seedEntryWithARecording()
        let cloudSession = try cloudCopy(.session, sid, tag: "s1")
        tracker.bootstrapIfNeeded()
        let engine = makeEngine()
        let complete = await firstFetch(engine, [cloudSession], deleted: tombstones.filter { $0.1 != "Session" })
        defer { for url in keptFiles(for: aid) { try? FileManager.default.removeItem(at: url) } }
        XCTAssertTrue(complete)
        XCTAssertTrue(exists("Session", sid)); XCTAssertFalse(exists("Attachment", aid))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.path))
        let entry = try XCTUnwrap(JournalRecovery.entries(store: store).first)
        XCTAssertEqual(entry.displaced["Name (this device)"], "bowing exercise")
        let outcome = JournalRecovery.restore(entry, store: store, context: container.viewContext)
        guard case .restored = outcome else { return XCTFail("restore failed: \(outcome)") }
        XCTAssertEqual(value("Attachment", aid, "displayName") as? String, "bowing exercise")
        XCTAssertEqual(value("Attachment", aid, "isThumbnail") as? Bool, true)
        let ctx = container.newBackgroundContext()
        var parent: UUID?
        ctx.performAndWait {
            let r = NSFetchRequest<NSManagedObject>(entityName: "Attachment"); r.predicate = NSPredicate(format: "id == %@", aid as CVarArg)
            parent = ((try? ctx.fetch(r))?.first?.value(forKey: "session") as? NSManagedObject)?.value(forKey: "id") as? UUID
        }
        XCTAssertEqual(parent, sid, "back in the entry it belonged to")
        let restored = try XCTUnwrap(AttachmentPathResolver.resolve(value("Attachment", aid, "fileURL") as? String))
        cleanup.append(restored)
        XCTAssertEqual(try Data(contentsOf: restored), Data("the only copy of this recording".utf8))
        XCTAssertTrue(keptFiles(for: aid).isEmpty, "the kept copy is used up")
    }

    /// Restore must never write over an attachment that is already there. The
    /// kept attachment's id has come back (here with different bytes): Restore
    /// stops, says so, and leaves the row, both files and the entry as they are.
    @MainActor
    func testRestoreStopsWhenAnAttachmentWithTheKeptIdAlreadyExistsAndKeepsBothFilesAndTheEntry() async throws {
        let (sid, aid, _, tombstones) = try seedEntryWithARecording()
        let cloudSession = try cloudCopy(.session, sid, tag: "s1")
        tracker.bootstrapIfNeeded()
        let engine = makeEngine()
        let complete = await firstFetch(engine, [cloudSession], deleted: tombstones.filter { $0.1 != "Session" })
        defer { for url in keptFiles(for: aid) { try? FileManager.default.removeItem(at: url) } }
        XCTAssertTrue(complete); XCTAssertFalse(exists("Attachment", aid))
        let kept = try XCTUnwrap(keptFiles(for: aid).first)
        // The same id is in the journal again, with other bytes, at the path a restore would write to.
        let present = JournalRecordMapping.materialisedURL(recordName: aid.uuidString, ext: "jpg")
        try Data("a different recording under the same id".utf8).write(to: present)
        try seedAttachment(aid, session: sid, file: present, name: "arrived since", clock: backupClock)

        let entry = try XCTUnwrap(JournalRecovery.entries(store: store).first)
        let outcome = JournalRecovery.restore(entry, store: store, context: container.viewContext)
        guard case .failed(let message) = outcome else { return XCTFail("restore must not report success: \(outcome)") }
        XCTAssertTrue(message.contains("already"), "the person is told why: \(message)")
        XCTAssertEqual(try Data(contentsOf: present), Data("a different recording under the same id".utf8), "the attachment that is there keeps its bytes")
        XCTAssertEqual(value("Attachment", aid, "displayName") as? String, "arrived since", "and its row is untouched")
        XCTAssertEqual(value("Attachment", aid, "fileURL") as? String, present.path)
        XCTAssertEqual(value("Attachment", aid, "isThumbnail") as? Bool, false)
        XCTAssertEqual(try Data(contentsOf: kept), Data("the only copy of this recording".utf8), "the kept copy keeps its bytes")
        XCTAssertEqual(JournalRecovery.entries(store: store).map(\.id), [entry.id], "and the entry is still on the list, unresolved")
        XCTAssertFalse(container.viewContext.hasChanges, "nothing is left half-made in the context")
    }

    /// The same guard when a whole entry is restored: one of its attachments'
    /// ids already exists elsewhere. Nothing is made, nothing kept is removed.
    @MainActor
    func testRestoringADeletedEntryStopsWhenOneOfItsAttachmentIdsAlreadyExists() async throws {
        let (sid, aid, _, tombstones) = try seedEntryWithARecording()
        let elsewhere = try seedSession(title: "Another entry", notes: "", clock: backupClock)
        tracker.bootstrapIfNeeded()
        let engine = makeEngine()
        let complete = await firstFetch(engine, [try cloudCopy(.session, elsewhere, tag: "s2")], deleted: tombstones)
        defer { for url in keptFiles(for: aid) { try? FileManager.default.removeItem(at: url) } }
        XCTAssertTrue(complete); XCTAssertFalse(exists("Session", sid))
        let kept = try XCTUnwrap(keptFiles(for: aid).first)
        let present = JournalRecordMapping.materialisedURL(recordName: aid.uuidString, ext: "jpg")
        try Data("a different recording under the same id".utf8).write(to: present)
        try seedAttachment(aid, session: elsewhere, file: present, name: "arrived since", clock: backupClock)

        let entry = try XCTUnwrap(JournalRecovery.entries(store: store).first)
        guard case .failed = JournalRecovery.restore(entry, store: store, context: container.viewContext) else { return XCTFail("restore must not report success") }
        XCTAssertFalse(exists("Session", sid), "the entry is not half-restored without its recording")
        XCTAssertEqual(try Data(contentsOf: present), Data("a different recording under the same id".utf8))
        XCTAssertEqual(try Data(contentsOf: kept), Data("the only copy of this recording".utf8))
        XCTAssertEqual(JournalRecovery.entries(store: store).map(\.id), [entry.id])
    }

    /// If the content cannot be kept, it is not deleted and the first fetch
    /// is not complete: the file that cannot be copied, and the recovery
    /// entry that cannot be written. The next attempt keeps it, then deletes.
    @MainActor
    func testAnEntryThatCannotBeKeptIsNotDeletedAndTheFirstFetchStaysIncomplete() async throws {
        let (sid, aid, recording, tombstones) = try seedEntryWithARecording()
        tracker.bootstrapIfNeeded()
        let engine = makeEngine()
        let keptDir = JournalImporter.displacedMediaDirectory().path, stateDir = tempDir.appendingPathComponent("state").path
        defer { for url in keptFiles(for: aid) { try? FileManager.default.removeItem(at: url) } }
        for (label, dir) in [("the file cannot be copied", keptDir), ("the recovery entry cannot be written", stateDir)] {
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir)
            let complete = await firstFetch(engine, [], deleted: tombstones)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir)
            XCTAssertFalse(complete, "\(label): the batch is not complete")
            XCTAssertTrue(exists("Session", sid), "\(label): the entry is still in the journal")
            XCTAssertTrue(exists("Attachment", aid), "\(label): and its attachment")
            XCTAssertEqual(try Data(contentsOf: recording), Data("the only copy of this recording".utf8), "\(label): and its file")
            XCTAssertFalse(store.state.initialFetchComplete, "\(label): the merge is not marked complete")
            XCTAssertEqual(engine.sendDecision(), .heldForFirstFetch)
        }
        let complete = await firstFetch(engine, [], deleted: tombstones)
        XCTAssertTrue(complete, "once it can be kept, it is kept and then deleted")
        XCTAssertFalse(exists("Session", sid))
        XCTAssertEqual(JournalRecovery.entries(store: store).count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(keptFiles(for: aid).first)), Data("the only copy of this recording".utf8))
    }

    /// Outside the first merge nothing changes: a deletion from the other
    /// device is an ordinary synced deletion and keeps no copy.
    @MainActor
    func testADeletionAfterTheFirstFetchIsAnOrdinaryDeletionAndKeepsNothing() async throws {
        let (sid, aid, _, tombstones) = try seedEntryWithARecording()
        tracker.bootstrapIfNeeded()
        store.update { $0.initialFetchComplete = true }
        let engine = makeEngine()
        let complete = await firstFetch(engine, [], deleted: tombstones)
        XCTAssertTrue(complete)
        XCTAssertFalse(exists("Session", sid)); XCTAssertFalse(exists("Attachment", aid))
        XCTAssertTrue(store.state.conflicts.isEmpty); XCTAssertTrue(keptFiles(for: aid).isEmpty)
    }

    /// The same for a list: deleted on the other device, changed or made here
    /// and never sent. In the first merge its lines are kept as a list.
    @MainActor
    func testAListDeletedElsewhereInTheFirstFetchKeepsThisDevicesLinesAsAList() async throws {
        let scope = JournalSavedListSync.currentScope()
        let engine = makeEngine()
        defer {
            if let current = try? SavedListLibrary.read(ownerScope: scope) {
                try? SavedListLibrary.commit(snapshot: current, updated: current.filter { !$0.name.hasPrefix("C197 ") }, ownerScope: scope)
            }
        }
        let id = UUID(), name = "C197 deleted \(id.uuidString.prefix(6))"
        let before = try SavedListLibrary.read(ownerScope: scope)
        try SavedListLibrary.commit(snapshot: before, updated: before + [SavedList(id: id, name: name, items: [SavedListLine(text: "only on this device")])], ownerScope: scope)
        store.update { JournalChangeTracker.merge([.init(recordName: id.uuidString, recordType: JournalSyncRecordType.savedList, op: .save)], into: &$0) }
        let complete = await firstFetch(engine, [], deleted: [(JournalRecordMapping.recordID(for: id), JournalSyncRecordType.savedList)])
        XCTAssertTrue(complete)
        let lists = try SavedListLibrary.read(ownerScope: scope).filter { $0.name.hasPrefix(name) }
        XCTAssertEqual(lists.map(\.name), [JournalSavedListSync.keptName(name)], "the deleted list is gone and its lines are kept beside it")
        XCTAssertEqual(lists.first?.items.map(\.text), ["only on this device"])
        XCTAssertNotEqual(lists.first?.id, id)
        XCTAssertNil(pendingSave(id.uuidString))
    }
}
#endif
