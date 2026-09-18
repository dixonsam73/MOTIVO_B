//
//  P6I02WithdrawalOutcomeTests.swift
//  MOTIVOTests
//
//  P6-I-02, Unit 2c — WITHDRAWAL OUTCOMES, AS THEY ARE.
//
//  A bound withdrawal now reports what it ESTABLISHED — the requested row was
//  removed, or nothing matched — after strict validation of the response. None
//  of these means "withdrawn". These cases drive the real queue and the real
//  `HTTPBackendPublishService` against the held `QueueStubServer`.
//
//  THE OPEN BLOCKER IS CHARACTERISED HERE, NOT CLOSED. The two
//  `testOPENBLOCKER_…` cases reproduce a late publish recreating a post after its
//  withdrawal was acknowledged. They PASS WHILE THE BLOCKER REPRODUCES and must
//  never be cited as evidence of safety.
//
//  NO NETWORK AND NO BACKEND. Synthetic uids, unsigned synthetic tokens.
//

import XCTest
@testable import Etudes

@MainActor
final class P6I02WithdrawalOutcomeTests: XCTestCase {

    private var queue: SessionSyncQueue { SessionSyncQueue.shared }
    private let ownerA = QueueStubFixture.ownerUID

    override func setUp() async throws {
        try await super.setUp()
        QueueStubFixture.connect()
        try LocalStackSupport.requireRealBackend(baseURL: QueueStubServer.baseURL.absoluteString)
        queue.clear()
    }

    override func tearDown() async throws {
        QueueStubFixture.attachTimeline(to: self)
        QueueStubServer.releaseAll()
        queue.clear()
        QueueStubFixture.disconnect()
        try await super.tearDown()
    }

    private func key(_ op: String, _ id: UUID) -> String { QueueStubServer.key(op, id) }

