//
//  P6I02BoundTransportTests.swift
//  MOTIVOTests
//
//  P6-I-02, Unit 2b — IDENTITY-BOUND TRANSPORT, EXECUTED.
//
//  Every queued request goes out AS the identity that owns the work, or not at
//  all. These cases drive the real `SessionSyncQueue`, the real
//  `HTTPBackendPublishService` and the real `NetworkManager.boundRequest`
//  against the held `QueueStubServer`, which records the `sub` and `jti` of the
//  bearer each request actually carried.
//
//  NO NETWORK AND NO BACKEND. Tokens are unsigned synthetic JWTs for synthetic
//  uids; attachments are synthetic files in the test host's own container. The
//  global `onAuthChallenge` is replaced for every case, so the app's real
//  session refresh is never reached.
//
//  WHAT IS NOT TESTED HERE, AND WHY: a cancellation of the QUEUE'S flush. The
//  flush runs in an unstructured Task that nothing cancels, so cancellation is
//  exercised at the service and transport level, where it can happen.
//

import XCTest
import CoreData
@testable import Etudes

@MainActor
final class P6I02BoundTransportTests: XCTestCase {

    private var queue: SessionSyncQueue { SessionSyncQueue.shared }
    private let ownerA = QueueStubFixture.ownerUID
    private let ownerB = "00000000-0000-0000-0000-0000000c8702"

    private var savedChallenge: (() async -> Bool)?
    private var challengeCalls = 0
    /// What the refresh "does". Default: refreshes nothing and reports failure.
    private var onChallenge: () async -> Bool = { false }

