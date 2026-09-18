//
//  P6I03SharingHandoffTests.swift
//  MOTIVOTests
//
//  P6-I-03 / C1 — a saved sharing choice survives a restart, and no older queued
//  intent for the same post can be dispatched before it.
//
//  Synthetic and disposable throughout. Sessions live in an IN-MEMORY Core Data
//  store built from the app's own model, never the app's store. Requests go only
//  to the held `QueueStubServer`. A "relaunch" is `unitTestSimulateRelaunch()`:
//  memory dropped, the queue reloaded from its file, recovery not yet run —
//  while the Core Data store, like a real one, keeps what was saved.
//
//  The dispatch barrier is enforced in hosted tests only when a test opts in;
//  this suite opts in for every test.
//

import XCTest
import CoreData
@testable import Etudes

@MainActor
final class P6I03SharingHandoffTests: XCTestCase {

    private var queue: SessionSyncQueue { SessionSyncQueue.shared }
    private let ownerA = QueueStubFixture.ownerUID
    private let ownerB = "00000000-0000-0000-0000-0000000c1b02"
    private var container: NSPersistentContainer!
    private var ctx: NSManagedObjectContext { container.viewContext }

    override func setUp() async throws {
        try await super.setUp()
        QueueStubFixture.connect()
        try LocalStackSupport.requireRealBackend(baseURL: QueueStubServer.baseURL.absoluteString)
        queue.clear()
        SessionSyncQueue.unitTestEnforceHandoffBarrier = true
        queue.unitTestSimulateRelaunch()                       // recovery .notRun
        container = try Self.makeStore()
    }

    override func tearDown() async throws {
        QueueStubFixture.attachTimeline(to: self)
        QueueStubServer.releaseAll()
        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil
        SharingHandoff.unitTestFailNextClear = false
        SharingHandoff.unitTestFailNextStage = false
        SharingHandoffRecovery.unitTestFailNextFetch = false
        if !queue.reconcileState.isOK {
            try? FileManager.default.removeItem(at: SessionSyncQueue.currentFileURL())
            _ = queue.attemptStoreRecovery()
        }
        queue.stopForFactoryReset()
        queue.resumeAfterFactoryReset()
        queue.setHandoffRecovery(.notRun, blockedPosts: [])
        SessionSyncQueue.unitTestEnforceHandoffBarrier = false
        QueueStubFixture.disconnect()
        container = nil
        try await super.tearDown()
    }

    // MARK: - Fixture

    private static func makeStore() throws -> NSPersistentContainer {
        let model = PersistenceController.shared.container.managedObjectModel
        let c = NSPersistentContainer(name: "C1Handoff", managedObjectModel: model)
        let d = NSPersistentStoreDescription()
        d.type = NSInMemoryStoreType
        c.persistentStoreDescriptions = [d]
        var failure: Error?
        c.loadPersistentStores { _, e in failure = e }
        if let failure { throw failure }
        // As the app configures its own view context.
        c.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        c.viewContext.automaticallyMergesChangesFromParent = true
        return c
    }

    private func newSession(shared: Bool) throws -> (object: NSManagedObject, id: UUID) {
        let s = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        let id = UUID()
        s.setValue(id, forKey: "id")
        s.setValue(Date(), forKey: "timestamp")
        s.setValue("c1", forKey: "title")
        s.setValue(shared, forKey: "isPublic")
        try ctx.save()
        return (s, id)
    }

    private func basePayload(_ id: UUID, shared: Bool, omissions: [UUID]? = nil) -> SessionSyncQueue.PostPublishPayload {
        SessionSyncQueue.PostPublishPayload(id: id, sessionID: id, sessionTimestamp: nil, title: "c1",
                                            durationSeconds: 60, activityType: nil, activityDetail: nil,
                                            instrumentLabel: nil, mood: nil, effort: nil, isPublic: shared,
                                            authorisedOmissions: omissions)
    }

