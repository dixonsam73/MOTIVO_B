//
//  SyncTestStep0Tests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  Step 0 of integration (2026-11-03): reproductions and regressions for the
//  focused review's findings B1–B6 and the hardening items taken on. Each
//  test names its finding. The engine itself talks to CloudKit, so what is
//  exercised here is the importer, the tracker, the removal bracket and the
//  pure rules the engine consults.
//

#if SYNCTEST
import XCTest
import CoreData
import CloudKit
@testable import Etudes

/// A send queue that edits the store's outbox the way the engine does.
final class Step0Queue: JournalSendQueue {
    let store: JournalSyncStateStore
    var saves: [String] = []
    var removed: [String] = []
    init(store: JournalSyncStateStore) { self.store = store }
    func enqueueSave(_ recordName: String, recordType: String, ownerOnly: Bool) {
        saves.append(recordName)
        store.update { JournalChangeTracker.merge([.init(recordName: recordName, recordType: recordType, op: .save, ownerOnly: ownerOnly)], into: &$0.outbox) }
    }
    func enqueueDelete(_ recordName: String, recordType: String) {
        store.update { JournalChangeTracker.merge([.init(recordName: recordName, recordType: recordType, op: .delete)], into: &$0.outbox) }
    }
    func removePendingSave(_ recordName: String) {
        removed.append(recordName)
        store.update { $0.outbox.removeAll { $0.recordName == recordName && $0.op == .save } }
    }
}

final class SyncTestStep0Tests: XCTestCase {

