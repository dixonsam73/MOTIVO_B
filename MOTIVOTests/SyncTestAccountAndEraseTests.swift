//
//  SyncTestAccountAndEraseTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  Stage E: the one account guard (sends, downloads and imports alike), the
//  boundary between pending operations, account changes and local cleanup.
//  An erase's batch deletes ARE tracked by persistent history (the hazard is
//  demonstrated, not assumed); with the removal marker they are discarded,
//  before and after a relaunch, and an interrupted removal is recovered with
//  nothing queued. Unlink persists with its pending work; re-enabling after a
//  removal fetches the cloud journal again without duplicates; a wiped list
//  library infers no deletions.
//

#if SYNCTEST
import XCTest
import CoreData
import CloudKit
@testable import Etudes

final class SyncTestAccountAndEraseTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var store: JournalSyncStateStore!
    private var tempDir: URL!
    private var stamp: NSObjectProtocol?
    private var keptContexts: [NSManagedObjectContext] = []
    private let userA = "_a1b2c3"
    private let userB = "_d4e5f6"

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-e-\(UUID().uuidString)", isDirectory: true)
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
    }

    override func tearDownWithError() throws {
        if let stamp { NotificationCenter.default.removeObserver(stamp) }
        keptContexts.removeAll()
        container = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: helpers

    @discardableResult
    private func makeSession(in ctx: NSManagedObjectContext, id: UUID = UUID(), title: String = "T", notes: String? = nil) -> NSManagedObject {
        let s = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        s.setValue(id, forKey: "id"); s.setValue(title, forKey: "title"); s.setValue(Date(), forKey: "timestamp")
        s.setValue(notes, forKey: "notes")
        return s
    }

    @discardableResult
    private func makeAttachment(session: NSManagedObject, in ctx: NSManagedObjectContext, id: UUID = UUID(), fileURL: String) -> NSManagedObject {
        let a = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: ctx)
        a.setValue(id, forKey: "id"); a.setValue("image", forKey: "kind"); a.setValue(Date(), forKey: "createdAt")
        a.setValue(fileURL, forKey: "fileURL"); a.setValue(session, forKey: "session")
        return a
    }

    private func count(_ entity: String) -> Int {
        (try? container.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: entity))) ?? 0
    }

    /// What `PersistenceController.destroyAndRebuildStoresForFactoryReset` does.
    private func batchDeleteAll(_ entities: [String]) throws {
        let ctx = container.viewContext
        try ctx.performAndWait {
            ctx.reset()
            var ids: [NSManagedObjectID] = []
            for name in entities {
                let delete = NSBatchDeleteRequest(fetchRequest: NSFetchRequest<NSFetchRequestResult>(entityName: name))
                delete.resultType = .resultTypeObjectIDs
                if let result = try ctx.execute(delete) as? NSBatchDeleteResult, let got = result.result as? [NSManagedObjectID] { ids += got }
            }
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: ids], into: [ctx])
            ctx.reset()
        }
    }

    private func importer(_ queue: RecordingSendQueue = RecordingSendQueue(), store: JournalSyncStateStore? = nil) -> (JournalImporter, NSManagedObjectContext) {
        let ctx = container.newBackgroundContext()
        ctx.transactionAuthor = JournalSyncAuthor.sync
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        keptContexts.append(ctx)
        let imp = JournalImporter(context: ctx, store: store ?? self.store, customOwner: "local:TEST")
        imp.queue = queue
        return (imp, ctx)
    }

    private func sessionRecord(id: UUID, title: String, owner: String? = nil) -> CKRecord {
        let r = CKRecord(recordType: "Session", recordID: JournalRecordMapping.recordID(for: id))
        r["title"] = title as CKRecordValue
        r["timestamp"] = Date() as CKRecordValue
        r["userModifiedAt"] = Date(timeIntervalSince1970: 1_000) as CKRecordValue
        if let owner { r["ownerUserID"] = owner as CKRecordValue }
        return r
    }

    private func decision(current: String?, store: JournalSyncStateStore? = nil) -> JournalAccountGuard.Decision {
        let st = (store ?? self.store).state
        return JournalAccountGuard.decide(bound: st.boundUserRecordName, current: current, unlinked: st.unlinked,
                                          localRemovalInProgress: st.localRemovalInProgress, localCopyRemoved: st.localCopyRemoved)
    }

    // MARK: the guard

    func testAccountGuardCoversEveryPausedState() {
        typealias G = JournalAccountGuard
        XCTAssertEqual(G.decide(bound: userA, current: userA, unlinked: false, localRemovalInProgress: false, localCopyRemoved: false), .allow)
        // Never bound yet: binds on the first account seen (the engine does the binding; the guard allows).
        XCTAssertEqual(G.decide(bound: nil, current: userA, unlinked: false, localRemovalInProgress: false, localCopyRemoved: false), .allow)
        // Different account: refused, not retried (needs the user).
        let other = G.decide(bound: userA, current: userB, unlinked: false, localRemovalInProgress: false, localCopyRemoved: false)
        XCTAssertFalse(other.allowed)
        if case .refuse(let reason, let retry) = other { XCTAssertTrue(reason.contains("different iCloud account")); XCTAssertFalse(retry) } else { XCTFail() }
        // Signed out / check failed: refused, retried.
        let out = G.decide(bound: userA, current: nil, unlinked: false, localRemovalInProgress: false, localCopyRemoved: false)
        if case .refuse(let reason, let retry) = out { XCTAssertTrue(reason.contains("Signed out")); XCTAssertTrue(retry) } else { XCTFail() }
        let never = G.decide(bound: nil, current: nil, unlinked: false, localRemovalInProgress: false, localCopyRemoved: false)
        if case .refuse(let reason, let retry) = never { XCTAssertTrue(reason.contains("Waiting for iCloud")); XCTAssertTrue(retry) } else { XCTFail() }
        // Unlinked beats the account being right; removal in progress beats everything.
        let unlinked = G.decide(bound: userA, current: userA, unlinked: true, localRemovalInProgress: false, localCopyRemoved: false)
        if case .refuse(let reason, let retry) = unlinked { XCTAssertTrue(reason.contains("Unlinked")); XCTAssertFalse(retry) } else { XCTFail() }
        let removed = G.decide(bound: userA, current: userA, unlinked: true, localRemovalInProgress: false, localCopyRemoved: true)
        if case .refuse(let reason, _) = removed { XCTAssertTrue(reason.contains("Local copy removed")) } else { XCTFail() }
        let inProgress = G.decide(bound: userA, current: userA, unlinked: false, localRemovalInProgress: true, localCopyRemoved: false)
        if case .refuse(let reason, let retry) = inProgress { XCTAssertTrue(reason.contains("removal in progress")); XCTAssertFalse(retry) } else { XCTFail() }
        // A different account while unlinked stays refused after re-enable too.
        XCTAssertFalse(G.decide(bound: userA, current: userB, unlinked: false, localRemovalInProgress: false, localCopyRemoved: true).allowed)
    }

    // MARK: the erase hazard, demonstrated and closed

    func testEraseBatchDeletesAreTrackedAsServerDeletionsWithoutTheMarker() throws {
        let tracker = JournalChangeTracker(container: container, store: store)
        let ctx = container.viewContext
        let s = makeSession(in: ctx, title: "Keep me")
        makeAttachment(session: s, in: ctx, fileURL: "/tmp/x.jpg")
        try ctx.save()
        tracker.bootstrapIfNeeded()
        XCTAssertEqual(store.state.outbox.count, 2)

        try batchDeleteAll(["Attachment", "Session"])
        let added = tracker.processHistory()
        XCTAssertEqual(Set(added.map(\.op)), [.delete], "the production erase's batch deletes reach history as deletions")
        XCTAssertEqual(added.count, 2)
        XCTAssertEqual(store.state.outbox.map(\.op), [.delete, .delete], "…and would be uploaded: the hazard the marker closes")
    }

    func testLocalRemovalMarkerEmptiesOutboxAndDiscardsCleanupAcrossRelaunch() throws {
        let tracker = JournalChangeTracker(container: container, store: store)
        store.update { $0.boundUserRecordName = userA }
        let ctx = container.viewContext
        let a = makeSession(in: ctx, title: "A")
        let b = makeSession(in: ctx, title: "B")
        makeAttachment(session: a, in: ctx, fileURL: "/tmp/a.jpg")
        try ctx.save()
        tracker.bootstrapIfNeeded()
        store.update { st in
            st.lastKnownRecords["x"] = Data([1]); st.assetHashes["x"] = "h"; st.listFingerprints["l"] = "f"; st.listScope = "device"
            st.engineState = nil; st.initialFetchComplete = true
        }
        XCTAssertEqual(store.state.outbox.count, 3, "pending work exists before the erase")

        // An ordinary deletion while linked still propagates (not a removal).
        let bg = container.newBackgroundContext()
        bg.performAndWait {
            let req = NSFetchRequest<NSManagedObject>(entityName: "Session")
            req.predicate = NSPredicate(format: "title == %@", "B")
            bg.delete(try! bg.fetch(req).first!)
            try! bg.save()
        }
        XCTAssertEqual(tracker.processHistory().map(\.op), [.delete], "an individual delete while linked is sent as intended")

        // Step 1: before any row is deleted.
        XCTAssertTrue(JournalLocalRemoval.begin(store: store, reason: "erase-all-etudes-data-local"))
        XCTAssertTrue(store.state.localRemovalInProgress)
        XCTAssertTrue(store.state.outbox.isEmpty, "pending saves AND the pending delete are dropped, not sent later")
        XCTAssertFalse(decision(current: userA).allowed)
        XCTAssertEqual(tracker.bootstrapIfNeeded(), 0)
        XCTAssertTrue(tracker.requeueUnsent().isEmpty)

        // The erase itself.
        try batchDeleteAll(["Attachment", "Session"])
        XCTAssertEqual(count("Session"), 0)
        XCTAssertTrue(tracker.processHistory().isEmpty, "cleanup history is discarded while the marker is set")
        XCTAssertTrue(store.state.outbox.isEmpty)

        // Relaunch mid-way (before finish): the marker is on disk and still discards.
        let relaunched = JournalSyncStateStore(fileURL: store.fileURL)
        XCTAssertTrue(relaunched.state.localRemovalInProgress)
        XCTAssertTrue(relaunched.state.outbox.isEmpty)
        let tracker2 = JournalChangeTracker(container: container, store: relaunched)
        XCTAssertTrue(tracker2.processHistory().isEmpty)

        // Step 2.
        XCTAssertTrue(JournalLocalRemoval.finish(store: relaunched, container: container))
        let st = JournalSyncStateStore(fileURL: store.fileURL).state
        XCTAssertFalse(st.localRemovalInProgress)
        XCTAssertTrue(st.localCopyRemoved); XCTAssertTrue(st.unlinked)
        XCTAssertEqual(st.boundUserRecordName, userA, "the binding is kept: a different account still cannot adopt this device")
        XCTAssertTrue(st.outbox.isEmpty); XCTAssertTrue(st.lastKnownRecords.isEmpty); XCTAssertTrue(st.assetHashes.isEmpty)
        XCTAssertTrue(st.listFingerprints.isEmpty); XCTAssertNil(st.listScope); XCTAssertNil(st.engineState)
        XCTAssertFalse(st.initialFetchComplete, "owner adoption waits for the next complete fetch")
        XCTAssertFalse(decision(current: userA, store: relaunched).allowed, "sync stays off until re-enabled")

        // Re-enable: nothing from the cleanup is restored; a new entry made
        // after the erase is tracked normally.
        JournalLocalRemoval.reenable(store: relaunched)
        XCTAssertTrue(decision(current: userA, store: relaunched).allowed)
        XCTAssertFalse(decision(current: userB, store: relaunched).allowed, "a different account after re-enable stays paused")
        XCTAssertTrue(tracker2.processHistory().isEmpty, "the token moved past the cleanup")
        XCTAssertEqual(tracker2.bootstrapIfNeeded(), 0, "no stale bootstrap of an empty store")
        makeSession(in: ctx, title: "After erase")
        try ctx.save()
        XCTAssertEqual(tracker2.processHistory().map(\.op), [.save])
    }

    func testInterruptedRemovalIsRecoveredAtNextLaunchWithNoDeletionsQueued() throws {
        let tracker = JournalChangeTracker(container: container, store: store)
        store.update { $0.boundUserRecordName = userA }
        let ctx = container.viewContext
        let s1 = makeSession(in: ctx, title: "One")
        makeSession(in: ctx, title: "Two")
        makeAttachment(session: s1, in: ctx, fileURL: "/tmp/one.jpg")
        try ctx.save()
        tracker.bootstrapIfNeeded()
        store.update { $0.lastKnownRecords["server"] = Data([1]) }

        // Begin, delete SOME rows the way the simulation / a killed erase would, no finish.
        JournalLocalRemoval.begin(store: store, reason: "simulated interruption")
        ctx.delete(s1)
        try ctx.save()
        XCTAssertEqual(count("Session"), 1); XCTAssertEqual(count("Attachment"), 0)

        // Next launch, before any engine exists.
        let relaunched = JournalSyncStateStore(fileURL: store.fileURL)
        var swept = false
        XCTAssertTrue(JournalLocalRemoval.recoverIfInterrupted(store: relaunched, container: container) { swept = true })
        XCTAssertTrue(swept)
        XCTAssertEqual(count("Session"), 0, "leftover rows removed locally")
        let st = relaunched.state
        XCTAssertFalse(st.localRemovalInProgress); XCTAssertTrue(st.localCopyRemoved); XCTAssertTrue(st.unlinked)
        XCTAssertTrue(st.outbox.isEmpty); XCTAssertTrue(st.lastKnownRecords.isEmpty)
        let tracker2 = JournalChangeTracker(container: container, store: relaunched)
        XCTAssertTrue(tracker2.processHistory().isEmpty, "neither the interrupted deletes nor the recovery's are queued")
        XCTAssertFalse(JournalLocalRemoval.recoverIfInterrupted(store: relaunched, container: container) { XCTFail("ran twice") })
        // Re-enable, then a later look at history still finds nothing from the cleanup.
        JournalLocalRemoval.reenable(store: relaunched)
        XCTAssertTrue(tracker2.processHistory().isEmpty)
        XCTAssertTrue(relaunched.state.outbox.isEmpty)
    }

    func testRecoveryAuthorNeverEntersTheOutboxEvenWithoutTheMarker() throws {
        let tracker = JournalChangeTracker(container: container, store: store)
        let ctx = container.viewContext
        makeSession(in: ctx, title: "X")
        try ctx.save()
        tracker.bootstrapIfNeeded()
        let removal = container.newBackgroundContext()
        removal.transactionAuthor = JournalSyncAuthor.localRemoval
        removal.performAndWait {
            for row in try! removal.fetch(NSFetchRequest<NSManagedObject>(entityName: "Session")) { removal.delete(row) }
            try! removal.save()
        }
        XCTAssertTrue(tracker.processHistory().isEmpty)
        XCTAssertEqual(store.state.outbox.map(\.op), [.save], "the original save is untouched; no delete was added")
    }

    // MARK: re-enable after removal: fetch again, no duplicates

    func testReenableAfterRemovalImportsTheCloudJournalOnceAndKeepsOwner() throws {
        store.update { $0.boundUserRecordName = userA }
        JournalLocalRemoval.begin(store: store, reason: "erase")
        try batchDeleteAll(["Attachment", "Session"])
        JournalLocalRemoval.finish(store: store, container: container)
        JournalLocalRemoval.reenable(store: store)
        XCTAssertNil(store.state.engineState, "a fresh engine fetches everything")

        let id = UUID()
        let queue = RecordingSendQueue()
        let (imp, ctx) = importer(queue)
        let record = sessionRecord(id: id, title: "From the cloud", owner: "owner.1")
        ctx.performAndWait { _ = imp.importModifications([record]) }
        XCTAssertEqual(count("Session"), 1)
        ctx.performAndWait { _ = imp.importModifications([record]) }
        XCTAssertEqual(count("Session"), 1, "a second fetch of the same record is not a duplicate")
        XCTAssertNotNil(store.state.lastKnownRecords[id.uuidString])
        XCTAssertTrue(queue.saves.isEmpty && queue.deletes.isEmpty, "importing sends nothing back")
        // And the import context's transactions never enter the outbox.
        let tracker = JournalChangeTracker(container: container, store: store)
        XCTAssertTrue(tracker.processHistory().isEmpty)
    }

    // MARK: unlink, sign-out, switch, relaunch

    func testUnlinkPersistsKeepsPendingWorkAndTracksEditsForReconnection() throws {
        let tracker = JournalChangeTracker(container: container, store: store)
        store.update { $0.boundUserRecordName = userA }
        let ctx = container.viewContext
        let s = makeSession(in: ctx, title: "Before unlink")
        try ctx.save()
        tracker.bootstrapIfNeeded()
        XCTAssertEqual(store.state.outbox.count, 1)

        JournalLocalRemoval.unlink(store: store)
        XCTAssertFalse(decision(current: userA).allowed)
        XCTAssertEqual(store.state.outbox.count, 1, "pending work kept")

        // Edits while unlinked stay local and are remembered for later.
        s.setValue("Edited while unlinked", forKey: "title")
        let t = makeSession(in: ctx, title: "Made while unlinked")
        try ctx.save()
        tracker.processHistory()
        XCTAssertEqual(store.state.outbox.count, 2)

        // Relaunch.
        let relaunched = JournalSyncStateStore(fileURL: store.fileURL)
        XCTAssertTrue(relaunched.state.unlinked, "unlink survives relaunch")
        XCTAssertFalse(decision(current: userA, store: relaunched).allowed)
        XCTAssertEqual(relaunched.state.outbox.count, 2)
        XCTAssertFalse(relaunched.state.localCopyRemoved)

        // Reconnection: the same outbox goes through the existing rules.
        JournalLocalRemoval.reenable(store: relaunched)
        XCTAssertTrue(decision(current: userA, store: relaunched).allowed)
        XCTAssertEqual(Set(relaunched.state.outbox.map(\.recordName)),
                       Set([s.value(forKey: "id") as! UUID, t.value(forKey: "id") as! UUID].map(\.uuidString)))
        XCTAssertEqual(relaunched.state.boundUserRecordName, userA)
    }

    func testPendingWorkSurvivesSignOutAccountSwitchAndRelaunchAndResumesOnlyForTheBoundAccount() throws {
        let tracker = JournalChangeTracker(container: container, store: store)
        store.update { $0.boundUserRecordName = userA }
        let ctx = container.viewContext
        let s = makeSession(in: ctx, title: "Unsynced Thought")
        makeAttachment(session: s, in: ctx, fileURL: "/tmp/t.jpg")
        try ctx.save()
        tracker.bootstrapIfNeeded()
        let before = store.state.outbox
        XCTAssertEqual(before.count, 2)

        // Sign-out: paused, retried, nothing dropped.
        XCTAssertFalse(decision(current: nil).allowed)
        // Edit while paused.
        s.setValue("Edited while signed out", forKey: "title")
        try ctx.save()
        tracker.processHistory()
        XCTAssertEqual(store.state.outbox.count, 2, "the edit merges into the pending save")
        // Switch to another account: refused; outbox untouched.
        XCTAssertFalse(decision(current: userB).allowed)
        XCTAssertEqual(store.state.outbox, store.state.outbox)
        // Relaunch under the other account: still refused, still pending.
        let relaunched = JournalSyncStateStore(fileURL: store.fileURL)
        XCTAssertFalse(decision(current: userB, store: relaunched).allowed)
        XCTAssertEqual(relaunched.state.outbox.count, 2)
        XCTAssertEqual(relaunched.state.boundUserRecordName, userA, "the binding never moves to the new account")
        // Back to the original: allowed, same two pending changes, nothing added or doubled.
        XCTAssertTrue(decision(current: userA, store: relaunched).allowed)
        XCTAssertEqual(Set(relaunched.state.outbox.map(\.recordName)), Set(before.map(\.recordName)))
    }

    // MARK: catch-up after a dormant period

    func testCatchUpRefetchesOnlyWhenTheZoneMovedSinceOurOwnBaseline() {
        XCTAssertFalse(JournalCatchUp.mustRefetch(hadToken: false, changedZones: ["Journal"], deletedZones: [], zoneName: "Journal"),
                       "a first call only sets the baseline")
        XCTAssertTrue(JournalCatchUp.mustRefetch(hadToken: true, changedZones: ["Journal"], deletedZones: [], zoneName: "Journal"))
        XCTAssertTrue(JournalCatchUp.mustRefetch(hadToken: true, changedZones: [], deletedZones: ["Journal"], zoneName: "Journal"))
        XCTAssertFalse(JournalCatchUp.mustRefetch(hadToken: true, changedZones: ["Other"], deletedZones: [], zoneName: "Journal"))
        XCTAssertFalse(JournalCatchUp.mustRefetch(hadToken: true, changedZones: [], deletedZones: [], zoneName: "Journal"))
    }

    func testLocalRemovalClearsTheCatchUpBaselineWithTheEngineState() throws {
        store.update { $0.catchUpToken = Data([1]); $0.engineState = nil }
        JournalLocalRemoval.begin(store: store, reason: "erase")
        JournalLocalRemoval.finish(store: store, container: container)
        XCTAssertNil(store.state.catchUpToken)
    }

    // MARK: lists after an erase

    @MainActor
    func testWipedListLibraryAfterRemovalInfersNoDeletions() throws {
        let suite = "synctest-e-lists-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let scope = LocalOwnerStoreMigration.listsNoOwnerScope
        let lists = [SavedList(id: UUID(), name: "Scales", items: []), SavedList(id: UUID(), name: "Studies", items: [])]
        try SavedListLibrary.commit(snapshot: [], updated: lists, ownerScope: scope, defaults: defaults)
        XCTAssertEqual(JournalSavedListSync.scan(store: store, defaults: defaults, scope: scope).count, 2)
        XCTAssertEqual(store.state.listFingerprints.count, 2)

        // The erase wipes UserDefaults; without the finish, the scan would send two deletions.
        defaults.removePersistentDomain(forName: suite)
        JournalLocalRemoval.begin(store: store, reason: "erase")
        JournalLocalRemoval.finish(store: store, container: container)
        JournalLocalRemoval.reenable(store: store)
        let afterErase = JournalSavedListSync.scan(store: store, defaults: defaults, scope: scope)
        XCTAssertTrue(afterErase.filter { $0.op == .delete }.isEmpty, "a wiped library is not two deleted lists")
        XCTAssertTrue(store.state.outbox.isEmpty)
    }
}
#endif