    /// Exactly what an editor's save step does: prepare, stage, save.
    @discardableResult
    private func saveChoice(_ s: NSManagedObject, shared: Bool, omissions: [UUID]? = nil) throws -> SessionSyncQueue.PostPublishPayload {
        let id = s.value(forKey: "id") as! UUID
        s.setValue(shared, forKey: "isPublic")
        let choice = PublishService.shared.prepareSharingChoice(payload: basePayload(id, shared: shared, omissions: omissions),
                                                                session: s, shouldPublish: shared)
        try SharingHandoff.stage(choice, on: s)
        try ctx.save()
        return choice
    }

    /// Exactly what an editor does after its save.
    @discardableResult
    private func handOff(_ choice: SessionSyncQueue.PostPublishPayload, _ s: NSManagedObject) -> SharingChoiceSaveResult {
        let result = PublishService.shared.publishPrepared(choice, objectID: s.objectID, shouldPublish: choice.isPublic)
        queue.unblockHandoffPost(choice.id)
        if result != .notSaved, let token = choice.choiceToken {
            SharingHandoff.clearIfMatches(objectID: s.objectID, token: token, container: container)
        }
        return result
    }

    private func recover() -> SessionSyncQueue.HandoffRecoveryState {
        SharingHandoffRecovery.run(reason: "test", container: container, queue: queue)
    }

    /// The marker as the STORE holds it (a private context, not the editor's).
    private func storedMarker(_ oid: NSManagedObjectID) -> Data? {
        let bg = container.newBackgroundContext()
        var data: Data?
        bg.performAndWait { data = (try? bg.existingObject(with: oid))?.value(forKey: SharingHandoff.attribute) as? Data }
        return data
    }

    private func storedValue(_ oid: NSManagedObjectID, _ key: String) -> Any? {
        let bg = container.newBackgroundContext()
        var value: Any?
        bg.performAndWait { value = (try? bg.existingObject(with: oid))?.value(forKey: key) }
        return value
    }

    private func onDisk() throws -> SessionSyncQueueEnvelope {
        try JSONDecoder().decode(SessionSyncQueueEnvelope.self, from: Data(contentsOf: SessionSyncQueue.currentFileURL()))
    }

    /// The NEXT queue write fails, leaving the older valid envelope on disk.
    private func failQueueWrites() throws {
        let file = SessionSyncQueue.currentFileURL()
        let older = try Data(contentsOf: file)
        SessionSyncQueueStore.unitTestCorruptAfterWrite = { try? older.write(to: file, options: .atomic) }
    }

    /// A kill: the queue restarts from its file. The failed-write seam is removed
    /// first, as a new process would not carry it.
    private func relaunch() {
        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil
        queue.unitTestSimulateRelaunch()
    }

    private func olderQueued(_ id: UUID, shared: Bool, owner: String? = nil) {
        XCTAssertEqual(queue.enqueueReportingSave(basePayload(id, shared: shared).withOwner(owner ?? ownerA)), .saved,
                       "fixture: an older intent persisted")
    }

    private func count(_ op: String, _ id: UUID) -> Int { QueueStubServer.count(QueueStubServer.key(op, id)) }

    /// Every request the server received that names this post, of any kind.
    private func requests(for id: UUID) -> Int {
        QueueStubServer.log.filter { $0.contains(id.uuidString.uppercased()) }.count
    }

    /// Waits for in-flight flush Tasks, then asserts nothing further arrived.
    private func settle() async { _ = await QueueStubFixture.poll(timeout: 0.4) { false } }

    // MARK: - 1, 2. Kill after a failed write: the saved choice, not the older one

