//
//  P6I02OwnershipBehaviourTests.swift
//  MOTIVOTests
//
//  P6-I-02, Unit 2a — OWNERSHIP, EXECUTED RATHER THAN READ.
//
//  These cases replace the source-text assertions that stood in for them. A
//  test that greps production source for a fragment proves the fragment is
//  present; it cannot prove the queue holds A's work while B is signed in, and
//  it passes unchanged if the surrounding logic is wrong. Every case here drives
//  the real `SessionSyncQueue.shared` and the real `PublishService`, and scores
//  the request timeline.
//
//  NO NETWORK AND NO BACKEND. They reuse `QueueStubServer` / `QueueStubFixture`
//  from SyncQueueOrderingTests — the same held URLProtocol stub C-87 uses — so
//  nothing here needs a live stack. Identity is switched by writing the same
//  UserDefaults key the app reads, on a disposable synthetic uid; no account,
//  no device and no personal data is involved.
//
//  FAILING-FIRST. Each case was run against the pre-fix source and failed; the
//  raw logs are in the Unit 2a evidence directory.
//

import XCTest
import CoreData
@testable import Etudes

@MainActor
final class P6I02OwnershipBehaviourTests: XCTestCase {

    private var queue: SessionSyncQueue { SessionSyncQueue.shared }

    /// Two disposable synthetic identities. A is the fixture's own owner, so
    /// payloads built by `QueueStubFixture.payload` belong to A.
    private let ownerA = QueueStubFixture.ownerUID
    private let ownerB = "00000000-0000-0000-0000-0000000c8702"

    private func signIn(_ uid: String) {
        // P6-I-02 Unit 2b. A sign-in changes BOTH the recorded identity and the
        // token, and the queue now sends only as a token whose subject is the
        // owner — so the fixture changes both, as the app does.
        NetworkManager.shared.setBearerToken(QueueStubFixture.token(sub: uid, jti: "signin-\(uid.suffix(4))"))
        UserDefaults.standard.set(uid, forKey: "supabaseUserID_v1")
        queue.noteIdentityChanged(reason: "test:identity→\(uid.suffix(4))")
        XCTAssertEqual(SessionSyncQueue.currentOwner(), uid, "fixture: the app must read this identity")
    }

    override func setUp() async throws {
        try await super.setUp()
        QueueStubFixture.connect()
        try LocalStackSupport.requireRealBackend(baseURL: QueueStubServer.baseURL.absoluteString)
        queue.clear()
        signIn(ownerA)
    }

    override func tearDown() async throws {
        QueueStubFixture.attachTimeline(to: self)
        QueueStubServer.releaseAll()
        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil
        // A latched store would poison every later case in this process — the
        // C-91 lesson. Repair it here rather than leaving it for the next test.
        if !queue.reconcileState.isOK {
            try? FileManager.default.removeItem(at: SessionSyncQueue.currentFileURL())
            _ = queue.attemptStoreRecovery()
        }
        queue.clear()
        QueueStubFixture.disconnect()
        try await super.tearDown()
    }

    private func post(_ id: UUID) -> String { QueueStubServer.key("POST", id) }

    // MARK: - 1. A → B → A

    /// A queues a publish, B signs in, and nothing of A's is sent. When A
    /// returns it is sent, unchanged. The hold is not an error state: it is A's
    /// work waiting for A.
    func testWorkQueuedByAIsHeldWhileBIsSignedInAndResumesWhenAReturns() async throws {
        let id = UUID()
        XCTAssertTrue(queue.enqueue(QueueStubFixture.payload(id, shared: true)))
        XCTAssertEqual(queue.items.first(where: { $0.id == id })?.ownerUserID, ownerA)

        QueueStubServer.mark("B signs in")
        signIn(ownerB)
        await queue.flushNow()

        XCTAssertEqual(QueueStubServer.count(post(id)), 0,
                       "A's queued publish must not be dispatched while B is signed in")
        XCTAssertTrue(queue.items.contains { $0.id == id && $0.ownerUserID == ownerA },
                      "held, not discarded")

        QueueStubServer.mark("A returns")
        signIn(ownerA)
        await queue.flushNow()

        XCTAssertEqual(QueueStubServer.count(post(id)), 1, "A's own work is sent when A returns")
        XCTAssertFalse(queue.items.contains { $0.id == id }, "and is acknowledged")
    }

