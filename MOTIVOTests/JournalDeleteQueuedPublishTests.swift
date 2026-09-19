//
//  JournalDeleteQueuedPublishTests.swift
//  MOTIVOTests
//
//  Journal delete in Connected must not leave a queued, not-yet-dispatched
//  publish that re-creates the deleted entry's post on a later flush.
//
//  REPRODUCED FIRST at 369bd53 (before the fix): after the journal delete, the
//  next flush sent POST <id> 201. The mechanism: the delete never touched
//  SessionSyncQueue, and a flush with no local session uploads the
//  self-contained payload with an empty attachment list.
//
//  THE FIX UNDER TEST is `JournalDeleteBackendStep.run`, which ContentView calls:
//  the backend delete, then `SessionSyncQueue.supersedeQueuedPublishForJournalDelete`,
//  and only then may the caller delete locally. These cases call that same
//  production helper; only the trivial Core Data deletion is done here.
//
//  SYNTHETIC ONLY. QueueStubServer answers loopback 127.0.0.1:9 alone. Owners
//  are synthetic UUIDs with unsigned synthetic tokens; Sessions are disposable
//  and removed in tearDown. No live backend, account or personal data.
//
//  NOT COVERED, BY DESIGN: a publish already dispatched and in flight when the
//  delete runs (open sharing blocker 1).
//

import XCTest
import CoreData
@testable import Etudes

@MainActor
final class JournalDeleteQueuedPublishTests: XCTestCase {
    private var queue: SessionSyncQueue { SessionSyncQueue.shared }
    private var ctx: NSManagedObjectContext { PersistenceController.shared.container.viewContext }
    private let ownerA = QueueStubFixture.ownerUID
    private let ownerB = "00000000-0000-0000-0000-0000000c8702"
    private var createdSessionIDs: [UUID] = []

    override func setUp() async throws {
        try await super.setUp()
        QueueStubFixture.connect()
        try LocalStackSupport.requireRealBackend(baseURL: QueueStubServer.baseURL.absoluteString)
        queue.clear()
    }

    override func tearDown() async throws {
        QueueStubFixture.attachTimeline(to: self)
        QueueStubServer.releaseAll()
        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil
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

    private func fetchSession(_ id: UUID) -> NSManagedObject? {
        let r = NSFetchRequest<NSManagedObject>(entityName: "Session")
        r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        r.fetchLimit = 1
        return (try? ctx.fetch(r))?.first
    }

    private func newSharedSession() throws -> UUID {
        let id = UUID()
        let s = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        s.setValue(id, forKey: "id")
        s.setValue(Date(), forKey: "timestamp")
        s.setValue("synthetic journal-delete fixture", forKey: "title")
        s.setValue(true, forKey: "isPublic")
        try ctx.save()
        createdSessionIDs.append(id)
        return id
    }

    /// Queued the way PublishService queues it: payload id == sessionID == session.id.
    private func publishPayload(_ id: UUID, owner: String) -> SessionSyncQueue.PostPublishPayload {
        SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: id, sessionTimestamp: nil, title: "synthetic journal-delete fixture",
            durationSeconds: 60, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil, isPublic: true
        ).withOwner(owner)
    }