    func testKillAfterFailedStopSharing_RelaunchSendsTheWithdrawal_NotTheOlderShare() async throws {
        let (s, id) = try newSession(shared: true)
        olderQueued(id, shared: true)                                  // the older, persisted share

        let choice = try saveChoice(s, shared: false)                  // the member stops sharing
        try failQueueWrites()
        XCTAssertEqual(handOff(choice, s), .notSaved)
        XCTAssertNotNil(storedMarker(s.objectID), "the marker committed with the choice")

        relaunch()
        XCTAssertEqual(queue.items.first { $0.id == id }?.op, .publish, "fixture: the file holds the OLDER share")

        await queue.flushNow()
        await settle()
        XCTAssertEqual(count("POST", id), 0, "BARRIER: the older share cannot go before recovery")

        XCTAssertEqual(recover(), .complete)
        let item = try XCTUnwrap(queue.items.first { $0.id == id })
        XCTAssertEqual(item.op, .unshare, "the saved choice replaced the older share")
        XCTAssertEqual(item.choiceToken, choice.choiceToken, "SAME identity, not a new choice")
        XCTAssertEqual(try onDisk().items.first { $0.id == id }?.op, .unshare, "and durably")
        XCTAssertNil(storedMarker(s.objectID), "handed off, so cleared")

        await queue.flushNow()
        XCTAssertGreaterThan(count("DEMOTE", id), 0, "the withdrawal is sent")
        XCTAssertEqual(count("POST", id), 0, "the older share never was")
    }

    func testKillAfterFailedShare_RelaunchSendsTheShare_NotTheOlderWithdrawal() async throws {
        let (s, id) = try newSession(shared: false)
        olderQueued(id, shared: false)

        let choice = try saveChoice(s, shared: true)
        try failQueueWrites()
        XCTAssertEqual(handOff(choice, s), .notSaved)

        relaunch()
        await queue.flushNow()
        await settle()
        XCTAssertEqual(count("DEMOTE", id), 0, "BARRIER")

        XCTAssertEqual(recover(), .complete)
        XCTAssertEqual(queue.items.first { $0.id == id }?.op, .publish)
        await queue.flushNow()
        XCTAssertEqual(count("POST", id), 1)
        XCTAssertEqual(count("DEMOTE", id), 0)
    }

    // MARK: - 3. Owner is captured, never re-read or adopted

    func testReplayUnderAnotherAccount_IsHeldForTheCapturedOwner() async throws {
        let (s, id) = try newSession(shared: true)
        olderQueued(UUID(), shared: true)                              // a valid envelope to fail over
        let choice = try saveChoice(s, shared: true)
        XCTAssertEqual(choice.ownerUserID, ownerA)
        try failQueueWrites()
        XCTAssertEqual(handOff(choice, s), .notSaved)

        relaunch()
        // B is now signed in.
        UserDefaults.standard.set(ownerB, forKey: "supabaseUserID_v1")
        NetworkManager.shared.setBearerToken(QueueStubFixture.token(sub: ownerB, jti: "c1-b"))

        XCTAssertEqual(recover(), .complete)
        let item = try XCTUnwrap(queue.items.first { $0.id == id })
        XCTAssertEqual(item.ownerUserID, ownerA, "replayed as A's work, never re-read as B's")
        await queue.flushNow()
        await settle()
        XCTAssertEqual(count("POST", id), 0, "held for A; nothing sent as B")
    }

    func testReplayOfAnOwnerlessChoice_IsQuarantined_NeverAdopted() async throws {
        let (s, id) = try newSession(shared: true)
        olderQueued(UUID(), shared: true)
        UserDefaults.standard.removeObject(forKey: "supabaseUserID_v1")   // nobody signed in
        let choice = try saveChoice(s, shared: true)
        XCTAssertNil(choice.ownerUserID)
        try failQueueWrites()
        XCTAssertEqual(handOff(choice, s), .notSaved)

        relaunch()
        UserDefaults.standard.set(ownerA, forKey: "supabaseUserID_v1")   // A signs in afterwards
        XCTAssertEqual(recover(), .complete)
        XCTAssertTrue(queue.quarantined.contains { $0.id == id && $0.ownerUserID == nil }, "quarantined, owner still unknown")
        XCTAssertFalse(queue.items.contains { $0.id == id }, "never adopted by A")
        XCTAssertNil(storedMarker(s.objectID), "durably held, so the marker is cleared")
        await queue.flushNow()
        await settle()
        XCTAssertEqual(count("POST", id), 0)
    }