    private var container: NSPersistentContainer!
    private var store: JournalSyncStateStore!
    private var tempDir: URL!
    private var stamp: NSObjectProtocol?
    private var ictx: NSManagedObjectContext!
    private var importer: JournalImporter!
    private var queue: Step0Queue!
    private var tracker: JournalChangeTracker!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-step0-\(UUID().uuidString)", isDirectory: true)
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
        store = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("state.json"))
        stamp = JournalUserEditStamp.install()
        // The engine's import context, as built in JournalSyncEngine.init.
        ictx = container.newBackgroundContext()
        ictx.name = "syncImport"
        ictx.transactionAuthor = JournalSyncAuthor.sync
        ictx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        ictx.stalenessInterval = 0
        queue = Step0Queue(store: store)
        importer = JournalImporter(context: ictx, store: store, customOwner: nil)
        importer.queue = queue
        importer.log = { [store] in store?.log($0) }
        tracker = JournalChangeTracker(container: container, store: store)
    }

    override func tearDownWithError() throws {
        if let stamp { NotificationCenter.default.removeObserver(stamp) }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
        JournalChangeTracker.testBeforeCommit = nil
        container = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: helpers

    private func sessionRecord(id: UUID, notes: String, modified: Date, title: String = "T") -> CKRecord {
        let r = CKRecord(recordType: "Session", recordID: JournalRecordMapping.recordID(for: id))
        r["title"] = title as CKRecordValue; r["timestamp"] = Date(timeIntervalSince1970: 1_700_000_000) as CKRecordValue
        r["notes"] = notes as CKRecordValue
        r["userModifiedAt"] = modified as CKRecordValue
        return r
    }

    private func attachmentRecord(id: UUID, sessionID: UUID, file: URL?, hash: String?) -> CKRecord {
        let r = CKRecord(recordType: "Attachment", recordID: JournalRecordMapping.recordID(for: id))
        r["kind"] = "image" as CKRecordValue
        r["createdAt"] = Date() as CKRecordValue
        r["userModifiedAt"] = Date() as CKRecordValue
        r["session"] = CKRecord.Reference(recordID: JournalRecordMapping.recordID(for: sessionID), action: .none)
        if let file { r["file"] = CKAsset(fileURL: file); r["fileExt"] = "jpg" as CKRecordValue }
        r["fileHash"] = hash.map { $0 as CKRecordValue }
        return r
    }

    @discardableResult
    private func importRecords(_ records: [CKRecord]) -> JournalImporter.Summary {
        var summary = JournalImporter.Summary()
        ictx.performAndWait { summary = importer.importModifications(records) }
        return summary
    }

    private func notes(_ id: UUID) -> String? {
        let ctx = container.newBackgroundContext()
        var out: String?
        ctx.performAndWait {
            let r = NSFetchRequest<NSManagedObject>(entityName: "Session"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            out = (try? ctx.fetch(r))?.first?.value(forKey: "notes") as? String
        }
        return out
    }

    private func rowCount(_ entity: String) -> Int {
        let ctx = container.newBackgroundContext()
        var n = 0
        ctx.performAndWait { n = (try? ctx.count(for: NSFetchRequest<NSManagedObject>(entityName: entity))) ?? 0 }
        return n
    }

    /// The person edits the session in the app's context (stamped now).
    private func editNotesInApp(_ id: UUID, _ text: String) throws {
        let ctx = container.viewContext
        let r = NSFetchRequest<NSManagedObject>(entityName: "Session"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let s = try XCTUnwrap(try ctx.fetch(r).first)
        s.setValue(text, forKey: "notes")
        try ctx.save()
    }

    private func pendingSave(_ id: UUID) -> JournalSyncPendingChange? {
        store.state.outbox.first { $0.recordName == id.uuidString && $0.op == .save }
    }

    // MARK: B1 — a server copy older than the local edit, with no save pending

    /// After this device's edit 1 was accepted (its outbox entry cleared), the
    /// person makes edit 2; the own-write echo or any older server copy of the
    /// record must not overwrite it, and the newer local copy must go up.
    func testB1_AnOlderServerCopyNeverOverwritesANewerLocalEditWhenNoSaveIsPending() throws {
        let id = UUID()
        let t0 = Date().addingTimeInterval(-600)
        importRecords([sessionRecord(id: id, notes: "server v1", modified: t0)])
        XCTAssertEqual(notes(id), "server v1")
        try editNotesInApp(id, "typed here after the send")      // stamped now; no processHistory: the send was accepted, nothing pending
        XCTAssertNil(pendingSave(id))
        // The own write comes back (same values, older clock) through the records-only catch-up.
        importRecords([sessionRecord(id: id, notes: "server v1", modified: t0)])
        XCTAssertEqual(notes(id), "typed here after the send", "B1: an older server copy must not replace the newer local edit")
        XCTAssertNotNil(pendingSave(id), "the newer local copy is queued so the server catches up")
        // A genuinely newer server edit still applies.
        importRecords([sessionRecord(id: id, notes: "other device, later", modified: Date().addingTimeInterval(60))])
        XCTAssertEqual(notes(id), "other device, later")
    }

    // MARK: B3 — the conflict decision must read the current save, not the import context's copy

    /// The import context keeps the object it imported (here held explicitly, as
    /// relationships and holds do in the app; C-118 showed the staleness on
    /// device). The person's later edit must decide the conflict and the
    /// displaced text must be the other device's, not the stale copy.
    func testB3_AnImportConflictIsDecidedFromTheCurrentSaveAndKeepsTheRightDisplacedText() throws {
        let id = UUID()
        let t0 = Date().addingTimeInterval(-600)
        importRecords([sessionRecord(id: id, notes: "v1", modified: t0)])
        var retained: NSManagedObject?
        ictx.performAndWait { retained = importer.fetch(entity: "Session", id: id); _ = retained?.value(forKey: "notes") }
        XCTAssertNotNil(retained)
        try editNotesInApp(id, "typed here")                     // stamped now (T2)
        XCTAssertFalse(tracker.processHistory().isEmpty)         // a save is pending
        XCTAssertNotNil(pendingSave(id))
        let t1 = Date().addingTimeInterval(-300)                 // other device: after v1, before the local edit
        importRecords([sessionRecord(id: id, notes: "other device", modified: t1)])
        XCTAssertEqual(notes(id), "typed here", "B3: the newer local edit must win against an older server edit")
        XCTAssertNotNil(pendingSave(id), "and stay queued")
        let entries = store.state.conflicts.filter { $0.recordName == id.uuidString }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.winner, "local")
        XCTAssertEqual(entries.first?.displaced["Notes (other device)"], "other device", "the displaced text is the other device's, never the stale copy")
        XCTAssertNil(entries.first?.displaced["Notes (this device)"])
        _ = retained
    }

    // MARK: B5 — imports during and after a device-only removal

    func testB5_ImportsAreRefusedDuringAndAfterADeviceOnlyRemovalUntilReEnabled() {
        let id = UUID()
        JournalLocalRemoval.begin(store: store, reason: "test")
        XCTAssertEqual(importRecords([sessionRecord(id: id, notes: "late fetch", modified: Date())]).received, 0, "B5: nothing is imported while the removal runs")
        XCTAssertEqual(rowCount("Session"), 0)
        JournalLocalRemoval.finish(store: store, container: container)
        XCTAssertEqual(importRecords([sessionRecord(id: id, notes: "late fetch", modified: Date())]).received, 0, "nor after it, while the local copy is removed")
        XCTAssertEqual(rowCount("Session"), 0)
        JournalLocalRemoval.reenable(store: store)
        XCTAssertEqual(importRecords([sessionRecord(id: id, notes: "fetched after re-enable", modified: Date())]).received, 1)
        XCTAssertEqual(rowCount("Session"), 1)
    }

    // MARK: B6 — a record whose file did not arrive

    func testB6_AnAttachmentRecordWithoutItsFileIsNotImportedWhenTheServerHoldsOne() throws {
        let sid = UUID(), aid = UUID()
        importRecords([sessionRecord(id: sid, notes: "", modified: Date())])
        // The file fetch failed: the record arrives asset-free although the server holds a file (hash set).
        let without = importRecords([attachmentRecord(id: aid, sessionID: sid, file: nil, hash: "abc")])
        XCTAssertEqual(without.received, 0, "B6: no row without its file")
        XCTAssertEqual(rowCount("Attachment"), 0)
        // A later fetch brings the file: imported once, file in place.
        let file = tempDir.appendingPathComponent("photo.jpg")
        try Data("jpeg bytes".utf8).write(to: file)
        let with = importRecords([attachmentRecord(id: aid, sessionID: sid, file: file, hash: "abc")])
        XCTAssertEqual(with.received, 1)
        XCTAssertEqual(rowCount("Attachment"), 1)
        // A sender that had no file at all (no hash) still delivers its row, as before.
        let bid = UUID()
        XCTAssertEqual(importRecords([attachmentRecord(id: bid, sessionID: sid, file: nil, hash: nil)]).received, 1)
        try? FileManager.default.removeItem(at: JournalRecordMapping.materialisedURL(recordName: aid.uuidString, ext: "jpg"))
        try? FileManager.default.removeItem(at: JournalRecordMapping.materialisedURL(recordName: bid.uuidString, ext: ""))
    }

    // MARK: B2 — an edit during an older send

    /// Edit 1 is in flight (revision 0 built into the batch); edit 2 merges into
    /// the same entry (revision 1). The acceptance of edit 1 must not clear the
    /// entry; the acceptance of the resend (revision 1) must.
    func testB2_ANewerEditDuringAnOlderSendStaysQueuedUntilItsOwnRevisionIsAccepted() {
        let name = UUID().uuidString
        let save = JournalSyncPendingChange(recordName: name, recordType: JournalSyncRecordType.session, op: .save)
        var outbox: [JournalSyncPendingChange] = []
        JournalChangeTracker.merge([save], into: &outbox)
        XCTAssertEqual(outbox.first?.revision, 0)
        let built = outbox.first!.revision                               // the batch is built with revision 0
        JournalChangeTracker.merge([save], into: &outbox)                 // edit 2 lands while the send is in flight
        XCTAssertEqual(outbox.count, 1); XCTAssertEqual(outbox.first?.revision, 1)
        let first = JournalOutboxSettle.settle(name: name, sentRevision: built, outbox: outbox)
        XCTAssertTrue(first.keptNewer, "B2: the accepted send carried edit 1 only; the entry stays for edit 2")
        XCTAssertEqual(first.outbox.count, 1)
        let second = JournalOutboxSettle.settle(name: name, sentRevision: 1, outbox: first.outbox)
        XCTAssertFalse(second.keptNewer); XCTAssertTrue(second.outbox.isEmpty, "the resend carried edit 2: settled")
        // A legacy acceptance with no recorded revision settles as before; a stranger name changes nothing.
        XCTAssertTrue(JournalOutboxSettle.settle(name: name, sentRevision: nil, outbox: outbox).outbox.isEmpty)
        XCTAssertEqual(JournalOutboxSettle.settle(name: "other", sentRevision: 0, outbox: outbox).outbox, outbox)
        // The revision survives the state file (a kill between the acceptance and the resend).
        store.update { $0.outbox = outbox }
        XCTAssertEqual(JournalSyncStateStore(fileURL: store.fileURL).state.outbox.first?.revision, 1)
        // The content save that absorbs a partial keeps counting.
        var mixed: [JournalSyncPendingChange] = [.init(recordName: name, recordType: JournalSyncRecordType.session, op: .save, ownerOnly: true)]
        JournalChangeTracker.merge([save], into: &mixed)
        XCTAssertFalse(mixed.first!.ownerOnly); XCTAssertEqual(mixed.first?.revision, 1)
    }

    // MARK: B4 — a removal begun while history is being processed

    /// The reader has fetched the removal's batch deletes before the marker was
    /// set (it read the marker at entry). Nothing may reach the outbox, and a
    /// relaunch plus re-enable must send no deletion.
    func testB4_ARemovalBegunDuringHistoryProcessingQueuesNoDeletionsAndReEnableSendsNone() throws {
        let ctx = container.viewContext
        let s = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        let id = UUID(); s.setValue(id, forKey: "id"); s.setValue("T", forKey: "title"); s.setValue(Date(), forKey: "timestamp")
        try ctx.save()
        XCTAssertEqual(tracker.processHistory().count, 1)                 // baseline: the insert is queued
        store.update { $0.outbox.removeAll() }                            // …and accepted
        // The removal's own batch delete lands while a reader is between its read and its commit.
        ctx.delete(s); try ctx.save()
        JournalChangeTracker.testBeforeCommit = { JournalLocalRemoval.begin(store: self.store, reason: "test") }
        let committed = tracker.processHistory()
        JournalChangeTracker.testBeforeCommit = nil
        XCTAssertTrue(committed.isEmpty, "B4: a commit that straddled the removal's begin is dropped")
        XCTAssertTrue(store.state.outbox.isEmpty)
        XCTAssertTrue(store.state.localRemovalInProgress)
        // Relaunch: the removal finishes (token fast-forwarded), sync is re-enabled.
        JournalLocalRemoval.finish(store: store, container: container)
        let reloaded = JournalSyncStateStore(fileURL: store.fileURL)
        XCTAssertTrue(reloaded.state.outbox.isEmpty)
        JournalLocalRemoval.reenable(store: reloaded)
        let afterTracker = JournalChangeTracker(container: container, store: reloaded)
        XCTAssertTrue(afterTracker.processHistory().isEmpty, "the deletion is behind the fast-forwarded token")
        XCTAssertFalse(reloaded.state.outbox.contains { $0.op == .delete }, "nothing to send that would delete the other device's copy")
        // The token moving under a reader (the finish's fast-forward) also drops the batch.
        let s2 = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        s2.setValue(UUID(), forKey: "id"); s2.setValue("T2", forKey: "title"); s2.setValue(Date(), forKey: "timestamp")
        try ctx.save()
        JournalChangeTracker.testBeforeCommit = { reloaded.update { $0.historyToken = Data([1, 2, 3]) } }
        XCTAssertTrue(afterTracker.processHistory().isEmpty, "a commit against a moved token is dropped, never merged on top")
        JournalChangeTracker.testBeforeCommit = nil
        // Second guard: a deletion that somehow sits in the outbox of a removed copy is dropped at re-enable.
        store.update { st in st.localCopyRemoved = true; st.unlinked = true; st.outbox = [.init(recordName: id.uuidString, recordType: "Session", op: .delete)] }
        JournalLocalRemoval.reenable(store: store)
        XCTAssertTrue(store.state.outbox.isEmpty)
        XCTAssertTrue(store.state.log.contains { $0.text.contains("Dropped 1 deletion(s)") })
    }

    // MARK: B6 — a failed download stays recoverable across a relaunch

    func testB6_AHeldDownloadSurvivesARelaunchAndIsNotCountedTwice() {
        let before = store.state.awaitingMedia
        store.update { s in s.awaitingMedia = JournalMediaHold.adding(["att-1", "att-2"], to: s.awaitingMedia); s.mediaDownloadsHeld += s.awaitingMedia.count - before.count }
        store.update { s in s.awaitingMedia = JournalMediaHold.adding(["att-2"], to: s.awaitingMedia) }
        let reloaded = JournalSyncStateStore(fileURL: store.fileURL)
        XCTAssertEqual(reloaded.state.awaitingMedia, ["att-1", "att-2"], "held by name until a fetch brings the file")
        XCTAssertEqual(reloaded.state.mediaDownloadsHeld, 2)
        XCTAssertEqual(JournalMediaHold.summary(uploads: [:], downloads: reloaded.state.awaitingMedia, hold: .none), "Media still to transfer: 2 to receive")
    }

    // MARK: H1/H3 — a failed write is visible to the catch-up

    func testH1_TheStoreCountsFailedWritesSoACatchUpKeepsItsTokenWhenAHoldDidNotPersist() throws {
        XCTAssertEqual(store.writeFailures, 0)
        XCTAssertTrue(store.update { $0.awaitingMedia = ["a"] })
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: tempDir.path)
        XCTAssertFalse(store.update { $0.awaitingMedia = ["a", "b"] })
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
        XCTAssertEqual(store.writeFailures, 1, "the catch-up compares this before and after its imports")
        XCTAssertEqual(store.state.awaitingMedia, ["a"], "memory never runs ahead of disk")
    }

    // MARK: H3 — a batch whose Core Data save fails reports it

    func testH3_AnImportBatchWhoseSaveFailsReportsItAndAppliesNothing() throws {
        // The same store opened read-only stands in for a save that cannot commit.
        let readOnly = NSPersistentContainer(name: "MOTIVO")
        let description = NSPersistentStoreDescription(url: tempDir.appendingPathComponent("store.sqlite"))
        description.isReadOnly = true
        description.shouldAddStoreAsynchronously = false
        readOnly.persistentStoreDescriptions = [description]
        var loadError: Error?
        readOnly.loadPersistentStores { _, error in loadError = error }
        try XCTUnwrap(loadError == nil ? () : nil, "read-only store failed to load: \(String(describing: loadError))")
        let ctx = readOnly.newBackgroundContext()
        ctx.transactionAuthor = JournalSyncAuthor.sync
        let imp = JournalImporter(context: ctx, store: store, customOwner: nil)
        imp.queue = queue
        imp.log = { [store] in store?.log($0) }
        let sid = UUID()
        var summary = JournalImporter.Summary()
        ctx.performAndWait { summary = imp.importModifications([sessionRecord(id: sid, notes: "cannot commit", modified: Date())]) }
        XCTAssertTrue(summary.saveFailed, "H3: the engine keeps the zone token and fetches the batch again")
        XCTAssertEqual(summary.received, 0)
        XCTAssertEqual(rowCount("Session"), 0)
        XCTAssertTrue(store.state.log.contains { $0.text.contains("Import save failed") })
    }

    // MARK: H4 — leftovers of an interrupted removal are not clocked edits

    func testH4_AnInterruptedRemovalRecoveredAtLaunchLeavesTheProfileAndLibraryAtNeverScanned() {
        store.update { st in
            st.profileFingerprint = JournalProfileValues(name: "Left over").fingerprint
            st.scoreScanDone = true
            st.scoreFingerprints = ["score-1": "x"]
        }
        JournalLocalRemoval.begin(store: store, reason: "test")
        XCTAssertTrue(JournalLocalRemoval.recoverIfInterrupted(store: store, container: container, sweepMedia: {}))
        XCTAssertNil(store.state.profileFingerprint, "H4: the next profile scan is the unclocked transition, never a clocked edit")
        XCTAssertFalse(store.state.scoreScanDone, "same for the library")
        XCTAssertTrue(store.state.localCopyRemoved); XCTAssertFalse(store.state.localRemovalInProgress)
        // A plain, completed removal keeps the empty baselines as before.
        JournalLocalRemoval.reenable(store: store)
        JournalLocalRemoval.begin(store: store, reason: "test")
        JournalLocalRemoval.finish(store: store, container: container)
        XCTAssertEqual(store.state.profileFingerprint, JournalProfileValues().fingerprint)
        XCTAssertTrue(store.state.scoreScanDone)
    }

    // MARK: H2 — the loser's text must be on disk before the server copy is applied

    func testH2_AServerWinIsNotAppliedWhenTheConflictEntryCannotBeSaved() throws {
        let id = UUID()
        importRecords([sessionRecord(id: id, notes: "v1", modified: Date().addingTimeInterval(-600))])
        try editNotesInApp(id, "typed here")
        XCTAssertFalse(tracker.processHistory().isEmpty)
        // The state file can no longer be written (disk full stands in as a read-only directory).
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: tempDir.path)
        XCTAssertFalse(store.update { $0.recordsReceived += 0 }, "precondition: writes fail")
        importRecords([sessionRecord(id: id, notes: "other device, newer", modified: Date().addingTimeInterval(60))])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempDir.path)
        XCTAssertEqual(notes(id), "typed here", "H2: without a saved recovery entry the local text is kept")
        XCTAssertNotNil(pendingSave(id), "and the pending save is kept for the next round")
        XCTAssertTrue(store.state.conflicts.isEmpty)
    }
}
#endif
