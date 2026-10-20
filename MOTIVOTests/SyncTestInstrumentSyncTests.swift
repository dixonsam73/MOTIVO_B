//
//  SyncTestInstrumentSyncTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  Profile instruments across devices: a session's instrument link travels
//  with it and resolves by id, by alias, by name, or by creating the row
//  under the local profile; two devices that each had the same-named
//  instrument keep their own rows through an alias; instrument deletions
//  reach the outbox; and the start retry backoff.
//

#if SYNCTEST
import XCTest
import CoreData
import CloudKit
@testable import Etudes

final class SyncTestInstrumentSyncTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var store: JournalSyncStateStore!
    private var tempDir: URL!
    private var stamp: NSObjectProtocol?
    private var keptContexts: [NSManagedObjectContext] = []

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-inst-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        container = NSPersistentContainer(name: "MOTIVO")
        let description = NSPersistentStoreDescription(url: tempDir.appendingPathComponent("store.sqlite"))
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        try XCTUnwrap(loadError == nil ? () : nil)
        container.viewContext.transactionAuthor = JournalSyncAuthor.app
        store = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("state.json"))
        stamp = JournalUserEditStamp.install()
    }

    override func tearDownWithError() throws {
        if let stamp { NotificationCenter.default.removeObserver(stamp) }
        keptContexts.removeAll()
        container = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: helpers

    private func importer(_ queue: RecordingSendQueue = RecordingSendQueue()) -> (JournalImporter, NSManagedObjectContext) {
        let ctx = container.newBackgroundContext()
        ctx.transactionAuthor = JournalSyncAuthor.sync
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        keptContexts.append(ctx)
        let imp = JournalImporter(context: ctx, store: store, customOwner: "local:TEST")
        imp.queue = queue
        return (imp, ctx)
    }

    @discardableResult
    private func makeProfile(in ctx: NSManagedObjectContext) -> NSManagedObject {
        let p = NSEntityDescription.insertNewObject(forEntityName: "Profile", into: ctx)
        p.setValue(UUID(), forKey: "id")
        p.setValue("Sam", forKey: "name")
        p.setValue("Cello", forKey: "primaryInstrument")
        return p
    }

    @discardableResult
    private func makeInstrument(in ctx: NSManagedObjectContext, id: UUID = UUID(), name: String, profile: NSManagedObject?) -> NSManagedObject {
        let i = NSEntityDescription.insertNewObject(forEntityName: "Instrument", into: ctx)
        i.setValue(id, forKey: "id")
        i.setValue(name, forKey: "name")
        i.setValue(profile, forKey: "profile")
        return i
    }

    @discardableResult
    private func makeSession(in ctx: NSManagedObjectContext, id: UUID = UUID(), instrument: NSManagedObject?) -> NSManagedObject {
        let s = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        s.setValue(id, forKey: "id")
        s.setValue("T", forKey: "title")
        s.setValue(Date(), forKey: "timestamp")
        s.setValue(instrument, forKey: "instrument")
        return s
    }

    private func instrumentRecord(id: UUID, name: String) -> CKRecord {
        let r = CKRecord(recordType: "Instrument", recordID: JournalRecordMapping.recordID(for: id))
        r["name"] = name as CKRecordValue
        return r
    }

    private func sessionRecord(id: UUID, instrumentID: UUID?, instrumentName: String?, modified: Date = Date()) -> CKRecord {
        let r = CKRecord(recordType: "Session", recordID: JournalRecordMapping.recordID(for: id))
        r["title"] = "T" as CKRecordValue
        r["timestamp"] = Date() as CKRecordValue
        r["userModifiedAt"] = modified as CKRecordValue
        if let instrumentID { r["instrumentRef"] = CKRecord.Reference(recordID: JournalRecordMapping.recordID(for: instrumentID), action: .none) }
        r["instrumentName"] = instrumentName.map { $0 as CKRecordValue }
        return r
    }

    private func all(_ entity: String) -> [NSManagedObject] {
        let ctx = container.newBackgroundContext()
        keptContexts.append(ctx)
        var out: [NSManagedObject] = []
        ctx.performAndWait { out = (try? ctx.fetch(NSFetchRequest<NSManagedObject>(entityName: entity))) ?? [] }
        return out
    }

    private func value(_ o: NSManagedObject, _ key: String) -> Any? {
        var v: Any?
        o.managedObjectContext?.performAndWait { v = o.value(forKey: key) }
        return v
    }

    private func sessionInstrumentID(_ sessionID: UUID) -> UUID? {
        let s = all("Session").first { value($0, "id") as? UUID == sessionID }
        guard let s else { return nil }
        var id: UUID?
        s.managedObjectContext?.performAndWait { id = (s.value(forKey: "instrument") as? NSManagedObject)?.value(forKey: "id") as? UUID }
        return id
    }

    // MARK: records

    func testSessionAndCustomInstrumentRecordsCarryTheInstrumentLink() throws {
        let ctx = container.viewContext
        let profile = makeProfile(in: ctx)
        let cello = makeInstrument(in: ctx, name: "Cello", profile: profile)
        let s = makeSession(in: ctx, instrument: cello)
        try ctx.save()
        let sr = try XCTUnwrap(JournalRecordMapping.record(for: s, base: nil))
        XCTAssertEqual(JournalRecordMapping.instrumentLink(of: sr).recordName, (cello.value(forKey: "id") as! UUID).uuidString)
        XCTAssertEqual(JournalRecordMapping.instrumentLink(of: sr).name, "Cello")
        let ir = try XCTUnwrap(JournalRecordMapping.record(for: cello, base: nil))
        XCTAssertEqual(ir.recordType, "Instrument")
        XCTAssertEqual(ir["name"] as? String, "Cello")
        let none = makeSession(in: ctx, instrument: nil)
        let nr = try XCTUnwrap(JournalRecordMapping.record(for: none, base: nil))
        XCTAssertNil(JournalRecordMapping.instrumentLink(of: nr).recordName)
    }

    // MARK: resolution

    func testSameNamedInstrumentOnBothDevicesIsAliasedNotDuplicated() throws {
        let ctx = container.viewContext
        let profile = makeProfile(in: ctx)
        let localID = UUID()
        makeInstrument(in: ctx, id: localID, name: "cello", profile: profile)
        try ctx.save()
        let remoteID = UUID()
        let sessionID = UUID()
        let (imp, ictx) = importer()
        ictx.performAndWait { _ = imp.importModifications([instrumentRecord(id: remoteID, name: "Cello"), sessionRecord(id: sessionID, instrumentID: remoteID, instrumentName: "Cello")]) }

        XCTAssertEqual(all("Instrument").count, 1, "no second Cello")
        XCTAssertEqual(store.state.instrumentAliases[remoteID.uuidString], localID.uuidString)
        XCTAssertEqual(sessionInstrumentID(sessionID), localID, "the session points at this device's Cello")

        // A rename on the other device reaches the aliased row.
        ictx.performAndWait { _ = imp.importModifications([instrumentRecord(id: remoteID, name: "Violoncello")]) }
        XCTAssertEqual(all("Instrument").compactMap { value($0, "name") as? String }, ["Violoncello"])
    }

    func testUnknownInstrumentIsCreatedUnderTheLocalProfileAndRepeatsDoNotDuplicate() throws {
        let ctx = container.viewContext
        makeProfile(in: ctx)
        try ctx.save()
        let violaID = UUID(), oudID = UUID(), s1 = UUID(), s2 = UUID()
        let (imp, ictx) = importer()
        // A session whose Instrument record has not arrived resolves by name and creates the row with the referenced id.
        ictx.performAndWait { _ = imp.importModifications([sessionRecord(id: s1, instrumentID: violaID, instrumentName: "Viola")]) }
        XCTAssertEqual(sessionInstrumentID(s1), violaID)
        // The Instrument record itself, later, is the same row; a plain new instrument is created with its id.
        ictx.performAndWait { _ = imp.importModifications([instrumentRecord(id: violaID, name: "Viola"), instrumentRecord(id: oudID, name: "Oud"),
                                                           sessionRecord(id: s2, instrumentID: oudID, instrumentName: "Oud")]) }
        ictx.performAndWait { _ = imp.importModifications([instrumentRecord(id: violaID, name: "Viola"), instrumentRecord(id: oudID, name: "Oud")]) }
        let instruments = all("Instrument")
        XCTAssertEqual(Set(instruments.compactMap { value($0, "id") as? UUID }), [violaID, oudID])
        for i in instruments {
            var hasProfile = false
            i.managedObjectContext?.performAndWait { hasProfile = i.value(forKey: "profile") != nil }
            XCTAssertTrue(hasProfile, "attached to the local profile, so the profile's instrument list and the editor's picker show it")
        }
        XCTAssertEqual(sessionInstrumentID(s2), oudID)
        XCTAssertTrue(store.state.instrumentAliases.isEmpty)
    }

    func testSessionWithoutAnInstrumentStaysWithout() throws {
        let ctx = container.viewContext
        makeProfile(in: ctx)
        try ctx.save()
        let sid = UUID()
        let (imp, ictx) = importer()
        ictx.performAndWait { _ = imp.importModifications([sessionRecord(id: sid, instrumentID: nil, instrumentName: nil)]) }
        XCTAssertNil(sessionInstrumentID(sid))
        XCTAssertTrue(all("Instrument").isEmpty)
    }

    func testServerWinsAConflictAndTheInstrumentLinkFollows() throws {
        let ctx = container.viewContext
        let profile = makeProfile(in: ctx)
        let cello = makeInstrument(in: ctx, name: "Cello", profile: profile)
        let sid = UUID()
        makeSession(in: ctx, id: sid, instrument: cello)
        try ctx.save()
        // Local stamp older than the server's, with a pending save.
        let (imp, ictx) = importer()
        ictx.performAndWait {
            let r = NSFetchRequest<NSManagedObject>(entityName: "Session"); r.predicate = NSPredicate(format: "id == %@", sid as CVarArg)
            (try? ictx.fetch(r))?.first?.setValue(Date(timeIntervalSince1970: 1_700_000_000), forKey: "userModifiedAt"); try? ictx.save()
        }
        store.update { $0.outbox.append(.init(recordName: sid.uuidString, recordType: "Session", op: .save)) }
        let violaID = UUID()
        ictx.performAndWait { _ = imp.importModifications([sessionRecord(id: sid, instrumentID: violaID, instrumentName: "Viola", modified: Date())]) }
        XCTAssertEqual(sessionInstrumentID(sid), violaID, "the other device changed the instrument; server content won")
        XCTAssertEqual(all("Instrument").count, 2)
    }

    // MARK: deletions

    func testInstrumentDeletionReachesTheOutboxAndAnAliasedRowIsNotDeleted() throws {
        let ctx = container.viewContext
        let profile = makeProfile(in: ctx)
        let id = UUID()
        let inst = makeInstrument(in: ctx, id: id, name: "Harp", profile: profile)
        try ctx.save()
        let tracker = JournalChangeTracker(container: container, store: store)
        XCTAssertEqual(tracker.bootstrapCustomsIfNeeded(customOwner: "local:TEST"), 1, "profile instruments are queued at bootstrap")
        tracker.processHistory()
        store.update { $0.outbox.removeAll() }
        ctx.delete(inst)
        try ctx.save()
        XCTAssertEqual(tracker.processHistory(), [.init(recordName: id.uuidString, recordType: "Instrument", op: .delete)])

        // An aliased row of this device's own survives the other device deleting its twin.
        let localID = UUID(), remoteID = UUID()
        makeInstrument(in: ctx, id: localID, name: "Cello", profile: profile)
        try ctx.save()
        let (imp, ictx) = importer()
        ictx.performAndWait { _ = imp.importModifications([instrumentRecord(id: remoteID, name: "cello")]) }
        XCTAssertEqual(store.state.instrumentAliases[remoteID.uuidString], localID.uuidString)
        ictx.performAndWait { imp.importDeletions([(JournalRecordMapping.recordID(for: remoteID), "Instrument")]) }
        XCTAssertEqual(all("Instrument").compactMap { value($0, "id") as? UUID }, [localID])
        XCTAssertNil(store.state.instrumentAliases[remoteID.uuidString])
    }

    func testUpgradeOfAnExistingStoreSendsInstrumentsAndLinkedSessionsOnce() throws {
        let ctx = container.viewContext
        let profile = makeProfile(in: ctx)
        let cello = makeInstrument(in: ctx, name: "Cello", profile: profile)
        let linked = makeSession(in: ctx, instrument: cello)
        makeSession(in: ctx, instrument: nil)
        try ctx.save()
        let tracker = JournalChangeTracker(container: container, store: store)
        tracker.bootstrapIfNeeded()                       // the stage-B upload of sessions
        store.update { $0.customsBootstrapQueued = true; $0.outbox.removeAll() }   // as a stage-B store is
        XCTAssertEqual(tracker.bootstrapCustomsIfNeeded(customOwner: "local:TEST"), 2)
        XCTAssertEqual(Set(store.state.outbox.map(\.recordName)),
                       [(cello.value(forKey: "id") as! UUID).uuidString, (linked.value(forKey: "id") as! UUID).uuidString],
                       "the instrument, and only the session that has one")
        XCTAssertEqual(tracker.bootstrapCustomsIfNeeded(customOwner: "local:TEST"), 0, "once")
    }

    // MARK: outgoing records read fresh

    func testAnEditToASyncedSessionIsReadFreshForSending() throws {
        let ctx = container.viewContext
        makeProfile(in: ctx)
        try ctx.save()
        let sid = UUID()
        let (imp, ictx) = importer()
        var record = sessionRecord(id: sid, instrumentID: nil, instrumentName: nil)
        record["notes"] = "as imported" as CKRecordValue
        ictx.performAndWait { _ = imp.importModifications([record]) }
        // The person edits the imported session in the app's context.
        let r = NSFetchRequest<NSManagedObject>(entityName: "Session"); r.predicate = NSPredicate(format: "id == %@", sid as CVarArg)
        let s = try XCTUnwrap(try ctx.fetch(r).first)
        s.setValue("edited here", forKey: "notes")
        try ctx.save()
        var stale: String?, fresh: String?
        ictx.performAndWait {
            stale = imp.fetch(entity: "Session", id: sid)?.value(forKey: "notes") as? String
            fresh = imp.freshObject(entity: "Session", id: sid)?.value(forKey: "notes") as? String
        }
        XCTAssertEqual(fresh, "edited here", "the outgoing record carries the edit")
        _ = stale  // whatever the cache held; the engine no longer reads it
        record = try XCTUnwrap(ictx.performAndWait { imp.freshObject(entity: "Session", id: sid).flatMap { JournalRecordMapping.record(for: $0, base: nil) } })
        XCTAssertEqual(record["notes"] as? String, "edited here")
    }

    // MARK: start retry

    func testStartRetryBackoff() {
        XCTAssertEqual([1, 2, 3, 4, 5, 6, 20].map(JournalSyncStartRetry.delay(attempt:)), [5, 10, 20, 40, 60, 60, 60])
    }
}
#endif