    private var scratchFiles: [URL] = []
    private var coreDataObjects: [NSManagedObject] = []
    private var privacyKeys: [(UUID, URL)] = []

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        QueueStubFixture.connect()
        try LocalStackSupport.requireRealBackend(baseURL: QueueStubServer.baseURL.absoluteString)
        queue.clear()
        signIn(ownerA, jti: "A1")
        savedChallenge = NetworkManager.shared.onAuthChallenge
        challengeCalls = 0
        onChallenge = { false }
        NetworkManager.shared.onAuthChallenge = { [weak self] in
            guard let self else { return false }
            self.challengeCalls += 1
            return await self.onChallenge()
        }
    }

    override func tearDown() async throws {
        QueueStubFixture.attachTimeline(to: self)
        QueueStubServer.releaseAll()
        NetworkManager.shared.onAuthChallenge = savedChallenge
        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil
        if !queue.reconcileState.isOK {
            try? FileManager.default.removeItem(at: SessionSyncQueue.currentFileURL())
            _ = queue.attemptStoreRecovery()
        }
        queue.clear()
        let ctx = PersistenceController.shared.container.viewContext
        for o in coreDataObjects where !o.isDeleted { ctx.delete(o) }
        try? ctx.save()
        for url in scratchFiles { try? FileManager.default.removeItem(at: url) }
        for (id, url) in privacyKeys { AttachmentPrivacy.setPrivate(id: id, url: url, false) }
        QueueStubFixture.disconnect()
        try await super.tearDown()
    }

    // MARK: - Fixture

    /// A sign-in changes the token AND the recorded identity, and starts a new
    /// queue generation — as the app does.
    private func signIn(_ uid: String, jti: String) {
        NetworkManager.shared.setBearerToken(QueueStubFixture.token(sub: uid, jti: jti))
        UserDefaults.standard.set(uid, forKey: "supabaseUserID_v1")
        queue.noteIdentityChanged(reason: "test:identity→\(uid.suffix(4))")
    }

    /// A token rotation for the SAME owner: no identity change, no new generation.
    private func rotate(to jti: String, sub: String? = nil) {
        NetworkManager.shared.setBearerToken(QueueStubFixture.token(sub: sub ?? ownerA, jti: jti))
    }

    private func key(_ op: String, _ id: UUID) -> String { QueueStubServer.key(op, id) }

    /// A publish payload owned by A. With `session`, a real Session and one
    /// included JPEG exist, so the publish has an upload phase and a refs phase.
    private func publishPayload(_ id: UUID, session: Bool = false) throws -> SessionSyncQueue.PostPublishPayload {
        if session { try makeSessionWithIncludedJPEG(id) }
        return SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: session ? id : nil, sessionTimestamp: nil, title: "2b",
            durationSeconds: 60, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil, isPublic: true
        ).withOwner(ownerA)
    }

    private func unsharePayload(_ id: UUID) -> SessionSyncQueue.PostPublishPayload {
        SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: nil, sessionTimestamp: nil, title: nil,
            durationSeconds: nil, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil, isPublic: false
        ).withOwner(ownerA)
    }

    private var attachmentID: UUID?

    private func makeSessionWithIncludedJPEG(_ sessionID: UUID) throws {
        let ctx = PersistenceController.shared.container.viewContext
        let session = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        session.setValue(sessionID, forKey: "id")
        session.setValue(Date(), forKey: "timestamp")
        session.setValue("2b fixture", forKey: "title")
        session.setValue(Int64(60), forKey: "durationSeconds")
        session.setValue(Int16(0), forKey: "activityType")
        session.setValue(false, forKey: "areNotesPrivate")
        session.setValue(Int16(5), forKey: "effort")
        session.setValue(Int16(5), forKey: "mood")
        session.setValue(true, forKey: "isPublic")

        let jpeg = Data(base64Encoded: "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==")!
        let attID = UUID()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docs.appendingPathComponent("\(attID.uuidString).jpg")
        try jpeg.write(to: fileURL)
        scratchFiles.append(fileURL)

        let att = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: ctx)
        att.setValue(attID, forKey: "id")
        att.setValue(fileURL.path, forKey: "fileURL")
        att.setValue(AttachmentKind.image.rawValue, forKey: "kind")
        att.setValue(Date(), forKey: "createdAt")
        att.setValue(false, forKey: "isThumbnail")
        att.setValue(session, forKey: "session")
        try ctx.obtainPermanentIDs(for: [session, att])
        try ctx.save()
        coreDataObjects.append(contentsOf: [att, session])
        AttachmentPrivacy.setPrivate(id: attID, url: fileURL, false)
        privacyKeys.append((attID, fileURL))
        attachmentID = attID
    }

    private var uploadKey: String { QueueStubServer.objectKey("POST", "\(attachmentID!.uuidString).jpg") }

    /// Flush, with `held` held in flight; returns once it has arrived.
    private func flushHolding(_ held: String) async throws -> Task<Void, Never> {
        QueueStubServer.hold(held)
        let flush = Task { await self.queue.flushNow() }
        guard await QueueStubFixture.poll(timeout: 5, { QueueStubServer.count(held) >= 1 }) else {
            QueueStubServer.releaseAll()
            await flush.value
            throw QueueStubFixture.SetupNotEstablished(description: "setup: \(held) never arrived. \(QueueStubServer.log)")
        }
        QueueStubServer.mark("setup: \(held) held")
        return flush
    }

    private var sentAsB: Bool { QueueStubServer.subjects.contains(ownerB) }

    private func heldForA(_ id: UUID) -> Bool {
        queue.items.contains { $0.id == id && $0.ownerUserID == ownerA }
    }

    // MARK: - B1, B2 · refresh must never run for, or retry under, a replacement identity

    /// A's request is in flight, B signs in, then A's request answers 401. The
    /// refresh must NOT run — it would refresh B's session on behalf of A's work.
    func testB1_A401AfterBSignedIn_DoesNotRefreshB() async throws {
        let id = UUID()
        queue.enqueue(try publishPayload(id))
        let flush = try await flushHolding(key("POST", id))

        QueueStubServer.mark("B signs in; A's POST will answer 401")
        signIn(ownerB, jti: "B1")
        QueueStubServer.respond(key("POST", id), with: 401)
        QueueStubServer.release(key("POST", id))
        await flush.value

        XCTAssertEqual(challengeCalls, 0, "the refresh must not run for the identity that replaced A")
        XCTAssertEqual(QueueStubServer.count(key("POST", id)), 1, "no retry")
        XCTAssertFalse(sentAsB, "nothing was ever sent as B")
        XCTAssertTrue(heldForA(id), "held for A, not acknowledged")
    }

    /// A→B→A during the refresh. The subject that comes back is A again, but the
    /// operation belongs to an earlier generation and must not retry.
    func testB2_ABADuringRefresh_FailsOnGenerationEvenThoughSubjectIsA() async throws {
        let id = UUID()
        queue.enqueue(try publishPayload(id))
        QueueStubServer.respond(key("PATCH", id), with: 401)
        onChallenge = { [unowned self] in
            self.signIn(self.ownerB, jti: "B1")
            self.signIn(self.ownerA, jti: "A2")
            return true
        }
        await queue.flushNow()

        XCTAssertEqual(challengeCalls, 1)
        XCTAssertEqual(QueueStubServer.count(key("PATCH", id)), 1, "no retry for a superseded operation")
        XCTAssertTrue(heldForA(id), "held, not acknowledged")
    }

    // MARK: - B3–B7 · the existing refresh policy, bound

    func testB3_401ThenSameOwnerRefresh_RetriesOnceWithTheNewToken() async throws {
        let id = UUID()
        queue.enqueue(try publishPayload(id))
        QueueStubServer.respond(key("PATCH", id), with: 401)
        onChallenge = { [unowned self] in self.rotate(to: "A2"); return true }
        await queue.flushNow()

        XCTAssertEqual(challengeCalls, 1)
        XCTAssertEqual(QueueStubServer.jtis(for: key("PATCH", id)), ["A1", "A2"],
                       "exactly one retry, carrying the refreshed token")
        XCTAssertFalse(queue.items.contains { $0.id == id }, "completed and acknowledged")
    }

    /// The refresh leaves somebody else's token in place WITHOUT an identity
    /// change being recorded — the subject check, not the generation, must stop it.
    func testB4_401ThenRefreshYieldsOtherSubject_NoRetryAndNothingCleared() async throws {
        let id = UUID()
        queue.enqueue(try publishPayload(id))
        QueueStubServer.respond(key("PATCH", id), with: 401)
        onChallenge = { [unowned self] in self.rotate(to: "B1", sub: self.ownerB); return true }
        await queue.flushNow()

        XCTAssertEqual(challengeCalls, 1)
        XCTAssertEqual(QueueStubServer.count(key("PATCH", id)), 1, "no retry under another subject")
        XCTAssertFalse(sentAsB)
        XCTAssertTrue(heldForA(id))
        XCTAssertNotNil(NetworkManager.shared.credential(for: ownerB),
                        "the transport cleared nothing: the token the refresh left is still held")
        XCTAssertEqual(SessionSyncQueue.currentOwner(), ownerA, "and adopted no identity")
    }

    func testB5_RefreshReturnsFalse_NoRetryAndTheGenuine401IsReturned() async throws {
        let id = UUID()
        let binding = try XCTUnwrap(OperationBinding(expectedOwner: ownerA, isStillCurrent: { true }))
        QueueStubServer.respond(key("GET", id), with: 401)
        onChallenge = { false }

        let result = await NetworkManager.shared.boundRequest(
            path: "rest/v1/posts?id=eq.\(id.uuidString)", method: "GET", binding: binding)

        XCTAssertEqual(challengeCalls, 1)
        XCTAssertEqual(QueueStubServer.count(key("GET", id)), 1, "no retry")
        guard case .failure(let error) = result,
              case .httpError(401, _)? = error as? NetworkManager.NetworkError else {
            return XCTFail("a genuine unchanged-owner 401 is returned as the 401: \(result)")
        }
    }

    /// Refresh returns false AND the gate has meanwhile failed: that is a STALE
    /// operation, reported as such — not the genuine 401. Neither retries.
    func testB5b_RefreshReturnsFalseAfterGateFailed_IsIdentityChangedNot401() async throws {
        let id = UUID()
        var open = true
        let binding = try XCTUnwrap(OperationBinding(expectedOwner: ownerA, isStillCurrent: { open }))
        QueueStubServer.respond(key("GET", id), with: 401)
        onChallenge = { open = false; return false }

        let result = await NetworkManager.shared.boundRequest(
            path: "rest/v1/posts?id=eq.\(id.uuidString)", method: "GET", binding: binding)

        XCTAssertEqual(QueueStubServer.count(key("GET", id)), 1)
        guard case .failure(let error) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(error as? TransportIdentityError, .identityChanged)
    }

    func testB6_SecondConsecutive401_NoSecondRefresh() async throws {
        let id = UUID()
        queue.enqueue(try publishPayload(id))
        QueueStubServer.respond(key("PATCH", id), with: 401)
        QueueStubServer.respond(key("PATCH", id), with: 401)
        onChallenge = { [unowned self] in self.rotate(to: "A2"); return true }
        await queue.flushNow()

        XCTAssertEqual(challengeCalls, 1, "one refresh per request, never two")
        XCTAssertEqual(QueueStubServer.count(key("PATCH", id)), 2, "one retry, then give up")
        XCTAssertTrue(heldForA(id))
    }

    func testB7_403_NeverRefreshes() async throws {
        let id = UUID()
        queue.enqueue(try publishPayload(id))
        QueueStubServer.respond(key("PATCH", id), with: 403)
        onChallenge = { [unowned self] in self.rotate(to: "A2"); return true }
        await queue.flushNow()

        XCTAssertEqual(challengeCalls, 0, "an authorisation denial is not an authentication failure (C-57)")
        XCTAssertEqual(QueueStubServer.count(key("PATCH", id)), 1)
        XCTAssertTrue(heldForA(id))
    }

    // MARK: - B8 · per-request credentials

    /// A same-owner rotation while P2 is in flight is used by the NEXT phase.
    func testB8_SameOwnerRotationMidOperation_IsUsedByTheNextPhase() async throws {
        let id = UUID()
        queue.enqueue(try publishPayload(id))
        let flush = try await flushHolding(key("POST", id))
        rotate(to: "A2")
        QueueStubServer.release(key("POST", id))
        await flush.value

        XCTAssertEqual(QueueStubServer.jtis(for: key("POST", id)), ["A1"])
        XCTAssertEqual(QueueStubServer.jtis(for: key("PATCH", id)), ["A2"],
                       "each request takes a fresh credential for the owner; the operation's token is not pinned")
        XCTAssertFalse(queue.items.contains { $0.id == id })
    }

    // MARK: - B9 · A→B at each PUBLISH phase

    private func assertPublishStops(heldAt phase: (UUID) -> String, laterPhases: (UUID) -> [String],
                                    file: StaticString = #filePath, line: UInt = #line) async throws {
        let id = UUID()
        queue.enqueue(try publishPayload(id, session: true))
        let flush = try await flushHolding(phase(id))
        QueueStubServer.mark("B signs in while \(phase(id)) is in flight")
        signIn(ownerB, jti: "B1")
        QueueStubServer.release(phase(id))
        await flush.value

        for later in laterPhases(id) {
            XCTAssertEqual(QueueStubServer.count(later), 0, "\(later) must not be sent after the identity changed",
                           file: file, line: line)
        }
        XCTAssertFalse(sentAsB, "nothing sent as B", file: file, line: line)
        XCTAssertTrue(heldForA(id), "held for A, not acknowledged", file: file, line: line)
    }

    func testB9a_SwitchDuringRowCreate_StopsMetadataUploadAndRefs() async throws {
        try await assertPublishStops(heldAt: { self.key("POST", $0) },
                                     laterPhases: { [self.key("PATCH", $0), self.uploadKey, self.key("REFS", $0)] })
    }

    func testB9b_SwitchDuringMetadata_StopsUploadAndRefs() async throws {
        try await assertPublishStops(heldAt: { self.key("PATCH", $0) },
                                     laterPhases: { [self.uploadKey, self.key("REFS", $0)] })
    }

    func testB9c_SwitchDuringUpload_StopsRefs() async throws {
        let id = UUID()
        queue.enqueue(try publishPayload(id, session: true))
        let flush = try await flushHolding(uploadKey)
        signIn(ownerB, jti: "B1")
        QueueStubServer.release(uploadKey)
        await flush.value

        XCTAssertEqual(QueueStubServer.count(key("REFS", id)), 0)
        XCTAssertFalse(sentAsB)
        XCTAssertTrue(heldForA(id))
    }

    /// FINAL-RESPONSE SCHEDULE. The last request succeeds, but the identity
    /// changed while it was in flight: success is returned, yet nothing is ACKed.
    func testB9d_SwitchDuringFinalRefsPatch_SucceedsButIsNotAcknowledged() async throws {
        try await assertPublishStops(heldAt: { self.key("REFS", $0) }, laterPhases: { _ in [] })
        XCTAssertTrue(QueueStubServer.arrivals.contains { $0.hasPrefix("REFS ") }, "fixture: the final phase was sent")
    }

    /// A→B→A while P2 is in flight. The token is A's again and the recorded
    /// identity is A again, so neither the subject check nor the owner check can
    /// stop the next phase — ONLY the generation in the gate can. It must.
    func testB9e_ABABetweenPhases_OnlyTheGenerationStopsTheNextPhase() async throws {
        let id = UUID()
        queue.enqueue(try publishPayload(id))
        let flush = try await flushHolding(key("POST", id))
        signIn(ownerB, jti: "B1")
        signIn(ownerA, jti: "A2")
        QueueStubServer.release(key("POST", id))
        await flush.value

        XCTAssertEqual(QueueStubServer.jtis(for: key("PATCH", id)).filter { $0 == "A2" }.count, 0,
                       "the superseded operation must not continue under the returning identity")
        XCTAssertTrue(heldForA(id), "held for A's NEW generation to send")
    }

    // MARK: - B10 · A→B at each UNSHARE phase

    private func assertUnshareStops(heldAt phase: (UUID) -> String, laterPhases: (UUID) -> [String],
                                    file: StaticString = #filePath, line: UInt = #line) async throws {
        let id = UUID()
        QueueStubServer.seedRow(id, objectPaths: ["users/\(ownerA)/\(id.uuidString)/o1.jpg"])
        queue.enqueue(unsharePayload(id))
        let flush = try await flushHolding(phase(id))
        signIn(ownerB, jti: "B1")
        QueueStubServer.release(phase(id))
        await flush.value

        for later in laterPhases(id) {
            XCTAssertEqual(QueueStubServer.count(later), 0, "\(later) must not be sent", file: file, line: line)
        }
        XCTAssertFalse(sentAsB, file: file, line: line)
        XCTAssertTrue(heldForA(id), file: file, line: line)
    }

    private var objectDelete: String { QueueStubServer.objectKey("DELETE", "o1.jpg") }

    func testB10a_SwitchDuringDemote_StopsRefsReadAndDeletes() async throws {
        try await assertUnshareStops(heldAt: { self.key("DEMOTE", $0) },
                                     laterPhases: { [self.key("GET", $0), self.objectDelete, self.key("DELETE", $0)] })
    }

    func testB10b_SwitchDuringRefsRead_StopsObjectAndRowDelete() async throws {
        try await assertUnshareStops(heldAt: { self.key("GET", $0) },
                                     laterPhases: { [self.objectDelete, self.key("DELETE", $0)] })
    }

    func testB10c_SwitchDuringObjectDelete_StopsRowDelete() async throws {
        try await assertUnshareStops(heldAt: { _ in self.objectDelete }, laterPhases: { [self.key("DELETE", $0)] })
    }

    func testB10d_SwitchDuringFinalRowDelete_IsNotAcknowledged() async throws {
        try await assertUnshareStops(heldAt: { self.key("DELETE", $0) }, laterPhases: { _ in [] })
    }

    // MARK: - B11 · a storage delete is never read as "already absent" on an identity refusal

    func testB11_401OnObjectDeleteThenOtherSubject_NoRetryNoRowDeleteNotAbsent() async throws {
        let id = UUID()
        QueueStubServer.seedRow(id, objectPaths: ["users/\(ownerA)/\(id.uuidString)/o1.jpg"])
        queue.enqueue(unsharePayload(id))
        QueueStubServer.respond(objectDelete, with: 401)
        onChallenge = { [unowned self] in self.rotate(to: "B1", sub: self.ownerB); return true }
        await queue.flushNow()

        XCTAssertEqual(QueueStubServer.count(objectDelete), 1, "no retry")
        XCTAssertEqual(QueueStubServer.count(key("DELETE", id)), 0,
                       "an identity refusal was NOT taken as 'already gone' — the row delete never ran")
        XCTAssertTrue(heldForA(id))
    }

    // MARK: - B12 · final-response HALT

    /// The store latches while the last request is in flight. The request
    /// succeeds; the acknowledgement must still be refused.
    func testB12_StoreLatchesDuringFinalRequest_IsNotAcknowledged() async throws {
        let id = UUID()
        queue.enqueue(try publishPayload(id))
        let flush = try await flushHolding(key("PATCH", id))

        let file = SessionSyncQueue.currentFileURL()
        let older = try Data(contentsOf: file)
        SessionSyncQueueStore.unitTestCorruptAfterWrite = { try? older.write(to: file, options: .atomic) }
        queue.enqueue(try publishPayload(UUID()))   // its persist fails → the store latches
        SessionSyncQueueStore.unitTestCorruptAfterWrite = nil
        XCTAssertFalse(queue.reconcileState.isOK, "fixture: latched while the final request is in flight")

        QueueStubServer.release(key("PATCH", id))
        await flush.value

        XCTAssertTrue(queue.items.contains { $0.id == id }, "a success through a latched store is not acknowledged")
    }

    // MARK: - B13, B14 · first send: the TOKEN'S subject, not the recorded identity

    func testB13_RecordedIdentityIsAButTokenIsB_NothingSent() async throws {
        let id = UUID()
        queue.enqueue(try publishPayload(id))
        rotate(to: "B1", sub: ownerB)      // defaults still say A
        await queue.flushNow()

        XCTAssertTrue(QueueStubServer.arrivals.isEmpty, "zero requests: \(QueueStubServer.arrivals)")
        XCTAssertTrue(heldForA(id))
    }

    func testB14_AbsentMalformedOrNonUUIDSubject_NothingSent() async throws {
        let id = UUID()
        queue.enqueue(try publishPayload(id))
        let tokens: [String?] = [nil, "not-a-jwt", QueueStubFixture.token(sub: "not-a-uuid", jti: "X")]
        for token in tokens {
            NetworkManager.shared.setBearerToken(token)
            await queue.flushNow()
        }
        XCTAssertTrue(QueueStubServer.arrivals.isEmpty, "zero requests: \(QueueStubServer.arrivals)")
        XCTAssertTrue(heldForA(id))
    }

    /// FIRST-SEND HALT: the gate is already closed at the first send.
    func testB14b_GateClosedAtFirstSend_NothingSent() async throws {
        let binding = try XCTUnwrap(OperationBinding(expectedOwner: ownerA, isStillCurrent: { false }))
        let result = await NetworkManager.shared.boundRequest(path: "rest/v1/posts?id=eq.\(UUID().uuidString)",
                                                              method: "GET", binding: binding)
        guard case .failure(let error) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(error as? TransportIdentityError, .identityChanged)
        XCTAssertTrue(QueueStubServer.arrivals.isEmpty)
    }

    // MARK: - B15, B16 · what a bound request names

    /// NOT DISCRIMINATING, AND STATED SO. The gate requires the recorded identity
    /// to equal the expected owner at every send, so a live read and the binding
    /// cannot differ while a request is sent. This pins the values; it cannot
    /// distinguish where they came from.
    func testB15_RowOwnerAndStoragePathAreTheExpectedOwner() async throws {
        let id = UUID()
        queue.enqueue(try publishPayload(id, session: true))
        await queue.flushNow()

        XCTAssertEqual(QueueStubServer.rowOwner(id), ownerA)
        let upload = QueueStubServer.allURLs.first { $0.key == uploadKey }
        XCTAssertTrue(upload?.url.contains("/users/\(ownerA)/") == true, "\(String(describing: upload))")
    }

    func testB16_EveryBoundPostsRequestIsOwnerFiltered() async throws {
        let published = UUID(), withdrawn = UUID()
        queue.enqueue(try publishPayload(published, session: true))
        QueueStubServer.seedRow(withdrawn, objectPaths: ["users/\(ownerA)/\(withdrawn.uuidString)/o1.jpg"])
        queue.enqueue(unsharePayload(withdrawn))
        await queue.flushNow()

        let postsRequests = QueueStubServer.allURLs.filter {
            $0.url.contains("/rest/v1/posts") && !$0.key.hasPrefix("POST ")
        }
        XCTAssertFalse(postsRequests.isEmpty, "fixture: bound posts requests were made")
        for r in postsRequests {
            XCTAssertTrue(r.url.contains("owner_user_id=eq.\(ownerA)"), "unfiltered: \(r.key) \(r.url)")
        }
    }

    // MARK: - B17 · a custom Authorization header is refused

    func testB17_CustomAuthorizationHeaderIsRefusedInAnyCase() async throws {
        let binding = try XCTUnwrap(OperationBinding(expectedOwner: ownerA, isStillCurrent: { true }))
        for name in ["Authorization", "authorization", "AUTHORIZATION"] {
            let result = await NetworkManager.shared.boundRequest(
                path: "rest/v1/posts?id=eq.\(UUID().uuidString)", method: "GET",
                headers: [name: "Bearer someone-else"], binding: binding)
            guard case .failure(let error) = result else { return XCTFail("\(name): \(result)") }
            XCTAssertEqual(error as? TransportIdentityError, .authorizationHeaderOverride, name)
        }
        XCTAssertTrue(QueueStubServer.arrivals.isEmpty)
    }

    func testB17b_BindingRejectsAnOwnerThatIsNotABackendIdentity() {
        XCTAssertNil(OperationBinding(expectedOwner: nil, isStillCurrent: { true }))
        XCTAssertNil(OperationBinding(expectedOwner: "   ", isStillCurrent: { true }))
        XCTAssertNil(OperationBinding(expectedOwner: "not-a-uuid", isStillCurrent: { true }))
        XCTAssertEqual(OperationBinding(expectedOwner: "  \(ownerA.uppercased()) ", isStillCurrent: { true })?.expectedOwner,
                       ownerA, "normalised once, at creation")
    }

    // MARK: - B19 · the direct-delete path is unchanged

    func testB19_AmbientDeletePostIsUnbound() async throws {
        let id = UUID()
        QueueStubServer.seedRow(id, objectPaths: [])
        NetworkManager.shared.setBearerToken("stub-bearer")   // no subject at all
        let result = await BackendEnvironment.shared.publish.deletePost(id)

        guard case .success = result else { return XCTFail("ambient delete must still succeed: \(result)") }
        XCTAssertEqual(QueueStubServer.count(key("GET", id)), 1)
        XCTAssertEqual(QueueStubServer.count(key("DELETE", id)), 1)
        for r in QueueStubServer.allURLs {
            XCTAssertFalse(r.url.contains("owner_user_id"), "the direct path gained a filter: \(r.url)")
        }
    }

    // MARK: - Cancellation

    /// Cancelled before it runs: nothing is sent, and nothing refreshes.
    func testC1_CancelledBeforeDispatch_SendsNothing() async throws {
        let binding = try XCTUnwrap(OperationBinding(expectedOwner: ownerA, isStillCurrent: { true }))
        let id = UUID()
        let task = Task { @MainActor in
            await NetworkManager.shared.boundRequest(path: "rest/v1/posts?id=eq.\(id.uuidString)",
                                                     method: "GET", binding: binding)
        }
        task.cancel()
        let result = await task.value

        guard case .failure(let error) = result else { return XCTFail("\(result)") }
        XCTAssertTrue(error is CancellationError, "\(error)")
        XCTAssertTrue(QueueStubServer.arrivals.isEmpty, "\(QueueStubServer.arrivals)")
    }

    /// Cancelled while the row create is held: the request is abandoned, no
    /// later phase is sent, no refresh runs although that request would have
    /// answered 401. Cancelling stops waiting; it does not undo server work.
    func testC2_CancelledWhileHeld_AbandonsAndSendsNoLaterPhase() async throws {
        let id = UUID()
        let payload = try publishPayload(id, session: true)
        let binding = try XCTUnwrap(OperationBinding(expectedOwner: ownerA, isStillCurrent: { true }))
        QueueStubServer.hold(key("POST", id))
        QueueStubServer.respond(key("POST", id), with: 401)
        let task = Task { @MainActor in
            await BackendEnvironment.shared.publish.uploadPost(payload, binding: binding)
        }
        guard await QueueStubFixture.poll(timeout: 5, { QueueStubServer.count(self.key("POST", id)) == 1 }) else {
            return XCTFail("setup: POST never arrived")
        }
        task.cancel()
        let result = await task.value

        guard case .failure(let error) = result else { return XCTFail("\(result)") }
        XCTAssertTrue(error is CancellationError, "\(error)")
        let abandoned = await QueueStubFixture.poll(timeout: 2, { QueueStubServer.abandoned(self.key("POST", id)) })
        XCTAssertTrue(abandoned, "the stub observed stopLoading before responding")
        XCTAssertEqual(challengeCalls, 0, "a cancelled request never reaches the refresh")
        for later in [key("PATCH", id), uploadKey, key("REFS", id)] {
            XCTAssertEqual(QueueStubServer.count(later), 0, "\(later) sent after cancellation")
        }
    }

    /// Cancelled while the refresh is running: no retry.
    func testC3_CancelledDuringRefresh_DoesNotRetry() async throws {
        let id = UUID()
        let binding = try XCTUnwrap(OperationBinding(expectedOwner: ownerA, isStillCurrent: { true }))
        QueueStubServer.respond(key("GET", id), with: 401)
        var releaseRefresh = false
        onChallenge = { [unowned self] in
            _ = await QueueStubFixture.poll(timeout: 5) { releaseRefresh }
            self.rotate(to: "A2")
            return true
        }
        let task = Task { @MainActor in
            await NetworkManager.shared.boundRequest(path: "rest/v1/posts?id=eq.\(id.uuidString)",
                                                     method: "GET", binding: binding)
        }
        guard await QueueStubFixture.poll(timeout: 5, { self.challengeCalls == 1 }) else {
            return XCTFail("setup: the refresh never started")
        }
        task.cancel()
        releaseRefresh = true
        let result = await task.value

        guard case .failure(let error) = result else { return XCTFail("\(result)") }
        XCTAssertTrue(error is CancellationError, "\(error)")
        XCTAssertEqual(QueueStubServer.count(key("GET", id)), 1, "no retry after cancellation")
    }

    // MARK: - Persistence

    /// PROVED ONLY FOR THE QUEUE FILE. A distinctive token is used and the file
    /// is searched for it. This is not a proof about logging (see the report).
    func testTokenIsNeverWrittenToTheQueueFile() async throws {
        let marker = "TOKEN-MARKER-\(UUID().uuidString)"
        rotate(to: marker)
        let id = UUID()
        queue.enqueue(try publishPayload(id))
        QueueStubServer.fail(key("PATCH", id))          // keeps the item queued after a send
        await queue.flushNow()

        let bytes = try Data(contentsOf: SessionSyncQueue.currentFileURL())
        let text = String(decoding: bytes, as: UTF8.self)
        let token = QueueStubFixture.token(sub: ownerA, jti: marker)
        XCTAssertTrue(queue.items.contains { $0.id == id }, "fixture: the item is still persisted")
        XCTAssertFalse(text.contains(marker), "the jti marker reached the queue file")
        XCTAssertFalse(text.contains(token), "the token reached the queue file")
        XCTAssertFalse(String(describing: NetworkManager.shared.credential(for: ownerA)!).contains(token))
    }
}
