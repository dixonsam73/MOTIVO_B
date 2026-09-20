//
//  S2bPublishAdmissionTests.swift
//  MOTIVOTests
//
//  S2b. A publish superseded WHILE ITS ATTACHMENTS ARE BEING PREPARED must not go
//  on to create a post. The admission question is asked once, by the publish
//  service, immediately before its first transport call.
//
//  The window is real because `uploadPostImpl` prepares attachments (awaiting an
//  audio derivative) after the queue's dispatch-time revision check and before the
//  first send, and single flight serialises flushes, not the member's actions.
//
//  WHAT S2b IS NOT: all-phase cancellation. Once admitted, every later phase runs
//  to completion — `testSupersededMidUpload_...` asserts that, and asserts what the
//  withdrawal actually did WHEN IT WAS RUN HERE. Neither the test nor S2b promises
//  that a withdrawal always runs, or that cleanup always follows.
//
//  SYNTHETIC ONLY: loopback stub, synthetic owner and token, disposable Session,
//  attachment and scratch file. No personal media.
//

import XCTest
import CoreData
import UIKit
@testable import Etudes

@MainActor
final class S2bPublishAdmissionTests: XCTestCase {
    private var queue: SessionSyncQueue { SessionSyncQueue.shared }
    private var ctx: NSManagedObjectContext { PersistenceController.shared.container.viewContext }
    private let ownerA = QueueStubFixture.ownerUID
    private let ownerB = "00000000-0000-0000-0000-0000000c8702"
    private var created: [UUID] = []
    private var scratch: [URL] = []
    private var privacyKeys: [(UUID, URL)] = []

    /// Bounded hold seam state. `proceed` is ALWAYS set in teardown, so a missed
    /// hook can never hang the suite; the hook's own wait is bounded too.
    private var seamEntered = false
    private var seamProceed = false

    override func setUp() async throws {
        try await super.setUp()
        QueueStubFixture.connect()
        try LocalStackSupport.requireRealBackend(baseURL: QueueStubServer.baseURL.absoluteString)
        queue.clear()
    }

    override func tearDown() async throws {
        QueueStubFixture.attachTimeline(to: self)
        seamProceed = true                                                   // release any waiter
        HTTPBackendPublishService.unitTestHoldBeforeFirstPublishSend = nil   // always cleared
        QueueStubServer.releaseAll()
        queue.clear()
        for id in created { if let o = fetchSession(id) { ctx.delete(o) } }
        try? ctx.save()
        created = []
        for (id, url) in privacyKeys { AttachmentPrivacy.setPrivate(id: id, url: url, true) }
        privacyKeys = []
        for f in scratch { try? FileManager.default.removeItem(at: f) }
        scratch = []
        QueueStubFixture.disconnect()
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func key(_ op: String, _ id: UUID) -> String { QueueStubServer.key(op, id) }

    private func signIn(_ uid: String) {
        NetworkManager.shared.setBearerToken(QueueStubFixture.token(sub: uid, jti: "signin-\(uid.suffix(4))"))
        UserDefaults.standard.set(uid, forKey: "supabaseUserID_v1")
        queue.noteIdentityChanged(reason: "test:identity→\(uid.suffix(4))")
    }

    private func fetchSession(_ id: UUID) -> NSManagedObject? {
        let r = NSFetchRequest<NSManagedObject>(entityName: "Session")
        r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        r.fetchLimit = 1
        return (try? ctx.fetch(r))?.first
    }

    /// A session carrying one real (tiny, generated) image, so the publish uploads
    /// an object. An image avoids the audio derivative path, which cannot run on a
    /// synthetic file. NOTE: a JPEG's prepared upload carries `temporaryFileURL:
    /// nil` (`BackendShim:~1427`), so this fixture does NOT exercise temporary-file
    /// cleanup; that cleanup is source-reviewed only (the existing
    /// `defer { discardTemporaries() }`).
    private func sessionWithImage() throws -> (session: UUID, attachment: UUID, objectName: String) {
        let sid = UUID(), aid = UUID()
        let s = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        s.setValue(sid, forKey: "id")
        s.setValue(Date(), forKey: "timestamp")
        s.setValue("s2b fixture", forKey: "title")
        s.setValue(true, forKey: "isPublic")
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("\(aid.uuidString).jpg")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { c in
            UIColor.gray.setFill(); c.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        try XCTUnwrap(image.jpegData(compressionQuality: 0.8)).write(to: url)
        scratch.append(url)
        let a = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: ctx)
        a.setValue(aid, forKey: "id")
        a.setValue(Date(), forKey: "createdAt")
        a.setValue(url.path, forKey: "fileURL")
        a.setValue("image", forKey: "kind")
        a.setValue(s, forKey: "session")
        try ctx.save()
        // Attachments are private by default; this one is deliberately included,
        // which is what makes the publish upload an object at all.
        AttachmentPrivacy.setPrivate(id: aid, url: url, false)
        privacyKeys.append((aid, url))
        created.append(sid)
        return (sid, aid, "\(aid.uuidString).jpg")
    }

    private func publish(_ id: UUID, sessionID: UUID? = nil, title: String = "s2b") -> SessionSyncQueue.PostPublishPayload {
        SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: sessionID, sessionTimestamp: nil, title: title,
            durationSeconds: 60, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil, isPublic: true
        ).withOwner(ownerA)
    }

