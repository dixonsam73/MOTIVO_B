//
//  P6I02SharingChoiceSaveTests.swift
//  MOTIVOTests
//
//  P6-I-02 Unit 2d-1 — the member is told when a sharing choice could not be
//  saved; the editor finishes exactly once; Try Again re-saves the QUEUE only.
//
//  THIS SLICE IS NOT DURABLE INTENT. `testOPEN_…` characterises what a relaunch
//  sees after a failed save (P6-I-03) and passes while that gap exists.
//
//  No network: the held `QueueStubServer`. Failed writes use the store's
//  existing test seam, restoring the older valid envelope — a write that did not
//  take. Synthetic uids, disposable data.
//

import XCTest
import CoreData
@testable import Etudes

// MARK: - The gate: exactly once, and nothing repeated

@MainActor
final class P6I02SharingChoiceSaveGateTests: XCTestCase {

    func testSaved_FinishesImmediatelyExactlyOnce_NoAlert() {
        var finishes = 0
        let gate = SharingChoiceSaveGate(recover: { XCTFail("no recovery when saved"); return true })
        gate.handle(.saved, stoppingSharing: false) { finishes += 1 }
        XCTAssertEqual(finishes, 1)
        XCTAssertFalse(gate.isPresented)
        XCTAssertFalse(gate.isAwaitingDecision)
    }

    func testHeldUnowned_IsNotAFailure() {
        var finishes = 0
        let gate = SharingChoiceSaveGate(recover: { XCTFail("no recovery"); return true })
        gate.handle(.heldUnowned, stoppingSharing: false) { finishes += 1 }
        XCTAssertEqual(finishes, 1)
        XCTAssertFalse(gate.isPresented)
    }

    func testNotSaved_WaitsForTheMember_AndLocksSave() {
        var finishes = 0
        let gate = SharingChoiceSaveGate(recover: { false })
        gate.handle(.notSaved, stoppingSharing: true) { finishes += 1 }
        XCTAssertEqual(finishes, 0, "the callback and dismissal must not fire before the alert resolves")
        XCTAssertTrue(gate.isPresented)
        XCTAssertTrue(gate.stoppingSharing)
        XCTAssertTrue(gate.isAwaitingDecision, "editors disable Save while this is true — no second session behind the alert")
    }

    func testOK_FinishesOnce_AndLaterAnswersDoNothing() {
        var finishes = 0, recoveries = 0
        let gate = SharingChoiceSaveGate(recover: { recoveries += 1; return true })
        gate.handle(.notSaved, stoppingSharing: false) { finishes += 1 }
        gate.acknowledge()
        gate.acknowledge()
        gate.tryAgain()
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(recoveries, 0, "Try Again after the editor finished must not re-save anything")
        XCTAssertFalse(gate.isAwaitingDecision)
    }

    func testTryAgainSucceeds_OnlyTheQueueIsRetried_AndTheEditorFinishesOnce() {
        var finishes = 0, recoveries = 0
        let gate = SharingChoiceSaveGate(recover: { recoveries += 1; return true })
        gate.handle(.notSaved, stoppingSharing: false) { finishes += 1 }
        gate.tryAgain()
        XCTAssertEqual(recoveries, 1, "Try Again calls the queue recovery — and nothing else")
        XCTAssertEqual(finishes, 1)
        XCTAssertFalse(gate.isPresented)
    }

    func testTryAgainFails_StaysOpen_ThenOKFinishesOnce() async {
        var finishes = 0, recoveries = 0
        let gate = SharingChoiceSaveGate(recover: { recoveries += 1; return false })
        gate.handle(.notSaved, stoppingSharing: false) { finishes += 1 }
        gate.tryAgain()
        XCTAssertEqual(finishes, 0)
        XCTAssertTrue(gate.isAwaitingDecision)
        let shownAgain = await QueueStubFixture.poll(timeout: 2) { gate.isPresented }
        XCTAssertTrue(shownAgain, "the alert returns after a failed Try Again")
        gate.acknowledge()
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(recoveries, 1)
    }

    func testEachSaveFinishesOnce_ASecondSaveIsNotSwallowed() {
        var finishes = 0
        let gate = SharingChoiceSaveGate(recover: { true })
        gate.handle(.notSaved, stoppingSharing: false) { finishes += 1 }
        gate.acknowledge()
        gate.handle(.saved, stoppingSharing: false) { finishes += 1 }
        XCTAssertEqual(finishes, 2)
    }

    // MARK: Copy

    func testCopy_StopSharingSaysFollowersMayStillSeeThePost() {
        XCTAssertTrue(SharingChoiceSaveCopy.message(stoppingSharing: true).contains("followers may still see the post"))
        XCTAssertFalse(SharingChoiceSaveCopy.message(stoppingSharing: false).contains("followers may still see"))
    }

