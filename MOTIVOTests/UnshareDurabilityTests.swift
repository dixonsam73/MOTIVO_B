//
//  UnshareDurabilityTests.swift
//  MOTIVOTests
//
//  PHASE 4 · P4-U2a-2 / C-61 — DURABLE UNSHARE INTENT.
//
//  Same boundary rules as PublishServiceConnectedDeleteTests: LOCAL STACK ONLY,
//  loopback-pinned, XCTSkip when it is not running, explicit fixture ids removed
//  by explicit id afterwards.
//

import XCTest
import CoreData
import CryptoKit
@testable import Etudes

@MainActor
final class UnshareDurabilityTests: XCTestCase {

    private static let baseURLString = "http://127.0.0.1:54321"
    private static let offlineURL = URL(string: "http://127.0.0.1:1")!
    private static let jwtSecret = "super-secret-jwt-token-with-at-least-32-characters-long"
    private static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
        + "eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9."
        + "CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
    private static let ownerUID = "00000000-0000-0000-0000-0000000f0001"

    private var postIDs: [UUID] = []
    private var objectPaths: [String] = []

    private static var queueFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MOTIVO", isDirectory: true)
            .appendingPathComponent("SessionSyncQueue_v1.json")
    }

    // MARK: - Lifecycle

    private func skipUnlessLocalStack() throws {
        let url = URL(string: Self.baseURLString)!
        guard url.host == "127.0.0.1" else { XCTFail("non-loopback host"); return }
        guard Self.probe(url.appendingPathComponent("rest/v1/")) else {
            throw XCTSkip("local Supabase stack not reachable — run `supabase start`")
        }
    }

    private static func probe(_ url: URL) -> Bool {
        var r = URLRequest(url: url); r.timeoutInterval = 3
        r.setValue(anonKey, forHTTPHeaderField: "apikey")
        let sem = DispatchSemaphore(value: 0); var ok = false
        URLSession.shared.dataTask(with: r) { _, resp, _ in
            if let h = resp as? HTTPURLResponse { ok = h.statusCode < 500 }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 5)
        return ok
    }

    override func setUp() async throws {
        try await super.setUp()
        BackendConfig.apiBaseURL = URL(string: Self.baseURLString)
        BackendConfig.apiToken = Self.anonKey
        NetworkManager.shared.baseURL = URL(string: Self.baseURLString)
        NetworkManager.shared.setBearerToken(Self.mintJWT(sub: Self.ownerUID))
        UserDefaults.standard.set(Self.ownerUID, forKey: "supabaseUserID_v1")
        SessionSyncQueue.shared.clear()
        setBackendMode(.backendConnected)
    }

    override func tearDown() async throws {
        NetworkManager.shared.baseURL = URL(string: Self.baseURLString)
        // Delete each object AS THE OWNER ENCODED IN ITS OWN PATH. Deleting
        // everything as `ownerUID` silently leaves any foreign-prefix fixture
        // behind -- which is exactly how two stray objects survived an earlier
        // run of this suite.
        for p in objectPaths {
            let parts = p.split(separator: "/")
            let owner = parts.count > 1 ? String(parts[1]) : Self.ownerUID
            _ = await Self.rest("storage/v1/object/attachments/" + p, "DELETE", nil, as: owner)
        }
        for id in postIDs { _ = await Self.rest("rest/v1/posts?id=eq.\(id.uuidString)", "DELETE") }
        objectPaths = []; postIDs = []
        SessionSyncQueue.shared.clear()
        NetworkManager.shared.setBearerToken(nil)
        UserDefaults.standard.removeObject(forKey: "supabaseUserID_v1")
        setBackendMode(.localSimulation)
        try await super.tearDown()
    }

    // MARK: - 1. Backward compatibility of the on-disk queue

    /// A queue file written before P4-U2a-2 has no `op` key. The synthesised
    /// decoder would throw `keyNotFound` on every entry; `load(from:)` would
    /// then fall through its legacy `[UUID]` branch and, failing that,
    /// propagate — silently discarding a queue of real pending publishes.
    func testLegacyQueueFileDecodesAsPublish() throws {
        let legacy = """
        [{"id":"\(UUID().uuidString)","isPublic":true,"areNotesPrivate":false},
         {"id":"\(UUID().uuidString)","isPublic":false,"areNotesPrivate":false,"title":"old"}]
        """
        let data = Data(legacy.utf8)
        let decoded = try JSONDecoder().decode([SessionSyncQueue.PostPublishPayload].self, from: data)
        XCTAssertEqual(decoded.count, 2, "legacy file must still decode")
        XCTAssertTrue(decoded.allSatisfy { $0.op == .publish },
                      "every legacy entry must default to .publish — its original meaning")
    }

    // MARK: - 2. Last intent wins, BOTH directions

    func testPublishThenUnshareResolvesToUnshare() throws {
        let id = UUID()
        SessionSyncQueue.shared.enqueue(Self.payload(id, op: .publish, isPublic: true))
        SessionSyncQueue.shared.enqueue(Self.payload(id, op: .unshare, isPublic: false))
        let items = SessionSyncQueue.shared.items.filter { $0.id == id }
        XCTAssertEqual(items.count, 1, "still one item per post id")
        XCTAssertEqual(items.first?.op, .unshare, "publish → unshare: LAST INTENT WINS")
    }

    func testUnshareThenPublishResolvesToPublish() throws {
        let id = UUID()
        SessionSyncQueue.shared.enqueue(Self.payload(id, op: .unshare, isPublic: false))
        SessionSyncQueue.shared.enqueue(Self.payload(id, op: .publish, isPublic: true))
        let items = SessionSyncQueue.shared.items.filter { $0.id == id }
        XCTAssertEqual(items.count, 1, "still one item per post id")
        XCTAssertEqual(items.first?.op, .publish, "unshare → publish: LAST INTENT WINS")
    }

    // MARK: - 3. Offline → persisted → reconstruction → reconnect → converges

    func testOfflineUnsharePersistsSurvivesReconstructionAndConverges() async throws {
        try skipUnlessLocalStack()
        let id = UUID()
        let obj = "users/\(Self.ownerUID)/\(id.uuidString)/\(UUID().uuidString).jpg"
        try await makeFixture(id, obj)

        // --- offline unshare
        NetworkManager.shared.baseURL = Self.offlineURL
        await PublishService.shared.publish(payload: Self.payload(id, op: .publish, isPublic: false),
                                            objectID: try throwawayObjectID(), shouldPublish: false)
        await Self.settle()

        XCTAssertTrue(SessionSyncQueue.shared.items.contains { $0.id == id && $0.op == .unshare },
                      "offline: the .unshare intent is retained in the queue")
        let publicWhileOffline = await Self.isPublic(id)
        XCTAssertEqual(publicWhileOffline, true, "offline: server untouched")

        // --- PROCESS RECONSTRUCTION: decode the real file with the real type
        //     through the real decoder, exactly as `load(from:)` does.
        let onDisk = try Data(contentsOf: Self.queueFile)
        let reconstructed = try JSONDecoder().decode([SessionSyncQueue.PostPublishPayload].self, from: onDisk)
        XCTAssertTrue(reconstructed.contains { $0.id == id && $0.op == .unshare },
                      "the .unshare survives reconstruction FROM DISK, not merely in memory")

        // --- reconnect; flush only. The user does NOT touch the session again.
        NetworkManager.shared.baseURL = URL(string: Self.baseURLString)
        await SessionSyncQueue.shared.flushNow()
        await Self.settle()

        let exists = await Self.exists(id)
        let objExists = await Self.objectExists(obj)
        XCTAssertFalse(exists, "CONVERGED: the row is absent after reconnect + flush alone")
        XCTAssertFalse(objExists, "CONVERGED: the storage object is gone too")
        XCTAssertFalse(SessionSyncQueue.shared.items.contains { $0.id == id },
                       "dequeued only after confirmed removal")
    }

    // MARK: - 4. Failure point A — demotion cannot reach the server

    func testDemotionUnreachableKeepsIntentQueued() async throws {
        try skipUnlessLocalStack()
        let id = UUID()
        let obj = "users/\(Self.ownerUID)/\(id.uuidString)/\(UUID().uuidString).jpg"
        try await makeFixture(id, obj)

        NetworkManager.shared.baseURL = Self.offlineURL
        SessionSyncQueue.shared.enqueue(Self.payload(id, op: .unshare, isPublic: false))
        await SessionSyncQueue.shared.flushNow()
        await Self.settle()

        NetworkManager.shared.baseURL = URL(string: Self.baseURLString)
        let stillPublic = await Self.isPublic(id)
        XCTAssertEqual(stillPublic, true, "A: nothing destructive was attempted")
        XCTAssertTrue(SessionSyncQueue.shared.items.contains { $0.id == id },
                      "A: the intent REMAINS QUEUED")
        let objSurvives = await Self.objectExists(obj)
        XCTAssertTrue(objSurvives, "A: the object is untouched")
    }

    // MARK: - 5. Failure point B — row private, intent retained, later convergence

    /// A true "demote 200 then object-delete fails" cannot be produced from the
    /// client: every non-transport Storage failure now reads as success, and a
    /// transport failure would already have failed the demote. So this builds
    /// the STATE under assertion — row already private, intent queued, flush
    /// fails — and then proves it converges. What it does not prove is that the
    /// *deletion* specifically was the failing step.
    func testPrivateRowWithRetainedIntentConverges() async throws {
        try skipUnlessLocalStack()
        let id = UUID()
        let obj = "users/\(Self.ownerUID)/\(id.uuidString)/\(UUID().uuidString).jpg"
        try await makeFixture(id, obj)

        _ = await Self.rest("rest/v1/posts?id=eq.\(id.uuidString)", "PATCH", ["is_public": false])
        let demoted = await Self.isPublic(id)
        XCTAssertEqual(demoted, false, "precondition: the row is already private")

        NetworkManager.shared.baseURL = Self.offlineURL
        SessionSyncQueue.shared.enqueue(Self.payload(id, op: .unshare, isPublic: false))
        await SessionSyncQueue.shared.flushNow()
        await Self.settle()

        NetworkManager.shared.baseURL = URL(string: Self.baseURLString)
        let midExists = await Self.exists(id)
        let midPublic = await Self.isPublic(id)
        XCTAssertTrue(midExists, "B: the row survives")
        XCTAssertEqual(midPublic, false, "B: and it is PRIVATE — a pending reconciliation state")
        XCTAssertTrue(SessionSyncQueue.shared.items.contains { $0.id == id },
                      "B: the intent REMAINS QUEUED — private is not the settled result")

        await SessionSyncQueue.shared.flushNow()
        await Self.settle()
        let finalExists = await Self.exists(id)
        XCTAssertFalse(finalExists, "B: a later flush CONVERGES to removal")
        XCTAssertFalse(SessionSyncQueue.shared.items.contains { $0.id == id }, "B: then dequeues")
    }

    // MARK: - 6. Failure point C — partial object deletion, retry converges

    func testPartiallyDeletedObjectsStillConverge() async throws {
        try skipUnlessLocalStack()
        let id = UUID()
        let objGone = "users/\(Self.ownerUID)/\(id.uuidString)/\(UUID().uuidString).jpg"
        let objLive = "users/\(Self.ownerUID)/\(id.uuidString)/\(UUID().uuidString).jpg"
        try await Self.upload(objGone)
        try await Self.upload(objLive)
        objectPaths.append(contentsOf: [objGone, objLive])
        postIDs.append(id)
        try await Self.insertPost(id, objects: [objGone, objLive])

        // Simulate a run that removed the first object and then failed.
        _ = await Self.rest("storage/v1/object/attachments/" + objGone, "DELETE")
        let goneNow = await Self.objectExists(objGone)
        XCTAssertFalse(goneNow, "precondition: one object is ALREADY absent")

        SessionSyncQueue.shared.enqueue(Self.payload(id, op: .unshare, isPublic: false))
        await SessionSyncQueue.shared.flushNow()
        await Self.settle()

        let exists = await Self.exists(id)
        let liveGone = !(await Self.objectExists(objLive))
        XCTAssertTrue(liveGone, "C: the remaining object is deleted")
        XCTAssertFalse(exists, "C: CONVERGES — an already-absent object is not a poison failure")
        XCTAssertFalse(SessionSyncQueue.shared.items.contains { $0.id == id }, "C: and dequeues")
    }

    // MARK: - 7. Already-absent object alone

    func testAlreadyAbsentObjectIsSuccessNotPoison() async throws {
        try skipUnlessLocalStack()
        let id = UUID()
        let ghost = "users/\(Self.ownerUID)/\(id.uuidString)/\(UUID().uuidString).jpg"
        postIDs.append(id)
        try await Self.insertPost(id, objects: [ghost])   // referenced but never uploaded

        SessionSyncQueue.shared.enqueue(Self.payload(id, op: .unshare, isPublic: false))
        await SessionSyncQueue.shared.flushNow()
        await Self.settle()

        let exists = await Self.exists(id)
        XCTAssertFalse(exists, "a reference to a non-existent object must not block convergence")
        XCTAssertFalse(SessionSyncQueue.shared.items.contains { $0.id == id }, "and it dequeues")
    }

    // MARK: - 8. .publish behaviour is unchanged

    func testOrdinaryPublishStillWorks() async throws {
        try skipUnlessLocalStack()
        let id = UUID()
        postIDs.append(id)

        SessionSyncQueue.shared.enqueue(Self.payload(id, op: .publish, isPublic: true))
        await SessionSyncQueue.shared.flushNow()
        await Self.settle()

        let exists = await Self.exists(id)
        let pub = await Self.isPublic(id)
        XCTAssertTrue(exists, "publish still creates the row")
        XCTAssertEqual(pub, true, "and it is public")
        XCTAssertFalse(SessionSyncQueue.shared.items.contains { $0.id == id }, "and dequeues")
    }

    // MARK: - 9. Solo stays local

    func testLocalSimulationDoesNotReachTheServer() async throws {
        try skipUnlessLocalStack()
        let id = UUID()
        let obj = "users/\(Self.ownerUID)/\(id.uuidString)/\(UUID().uuidString).jpg"
        try await makeFixture(id, obj)

        setBackendMode(.localSimulation)
        SessionSyncQueue.shared.enqueue(Self.payload(id, op: .unshare, isPublic: false))
        await SessionSyncQueue.shared.flushNow()
        await Self.settle()

        setBackendMode(.backendConnected)
        let exists = await Self.exists(id)
        XCTAssertTrue(exists, "Solo must not reach the server")
        XCTAssertTrue(SessionSyncQueue.shared.items.contains { $0.id == id }, "and the item is retained")
    }

    // MARK: - P4-U2c. An .unshare REMOVES attachments and uploads nothing

    /// The fourth distinction U2c must draw: an unshare of a post that still
    /// carries attachment refs must delete those objects and must never invoke
    /// the upload path. The structural half -- that the upload door is inside
    /// `uploadPost`, which `.unshare` never reaches -- is pinned by
    /// `u2c-acceptance.sh`; this is the behavioural half.
    func testUnshareRemovesAttachmentsAndUploadsNothing() async throws {
        try skipUnlessLocalStack()
        let id = UUID()
        let objA = "users/\(Self.ownerUID)/\(id.uuidString)/\(UUID().uuidString).jpg"
        let objB = "users/\(Self.ownerUID)/\(id.uuidString)/\(UUID().uuidString).jpg"
        try await Self.upload(objA)
        try await Self.upload(objB)
        objectPaths.append(contentsOf: [objA, objB])
        postIDs.append(id)
        try await Self.insertPost(id, objects: [objA, objB])

        let beforeA = await Self.objectExists(objA)
        let beforeB = await Self.objectExists(objB)
        XCTAssertTrue(beforeA && beforeB, "precondition: both objects are on Storage")

        SessionSyncQueue.shared.enqueue(Self.payload(id, op: .unshare, isPublic: false))
        await SessionSyncQueue.shared.flushNow()
        await Self.settle()

        let afterA = await Self.objectExists(objA)
        let afterB = await Self.objectExists(objB)
        let row = await Self.exists(id)
        XCTAssertFalse(afterA, "unshare deletes the first attachment object")
        XCTAssertFalse(afterB, "…and the second")
        XCTAssertFalse(row, "…and the row")
        XCTAssertFalse(SessionSyncQueue.shared.items.contains { $0.id == id },
                       "…and dequeues, having uploaded nothing")
    }

    // MARK: - Helpers

    private func makeFixture(_ id: UUID, _ object: String) async throws {
        postIDs.append(id); objectPaths.append(object)
        try await Self.upload(object)
        try await Self.insertPost(id, objects: [object])
    }

    private static func payload(_ id: UUID, op: SessionSyncQueue.PostOp, isPublic: Bool)
    -> SessionSyncQueue.PostPublishPayload {
        SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: id, sessionTimestamp: nil, title: nil, durationSeconds: nil,
            activityType: nil, activityDetail: nil, instrumentLabel: nil, mood: nil, effort: nil,
            isPublic: isPublic, notes: nil, areNotesPrivate: false, op: op)
    }

    private func throwawayObjectID() throws -> NSManagedObjectID {
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = PersistenceController.shared.container.persistentStoreCoordinator
        let model = PersistenceController.shared.container.managedObjectModel
        guard let name = (model.entities.first(where: { $0.name == "Session" }) ?? model.entities.first)?.name else {
            throw NSError(domain: "test", code: 1)
        }
        let obj = NSEntityDescription.insertNewObject(forEntityName: name, into: ctx)
        let oid = obj.objectID
        ctx.rollback()
        return oid
    }

    private static func settle() async { try? await Task.sleep(nanoseconds: 2_500_000_000) }

    private static func mintJWT(sub: String) -> String {
        func b64(_ d: Data) -> String {
            d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let now = Int(Date().timeIntervalSince1970)
        let si = b64(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8)) + "." + b64(Data("""
        {"sub":"\(sub)","role":"authenticated","aud":"authenticated","iat":\(now),"exp":\(now + 3600)}
        """.utf8))
        let sig = HMAC<SHA256>.authenticationCode(for: Data(si.utf8), using: SymmetricKey(data: Data(jwtSecret.utf8)))
        return si + "." + b64(Data(sig))
    }

    @discardableResult
    private static func rest(_ path: String, _ method: String, _ body: [String: Any]? = nil,
                             as uid: String? = nil) async -> (Int, Data) {
        var r = URLRequest(url: URL(string: baseURLString + "/" + path)!)
        r.httpMethod = method
        r.setValue(anonKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + mintJWT(sub: uid ?? ownerUID), forHTTPHeaderField: "Authorization")
        r.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        do { let (d, resp) = try await URLSession.shared.data(for: r)
             return ((resp as? HTTPURLResponse)?.statusCode ?? -1, d) }
        catch { return (-1, Data()) }
    }

    private static func upload(_ path: String) async throws {
        var r = URLRequest(url: URL(string: baseURLString + "/storage/v1/object/attachments/" + path)!)
        r.httpMethod = "POST"
        r.setValue(anonKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + mintJWT(sub: ownerUID), forHTTPHeaderField: "Authorization")
        r.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        r.httpBody = Data("u2a2".utf8)
        let (_, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else { throw NSError(domain: "fixture", code: code) }
    }

    private static func insertPost(_ id: UUID, objects: [String]) async throws {
        let refs = objects.map { ["bucket": "attachments", "path": $0] }
        let (code, _) = await rest("rest/v1/posts", "POST", [
            "id": id.uuidString, "owner_user_id": ownerUID, "is_public": true, "attachments": refs])
        guard (200..<300).contains(code) else { throw NSError(domain: "fixture", code: code) }
    }

    private static func exists(_ id: UUID) async -> Bool {
        let (code, data) = await rest("rest/v1/posts?id=eq.\(id.uuidString)&select=id", "GET")
        guard code == 200, let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return false }
        return !rows.isEmpty
    }

    private static func isPublic(_ id: UUID) async -> Bool? {
        let (code, data) = await rest("rest/v1/posts?id=eq.\(id.uuidString)&select=is_public", "GET")
        guard code == 200, let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              let f = rows.first else { return nil }
        return f["is_public"] as? Bool
    }

    private static func objectExists(_ path: String) async -> Bool {
        let (code, _) = await rest("storage/v1/object/attachments/" + path, "GET")
        return code == 200
    }
}