    /// A shared session whose publish is QUEUED and NOT dispatched: its first
    /// attempt failed with a 500, so it waits for the next flush.
    private func sharedSessionWithQueuedPublish() async throws -> UUID {
        let id = try newSharedSession()
        XCTAssertTrue(queue.enqueue(publishPayload(id, owner: ownerA)), "setup: the publish is durable")
        QueueStubServer.respond(key("POST", id), with: 500)
        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(key("POST", id)), 1, "setup: the first attempt was sent")
        XCTAssertFalse(QueueStubServer.hasRow(id), "setup: no row after the failed attempt")
        XCTAssertEqual(ownItem(id)?.op, .publish, "setup: the publish is still queued")
        return id
    }

    private func ownItem(_ id: UUID, owner: String? = nil) -> SessionSyncQueue.PostPublishPayload? {
        let o = owner ?? ownerA
        return queue.items.first { $0.id == id && $0.ownerUserID == o }
    }

    /// ContentView's Connected journal delete: the production backend step, then
    /// local deletion only if it allows. The owner is captured by the caller.
    private func journalDelete(_ id: UUID, capturedOwner: String?) async -> Bool {
        guard await JournalDeleteBackendStep.run(postID: id, capturedOwner: capturedOwner) else { return false }
        if let session = fetchSession(id) { ctx.delete(session) }
        do { try ctx.save() } catch { return false }
        return true
    }

    /// Makes writes fail while leaving a VALID, OLDER envelope on disk (the
    /// P6I02OwnershipBehaviourTests seam). Stays in force until the hook is cleared.
    private func failWritesLeavingAnOlderValidEnvelope() throws {
        let file = SessionSyncQueue.currentFileURL()
        let older = try Data(contentsOf: file)
        SessionSyncQueueStore.unitTestCorruptAfterWrite = { try? older.write(to: file, options: .atomic) }
    }

    private func onDiskOp(_ id: UUID, owner: String) throws -> SessionSyncQueue.PostOp? {
        let env = try JSONDecoder().decode(SessionSyncQueueEnvelope.self,
                                           from: Data(contentsOf: SessionSyncQueue.currentFileURL()))
        return env.items.first { $0.id == id && $0.ownerUserID == owner }?.op
    }

    // MARK: - The reproduction, now the requirement

    func testJournalDelete_ThenLaterFlush_DoesNotRecreateThePost() async throws {
        let id = try await sharedSessionWithQueuedPublish()

        QueueStubServer.mark("member deletes the journal entry")
        let deleted = await journalDelete(id, capturedOwner: SessionSyncQueue.currentOwner())
        XCTAssertTrue(deleted, "the journal delete completed")
        XCTAssertNil(fetchSession(id), "the local session is gone")
        XCTAssertFalse(QueueStubServer.hasRow(id))
        XCTAssertEqual(ownItem(id)?.op, .unshare, "the queued publish was superseded")

        QueueStubServer.mark("a later flush (next foreground)")
        let afterDelete = QueueStubServer.position
        await queue.flushNow()

        XCTAssertFalse(QueueStubServer.arrived(key("POST", id), since: afterDelete),
                       "a post the member deleted must not be published afterwards")
        XCTAssertFalse(QueueStubServer.hasRow(id),
                       "the deleted entry's post must not exist on the server after a later flush")
        XCTAssertNil(ownItem(id), "the withdrawal was acknowledged")
    }

    // MARK: - Unchanged paths

    /// Nothing queued: the same two requests as before the fix, and no queue write.
    func testNoQueuedWork_RequestsAndQueueUnchanged() async throws {
        let id = try newSharedSession()
        QueueStubServer.seedRow(id, objectPaths: [])
        let before = queue.items
        let start = QueueStubServer.arrivals.count

        let deleted = await journalDelete(id, capturedOwner: SessionSyncQueue.currentOwner())

        XCTAssertTrue(deleted)
        XCTAssertEqual(Array(QueueStubServer.arrivals.dropFirst(start)),
                       [key("GET", id), key("DELETE", id)], "only the existing backend delete")
        XCTAssertEqual(queue.items, before, "no queue write")
        XCTAssertTrue(queue.isFullySaved)
    }

    /// Backend delete fails: nothing new happens. No queue write; the caller keeps
    /// the entry.
    func testBackendDeleteFailure_NoQueueWriteAndLocalKept() async throws {
        let id = try await sharedSessionWithQueuedPublish()
        let before = queue.items
        QueueStubServer.respond(key("GET", id), with: 500)

        let deleted = await journalDelete(id, capturedOwner: SessionSyncQueue.currentOwner())

        XCTAssertFalse(deleted, "fail-closed")
        XCTAssertNotNil(fetchSession(id), "the local entry is kept")
        XCTAssertEqual(queue.items, before, "the queued publish is untouched")
        XCTAssertEqual(QueueStubServer.count(key("DELETE", id)), 0)
    }

    // MARK: - Ownership

    /// The account switches while the backend delete is awaited: refuse local
    /// deletion and write nothing.
    func testOwnerSwitchDuringBackendDelete_RefusesAndWritesNothing() async throws {
        let id = try await sharedSessionWithQueuedPublish()
        let before = queue.items
        let captured = SessionSyncQueue.currentOwner()
        QueueStubServer.hold(key("DELETE", id))

        let run = Task { await self.journalDelete(id, capturedOwner: captured) }
        let held = await QueueStubFixture.poll(timeout: 5) { QueueStubServer.count(self.key("DELETE", id)) == 1 }
        XCTAssertTrue(held, "setup: the backend DELETE is in flight")
        signIn(ownerB)
        QueueStubServer.release(key("DELETE", id))
        let deleted = await run.value

        XCTAssertFalse(deleted, "identity changed across the await: refused")
        XCTAssertNotNil(fetchSession(id), "the local entry is kept")
        XCTAssertEqual(queue.items, before, "no enqueue, and A's publish is untouched")
    }

    /// Another identity's queued publish for the same post is never read, merged
    /// or superseded, and no owner is taken from the current sign-in for it.
    func testForeignOwnerQueuedPublish_Untouched() async throws {
        let id = try newSharedSession()
        XCTAssertTrue(queue.enqueue(publishPayload(id, owner: ownerB)), "setup: B's publish is durable")
        let foreign = ownItem(id, owner: ownerB)
        XCTAssertNotNil(foreign)

        let deleted = await journalDelete(id, capturedOwner: SessionSyncQueue.currentOwner())

        XCTAssertTrue(deleted, "no same-owner work: proceeds as before")
        XCTAssertEqual(ownItem(id, owner: ownerB), foreign, "B's work, byte for byte")
        XCTAssertNil(ownItem(id), "nothing was created for A")
    }

    // MARK: - Durability

    /// A failed supersession write leaves memory at `.unshare` and disk at
    /// `.publish`. A repeat delete must not treat the in-memory unshare as done:
    /// it refuses until the queue is saved, and then disk holds the withdrawal.
    func testRepeatDelete_AfterFailedWrite_RefusesUntilDurable() async throws {
        let id = try await sharedSessionWithQueuedPublish()
        try failWritesLeavingAnOlderValidEnvelope()

        let first = await journalDelete(id, capturedOwner: SessionSyncQueue.currentOwner())
        XCTAssertFalse(first, "the withdrawal did not reach disk: refused")
        XCTAssertEqual(ownItem(id)?.op, .unshare, "memory holds the newer intent")
        XCTAssertEqual(try onDiskOp(id, owner: ownerA), .publish, "disk still holds the older publish")
        XCTAssertNotNil(fetchSession(id), "the local entry is kept")

        let second = await journalDelete(id, capturedOwner: SessionSyncQueue.currentOwner())
        XCTAssertFalse(second, "still unsaved: the in-memory unshare must not bypass durability")
        XCTAssertNotNil(fetchSession(id))

        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil
        let third = await journalDelete(id, capturedOwner: SessionSyncQueue.currentOwner())
        XCTAssertTrue(third, "recovered and saved: now allowed")
        XCTAssertNil(fetchSession(id))
        XCTAssertEqual(try onDiskOp(id, owner: ownerA), .unshare, "disk now holds the withdrawal")

        queue.unitTestSimulateRelaunch()
        XCTAssertEqual(ownItem(id)?.op, .unshare, "after a relaunch the withdrawal is what reloads")
        let afterRelaunch = QueueStubServer.position
        await queue.flushNow()
        XCTAssertFalse(QueueStubServer.arrived(key("POST", id), since: afterRelaunch), "nothing is re-published")
    }

    /// A store already halted at launch: memory never saw the file, so it cannot
    /// say "nothing queued". Recovery runs first, and the publish on disk is found
    /// and superseded.
    func testHaltedStoreAtLaunch_RecoversThenSupersedes() async throws {
        let id = try await sharedSessionWithQueuedPublish()
        queue.unitTestSimulateStartupHalt()
        XCTAssertNil(ownItem(id), "setup: memory does not see the queued publish")

        let deleted = await journalDelete(id, capturedOwner: SessionSyncQueue.currentOwner())

        XCTAssertTrue(deleted)
        XCTAssertEqual(ownItem(id)?.op, .unshare, "the publish found on disk was superseded")
        XCTAssertEqual(try onDiskOp(id, owner: ownerA), .unshare)
        let after = QueueStubServer.position
        await queue.flushNow()
        XCTAssertFalse(QueueStubServer.arrived(key("POST", id), since: after))
    }

    /// Halted and unrecoverable: refuse, even though memory shows nothing queued.
    func testHaltedStoreUnrecoverable_Refuses() async throws {
        let id = try await sharedSessionWithQueuedPublish()
        try failWritesLeavingAnOlderValidEnvelope()
        queue.unitTestSimulateStartupHalt()

        let deleted = await journalDelete(id, capturedOwner: SessionSyncQueue.currentOwner())

        XCTAssertFalse(deleted, "the queue cannot be saved, so it cannot answer: refused")
        XCTAssertNotNil(fetchSession(id))
    }

    // MARK: - ContentView calls the helper

    /// Comments stripped. The owner is captured before the Task, and the journal
    /// delete goes through the helper before local deletion, with no direct
    /// backend delete left in it.
    func testContentView_UsesTheHelperBeforeLocalDeletion() throws {
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

        guard let step = code.range(of: "JournalDeleteBackendStep.run(postID: postID, capturedOwner: capturedOwner)"),
              let local = code.range(of: "viewContext.delete(session)") else {
            return XCTFail("the helper or the local delete is missing")
        }
        XCTAssertLessThan(step.lowerBound, local.lowerBound, "backend step first, then local deletion")
        XCTAssertFalse(code.contains("publish.deletePost("), "no direct backend delete bypassing the helper")
    }
}