    // MARK: - 2. One post id, two owners

    /// The same post id queued by two identities is two separate items. They
    /// must not merge — a merge would publish one member's title and notes under
    /// the other's intent — and one's acknowledgement must not dequeue the
    /// other's.
    func testSamePostForTwoOwnersNeitherMergesNorAcknowledgesTheOther() async throws {
        let id = UUID()
        XCTAssertTrue(queue.enqueue(QueueStubFixture.payload(id, shared: true)))

        let bIntent = SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: id, sessionTimestamp: Date(), title: "belongs-to-B",
            durationSeconds: 900, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil,
            isPublic: true, notes: "B's private notes", areNotesPrivate: true
        ).withOwner(ownerB)
        XCTAssertTrue(queue.enqueue(bIntent))

        let forThisPost = queue.items.filter { $0.id == id }
        XCTAssertEqual(forThisPost.count, 2, "two owners, two items")
        XCTAssertEqual(forThisPost.first(where: { $0.ownerUserID == ownerA })?.title, "c87",
                       "A's intent is untouched by B's")
        XCTAssertNil(forThisPost.first(where: { $0.ownerUserID == ownerA })?.notes,
                     "B's notes must not merge into A's item")
        XCTAssertEqual(forThisPost.first(where: { $0.ownerUserID == ownerB })?.title, "belongs-to-B")

        await queue.flushNow()   // signed in as A

