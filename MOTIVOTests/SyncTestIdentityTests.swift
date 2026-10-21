//
//  SyncTestIdentityTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  Stage B of the private sync trial: the ownership rules, ownership kept
//  separate from content edits (both arrival orders), attachments following
//  their session's owner without being synced, custom rows stamped with the
//  local install key and de-duplicated deterministically, two independent
//  Solo journals converging without loss, saved Lists round-tripping (same
//  name, both survive), the store merge on adoption being copy-if-absent and
//  idempotent, and the C-114 refusal holding after adoption.
//

#if SYNCTEST
import XCTest
import CoreData
import CloudKit
@testable import Etudes

/// Records what the importer asks the engine to send.
final class RecordingSendQueue: JournalSendQueue {
    var saves: [(String, String, Bool)] = []
    var deletes: [(String, String)] = []
    var removed: [String] = []
    func enqueueSave(_ recordName: String, recordType: String, ownerOnly: Bool) { saves.append((recordName, recordType, ownerOnly)) }
    func enqueueDelete(_ recordName: String, recordType: String) { deletes.append((recordName, recordType)) }
    func removePendingSave(_ recordName: String) { removed.append(recordName) }
}

final class SyncTestIdentityTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var store: JournalSyncStateStore!
    private var tempDir: URL!
    private var stamp: NSObjectProtocol?
    private var defaults: UserDefaults!
    private var suiteName: String!
    /// Objects returned by `fetchAll` stay readable only while their context lives.
    private var keptContexts: [NSManagedObjectContext] = []
    private let k2 = "local:TEST-INSTALL"

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-id-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        container = Self.makeContainer(at: tempDir.appendingPathComponent("store.sqlite"))
        store = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("state.json"))
        stamp = JournalUserEditStamp.install()
        suiteName = "synctest-identity-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        if let stamp { NotificationCenter.default.removeObserver(stamp) }
        defaults.removePersistentDomain(forName: suiteName)
        keptContexts.removeAll()
        container = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private static func makeContainer(at url: URL) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "MOTIVO")
        let description = NSPersistentStoreDescription(url: url)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in precondition(error == nil, "\(String(describing: error))") }
        container.viewContext.transactionAuthor = JournalSyncAuthor.app
        return container
    }

    // MARK: helpers

    private func importContext(_ c: NSPersistentContainer? = nil) -> NSManagedObjectContext {
        let ctx = (c ?? container).newBackgroundContext()
        ctx.transactionAuthor = JournalSyncAuthor.sync
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return ctx
    }

    private func makeImporter(_ ctx: NSManagedObjectContext, queue: RecordingSendQueue, store: JournalSyncStateStore? = nil) -> JournalImporter {
        let importer = JournalImporter(context: ctx, store: store ?? self.store, customOwner: k2)
        importer.queue = queue
        return importer
    }

    @discardableResult
    private func makeSession(in ctx: NSManagedObjectContext, id: UUID = UUID(), title: String = "T", notes: String? = nil,
                             owner: String? = nil) -> NSManagedObject {
        let s = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        s.setValue(id, forKey: "id")
        s.setValue(title, forKey: "title")
        s.setValue(notes, forKey: "notes")
        s.setValue(Date(), forKey: "timestamp")
        s.setValue(owner, forKey: "ownerUserID")
        return s
    }

    @discardableResult
    private func makeAttachment(session: NSManagedObject, in ctx: NSManagedObjectContext, id: UUID = UUID(), fileURL: String) -> NSManagedObject {
        let a = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: ctx)
        a.setValue(id, forKey: "id")
        a.setValue("image", forKey: "kind")
        a.setValue(Date(), forKey: "createdAt")
        a.setValue(fileURL, forKey: "fileURL")
        a.setValue(session, forKey: "session")
        return a
    }

    @discardableResult
    private func makeInstrument(in ctx: NSManagedObjectContext, id: UUID = UUID(), name: String, owner: String,
                                order: Int16 = 0, visible: Bool = true) -> NSManagedObject {
        let u = NSEntityDescription.insertNewObject(forEntityName: "UserInstrument", into: ctx)
        u.setValue(id, forKey: "id")
        u.setValue(name, forKey: "displayName")
        u.setValue(PersistenceController.normalized(name), forKey: "normalizedName")
        u.setValue(owner, forKey: "ownerUserID")
        u.setValue(order, forKey: "displayOrder")
        u.setValue(visible, forKey: "isVisibleOnProfile")
        return u
    }

    private func sessionRecord(id: UUID, title: String = "T", notes: String?, owner: String?, modified: Date) -> CKRecord {
        let r = CKRecord(recordType: "Session", recordID: JournalRecordMapping.recordID(for: id))
        r["title"] = title as CKRecordValue
        r["notes"] = notes.map { $0 as CKRecordValue }
        r["timestamp"] = Date() as CKRecordValue
        r["ownerUserID"] = owner.map { $0 as CKRecordValue }
        r["userModifiedAt"] = modified as CKRecordValue
        return r
    }

    private func instrumentRecord(id: UUID, name: String, order: Int16 = 0, visible: Bool = true) -> CKRecord {
        let r = CKRecord(recordType: "UserInstrument", recordID: JournalRecordMapping.recordID(for: id))
        r["displayName"] = name as CKRecordValue
        r["normalizedName"] = PersistenceController.normalized(name) as CKRecordValue
        r["displayOrder"] = NSNumber(value: order)
        r["isVisibleOnProfile"] = NSNumber(value: visible)
        return r
    }

    private func fetchAll(_ entity: String, in c: NSPersistentContainer? = nil, where predicate: NSPredicate? = nil) -> [NSManagedObject] {
        let ctx = (c ?? container).newBackgroundContext()
        keptContexts.append(ctx)
        var out: [NSManagedObject] = []
        ctx.performAndWait {
            let r = NSFetchRequest<NSManagedObject>(entityName: entity)
            r.predicate = predicate
            out = (try? ctx.fetch(r)) ?? []
        }
        return out
    }

    private func fetchSession(_ id: UUID, in c: NSPersistentContainer? = nil) -> (notes: String?, owner: String?, modified: Date?)? {
        let rows = fetchAll("Session", in: c, where: NSPredicate(format: "id == %@", id as CVarArg))
        guard let s = rows.first else { return nil }
        var out: (String?, String?, Date?) = (nil, nil, nil)
        s.managedObjectContext?.performAndWait {
            out = (s.value(forKey: "notes") as? String, s.value(forKey: "ownerUserID") as? String, s.value(forKey: "userModifiedAt") as? Date)
        }
        return out
    }

    /// The edit stamp observer sets `userModifiedAt` to now on every local
    /// save, so an older stamp is written through a `sync`-author context,
    /// which the observer skips (exactly as an import would leave it).
    private func setStamp(_ id: UUID, _ date: Date) {
        let ctx = importContext()
        ctx.performAndWait {
            let r = NSFetchRequest<NSManagedObject>(entityName: "Session")
            r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let s = (try? ctx.fetch(r))?.first { s.setValue(date, forKey: "userModifiedAt"); try? ctx.save() }
        }
    }

    private func markPendingSave(_ id: UUID, type: String = "Session", store: JournalSyncStateStore? = nil) {
        (store ?? self.store).update { $0.outbox.append(.init(recordName: id.uuidString, recordType: type, op: .save)) }
    }

    // MARK: (1) the ownership rules, order-independent

    func testAdoptionIsDecidedOverTheWholeStoreAndNeverOverwritesK1() {
        // No K1, fetch not complete: wait, whatever has arrived so far.
        XCTAssertEqual(JournalOwnership.decideAdoption(k1: nil, localOwners: ["A"], initialFetchComplete: false), .wait)
        // No K1, complete: one owner → adopt; none → nothing; several → report only.
        XCTAssertEqual(JournalOwnership.decideAdoption(k1: nil, localOwners: ["A"], initialFetchComplete: true), .adopt("A"))
        XCTAssertEqual(JournalOwnership.decideAdoption(k1: nil, localOwners: [], initialFetchComplete: true), .nothingToDo)
        XCTAssertEqual(JournalOwnership.decideAdoption(k1: nil, localOwners: ["A", "B"], initialFetchComplete: true), .report(foreign: ["A", "B"]))
        // K1 present: never overwritten, foreign owners reported.
        XCTAssertEqual(JournalOwnership.decideAdoption(k1: "A", localOwners: ["A"], initialFetchComplete: true), .nothingToDo)
        XCTAssertEqual(JournalOwnership.decideAdoption(k1: "A", localOwners: ["A", "B"], initialFetchComplete: false), .report(foreign: ["B"]))
        XCTAssertEqual(JournalOwnership.decideAdoption(k1: "A", localOwners: ["B"], initialFetchComplete: true), .report(foreign: ["B"]))
        // Whitespace and empties are not owners.
        XCTAssertEqual(JournalOwnership.assess(["", "  ", " A "]), .single("A"))
    }

    func testEligibilityIsOwnershipOnly() {
        XCTAssertTrue(JournalOwnership.isEligible(owner: nil, journalOwner: "A"))
        XCTAssertTrue(JournalOwnership.isEligible(owner: "", journalOwner: nil))
        XCTAssertTrue(JournalOwnership.isEligible(owner: "A", journalOwner: "A"))
        XCTAssertFalse(JournalOwnership.isEligible(owner: "B", journalOwner: "A"))
        XCTAssertFalse(JournalOwnership.isEligible(owner: "B", journalOwner: nil), "an owned entry on an ownerless device stays local")
        XCTAssertEqual(JournalOwnership.journalOwner(k1: nil, local: .single("A")), "A")
        XCTAssertEqual(JournalOwnership.journalOwner(k1: "K", local: .mixed(["A", "B"])), "K")
        XCTAssertNil(JournalOwnership.journalOwner(k1: nil, local: .mixed(["A", "B"])))
    }

    func testOwnerMergeAndOwnershipOnlyKeys() {
        XCTAssertEqual(JournalOwnership.mergedOwner(local: nil, server: "A"), "A")
        XCTAssertEqual(JournalOwnership.mergedOwner(local: "A", server: nil), "A")
        XCTAssertEqual(JournalOwnership.mergedOwner(local: "A", server: "B"), "A", "a difference keeps the local owner; it is reported, not overwritten")
        XCTAssertTrue(JournalOwnership.isOwnershipOnly(["ownerUserID"]))
        XCTAssertTrue(JournalOwnership.isOwnershipOnly(["ownerUserID", "userModifiedAt"]))
        XCTAssertFalse(JournalOwnership.isOwnershipOnly(["ownerUserID", "notes"]))
        XCTAssertFalse(JournalOwnership.isOwnershipOnly([]))
    }

    func testDedupeWinnerIsTheSameWhateverTheOrder() {
        let a = UUID(), b = UUID(), c = UUID()
        let expected = [a, b, c].min { $0.uuidString < $1.uuidString }
        XCTAssertEqual(JournalOwnership.dedupeWinner([a, b, c]), expected)
        XCTAssertEqual(JournalOwnership.dedupeWinner([c, b, a]), expected)
        XCTAssertEqual(JournalOwnership.dedupeWinner([b, c, a]), expected)
        XCTAssertNil(JournalOwnership.dedupeWinner([]))
    }

    // MARK: (2) and (3) C-114 after adoption

    func testDifferentAppleAccountStillRefusedOnASyncedDevice() {
        // After adoption the device holds K1 "A" and the journal is "A"'s.
        XCTAssertTrue(AuthManager.refusesSignIn(storedOwner: "A", incoming: "B", storedOwnerHasLocalJournal: true))
        XCTAssertFalse(AuthManager.refusesSignIn(storedOwner: "A", incoming: "A", storedOwnerHasLocalJournal: true))
        XCTAssertFalse(AuthManager.refusesSignIn(storedOwner: nil, incoming: "B", storedOwnerHasLocalJournal: false))
        // And synced data can never move K1 to "B".
        XCTAssertEqual(JournalOwnership.decideAdoption(k1: "A", localOwners: ["B"], initialFetchComplete: true), .report(foreign: ["B"]))
    }

    // MARK: (5) ownership separate from content, both arrival orders

    func testOwnerOnlyChangeDoesNotMoveTheUserEditStamp() throws {
        let ctx = container.viewContext
        let s = makeSession(in: ctx, title: "Stamped")
        try ctx.save()
        let first = try XCTUnwrap(s.value(forKey: "userModifiedAt") as? Date)
        Thread.sleep(forTimeInterval: 0.02)
        s.setValue("A", forKey: "ownerUserID")
        try ctx.save()
        XCTAssertEqual(s.value(forKey: "userModifiedAt") as? Date, first, "giving an entry its owner is not a user edit")
        Thread.sleep(forTimeInterval: 0.02)
        s.setValue("real edit", forKey: "notes")
        try ctx.save()
        XCTAssertGreaterThan(try XCTUnwrap(s.value(forKey: "userModifiedAt") as? Date), first)
    }

    func testOwnerOnlyAttachmentChangeIsNotQueuedAndAttachmentRecordsCarryNoOwner() throws {
        let ctx = container.viewContext
        let file = tempDir.appendingPathComponent("p.jpg")
        try Data([1, 2, 3]).write(to: file)
        let s = makeSession(in: ctx)
        let a = makeAttachment(session: s, in: ctx, fileURL: file.path)
        try ctx.save()
        let tracker = JournalChangeTracker(container: container, store: store)
        tracker.bootstrapIfNeeded()
        XCTAssertEqual(store.state.outbox.count, 3, "session, attachment and its meta record (stage G)")
        store.update { $0.outbox.removeAll() }

        // Owner-only on the attachment: nothing to send (the owner is not a synced field).
        a.setValue("A", forKey: "ownerUserID")
        try ctx.save()
        XCTAssertTrue(tracker.processHistory().isEmpty)
        // Owner-only on the session: sent (the owner is a synced field), but not as an edit.
        s.setValue("A", forKey: "ownerUserID")
        try ctx.save()
        let added = tracker.processHistory()
        XCTAssertEqual(added.map(\.recordType), ["Session"])

        let record = try XCTUnwrap(JournalRecordMapping.record(for: a, base: nil))
        XCTAssertNil(record["ownerUserID"], "attachment owner follows its session locally and is never uploaded")
        XCTAssertFalse(JournalRecordMapping.attachmentKeys.contains("ownerUserID"))
    }

    func testOfflineNotesEditThenOwnershipArrives_notesKeptOwnerTaken() throws {
        // Device B edited notes offline (newer stamp, pending save). The server copy
        // carries the owner from a different device but older content.
        let id = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let ctx = container.viewContext
        makeSession(in: ctx, id: id, notes: "edited offline", owner: nil)
        try ctx.save()
        setStamp(id, t0.addingTimeInterval(100))
        markPendingSave(id)
        let queue = RecordingSendQueue()
        let imp = importContext()
        let importer = makeImporter(imp, queue: queue)
        var applied = true
        imp.performAndWait { applied = importer.importSession(sessionRecord(id: id, notes: "old notes", owner: "A", modified: t0)); importer.save() }
        XCTAssertFalse(applied, "local content won")
        let s = try XCTUnwrap(fetchSession(id))
        XCTAssertEqual(s.notes, "edited offline")
        XCTAssertEqual(s.owner, "A", "the owner was taken without disturbing the content")
        XCTAssertEqual(s.modified, t0.addingTimeInterval(100), "taking the owner did not move the edit stamp")
        XCTAssertTrue(store.state.outbox.contains { $0.recordName == id.uuidString && $0.op == .save }, "the pending save still carries notes and owner")
        XCTAssertEqual(store.state.conflicts.last?.winner, "local")
    }

    func testOwnershipThenOfflineNotesEditArrives_notesTakenOwnerKept() throws {
        // Device B gave the entry its owner (owner-only, stamp unchanged, pending
        // save). The server copy is an ownerless but NEWER notes edit.
        let id = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let ctx = container.viewContext
        makeSession(in: ctx, id: id, notes: "original", owner: "A")
        try ctx.save()
        setStamp(id, t0)
        markPendingSave(id)
        let queue = RecordingSendQueue()
        let imp = importContext()
        let importer = makeImporter(imp, queue: queue)
        var applied = false
        imp.performAndWait { applied = importer.importSession(sessionRecord(id: id, notes: "edited on the other device", owner: nil, modified: t0.addingTimeInterval(100))); importer.save() }
        XCTAssertTrue(applied, "server content won")
        let s = try XCTUnwrap(fetchSession(id))
        XCTAssertEqual(s.notes, "edited on the other device")
        XCTAssertEqual(s.owner, "A", "the owner survived the content edit")
        XCTAssertEqual(queue.removed, [id.uuidString], "the stale local save left the queue")
        XCTAssertEqual(queue.saves.map(\.0), [id.uuidString], "and the owner is sent back, nothing else")
        XCTAssertEqual(store.state.conflicts.last?.winner, "server")
    }

    func testOwnerlessServerCopyOverAnOwnedLocalEntryKeepsTheOwner() throws {
        let id = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let ctx = container.viewContext
        makeSession(in: ctx, id: id, notes: "n", owner: "A")
        try ctx.save()
        setStamp(id, t0)
        let queue = RecordingSendQueue()
        let imp = importContext()
        let importer = makeImporter(imp, queue: queue)
        imp.performAndWait { _ = importer.importSession(sessionRecord(id: id, notes: "n2", owner: nil, modified: t0.addingTimeInterval(5))); importer.save() }
        let s = try XCTUnwrap(fetchSession(id))
        XCTAssertEqual(s.notes, "n2")
        XCTAssertEqual(s.owner, "A")
        XCTAssertEqual(queue.saves.map(\.0), [id.uuidString])
    }

    func testDifferentOwnerOnImportIsKeptLocallyAndReported() throws {
        let id = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let ctx = container.viewContext
        makeSession(in: ctx, id: id, owner: "A")
        try ctx.save()
        setStamp(id, t0)
        let imp = importContext()
        let importer = makeImporter(imp, queue: RecordingSendQueue())
        imp.performAndWait { _ = importer.importSession(sessionRecord(id: id, notes: nil, owner: "B", modified: t0.addingTimeInterval(1))); importer.save() }
        XCTAssertEqual(try XCTUnwrap(fetchSession(id)).owner, "A", "nothing overwrites this device's owner")
        XCTAssertEqual(store.state.ownerConflicts, 1)
    }

    // MARK: attachments follow their session's owner

    func testImportedAttachmentTakesItsSessionsOwner() throws {
        let sid = UUID(), aid = UUID()
        let ctx = container.viewContext
        makeSession(in: ctx, id: sid, owner: "A")
        try ctx.save()
        let file = tempDir.appendingPathComponent("in.jpg")
        try Data([9, 9]).write(to: file)
        let r = CKRecord(recordType: "Attachment", recordID: JournalRecordMapping.recordID(for: aid))
        r["kind"] = "image" as CKRecordValue
        r["createdAt"] = Date() as CKRecordValue
        r["userModifiedAt"] = Date() as CKRecordValue
        r["fileExt"] = "jpg" as CKRecordValue
        r["file"] = CKAsset(fileURL: file)
        r["session"] = CKRecord.Reference(recordID: JournalRecordMapping.recordID(for: sid), action: .none)
        let imp = importContext()
        let importer = makeImporter(imp, queue: RecordingSendQueue())
        imp.performAndWait { _ = importer.importModifications([r]) }
        let a = try XCTUnwrap(fetchAll("Attachment").first)
        a.managedObjectContext?.performAndWait { XCTAssertEqual(a.value(forKey: "ownerUserID") as? String, "A") }
        try? FileManager.default.removeItem(at: JournalRecordMapping.materialisedURL(recordName: aid.uuidString, ext: "jpg"))
    }

    // MARK: (6) custom rows: local K2, deterministic de-duplication

    func testImportedCustomRowIsStampedWithThisInstallsKeyAndDuplicatesCollapseToTheSmallestId() throws {
        for localFirst in [true, false] {
            let dir = tempDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let c = Self.makeContainer(at: dir.appendingPathComponent("s.sqlite"))
            let st = JournalSyncStateStore(fileURL: dir.appendingPathComponent("state.json"))
            let ids = [UUID(), UUID()].sorted { $0.uuidString < $1.uuidString }
            let localID = localFirst ? ids[0] : ids[1]
            let remoteID = localFirst ? ids[1] : ids[0]
            let ctx = c.viewContext
            // The local row is hidden on the profile and has no order; the remote has both.
            makeInstrument(in: ctx, id: localID, name: "Cello", owner: k2, order: 0, visible: false)
            try ctx.save()
            let queue = RecordingSendQueue()
            let imp = importContext(c)
            let importer = makeImporter(imp, queue: queue, store: st)
            imp.performAndWait { _ = importer.importModifications([instrumentRecord(id: remoteID, name: " cello", order: 3, visible: true)]) }

            let rows = fetchAll("UserInstrument", in: c)
            XCTAssertEqual(rows.count, 1, "one row named cello survives (local first: \(localFirst))")
            let row = try XCTUnwrap(rows.first)
            row.managedObjectContext?.performAndWait {
                XCTAssertEqual(row.value(forKey: "id") as? UUID, ids[0], "the smallest id wins on every device")
                XCTAssertEqual(row.value(forKey: "ownerUserID") as? String, k2, "stamped with this install's key")
                XCTAssertEqual(row.value(forKey: "displayOrder") as? Int16, 3, "settings the winner lacked were kept from the loser")
                XCTAssertEqual(row.value(forKey: "isVisibleOnProfile") as? Bool, true)
            }
            XCTAssertEqual(queue.deletes.map(\.0), [ids[1].uuidString], "the loser is removed on the server too")
            if localFirst { XCTAssertEqual(queue.saves.map(\.0), [ids[0].uuidString], "the local winner, now changed, is sent") }
        }
    }

    func testCustomRowsUnderAnotherOwnerAreLeftAlone() throws {
        let ctx = container.viewContext
        makeInstrument(in: ctx, name: "Viola", owner: "legacy-or-backend-id")
        makeInstrument(in: ctx, name: "Viola", owner: k2)
        try ctx.save()
        let tracker = JournalChangeTracker(container: container, store: store)
        XCTAssertEqual(tracker.bootstrapCustomsIfNeeded(customOwner: k2), 1, "only this install's own rows are queued")
        let imp = importContext()
        let importer = makeImporter(imp, queue: RecordingSendQueue())
        imp.performAndWait { importer.dedupeCustoms() }
        XCTAssertEqual(fetchAll("UserInstrument").count, 2, "de-duplication is within this install's rows only")
    }

    func testLocalDeletionOfACustomRowReachesTheOutbox() throws {
        let ctx = container.viewContext
        let id = UUID()
        let u = makeInstrument(in: ctx, id: id, name: "Oud", owner: k2)
        try ctx.save()
        let tracker = JournalChangeTracker(container: container, store: store)
        tracker.bootstrapCustomsIfNeeded(customOwner: k2)
        tracker.processHistory()   // consumes the insert
        store.update { $0.outbox.removeAll() }
        ctx.delete(u)
        try ctx.save()
        let added = tracker.processHistory()
        XCTAssertEqual(added, [.init(recordName: id.uuidString, recordType: "UserInstrument", op: .delete)],
                       "custom rows keep no id after deletion; the URI map supplies it")
    }

    // MARK: (6) two independent Solo journals converge

    func testTwoIndependentSoloJournalsUnionWithoutLossOrDuplicates() throws {
        // Device A: 2 sessions, 1 attachment, custom "Cello". Device B: 2 sessions, custom "Cello".
        let dirA = tempDir.appendingPathComponent("A", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        let a = Self.makeContainer(at: dirA.appendingPathComponent("a.sqlite"))
        let file = dirA.appendingPathComponent("a.jpg")
        try Data([4, 5, 6]).write(to: file)
        let aSessions = [UUID(), UUID()]
        let aAttachment = UUID()
        let aCello = UUID()
        try a.viewContext.performAndWait {
            let s1 = makeSession(in: a.viewContext, id: aSessions[0], title: "A1")
            makeSession(in: a.viewContext, id: aSessions[1], title: "A2")
            makeAttachment(session: s1, in: a.viewContext, id: aAttachment, fileURL: file.path)
            makeInstrument(in: a.viewContext, id: aCello, name: "Cello", owner: "local:OTHER-INSTALL")
            try a.viewContext.save()
        }
        // A's records as its engine would build them.
        var records: [CKRecord] = []
        a.viewContext.performAndWait {
            for o in fetchAll("Session", in: a) + fetchAll("Attachment", in: a) + fetchAll("UserInstrument", in: a) {
                let obj = a.viewContext.object(with: o.objectID)
                records.append(JournalRecordMapping.record(for: obj, base: nil)!)
            }
        }
        // Device B.
        let bSessions = [UUID(), UUID()]
        let bCello = UUID()
        let ctx = container.viewContext
        makeSession(in: ctx, id: bSessions[0], title: "B1")
        makeSession(in: ctx, id: bSessions[1], title: "B2")
        makeInstrument(in: ctx, id: bCello, name: "cello", owner: k2)
        try ctx.save()

        let queue = RecordingSendQueue()
        let imp = importContext()
        let importer = makeImporter(imp, queue: queue)
        imp.performAndWait { _ = importer.importModifications(records) }
        // Repeat: ids are retained, so nothing duplicates.
        imp.performAndWait { _ = importer.importModifications(records) }

        let sessionIDs = Set(fetchAll("Session").compactMap { o -> UUID? in var v: UUID?; o.managedObjectContext?.performAndWait { v = o.value(forKey: "id") as? UUID }; return v })
        XCTAssertEqual(sessionIDs, Set(aSessions + bSessions), "every entry from both devices, exactly once")
        XCTAssertEqual(fetchAll("Attachment").count, 1)
        let cellos = fetchAll("UserInstrument")
        XCTAssertEqual(cellos.count, 1, "one Cello")
        cellos.first?.managedObjectContext?.performAndWait {
            XCTAssertEqual(cellos.first?.value(forKey: "id") as? UUID, [aCello, bCello].min { $0.uuidString < $1.uuidString })
            XCTAssertEqual(cellos.first?.value(forKey: "ownerUserID") as? String, k2)
        }
        try? FileManager.default.removeItem(at: JournalRecordMapping.materialisedURL(recordName: aAttachment.uuidString, ext: "jpg"))
    }

    // MARK: saved Lists

    @MainActor
    func testSavedListsRoundTripAndTwoListsWithTheSameNameBothSurvive() throws {
        let scope = "device"
        let scales1 = SavedList(id: UUID(), name: "Scales", items: [SavedListLine(text: "C major")])
        let scales2 = SavedList(id: UUID(), name: "Scales", items: [SavedListLine(text: "G major")])
        try SavedListLibrary.commit(snapshot: [], updated: [scales1, scales2], ownerScope: scope, defaults: defaults)

        let pending = JournalSavedListSync.scan(store: store, defaults: defaults, scope: scope)
        XCTAssertEqual(Set(pending.map(\.recordName)), [scales1.id.uuidString, scales2.id.uuidString])
        XCTAssertTrue(JournalSavedListSync.scan(store: store, defaults: defaults, scope: scope).isEmpty, "unchanged lists are not resent")
        let records = JournalSavedListSync.records(for: pending.map(\.recordName), bases: [:], defaults: defaults, scope: scope)
        XCTAssertEqual(records.count, 2)

        // The other device, with a list of its own and no pending changes.
        let otherSuite = "synctest-identity-other-\(UUID().uuidString)"
        let other = UserDefaults(suiteName: otherSuite)!
        defer { other.removePersistentDomain(forName: otherSuite) }
        let otherStore = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("other.json"))
        let own = SavedList(id: UUID(), name: "Scales", items: [SavedListLine(text: "D major")])
        try SavedListLibrary.commit(snapshot: [], updated: [own], ownerScope: scope, defaults: other)
        store.update { $0.outbox.removeAll() }
        XCTAssertEqual(JournalSavedListSync.apply(Array(records.values), store: otherStore, defaults: other, scope: scope), 2)
        XCTAssertEqual(JournalSavedListSync.apply(Array(records.values), store: otherStore, defaults: other, scope: scope), 2, "re-applying is harmless")
        let merged = try SavedListLibrary.read(ownerScope: scope, defaults: other)
        XCTAssertEqual(merged.count, 3, "three lists named Scales, all kept")
        XCTAssertEqual(Set(merged.map(\.id)), [scales1.id, scales2.id, own.id])
        XCTAssertTrue(JournalSavedListSync.scan(store: otherStore, defaults: other, scope: scope).map(\.recordName).elementsEqual([own.id.uuidString]),
                      "only the other device's own list is new to the server")

        // Local change and deletion are detected.
        var lists = try SavedListLibrary.read(ownerScope: scope, defaults: defaults)
        lists[0].items.append(SavedListLine(text: "A minor"))
        try SavedListLibrary.commit(snapshot: try SavedListLibrary.read(ownerScope: scope, defaults: defaults), updated: [lists[0]], ownerScope: scope, defaults: defaults)
        let changes = JournalSavedListSync.scan(store: store, defaults: defaults, scope: scope)
        XCTAssertEqual(changes.count, 2)
        XCTAssertEqual(changes.filter { $0.op == .save }.map(\.recordName), [lists[0].id.uuidString])
        XCTAssertEqual(changes.filter { $0.op == .delete }.map(\.recordName), [lists[1].id.uuidString])
        XCTAssertEqual(JournalSavedListSync.applyDeletions([lists[1].id.uuidString], store: otherStore, defaults: other, scope: scope), 1)
        XCTAssertEqual(try SavedListLibrary.read(ownerScope: scope, defaults: other).count, 2)
    }

    @MainActor
    func testAChangeOfListScopeIsNeverReadAsDeletion() throws {
        // Two lists under "device", scanned and sent. Then the owner key appears
        // and the lookup moves to the owner's scope, which is still empty.
        let l1 = SavedList(id: UUID(), name: "A", items: [SavedListLine(text: "x")])
        let l2 = SavedList(id: UUID(), name: "B", items: [SavedListLine(text: "y")])
        try SavedListLibrary.commit(snapshot: [], updated: [l1, l2], ownerScope: "device", defaults: defaults)
        XCTAssertEqual(JournalSavedListSync.scan(store: store, defaults: defaults, scope: "device").count, 2)
        store.update { $0.outbox.removeAll() }

        let moved = JournalSavedListSync.scan(store: store, defaults: defaults, scope: "owner-1")
        XCTAssertTrue(moved.isEmpty, "an empty new scope is a change of lookup, not two deletions")
        XCTAssertTrue(store.state.outbox.isEmpty)
        XCTAssertEqual(store.state.listScope, "owner-1")

        // Once the lists are merged into the new scope they are re-sent (same ids,
        // so the server replaces rather than duplicates); a later real deletion
        // in the SAME scope is still detected.
        LocalOwnerStoreMigration.mergeNoOwnerStores(into: "owner-1", defaults: defaults)
        let resent = JournalSavedListSync.scan(store: store, defaults: defaults, scope: "owner-1")
        XCTAssertEqual(Set(resent.map(\.recordName)), [l1.id.uuidString, l2.id.uuidString])
        XCTAssertTrue(resent.allSatisfy { $0.op == .save })
        let lists = try SavedListLibrary.read(ownerScope: "owner-1", defaults: defaults)
        try SavedListLibrary.commit(snapshot: lists, updated: [lists[0]], ownerScope: "owner-1", defaults: defaults)
        let deletion = JournalSavedListSync.scan(store: store, defaults: defaults, scope: "owner-1")
        XCTAssertEqual(deletion.map(\.op), [.delete])
    }

    // (4) The store merge on adoption is C-116's production merge; its cases
    // (both sides with content, same name twice, repeat and interruption) are
    // in C116OwnerStoreMigrationTests.

    // MARK: state file compatibility

    func testOlderStateFileDecodesWithStageBDefaults() throws {
        let json = """
        {"bootstrapQueued":true,"outbox":[],"lastKnownRecords":{},"awaitingParent":{},"conflicts":[],"log":[],
         "bytesSent":0,"bytesReceived":0,"recordsSent":3,"recordsReceived":4}
        """
        let decoded = try JSONDecoder().decode(JournalSyncPersistedState.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.bootstrapQueued)
        XCTAssertEqual(decoded.recordsSent, 3)
        XCTAssertFalse(decoded.initialFetchComplete)
        XCTAssertNil(decoded.pendingOwnerAdoption)
        XCTAssertTrue(decoded.customRecordNames.isEmpty)
        XCTAssertTrue(decoded.listFingerprints.isEmpty)
    }
}
#endif