    private func unshare(_ id: UUID) -> SessionSyncQueue.PostPublishPayload {
        SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: nil, sessionTimestamp: nil, title: nil,
            durationSeconds: nil, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil, isPublic: false
        ).withOwner(ownerA)
    }

    /// Installs the bounded hold seam. The hook waits at most 5 s, and the test
    /// waits at most 5 s for it to be entered.
    private func installHoldSeam() {
        seamEntered = false
        seamProceed = false
        HTTPBackendPublishService.unitTestHoldBeforeFirstPublishSend = { [weak self] in
            guard let self else { return }
            self.seamEntered = true
            _ = await QueueStubFixture.poll(timeout: 5) { self.seamProceed }
        }
    }

    private func waitForSeam() async -> Bool {
        await QueueStubFixture.poll(timeout: 5) { self.seamEntered }
    }

    // MARK: - The preparation window

    /// Superseded by the member's WITHDRAWAL during preparation: the publish is
    /// never admitted, so no row and no object are created.
    func testSupersededByUnshareDuringPreparation_PublishNeverSent() async throws {
        let id = UUID()
        XCTAssertTrue(queue.enqueue(publish(id)))
        installHoldSeam()
        let start = QueueStubServer.arrivals.count

        let flush = Task { await queue.flushNow() }
        let entered = await waitForSeam()
        XCTAssertTrue(entered, "setup: the service reached the admission point")
        XCTAssertTrue(queue.enqueue(unshare(id)), "the member withdraws during preparation")
        seamProceed = true
        await flush.value

        XCTAssertEqual(QueueStubServer.count(key("POST", id)), 0, "no row was created")
        XCTAssertFalse(QueueStubServer.hasRow(id))
        XCTAssertTrue(Array(QueueStubServer.arrivals.dropFirst(start)).allSatisfy { !$0.hasPrefix("POST OBJ") },
                      "no object was uploaded")
    }

    /// Superseded by a NEWER PUBLISH during preparation: the stale one is not sent.
    /// Without admission BOTH would have been posted; exactly one POST is the
    /// discriminator.
    func testSupersededByNewerPublishDuringPreparation_OnlyTheLatestIsSent() async throws {
        let id = UUID()
        XCTAssertTrue(queue.enqueue(publish(id, title: "first")))
        installHoldSeam()

        let flush = Task { await queue.flushNow() }
        let entered = await waitForSeam()
        XCTAssertTrue(entered)
        XCTAssertTrue(queue.enqueue(publish(id, title: "second")), "a newer publish lands during preparation")
        HTTPBackendPublishService.unitTestHoldBeforeFirstPublishSend = nil   // the retry must not hold
        seamProceed = true
        await flush.value

        XCTAssertEqual(QueueStubServer.count(key("POST", id)), 1, "exactly one publish was sent, not two")
        XCTAssertTrue(QueueStubServer.hasRow(id))
        XCTAssertFalse(queue.items.contains { $0.id == id }, "the latest intent was sent and acknowledged")
    }

    /// The IDENTITY changes during preparation: the existing binding gate refuses at
    /// the first send, nothing is sent as the new identity, and the item is held.
    func testIdentityChangeDuringPreparation_HeldAndNothingSent() async throws {
        let id = UUID()
        XCTAssertTrue(queue.enqueue(publish(id)))
        installHoldSeam()

        let flush = Task { await queue.flushNow() }
        let entered = await waitForSeam()
        XCTAssertTrue(entered)
        signIn(ownerB)
        seamProceed = true
        await flush.value

        XCTAssertEqual(QueueStubServer.count(key("POST", id)), 0, "nothing was sent")
        XCTAssertFalse(QueueStubServer.subjects.contains(ownerB), "and nothing as the new identity")
        XCTAssertEqual(queue.items.first(where: { $0.id == id })?.op, .publish, "A's publish is held, not lost")
        signIn(ownerA)
    }

    /// Not superseded: admission changes nothing. A payload with no session sends
    /// the row POST and the metadata PATCH, and is acknowledged.
    func testNotSuperseded_UnchangedSequenceAndAcknowledged() async throws {
        let id = UUID()
        XCTAssertTrue(queue.enqueue(publish(id)))
        let start = QueueStubServer.arrivals.count

        await queue.flushNow()

        XCTAssertEqual(Array(QueueStubServer.arrivals.dropFirst(start)), [key("POST", id), key("PATCH", id)])
        XCTAssertTrue(QueueStubServer.hasRow(id))
        XCTAssertFalse(queue.items.contains { $0.id == id }, "acknowledged")
    }

    // MARK: - S2b is NOT all-phase cancellation (the orphan counterexample)

    /// Superseded AFTER admission, while the OBJECT UPLOAD is in flight: the publish
    /// still completes and attaches the object in its refs, and the withdrawal that
    /// runs here then issues the row and object deletes.
    ///
    /// Had the publish been cancelled mid-upload instead, the refs would not have
    /// named the object, and the withdrawal would have issued no delete for it.
    /// That is why S2b stops at admission.
    ///
    /// Scored on OBSERVED REQUEST ORDER, not on transient row state: the same flush
    /// can process the queued withdrawal immediately. A stub DELETE proves the
    /// request was issued, not that bytes are gone.
    func testSupersededMidUpload_CompletesAndTheWithdrawalRunHereRemovesRowAndObject() async throws {
        let f = try sessionWithImage()
        XCTAssertTrue(queue.enqueue(publish(f.session, sessionID: f.session)))
        let objectKey = QueueStubServer.objectKey("POST", f.objectName)
        QueueStubServer.hold(objectKey)

        let flush = Task { await queue.flushNow() }
        let uploading = await QueueStubFixture.poll(timeout: 5) { QueueStubServer.count(objectKey) == 1 }
        XCTAssertTrue(uploading, "setup: the object upload is in flight")
        XCTAssertTrue(queue.enqueue(unshare(f.session)), "the member withdraws mid-upload")
        QueueStubServer.release(objectKey)
        await flush.value

        await QueueStubFixture.drain(queue, f.session)

        let order = QueueStubServer.arrivals
        let objectPost = try XCTUnwrap(order.firstIndex(of: objectKey), "the object was uploaded")
        let refs = try XCTUnwrap(order.firstIndex(of: key("REFS", f.session)), "the publish attached its refs")
        let rowDelete = try XCTUnwrap(order.firstIndex(of: key("DELETE", f.session)), "the withdrawal deleted the row")
        let objectDelete = try XCTUnwrap(order.firstIndex(of: QueueStubServer.objectKey("DELETE", f.objectName)),
                                         "and issued a delete for the object its refs named")
        XCTAssertLessThan(objectPost, refs, "upload, then refs: the publish completed after supersession")
        XCTAssertLessThan(refs, objectDelete, "refs were attached before the withdrawal's object delete")
        XCTAssertLessThan(objectDelete, rowDelete, "objects before the row, as the withdrawal sequence requires")
        XCTAssertFalse(QueueStubServer.hasRow(f.session))
    }

    // MARK: - The simulated service honours admission

    func testSimulatedService_RefusesWhenNotAdmitted() async throws {
        setBackendMode(.localSimulation)
        defer { setBackendMode(.backendConnected) }
        let service = BackendEnvironment.shared.publish
        XCTAssertTrue(service is SimulatedPublishService)
        let binding = try XCTUnwrap(queue.journalDeleteBinding(capturedOwner: ownerA))

        let refused = await service.uploadPost(publish(UUID()), binding: binding, admission: { false })
        guard case .failure(let error) = refused else { return XCTFail("must not invent success: \(refused)") }
        XCTAssertEqual(error as? PublishAdmissionError, .supersededBeforeFirstSend)

        let admitted = await service.uploadPost(publish(UUID()), binding: binding, admission: { true })
        guard case .success = admitted else { return XCTFail("admitted: simulated semantics unchanged") }
    }
}