    func testCopy_PromisesNothingItCannotKeep() {
        for stopping in [true, false] {
            let text = SharingChoiceSaveCopy.message(stoppingSharing: stopping).lowercased()
            for banned in ["will keep trying", "automatically", "completes on its own", "all requests", "nothing will be sent"] {
                XCTAssertFalse(text.contains(banned), "\(stopping): \(banned)")
            }
            XCTAssertTrue(text.contains("this change") || text.contains("your choice"), "the copy is about THIS choice")
            XCTAssertTrue(text.contains("may be lost if études closes"), "and honest about restart")
        }
    }
}

// MARK: - The queue and the producer: real failed writes

@MainActor
final class P6I02SharingChoiceSaveQueueTests: XCTestCase {

    private var queue: SessionSyncQueue { SessionSyncQueue.shared }
    private let owner = QueueStubFixture.ownerUID

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
        if !queue.reconcileState.isOK {
            try? FileManager.default.removeItem(at: SessionSyncQueue.currentFileURL())
            _ = queue.attemptStoreRecovery()
        }
        queue.stopForFactoryReset()          // clears quarantine too
        queue.resumeAfterFactoryReset()
        QueueStubFixture.disconnect()
        try await super.tearDown()
    }

    /// The NEXT write fails while leaving the older, valid envelope on disk.
    private func failWritesLeavingOlderEnvelope() throws {
        let file = SessionSyncQueue.currentFileURL()
        let older = try Data(contentsOf: file)
        SessionSyncQueueStore.unitTestCorruptAfterWrite = { try? older.write(to: file, options: .atomic) }
    }

    private func objectID() throws -> NSManagedObjectID {
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = PersistenceController.shared.container.persistentStoreCoordinator
        let o = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        let oid = o.objectID
        ctx.rollback()
        return oid
    }

    private func payload(_ id: UUID, shared: Bool) -> SessionSyncQueue.PostPublishPayload {
        SessionSyncQueue.PostPublishPayload(id: id, sessionID: id, sessionTimestamp: nil, title: "2d-1",
                                            durationSeconds: 60, activityType: nil, activityDetail: nil,
                                            instrumentLabel: nil, mood: nil, effort: nil, isPublic: shared)
    }

    private func onDisk() throws -> SessionSyncQueueEnvelope {
        try JSONDecoder().decode(SessionSyncQueueEnvelope.self, from: Data(contentsOf: SessionSyncQueue.currentFileURL()))
    }

    // F7 — queued at the member's action, not later in a Task.
    func testF7_TheChoiceIsQueuedBeforePublishReturns() throws {
        let id = UUID()
        let result = PublishService.shared.publish(payload: payload(id, shared: true), objectID: try objectID(), shouldPublish: true)
        XCTAssertEqual(result, .saved)
        XCTAssertTrue(queue.items.contains { $0.id == id }, "already queued when publish returns — the kill-in-the-gap window is gone")
        XCTAssertTrue(try onDisk().items.contains { $0.id == id }, "and on disk")
    }

    // F1 — a failed write is reported, held in memory, and nothing is sent.
    func testF1_FailedWrite_IsNotSaved_HeldInMemory_NothingSent() async throws {
        let seed = UUID()
        _ = queue.enqueueReportingSave(payload(seed, shared: true).withOwner(owner))   // a valid older envelope
        QueueStubServer.hold(QueueStubServer.key("POST", seed))                      // keep the seed from flushing away
        try failWritesLeavingOlderEnvelope()

        let id = UUID()
        let result = PublishService.shared.publish(payload: payload(id, shared: false), objectID: try objectID(), shouldPublish: false)
        XCTAssertEqual(result, .notSaved)
        XCTAssertTrue(queue.items.contains { $0.id == id && $0.op == .unshare }, "held in memory")
        XCTAssertFalse(try onDisk().items.contains { $0.id == id }, "not on disk")

        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(QueueStubServer.key("DEMOTE", id)), 0, "this unsaved choice was not sent")
    }

    // F2 — Try Again re-saves the queue; the choice is then on disk and sent.
    func testF2_TryAgainRecovers_ChoiceSavedAndThenSent() async throws {
        _ = queue.enqueueReportingSave(payload(UUID(), shared: true).withOwner(owner))
        try failWritesLeavingOlderEnvelope()
        let id = UUID()
        XCTAssertEqual(PublishService.shared.publish(payload: payload(id, shared: true), objectID: try objectID(), shouldPublish: true), .notSaved)
        // As in the app: the publish's own flush runs right after the save and is
        // REFUSED while the store is latched — before the member sees the alert.
        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(QueueStubServer.key("POST", id)), 0, "fixture: refused while unsaved")

        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil          // the disk works again
        var finishes = 0
        let gate = SharingChoiceSaveGate()                            // the REAL recovery
        gate.handle(.notSaved, stoppingSharing: false) { finishes += 1 }
        gate.tryAgain()

        XCTAssertEqual(finishes, 1)
        XCTAssertTrue(try onDisk().items.contains { $0.id == id }, "saved by Try Again")
        // NO manual flush: Try Again itself must schedule the ordinary flush.
        let sent = await QueueStubFixture.poll(timeout: 5) { QueueStubServer.count(QueueStubServer.key("POST", id)) == 1 }
        XCTAssertTrue(sent, "Try Again's recovery is followed by a flush that sends the choice")
    }

    // F3 — Try Again while the disk still fails: not finished, nothing sent.
    func testF3_TryAgainStillFailing_NothingFinished_NothingSent() async throws {
        _ = queue.enqueueReportingSave(payload(UUID(), shared: true).withOwner(owner))
        try failWritesLeavingOlderEnvelope()
        let id = UUID()
        XCTAssertEqual(PublishService.shared.publish(payload: payload(id, shared: true), objectID: try objectID(), shouldPublish: true), .notSaved)

        var finishes = 0
        let gate = SharingChoiceSaveGate()
        gate.handle(.notSaved, stoppingSharing: false) { finishes += 1 }
        gate.tryAgain()
        XCTAssertEqual(finishes, 0)
        XCTAssertTrue(gate.isAwaitingDecision)
        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(QueueStubServer.key("POST", id)), 0)
    }

    // Automatic recovery first, then the member's Try Again re-reads state.
    func testAutomaticRecoveryThenTryAgain_FinishesAndStillFlushes() async throws {
        _ = queue.enqueueReportingSave(payload(UUID(), shared: true).withOwner(owner))
        try failWritesLeavingOlderEnvelope()
        let id = UUID()
        XCTAssertEqual(PublishService.shared.publish(payload: payload(id, shared: true), objectID: try objectID(), shouldPublish: true), .notSaved)
        // As in the app: the publish's own flush runs right after the save and is
        // REFUSED while the store is latched — before the member sees the alert.
        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(QueueStubServer.key("POST", id)), 0, "fixture: refused while unsaved")
        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil
        XCTAssertTrue(queue.recoverIfNeeded(reason: "test:foreground"), "the foreground attempt saved it")

        var finishes = 0
        let gate = SharingChoiceSaveGate()
        gate.handle(.notSaved, stoppingSharing: false) { finishes += 1 }
        gate.tryAgain()
        XCTAssertEqual(finishes, 1, "Try Again sees it is already saved and finishes")
        XCTAssertTrue(queue.isFullySaved)
        let sent = await QueueStubFixture.poll(timeout: 5) { QueueStubServer.count(QueueStubServer.key("POST", id)) == 1 }
        XCTAssertTrue(sent, "and still schedules the flush, although the foreground attempt did the saving")
    }

    // F6 — no identity: quarantined AND persisted, reported as held, not dropped.
    func testF6_Ownerless_IsQuarantinedPersisted_AndReportedHeld() throws {
        UserDefaults.standard.removeObject(forKey: "supabaseUserID_v1")
        let id = UUID()
        let result = PublishService.shared.publish(payload: payload(id, shared: true), objectID: try objectID(), shouldPublish: true)
        XCTAssertEqual(result, .heldUnowned)
        XCTAssertTrue(queue.quarantined.contains { $0.id == id })
        XCTAssertTrue(try onDisk().quarantined.contains { $0.id == id }, "persisted to quarantine, as before")
        XCTAssertFalse(queue.items.contains { $0.id == id }, "never dispatchable")
    }

    // F6b — an ownerless choice whose quarantine write fails is NOT hidden.
    func testF6b_OwnerlessQuarantineWriteFails_IsNotSaved() throws {
        _ = queue.enqueueReportingSave(payload(UUID(), shared: true).withOwner(owner))
        try failWritesLeavingOlderEnvelope()
        UserDefaults.standard.removeObject(forKey: "supabaseUserID_v1")
        let id = UUID()
        let result = PublishService.shared.publish(payload: payload(id, shared: true), objectID: try objectID(), shouldPublish: true)
        XCTAssertEqual(result, .notSaved, "a failed quarantine write is a failed save, not 'held'")
        XCTAssertTrue(queue.quarantined.contains { $0.id == id }, "still held in memory")
    }

    // F8 — OPEN (P6-I-03), a characterisation, NOT a safety claim.
    func testOPEN_RestartAfterFailedStopSharing_TheOlderSavedShareIsWhatARelaunchSees() throws {
        let id = UUID()
        XCTAssertEqual(PublishService.shared.publish(payload: payload(id, shared: true), objectID: try objectID(), shouldPublish: true), .saved)
        try failWritesLeavingOlderEnvelope()
        XCTAssertEqual(PublishService.shared.publish(payload: payload(id, shared: false), objectID: try objectID(), shouldPublish: false), .notSaved)
        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil

        // What a relaunch would load: the file, not memory.
        let relaunch = try onDisk()
        XCTAssertEqual(relaunch.items.first { $0.id == id }?.op, .publish,
                       "OPEN: after a failed save and a restart, the older SHARE is what runs — the member was told it may be lost")
    }
}
