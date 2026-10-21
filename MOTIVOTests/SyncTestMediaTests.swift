//
//  SyncTestMediaTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  Stage D: media travels only when its content changed (a metadata edit
//  sends the record alone), a replaced file is received and written into
//  place, transport downloads are counted apart from files kept, and an
//  owner-only pending save is neither a content conflict nor a full-record
//  send, while a genuine concurrent edit is still reported with its losing text.
//

#if SYNCTEST
import XCTest
import CoreData
import CloudKit
@testable import Etudes

final class SyncTestMediaTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var store: JournalSyncStateStore!
    private var tempDir: URL!
    private var stamp: NSObjectProtocol?
    private var keptContexts: [NSManagedObjectContext] = []

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-media-\(UUID().uuidString)", isDirectory: true)
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
    private func makeSession(in ctx: NSManagedObjectContext, id: UUID = UUID(), notes: String? = nil, owner: String? = nil) -> NSManagedObject {
        let s = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        s.setValue(id, forKey: "id"); s.setValue("T", forKey: "title"); s.setValue(Date(), forKey: "timestamp")
        s.setValue(notes, forKey: "notes"); s.setValue(owner, forKey: "ownerUserID")
        return s
    }

    @discardableResult
    private func makeAttachment(session: NSManagedObject, in ctx: NSManagedObjectContext, id: UUID = UUID(), fileURL: String) -> NSManagedObject {
        let a = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: ctx)
        a.setValue(id, forKey: "id"); a.setValue("image", forKey: "kind"); a.setValue(Date(), forKey: "createdAt")
        a.setValue(fileURL, forKey: "fileURL"); a.setValue(session, forKey: "session")
        return a
    }

    private func attachmentRecord(id: UUID, sessionID: UUID, file: URL?, hash: String?, ext: String = "jpg", displayName: String? = nil) -> CKRecord {
        let r = CKRecord(recordType: "Attachment", recordID: JournalRecordMapping.recordID(for: id))
        r["kind"] = "image" as CKRecordValue
        r["createdAt"] = Date() as CKRecordValue
        r["userModifiedAt"] = Date() as CKRecordValue
        r["displayName"] = displayName.map { $0 as CKRecordValue }
        r["session"] = CKRecord.Reference(recordID: JournalRecordMapping.recordID(for: sessionID), action: .none)
        if let file { r["file"] = CKAsset(fileURL: file); r["fileExt"] = ext as CKRecordValue }
        r["fileHash"] = hash.map { $0 as CKRecordValue }
        return r
    }

    private func sessionRecord(id: UUID, notes: String?, owner: String?, modified: Date) -> CKRecord {
        let r = CKRecord(recordType: "Session", recordID: JournalRecordMapping.recordID(for: id))
        r["title"] = "T" as CKRecordValue; r["timestamp"] = Date() as CKRecordValue
        r["notes"] = notes.map { $0 as CKRecordValue }; r["ownerUserID"] = owner.map { $0 as CKRecordValue }
        r["userModifiedAt"] = modified as CKRecordValue
        return r
    }

    private func setStamp(_ id: UUID, _ date: Date) {
        let ctx = container.newBackgroundContext(); ctx.transactionAuthor = JournalSyncAuthor.sync
        ctx.performAndWait {
            let r = NSFetchRequest<NSManagedObject>(entityName: "Session"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let s = (try? ctx.fetch(r))?.first { s.setValue(date, forKey: "userModifiedAt"); try? ctx.save() }
        }
    }

    private func attachmentState(_ id: UUID) -> (fileURL: String?, name: String?) {
        let ctx = container.newBackgroundContext(); keptContexts.append(ctx)
        var out: (String?, String?) = (nil, nil)
        ctx.performAndWait {
            let r = NSFetchRequest<NSManagedObject>(entityName: "Attachment"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let a = (try? ctx.fetch(r))?.first { out = (a.value(forKey: "fileURL") as? String, a.value(forKey: "displayName") as? String) }
        }
        return out
    }

    private func materialised(_ id: UUID, ext: String = "jpg") -> URL { JournalRecordMapping.materialisedURL(recordName: id.uuidString, ext: ext) }

    // MARK: policy and hashing

    func testAssetPolicy() {
        XCTAssertTrue(JournalAssetPolicy.includeAsset(hasServerCopy: false, serverHash: nil, localHash: "a"), "new record: always")
        XCTAssertTrue(JournalAssetPolicy.includeAsset(hasServerCopy: true, serverHash: nil, localHash: "a"), "server hash unknown: once")
        XCTAssertTrue(JournalAssetPolicy.includeAsset(hasServerCopy: true, serverHash: "a", localHash: nil), "local hash unknown: send")
        XCTAssertFalse(JournalAssetPolicy.includeAsset(hasServerCopy: true, serverHash: "a", localHash: "a"), "unchanged: metadata only")
        XCTAssertTrue(JournalAssetPolicy.includeAsset(hasServerCopy: true, serverHash: "a", localHash: "b"), "replaced: send")
    }

    func testHashCacheHitsForAnUnchangedFileAndMissesAfterAChange() throws {
        let file = tempDir.appendingPathComponent("m.bin")
        try Data(repeating: 7, count: 3_000_000).write(to: file)
        let first = try XCTUnwrap(JournalAssetHash.cachedHash(of: file, cache: nil))
        let second = try XCTUnwrap(JournalAssetHash.cachedHash(of: file, cache: first.entry))
        XCTAssertEqual(first.hash, second.hash)
        XCTAssertEqual(first.entry, second.entry)
        XCTAssertEqual(first.hash, JournalAssetHash.hash(of: file))
        Thread.sleep(forTimeInterval: 1.1)   // the stamp has second resolution
        try Data(repeating: 8, count: 3_000_001).write(to: file)
        let third = try XCTUnwrap(JournalAssetHash.cachedHash(of: file, cache: first.entry))
        XCTAssertNotEqual(third.hash, first.hash)
    }

    // MARK: records

    func testAttachmentRecordCarriesTheFileOnlyWhenAskedAndSessionOwnerOnlyIsPartial() throws {
        let ctx = container.viewContext
        let file = tempDir.appendingPathComponent("p.jpg"); try Data([1, 2, 3]).write(to: file)
        let s = makeSession(in: ctx, notes: "n", owner: "A")
        let a = makeAttachment(session: s, in: ctx, fileURL: file.path)
        a.setValue("Original name", forKey: "displayName")
        try ctx.save()
        let base = CKRecord(recordType: "Attachment", recordID: JournalRecordMapping.recordID(for: a.value(forKey: "id") as! UUID))

        let metadataOnly = try XCTUnwrap(JournalRecordMapping.record(for: a, base: base, includeAsset: false))
        XCTAssertNil(metadataOnly["file"]); XCTAssertNil(metadataOnly["fileExt"]); XCTAssertNil(metadataOnly["fileHash"])
        // Stage G: the name travels on the meta record, never on the content record.
        XCTAssertNil(metadataOnly["displayName"])
        XCTAssertEqual(JournalRecordMapping.metaRecord(for: a, base: nil)?["displayName"] as? String, "Original name", "a rename travels")

        let withFile = try XCTUnwrap(JournalRecordMapping.record(for: a, base: base, includeAsset: true, fileHash: "h"))
        XCTAssertNotNil(withFile["file"] as? CKAsset); XCTAssertEqual(withFile["fileExt"] as? String, "jpg"); XCTAssertEqual(withFile["fileHash"] as? String, "h")

        let sessionBase = CKRecord(recordType: "Session", recordID: JournalRecordMapping.recordID(for: s.value(forKey: "id") as! UUID))
        let ownerOnly = try XCTUnwrap(JournalRecordMapping.record(for: s, base: sessionBase, ownerOnly: true))
        XCTAssertEqual(Set(ownerOnly.allKeys()), ["ownerUserID"], "an owner-only send carries nothing else")
        let fresh = try XCTUnwrap(JournalRecordMapping.record(for: s, base: nil, ownerOnly: true))
        XCTAssertTrue(fresh.allKeys().contains("notes"), "a record the server has never seen is sent whole")
    }

    // MARK: receiving media

    func testUnchangedHashLeavesTheLocalFileAloneAndAReplacementIsWrittenIntoPlace() throws {
        let ctx = container.viewContext
        let sid = UUID(), aid = UUID()
        makeSession(in: ctx, id: sid)
        try ctx.save()
        // First arrival: materialised and hashed.
        let v1 = tempDir.appendingPathComponent("v1.jpg"); try Data(repeating: 1, count: 1000).write(to: v1)
        let h1 = try XCTUnwrap(JournalAssetHash.hash(of: v1))
        let (imp, ictx) = importer()
        ictx.performAndWait { _ = imp.importModifications([attachmentRecord(id: aid, sessionID: sid, file: v1, hash: h1)]) }
        XCTAssertEqual(store.state.assetHashes[aid.uuidString], h1)
        XCTAssertEqual(JournalAssetHash.hash(of: materialised(aid)), h1)
        XCTAssertEqual(store.state.assetBytesDownloaded, 1000)
        XCTAssertEqual(store.state.bytesReceived, 0, "the importer's own counter is updated by the engine; the summary carries the bytes")

        // A metadata edit from the other device: same hash, nothing rewritten.
        let v1again = tempDir.appendingPathComponent("v1b.jpg"); try Data(repeating: 1, count: 1000).write(to: v1again)
        let before = try FileManager.default.attributesOfItem(atPath: materialised(aid).path)[.modificationDate] as? Date
        Thread.sleep(forTimeInterval: 1.1)
        ictx.performAndWait { _ = imp.importModifications([attachmentRecord(id: aid, sessionID: sid, file: v1again, hash: h1, displayName: "Renamed")]) }
        let after = try FileManager.default.attributesOfItem(atPath: materialised(aid).path)[.modificationDate] as? Date
        XCTAssertEqual(before, after, "unchanged media is not rewritten")
        XCTAssertEqual(attachmentState(aid).name, "Renamed")
        XCTAssertEqual(store.state.assetBytesDownloaded, 2000, "but CloudKit did download it: transport, counted apart")

        // A replacement: new hash, new bytes in place.
        let v2 = tempDir.appendingPathComponent("v2.jpg"); try Data(repeating: 2, count: 1500).write(to: v2)
        let h2 = try XCTUnwrap(JournalAssetHash.hash(of: v2))
        var summary = JournalImporter.Summary()
        ictx.performAndWait { summary = imp.importModifications([attachmentRecord(id: aid, sessionID: sid, file: v2, hash: h2)]) }
        XCTAssertEqual(JournalAssetHash.hash(of: materialised(aid)), h2, "the replaced file is what opens here now")
        XCTAssertEqual(store.state.assetHashes[aid.uuidString], h2)
        XCTAssertEqual(summary.bytes, 1500)
        XCTAssertEqual(attachmentState(aid).fileURL, materialised(aid).path)
        try? FileManager.default.removeItem(at: materialised(aid))
    }

    func testTheCreatorsOwnFileIsKeptUntilTheServerSaysItChanged() throws {
        // This device made the attachment (its own file name); the server copy
        // comes back without a hash (older sender) and then with the same hash.
        let ctx = container.viewContext
        let sid = UUID(), aid = UUID()
        let s = makeSession(in: ctx, id: sid)
        let own = tempDir.appendingPathComponent("photo-\(aid.uuidString).jpg"); try Data(repeating: 3, count: 800).write(to: own)
        makeAttachment(session: s, in: ctx, id: aid, fileURL: own.path)
        try ctx.save()
        let h = try XCTUnwrap(JournalAssetHash.hash(of: own))
        let (imp, ictx) = importer()
        ictx.performAndWait { _ = imp.importModifications([attachmentRecord(id: aid, sessionID: sid, file: own, hash: nil)]) }
        XCTAssertEqual(attachmentState(aid).fileURL, own.path, "no hash on the server: nothing touched")
        XCTAssertNil(store.state.assetHashes[aid.uuidString])
        ictx.performAndWait { _ = imp.importModifications([attachmentRecord(id: aid, sessionID: sid, file: own, hash: h)]) }
        XCTAssertEqual(attachmentState(aid).fileURL, own.path, "same content: the creator's file stays")
        XCTAssertEqual(store.state.assetHashes[aid.uuidString], h, "and the server's hash is adopted")
        // Now a genuine replacement from the other device.
        let v2 = tempDir.appendingPathComponent("other.jpg"); try Data(repeating: 4, count: 900).write(to: v2)
        let h2 = try XCTUnwrap(JournalAssetHash.hash(of: v2))
        ictx.performAndWait { _ = imp.importModifications([attachmentRecord(id: aid, sessionID: sid, file: v2, hash: h2)]) }
        XCTAssertEqual(attachmentState(aid).fileURL, materialised(aid).path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: own.path), "the old file is removed, no duplicate")
        XCTAssertEqual(JournalAssetHash.hash(of: materialised(aid)), h2)
        try? FileManager.default.removeItem(at: materialised(aid))
    }

    // MARK: owner-only pending saves

    func testOwnerOnlyUpdatesAreFlaggedAndAContentEditAbsorbsThem() throws {
        let ctx = container.viewContext
        let s = makeSession(in: ctx, notes: "n")
        try ctx.save()
        let tracker = JournalChangeTracker(container: container, store: store)
        tracker.bootstrapIfNeeded()
        store.update { $0.outbox.removeAll() }
        s.setValue("A", forKey: "ownerUserID"); try ctx.save()
        XCTAssertEqual(tracker.processHistory().map(\.ownerOnly), [true])
        XCTAssertEqual(store.state.outbox.map(\.ownerOnly), [true])
        s.setValue("edited", forKey: "notes"); try ctx.save()
        XCTAssertEqual(tracker.processHistory().map(\.ownerOnly), [false])
        XCTAssertEqual(store.state.outbox.map(\.ownerOnly), [false], "the content save replaced the owner-only entry")
        s.setValue("B", forKey: "ownerUserID"); try ctx.save()
        _ = tracker.processHistory()
        XCTAssertEqual(store.state.outbox.map(\.ownerOnly), [false], "an owner-only save never downgrades a pending content save")
    }

    func testOwnerOnlyPendingSaveIsNotAConflictButAConcurrentEditStillIs() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let ctx = container.viewContext
        // Owner-only pending: the server's newer content is taken, the owner kept, no conflict logged.
        let ownerOnlyID = UUID()
        makeSession(in: ctx, id: ownerOnlyID, notes: "original", owner: "A")
        try ctx.save()
        setStamp(ownerOnlyID, t0)
        store.update { $0.outbox.append(.init(recordName: ownerOnlyID.uuidString, recordType: "Session", op: .save, ownerOnly: true)) }
        let queue = RecordingSendQueue()
        let (imp, ictx) = importer(queue)
        ictx.performAndWait { _ = imp.importSession(sessionRecord(id: ownerOnlyID, notes: "edited elsewhere", owner: nil, modified: t0.addingTimeInterval(60))); imp.save() }
        XCTAssertTrue(store.state.conflicts.isEmpty, "no misleading conflict")
        XCTAssertEqual(queue.removed, [ownerOnlyID.uuidString])
        XCTAssertEqual(queue.saves.map { ($0.0, $0.2) }.first.map { "\($0.0)|\($0.1)" }, "\(ownerOnlyID.uuidString)|true", "the owner goes back, owner-only")
        let r = NSFetchRequest<NSManagedObject>(entityName: "Session"); r.predicate = NSPredicate(format: "id == %@", ownerOnlyID as CVarArg)
        ictx.performAndWait {
            let s = (try? ictx.fetch(r))?.first
            XCTAssertEqual(s?.value(forKey: "notes") as? String, "edited elsewhere")
            XCTAssertEqual(s?.value(forKey: "ownerUserID") as? String, "A")
        }

        // Genuine concurrent edit: content pending here, newer content there → reported with the losing text.
        let concurrentID = UUID()
        makeSession(in: ctx, id: concurrentID, notes: "mine, older", owner: "A")
        try ctx.save()
        setStamp(concurrentID, t0)
        store.update { $0.outbox.append(.init(recordName: concurrentID.uuidString, recordType: "Session", op: .save, ownerOnly: false)) }
        ictx.performAndWait { _ = imp.importSession(sessionRecord(id: concurrentID, notes: "theirs, newer", owner: "A", modified: t0.addingTimeInterval(60))); imp.save() }
        XCTAssertEqual(store.state.conflicts.count, 1)
        XCTAssertEqual(store.state.conflicts.last?.winner, "server")
        XCTAssertEqual(store.state.conflicts.last?.losingNotes, "mine, older", "the losing text is kept")
    }

    func testPendingChangeDecodesWithoutTheOwnerOnlyField() throws {
        let decoded = try JSONDecoder().decode(JournalSyncPendingChange.self, from: Data(#"{"recordName":"x","recordType":"Session","op":"save"}"#.utf8))
        XCTAssertFalse(decoded.ownerOnly)
    }
}
#endif
