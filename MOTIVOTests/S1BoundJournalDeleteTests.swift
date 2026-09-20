//
//  S1BoundJournalDeleteTests.swift
//  MOTIVOTests
//
//  S1. The journal delete's DIRECT backend call must be sent as the owner captured
//  at the member's action, owner-filtered, and gated before every request — and the
//  gate must be re-checked after the last await, before any local or queue mutation.
//
//  WHAT S1 DOES NOT CHANGE: a validated empty result (`noRowMatched`) stays a
//  SUCCESS. A never-shared entry produces exactly that, and the product deletes it
//  locally. Only a malformed or mismatched response refuses. Nothing here infers
//  foreign ownership from `[]`.
//
//  SYNTHETIC ONLY: loopback stub, synthetic owners and tokens, disposable Sessions.
//

import XCTest
import CoreData
@testable import Etudes

@MainActor
final class S1BoundJournalDeleteTests: XCTestCase {
    private var queue: SessionSyncQueue { SessionSyncQueue.shared }
    private var container: NSPersistentContainer { PersistenceController.shared.container }
    private var ctx: NSManagedObjectContext { container.viewContext }
    private let ownerA = QueueStubFixture.ownerUID
    private let ownerB = "00000000-0000-0000-0000-0000000c8702"
    private var created: [UUID] = []

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
        for id in created { if let o = fetch(id) { ctx.delete(o) } }
        try? ctx.save()
        created = []
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

    private func fetch(_ id: UUID) -> NSManagedObject? {
        let r = NSFetchRequest<NSManagedObject>(entityName: "Session")
        r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        r.fetchLimit = 1
        return (try? ctx.fetch(r))?.first
    }

    private func existsInStore(_ id: UUID) -> Bool {
        let c = container.newBackgroundContext()
        var n = 0
        c.performAndWait {
            let r = NSFetchRequest<NSManagedObject>(entityName: "Session")
            r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            n = (try? c.count(for: r)) ?? 0
        }
        return n > 0
    }

    @discardableResult
    private func newSession(shared: Bool = true) throws -> UUID {
        let id = UUID()
        let s = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        s.setValue(id, forKey: "id")
        s.setValue(Date(), forKey: "timestamp")
        s.setValue("s1 fixture", forKey: "title")
        s.setValue(shared, forKey: "isPublic")
        try ctx.save()
        created.append(id)
        return id
    }

    private func localDelete(_ id: UUID) -> () -> Bool {
        let oid = fetch(id)!.objectID
        return { JournalDeleteBackendStep.deleteSessionLocally(objectID: oid) }
    }

    private func delete(_ id: UUID, capturedOwner: String?, wasShared: Bool = true) async -> JournalDeleteBackendStep.Outcome {
        await JournalDeleteBackendStep.run(postID: id, capturedOwner: capturedOwner,
                                           sessionWasShared: wasShared, deleteLocally: localDelete(id))
    }

    // MARK: - Success semantics preserved

    /// A shared post that exists: deleted, and every request is owner-filtered and
    /// sent as the captured owner.
    func testExistingPost_DeletedAndEveryRequestIsOwnerBound() async throws {
        let id = try newSession()
        QueueStubServer.seedRow(id, objectPaths: [])

        let outcome = await delete(id, capturedOwner: ownerA)
        XCTAssertEqual(outcome, .deleted)

        XCTAssertFalse(QueueStubServer.hasRow(id))
        XCTAssertFalse(existsInStore(id))
        for k in [key("GET", id), key("DELETE", id)] {
            XCTAssertEqual(QueueStubServer.subjects(for: k), [ownerA], "\(k) sent as the captured owner")
            XCTAssertTrue(QueueStubServer.allURLs.last(where: { $0.key == k })?.url
                .contains("owner_user_id=eq.\(ownerA)") == true, "\(k) is owner-filtered")
        }
    }

    /// A GENUINELY never-shared entry (`isPublic` false, and the caller says so):
    /// the owner-scoped DELETE validates `[]`, which is SUCCESS — the entry is
    /// deleted locally, exactly as before S1 — and **no withdrawal is queued**.
    /// `[]` is never read as "someone else owns it".
    func testNeverSharedEntry_EmptyResultIsSuccessAndQueuesNothing() async throws {
        let id = try newSession(shared: false)       // unshared, and no row seeded
        let before = queue.items

        let outcome = await delete(id, capturedOwner: ownerA, wasShared: false)
        XCTAssertEqual(outcome, .deleted)
        XCTAssertFalse(existsInStore(id), "local deletion still finishes")
        XCTAssertEqual(QueueStubServer.count(key("DELETE", id)), 1)
        XCTAssertEqual(queue.items, before, "no spurious withdrawal for an unshared entry")
    }

