//
//  JournalDeleteQueuedPublishTests.swift
//  MOTIVOTests
//
//  Journal delete must not leave ANY queued, not-yet-dispatched publish for the
//  deleted entry — of any owner on this installation, or in quarantine — that a
//  later flush could use to re-create its post (Samuel's decision D1, pending
//  shares). Withdrawals stay owned by the account that queued the work.
//
//  REPRODUCED FIRST at 369bd53: after a journal delete the next flush sent
//  POST <id> 201. Same-owner fix at a0313cb; this revision covers every owner,
//  quarantine, Solo, the same-turn local deletion and refusal reasons.
//
//  PRODUCTION PATHS: `JournalDeleteBackendStep.run` / `runLocalOnly` with the
//  production `deleteSessionLocally`, the real `SessionSyncQueue`, and the real
//  C1 `SharingHandoff` stage and recovery.
//
//  SYNTHETIC ONLY. QueueStubServer answers loopback 127.0.0.1:9 alone. Owners
//  are synthetic UUIDs with unsigned synthetic tokens; Sessions and media files
//  are disposable and removed in tearDown. No live backend, account or personal
//  data.
//
//  NOT COVERED, BY DESIGN: a publish already dispatched and in flight, and posts
//  already acknowledged (published and dequeued) — the latter needs ownership
//  evidence that is scoped separately.
//

import XCTest
import CoreData
@testable import Etudes

@MainActor
final class JournalDeleteQueuedPublishTests: XCTestCase {
    private var queue: SessionSyncQueue { SessionSyncQueue.shared }
    private var container: NSPersistentContainer { PersistenceController.shared.container }
    private var ctx: NSManagedObjectContext { container.viewContext }
    private let ownerA = QueueStubFixture.ownerUID
    private let ownerB = "00000000-0000-0000-0000-0000000c8702"
    private var createdSessionIDs: [UUID] = []
    private var scratchFiles: [URL] = []

    override func setUp() async throws {
        try await super.setUp()
        QueueStubFixture.connect()
        try LocalStackSupport.requireRealBackend(baseURL: QueueStubServer.baseURL.absoluteString)
        queue.clear()
        _ = queue.streamForNewChoice()   // C1 install stream, for staged markers
    }

    override func tearDown() async throws {
        QueueStubFixture.attachTimeline(to: self)
        QueueStubServer.releaseAll()
        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil
        JournalDeleteBackendStep.unitTestFailNextLocalSave = false
        // A latched store would poison later cases in this process (C-91).
        if !queue.reconcileState.isOK || queue.memoryDivergesFromDisk {
            try? FileManager.default.removeItem(at: SessionSyncQueue.currentFileURL())
            _ = queue.attemptStoreRecovery()
        }
        queue.clear()
        for id in createdSessionIDs {
            if let o = fetchSession(id) { ctx.delete(o) }
        }
        try? ctx.save()
        createdSessionIDs = []
        for f in scratchFiles { try? FileManager.default.removeItem(at: f) }
        scratchFiles = []
        QueueStubFixture.disconnect()
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func key(_ op: String, _ id: UUID) -> String { QueueStubServer.key(op, id) }

    private func signIn(_ uid: String) {
        NetworkManager.shared.setBearerToken(QueueStubFixture.token(sub: uid, jti: "signin-\(uid.suffix(4))"))
        UserDefaults.standard.set(uid, forKey: "supabaseUserID_v1")
        queue.noteIdentityChanged(reason: "test:identity→\(uid.suffix(4))")
        XCTAssertEqual(SessionSyncQueue.currentOwner(), uid, "fixture: the app must read this identity")
    }

    private func signOut() {
        NetworkManager.shared.setBearerToken(nil)
        UserDefaults.standard.removeObject(forKey: "supabaseUserID_v1")
        queue.noteIdentityChanged(reason: "test:signOut")
        XCTAssertNil(SessionSyncQueue.currentOwner(), "fixture: signed out")
    }

    /// A fresh read of the store, independent of the view context.
    private func sessionExistsInStore(_ id: UUID) -> Bool {
        let c = container.newBackgroundContext()
        var exists = false
        c.performAndWait {
            let r = NSFetchRequest<NSManagedObject>(entityName: "Session")
            r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            exists = ((try? c.count(for: r)) ?? 0) > 0
        }
        return exists
    }

    private func fetchSession(_ id: UUID) -> NSManagedObject? {
        let r = NSFetchRequest<NSManagedObject>(entityName: "Session")
        r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        r.fetchLimit = 1
        return (try? ctx.fetch(r))?.first
    }

    @discardableResult
    private func newSharedSession(withMediaFile: Bool = false) throws -> (id: UUID, file: URL?) {
        let id = UUID()
        let s = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        s.setValue(id, forKey: "id")
        s.setValue(Date(), forKey: "timestamp")
        s.setValue("synthetic journal-delete fixture", forKey: "title")
        s.setValue(true, forKey: "isPublic")
        var file: URL?
        if withMediaFile {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = docs.appendingPathComponent("\(UUID().uuidString).m4a")
            try Data("synthetic".utf8).write(to: url)
            scratchFiles.append(url)
            let a = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: ctx)
            a.setValue(UUID(), forKey: "id")
            a.setValue(Date(), forKey: "createdAt")
            a.setValue(url.path, forKey: "fileURL")
            a.setValue("audio", forKey: "kind")
            a.setValue(s, forKey: "session")
            file = url
        }
        try ctx.save()
        createdSessionIDs.append(id)
        return (id, file)
    }

