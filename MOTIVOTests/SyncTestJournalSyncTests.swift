//
//  SyncTestJournalSyncTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  The repeatable, network-free half of Checkpoint 1: history-driven change
//  tracking across contexts (including a background deletion with a preserved
//  id), outbox/token durability, the merge and conflict rules, the record
//  mapping round trip, and the user-edit stamp skipping the import author.
//

#if SYNCTEST
import XCTest
import CoreData
import CloudKit
@testable import Etudes

final class SyncTestJournalSyncTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var store: JournalSyncStateStore!
    private var tempDir: URL!
    private var stamp: NSObjectProtocol?

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // The app's model, loaded from the test host bundle as the app itself does.
        container = NSPersistentContainer(name: "MOTIVO")
        let description = NSPersistentStoreDescription(url: tempDir.appendingPathComponent("store.sqlite"))
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        try XCTUnwrap(loadError == nil ? () : nil, "store failed to load: \(String(describing: loadError))")
        container.viewContext.transactionAuthor = JournalSyncAuthor.app
        store = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("state.json"))
        stamp = JournalUserEditStamp.install()
    }

    override func tearDownWithError() throws {
        if let stamp { NotificationCenter.default.removeObserver(stamp) }
        container = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: helpers

    @discardableResult
    private func makeSession(in ctx: NSManagedObjectContext, title: String = "T") -> NSManagedObject {
        let s = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        s.setValue(UUID(), forKey: "id")
        s.setValue(title, forKey: "title")
        s.setValue(Date(), forKey: "timestamp")
        return s
    }

    @discardableResult
    private func makeAttachment(in ctx: NSManagedObject, context: NSManagedObjectContext, fileURL: String) -> NSManagedObject {
        let a = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: context)
        a.setValue(UUID(), forKey: "id")
        a.setValue("image", forKey: "kind")
        a.setValue(Date(), forKey: "createdAt")
        a.setValue(fileURL, forKey: "fileURL")
        a.setValue(ctx, forKey: "session")
        return a
    }

    // MARK: change tracking

    func testBootstrapQueuesExistingRowsOnceAndAdvancesToken() throws {
        let ctx = container.viewContext
        let s = makeSession(in: ctx)
        makeAttachment(in: s, context: ctx, fileURL: "/tmp/x.jpg")
        try ctx.save()

        let tracker = JournalChangeTracker(container: container, store: store)
        XCTAssertEqual(tracker.bootstrapIfNeeded(), 2)
        XCTAssertTrue(store.state.bootstrapQueued)
        XCTAssertEqual(store.state.outbox.count, 2)
        XCTAssertEqual(tracker.bootstrapIfNeeded(), 0, "bootstrap runs once")
        // The pre-bootstrap save is NOT replayed by history (token captured before enumeration covers it).
        XCTAssertEqual(tracker.processHistory().count, 0)
    }

    func testModelPreservesIDsInHistoryTombstones() throws {
        let model = container.managedObjectModel
        for entity in ["Session", "Attachment"] {
            let attribute = try XCTUnwrap(model.entitiesByName[entity]?.attributesByName["id"])
            XCTAssertTrue(attribute.preservesValueInHistoryOnDeletion, "\(entity).id must be preserved after deletion (V11)")
        }
    }

    func testHistoryCapturesInsertUpdateAndBackgroundDeletionWithPreservedID() throws {
        let tracker = JournalChangeTracker(container: container, store: store)
        tracker.bootstrapIfNeeded()

        let ctx = container.viewContext
        let s = makeSession(in: ctx, title: "First")
        let sid = s.value(forKey: "id") as! UUID
        try ctx.save()
        var added = tracker.processHistory()
        XCTAssertEqual(added, [.init(recordName: sid.uuidString, recordType: "Session", op: .save)])
        XCTAssertNotNil(store.state.userModifiedAt(for: s), "stamp applied on insert")

        s.setValue("Second", forKey: "title")
        try ctx.save()
        added = tracker.processHistory()
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(store.state.outbox.count, 1, "save merged, not duplicated")

        // Deletion from a BACKGROUND context with no author: still a local change.
        let bg = container.newBackgroundContext()
        bg.performAndWait {
            let req = NSFetchRequest<NSManagedObject>(entityName: "Session")
            req.predicate = NSPredicate(format: "id == %@", sid as CVarArg)
            let obj = try! bg.fetch(req).first!
            bg.delete(obj)
            try! bg.save()
        }
        added = tracker.processHistory()
        XCTAssertEqual(added, [.init(recordName: sid.uuidString, recordType: "Session", op: .delete)],
                       "tombstone carries the preserved id")
        XCTAssertEqual(store.state.outbox, [.init(recordName: sid.uuidString, recordType: "Session", op: .delete)],
                       "delete supersedes the pending save")
    }

    func testImportAuthorIsExcludedAndNotStamped() throws {
        let tracker = JournalChangeTracker(container: container, store: store)
        tracker.bootstrapIfNeeded()
        let imp = container.newBackgroundContext()
        imp.transactionAuthor = JournalSyncAuthor.sync
        var stamped: Date?
        imp.performAndWait {
            let s = makeSession(in: imp)
            let serverDate = Date(timeIntervalSince1970: 1_000)
            s.setValue(serverDate, forKey: "userModifiedAt")
            try! imp.save()
            stamped = s.value(forKey: "userModifiedAt") as? Date
        }
        XCTAssertEqual(stamped, Date(timeIntervalSince1970: 1_000), "server stamp kept as-is")
        XCTAssertEqual(tracker.processHistory().count, 0, "imports never enter the outbox")
    }

    func testOutboxAndTokenAdvanceTogetherOrNotAtAll() throws {
        let tracker = JournalChangeTracker(container: container, store: store)
        tracker.bootstrapIfNeeded()
        let tokenBefore = store.state.historyToken
        let ctx = container.viewContext
        makeSession(in: ctx)
        try ctx.save()

        // Make the state file unwritable: a directory in its place.
        try FileManager.default.removeItem(at: store.fileURL)
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: false)
        XCTAssertEqual(tracker.processHistory().count, 0, "nothing reported when the write fails")
        XCTAssertEqual(store.state.historyToken, tokenBefore, "token did not advance")
        XCTAssertEqual(store.state.outbox.count, 0)

        try FileManager.default.removeItem(at: store.fileURL)
        XCTAssertEqual(tracker.processHistory().count, 1, "the change is still there to pick up")
        XCTAssertNotEqual(store.state.historyToken, tokenBefore)
        // And it is durable: a fresh store instance reads it back.
        let reread = JournalSyncStateStore(fileURL: store.fileURL)
        XCTAssertEqual(reread.state.outbox.count, 1)
    }

    // MARK: rules

    func testMergeRules() {
        var outbox: [JournalSyncPendingChange] = []
        let a = JournalSyncPendingChange(recordName: "A", recordType: "Session", op: .save)
        JournalChangeTracker.merge([a, a], into: &outbox)
        XCTAssertEqual(outbox, [a])
        JournalChangeTracker.merge([.init(recordName: "A", recordType: "Session", op: .delete)], into: &outbox)
        XCTAssertEqual(outbox, [.init(recordName: "A", recordType: "Session", op: .delete)])
    }

    func testConflictRuleNewestUserEditWinsTiesAndMissingGoToServer() {
        let t1 = Date(timeIntervalSince1970: 100), t2 = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(JournalConflictRule.decide(localUserModifiedAt: t2, serverUserModifiedAt: t1), .local)
        XCTAssertEqual(JournalConflictRule.decide(localUserModifiedAt: t1, serverUserModifiedAt: t2), .server)
        XCTAssertEqual(JournalConflictRule.decide(localUserModifiedAt: t1, serverUserModifiedAt: t1), .server)
        XCTAssertEqual(JournalConflictRule.decide(localUserModifiedAt: nil, serverUserModifiedAt: nil), .server)
        XCTAssertEqual(JournalConflictRule.decide(localUserModifiedAt: t1, serverUserModifiedAt: nil), .local)
    }

    // MARK: mapping

    func testSessionAndAttachmentRoundTripThroughRecords() throws {
        let ctx = container.viewContext
        let file = tempDir.appendingPathComponent("photo.jpg")
        try Data([1, 2, 3]).write(to: file)
        let s = makeSession(in: ctx, title: "Round trip")
        s.setValue("notes here", forKey: "notes")
        s.setValue("Cello", forKey: "userInstrumentLabel")
        s.setValue(Int64(1234), forKey: "durationSeconds")
        let a = makeAttachment(in: s, context: ctx, fileURL: file.path)
        try ctx.save()

        let sRecord = try XCTUnwrap(JournalRecordMapping.record(for: s, base: nil))
        let aRecord = try XCTUnwrap(JournalRecordMapping.record(for: a, base: nil))
        XCTAssertEqual(sRecord.recordType, "Session")
        XCTAssertEqual(sRecord.recordID.recordName, (s.value(forKey: "id") as! UUID).uuidString)
        XCTAssertEqual(sRecord["title"] as? String, "Round trip")
        XCTAssertEqual((sRecord["durationSeconds"] as? NSNumber)?.int64Value, 1234)
        XCTAssertNotNil(sRecord["userModifiedAt"] as? Date)
        XCTAssertEqual(JournalRecordMapping.sessionRecordName(of: aRecord), sRecord.recordID.recordName)
        XCTAssertEqual((aRecord["file"] as? CKAsset)?.fileURL?.path, file.path)
        XCTAssertEqual(aRecord["fileExt"] as? String, "jpg")

        // Apply onto fresh objects in another context, as an import would.
        let imp = container.newBackgroundContext()
        imp.transactionAuthor = JournalSyncAuthor.sync
        try imp.performAndWait {
            let s2 = NSEntityDescription.insertNewObject(forEntityName: "Session", into: imp)
            XCTAssertTrue(JournalRecordMapping.apply(sRecord, to: s2))
            XCTAssertEqual(s2.value(forKey: "id") as? UUID, s.value(forKey: "id") as? UUID)
            XCTAssertEqual(s2.value(forKey: "title") as? String, "Round trip")
            XCTAssertEqual(s2.value(forKey: "notes") as? String, "notes here")
            XCTAssertEqual(s2.value(forKey: "userInstrumentLabel") as? String, "Cello")
            XCTAssertEqual(s2.value(forKey: "durationSeconds") as? Int64, 1234)
            let a2 = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: imp)
            XCTAssertTrue(JournalRecordMapping.apply(aRecord, to: a2))
            XCTAssertEqual(a2.value(forKey: "kind") as? String, "image")
            a2.setValue(s2, forKey: "session")
            XCTAssertNoThrow(try imp.save(), "all non-optional attributes satisfied")
        }

        // Materialised path follows the editor's <id>.<ext> convention the resolver finds.
        let url = JournalRecordMapping.materialisedURL(recordName: aRecord.recordID.recordName, ext: "jpg")
        XCTAssertEqual(url.lastPathComponent, "\(aRecord.recordID.recordName).jpg")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Documents")
    }

    func testSystemFieldsSurviveEncoding() throws {
        let record = CKRecord(recordType: "Session", recordID: JournalRecordMapping.recordID(for: UUID()))
        record["title"] = "x" as CKRecordValue
        let data = JournalSyncStateStore.encodeSystemFields(record)
        let back = try XCTUnwrap(JournalSyncStateStore.recordFromSystemFields(data))
        XCTAssertEqual(back.recordID, record.recordID)
        XCTAssertNil(back["title"], "system fields only")
        let whole = try XCTUnwrap(JournalSyncStateStore.encodeWholeRecord(record))
        XCTAssertEqual(JournalSyncStateStore.decodeWholeRecord(whole)?["title"] as? String, "x")
    }
}

private extension JournalSyncPersistedState {
    func userModifiedAt(for object: NSManagedObject) -> Date? { object.value(forKey: "userModifiedAt") as? Date }
}
#endif