    private func unshare(_ id: UUID) -> SessionSyncQueue.PostPublishPayload {
        SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: nil, sessionTimestamp: nil, title: nil,
            durationSeconds: nil, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil, isPublic: false
        ).withOwner(ownerA)
    }

    private func publish(_ id: UUID) -> SessionSyncQueue.PostPublishPayload {
        QueueStubFixture.payload(id, shared: true)
    }

    private func queued(_ id: UUID) -> Bool { queue.items.contains { $0.id == id } }

    // MARK: - V1–V5 · strict validation of the row DELETE

    func testV1_ExactlyTheRequestedRow_IsRowDeletedAndAcknowledged() async throws {
        let id = UUID()
        QueueStubServer.seedRow(id, objectPaths: [])
        queue.enqueue(unshare(id))
        await queue.flushNow()

        XCTAssertFalse(QueueStubServer.hasRow(id))
        XCTAssertFalse(queued(id), "acknowledged")
        let deleteURL = QueueStubServer.allURLs.first { $0.key == key("DELETE", id) }?.url ?? ""
        XCTAssertTrue(deleteURL.contains("select=id"), "the bound DELETE asks for the removed row: \(deleteURL)")
    }

    func testV2_EmptyArray_IsNoRowMatchedAndAcknowledged() async throws {
        let id = UUID()                       // never existed
        queue.enqueue(unshare(id))
        await queue.flushNow()

        XCTAssertEqual(QueueStubServer.count(key("DELETE", id)), 1)
        XCTAssertFalse(queued(id), "acknowledged, as today — and not claimed to be a withdrawal")
    }

    func testV3_AForeignRowID_IsUndeterminedAndHeld() async throws {
        let id = UUID()
        QueueStubServer.respondBody(key("DELETE", id), #"[{"id":""# + UUID().uuidString + #""}]"#)
        queue.enqueue(unshare(id))
        await queue.flushNow()
        XCTAssertTrue(queued(id), "a row that is not the requested one is not a deletion of it")
    }

    func testV4_TwoRows_IsUndeterminedAndHeld() async throws {
        let id = UUID()
        QueueStubServer.respondBody(key("DELETE", id),
                                    #"[{"id":""# + id.uuidString + #""},{"id":""# + id.uuidString + #""}]"#)
        queue.enqueue(unshare(id))
        await queue.flushNow()
        XCTAssertTrue(queued(id), "a unique-id filter cannot legitimately remove two rows")
    }

    func testV5_MalformedBodies_AreUndeterminedAndHeld() async throws {
        let bodies = ["{}", #""x""#, #"[{"no_id":1}]"#, #"[{"id":"not-a-uuid"}]"#, "not json", ""]
        for body in bodies {
            let id = UUID()
            QueueStubServer.respondBody(key("DELETE", id), body)
            queue.enqueue(unshare(id))
            await queue.flushNow()
            XCTAssertTrue(queued(id), "held for body \(body.debugDescription)")
        }
    }

    // MARK: - V6 · the demote is recorded, never decisive

    func testV6_AnyDemoteResult_TheDeleteStillRuns() async throws {
        let bodies = ["[]", #"[{"id":""# + UUID().uuidString + #""}]"#, "{}"]
        for body in bodies {
            let id = UUID()
            QueueStubServer.seedRow(id, objectPaths: [])
            QueueStubServer.respondBody(key("DEMOTE", id), body)
            queue.enqueue(unshare(id))
            await queue.flushNow()
            XCTAssertEqual(QueueStubServer.count(key("DELETE", id)), 1, "delete ran after demote body \(body)")
            XCTAssertFalse(queued(id), "and the row delete decided the outcome")
        }
    }

    // MARK: - V7 · partial progress

    func testV7_ObjectDeleteFailsAfterAnotherSucceeded_HeldWithPartialProgress() async throws {
        let id = UUID()
        QueueStubServer.seedRow(id, objectPaths: ["users/\(ownerA)/\(id.uuidString)/o1.jpg",
                                                  "users/\(ownerA)/\(id.uuidString)/o2.jpg"])
        QueueStubServer.fail(QueueStubServer.objectKey("DELETE", "o2.jpg"))
        queue.enqueue(unshare(id))
        await queue.flushNow()

        XCTAssertEqual(QueueStubServer.count(QueueStubServer.objectKey("DELETE", "o1.jpg")), 1,
                       "the first object WAS deleted — partial progress is real")
        XCTAssertEqual(QueueStubServer.count(key("DELETE", id)), 0, "the row delete did not run")
        XCTAssertTrue(queued(id), "held")
    }

    // MARK: - V8 · zero rows can follow a real deletion

    func testV8_ResponseLostAfterTheDeleteApplied_RetryMatchesNothing() async throws {
        let id = UUID()
        QueueStubServer.seedRow(id, objectPaths: [])
        QueueStubServer.dropResponseAfterApplying(key("DELETE", id))
        queue.enqueue(unshare(id))

        await queue.flushNow()
        XCTAssertFalse(QueueStubServer.hasRow(id), "the server removed the row")
        XCTAssertTrue(queued(id), "but the client never heard: held")

        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(key("DELETE", id)), 2)
        XCTAssertFalse(queued(id),
                       "the retry matched nothing and was acknowledged — a zero-row result that FOLLOWED a real deletion")
    }

    // MARK: - V9 · the direct-delete path is unchanged

    func testV9_AmbientDeletePost_KeepsMinimalAndZeroRowsIsSuccess() async throws {
        let id = UUID()                       // never existed: a never-published session
        NetworkManager.shared.setBearerToken("stub-bearer")
        let result = await BackendEnvironment.shared.publish.deletePost(id)

        guard case .success = result else {
            return XCTFail("ContentView's contract: a zero-row delete must stay success: \(result)")
        }
        for r in QueueStubServer.allURLs {
            XCTAssertFalse(r.url.contains("select=id"), "the direct path now asks for rows: \(r.url)")
        }
    }

    // MARK: - V10, V11 · the simulated service reports itself as unverified

    /// `SimulatedPublishService` is selected whenever HTTP config is absent. It
    /// sends nothing and reports `.simulatedUnverified`, which the queue
    /// acknowledges, as it did before 2c.
    func testV10_SimulatedServiceReportsSimulatedUnverified() async throws {
        let id = UUID()
        let savedBase = NetworkManager.shared.baseURL
        NetworkManager.shared.baseURL = nil
        defer { NetworkManager.shared.baseURL = savedBase }
        XCTAssertTrue(BackendEnvironment.shared.publish is SimulatedPublishService, "fixture")

        let binding = try XCTUnwrap(OperationBinding(expectedOwner: ownerA, isStillCurrent: { true }))
        let direct = await BackendEnvironment.shared.publish.unsharePost(id, binding: binding)
        XCTAssertEqual(try direct.get(), .simulatedUnverified)

        queue.enqueue(unshare(id))
        await queue.flushNow()
        XCTAssertFalse(queued(id), "acknowledged as before 2c")
        XCTAssertTrue(QueueStubServer.arrivals.isEmpty, "and nothing was sent")
    }

    /// CHARACTERISES CURRENT BEHAVIOUR — NOT A CONNECTED WITHDRAWAL PROOF, and
    /// a separately identified concern for the final scope review. In
    /// backendConnected mode with HTTP config missing, the publish service falls
    /// back to the simulated one: the withdrawal is ACKNOWLEDGED although NOTHING
    /// WAS SENT. 2c reports it truthfully and does not change it.
    func testV11_ConnectedModeWithoutHTTPConfig_FallsBackAndAcknowledgesUnsent() async throws {
        let id = UUID()
        XCTAssertEqual(BackendEnvironment.shared.mode, .backendConnected, "fixture: Connected mode")
        let savedBase = NetworkManager.shared.baseURL
        NetworkManager.shared.baseURL = nil
        defer { NetworkManager.shared.baseURL = savedBase }
        XCTAssertTrue(BackendEnvironment.shared.publish is SimulatedPublishService,
                      "CURRENT BEHAVIOUR: Connected mode falls back to the simulated service")

        queue.enqueue(unshare(id))
        await queue.flushNow()

        XCTAssertFalse(queued(id), "CURRENT BEHAVIOUR: acknowledged")
        XCTAssertTrue(QueueStubServer.arrivals.isEmpty, "although nothing was sent")
    }

    // MARK: - OPEN BLOCKER — characterisation, NOT closure evidence

    /// OPEN BLOCKER (P6-I-02 stable withdrawal). Reproduces addendum A.1 where the
    /// withdrawal MATCHES NOTHING: P is received but not yet committed, D is
    /// acknowledged, then P commits. Passes while the blocker reproduces.
    func testOPENBLOCKER_LatePublishCommitsAfterAcknowledgedNoRowMatched() async throws {
        let id = UUID()
        QueueStubServer.deferCommit(id)

        queue.enqueue(publish(id))
        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(key("POST", id)), 1, "event 1: P was sent")
        XCTAssertTrue(QueueStubServer.log.contains("\(key("POST", id)) lost"), "event 2: the client was told it failed")
        XCTAssertFalse(QueueStubServer.hasRow(id), "event 3: not yet committed")

        queue.enqueue(unshare(id))
        XCTAssertEqual(queue.items.first { $0.id == id }?.op, .unshare, "event 4: D replaced P")
        await queue.flushNow()
        XCTAssertEqual(QueueStubServer.count(key("DELETE", id)), 1, "event 5: D's DELETE was sent")
        XCTAssertFalse(queued(id), "event 6: D was ACKNOWLEDGED (noRowMatched)")

        QueueStubServer.commitDeferred(id)
        XCTAssertTrue(QueueStubServer.hasRow(id), "EXPOSED: the post exists after an acknowledged withdrawal")
        XCTAssertTrue(queue.items.isEmpty, "EXPOSED: and nothing remains to retry")
    }

    /// OPEN BLOCKER, the other case: the withdrawal DELETES a current row
    /// (rowDeleted), then an earlier unresolved publish recreates it. Shows the
    /// gap is not confined to `noRowMatched`. Passes while the blocker reproduces.
    func testOPENBLOCKER_LatePublishRecreatesAfterAcknowledgedRowDeleted() async throws {
        let id = UUID()
        queue.enqueue(publish(id))
        await queue.flushNow()
        XCTAssertTrue(QueueStubServer.hasRow(id), "event 1: an earlier publish committed")
        XCTAssertFalse(queued(id))

        QueueStubServer.deferCommit(id)
        queue.enqueue(publish(id))
        await queue.flushNow()
        XCTAssertTrue(QueueStubServer.log.contains("\(key("POST", id)) lost"), "event 2: a second publish's outcome is unknown")

        queue.enqueue(unshare(id))
        await queue.flushNow()
        XCTAssertFalse(QueueStubServer.hasRow(id), "event 3: D removed the current row (rowDeleted)")
        XCTAssertFalse(queued(id), "event 4: D was ACKNOWLEDGED")

        QueueStubServer.commitDeferred(id)
        XCTAssertTrue(QueueStubServer.hasRow(id), "EXPOSED: recreated after an acknowledged rowDeleted withdrawal")
        XCTAssertTrue(queue.items.isEmpty, "EXPOSED: and nothing remains to retry")
    }
}

/// A check on the COMMITTED SNAPSHOT (`supabase/schema/policies.json`) — the
/// artefact last captured from production. It is NOT a check on production at
/// the moment of a withdrawal, and must never be described as one.
final class P6I02PolicySnapshotTripwireTests: XCTestCase {

    private struct Policy: Decodable { let tablename: String; let policyname: String; let qual: String? }

    private func policies() throws -> [Policy] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("supabase/schema/policies.json")
        return try JSONDecoder().decode([Policy].self, from: Data(contentsOf: url))
    }

    func testSnapshot_OwnerDeleteIsUngatedAndOwnerScoped() throws {
        let delete = try XCTUnwrap(policies().first { $0.tablename == "posts" && $0.policyname == "posts_delete_owner" })
        XCTAssertEqual(delete.qual, "(owner_user_id = auth.uid())",
                       "a changed DELETE policy changes what a zero-row withdrawal can mean")
    }

    func testSnapshot_OwnerSelectDisjunctIsUngated() throws {
        let select = try XCTUnwrap(policies().first { $0.tablename == "posts" && $0.policyname == "posts_select_public_or_owner" })
        XCTAssertTrue(select.qual?.hasPrefix("((owner_user_id = auth.uid()) OR") == true,
                      "RETURNING on the owner's own row relies on this disjunct being first and ungated")
    }
}