    // MARK: - 4. Token identity: compare-and-clear, and no extra request

    func testAnOlderClearDoesNotEraseANewerChoice() throws {
        let (s, _) = try newSession(shared: true)
        let first = try saveChoice(s, shared: false)
        let second = try saveChoice(s, shared: true)
        XCTAssertFalse(SharingHandoff.clearIfMatches(objectID: s.objectID, token: first.choiceToken!, container: container))
        guard case .record(let r)? = storedMarker(s.objectID).map(SharingHandoff.decode) else { return XCTFail("marker gone") }
        XCTAssertEqual(r.token, second.choiceToken, "the newer choice's marker survives an older clear")
    }

    func testAcknowledgedThenClearFails_RelaunchSendsNothingMore() async throws {
        XCTAssertEqual(recover(), .complete)
        let (s, id) = try newSession(shared: false)
        let choice = try saveChoice(s, shared: true)
        SharingHandoff.unitTestFailNextClear = true
        XCTAssertEqual(handOff(choice, s), .saved)
        let sent = await QueueStubFixture.poll(timeout: 5) { self.count("POST", id) == 1 && !self.queue.items.contains { $0.id == id } }
        XCTAssertTrue(sent, "sent and acknowledged")
        XCTAssertNotNil(storedMarker(s.objectID), "fixture: the clear failed, so the marker is still there")
        let requestsBefore = requests(for: id)

        relaunch()
        XCTAssertEqual(recover(), .complete)
        XCTAssertNil(storedMarker(s.objectID), "the ledger says it was taken: cleared, not replayed")
        XCTAssertFalse(queue.items.contains { $0.id == id }, "nothing re-queued")
        await queue.flushNow()
        await settle()
        XCTAssertEqual(requests(for: id), requestsBefore, "ZERO additional requests for this post, measured at the server")
        XCTAssertEqual(count("POST", id), 1)
    }

    // MARK: - 5. The barrier, and what blocks

    func testEveryDispatchPathIsRefusedUntilRecoveryCompletes() async throws {
        let id = UUID()
        olderQueued(id, shared: true)
        XCTAssertEqual(queue.handoffRecovery, .notRun)

        await queue.flushNow()                                                     // foreground / Try Again / debug
        let (s, other) = try newSession(shared: true)
        _ = PublishService.shared.publish(payload: basePayload(other, shared: true), objectID: s.objectID, shouldPublish: true)   // immediate flush
        await settle()
        XCTAssertEqual(count("POST", id), 0)
        XCTAssertEqual(count("POST", other), 0)

        XCTAssertEqual(recover(), .complete)
        await queue.flushNow()
        XCTAssertEqual(count("POST", id), 1)
        XCTAssertEqual(count("POST", other), 1)
    }

    func testUnreadableMarkers_BlockGlobally() async throws {
        let id = UUID()
        olderQueued(id, shared: true)
        SharingHandoffRecovery.unitTestFailNextFetch = true
        if case .blocked = recover() {} else { XCTFail("a failed read must block") }
        await queue.flushNow()
        await settle()
        XCTAssertEqual(count("POST", id), 0, "nothing may go first when the markers cannot be read")
    }

    func testUndecodableMarker_BlocksOnlyItsPost() async throws {
        let (x, xid) = try newSession(shared: true)
        x.setValue(Data("not a record".utf8), forKey: SharingHandoff.attribute)
        try ctx.save()
        olderQueued(xid, shared: true)
        let yid = UUID()
        olderQueued(yid, shared: true)

        XCTAssertEqual(recover(), .complete)
        XCTAssertEqual(queue.handoffBlockedPosts, [xid])
        await queue.flushNow()
        XCTAssertEqual(count("POST", yid), 1, "other posts proceed")
        XCTAssertEqual(count("POST", xid), 0, "the blocked post's older work is withheld")
        XCTAssertNotNil(storedMarker(x.objectID), "kept, not cleared")
    }

