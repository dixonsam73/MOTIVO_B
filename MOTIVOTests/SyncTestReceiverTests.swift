//
//  SyncTestReceiverTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  Stage G: a metadata edit queues only the small meta record; a content
//  change queues the content record; a no-op write is not an edit; the
//  editor's thumbnail pass touches nothing that did not change; meta records
//  arrive before or after their attachment; legacy metadata on an old content
//  record counts only until a meta record is known; deletions cover both
//  records; the catch-up fetches a file only when this device lacks it.
//

#if SYNCTEST
import XCTest
import CoreData
import CloudKit
@testable import Etudes

final class SyncTestReceiverTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var store: JournalSyncStateStore!
    private var tempDir: URL!
    private var stamp: NSObjectProtocol?
    private var keptContexts: [NSManagedObjectContext] = []

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-g-\(UUID().uuidString)", isDirectory: true)
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
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        store = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("state.json"))
        stamp = JournalUserEditStamp.install()
        JournalMetadataMirror.container = container
    }

    override func tearDownWithError() throws {
        if let stamp { NotificationCenter.default.removeObserver(stamp) }
        JournalMetadataMirror.container = nil
        keptContexts.removeAll()
        container = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: helpers

    @discardableResult
    private func makeSession(in ctx: NSManagedObjectContext, id: UUID = UUID()) -> NSManagedObject {
        let s = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        s.setValue(id, forKey: "id"); s.setValue("T", forKey: "title"); s.setValue(Date(), forKey: "timestamp")
        return s
    }

    @discardableResult
    private func makeAttachment(session: NSManagedObject, in ctx: NSManagedObjectContext, id: UUID = UUID(), kind: String = "audio",
                                fileURL: String? = nil, thumbnail: Bool = false) -> NSManagedObject {
        let a = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: ctx)
        a.setValue(id, forKey: "id"); a.setValue(kind, forKey: "kind"); a.setValue(Date(), forKey: "createdAt")
        a.setValue(fileURL ?? "/tmp/\(id.uuidString).m4a", forKey: "fileURL"); a.setValue(session, forKey: "session")
        a.setValue(thumbnail, forKey: "isThumbnail")
        return a
    }

    private func importer(_ queue: RecordingSendQueue = RecordingSendQueue()) -> (JournalImporter, NSManagedObjectContext) {
        let ctx = container.newBackgroundContext()
        ctx.transactionAuthor = JournalSyncAuthor.sync
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        keptContexts.append(ctx)
        let imp = JournalImporter(context: ctx, store: store, customOwner: "local:TEST")
        imp.queue = queue
        return (imp, ctx)
    }

    private func attachmentRecord(id: UUID, sessionID: UUID, kind: String = "audio", legacyName: String? = nil, legacyPrivate: Bool? = nil,
                                  stamp: Date = Date(timeIntervalSince1970: 1_000)) -> CKRecord {
        let r = CKRecord(recordType: "Attachment", recordID: JournalRecordMapping.recordID(for: id))
        r["kind"] = kind as CKRecordValue; r["createdAt"] = Date() as CKRecordValue; r["userModifiedAt"] = stamp as CKRecordValue
        r["fileExt"] = "m4a" as CKRecordValue
        r[JournalRecordMapping.sessionRefKey] = CKRecord.Reference(recordID: JournalRecordMapping.recordID(for: sessionID), action: .none)
        if let legacyName { r["displayName"] = legacyName as CKRecordValue }
        if let legacyPrivate { r[JournalMetadataKeys.isPrivate] = NSNumber(value: legacyPrivate) }
        return r
    }

    private func metaRecord(id: UUID, name: String?, star: Bool = false, isPrivate: Bool? = nil, pages: String = "[]",
                            stamp: Date = Date(timeIntervalSince1970: 2_000)) -> CKRecord {
        let r = CKRecord(recordType: JournalSyncRecordType.attachmentMeta,
                         recordID: CKRecord.ID(recordName: JournalSyncRecordType.metaName(for: id.uuidString), zoneID: JournalRecordMapping.zoneID))
        if let name { r["displayName"] = name as CKRecordValue }
        r["isThumbnail"] = NSNumber(value: star); r["userModifiedAt"] = stamp as CKRecordValue
        if let isPrivate { r[JournalMetadataKeys.isPrivate] = NSNumber(value: isPrivate) }
        r[JournalMetadataKeys.selectedPages] = pages as CKRecordValue
        return r
    }

    private func wait(for condition: @escaping () -> Bool, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertTrue(condition(), "condition not met within \(timeout)s")
    }

    private func pending(_ name: String) -> JournalSyncPendingChange? { store.state.outbox.first { $0.recordName == name } }

    // MARK: which record a change queues

    func testRenameQueuesOnlyTheMetaRecordAndAFileChangeQueuesTheContentRecord() throws {
        let ctx = container.viewContext
        let s = makeSession(in: ctx)
        let a = makeAttachment(session: s, in: ctx)
        try ctx.save()
        let aid = (a.value(forKey: "id") as! UUID).uuidString
        let meta = JournalSyncRecordType.metaName(for: aid)
        let tracker = JournalChangeTracker(container: container, store: store)
        XCTAssertEqual(tracker.bootstrapIfNeeded(), 3, "session, attachment and its meta record")
        store.update { $0.outbox.removeAll() }

        a.setValue("New name", forKey: "displayName")
        try ctx.save()
        tracker.processHistory()
        XCTAssertNotNil(pending(meta)); XCTAssertNil(pending(aid), "a rename never queues the content record")
        XCTAssertTrue(pending(meta)!.metadataEdit)
        store.update { $0.outbox.removeAll() }

        a.setValue("/tmp/replaced.m4a", forKey: "fileURL")
        try ctx.save()
        tracker.processHistory()
        XCTAssertNotNil(pending(aid), "a replaced file queues the content record")
        XCTAssertFalse(pending(aid)!.assetFree)
        XCTAssertNotNil(pending(meta), "…and the meta record, whose stamp moved (small)")
        store.update { $0.outbox.removeAll() }

        // A privacy touch (metadata author, stamp only) → meta only.
        AttachmentPrivacy.setPrivate(id: UUID(uuidString: aid), url: nil, true)
        wait(for: { tracker.processHistory(); return self.pending(meta) != nil })
        XCTAssertNil(pending(aid))

        // Deletion queues both.
        ctx.delete(a); try ctx.save()
        tracker.processHistory()
        XCTAssertEqual(pending(aid)?.op, .delete); XCTAssertEqual(pending(meta)?.op, .delete)
    }

    func testANoOpWriteIsNotAnEditAndTheThumbnailPassTouchesOnlyChangedRows() throws {
        let ctx = container.viewContext
        let s = makeSession(in: ctx)
        let a = makeAttachment(session: s, in: ctx, thumbnail: true)
        let b = makeAttachment(session: s, in: ctx)
        try ctx.save()
        let tracker = JournalChangeTracker(container: container, store: store)
        tracker.bootstrapIfNeeded(); store.update { $0.outbox.removeAll() }
        let stampA = a.value(forKey: "userModifiedAt") as? Date
        let aid = (a.value(forKey: "id") as! UUID)

        // Setting the value it already has.
        a.setValue(true, forKey: "isThumbnail"); b.setValue(false, forKey: "isThumbnail")
        try ctx.save()
        XCTAssertTrue(tracker.processHistory().isEmpty, "no-op writes leave no history")
        XCTAssertEqual(a.value(forKey: "userModifiedAt") as? Date, stampA, "and no stamp")

        // The editor's thumbnail pass with the same thumbnail: nothing queued.
        try ctx.performAndWait {
            AttachmentCommitService.applyThumbnailFlags(finalThumbnailID: aid, to: s as! Session, ctx: ctx)
            XCTAssertFalse(ctx.hasChanges, "only real changes are written")
            try ctx.save()
        }
        XCTAssertTrue(tracker.processHistory().isEmpty)

        // Moving the star is a real change on exactly the two rows involved, meta only.
        let bid = (b.value(forKey: "id") as! UUID)
        try ctx.performAndWait {
            AttachmentCommitService.applyThumbnailFlags(finalThumbnailID: bid, to: s as! Session, ctx: ctx)
            try ctx.save()
        }
        let added = tracker.processHistory()
        XCTAssertEqual(Set(added.map(\.recordName)), Set([JournalSyncRecordType.metaName(for: aid.uuidString), JournalSyncRecordType.metaName(for: bid.uuidString)]))
    }

    // MARK: records

    func testMetaRecordCarriesTheMetadataAndTheContentRecordDoesNot() throws {
        let ctx = container.viewContext
        let s = makeSession(in: ctx)
        let a = makeAttachment(session: s, in: ctx, thumbnail: true)
        a.setValue("Named", forKey: "displayName")
        try ctx.save()
        let aid = a.value(forKey: "id") as! UUID
        AttachmentPrivacy.setPrivate(id: aid, url: nil, false, mirror: false)
        PDFSelectedPagesStore.setPages([2], for: aid, mirror: false)
        defer { PDFSelectedPagesStore.setPages(nil, for: aid, mirror: false) }
        let meta = try XCTUnwrap(JournalRecordMapping.metaRecord(for: a, base: nil))
        XCTAssertEqual(meta.recordID.recordName, aid.uuidString + "-meta")
        XCTAssertEqual(meta["displayName"] as? String, "Named")
        XCTAssertEqual((meta["isThumbnail"] as? NSNumber)?.boolValue, true)
        XCTAssertEqual((meta[JournalMetadataKeys.isPrivate] as? NSNumber)?.boolValue, false)
        XCTAssertEqual(meta[JournalMetadataKeys.selectedPages] as? String, "[2]")
        XCTAssertNotNil(meta["userModifiedAt"])
        let content = try XCTUnwrap(JournalRecordMapping.record(for: a, base: nil))
        XCTAssertNil(content["displayName"]); XCTAssertNil(content[JournalMetadataKeys.isPrivate]); XCTAssertNil(content["isThumbnail"])
        XCTAssertEqual(content["kind"] as? String, "audio")
        XCTAssertFalse(JournalRecordMapping.keysWithoutAsset.contains(JournalRecordMapping.assetKey))
        XCTAssertTrue(JournalRecordMapping.keysWithoutAsset.contains("fileHash"))
    }

    // MARK: import, either order; legacy fields only until a meta record is known

    func testMetaBeforeAndAfterItsAttachmentAndLegacyFieldsStopCountingOnceMetaIsKnown() throws {
        let sid = UUID(), aid = UUID(), bid = UUID()
        let (imp, ctx) = importer()
        ctx.performAndWait { makeSession(in: ctx, id: sid); try? ctx.save() }

        // Meta first: held, then applied when the attachment lands.
        ctx.performAndWait { _ = imp.importAttachmentMeta(metaRecord(id: aid, name: "From meta", star: true, isPrivate: false)) }
        XCTAssertEqual(store.state.awaitingMeta.count, 1)
        ctx.performAndWait { _ = imp.importAttachment(attachmentRecord(id: aid, sessionID: sid, legacyName: "Stale legacy", legacyPrivate: true)); imp.save() }
        ctx.performAndWait {
            let a = imp.fetch(entity: "Attachment", id: aid)
            XCTAssertEqual(a?.value(forKey: "displayName") as? String, "From meta", "the held meta record wins over legacy fields")
            XCTAssertEqual(a?.value(forKey: "isThumbnail") as? Bool, true)
        }
        XCTAssertFalse(AttachmentPrivacy.isPrivate(id: aid, url: nil))
        XCTAssertTrue(store.state.awaitingMeta.isEmpty)

        // Attachment first with legacy fields (an older build's record): applied; then meta replaces.
        ctx.performAndWait { _ = imp.importAttachment(attachmentRecord(id: bid, sessionID: sid, legacyName: "Legacy name", legacyPrivate: true)); imp.save() }
        ctx.performAndWait { XCTAssertEqual(imp.fetch(entity: "Attachment", id: bid)?.value(forKey: "displayName") as? String, "Legacy name") }
        XCTAssertTrue(AttachmentPrivacy.isPrivate(id: bid, url: nil))
        ctx.performAndWait { _ = imp.importAttachmentMeta(metaRecord(id: bid, name: "Meta name", isPrivate: false)); imp.save() }
        // A later old-format content record for b no longer carries its legacy fields.
        ctx.performAndWait { _ = imp.importAttachment(attachmentRecord(id: bid, sessionID: sid, legacyName: "Stale again", legacyPrivate: true,
                                                                       stamp: Date(timeIntervalSince1970: 3_000))); imp.save() }
        ctx.performAndWait { XCTAssertEqual(imp.fetch(entity: "Attachment", id: bid)?.value(forKey: "displayName") as? String, "Meta name") }
        XCTAssertFalse(AttachmentPrivacy.isPrivate(id: bid, url: nil))

        // A meta record without displayName is no information.
        ctx.performAndWait { _ = imp.importAttachmentMeta(metaRecord(id: bid, name: nil, stamp: Date(timeIntervalSince1970: 4_000))); imp.save() }
        ctx.performAndWait { XCTAssertEqual(imp.fetch(entity: "Attachment", id: bid)?.value(forKey: "displayName") as? String, "Meta name") }
    }

    func testMetaConflictUsesTheAttachmentStampAndDeletionsCleanBothRecords() throws {
        let sid = UUID(), aid = UUID()
        let queue = RecordingSendQueue()
        let (imp, ctx) = importer(queue)
        ctx.performAndWait {
            let s = makeSession(in: ctx, id: sid)
            let a = makeAttachment(session: s, in: ctx, id: aid)
            a.setValue("Mine, newer", forKey: "displayName"); a.setValue(Date(timeIntervalSince1970: 9_000), forKey: "userModifiedAt")
            try? ctx.save()
        }
        let meta = JournalSyncRecordType.metaName(for: aid.uuidString)
        store.update { $0.outbox = [.init(recordName: meta, recordType: JournalSyncRecordType.attachmentMeta, op: .save, metadataEdit: true)] }
        var applied = true
        ctx.performAndWait { applied = imp.importAttachmentMeta(metaRecord(id: aid, name: "Theirs, older", stamp: Date(timeIntervalSince1970: 1_000))) }
        XCTAssertFalse(applied); XCTAssertTrue(queue.removed.isEmpty)
        ctx.performAndWait { XCTAssertEqual(imp.fetch(entity: "Attachment", id: aid)?.value(forKey: "displayName") as? String, "Mine, newer") }

        // Remote deletion of the attachment removes the row and forgets its meta.
        store.update { $0.lastKnownRecords[meta] = Data([1]); $0.awaitingMeta[meta] = Data([2]) }
        ctx.performAndWait { imp.importDeletions([(JournalRecordMapping.recordID(for: aid), JournalSyncRecordType.attachment)]) }
        ctx.performAndWait { XCTAssertNil(imp.fetch(entity: "Attachment", id: aid)) }
        XCTAssertNil(store.state.lastKnownRecords[meta]); XCTAssertNil(store.state.awaitingMeta[meta])
        XCTAssertTrue(store.state.outbox.isEmpty)
        // A meta deletion alone never deletes a row.
        let other = UUID()
        ctx.performAndWait { let s = imp.fetch(entity: "Session", id: sid)!; makeAttachment(session: s, in: ctx, id: other); try? ctx.save() }
        ctx.performAndWait { imp.importDeletions([(CKRecord.ID(recordName: JournalSyncRecordType.metaName(for: other.uuidString), zoneID: JournalRecordMapping.zoneID), JournalSyncRecordType.attachmentMeta)]) }
        ctx.performAndWait { XCTAssertNotNil(imp.fetch(entity: "Attachment", id: other)) }
    }

    // MARK: a path rewrite is not a content change

    func testAPathRewriteWithTheSameBytesQueuesNoContentRecord() throws {
        let ctx = container.viewContext
        let s = makeSession(in: ctx)
        let fileA = tempDir.appendingPathComponent("a.m4a"); try Data([1, 2, 3]).write(to: fileA)
        let a = makeAttachment(session: s, in: ctx, fileURL: fileA.path)
        try ctx.save()
        let aid = (a.value(forKey: "id") as! UUID).uuidString
        let meta = JournalSyncRecordType.metaName(for: aid)
        let tracker = JournalChangeTracker(container: container, store: store)
        tracker.bootstrapIfNeeded(); store.update { $0.outbox.removeAll() }
        // The server holds this file's hash.
        let hash = try XCTUnwrap(JournalAssetHash.hash(of: fileA))
        store.update { $0.assetHashes[aid] = hash }

        // Same bytes at another path (the container moved): meta only, since the stamp moved.
        let moved = tempDir.appendingPathComponent("moved.m4a"); try Data([1, 2, 3]).write(to: moved)
        a.setValue(moved.path, forKey: "fileURL"); try ctx.save()
        tracker.processHistory()
        XCTAssertNil(pending(aid), "no content record for a path rewrite")
        XCTAssertNotNil(pending(meta))
        store.update { $0.outbox.removeAll() }

        // Different bytes: a replacement, content record queued.
        let replaced = tempDir.appendingPathComponent("replaced.m4a"); try Data([9, 9, 9, 9]).write(to: replaced)
        a.setValue(replaced.path, forKey: "fileURL"); try ctx.save()
        tracker.processHistory()
        XCTAssertNotNil(pending(aid)); XCTAssertFalse(pending(aid)!.assetFree)
    }

    // MARK: own-write echo

    func testARecordWhoseChangeTagThisDeviceHoldsIsAnEcho() throws {
        let id = UUID()
        let record = CKRecord(recordType: "Attachment", recordID: JournalRecordMapping.recordID(for: id))
        // A record never saved has no change tag: never an echo.
        XCTAssertFalse(JournalEcho.isKnown(changeTag: record.recordChangeTag, storedSystemFields: JournalSyncStateStore.encodeSystemFields(record)))
        // Simulate a server-saved record by decoding system fields that carry a tag.
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        let stored = archiver.encodedData
        XCTAssertFalse(JournalEcho.isKnown(changeTag: "abc", storedSystemFields: stored), "a different (or missing) tag is new information")
        XCTAssertFalse(JournalEcho.isKnown(changeTag: "abc", storedSystemFields: nil))
    }

    // MARK: catch-up decisions

    func testCatchUpFetchesAFileOnlyWhenThisDeviceLacksIt() {
        XCTAssertFalse(JournalCatchUp.needsAsset(serverHash: "h", knownHash: "h", fileExists: true))
        XCTAssertFalse(JournalCatchUp.needsAsset(serverHash: nil, knownHash: nil, fileExists: true), "an old record with a file here")
        XCTAssertTrue(JournalCatchUp.needsAsset(serverHash: "h2", knownHash: "h", fileExists: true), "replaced on the other device")
        XCTAssertTrue(JournalCatchUp.needsAsset(serverHash: "h", knownHash: nil, fileExists: false))
        XCTAssertTrue(JournalCatchUp.needsAsset(serverHash: nil, knownHash: nil, fileExists: false))
    }
}
#endif