    private func publishPayload(_ id: UUID, owner: String?, token: UUID? = nil) -> SessionSyncQueue.PostPublishPayload {
        var p = SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: id, sessionTimestamp: nil, title: "synthetic journal-delete fixture",
            durationSeconds: 60, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil, isPublic: true
        ).withOwner(owner)
        p.choiceToken = token
        return p
    }

    /// A shared session whose publish is QUEUED and NOT dispatched: its first
    /// attempt failed with a 500, so it waits for the next flush.
    private func sharedSessionWithQueuedPublish() async throws -> UUID {
        let id = try newSharedSession().id
        XCTAssertTrue(queue.enqueue(publishPayload(id, owner: ownerA)), "setup: the publish is durable")
        QueueStubServer.respond(key("POST", id), with: 500)
        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(key("POST", id)), 1, "setup: the first attempt was sent")
        XCTAssertFalse(QueueStubServer.hasRow(id), "setup: no row after the failed attempt")
        XCTAssertEqual(item(id, ownerA)?.op, .publish, "setup: the publish is still queued")
        return id
    }

    private func item(_ id: UUID, _ owner: String) -> SessionSyncQueue.PostPublishPayload? {
        queue.items.first { $0.id == id && $0.ownerUserID == owner }
    }

    private func quarantinedItem(_ id: UUID) -> SessionSyncQueue.PostPublishPayload? {
        queue.quarantined.first { $0.id == id }
    }

    private func localDelete(_ id: UUID) -> () -> Bool {
        let oid = fetchSession(id)!.objectID
        return { JournalDeleteBackendStep.deleteSessionLocally(objectID: oid) }
    }

    /// ContentView's Connected branch.
    private func connectedDelete(_ id: UUID, capturedOwner: String?) async -> JournalDeleteBackendStep.Outcome {
        await JournalDeleteBackendStep.run(postID: id, capturedOwner: capturedOwner, deleteLocally: localDelete(id))
    }

    /// ContentView's Solo / lapsed / signed-out branch.
    private func localOnlyDelete(_ id: UUID, capturedOwner: String?) -> JournalDeleteBackendStep.Outcome {
        JournalDeleteBackendStep.runLocalOnly(postID: id, capturedOwner: capturedOwner, deleteLocally: localDelete(id))
    }

    private func failWritesLeavingAnOlderValidEnvelope() throws {
        let file = SessionSyncQueue.currentFileURL()
        let older = try Data(contentsOf: file)
        SessionSyncQueueStore.unitTestCorruptAfterWrite = { try? older.write(to: file, options: .atomic) }
    }

    private func onDisk() throws -> SessionSyncQueueEnvelope {
        try JSONDecoder().decode(SessionSyncQueueEnvelope.self, from: Data(contentsOf: SessionSyncQueue.currentFileURL()))
    }

    private func onDiskOp(_ id: UUID, owner: String) throws -> SessionSyncQueue.PostOp? {
        try onDisk().items.first { $0.id == id && $0.ownerUserID == owner }?.op
    }

    // MARK: - The reproduction, now the requirement

    func testJournalDelete_ThenLaterFlush_DoesNotRecreateThePost() async throws {
        let id = try await sharedSessionWithQueuedPublish()

        QueueStubServer.mark("member deletes the journal entry")
        let outcome = await connectedDelete(id, capturedOwner: SessionSyncQueue.currentOwner())
        XCTAssertEqual(outcome, .deleted)
        XCTAssertFalse(sessionExistsInStore(id))
        XCTAssertEqual(item(id, ownerA)?.op, .unshare, "the queued publish was superseded")

        QueueStubServer.mark("a later flush (next foreground)")
        let afterDelete = QueueStubServer.position
        await queue.flushNow()

        XCTAssertFalse(QueueStubServer.arrived(key("POST", id), since: afterDelete),
                       "a post the member deleted must not be published afterwards")
        XCTAssertFalse(QueueStubServer.hasRow(id))
        XCTAssertNil(item(id, ownerA), "the withdrawal was acknowledged")
    }

    // MARK: - Unchanged paths

    func testNoQueuedWork_RequestsAndQueueUnchanged() async throws {
        let id = try newSharedSession().id
        QueueStubServer.seedRow(id, objectPaths: [])
        let before = queue.items
        let start = QueueStubServer.arrivals.count

        let outcome = await connectedDelete(id, capturedOwner: SessionSyncQueue.currentOwner())

        XCTAssertEqual(outcome, .deleted)
        XCTAssertEqual(Array(QueueStubServer.arrivals.dropFirst(start)),
                       [key("GET", id), key("DELETE", id)], "only the existing backend delete")
        XCTAssertEqual(queue.items, before, "no queue write")
        XCTAssertTrue(queue.isFullySaved)
        XCTAssertFalse(sessionExistsInStore(id))
    }

    func testBackendDeleteFailure_RefusedNoQueueWriteAndLocalKept() async throws {
        let id = try await sharedSessionWithQueuedPublish()
        let before = queue.items
        QueueStubServer.respond(key("GET", id), with: 500)

        let outcome = await connectedDelete(id, capturedOwner: SessionSyncQueue.currentOwner())

        XCTAssertEqual(outcome, .refused(.backendDeleteUnconfirmed))
        XCTAssertTrue(sessionExistsInStore(id), "the local entry is kept")
        XCTAssertEqual(queue.items, before, "no owner's item changed")
        XCTAssertEqual(QueueStubServer.count(key("DELETE", id)), 0)
    }

    // MARK: - Ownership

    func testOwnerSwitchDuringBackendDelete_RefusesAndWritesNothing() async throws {
        let id = try await sharedSessionWithQueuedPublish()
        let before = queue.items
        let captured = SessionSyncQueue.currentOwner()
        QueueStubServer.hold(key("DELETE", id))

        let run = Task { await self.connectedDelete(id, capturedOwner: captured) }
        let held = await QueueStubFixture.poll(timeout: 5) { QueueStubServer.count(self.key("DELETE", id)) == 1 }
        XCTAssertTrue(held, "setup: the backend DELETE is in flight")
        signIn(ownerB)
        QueueStubServer.release(key("DELETE", id))
        let outcome = await run.value

        XCTAssertEqual(outcome, .refused(.identityChanged))
        XCTAssertTrue(sessionExistsInStore(id), "the local entry is kept")
        XCTAssertEqual(queue.items, before, "nothing written")
    }

    /// D1. Another account's queued publish becomes a withdrawal OWNED BY THAT
    /// ACCOUNT; nothing is sent as it while it is not current, and when it signs
    /// in, the withdrawal is sent as it and no POST is.
    func testForeignOwnerQueuedPublish_BecomesItsOwnWithdrawal() async throws {
        let id = try newSharedSession().id
        XCTAssertTrue(queue.enqueue(publishPayload(id, owner: ownerB)), "setup: B's publish is durable")

        let start = QueueStubServer.position
        let outcome = await connectedDelete(id, capturedOwner: SessionSyncQueue.currentOwner())
        XCTAssertEqual(outcome, .deleted)
        XCTAssertEqual(item(id, ownerB)?.op, .unshare, "B's publish is now B's withdrawal")
        XCTAssertNil(item(id, ownerA), "nothing created for A")
        XCTAssertFalse(QueueStubServer.subjects.contains(ownerB), "nothing sent as B while A is current")

        signIn(ownerB)
        await queue.flushNow()
        XCTAssertFalse(QueueStubServer.arrived(key("POST", id), since: start), "no publish, ever")
        XCTAssertEqual(QueueStubServer.subjects(for: key("DELETE", id)).last, ownerB,
                       "B's withdrawal is sent as B")
        XCTAssertNil(item(id, ownerB), "acknowledged")
    }

    /// Signed out: the captured owner is nil. Other owners' work is still
    /// converted, and nothing is sent.
    func testSignedOut_ConvertsHeldWorkWithoutSending() throws {
        let id = try newSharedSession().id
        XCTAssertTrue(queue.enqueue(publishPayload(id, owner: ownerB)))
        signOut()
        let start = QueueStubServer.arrivals.count

        XCTAssertEqual(localOnlyDelete(id, capturedOwner: nil), .deleted)

        XCTAssertEqual(item(id, ownerB)?.op, .unshare)
        XCTAssertEqual(QueueStubServer.arrivals.count, start, "no requests")
        XCTAssertFalse(sessionExistsInStore(id))
    }

    /// Solo: no backend call. The member's own publish becomes their withdrawal,
    /// held until they are Connected, then sent as them with no POST.
    func testSolo_OwnPublishBecomesWithdrawal_SentOnlyWhenConnected() async throws {
        let id = try newSharedSession().id
        XCTAssertTrue(queue.enqueue(publishPayload(id, owner: ownerA)))
        setBackendMode(.localSimulation)
        let start = QueueStubServer.position

        XCTAssertEqual(localOnlyDelete(id, capturedOwner: SessionSyncQueue.currentOwner()), .deleted)
        XCTAssertEqual(item(id, ownerA)?.op, .unshare)
        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.position, start, "Solo sends nothing")

        setBackendMode(.backendConnected)
        await queue.flushNow()
        XCTAssertFalse(QueueStubServer.arrived(key("POST", id), since: start))
        XCTAssertEqual(QueueStubServer.subjects(for: key("DELETE", id)).last, ownerA)
    }

    func testSolo_IdentityChanged_Refused() throws {
        let id = try newSharedSession().id
        XCTAssertTrue(queue.enqueue(publishPayload(id, owner: ownerA)))
        let before = queue.items
        XCTAssertEqual(localOnlyDelete(id, capturedOwner: ownerB), .refused(.identityChanged))
        XCTAssertEqual(queue.items, before)
        XCTAssertTrue(sessionExistsInStore(id))
    }

    /// Quarantined (unknown-owner) work becomes an UNOWNED withdrawal and stays
    /// quarantined; quarantine for other posts is untouched.
    func testQuarantinedPublish_BecomesUnownedWithdrawal() throws {
        let id = try newSharedSession().id
        let other = UUID()
        queue.enqueue(publishPayload(id, owner: nil))
        queue.enqueue(publishPayload(other, owner: nil))
        XCTAssertEqual(quarantinedItem(id)?.op, .publish, "setup: quarantined")
        let otherBefore = quarantinedItem(other)

        XCTAssertEqual(localOnlyDelete(id, capturedOwner: SessionSyncQueue.currentOwner()), .deleted)

        XCTAssertEqual(quarantinedItem(id)?.op, .unshare)
        XCTAssertNil(quarantinedItem(id)?.ownerUserID, "no owner invented")
        XCTAssertFalse(queue.items.contains { $0.id == id }, "still not dispatchable")
        XCTAssertEqual(quarantinedItem(other), otherBefore, "other quarantine untouched")
        XCTAssertEqual(try onDisk().quarantined.first { $0.id == id }?.op, .unshare, "durable")
    }

    /// A, B and quarantine converted by ONE write: when that write fails, none of
    /// them is on disk as a withdrawal — no partial state.
    func testSeveralOwnersAndQuarantine_OneWrite() throws {
        let id = try newSharedSession().id
        let unrelated = UUID()
        XCTAssertTrue(queue.enqueue(publishPayload(id, owner: ownerA)))
        XCTAssertTrue(queue.enqueue(publishPayload(id, owner: ownerB)))
        XCTAssertTrue(queue.enqueue(publishPayload(unrelated, owner: ownerA)))
        queue.enqueue(publishPayload(id, owner: nil))
        let unrelatedBefore = item(unrelated, ownerA)

        try failWritesLeavingAnOlderValidEnvelope()
        XCTAssertEqual(localOnlyDelete(id, capturedOwner: SessionSyncQueue.currentOwner()), .refused(.queueNotSaved))
        let failedDisk = try onDisk()
        XCTAssertEqual(failedDisk.items.filter { $0.id == id }.map(\.op), [.publish, .publish], "no partial write")
        XCTAssertTrue(sessionExistsInStore(id))

        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil
        XCTAssertEqual(localOnlyDelete(id, capturedOwner: SessionSyncQueue.currentOwner()), .deleted)
        let disk = try onDisk()
        XCTAssertEqual(disk.items.filter { $0.id == id }.map(\.op), [.unshare, .unshare])
        XCTAssertEqual(Set(disk.items.filter { $0.id == id }.compactMap(\.ownerUserID)), [ownerA, ownerB])
        XCTAssertEqual(disk.quarantined.first { $0.id == id }?.op, .unshare)
        XCTAssertEqual(item(unrelated, ownerA), unrelatedBefore, "other posts untouched")
    }

    // MARK: - Durability

    func testRepeatDelete_AfterFailedWrite_RefusesUntilDurable() async throws {
        let id = try await sharedSessionWithQueuedPublish()
        try failWritesLeavingAnOlderValidEnvelope()

        let first = await connectedDelete(id, capturedOwner: SessionSyncQueue.currentOwner())
        XCTAssertEqual(first, .refused(.queueNotSaved))
        XCTAssertEqual(item(id, ownerA)?.op, .unshare, "memory holds the newer intent")
        XCTAssertEqual(try onDiskOp(id, owner: ownerA), .publish, "disk still holds the older publish")
        XCTAssertTrue(sessionExistsInStore(id))

        let second = await connectedDelete(id, capturedOwner: SessionSyncQueue.currentOwner())
        XCTAssertEqual(second, .refused(.queueNotSaved), "the in-memory unshare must not bypass durability")
        XCTAssertTrue(sessionExistsInStore(id))

        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil
        let third = await connectedDelete(id, capturedOwner: SessionSyncQueue.currentOwner())
        XCTAssertEqual(third, .deleted)
        XCTAssertEqual(try onDiskOp(id, owner: ownerA), .unshare)

        queue.unitTestSimulateRelaunch()
        XCTAssertEqual(item(id, ownerA)?.op, .unshare, "after a relaunch the withdrawal is what reloads")
        let afterRelaunch = QueueStubServer.position
        await queue.flushNow()
        XCTAssertFalse(QueueStubServer.arrived(key("POST", id), since: afterRelaunch))
    }

    func testHaltedStoreAtLaunch_RecoversThenConvertsOtherOwner() async throws {
        let id = try newSharedSession().id
        XCTAssertTrue(queue.enqueue(publishPayload(id, owner: ownerB)))
        queue.unitTestSimulateStartupHalt()
        XCTAssertNil(item(id, ownerB), "setup: memory does not see B's publish")

        XCTAssertEqual(localOnlyDelete(id, capturedOwner: SessionSyncQueue.currentOwner()), .deleted)
        XCTAssertEqual(item(id, ownerB)?.op, .unshare, "found on disk and converted")
        XCTAssertEqual(try onDiskOp(id, owner: ownerB), .unshare)
    }

    func testHaltedStoreUnrecoverable_Refuses() async throws {
        let id = try await sharedSessionWithQueuedPublish()
        try failWritesLeavingAnOlderValidEnvelope()
        queue.unitTestSimulateStartupHalt()

        let outcome = await connectedDelete(id, capturedOwner: SessionSyncQueue.currentOwner())
        XCTAssertEqual(outcome, .refused(.queueNotSaved))
        XCTAssertTrue(sessionExistsInStore(id))
    }

    // MARK: - C1 handoff: ledger and markers

    /// T14. The verified ledger is identical before and after conversion, and the
    /// withdrawal carries no token.
    func testConversionLeavesHandoffLedgerUntouched() throws {
        let id = try newSharedSession().id
        let token = UUID()
        XCTAssertTrue(queue.enqueue(publishPayload(id, owner: ownerA, token: token)))
        XCTAssertEqual(queue.verifiedHandoffToken(owner: ownerA, postID: id), token, "setup: verified")

        XCTAssertEqual(localOnlyDelete(id, capturedOwner: SessionSyncQueue.currentOwner()), .deleted)

        XCTAssertEqual(queue.verifiedHandoffToken(owner: ownerA, postID: id), token, "ledger untouched")
        XCTAssertNil(item(id, ownerA)?.choiceToken, "the withdrawal carries no token")
        XCTAssertEqual(try onDisk().handedOff?[SessionSyncQueue.handoffLedgerKey(owner: ownerA, postID: id)], token)
    }

    /// T15. The local save fails after the conversion, so the session and its
    /// marker survive. Replay then finds the marker's token verified: it clears
    /// the marker and does NOT re-enqueue the publish.
    func testLocalSaveFailure_SurvivingMarkerIsNotReplayedOverTheWithdrawal() async throws {
        let id = try newSharedSession().id
        let session = fetchSession(id)!
        let token = UUID()
        let choice = publishPayload(id, owner: ownerA, token: token)
        try SharingHandoff.stage(choice, on: session, queue: queue)
        try ctx.save()
        XCTAssertTrue(queue.enqueue(choice), "setup: the choice was durably taken, marker kept")

        JournalDeleteBackendStep.unitTestFailNextLocalSave = true
        let outcome = await connectedDelete(id, capturedOwner: SessionSyncQueue.currentOwner())
        XCTAssertEqual(outcome, .refused(.localSaveFailed))
        XCTAssertTrue(sessionExistsInStore(id), "the entry is kept")
        XCTAssertEqual(item(id, ownerA)?.op, .unshare)

        let state = SharingHandoffRecovery.run(reason: "test", container: container, queue: queue)
        XCTAssertEqual(state, .complete)
        XCTAssertEqual(item(id, ownerA)?.op, .unshare, "the verified marker was only cleared, not replayed")
        let start = QueueStubServer.position
        await queue.flushNow()
        XCTAssertFalse(QueueStubServer.arrived(key("POST", id), since: start))
    }

    /// T16. A marker whose choice the queue never took (a crash before enqueue).
    /// After a successful delete the row, and so the marker, are gone: replay
    /// re-enqueues nothing.
    /// Recovery runs IMMEDIATELY after the helper returns, in the same turn, while
    /// the view context has not merged yet and still holds the stale Session with
    /// its marker. Recovery reads markers through its own fresh context
    /// (`SharingHandoff.readMarkers`), so the stale object cannot feed it.
    func testUntakenMarker_GoneWithTheRow_NothingReplayed() throws {
        let id = try newSharedSession().id
        let session = fetchSession(id)!
        try SharingHandoff.stage(publishPayload(id, owner: ownerA, token: UUID()), on: session, queue: queue)
        try ctx.save()

        XCTAssertEqual(localOnlyDelete(id, capturedOwner: SessionSyncQueue.currentOwner()), .deleted)
        XCTAssertFalse(session.isDeleted, "setup: the view context has not merged yet (stale)")
        XCTAssertNotNil(session.value(forKey: SharingHandoff.attribute), "setup: its stale marker is still visible there")
        XCTAssertEqual(SharingHandoffRecovery.run(reason: "test", container: container, queue: queue), .complete)
        XCTAssertFalse(queue.items.contains { $0.id == id && $0.op == .publish }, "nothing re-enqueued")
    }

    // MARK: - Local deletion

    /// A failed local save deletes nothing: the session is in the store, its media
    /// file is still on disk, the view context holds no pending deletion, and an
    /// unrelated later save does not commit one.
    /// An unrelated UNSAVED edit already pending in the view context survives the
    /// failure untouched, no deletion is left pending there, and saving that edit
    /// later commits no deletion.
    func testLocalSaveFailure_KeepsSessionAndFiles_AndNothingPending() throws {
        let (id, file) = try newSharedSession(withMediaFile: true)
        let other = try newSharedSession().id
        fetchSession(other)!.setValue("unsaved edit", forKey: "title")
        XCTAssertTrue(ctx.hasChanges, "setup: an unrelated edit is pending")

        JournalDeleteBackendStep.unitTestFailNextLocalSave = true
        XCTAssertEqual(localOnlyDelete(id, capturedOwner: SessionSyncQueue.currentOwner()), .refused(.localSaveFailed))
        XCTAssertTrue(sessionExistsInStore(id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file!.path), "files removed only after a successful save")
        XCTAssertTrue(ctx.deletedObjects.isEmpty, "no deletion pending in the editors' context")
        XCTAssertFalse(fetchSession(id)!.isDeleted)
        XCTAssertEqual(fetchSession(other)!.value(forKey: "title") as? String, "unsaved edit", "the unrelated edit survives")

        try ctx.save()
        XCTAssertTrue(sessionExistsInStore(id), "saving the unrelated edit commits no deletion")
        XCTAssertEqual(storedTitle(other), "unsaved edit")
    }

    /// Success: the row leaves the journal's own context through the normal merge,
    /// and an unrelated unsaved edit there survives and still saves.
    func testLocalDelete_Success_RemovesFilesAfterSave_MergesAndKeepsEdits() async throws {
        let (id, file) = try newSharedSession(withMediaFile: true)
        let other = try newSharedSession().id
        fetchSession(other)!.setValue("unsaved edit", forKey: "title")
        let registered = fetchSession(id)!   // the object the journal's context holds

        XCTAssertEqual(localOnlyDelete(id, capturedOwner: SessionSyncQueue.currentOwner()), .deleted)
        XCTAssertFalse(sessionExistsInStore(id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file!.path))
        XCTAssertFalse(registered.isDeleted, "setup: not merged yet in this turn")

        // The normal merge (automaticallyMergesChangesFromParent) removes it from the
        // journal's context. A fetch alone would not prove this: it reads the store.
        let merged = await QueueStubFixture.poll(timeout: 3) {
            registered.isDeleted || registered.managedObjectContext == nil
        }
        XCTAssertTrue(merged, "the view context merged the deletion")
        XCTAssertNil(fetchSession(id), "the journal's context no longer returns the row")
        XCTAssertEqual(fetchSession(other)!.value(forKey: "title") as? String, "unsaved edit", "the unrelated edit survives")
        try ctx.save()
        XCTAssertEqual(storedTitle(other), "unsaved edit")
    }

    private func storedTitle(_ id: UUID) -> String? {
        let c = container.newBackgroundContext()
        var title: String?
        c.performAndWait {
            let r = NSFetchRequest<NSManagedObject>(entityName: "Session")
            r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            title = (try? c.fetch(r))?.first?.value(forKey: "title") as? String
        }
        return title
    }

    // MARK: - U3: already-acknowledged posts (candidate withdrawal attempts)

    private let ownerC = "00000000-0000-0000-0000-0000000c8703"
    private let ownerX = "00000000-0000-0000-0000-0000000c87ff"

    /// A publish as the CURRENT owner, with a token, flushed and acknowledged:
    /// the queue item is gone, the row exists, and the ledger names the owner.
    private func acknowledgedPublish(_ id: UUID, token: UUID? = UUID()) async {
        XCTAssertTrue(queue.enqueue(publishPayload(id, owner: SessionSyncQueue.currentOwner(), token: token)))
        await queue.flushNow()
        XCTAssertTrue(QueueStubServer.hasRow(id), "setup: published")
        XCTAssertFalse(queue.items.contains { $0.id == id }, "setup: acknowledged, no queue item left")
    }

    private func deleteURL(_ id: UUID) -> String? {
        QueueStubServer.allURLs.last { $0.key == key("DELETE", id) }?.url
    }

    /// The ledger owner of an acknowledged post gets a withdrawal attempt, held in
    /// Solo, then sent AS that owner with its owner filter; the row goes.
    func testAcknowledged_LedgerOwner_AttemptSentAsOwnerWithFilter() async throws {
        let id = try newSharedSession().id
        await acknowledgedPublish(id)
        let ledgerBefore = queue.verifiedHandoffToken(owner: ownerA, postID: id)
        XCTAssertNotNil(ledgerBefore, "setup: the ledger names A")
        setBackendMode(.localSimulation)
        let start = QueueStubServer.position

        XCTAssertEqual(JournalDeleteBackendStep.runLocalOnly(postID: id, capturedOwner: SessionSyncQueue.currentOwner(),
                                                            sessionWasShared: false, deleteLocally: localDelete(id)), .deleted)
        XCTAssertEqual(item(id, ownerA)?.op, .unshare, "from the ledger alone (sessionWasShared false)")
        XCTAssertEqual(QueueStubServer.position, start, "Solo sends nothing")
        XCTAssertEqual(queue.verifiedHandoffToken(owner: ownerA, postID: id), ledgerBefore, "ledger untouched")

        setBackendMode(.backendConnected)
        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.subjects(for: key("DELETE", id)).last, ownerA)
        XCTAssertTrue(deleteURL(id)?.contains("owner_user_id=eq.\(ownerA)") == true, "owner-filtered")
        XCTAssertFalse(QueueStubServer.hasRow(id))
        XCTAssertNil(item(id, ownerA), "acknowledged")
    }

    /// Signed out: B's acknowledged post gets a B-owned attempt, nothing is sent,
    /// and only when B is current is it sent, as B.
    func testAcknowledged_SignedOut_LedgerOwnerB_WaitsForB() async throws {
        let id = try newSharedSession().id
        signIn(ownerB)
        await acknowledgedPublish(id)
        signOut()
        let start = QueueStubServer.arrivals.count

        XCTAssertEqual(JournalDeleteBackendStep.runLocalOnly(postID: id, capturedOwner: nil,
                                                            sessionWasShared: true, deleteLocally: localDelete(id)), .deleted)
        XCTAssertEqual(item(id, ownerB)?.op, .unshare)
        XCTAssertEqual(queue.items.filter { $0.id == id }.count, 1, "no other owner invented")
        XCTAssertEqual(QueueStubServer.arrivals.count, start, "nothing sent while signed out")

        signIn(ownerA)
        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(key("DELETE", id)), 0, "not sent while A is current")
        XCTAssertTrue(QueueStubServer.hasRow(id), "held for B")

        signIn(ownerB)
        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.subjects(for: key("DELETE", id)).last, ownerB)
        XCTAssertFalse(QueueStubServer.hasRow(id))
    }

    /// Legacy (acknowledged with no token, so no ledger entry): the captured
    /// identity is attempted only when the entry was shared; signed out, nothing.
    func testLegacy_NoLedger_SelfAttemptOnlyIfShared_NothingWhenSignedOut() async throws {
        let shared = try newSharedSession().id
        let notShared = try newSharedSession().id
        let signedOut = try newSharedSession().id
        await acknowledgedPublish(shared, token: nil)
        await acknowledgedPublish(notShared, token: nil)
        await acknowledgedPublish(signedOut, token: nil)
        XCTAssertNil(queue.verifiedHandoffToken(owner: ownerA, postID: shared), "setup: no ledger entry")
        setBackendMode(.localSimulation)

        XCTAssertEqual(JournalDeleteBackendStep.runLocalOnly(postID: shared, capturedOwner: ownerA,
                                                            sessionWasShared: true, deleteLocally: localDelete(shared)), .deleted)
        XCTAssertEqual(item(shared, ownerA)?.op, .unshare, "self-scoped attempt")

        XCTAssertEqual(JournalDeleteBackendStep.runLocalOnly(postID: notShared, capturedOwner: ownerA,
                                                            sessionWasShared: false, deleteLocally: localDelete(notShared)), .deleted)
        XCTAssertFalse(queue.items.contains { $0.id == notShared }, "not shared: nothing added")

        signOut()
        XCTAssertEqual(JournalDeleteBackendStep.runLocalOnly(postID: signedOut, capturedOwner: nil,
                                                            sessionWasShared: true, deleteLocally: localDelete(signedOut)), .deleted)
        XCTAssertFalse(queue.items.contains { $0.id == signedOut }, "GAP: no evidence, no owner invented")
        XCTAssertTrue(QueueStubServer.hasRow(signedOut), "the legacy signed-out post stays")
    }

    /// A candidate that does NOT own the post: its attempt matches nothing, its
    /// refs read returns nothing, no storage object is touched, and the owner's
    /// row survives.
    func testNonOwnerCandidate_MatchesNothing_RowRefsAndObjectsUntouched() async throws {
        let id = try newSharedSession().id
        QueueStubServer.enforceOwnerFilterForTest()
        QueueStubServer.seedRow(id, objectPaths: ["users/x/\(id.uuidString.lowercased()).m4a"], owner: ownerX)
        setBackendMode(.localSimulation)

        XCTAssertEqual(JournalDeleteBackendStep.runLocalOnly(postID: id, capturedOwner: ownerA,
                                                            sessionWasShared: true, deleteLocally: localDelete(id)), .deleted)
        setBackendMode(.backendConnected)
        let start = QueueStubServer.arrivals.count
        await queue.flushNow()

        let sent = Array(QueueStubServer.arrivals.dropFirst(start))
        XCTAssertEqual(sent, [key("DEMOTE", id), key("GET", id), key("DELETE", id)], "no storage call: \(sent)")
        XCTAssertTrue(QueueStubServer.hasRow(id), "X's row survives")
        XCTAssertNil(item(id, ownerA), "acknowledged as no row matched")
        for k in [key("DEMOTE", id), key("GET", id), key("DELETE", id)] {
            XCTAssertEqual(QueueStubServer.subjects(for: k), [ownerA], "sent as A only")
        }
    }

    /// Several candidates: each is sent only while its own owner is current.
    func testCandidates_EachSentOnlyAsItsOwner() async throws {
        let id = try newSharedSession().id
        signIn(ownerB)
        await acknowledgedPublish(id)          // the ledger names B; the row is B's
        signIn(ownerA)
        QueueStubServer.enforceOwnerFilterForTest()
        setBackendMode(.localSimulation)
        XCTAssertEqual(JournalDeleteBackendStep.runLocalOnly(postID: id, capturedOwner: ownerA,
                                                            sessionWasShared: true, deleteLocally: localDelete(id)), .deleted)
        XCTAssertEqual(Set(queue.items.filter { $0.id == id }.compactMap(\.ownerUserID)), [ownerA, ownerB])

        setBackendMode(.backendConnected)
        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.subjects(for: key("DELETE", id)), [ownerA], "only A's, as A")
        XCTAssertTrue(QueueStubServer.hasRow(id), "A does not own it")
        XCTAssertEqual(item(id, ownerB)?.op, .unshare, "B's attempt still held")

        signIn(ownerB)
        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.subjects(for: key("DELETE", id)).last, ownerB)
        XCTAssertFalse(QueueStubServer.hasRow(id), "the owner's attempt withdrew it")
    }

    /// Only well-formed ledger keys for exactly this post, with a normalised UUID
    /// owner, count. Unowned and malformed keys are skipped.
    func testLedgerOwners_SkipsMalformedAndUnowned() {
        let post = UUID()
        let p = post.uuidString.lowercased()
        let ledger: [String: UUID] = [
            "\(ownerC)|\(p)": UUID(),                    // valid
            "~|\(p)": UUID(),                             // unowned
            "not-a-uuid|\(p)": UUID(),                    // not a UUID
            "\(ownerB.uppercased())|\(p)": UUID(),        // not normalised
            "\(ownerA)|\(UUID().uuidString.lowercased())": UUID(),   // another post
            "\(ownerA)|\(p)|extra": UUID(),              // malformed
            "\(ownerA)|\(p.uppercased())": UUID(),        // suffix not exact
            "": UUID()
        ]
        XCTAssertEqual(SessionSyncQueue.ledgerOwners(for: post, in: ledger), [ownerC])
    }

    /// The same, through the real durable ledger: a file carrying malformed keys is
    /// reloaded, and only the valid owner gets an attempt. The ledger is not modified.
    func testMalformedDurableLedgerKeys_OnlyValidOwnerAttempted() throws {
        let id = try newSharedSession().id
        XCTAssertTrue(queue.enqueue(publishPayload(UUID(), owner: ownerA, token: UUID())), "setup: a store file exists")
        var env = try onDisk()
        let p = id.uuidString.lowercased()
        var ledger = env.handedOff ?? [:]
        ledger["\(ownerC)|\(p)"] = UUID()
        ledger["~|\(p)"] = UUID()
        ledger["garbage|\(p)"] = UUID()
        env.handedOff = ledger
        try JSONEncoder().encode(env).write(to: SessionSyncQueue.currentFileURL(), options: .atomic)
        queue.unitTestSimulateRelaunch()
        signOut()

        XCTAssertEqual(localOnlyDelete(id, capturedOwner: nil), .deleted)
        XCTAssertEqual(queue.items.filter { $0.id == id }.compactMap(\.ownerUserID), [ownerC])
        XCTAssertEqual(try onDisk().handedOff?.filter { $0.key.hasSuffix(p) }.count, 3, "ledger not modified")
    }

    /// Conversion and appends are ONE write: on failure nothing reaches disk and
    /// the delete is refused; after recovery both are durable and survive a relaunch.
    /// An existing withdrawal is left exactly as it is.
    func testConversionAndAppends_OneWrite_Durable_ExistingUnshareUnchanged() async throws {
        let id = try newSharedSession().id
        let other = try newSharedSession().id
        signIn(ownerB)
        await acknowledgedPublish(id)                               // ledger: B
        signIn(ownerA)
        XCTAssertTrue(queue.enqueue(publishPayload(id, owner: ownerA)))   // A publish queued
        let existing = SessionSyncQueue.PostPublishPayload(
            id: other, sessionID: other, sessionTimestamp: nil, title: nil, durationSeconds: nil,
            activityType: nil, activityDetail: nil, instrumentLabel: nil, mood: nil, effort: nil,
            isPublic: false, ownerUserID: ownerA)
        XCTAssertTrue(queue.enqueue(existing))
        setBackendMode(.localSimulation)

        try failWritesLeavingAnOlderValidEnvelope()
        XCTAssertEqual(localOnlyDelete(id, capturedOwner: ownerA), .refused(.queueNotSaved))
        let failed = try onDisk().items.filter { $0.id == id }
        XCTAssertEqual(failed.map(\.op), [.publish], "nothing partial: no conversion, no append on disk")

        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil
        XCTAssertEqual(localOnlyDelete(id, capturedOwner: ownerA), .deleted)
        queue.unitTestSimulateRelaunch()
        let reloaded = queue.items.filter { $0.id == id }
        XCTAssertEqual(Set(reloaded.compactMap(\.ownerUserID)), [ownerA, ownerB])
        XCTAssertTrue(reloaded.allSatisfy { $0.op == .unshare && $0.choiceToken == nil })

        // An existing withdrawal for a ledger owner is not duplicated or changed.
        let before = queue.items.filter { $0.id == other }
        XCTAssertEqual(JournalDeleteBackendStep.runLocalOnly(postID: other, capturedOwner: ownerA,
                                                            sessionWasShared: true, deleteLocally: localDelete(other)), .deleted)
        XCTAssertEqual(queue.items.filter { $0.id == other }, before)
    }

    // MARK: - Refusal explanations

    /// Each reason maps to neutral copy that promises nothing about server state.
    func testRefusalMessages() {
        XCTAssertEqual(JournalDeleteRefusal.title, "Session not deleted")
        XCTAssertEqual(JournalDeleteRefusal.backendDeleteUnconfirmed.message,
                       "Études couldn’t confirm that this session’s shared post was removed, so the session has been kept. Try again.")
        XCTAssertEqual(JournalDeleteRefusal.identityChanged.message,
                       "Your Études account changed while this session was being deleted, so it has been kept. Try again.")
        for r in [JournalDeleteRefusal.queueNotSaved, .localSaveFailed, .missingIdentifier] {
            XCTAssertEqual(r.message, "Études couldn’t finish deleting this session, so it has been kept. Try again.")
        }
    }

    // MARK: - ContentView wiring (structure only; behaviour is proven above)

    func testContentView_RoutesEveryBranchThroughTheHelper() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let raw = try String(contentsOf: root.appendingPathComponent("MOTIVO/ContentView.swift"), encoding: .utf8)
        func body(_ signature: String) -> String? {
            guard let start = raw.range(of: signature) else { return nil }
            let tail = raw[start.lowerBound...]
            let end = tail.range(of: "\n    }\n")?.upperBound ?? tail.endIndex
            return tail[..<end].split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> Substring in
                    if let r = line.range(of: "//") { return line[..<r.lowerBound] }
                    return line
                }
                .joined(separator: "\n")
        }
        guard let entry = body("private func deleteSessions(at offsets: IndexSet)"),
              let code = body("private func deleteSessionsWithBackendIfNeeded(") else {
            return XCTFail("journal delete functions not found")
        }
        guard let capture = entry.range(of: "SessionSyncQueue.currentOwner()"),
              let task = entry.range(of: "Task {") else {
            return XCTFail("the owner is not captured at the action")
        }
        XCTAssertLessThan(capture.lowerBound, task.lowerBound, "captured before the deferred Task")
        let flat = code.replacingOccurrences(of: "\n", with: " ").split(whereSeparator: { $0 == " " }).joined(separator: " ")
        XCTAssertTrue(flat.contains("JournalDeleteBackendStep.run(postID: postID, capturedOwner: capturedOwner, sessionWasShared: sessionWasShared, deleteLocally: deleteLocally)"))
        XCTAssertTrue(flat.contains("JournalDeleteBackendStep.runLocalOnly(postID: postID, capturedOwner: capturedOwner, sessionWasShared: sessionWasShared, deleteLocally: deleteLocally)"))
        XCTAssertTrue(flat.contains("let sessionWasShared = session.isPublic"), "read before the delete")
        XCTAssertTrue(code.contains("JournalDeleteBackendStep.deleteSessionLocally(objectID: objectID)"))
        XCTAssertTrue(code.contains("journalDeleteRefusal = reason"), "a refusal is shown")
        XCTAssertFalse(code.contains("publish.deletePost("), "no direct backend delete")
        XCTAssertFalse(code.contains("viewContext.delete("), "no deletion in the editors' context")
        XCTAssertFalse(code.contains("deleteAttachmentFiles"), "no file deletion before the save")
    }
}