    func testMarkerWhosePayloadNamesAnotherSession_IsBlocked() throws {
        let (x, xid) = try newSession(shared: true)
        var wrong = SessionSyncQueue.PostPublishPayload(id: xid, sessionID: UUID(), sessionTimestamp: nil, title: "c1",
                                                    durationSeconds: 60, activityType: nil, activityDetail: nil,
                                                    instrumentLabel: nil, mood: nil, effort: nil, isPublic: true,
                                                    ownerUserID: ownerA)
        wrong.choiceToken = UUID()
        let record = SharingHandoffRecord(v: 1, stream: try XCTUnwrap(queue.verifiedInstallStream), token: wrong.choiceToken!, payload: wrong)
        x.setValue(SharingHandoff.encode(record), forKey: SharingHandoff.attribute)
        try ctx.save()
        XCTAssertEqual(recover(), .complete)
        XCTAssertTrue(queue.handoffBlockedPosts.contains(xid))
        XCTAssertFalse(queue.items.contains { $0.id == xid }, "not replayed")
    }

    func testStagingRefusesAPayloadForAnotherSession() throws {
        let (x, _) = try newSession(shared: true)
        var foreign = basePayload(UUID(), shared: true).withOwner(ownerA)
        foreign.choiceToken = UUID()
        XCTAssertThrowsError(try SharingHandoff.stage(foreign, on: x))
    }

    // MARK: - 6. Provenance: foreign markers held; a corrupt store never rotates

    func testForeignStreamMarker_IsHeld_NotReplayedNotCleared_ThenAFreshChoiceUnblocks() async throws {
        let (s, id) = try newSession(shared: true)
        olderQueued(id, shared: true)
        var restored = basePayload(id, shared: false).withOwner(ownerA)
        restored.choiceToken = UUID()
        let record = SharingHandoffRecord(v: 1, stream: UUID(), token: restored.choiceToken!, payload: restored)
        s.setValue(SharingHandoff.encode(record), forKey: SharingHandoff.attribute)
        try ctx.save()

        XCTAssertEqual(recover(), .complete)
        XCTAssertTrue(queue.handoffBlockedPosts.contains(id))
        XCTAssertEqual(queue.items.first { $0.id == id }?.op, .publish, "the foreign choice was not replayed")
        XCTAssertNotNil(storedMarker(s.objectID), "nor cleared")
        await queue.flushNow()
        await settle()
        XCTAssertEqual(count("POST", id), 0, "and the post is withheld")

        // A fresh choice from THIS install on that session.
        let fresh = try saveChoice(s, shared: true)
        XCTAssertEqual(handOff(fresh, s), .saved)
        XCTAssertFalse(queue.handoffBlockedPosts.contains(id), "unblocked in the same turn")
        let sent = await QueueStubFixture.poll(timeout: 5) { self.count("POST", id) == 1 }
        XCTAssertTrue(sent)
    }

    func testCorruptStore_NeitherRotatesTheStreamNorDiscardsTheMarker() async throws {
        let (s, id) = try newSession(shared: true)
        olderQueued(UUID(), shared: true)
        let stream = try XCTUnwrap(queue.verifiedInstallStream)
        let choice = try saveChoice(s, shared: false)
        try failQueueWrites()
        XCTAssertEqual(handOff(choice, s), .notSaved)
        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil

        let file = SessionSyncQueue.currentFileURL()
        let good = try Data(contentsOf: file)
        try Data("{ corrupt".utf8).write(to: file)
        relaunch()
        XCTAssertFalse(queue.reconcileState.isOK, "fixture: the store halts")
        if case .blocked = recover() {} else { XCTFail("a halted store blocks") }
        XCTAssertNil(queue.verifiedInstallStream, "no stream was made up for a store that could not be read")
        XCTAssertNotNil(storedMarker(s.objectID), "the marker is kept")

        try good.write(to: file)
        XCTAssertEqual(queue.attemptStoreRecovery(), .ok)
        XCTAssertEqual(queue.verifiedInstallStream, stream, "the SAME stream comes back")
        XCTAssertEqual(recover(), .complete)
        XCTAssertEqual(queue.items.first { $0.id == id }?.op, .unshare, "and the choice is replayed")
        XCTAssertNil(storedMarker(s.objectID))
    }