        XCTAssertEqual(QueueStubServer.count(post(id)), 1, "exactly one of them was sent")
        XCTAssertFalse(queue.items.contains { $0.id == id && $0.ownerUserID == ownerA },
                       "A's item is acknowledged")
        XCTAssertTrue(queue.items.contains { $0.id == id && $0.ownerUserID == ownerB },
                      "A's acknowledgement must not dequeue B's work for the same post")
    }

    // MARK: - 3. Capture happens before the deferred Task

    /// The producer captures the owner synchronously at the member's action. The
    /// identity is changed after `publish` returns but before its deferred
    /// `Task` body runs — which is exactly the window the defect lived in — and
    /// the queued item must still belong to A.
    func testTheOwnerIsCapturedBeforeTheDeferredTaskRuns() async throws {
        let id = UUID()
        let oid = try unresolvableObjectID()
        let incoming = SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: id, sessionTimestamp: Date(), title: "capture-window",
            durationSeconds: 60, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil, isPublic: true
        )
        XCTAssertNil(incoming.ownerUserID, "fixture: the view sends no owner; the producer binds it")

        PublishService.shared.publish(payload: incoming, objectID: oid, shouldPublish: true)
        // NO AWAIT ABOVE OR BELOW THIS LINE until the identity has changed: the
        // deferred Task is @MainActor and cannot have run yet.
        QueueStubServer.mark("identity changes before the deferred Task runs")
        signIn(ownerB)

        let queued = await QueueStubFixture.poll(timeout: 5) { self.queue.items.contains { $0.id == id } }
        XCTAssertTrue(queued, "the publish reached the queue")
        XCTAssertEqual(queue.items.first(where: { $0.id == id })?.ownerUserID, ownerA,
                       "the owner captured at the action, not the identity signed in when the Task ran")
        XCTAssertEqual(QueueStubServer.count(post(id)), 0, "and nothing of A's was uploaded as B")
    }

    // MARK: - 4. An explicitly unknown owner refuses; it never falls back

    /// `enqueue(postID:capturedOwner:)` takes an owner the CALLER captured. A
    /// nil there means "captured, and unknown" and must refuse. Falling back to
    /// `currentOwner()` is the defect: the capture happened before a deferred
    /// Task, so the fallback adopts whoever is signed in later.
    func testAnExplicitlyUnknownCapturedOwnerIsRefusedRatherThanAdopted() async throws {
        let refused = UUID(), blank = UUID(), captured = UUID()

        XCTAssertFalse(queue.enqueue(postID: refused, capturedOwner: nil))
        XCTAssertFalse(queue.enqueue(postID: blank, capturedOwner: "   "))
        for id in [refused, blank] {
            XCTAssertFalse(queue.items.contains { $0.id == id }, "nothing dispatchable was created")
            XCTAssertFalse(queue.quarantined.contains { $0.id == id },
                           "a refusal records nothing; there is no member intent to hold")
        }

        // The convenience overload captures AT THE CALL, which is safe only
        // because the call is synchronous with the action.
        XCTAssertTrue(queue.enqueue(postID: captured))
        XCTAssertEqual(queue.items.first(where: { $0.id == captured })?.ownerUserID, ownerA)

        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(post(refused)), 0)
        XCTAssertEqual(QueueStubServer.count(post(blank)), 0)
        XCTAssertEqual(QueueStubServer.count(post(captured)), 1)
    }

    // MARK: - 5. Unattributable work is quarantined, not filtered

    /// A payload whose owner is absent or empty is HELD, not admitted to the
    /// dispatchable set. Relying on the flush filter alone was wrong: such an
    /// item still sat in `items`, where it could merge with real work or be
    /// cleared alongside it.
    func testUnattributableWorkIsQuarantinedAndNeverDispatched() async throws {
        let unowned = UUID(), empty = UUID()
        defer {
            queue.stopForFactoryReset()
            queue.resumeAfterFactoryReset()
        }

        queue.enqueue(QueueStubFixture.payload(unowned, shared: true).withOwner(nil))
        queue.enqueue(QueueStubFixture.payload(empty, shared: true).withOwner("   "))

        for id in [unowned, empty] {
            XCTAssertFalse(queue.items.contains { $0.id == id }, "never dispatchable")
            XCTAssertTrue(queue.quarantined.contains { $0.id == id }, "and never discarded either")
        }

        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(post(unowned)), 0)
        XCTAssertEqual(QueueStubServer.count(post(empty)), 0)

        // Nor does signing in adopt it. Quarantine leaves only by explicit
        // reauthorisation, which this unit does not build.
        signIn(ownerB)
        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(post(unowned)), 0)
        XCTAssertTrue(queue.quarantined.contains { $0.id == unowned })
    }

    // MARK: - 6. A halted store dispatches nothing

    /// A write that fails readback latches the store. The member's newer intent
    /// is retained in memory and reported as not durable, nothing is dispatched
    /// from it, and recovery is explicit.
    func testAHaltedStoreDispatchesNothingAndRecoveryPreservesTheNewerIntent() async throws {
        let id = UUID()
        let file = SessionSyncQueue.currentFileURL()

        SessionSyncQueueStore.unitTestCorruptAfterWrite = {
            try? Data("{ not an envelope".utf8).write(to: file, options: .atomic)
        }
        let durable = queue.enqueue(QueueStubFixture.payload(id, shared: true))
        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil

        XCTAssertFalse(durable, "the caller is told the write did not land")
        XCTAssertFalse(queue.reconcileState.isOK, "the store is latched, not merely logged")
        XCTAssertTrue(queue.memoryDivergesFromDisk)
        XCTAssertTrue(queue.items.contains { $0.id == id },
                      "the member's intent is retained; a failed write must not discard it")

        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(post(id)), 0,
                       "a halted store is not a safe basis for dispatch")

        XCTAssertFalse(queue.attemptStoreRecovery().isOK,
                       "recovery refuses while the damage is still on disk")

        // HARNESS REPAIR, not product behaviour: production preserves a damaged
        // file and halts. Removing it here is how the test reaches the recovery
        // path the member would reach after the file was dealt with.
        try? FileManager.default.removeItem(at: file)
        XCTAssertTrue(queue.attemptStoreRecovery().isOK)
        XCTAssertFalse(queue.memoryDivergesFromDisk)
        XCTAssertTrue(queue.items.contains { $0.id == id }, "recovery keeps the newer in-memory intent")

        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(post(id)), 1, "and it dispatches once the store is sound")
    }

    // MARK: - 7. An identity change does not start a second concurrent flush

    /// C-87's single flight must survive an identity change. The earlier
    /// revision dropped the in-flight handle, so the next flush saw none and
    /// started a second pass while A's request was still suspended.
    ///
    /// THE SEQUENCE MATTERS AND MY FIRST VERSION OF THIS CASE HAD IT WRONG. It
    /// signed in as B and flushed, which proves nothing: B cannot dispatch A's
    /// item under any implementation, so a missing single-flight guard has
    /// nothing to expose. The overlap needs A to RETURN while the first request
    /// is still in flight — the item dispatchable again, its revision unchanged,
    /// and its request not yet answered. Measured: the earlier revision sends it
    /// a second time, concurrently.
    func testIdentityChangeDrainsTheRunningFlushInsteadOfStartingASecondOne() async throws {
        let id = UUID()
        let flush = try await QueueStubFixture.publishHeldInFlight(queue, id)

        QueueStubServer.mark("A signs out while its POST is in flight")
        signIn(ownerB)
        QueueStubServer.mark("A signs back in, the POST still unanswered")
        signIn(ownerA)

        let joining = Task { await self.queue.flushNow() }
        let overlapped = await QueueStubFixture.poll(timeout: 1.5) {
            QueueStubServer.count(self.post(id)) > 1
        }
        XCTAssertFalse(overlapped,
                       "the same item must not be sent again while its first request is still in flight")

        QueueStubServer.mark("release the held POST")
        QueueStubServer.release(post(id))
        await flush.value
        await joining.value

        // The first pass's acknowledgement belonged to a superseded generation
        // and was withheld, so the intent survived and the follow-up pass — which
        // the drain arranges rather than dropping — sent it once, sequentially.
        XCTAssertEqual(QueueStubServer.count(post(id)), 2,
                       "two sequential sends, never two concurrent ones")
        XCTAssertFalse(queue.items.contains { $0.id == id },
                       "and the wakeup was not lost: the follow-up pass acknowledged it")
    }

    // MARK: - 8. Recovery from a write that did not take

    /// A FAILED WRITE THAT LEAVES A VALID, OLDER ENVELOPE — the realistic shape,
    /// and the one a corrupt-file test cannot reach. Recovery reads a file that
    /// decodes perfectly and is simply out of date, so an append-what-is-missing
    /// union silently prefers it: the publish persisted before the halt beats the
    /// withdrawal the member made after it.
    func testRecoveryPrefersTheNewerInMemoryWithdrawalOverTheOlderPersistedPublish() async throws {
        let id = UUID()
        XCTAssertTrue(queue.enqueue(QueueStubFixture.payload(id, shared: true)),
                      "fixture: the publish is durable")

        try failNextWriteLeavingAnOlderValidEnvelope()
        let durable = queue.enqueue(QueueStubFixture.payload(id, shared: false))
        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil

        XCTAssertFalse(durable, "the withdrawal did not reach disk")
        XCTAssertFalse(queue.reconcileState.isOK)
        let onDisk = try JSONDecoder().decode(SessionSyncQueueEnvelope.self,
                                              from: Data(contentsOf: SessionSyncQueue.currentFileURL()))
        XCTAssertEqual(onDisk.items.first(where: { $0.id == id })?.op, .publish,
                       "fixture: the file is VALID and older — not corrupt")
        XCTAssertEqual(queue.items.first(where: { $0.id == id })?.op, .unshare,
                       "memory holds the newer intent")

        XCTAssertTrue(queue.attemptStoreRecovery().isOK)

        XCTAssertEqual(queue.items.first(where: { $0.id == id })?.op, .unshare,
                       "the member's withdrawal must survive recovery; the older persisted publish must not win")
        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(post(id)), 0, "and nothing is re-published")
    }

    /// AN ABSENT KEY IS INTENT TOO. When the acknowledgement's own persist fails,
    /// memory has removed the item and disk still holds it; recovery must not
    /// read the gap as "nothing to merge" and put it back.
    func testRecoveryDoesNotResurrectWorkMemoryAlreadyRemoved() async throws {
        let id = UUID()
        XCTAssertTrue(queue.enqueue(QueueStubFixture.payload(id, shared: true)))

        try failNextWriteLeavingAnOlderValidEnvelope()
        queue.dequeue(postID: id)
        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil

        XCTAssertFalse(queue.reconcileState.isOK, "the removal did not reach disk, so the store latched")
        XCTAssertFalse(queue.items.contains { $0.id == id }, "memory has removed it")

        XCTAssertTrue(queue.attemptStoreRecovery().isOK)
        XCTAssertFalse(queue.items.contains { $0.id == id },
                       "recovery must not resurrect work memory had already removed")
        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(post(id)), 0)
    }

    // MARK: - 9. A halt that arrives mid-flush

    /// The entry guard is not enough. A write can fail WHILE a request is being
    /// awaited — an acknowledgement's own persist is the likeliest one — and the
    /// remaining items of the snapshot would then be dispatched from a store that
    /// is no longer a safe basis for dispatch.
    func testAHaltWhileARequestIsInFlightStopsTheRestOfTheFlush() async throws {
        let first = UUID(), second = UUID()
        XCTAssertTrue(queue.enqueue(QueueStubFixture.payload(first, shared: true)))
        XCTAssertTrue(queue.enqueue(QueueStubFixture.payload(second, shared: true)))

        QueueStubServer.hold(post(first))
        let flush = Task { await self.queue.flushNow() }
        guard await QueueStubFixture.poll(timeout: 5, { QueueStubServer.count(self.post(first)) == 1 }) else {
            QueueStubServer.releaseAll()
            await flush.value
            return XCTFail("setup: the first POST was never observed in flight, so nothing after this tests the halt")
        }

        try failNextWriteLeavingAnOlderValidEnvelope()
        QueueStubServer.mark("release the first POST; its acknowledgement will fail to persist")
        QueueStubServer.release(post(first))
        await flush.value
        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil

        XCTAssertFalse(queue.reconcileState.isOK, "the failed acknowledgement latched the store")
        XCTAssertEqual(QueueStubServer.count(post(second)), 0,
                       "the rest of the snapshot must not be dispatched from a halted store")
        XCTAssertTrue(queue.items.contains { $0.id == second }, "and it is retained, not lost")
    }

    // MARK: - 10. Recovery after a halt that was already in place at launch

    /// THE OTHER RECOVERY BRANCH. When the store was already halted when the
    /// process started, memory never saw the file, so unrelated work on it is
    /// real and must be kept — but where both hold the SAME key, memory is still
    /// the newer of the two. Appending only what was missing let the older
    /// on-disk publish beat the withdrawal made after the halt.
    ///
    /// It also proves the adopted disk-only item actually SENDS: work merged in
    /// from the file has no revision entry, and the per-item guard compares a
    /// missing revision against the snapshot's default of 0, so without one it is
    /// skipped on every pass for ever.
    func testStartupHaltRecoveryKeepsUnrelatedDiskWorkAndLetsMemoryOverrideItsOwnKey() async throws {
        let withdrawn = UUID(), unrelated = UUID()
        XCTAssertTrue(queue.enqueue(QueueStubFixture.payload(withdrawn, shared: true)))
        XCTAssertTrue(queue.enqueue(QueueStubFixture.payload(unrelated, shared: true)),
                      "fixture: both are durable on disk before the halt")

        // The process now starts with the store halted: nothing loaded.
        queue.unitTestSimulateStartupHalt()
        XCTAssertFalse(queue.reconcileState.isOK)
        XCTAssertTrue(queue.items.isEmpty, "fixture: memory holds nothing from the file")

        // The member withdraws one of them while the store is halted.
        XCTAssertFalse(queue.enqueue(QueueStubFixture.payload(withdrawn, shared: false)),
                       "not durable — the store is halted")
        XCTAssertTrue(queue.memoryDivergesFromDisk)

        XCTAssertTrue(queue.attemptStoreRecovery().isOK)

        XCTAssertEqual(queue.items.first(where: { $0.id == withdrawn })?.op, .unshare,
                       "memory overrides the file for its OWN key")
        XCTAssertEqual(queue.items.first(where: { $0.id == unrelated })?.op, .publish,
                       "and unrelated work on the file is kept, not discarded")

        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(post(unrelated)), 1,
                       "work adopted from the file must actually send: it needs a revision")
        XCTAssertEqual(QueueStubServer.count(post(withdrawn)), 0, "and the withdrawn post is not published")
        XCTAssertTrue(queue.items.isEmpty, "both converged and were acknowledged")
    }

    /// Recovery applies the SAME provenance invariant as load. An unowned item
    /// on the file must be quarantined when recovery adopts it, not dispatched —
    /// an earlier revision normalised on load only.
    func testRecoveryQuarantinesUnownedWorkAdoptedFromTheFile() async throws {
        let unowned = UUID()
        defer {
            queue.stopForFactoryReset()
            queue.resumeAfterFactoryReset()
        }

        // A file written with an unowned item in its DISPATCHABLE set — the shape
        // a downgraded build, or a build before this unit, leaves behind.
        var envelope = SessionSyncQueueEnvelope.empty()
        envelope.items = [QueueStubFixture.payload(unowned, shared: true).withOwner(nil)]
        try JSONEncoder().encode(envelope).write(to: SessionSyncQueue.currentFileURL(), options: .atomic)

        queue.unitTestSimulateStartupHalt()
        XCTAssertTrue(queue.attemptStoreRecovery().isOK)

        XCTAssertFalse(queue.items.contains { $0.id == unowned },
                       "recovery must not adopt unattributable work into the dispatchable set")
        XCTAssertTrue(queue.quarantined.contains { $0.id == unowned }, "it is held, not discarded")

        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(post(unowned)), 0)
    }

    // MARK: - Fixture

    /// Makes the NEXT write fail while leaving a VALID, OLDER envelope on disk:
    /// the bytes from before the write are put back, so the readback decodes
    /// cleanly and simply is not what was intended. That is a write that did not
    /// take — a different, and more realistic, failure from a torn or corrupt
    /// file, and the only one that can expose a recovery merge preferring disk.
    private func failNextWriteLeavingAnOlderValidEnvelope() throws {
        let file = SessionSyncQueue.currentFileURL()
        let older = try Data(contentsOf: file)
        SessionSyncQueueStore.unitTestCorruptAfterWrite = {
            try? older.write(to: file, options: .atomic)
        }
    }

    /// An object id the producer cannot resolve, so its Core Data enrichment
    /// fails and the incoming payload is used unchanged. Asserted, so the case
    /// cannot pass because the object happened to resolve.
    private func unresolvableObjectID() throws -> NSManagedObjectID {
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = PersistenceController.shared.container.persistentStoreCoordinator
        let o = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        let oid = o.objectID
        ctx.rollback()
        XCTAssertThrowsError(try PersistenceController.shared.container.viewContext.existingObject(with: oid))
        return oid
    }
}