    /// A shared post WITH a referenced object: the object is deleted through the
    /// single-object route before the row, and both are gone.
    func testReferencedObject_DeletedBeforeTheRow() async throws {
        let id = try newSession()
        let object = "\(id.uuidString.lowercased()).m4a"
        QueueStubServer.seedRow(id, objectPaths: ["users/\(ownerA)/\(id.uuidString)/\(object)"])
        let start = QueueStubServer.arrivals.count

        let outcome = await delete(id, capturedOwner: ownerA)

        XCTAssertEqual(outcome, .deleted)
        let sent = Array(QueueStubServer.arrivals.dropFirst(start))
        XCTAssertEqual(sent, [key("GET", id), QueueStubServer.objectKey("DELETE", object), key("DELETE", id)],
                       "refs, then the object, then the row: \(sent)")
        XCTAssertFalse(QueueStubServer.hasRow(id))
        XCTAssertFalse(existsInStore(id))
    }

    /// A row owned by SOMEONE ELSE, with the stub enforcing the owner filter: the
    /// owner-scoped DELETE matches nothing, which is success, so the member's local
    /// entry is deleted — and the other owner's row and objects are untouched.
    func testForeignOwnedRow_LocalDeleteSucceedsAndForeignDataUntouched() async throws {
        let id = try newSession()
        let object = "\(id.uuidString.lowercased()).m4a"
        QueueStubServer.enforceOwnerFilterForTest()
        QueueStubServer.seedRow(id, objectPaths: ["users/\(ownerB)/\(id.uuidString)/\(object)"], owner: ownerB)

        let outcome = await delete(id, capturedOwner: ownerA)

        XCTAssertEqual(outcome, .deleted, "a validated [] is success, not an ownership inference")
        XCTAssertFalse(existsInStore(id), "the member's local entry is deleted")
        XCTAssertTrue(QueueStubServer.hasRow(id), "the other owner's row survives")
        XCTAssertEqual(QueueStubServer.count(QueueStubServer.objectKey("DELETE", object)), 0,
                       "no storage delete for another owner's object")
    }