    // MARK: - The stream must be durable before any choice is saved

    /// The member's save attempt, through the SAME transaction the editors use.
    private func attemptSave(_ s: NSManagedObject, shared: Bool) throws -> AttachmentCommitTransaction.Outcome {
        let ticket = try AttemptScopedUndo.open(in: ctx)
        s.setValue(shared, forKey: "isPublic")
        return AttachmentCommitTransaction.run(.init(
            commit: { .empty },
            save: {
                let id = s.value(forKey: "id") as! UUID
                let choice = PublishService.shared.prepareSharingChoice(payload: self.basePayload(id, shared: shared),
                                                                        session: s, shouldPublish: shared)
                try SharingHandoff.stage(choice, on: s)
                try self.ctx.save()
            },
            finalise: { _ in AttemptScopedUndo.release(ticket) },
            discardAttempt: { AttemptScopedUndo.undoAndRelease(ticket) }
        ))
    }

    /// Codex interim: the FIRST choice on a store written before C1, when the
    /// write that would make its stream durable fails, then a kill. The save
    /// must FAIL rather than commit a marker whose stream the store never kept —
    /// which a restart would misread as another install's and hold for ever.
    func testFirstChoiceOnAPreC1Store_WhenTheStreamCannotBeKept_TheSaveFails_AndAfterRestartItWorks() async throws {
        let (s, id) = try newSession(shared: true)
        olderQueued(UUID(), shared: true)

        // A pre-C1 envelope: no stream, no ledger.
        let file = SessionSyncQueue.currentFileURL()
        var preC1 = try onDisk()
        preC1.installStream = nil
        preC1.handedOff = nil
        let preC1Bytes = try JSONEncoder().encode(preC1)
        try preC1Bytes.write(to: file)

        // Launch: the whole-store reconcile write succeeds; the NEXT write — the
        // one that would keep a new stream — does not.
        var writes = 0
        SessionSyncQueueStore.unitTestCorruptAfterWrite = {
            writes += 1
            if writes == 2 { try? preC1Bytes.write(to: file, options: .atomic) }
        }
        queue.unitTestSimulateRelaunch()
        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil
        XCTAssertEqual(writes, 2, "fixture: reconcile, then the stream write")
        XCTAssertNil(queue.verifiedInstallStream, "fixture: the stream is not durable")

        guard case .saveFailed = try attemptSave(s, shared: false) else { return XCTFail("the save must fail") }
        XCTAssertNil(storedMarker(s.objectID), "no marker with an unkept stream")
        XCTAssertEqual(storedValue(s.objectID, "isPublic") as? Bool, true, "and the choice was not saved")

        // Kill and relaunch: the store now keeps a stream; the member saves again.
        relaunch()
        let stream = try XCTUnwrap(queue.verifiedInstallStream)
        XCTAssertEqual(recover(), .complete)
        let choice = try saveChoice(s, shared: false)
        guard case .record(let r)? = storedMarker(s.objectID).map(SharingHandoff.decode) else { return XCTFail("no marker") }
        XCTAssertEqual(r.stream, stream, "marked with the durable stream")
        try failQueueWrites()
        XCTAssertEqual(handOff(choice, s), .notSaved)

        relaunch()
        XCTAssertEqual(recover(), .complete)
        XCTAssertFalse(queue.handoffBlockedPosts.contains(id), "recognised as THIS install's choice, not held as foreign")
        XCTAssertEqual(queue.items.first { $0.id == id }?.choiceToken, choice.choiceToken, "and replayed")
    }

