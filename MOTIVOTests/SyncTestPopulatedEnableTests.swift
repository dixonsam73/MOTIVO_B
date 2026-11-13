//
//  SyncTestPopulatedEnableTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  C-197, assessed 2026-11-13: turning sync on on a device that already holds
//  the journal iCloud holds (two devices restored from one backup, sync then
//  turned on on both). Nothing here changes production code. EVERY TEST PINS
//  WHAT THE CODE DOES TODAY; a test whose name starts `testFAULT_` asserts a
//  behaviour that is wrong or doubtful, so the suite stays green while the
//  fault is on record. Fix the fault and that test must be rewritten.
//
//  The device is played by a temporary store filled with synthetic rows and a
//  bootstrap (`JournalChangeTracker.bootstrapIfNeeded`, what `activate` runs
//  first). iCloud is played by records built from those rows. The two orders
//  the first activation can take are driven through the paths the engine uses:
//    send first  → the save is rejected (serverRecordChanged) and the engine
//                  calls `JournalImporter.resolveSendConflict`;
//    fetch first → the whole zone arrives while the saves are still pending
//                  and the engine calls `applyFetchedBatch`.
//  Which order a real activation takes cannot be reached without a seam
//  (`activate` is private and needs CloudKit); that part of the assessment is
//  read from the code, not tested here.
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
        store = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("state.json"))
        tracker = JournalChangeTracker(container: container, store: store)
        suiteName = "synctest-c197-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        // No `JournalUserEditStamp.install()` here, on purpose: the observer is
        // installed by `JournalSyncEngine.start` (JournalSyncEngine.swift:241),
        // so a device whose sync was never on saves without it.
    }

    override func tearDownWithError() throws {
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

    /// The person edits a row in the app while sync is off: an ordinary save
    /// in the view context.
    private func editInApp(_ id: UUID, _ body: (NSManagedObject) -> Void) throws {
        let ctx = container.viewContext
        let r = NSFetchRequest<NSManagedObject>(entityName: "Session"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let row = try XCTUnwrap(try ctx.fetch(r).first)
        body(row)
        try ctx.save()
    }

    // MARK: 1. What the first activation queues, and what it knows

    /// Everything the device holds is queued before anything is fetched, and
    /// the device knows no server copy and no server file hash. With those
    /// inputs the asset rule says "carry the file" for every attachment
    /// (the engine asks it at JournalSyncEngine.swift:1898).
    func testTheFirstBootstrapQueuesEveryRowAndKnowsNothingOfTheServerSoEveryFileIsDueToGoUp() throws {
        let photo = try file("photo.jpg", "jpeg bytes")
        let sid = try seedSession(title: "Scales", notes: "slow", clock: backupClock)
        let aid = try seedAttachment(session: sid, file: photo, name: "take 1", clock: backupClock)
        XCTAssertEqual(tracker.bootstrapIfNeeded(), 3, "the session, the attachment and its metadata record")
        let st = store.state
        XCTAssertNotNil(pendingSave(sid.uuidString)); XCTAssertNotNil(pendingSave(aid.uuidString))
        XCTAssertTrue(st.lastKnownRecords.isEmpty, "no server copy is known")
        XCTAssertTrue(st.assetHashes.isEmpty, "no server file is known")
        XCTAssertFalse(st.initialFetchComplete); XCTAssertNil(st.catchUpZoneToken)
        let localHash = try XCTUnwrap(JournalAssetHash.hash(of: photo))
        XCTAssertTrue(JournalAssetPolicy.includeAsset(hasServerCopy: st.lastKnownRecords[aid.uuidString] != nil,
                                                      serverHash: st.assetHashes[aid.uuidString], localHash: localHash,
                                                      assetFree: pendingSave(aid.uuidString)?.assetFree ?? false),
                      "a save built now carries the file, although iCloud already holds the same bytes")
    }

    // MARK: 2. Identical records

    /// Send first: three rejected saves, three entries in the state file's
    /// conflicts list, although nothing differed. The journal is unchanged and
    /// nothing is sent again. The attachment's entry is worse than noise: the
    /// content record carries no name (the name lives on the metadata record),
    /// so the comparison reads the local name against "" and lists it as
    /// displaced (JournalImporter.swift:902-908). The person's Displaced by
    /// sync list then shows one entry per NAMED attachment, offering to
    /// restore a name that never changed.
    @MainActor
    func testFAULT_IdenticalRecordsSendFirstLeaveAConflictEntryEachAndANamedAttachmentIsListedAsDisplaced() throws {
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
        XCTAssertEqual(resends, [false, false, false], "equal clocks: the server copy stands and nothing is sent again")
        XCTAssertTrue(store.state.outbox.isEmpty)
        XCTAssertEqual(value("Session", sid, "notes") as? String, "slow"); XCTAssertEqual(value("Attachment", aid, "displayName") as? String, "take 1")
        XCTAssertEqual(try Data(contentsOf: photo), Data("jpeg bytes".utf8))
        // The fault: a "conflict" is written for content that is the same.
        assertIdenticalRecordsLeftThreeEntries(session: sid, attachment: aid)
    }

    /// Fetch first: the same three entries, by the import path. No file is
    /// asked for and the device's own file stays in place.
    @MainActor
    func testFAULT_IdenticalRecordsFetchFirstLeaveTheSameEntriesAndTheLocalFileStays() async throws {
        let photo = try file("photo.jpg", "jpeg bytes")
        let hash = try XCTUnwrap(JournalAssetHash.hash(of: photo))
        let sid = try seedSession(title: "Scales", notes: "slow", clock: backupClock)
        let aid = try seedAttachment(session: sid, file: photo, name: "take 1", clock: backupClock)
        let cloud = [try cloudCopy(.session, sid, tag: "s1"), try cloudCopy(.attachment(hash: hash), aid, tag: "a1"), try cloudCopy(.meta, aid, tag: "m1")]
        tracker.bootstrapIfNeeded()
        let engine = makeEngine()
        let complete = await engine.applyFetchedBatch(modified: cloud, deleted: [], newToken: nil, assetsFetched: 0,
                                                      generation: engine.generationForTesting(), reason: "first fetch", writeFailuresBefore: store.writeFailures)
        XCTAssertTrue(complete); XCTAssertTrue(store.state.initialFetchComplete)
        XCTAssertTrue(store.state.outbox.isEmpty, "every pending save was settled by the cloud copy, so nothing is uploaded")
        XCTAssertEqual(store.state.assetHashes[aid.uuidString], hash, "the server's hash is learned without the file")
        XCTAssertEqual(value("Attachment", aid, "fileURL") as? String, photo.path)
        XCTAssertEqual(value("Attachment", aid, "displayName") as? String, "take 1")
        assertIdenticalRecordsLeftThreeEntries(session: sid, attachment: aid)
    }

    /// What both orders leave for one session and one named attachment whose
    /// cloud copies are identical to the device's.
    @MainActor
    private func assertIdenticalRecordsLeftThreeEntries(session sid: UUID, attachment aid: UUID, line: UInt = #line) {
        let entries = store.state.conflicts
        XCTAssertEqual(entries.count, 3, "one per session, attachment and attachment-metadata record", line: line)
        XCTAssertTrue(entries.allSatisfy { $0.winner == "server" }, line: line)
        let displaced = Dictionary(entries.map { ($0.recordName, $0.displaced) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(displaced[sid.uuidString], [:], "the session's entry has nothing in it", line: line)
        XCTAssertEqual(displaced[JournalSyncRecordType.metaName(for: aid.uuidString)], [:], "nor has the metadata record's", line: line)
        XCTAssertEqual(displaced[aid.uuidString], ["Name (this device)": "take 1"],
                       "the attachment's claims its name was displaced, although the name is unchanged", line: line)
        XCTAssertEqual(JournalRecovery.entries(store: store).map(\.recordName), [aid.uuidString],
                       "and that one is shown to the person on the Displaced by sync list", line: line)
    }

    // MARK: 3. Divergent edits

    /// The clock that decides a conflict (`userModifiedAt`) is written only by
    /// an observer the engine installs (JournalSyncEngine.swift:241). An edit
    /// made while sync was never on therefore has no clock, and at the first
    /// activation it loses to the cloud copy even when that copy is the OLDER
    /// text. Title and notes are kept for recovery; no other field is.
    @MainActor
    func testFAULT_AnEditMadeBeforeSyncWasTurnedOnHasNoClockSoTheOlderCloudCopyWinsAndOnlyTitleAndNotesAreKept() throws {
        try XCTSkipIf(JournalSyncCoordinator.shared.isInUse, "the host app has sync in use, so its edit-stamp observer is installed")
        // Two sessions as the backup held them; iCloud has them as the other device uploaded them.
        let sendFirst = try seedSession(title: "Scales", notes: "as in the backup", duration: 600, clock: nil)
        let fetchFirst = try seedSession(title: "Arpeggios", notes: "as in the backup", duration: 600, clock: nil)
        let cloud = [try cloudCopy(.session, sendFirst, tag: "s1"), try cloudCopy(.session, fetchFirst, tag: "s2")]
        // The person then edits both on this device, sync still off.
        for id in [sendFirst, fetchFirst] {
            try editInApp(id) { $0.setValue("rewritten here after the backup", forKey: "notes"); $0.setValue(Int64(1800), forKey: "durationSeconds") }
        }
        try XCTSkipIf(value("Session", sendFirst, "userModifiedAt") != nil, "an edit-stamp observer from another test is still installed")
        XCTAssertNil(value("Session", fetchFirst, "userModifiedAt"), "with sync off nothing stamps the edit")
        // Sync is turned on.
        tracker.bootstrapIfNeeded()
        let (imp, ictx) = importer()
        var resend = true
        var imported = JournalImporter.Summary()
        ictx.performAndWait {
            resend = imp.resolveSendConflict(recordType: "Session", recordName: sendFirst.uuidString, server: cloud[0])   // send first
            imported = imp.importModifications([cloud[1]])                                                             // fetch first
        }
        XCTAssertFalse(resend); XCTAssertEqual(imported.received, 1)
        for id in [sendFirst, fetchFirst] {
            XCTAssertEqual(value("Session", id, "notes") as? String, "as in the backup", "the edit is gone from the journal")
            XCTAssertEqual(value("Session", id, "durationSeconds") as? Int64, 600, "and so is the duration it set")
            XCTAssertNil(pendingSave(id.uuidString), "nothing is sent, so the other device never sees the edit")
        }
        let shown = JournalRecovery.entries(store: store)
        XCTAssertEqual(shown.count, 2, "both are on the Displaced by sync list")
        XCTAssertTrue(shown.allSatisfy { $0.displaced == ["Notes (this device)": "rewritten here after the backup"] },
                      "the notes can be restored by hand; the duration is recorded nowhere")
    }

    /// With a clock on both sides the rule works as designed whichever side is
    /// newer, and the losing text is readable. This is the case of a device
    /// that had sync on before (unlinked, then turned on again).
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

    // MARK: 4. Media

    /// The other device replaced a recording (a trim) after the backup and
    /// uploaded it. This device holds the old file under the same attachment
    /// id and has never exchanged a hash. The cloud record wins, but the file
    /// is put in place only when a KNOWN hash differs (JournalImporter.swift:397),
    /// and with no known hash the server's is adopted for the file already
    /// here (:441). The device keeps the old bytes and believes they are the
    /// cloud's, so no later catch-up fetches the new file.
    func testFAULT_AStaleLocalFileIsKeptAndRecordedAsTheCloudsWhenTheCloudHoldsADifferentFileForTheSameAttachment() throws {
        let old = try file("recording.jpg", "the take as the backup held it")
        let trimmed = try file("trimmed.jpg", "the trimmed take")
        let trimmedHash = try XCTUnwrap(JournalAssetHash.hash(of: trimmed))
        let sid = try seedSession(title: "Recording", notes: "", clock: backupClock)
        let aid = try seedAttachment(session: sid, file: old, name: "take 1", clock: backupClock)
        let cloud = try cloudCopy(.attachment(hash: trimmedHash), aid, tag: "a2")
        cloud[JournalRecordMapping.assetKey] = CKAsset(fileURL: trimmed)          // the catch-up fetched it: the hash is new here
        cloud["userModifiedAt"] = backupClock.addingTimeInterval(600) as CKRecordValue
        tracker.bootstrapIfNeeded()
        XCTAssertTrue(JournalCatchUp.needsAsset(serverHash: trimmedHash, knownHash: store.state.assetHashes[aid.uuidString], fileExists: true,
                                                localHash: JournalAssetHash.hash(of: old)), "precondition: the first fetch does ask for the file")
        let (imp, ictx) = importer()
        var summary = JournalImporter.Summary()
        ictx.performAndWait { summary = imp.importModifications([cloud]) }
        XCTAssertEqual(summary.received, 1, "the cloud record is applied")
        XCTAssertNil(pendingSave(aid.uuidString))
        XCTAssertEqual(value("Attachment", aid, "fileURL") as? String, old.path, "the row still points at the old file")
        XCTAssertEqual(try Data(contentsOf: old), Data("the take as the backup held it".utf8), "whose bytes are unchanged")
        XCTAssertEqual(store.state.assetHashes[aid.uuidString], trimmedHash, "yet the state file says this device holds the trimmed file")
        XCTAssertFalse(JournalCatchUp.needsAsset(serverHash: trimmedHash, knownHash: store.state.assetHashes[aid.uuidString], fileExists: true,
                                                 localHash: JournalAssetHash.hash(of: old)),
                       "so no later catch-up fetches it, although the file here still hashes differently")
        XCTAssertFalse(FileManager.default.fileExists(atPath: JournalRecordMapping.materialisedURL(recordName: aid.uuidString, ext: "jpg").path))
    }

    // MARK: 5. Entries deleted on the other device

    /// A whole-zone read is "what the zone holds now". With no tombstone for
    /// an entry deleted on the other device, the completed first fetch leaves
    /// that entry on this device AND still queued, and its outgoing record is
    /// a new one (no server change tag), which the server accepts. Fetching
    /// before sending does not change that. The merge is a union the other way
    /// too: an entry only iCloud holds arrives here.
    @MainActor
    func testFAULT_AnEntryDeletedOnTheOtherDeviceStaysQueuedAfterACompleteFirstFetchThatBringsNoTombstone() async throws {
        let kept = try seedSession(title: "Kept on both", notes: "", clock: backupClock)
        let deletedElsewhere = try seedSession(title: "Deleted on the other device", notes: "", clock: backupClock)
        let cloudOnly = UUID()
        let fromCloud = CKRecord(recordType: "Session", recordID: JournalRecordMapping.recordID(for: cloudOnly))
        fromCloud["title"] = "Only in iCloud" as CKRecordValue; fromCloud["timestamp"] = backupClock as CKRecordValue
        fromCloud["userModifiedAt"] = backupClock as CKRecordValue; fromCloud["testTag"] = "s9" as CKRecordValue
        let zone = [try cloudCopy(.session, kept, tag: "s1"), fromCloud]
        tracker.bootstrapIfNeeded()
        let engine = makeEngine()
        let complete = await engine.applyFetchedBatch(modified: zone, deleted: [], newToken: nil, assetsFetched: 0,
                                                      generation: engine.generationForTesting(), reason: "first fetch", writeFailuresBefore: store.writeFailures)
        XCTAssertTrue(complete); XCTAssertTrue(store.state.initialFetchComplete, "the first fetch is complete")
        XCTAssertNil(pendingSave(kept.uuidString), "the entry both hold is settled")
        XCTAssertTrue(exists("Session", cloudOnly), "an entry only iCloud holds arrives here")
        XCTAssertTrue(exists("Session", deletedElsewhere), "the entry deleted elsewhere is still in this journal")
        XCTAssertNotNil(pendingSave(deletedElsewhere.uuidString), "and still waits to be uploaded")
        XCTAssertNil(store.state.lastKnownRecords[deletedElsewhere.uuidString], "as a record the server has never seen")
        let ctx = container.newBackgroundContext()
        var outgoing: CKRecord?
        ctx.performAndWait {
            let r = NSFetchRequest<NSManagedObject>(entityName: "Session"); r.predicate = NSPredicate(format: "id == %@", deletedElsewhere as CVarArg)
            outgoing = (try? ctx.fetch(r))?.first.flatMap { JournalRecordMapping.record(for: $0, base: nil) }
        }
        XCTAssertNil(try XCTUnwrap(outgoing).recordChangeTag, "a save without a change tag creates the record again for every device")
    }

    /// When the read does carry tombstones (the Production zone returned three
    /// to a fresh read on 2026-11-13), and they are applied before the send,
    /// the entry is removed from this device and from the outbox.
    @MainActor
    func testATombstoneAppliedBeforeTheSendRemovesTheLocalEntryAndItsPendingSaves() async throws {
        let photo = try file("photo.jpg", "jpeg bytes")
        let kept = try seedSession(title: "Kept on both", notes: "", clock: backupClock)
        let deletedElsewhere = try seedSession(title: "Deleted on the other device", notes: "", clock: backupClock)
        let aid = try seedAttachment(session: deletedElsewhere, file: photo, name: "take 1", clock: backupClock)
        let meta = JournalSyncRecordType.metaName(for: aid.uuidString)
        let zone = [try cloudCopy(.session, kept, tag: "s1")]
        tracker.bootstrapIfNeeded()
        XCTAssertEqual(store.state.outbox.count, 4)
        let engine = makeEngine()
        let tombstones: [(CKRecord.ID, CKRecord.RecordType)] = [
            (JournalRecordMapping.recordID(for: deletedElsewhere), "Session"), (JournalRecordMapping.recordID(for: aid), "Attachment"),
            (CKRecord.ID(recordName: meta, zoneID: JournalRecordMapping.zoneID), JournalSyncRecordType.attachmentMeta)]
        let complete = await engine.applyFetchedBatch(modified: zone, deleted: tombstones, newToken: nil, assetsFetched: 0,
                                                      generation: engine.generationForTesting(), reason: "first fetch", writeFailuresBefore: store.writeFailures)
        XCTAssertTrue(complete)
        XCTAssertFalse(exists("Session", deletedElsewhere)); XCTAssertFalse(exists("Attachment", aid))
        XCTAssertTrue(exists("Session", kept))
        XCTAssertTrue(store.state.outbox.isEmpty, "nothing of the deleted entry is uploaded")
        XCTAssertTrue(FileManager.default.fileExists(atPath: photo.path), "a file outside Documents is never removed by a remote deletion")
    }

    // MARK: 6. Saved Lists (no clock): the winner depends on the order

    /// A list both devices hold (same id), edited differently on each. If the
    /// zone is fetched while this device's save is pending, the local version
    /// is kept and then replaces the cloud's (JournalSavedListSync.swift:108,
    /// :125). If the save is sent first and rejected, the cloud's replaces the
    /// local one (JournalSyncEngine.swift:2205). Neither loser is kept.
    @MainActor
    func testFAULT_ForAListBothDevicesEditedTheWinnerDependsOnWhetherTheFetchOrTheSendCameFirstAndTheLoserIsKeptNowhere() throws {
        let scope = "device"
        let id = UUID()
        let local = SavedList(id: id, name: "Warm-up", items: [SavedListLine(text: "edited on this device")])
        let cloud = try XCTUnwrap(JournalRecordMapping.record(for: SavedList(id: id, name: "Warm-up", items: [SavedListLine(text: "edited on the other device")]), base: nil))

        // Fetch first.
        try SavedListLibrary.commit(snapshot: [], updated: [local], ownerScope: scope, defaults: defaults)
        XCTAssertEqual(JournalSavedListSync.scan(store: store, defaults: defaults, scope: scope).map(\.recordName), [id.uuidString], "the first scan queues every list")
        XCTAssertEqual(JournalSavedListSync.apply([cloud], store: store, defaults: defaults, scope: scope), 0, "a pending list is not replaced")
        XCTAssertEqual(try SavedListLibrary.read(ownerScope: scope, defaults: defaults).first?.items.map(\.text), ["edited on this device"])
        XCTAssertNotNil(pendingSave(id.uuidString))
        let next = JournalSavedListSync.records(for: [id.uuidString], bases: store.state.lastKnownRecords, defaults: defaults, scope: scope)
        XCTAssertEqual(JournalRecordMapping.savedList(from: try XCTUnwrap(next[id.uuidString]))?.items.map(\.text), ["edited on this device"],
                       "and the save that follows carries the local lines on top of the cloud copy")
        XCTAssertTrue(store.state.conflicts.isEmpty, "the other device's lines are kept nowhere")

        // Send first: the same list on a second device state.
        let otherSuite = "synctest-c197-other-\(UUID().uuidString)"
        let other = try XCTUnwrap(UserDefaults(suiteName: otherSuite))
        defer { other.removePersistentDomain(forName: otherSuite) }
        let otherStore = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("other.json"))
        try SavedListLibrary.commit(snapshot: [], updated: [local], ownerScope: scope, defaults: other)
        XCTAssertEqual(JournalSavedListSync.scan(store: otherStore, defaults: other, scope: scope).count, 1)
        XCTAssertEqual(JournalSavedListSync.apply([cloud], store: otherStore, defaults: other, scope: scope, overridePending: true), 1)
        XCTAssertEqual(try SavedListLibrary.read(ownerScope: scope, defaults: other).first?.items.map(\.text), ["edited on the other device"])
        XCTAssertTrue(otherStore.state.outbox.isEmpty)
        XCTAssertTrue(otherStore.state.conflicts.isEmpty, "this device's lines are kept nowhere")
    }
}
#endif
