//
//  SyncTestStep0ReviewTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  The independent review of Step 0 (2026-11-03) found six remaining paths,
//  R1–R6. Each test drives the actual calling path: the engine's removal
//  entry point, the catch-up's apply sequence with a hook between record
//  families, the importer's retry after a failed save, the outbox settle
//  after an entry was removed and re-created, the rejected-send conflict
//  handler, and the media release's apply half. They were run against the
//  seams alone first (every one failed as the review predicted), then
//  against the fixes.
//

#if SYNCTEST
import XCTest
import CoreData
import CloudKit
@testable import Etudes

final class SyncTestStep0ReviewTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var store: JournalSyncStateStore!
    private var tempDir: URL!
    private var stamp: NSObjectProtocol?
    private var tracker: JournalChangeTracker!
    /// The importer holds its queue weakly (the engine is the queue); tests keep theirs here.
    private var queues: [Step0Queue] = []

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-review-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir.appendingPathComponent("state"), withIntermediateDirectories: true)
        container = try Self.openStore(at: tempDir.appendingPathComponent("store.sqlite"), readOnly: false)
        container.viewContext.transactionAuthor = JournalSyncAuthor.app
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        store = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("state/state.json"))
        stamp = JournalUserEditStamp.install()
        tracker = JournalChangeTracker(container: container, store: store)
    }

    override func tearDownWithError() throws {
        if let stamp { NotificationCenter.default.removeObserver(stamp) }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.appendingPathComponent("state").path)
        JournalSyncEngine.testBeforeFamily = nil
        queues.removeAll()
        container = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: helpers

    private static func openStore(at url: URL, readOnly: Bool) throws -> NSPersistentContainer {
        let c = NSPersistentContainer(name: "MOTIVO")
        let d = NSPersistentStoreDescription(url: url)
        d.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        d.isReadOnly = readOnly
        d.shouldAddStoreAsynchronously = false
        c.persistentStoreDescriptions = [d]
        var loadError: Error?
        c.loadPersistentStores { _, error in loadError = error }
        try XCTUnwrap(loadError == nil ? () : nil, "store failed to load: \(String(describing: loadError))")
        return c
    }

    /// An engine as the coordinator builds it, never started (no CloudKit traffic).
    @MainActor
    private func makeEngine(persistence: NSPersistentContainer? = nil) -> JournalSyncEngine {
        let engine = JournalSyncEngine(containerIdentifier: JournalSyncCoordinator.containerIdentifier, persistence: persistence ?? container,
                                       store: store, status: JournalSyncStatus(), customOwner: nil)
        engine.importer.log = { [store] in store?.log($0) }
        engine.importer.changeTag = { $0["testTag"] as? String }
        store.update { $0.boundUserRecordName = "_user" }
        engine.assumeCurrentUserForTesting("_user")
        return engine
    }

    private func importer(on persistence: NSPersistentContainer? = nil) -> (JournalImporter, NSManagedObjectContext, Step0Queue) {
        let ctx = (persistence ?? container).newBackgroundContext()
        ctx.name = "syncImport"; ctx.transactionAuthor = JournalSyncAuthor.sync
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy; ctx.stalenessInterval = 0
        let q = Step0Queue(store: store)
        queues.append(q)
        let imp = JournalImporter(context: ctx, store: store, customOwner: nil)
        imp.queue = q
        imp.log = { [store] in store?.log($0) }
        imp.changeTag = { $0["testTag"] as? String }
        return (imp, ctx, q)
    }

    private func sessionRecord(id: UUID, notes: String, modified: Date, tag: String) -> CKRecord {
        let r = CKRecord(recordType: "Session", recordID: JournalRecordMapping.recordID(for: id))
        r["title"] = "T" as CKRecordValue; r["timestamp"] = Date(timeIntervalSince1970: 1_700_000_000) as CKRecordValue
        r["notes"] = notes as CKRecordValue; r["userModifiedAt"] = modified as CKRecordValue
        r["testTag"] = tag as CKRecordValue
        return r
    }

    private func profileRecord(name: String) -> CKRecord {
        let r = CKRecord(recordType: JournalSyncRecordType.profile, recordID: CKRecord.ID(recordName: JournalProfileSync.profileName, zoneID: JournalRecordMapping.zoneID))
        r[JournalProfileKeys.name] = name as CKRecordValue
        r[JournalProfileKeys.stamp] = Date() as CKRecordValue
        return r
    }

    private func attachmentRecord(id: UUID, sessionID: UUID, file: URL, hash: String, tag: String) -> CKRecord {
        let r = CKRecord(recordType: "Attachment", recordID: JournalRecordMapping.recordID(for: id))
        r["kind"] = "image" as CKRecordValue; r["createdAt"] = Date() as CKRecordValue; r["userModifiedAt"] = Date() as CKRecordValue
        r["session"] = CKRecord.Reference(recordID: JournalRecordMapping.recordID(for: sessionID), action: .none)
        r["file"] = CKAsset(fileURL: file); r["fileExt"] = "jpg" as CKRecordValue; r["fileHash"] = hash as CKRecordValue
        r["testTag"] = tag as CKRecordValue
        return r
    }

    private func notes(_ id: UUID) -> String? { value("Session", id, "notes") as? String }
    private func value(_ entity: String, _ id: UUID, _ key: String) -> Any? {
        let ctx = container.newBackgroundContext(); var out: Any?
        ctx.performAndWait {
            let r = NSFetchRequest<NSManagedObject>(entityName: entity); r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            out = (try? ctx.fetch(r))?.first?.value(forKey: key)
        }
        return out
    }
    private func rowCount(_ entity: String) -> Int {
        let ctx = container.newBackgroundContext(); var n = 0
        ctx.performAndWait { n = (try? ctx.count(for: NSFetchRequest<NSManagedObject>(entityName: entity))) ?? 0 }
        return n
    }
    private func profileName() -> String? {
        let ctx = container.newBackgroundContext(); var out: String?
        ctx.performAndWait { out = (try? ctx.fetch(NSFetchRequest<NSManagedObject>(entityName: JournalSyncRecordType.profile)))?.first?.value(forKey: "name") as? String }
        return out
    }
    private func editNotesInApp(_ id: UUID, _ text: String) throws {
        let ctx = container.viewContext
        let r = NSFetchRequest<NSManagedObject>(entityName: "Session"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let s = try XCTUnwrap(try ctx.fetch(r).first); s.setValue(text, forKey: "notes"); try ctx.save()
    }
    private func makeStateUnwritable(_ on: Bool) throws {
        try FileManager.default.setAttributes([.posixPermissions: on ? 0o500 : 0o755], ofItemAtPath: tempDir.appendingPathComponent("state").path)
    }
    private func pendingSave(_ id: UUID) -> JournalSyncPendingChange? { store.state.outbox.first { $0.recordName == id.uuidString && $0.op == .save } }

    // MARK: R1 — the removal marker cannot be saved

    @MainActor
    func testR1_ARemovalWhoseMarkerCannotBeSavedIsRefusedAndStopsTransport() throws {
        let engine = makeEngine()
        store.update { $0.boundUserRecordName = "_user" }
        XCTAssertTrue(engine.currentDecision().allowed, "precondition: the bound account allows")
        try makeStateUnwritable(true)
        let began = engine.beginLocalRemoval(reason: "test")
        try makeStateUnwritable(false)
        XCTAssertFalse(began, "R1: the caller learns the marker did not persist and must not delete anything")
        XCTAssertFalse(engine.currentDecision().allowed, "and nothing is sent or fetched meanwhile")
        XCTAssertFalse(store.state.localRemovalInProgress, "the marker is not on disk")
        XCTAssertTrue(store.state.outbox.isEmpty)
        // The coordinator's entry point reports the same (no engine: the pure marker write).
        XCTAssertFalse(JournalLocalRemoval.begin(store: JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("missing-dir/x.json")), reason: "test"))
    }

    // MARK: R2 — a removal between two record families of one catch-up

    @MainActor
    func testR2_ARemovalBetweenRecordFamiliesStopsTheLaterFamiliesAndTheTokenCommit() async throws {
        let engine = makeEngine()
        store.update { $0.boundUserRecordName = "_user" }
        let sid = UUID()
        let records = [sessionRecord(id: sid, notes: "first family", modified: Date(), tag: "s1"), profileRecord(name: "Arrived Late")]
        JournalSyncEngine.testBeforeFamily = { family in
            if family == "profile" { engine.beginLocalRemoval(reason: "test") }
        }
        let complete = await engine.applyFetchedBatch(modified: records, deleted: [], newToken: nil, assetsFetched: 0,
                                                      generation: 0, reason: "test", writeFailuresBefore: store.writeFailures)
        JournalSyncEngine.testBeforeFamily = nil
        XCTAssertFalse(complete, "R2: the batch is not complete once the removal began")
        XCTAssertTrue(store.state.localRemovalInProgress)
        XCTAssertNotEqual(profileName(), "Arrived Late", "the profile family after the removal must not be applied")
        XCTAssertFalse(store.state.initialFetchComplete, "and the first-fetch state is not committed on a removed copy")
        XCTAssertTrue(store.state.catchUpRecords == 0, "nothing counted as caught up")
    }

    // MARK: R3 — a failed save must not suppress the retry

    func testR3_ARecordWhoseSaveFailedIsImportedOnTheRetryNotSkippedAsAnEcho() throws {
        let readOnly = try Self.openStore(at: tempDir.appendingPathComponent("store.sqlite"), readOnly: true)
        let (failing, fctx, _) = importer(on: readOnly)
        let sid = UUID()
        let record = sessionRecord(id: sid, notes: "new on the server", modified: Date(), tag: "server-tag-1")
        var first = JournalImporter.Summary()
        fctx.performAndWait { first = failing.importModifications([record]) }
        XCTAssertTrue(first.saveFailed); XCTAssertEqual(rowCount("Session"), 0)
        // Relaunch: a fresh importer on the same state file retries the same record (the zone token was kept).
        let reloaded = JournalSyncStateStore(fileURL: store.fileURL)
        store = reloaded
        let (retry, rctx, _) = importer()
        var second = JournalImporter.Summary()
        rctx.performAndWait { second = retry.importModifications([record]) }
        XCTAssertEqual(second.echoes, 0, "R3: a record that never reached the store is not an echo")
        XCTAssertEqual(second.received, 1)
        XCTAssertEqual(notes(sid), "new on the server")
        XCTAssertEqual(reloaded.state.knownChangeTags[sid.uuidString], "server-tag-1", "known only once applied")
        // And a genuine echo of that applied copy is now skipped.
        var third = JournalImporter.Summary()
        rctx.performAndWait { third = retry.importModifications([record]) }
        XCTAssertEqual(third.echoes, 1); XCTAssertEqual(third.received, 0)
    }

    // MARK: R4 — an old acknowledgement after the entry was removed and re-created

    func testR4_AnOldSendAcknowledgementNeverSettlesAnEntryCreatedAfterItsRemoval() throws {
        let (imp, ictx, _) = importer()
        let sid = UUID()
        let t0 = Date().addingTimeInterval(-600)
        ictx.performAndWait { _ = imp.importModifications([sessionRecord(id: sid, notes: "v1", modified: t0, tag: "t1")]) }
        // Edit A: queued; the batch is built with its revision.
        try editNotesInApp(sid, "edit A")
        XCTAssertFalse(tracker.processHistory().isEmpty)
        let sentRevision = try XCTUnwrap(pendingSave(sid)).revision
        // Before A's acceptance is handled, a catch-up sees the server copy with A's clock (equal clock: server wins, entry settled).
        let clockA = try XCTUnwrap(value("Session", sid, "userModifiedAt") as? Date)
        var echo = JournalImporter.Summary()
        ictx.performAndWait { echo = imp.importModifications([sessionRecord(id: sid, notes: "edit A", modified: clockA, tag: "t2")]) }
        XCTAssertNil(pendingSave(sid), "precondition: the catch-up settled A's entry; received \(echo.received) echoes \(echo.echoes) saveFailed \(echo.saveFailed) conflicts \(store.state.conflicts.count) outbox \(store.state.outbox.map { ($0.recordName.prefix(8), $0.op.rawValue, $0.revision) }) clockA \(clockA.timeIntervalSince1970) localNow \(String(describing: (value("Session", sid, "userModifiedAt") as? Date)?.timeIntervalSince1970)) log: \(store.state.log.suffix(6).map(\.text))")
        // Edit B creates a new entry.
        try editNotesInApp(sid, "edit B")
        XCTAssertFalse(tracker.processHistory().isEmpty)
        let entryB = try XCTUnwrap(pendingSave(sid))
        // A's delayed acceptance arrives.
        let settled = JournalOutboxSettle.settle(name: sid.uuidString, sentRevision: sentRevision, outbox: store.state.outbox)
        XCTAssertTrue(settled.keptNewer, "R4: edit B's entry is newer than the send being acknowledged")
        XCTAssertEqual(settled.outbox.count, 1)
        XCTAssertGreaterThan(entryB.revision, sentRevision, "a re-created entry never reuses an earlier revision")
        // The sequence survives a relaunch.
        XCTAssertEqual(JournalSyncStateStore(fileURL: store.fileURL).state.outboxSequence, store.state.outboxSequence)
    }

    // MARK: R5 — the rejected-send conflict handler

    func testR5_ARejectedSendWhoseRecoveryEntryCannotBeSavedKeepsTheLocalText() throws {
        let (imp, ictx, _) = importer()
        let sid = UUID()
        ictx.performAndWait { _ = imp.importModifications([sessionRecord(id: sid, notes: "v1", modified: Date().addingTimeInterval(-600), tag: "t1")]) }
        try editNotesInApp(sid, "typed here")
        XCTAssertFalse(tracker.processHistory().isEmpty)
        let server = sessionRecord(id: sid, notes: "other device, newer", modified: Date().addingTimeInterval(60), tag: "t2")
        try makeStateUnwritable(true)
        var resend = false
        ictx.performAndWait { resend = imp.resolveSendConflict(recordType: "Session", recordName: sid.uuidString, server: server) }
        try makeStateUnwritable(false)
        XCTAssertEqual(notes(sid), "typed here", "R5: no overwrite without a saved recovery entry")
        XCTAssertNotNil(pendingSave(sid), "the edit stays queued")
        XCTAssertTrue(resend, "and is tried again")
        XCTAssertTrue(store.state.conflicts.isEmpty)
    }

    // MARK: R6 — a held download whose import fails stays held

    @MainActor
    func testR6_AHeldDownloadStaysHeldUntilItIsDurablyImported() async throws {
        let sid = UUID(), aid = UUID()
        let (imp, ictx, _) = importer()
        ictx.performAndWait { _ = imp.importModifications([sessionRecord(id: sid, notes: "", modified: Date(), tag: "s")]) }
        let file = tempDir.appendingPathComponent("photo.jpg")
        try Data("jpeg bytes".utf8).write(to: file)
        store.update { $0.awaitingMedia = [aid.uuidString] }
        let record = attachmentRecord(id: aid, sessionID: sid, file: file, hash: "h1", tag: "a1")
        // First release: the download succeeded but the store cannot commit.
        let readOnly = try Self.openStore(at: tempDir.appendingPathComponent("store.sqlite"), readOnly: true)
        let failing = makeEngine(persistence: readOnly)
        _ = await failing.applyReleasedMedia(full: [record], gone: [], generation: 0)
        XCTAssertEqual(store.state.awaitingMedia, [aid.uuidString], "R6: the hold stays until the row is in the store")
        XCTAssertEqual(rowCount("Attachment"), 0)
        // Relaunch, store writable: the retry applies it once and releases the hold.
        store = JournalSyncStateStore(fileURL: store.fileURL)
        XCTAssertEqual(store.state.awaitingMedia, [aid.uuidString])
        let working = makeEngine()
        let released = await working.applyReleasedMedia(full: [record], gone: [], generation: 0)
        XCTAssertEqual(released, [aid.uuidString])
        XCTAssertTrue(store.state.awaitingMedia.isEmpty)
        XCTAssertEqual(rowCount("Attachment"), 1)
        try? FileManager.default.removeItem(at: JournalRecordMapping.materialisedURL(recordName: aid.uuidString, ext: "jpg"))
    }
}
#endif