    /// A store halted at launch has a real stream on disk. Nothing may be saved
    /// against a substitute; recovery brings the real one back.
    func testLaunchHaltedStore_NoSubstituteStream_TheSaveFails_UntilRecovery() throws {
        let (s, _) = try newSession(shared: true)
        olderQueued(UUID(), shared: true)
        let stream = try XCTUnwrap(queue.verifiedInstallStream)
        let file = SessionSyncQueue.currentFileURL()
        let good = try Data(contentsOf: file)
        try Data("{ corrupt".utf8).write(to: file)
        relaunch()
        XCTAssertFalse(queue.reconcileState.isOK, "fixture: halted at launch")

        guard case .saveFailed = try attemptSave(s, shared: false) else { return XCTFail("the save must fail") }
        XCTAssertNil(queue.verifiedInstallStream, "no substitute stream was minted")
        XCTAssertNil(storedMarker(s.objectID))

        try good.write(to: file)
        XCTAssertEqual(queue.attemptStoreRecovery(), .ok)
        XCTAssertEqual(queue.verifiedInstallStream, stream, "the real stream comes back")
        XCTAssertEqual(recover(), .complete)
        _ = try saveChoice(s, shared: false)
        guard case .record(let r)? = storedMarker(s.objectID).map(SharingHandoff.decode) else { return XCTFail("no marker") }
        XCTAssertEqual(r.stream, stream)
    }

    // MARK: - Acceptance checks (Codex §9)

    /// §9.2 — the marker holds the FINAL enriched payload: notes as the Session
    /// holds them, notes privacy, consent, captured owner, and the token.
    func testMarkerHoldsTheExactFinalPayload() throws {
        let (s, id) = try newSession(shared: false)
        s.setValue("  practised the scales  ", forKey: "notes")
        s.setValue(true, forKey: "areNotesPrivate")
        let omitted = [UUID()]
        let choice = try saveChoice(s, shared: true, omissions: omitted)
        guard case .record(let r)? = storedMarker(s.objectID).map(SharingHandoff.decode) else { return XCTFail("no marker") }
        XCTAssertEqual(r.payload, choice)
        XCTAssertEqual(r.payload.notes, "practised the scales")
        XCTAssertTrue(r.payload.areNotesPrivate)
        XCTAssertEqual(r.payload.authorisedOmissions, omitted)
        XCTAssertEqual(r.payload.ownerUserID, ownerA)
        XCTAssertEqual(r.payload.id, id)
        XCTAssertEqual(r.token, choice.choiceToken)
        XCTAssertEqual(r.stream, queue.verifiedInstallStream)
    }

    /// §9.2 negative — a marker that cannot be written FAILS THE SAVE through the
    /// same transaction the editors use. The choice is never saved without it.
    func testStageFailure_FailsTheSave_AndLeavesNothing() throws {
        let (s, _) = try newSession(shared: true)
        let ticket = try AttemptScopedUndo.open(in: ctx)
        s.setValue(false, forKey: "isPublic")
        SharingHandoff.unitTestFailNextStage = true
        var finalised = false, discarded = false
        let outcome = AttachmentCommitTransaction.run(.init(
            commit: { .empty },
            save: {
                let id = s.value(forKey: "id") as! UUID
                let choice = PublishService.shared.prepareSharingChoice(payload: self.basePayload(id, shared: false),
                                                                        session: s, shouldPublish: false)
                try SharingHandoff.stage(choice, on: s)
                try self.ctx.save()
            },
            finalise: { _ in finalised = true },
            discardAttempt: { discarded = true; AttemptScopedUndo.undoAndRelease(ticket) }
        ))
        guard case .saveFailed = outcome else { return XCTFail("expected a failed save, got \(outcome)") }
        XCTAssertFalse(finalised)
        XCTAssertTrue(discarded)
        XCTAssertEqual(storedValue(s.objectID, "isPublic") as? Bool, true, "the choice was not saved")
        XCTAssertNil(storedMarker(s.objectID), "and no marker")
        XCTAssertEqual(s.value(forKey: "isPublic") as? Bool, true, "the attempt was undone in memory too")
    }