    /// A malformed or mismatched 2xx body is NOT success: it refuses, and nothing
    /// local or queued changes.
    func testUndeterminedResponse_RefusesAndChangesNothing() async throws {
        let id = try newSession()
        QueueStubServer.seedRow(id, objectPaths: [])
        let before = queue.items
        QueueStubServer.respondBody(key("DELETE", id), #"[{"id":"00000000-0000-0000-0000-000000009999"}]"#)

        let outcome = await delete(id, capturedOwner: ownerA)
        XCTAssertEqual(outcome, .refused(.backendDeleteUnconfirmed))
        XCTAssertTrue(existsInStore(id), "the entry is kept")
        XCTAssertEqual(queue.items, before, "no queue write")
    }

    // MARK: - Identity gating

    /// The captured owner must be a backend identity before ANY request: a missing
    /// or malformed owner fails closed, with nothing sent.
    func testMissingCapturedOwner_FailsClosedBeforeAnyRequest() async throws {
        let id = try newSession()
        let start = QueueStubServer.arrivals.count

        let outcome = await delete(id, capturedOwner: nil)

        XCTAssertEqual(outcome, .refused(.ownerUnavailable))
        XCTAssertEqual(QueueStubServer.arrivals.count, start, "nothing sent")
        XCTAssertTrue(existsInStore(id))
    }

    /// The identity changes while the FIRST phase is held: no later phase is sent,
    /// nothing is sent as the new identity, and nothing local or queued changes.
    func testIdentitySwitchDuringRefsGet_StopsLaterPhases() async throws {
        let id = try newSession()
        QueueStubServer.seedRow(id, objectPaths: ["users/a/\(id.uuidString.lowercased()).m4a"])
        let before = queue.items
        QueueStubServer.hold(key("GET", id))

        let run = Task { await self.delete(id, capturedOwner: self.ownerA) }
        let held = await QueueStubFixture.poll(timeout: 5) { QueueStubServer.count(self.key("GET", id)) == 1 }
        XCTAssertTrue(held, "setup: the refs GET is in flight")
        signIn(ownerB)
        QueueStubServer.release(key("GET", id))
        let outcome = await run.value

        XCTAssertEqual(outcome, .refused(.backendDeleteUnconfirmed))
        XCTAssertEqual(QueueStubServer.count(key("DELETE", id)), 0, "no row DELETE")
        XCTAssertTrue(QueueStubServer.arrivals.allSatisfy { !$0.hasPrefix("DELETE OBJ") }, "no storage delete")
        XCTAssertFalse(QueueStubServer.subjects.contains(ownerB), "nothing sent as the new identity")
        XCTAssertTrue(QueueStubServer.hasRow(id))
        XCTAssertTrue(existsInStore(id))
        XCTAssertEqual(queue.items, before)
    }

    /// The identity changes while a STORAGE delete is held: the next phase (the row
    /// DELETE) is not sent.
    func testIdentitySwitchDuringStorageDelete_StopsNextPhase() async throws {
        let id = try newSession()
        let object = "\(id.uuidString.lowercased()).m4a"
        QueueStubServer.seedRow(id, objectPaths: ["users/a/\(object)"])
        QueueStubServer.hold(QueueStubServer.objectKey("DELETE", object))

        let run = Task { await self.delete(id, capturedOwner: self.ownerA) }
        let held = await QueueStubFixture.poll(timeout: 5) {
            QueueStubServer.count(QueueStubServer.objectKey("DELETE", object)) == 1
        }
        XCTAssertTrue(held, "setup: the storage delete is in flight")
        signIn(ownerB)
        QueueStubServer.release(QueueStubServer.objectKey("DELETE", object))
        let outcome = await run.value

        XCTAssertEqual(outcome, .refused(.backendDeleteUnconfirmed))
        XCTAssertEqual(QueueStubServer.count(key("DELETE", id)), 0, "the row DELETE never went")
        XCTAssertTrue(QueueStubServer.hasRow(id))
        XCTAssertTrue(existsInStore(id))
    }

    /// A 401 mid-sequence must not be retried ambiently as whoever is now signed in.
    func testUnauthorizedThenIdentitySwitch_NoAmbientRetry() async throws {
        let id = try newSession()
        QueueStubServer.seedRow(id, objectPaths: [])
        QueueStubServer.hold(key("GET", id))
        QueueStubServer.respond(key("GET", id), with: 401)
        let previousHandler = NetworkManager.shared.onAuthChallenge
        var challenges = 0
        NetworkManager.shared.onAuthChallenge = { challenges += 1; return false }
        defer { NetworkManager.shared.onAuthChallenge = previousHandler }

        let run = Task { await self.delete(id, capturedOwner: self.ownerA) }
        let held = await QueueStubFixture.poll(timeout: 5) { QueueStubServer.count(self.key("GET", id)) == 1 }
        XCTAssertTrue(held)
        signIn(ownerB)
        QueueStubServer.release(key("GET", id))
        let outcome = await run.value

        XCTAssertEqual(outcome, .refused(.backendDeleteUnconfirmed))
        XCTAssertEqual(challenges, 0, "the auth-challenge handler was never invoked")
        XCTAssertEqual(QueueStubServer.count(key("GET", id)), 1, "the 401 was not retried")
        XCTAssertFalse(QueueStubServer.subjects.contains(ownerB), "no request carried the new identity")
        XCTAssertEqual(QueueStubServer.count(key("DELETE", id)), 0)
        XCTAssertTrue(existsInStore(id))
    }

    /// A→B→A: owner equality alone would pass. The generation must invalidate it,
    /// and the re-check happens after the LAST await, before any mutation.
    func testABASwitchDuringDelete_RefusesBeforeAnyMutation() async throws {
        let id = try newSession()
        QueueStubServer.seedRow(id, objectPaths: [])
        let before = queue.items
        QueueStubServer.hold(key("DELETE", id))

        let run = Task { await self.delete(id, capturedOwner: self.ownerA) }
        let held = await QueueStubFixture.poll(timeout: 5) { QueueStubServer.count(self.key("DELETE", id)) == 1 }
        XCTAssertTrue(held, "setup: the row DELETE is in flight")
        signIn(ownerB)
        signIn(ownerA)                       // back to A: owner equality is restored
        QueueStubServer.release(key("DELETE", id))
        let outcome = await run.value

        XCTAssertEqual(outcome, .refused(.identityChanged), "the generation, not owner equality, decides")
        XCTAssertTrue(existsInStore(id), "no local deletion")
        XCTAssertEqual(queue.items, before, "no queue write")
    }

    /// A factory reset during the delete invalidates it the same way.
    func testFactoryResetDuringDelete_RefusesBeforeAnyMutation() async throws {
        let id = try newSession()
        QueueStubServer.seedRow(id, objectPaths: [])
        QueueStubServer.hold(key("DELETE", id))

        let run = Task { await self.delete(id, capturedOwner: self.ownerA) }
        let held = await QueueStubFixture.poll(timeout: 5) { QueueStubServer.count(self.key("DELETE", id)) == 1 }
        XCTAssertTrue(held)
        queue.stopForFactoryReset()
        QueueStubServer.release(key("DELETE", id))
        let outcome = await run.value
        queue.resumeAfterFactoryReset()

        XCTAssertEqual(outcome, .refused(.identityChanged))
        XCTAssertTrue(existsInStore(id), "no local deletion")
    }
}
