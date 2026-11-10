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
        XCTAssertEqual(tracker.bootstrapIfNeeded(), 3, "session, attachment and its meta record (stage G)")
        XCTAssertTrue(store.state.bootstrapQueued)
        XCTAssertEqual(store.state.outbox.count, 3)
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

    // MARK: C-174: one send in flight

    func testSendGateRunsOneSendAtATimeAndOneFollowUpForRequestsMadeMeanwhile() {
        var gate = JournalSendGate()
        XCTAssertTrue(gate.enter(), "nothing in flight: send now")
        XCTAssertFalse(gate.enter(), "a second request while sending is kept, not run")
        XCTAssertFalse(gate.enter(), "and a third adds nothing")
        XCTAssertTrue(gate.leave(), "the send finished: the kept request runs once")
        XCTAssertTrue(gate.enter(), "that follow-up is the one in flight now")
        XCTAssertFalse(gate.leave(), "nothing was asked for meanwhile: no further send")
        XCTAssertFalse(gate.inFlight)
    }

    // MARK: C-190: a kept send request is recorded, and nothing else changes

    func testAKeptSendRequestIsRecordedWithItsTimingAndTheGateDecidesAsBefore() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        // The gate's answers are those of the test above, with or without a time.
        var gate = JournalSendGate()
        XCTAssertTrue(gate.enter(now: t0))
        XCTAssertEqual(gate.inFlightSince, t0, "the send in flight began now")
        XCTAssertEqual(gate.keptDuringFlight, 0)
        XCTAssertFalse(gate.enter(now: t0 + 240), "asked for 4 minutes into the upload: kept, not run")
        XCTAssertEqual(gate.keptDuringFlight, 1)
        XCTAssertEqual(gate.inFlightSince, t0, "the kept request does not restart the clock")
        XCTAssertFalse(gate.enter(now: t0 + 300))
        XCTAssertEqual(gate.keptDuringFlight, 2, "each kept request is counted")
        XCTAssertTrue(gate.queued)
        XCTAssertTrue(gate.leave(), "still exactly one follow-up, however many were kept")
        XCTAssertNil(gate.inFlightSince)
        XCTAssertFalse(gate.inFlight)
        XCTAssertTrue(gate.enter(now: t0 + 600))
        XCTAssertEqual(gate.keptDuringFlight, 0, "the count belongs to one send")
        XCTAssertEqual(gate.inFlightSince, t0 + 600)
        XCTAssertFalse(gate.leave())

        // What the device run reads: the time into the send, who asked, what waited.
        let deferred = JournalDeferredSend(trigger: "local change, foreground or activation", activeFor: 240.04, ordinal: 1, outbox: 5, attachmentsInOutbox: 4)
        XCTAssertEqual(deferred.logText,
                       "Send asked for (local change, foreground or activation) while one has been in flight for 240.0 s: kept, runs once after it (kept request 1 of this send; outbox 5, 4 attachment record(s))")
        XCTAssertEqual(JournalDeferredSend.ranText(kept: 2, flightLasted: 611.26),
                       "Kept send request runs now: the send before it was in flight for 611.3 s and 2 request(s) were kept meanwhile")

        // Recording counts it in the state file and writes one line; the
        // outbox and everything else in the file are as they were.
        let pending = JournalSyncPendingChange(recordName: "att-1", recordType: JournalSyncRecordType.attachment, op: .save)
        store.update { $0.outbox = [pending]; $0.recordsSent = 7 }
        let before = store.state
        XCTAssertEqual(before.sendRequestsDeferred, 0)
        JournalDeferredSend.record(deferred, in: store)
        JournalDeferredSend.record(JournalDeferredSend(trigger: "poll or push", activeFor: 300, ordinal: 2, outbox: 6, attachmentsInOutbox: 4), in: store)
        let after = store.state
        XCTAssertEqual(after.sendRequestsDeferred, 2)
        XCTAssertEqual(after.log.count, before.log.count + 2)
        XCTAssertEqual(after.log.suffix(2).first?.text, deferred.logText)
        XCTAssertEqual(after.outbox, before.outbox, "the observation queues and removes nothing")
        XCTAssertEqual(after.recordsSent, before.recordsSent)
        XCTAssertEqual(after.outboxSequence, before.outboxSequence)

        // The count survives a relaunch, and a state file written before the
        // field existed reads as zero.
        let reloaded = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("state.json"))
        XCTAssertEqual(reloaded.state.sendRequestsDeferred, 2)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: tempDir.appendingPathComponent("state.json"))) as? [String: Any])
        XCTAssertNotNil(object.removeValue(forKey: "sendRequestsDeferred"), "the count is in the file a trial reads over the cable")
        let olderURL = tempDir.appendingPathComponent("state-before-c190.json")
        try JSONSerialization.data(withJSONObject: object).write(to: olderURL)
        let older = JournalSyncStateStore(fileURL: olderURL)
        XCTAssertEqual(older.state.sendRequestsDeferred, 0)
        XCTAssertEqual(older.state.outbox, [pending], "and the rest of an older file loads as before")
    }

}

private extension JournalSyncPersistedState {
    func userModifiedAt(for object: NSManagedObject) -> Date? { object.value(forKey: "userModifiedAt") as? Date }
}
#endif