    /// §9.3 — compare-and-clear leaves unrelated pending edits alone.
    func testClear_DoesNotTouchUnrelatedPendingEdits() async throws {
        let (s, _) = try newSession(shared: true)
        let choice = try saveChoice(s, shared: true)
        s.setValue("edited, not yet saved", forKey: "title")

        XCTAssertTrue(SharingHandoff.clearIfMatches(objectID: s.objectID, token: choice.choiceToken!, container: container))
        XCTAssertTrue(ctx.hasChanges, "the pending edit is still pending")
        XCTAssertEqual(s.value(forKey: "title") as? String, "edited, not yet saved")
        XCTAssertNil(storedMarker(s.objectID))

        try ctx.save()
        XCTAssertEqual(storedValue(s.objectID, "title") as? String, "edited, not yet saved")
        XCTAssertNil(storedMarker(s.objectID), "a later save of the edit does not bring the marker back")
    }

    /// §9.4 — a failed write never advances the ledger; only a verified persist does.
    func testLedgerAdvancesOnlyOnAVerifiedPersist() throws {
        let (s, id) = try newSession(shared: true)
        olderQueued(UUID(), shared: true)
        let choice = try saveChoice(s, shared: false)
        try failQueueWrites()
        XCTAssertEqual(handOff(choice, s), .notSaved)
        XCTAssertNil(queue.verifiedHandoffToken(owner: ownerA, postID: id), "a failed write did not advance it")
        XCTAssertNil(try onDisk().handedOff?[SessionSyncQueue.handoffLedgerKey(owner: ownerA, postID: id)])

        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil
        XCTAssertTrue(queue.recoverIfNeeded(reason: "test"))
        XCTAssertEqual(queue.verifiedHandoffToken(owner: ownerA, postID: id), choice.choiceToken, "the verified recovery did")
        XCTAssertEqual(try onDisk().handedOff?[SessionSyncQueue.handoffLedgerKey(owner: ownerA, postID: id)], choice.choiceToken)
    }

    /// §9.1 — a real V9 store with a session migrates to V10: data kept, marker nil.
    func testV9StoreMigratesToV10() throws {
        let momd = try XCTUnwrap(Bundle.main.url(forResource: "MOTIVO", withExtension: "momd"))
        let v9 = try XCTUnwrap(NSManagedObjectModel(contentsOf: momd.appendingPathComponent("MOTIVO V9.mom")))
        XCTAssertNil(v9.entitiesByName["Session"]?.attributesByName[SharingHandoff.attribute], "fixture: V9 has no marker")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("c1-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("v9.sqlite")

        let id = UUID()
        do {
            let psc = NSPersistentStoreCoordinator(managedObjectModel: v9)
            let store = try psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
            let c = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            c.persistentStoreCoordinator = psc
            let s = NSManagedObject(entity: v9.entitiesByName["Session"]!, insertInto: c)
            s.setValue(id, forKey: "id")
            s.setValue(Date(timeIntervalSince1970: 1_700_000_000), forKey: "timestamp")
            s.setValue("from V9", forKey: "title")
            s.setValue("kept notes", forKey: "notes")
            s.setValue(false, forKey: "isPublic")
            try c.save()
            try psc.remove(store)
        }

        let current = PersistenceController.shared.container.managedObjectModel
        XCTAssertNotNil(current.entitiesByName["Session"]?.attributesByName[SharingHandoff.attribute], "V10 is current")
        let psc = NSPersistentStoreCoordinator(managedObjectModel: current)
        try psc.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url,
                                   options: [NSMigratePersistentStoresAutomaticallyOption: true,
                                             NSInferMappingModelAutomaticallyOption: true])
        let c = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        c.persistentStoreCoordinator = psc
        let rows = try c.fetch(NSFetchRequest<NSManagedObject>(entityName: "Session"))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.value(forKey: "id") as? UUID, id)
        XCTAssertEqual(rows.first?.value(forKey: "title") as? String, "from V9")
        XCTAssertEqual(rows.first?.value(forKey: "notes") as? String, "kept notes")
        XCTAssertEqual(rows.first?.value(forKey: "isPublic") as? Bool, false)
        XCTAssertNil(rows.first?.value(forKey: SharingHandoff.attribute), "the new attribute starts empty")
    }
}
