//
//  PublishServiceConnectedDeleteTests.swift
//  MOTIVOTests
//
//  PHASE 4 · P4-U2a / C-60 — BEHAVIOURAL ACCEPTANCE.
//
//  THIS FILE DELIBERATELY WIDENS THIS TARGET'S SCOPE, AND THAT IS STATED RATHER
//  THAN SNEAKED IN. MOTIVOTests.swift declares the target covers "the PURE
//  pieces ... nothing that needs a network, a session, StoreKit or a running
//  app". U2a's acceptance cannot be met inside that boundary: the thing it
//  changes is a GATE in front of a network call, so proving it requires running
//  the real client code against a real backend.
//
//  THE PURE SUITE'S GUARANTEE IS PRESERVED. Every test here calls
//  `try skipUnlessLocalStack()` first and XCTSkips when the local Supabase stack
//  is not reachable, so `xcodebuild test` still passes on any machine.
//
//  LOCAL STACK ONLY -- NEVER PRODUCTION. The base URL is pinned to
//  127.0.0.1:54321 and asserted to be a loopback host before anything is
//  written. Evidence level is "verified against a faithful local reproduction",
//  which is what this project calls it everywhere else.
//
//  WHAT IS PROVEN. A: in .backendConnected an unshare deletes the post row AND
//  its storage object. B: fail-closed -- if the object cannot be deleted, the
//  row survives. C: .backendPreview still reaches deletion (this is an
//  EXPANSION, not a replacement). D: .localSimulation does not.
//

import XCTest
import CoreData
import CryptoKit
@testable import Etudes

@MainActor
final class PublishServiceConnectedDeleteTests: XCTestCase {

    // MARK: - Local stack constants (published by `supabase status`, dev-only)

    private static let baseURLString = "http://127.0.0.1:54321"
    private static let jwtSecret = "super-secret-jwt-token-with-at-least-32-characters-long"
    private static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
        + "eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9."
        + "CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

    /// Local fixture identities created by the U7f suite. `.invalid` emails,
    /// obviously-synthetic uuids. Never a production uid.
    private static let ownerUID  = "00000000-0000-0000-0000-0000000f0001"
    private static let otherUID  = "00000000-0000-0000-0000-0000000f0002"

    private var createdPostIDs: [UUID] = []
    private var createdObjectPaths: [String] = []

    // MARK: - Guards

    private func skipUnlessLocalStack() throws {
        let url = URL(string: Self.baseURLString)!
        // Belt and braces: this suite must never be able to touch production.
        let host = url.host ?? ""
        guard host == "127.0.0.1" || host == "localhost" else {
            XCTFail("refusing to run against non-loopback host \(host)")
            return
        }
        guard Self.probe(url.appendingPathComponent("rest/v1/")) else {
            throw XCTSkip("local Supabase stack not reachable at \(Self.baseURLString) — run `supabase start`")
        }
    }

    private static func probe(_ url: URL) -> Bool {
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            if let h = resp as? HTTPURLResponse { ok = h.statusCode < 500 }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 5)
        return ok
    }

    // MARK: - Setup / teardown

    override func setUp() async throws {
        try await super.setUp()
        BackendConfig.apiBaseURL = URL(string: Self.baseURLString)
        BackendConfig.apiToken = Self.anonKey
        NetworkManager.shared.baseURL = URL(string: Self.baseURLString)
        NetworkManager.shared.setBearerToken(Self.mintJWT(sub: Self.ownerUID))
        // uploadPost gates on AuthManager.canonicalBackendUserID() and returns
        // "Missing owner user id" before it ever reaches the network. Without
        // this the Share-ON / demote cases pass or fail for the wrong reason --
        // which is exactly what happened on this suite's first attempt.
        UserDefaults.standard.set(Self.ownerUID, forKey: "supabaseUserID_v1")
    }

    override func tearDown() async throws {
        // Explicit-id cleanup only. NEVER a predicate sweep -- B-22's rule.
        for path in createdObjectPaths { _ = await Self.adminDeleteObject(path) }
        for id in createdPostIDs { _ = await Self.adminDeletePost(id) }
        createdObjectPaths = []
        createdPostIDs = []
        NetworkManager.shared.setBearerToken(nil)
        NetworkManager.shared.baseURL = URL(string: Self.baseURLString)
        SessionSyncQueue.shared.clear()
        UserDefaults.standard.removeObject(forKey: "supabaseUserID_v1")
        setBackendMode(.localSimulation)
        try await super.tearDown()
    }

    // MARK: - A. .backendConnected deletes the row AND the object

    func testConnectedModeUnshareDeletesPostAndStorageObject() async throws {
        try skipUnlessLocalStack()

        let postID = UUID()
        let objectPath = "users/\(Self.ownerUID)/\(postID.uuidString)/\(UUID().uuidString).jpg"
        try await makeFixture(postID: postID, objectPath: objectPath, owner: Self.ownerUID)

        let prePost = await Self.postExists(postID)
        let preObj = await Self.objectExists(objectPath)
        XCTAssertTrue(prePost, "precondition: post row exists")
        XCTAssertTrue(preObj, "precondition: storage object exists")

        setBackendMode(.backendConnected)
        await PublishService.shared.publish(
            payload: Self.payload(postID),
            objectID: try throwawayObjectID(),
            shouldPublish: false
        )
        await Self.settle()

        let postStillThere = await Self.postExists(postID)
        let objStillThere = await Self.objectExists(objectPath)
        let rowGone = !postStillThere
        let objGone = !objStillThere
        XCTAssertTrue(objGone, "A: storage object must be deleted in .backendConnected")
        XCTAssertTrue(rowGone, "A: post row must be deleted in .backendConnected")
    }

    // MARK: - B. Fail-closed: object cannot be removed -> row survives

    func testConnectedModeFailClosedWhenObjectCannotBeDeleted() async throws {
        try skipUnlessLocalStack()

        // The post is owned by us, but its attachment ref points at an object
        // under ANOTHER user's prefix. The storage DELETE policy requires
        // foldername[2] == auth.uid(), so removal is refused -- which is exactly
        // the condition the fail-closed branch exists for.
        let postID = UUID()
        let foreignPath = "users/\(Self.otherUID)/\(UUID().uuidString)/\(UUID().uuidString).jpg"
        try await makeFixture(postID: postID, objectPath: foreignPath, owner: Self.ownerUID,
                              uploadAs: Self.otherUID)

        let prePost2 = await Self.postExists(postID)
        let preObj2 = await Self.objectExists(foreignPath)
        XCTAssertTrue(prePost2, "precondition: post row exists")
        XCTAssertTrue(preObj2, "precondition: foreign object exists")

        setBackendMode(.backendConnected)
        await PublishService.shared.publish(
            payload: Self.payload(postID),
            objectID: try throwawayObjectID(),
            shouldPublish: false
        )
        await Self.settle()

        let objSurvives = await Self.objectExists(foreignPath)
        let rowSurvives = await Self.postExists(postID)
        XCTAssertTrue(objSurvives, "B: object must survive a refused delete")
        XCTAssertTrue(rowSurvives,
                      "B: FAIL-CLOSED — the post row must NOT be deleted when its object could not be")
    }

    // MARK: - E. C-61 — a FAILED unshare-delete leaves the row PUBLICLY VISIBLE

    /// This is the measurement behind C-61, and it is the reason U2b is blocked.
    /// The fail-closed branch (case B) correctly preserves the row -- but the row
    /// it preserves still carries `is_public = true`, because the only writer of
    /// that column is `patchPostMetadata`, whose single caller sits inside
    /// `uploadPost`, which never runs on the `shouldPublish == false` path.
    ///
    /// TODAY (pre-U2b) an unshare PATCHes the row to is_public=false and the
    /// content becomes invisible. Under U2b, if the delete fails, it stays
    /// VISIBLE. That is a privacy regression on the failure path, not merely
    /// residue.
    /// RE-EXPRESSED BY P4-U2a-2. It used to assert the DEFECT -- that a failed
    /// unshare left the row `is_public = true`. C-61 is now fixed by
    /// demote-then-delete, so the same fixture must leave the row PRIVATE.
    /// The historical assertion is deliberately inverted rather than deleted:
    /// this is the test that measured C-61, and it is now the test that measures
    /// its repair.
    func testFailedUnshareLeavesRowPrivateNotPublic_C61Fixed() async throws {
        try skipUnlessLocalStack()

        let postID = UUID()
        let foreignPath = "users/\(Self.otherUID)/\(UUID().uuidString)/\(UUID().uuidString).jpg"
        try await makeFixture(postID: postID, objectPath: foreignPath, owner: Self.ownerUID,
                              uploadAs: Self.otherUID)

        let prePublic = await Self.postIsPublic(postID)
        XCTAssertEqual(prePublic, true, "precondition: the post is shared")

        setBackendMode(.backendConnected)
        await PublishService.shared.publish(
            payload: Self.payload(postID),
            objectID: try throwawayObjectID(),
            shouldPublish: false
        )
        await Self.settle()

        let stillExists = await Self.postExists(postID)
        let stillPublic = await Self.postIsPublic(postID)
        XCTAssertTrue(stillExists, "the row survives — fail-closed, because the object could not be removed")
        XCTAssertEqual(stillPublic, false,
                       "C-61 FIXED: the row is now PRIVATE, so nothing the member withdrew stays visible")
        XCTAssertTrue(SessionSyncQueue.shared.items.contains { $0.id == postID && $0.op == .unshare },
                      "C-61 FIXED: and the .unshare intent is retained so it converges later")
    }

    // MARK: - F. TODAY's unshare (the pre-U2b baseline C-61 is measured against)

    /// The shipping behaviour: `shouldPublish: true` is hard-coded, so an
    /// unshare enqueues with `isPublic == false`, `uploadPost` runs, and
    /// `patchPostMetadata` DEMOTES the row. The content becomes invisible even
    /// though the row survives.
    ///
    /// This is the comparison that makes C-61 a REGRESSION rather than merely a
    /// gap: today the failure mode is residue, under U2b it is exposure.
    /// RE-EXPRESSED BY THE P4-U2c AMENDMENT, AND IT NOW ASSERTS SOMETHING
    /// STRONGER. It used to document the PRE-U2b world: a payload with
    /// `isPublic: false` published with `shouldPublish: true` demoted the row
    /// and kept it. That combination is the state the amendment abolished --
    /// `op` is derived from `isPublic`, so such a payload IS an unshare.
    ///
    /// What it proves now: **the payload's privacy wins over a contradictory
    /// caller.** Asking to publish something marked private removes it; it does
    /// not leave a private row, and it certainly does not leave a public one.
    func testPrivatePayloadUnsharesEvenWhenCallerAsksToPublish() async throws {
        try skipUnlessLocalStack()

        let postID = UUID()
        let objectPath = "users/\(Self.ownerUID)/\(postID.uuidString)/\(UUID().uuidString).jpg"
        try await makeFixture(postID: postID, objectPath: objectPath, owner: Self.ownerUID)

        let prePublic = await Self.postIsPublic(postID)
        XCTAssertEqual(prePublic, true, "precondition: the post is shared")

        setBackendMode(.backendConnected)
        // Exactly what the shipping call sites do today: publish anyway, and let
        // is_public carry the visibility.
        await PublishService.shared.publish(
            payload: Self.payload(postID, isPublic: false),
            objectID: try throwawayObjectID(),
            shouldPublish: true
        )
        await Self.settle()

        let stillExists = await Self.postExists(postID)
        XCTAssertFalse(stillExists,
                       "a private payload REMOVES the row even though the caller passed shouldPublish: true")
    }

    // MARK: - G/H. OFFLINE DURABILITY — the property U2b would lose

    /// A dead loopback port. Non-nil, so every mode/config gate still passes and
    /// the request genuinely fails at the transport, which is what "offline"
    /// looks like to this code.
    private static let offlineURL = URL(string: "http://127.0.0.1:1")!

    /// G. TODAY: an offline unshare is DURABLY QUEUED and converges on reconnect
    /// with no further user action. This is the eventual-delivery property that
    /// exists only because the shipping call sites hard-code `shouldPublish: true`.
    /// RE-EXPRESSED BY THE P4-U2c AMENDMENT. Its original subject -- the
    /// pre-U2b demote-and-keep path -- no longer exists. The durability property
    /// it measured is unchanged and is asserted here in its current form: an
    /// offline private-payload save is persisted and converges on reconnect
    /// with no further user action. Its historical result is recorded in
    /// docs/phase-4-u2a2-durability.md.
    func testOfflinePrivatePayloadIsQueuedAndConvergesOnReconnect() async throws {
        try skipUnlessLocalStack()

        let postID = UUID()
        let objectPath = "users/\(Self.ownerUID)/\(postID.uuidString)/\(UUID().uuidString).jpg"
        try await makeFixture(postID: postID, objectPath: objectPath, owner: Self.ownerUID)
        let prePublic = await Self.postIsPublic(postID)
        XCTAssertEqual(prePublic, true, "precondition: shared")

        setBackendMode(.backendConnected)
        SessionSyncQueue.shared.clear()

        // --- go offline, then unshare exactly as the shipping app does today
        NetworkManager.shared.baseURL = Self.offlineURL
        await PublishService.shared.publish(
            payload: Self.payload(postID, isPublic: false),
            objectID: try throwawayObjectID(),
            shouldPublish: true
        )
        await Self.settle()

        let queuedWhileOffline = SessionSyncQueue.shared.items.contains { $0.id == postID }
        XCTAssertTrue(queuedWhileOffline,
                      "G: the unshare intent must be DURABLY QUEUED while offline")

        // DURABLE ACROSS PROCESS DEATH, not merely in memory: the queue is a
        // file the initialiser reads back. Asserting the FILE is what makes
        // "survives termination" evidence rather than inference.
        let queueFile = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MOTIVO", isDirectory: true)
            .appendingPathComponent("SessionSyncQueue_v1.json")
        let onDisk = (try? String(contentsOf: queueFile, encoding: .utf8)) ?? ""
        XCTAssertTrue(onDisk.localizedCaseInsensitiveContains(postID.uuidString),
                      "G: the intent is PERSISTED TO DISK at \(queueFile.lastPathComponent)")
        let publicWhileOffline = await Self.postIsPublic(postID)
        XCTAssertEqual(publicWhileOffline, true, "G: server not yet updated while offline")

        // --- connectivity returns; the user does NOT edit the session again.
        //     This is the foreground flush (MOTIVOApp:379).
        NetworkManager.shared.baseURL = URL(string: Self.baseURLString)
        await SessionSyncQueue.shared.flushNow()
        await Self.settle()

        let convergedExists = await Self.postExists(postID)
        let drained = !SessionSyncQueue.shared.items.contains { $0.id == postID }
        XCTAssertFalse(convergedExists,
                       "CONVERGENCE — delivered on reconnect with no further user action")
        XCTAssertTrue(drained, "and the queue item is drained")
    }

    /// H. THE REGRESSION U2b WOULD INTRODUCE: on the `shouldPublish == false`
    /// path nothing is enqueued at all, so an offline unshare leaves NO durable
    /// intent and NOTHING retries it. Runs against today's code because U2a
    /// already made this branch reachable.
    /// RE-EXPRESSED BY P4-U2a-2. It used to assert that the unshare path
    /// enqueued NOTHING, which was the measurement that blocked U2b. The path
    /// now persists an `.unshare` intent before trusting the network.
    func testOfflineUnshareNowLeavesADurableIntent() async throws {
        try skipUnlessLocalStack()

        let postID = UUID()
        let objectPath = "users/\(Self.ownerUID)/\(postID.uuidString)/\(UUID().uuidString).jpg"
        try await makeFixture(postID: postID, objectPath: objectPath, owner: Self.ownerUID)

        setBackendMode(.backendConnected)
        SessionSyncQueue.shared.clear()

        NetworkManager.shared.baseURL = Self.offlineURL
        await PublishService.shared.publish(
            payload: Self.payload(postID, isPublic: false),
            objectID: try throwawayObjectID(),
            shouldPublish: false
        )
        await Self.settle()

        XCTAssertTrue(SessionSyncQueue.shared.items.contains { $0.id == postID && $0.op == .unshare },
                      "P4-U2a-2: an .unshare intent IS now persisted before the network is trusted")

        // Reconnect and flush: there is simply nothing to converge.
        NetworkManager.shared.baseURL = URL(string: Self.baseURLString)
        await SessionSyncQueue.shared.flushNow()
        await Self.settle()

        let stillExists = await Self.postExists(postID)
        XCTAssertFalse(stillExists,
                       "P4-U2a-2: reconnect + flush ALONE converges to removal — the queue retried it")
        XCTAssertFalse(SessionSyncQueue.shared.items.contains { $0.id == postID },
                       "P4-U2a-2: and the intent is dequeued only after the row is gone")
    }

    // MARK: - C. .backendPreview still reaches deletion (expansion, not replacement)

    func testPreviewModeStillDeletes() async throws {
        try skipUnlessLocalStack()

        let postID = UUID()
        let objectPath = "users/\(Self.ownerUID)/\(postID.uuidString)/\(UUID().uuidString).jpg"
        try await makeFixture(postID: postID, objectPath: objectPath, owner: Self.ownerUID)

        setBackendMode(.backendPreview)
        await PublishService.shared.publish(
            payload: Self.payload(postID),
            objectID: try throwawayObjectID(),
            shouldPublish: false
        )
        await Self.settle()

        let previewRowGone = await Self.postExists(postID)
        XCTAssertFalse(previewRowGone, "C: .backendPreview must STILL delete — U2a expands, never replaces")
    }

    // MARK: - D. .localSimulation must not fire the gate

    func testLocalSimulationDoesNotDelete() async throws {
        try skipUnlessLocalStack()

        let postID = UUID()
        let objectPath = "users/\(Self.ownerUID)/\(postID.uuidString)/\(UUID().uuidString).jpg"
        try await makeFixture(postID: postID, objectPath: objectPath, owner: Self.ownerUID)

        setBackendMode(.localSimulation)
        await PublishService.shared.publish(
            payload: Self.payload(postID),
            objectID: try throwawayObjectID(),
            shouldPublish: false
        )
        await Self.settle()

        // Also the measurement behind the scope record's §7 observation:
        // SimulatedPublishService.deletePost performs REAL deletion, so what
        // keeps it harmless is this gate not firing.
        let soloRow = await Self.postExists(postID)
        let soloObj = await Self.objectExists(objectPath)
        XCTAssertTrue(soloRow, "D: .localSimulation must not reach deletion")
        XCTAssertTrue(soloObj, "D: nor remove the object")
    }

    // MARK: - Fixture helpers

    private func makeFixture(postID: UUID, objectPath: String, owner: String,
                             uploadAs uploader: String? = nil) async throws {
        createdPostIDs.append(postID)
        createdObjectPaths.append(objectPath)
        try await Self.adminUploadObject(objectPath, as: uploader ?? owner)
        try await Self.adminInsertPost(postID, owner: owner, objectPath: objectPath)
    }

    private static func payload(_ id: UUID, isPublic: Bool = true) -> SessionSyncQueue.PostPublishPayload {
        SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: id, sessionTimestamp: nil, title: nil,
            durationSeconds: nil, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil, isPublic: isPublic
        )
    }

    /// Any valid NSManagedObjectID will do: on the `shouldPublish == false`
    /// path it is used only for `uriRepresentation()`, and a TEMPORARY id has a
    /// perfectly good URI. So this inserts into a scratch context of the app's
    /// EXISTING container and never saves.
    ///
    /// It used to build a second `NSPersistentContainer(name: "MOTIVO")`, which
    /// loaded the same model a second time and left the shared store throwing
    /// "A fetch request must have an entity" in whichever test ran next --
    /// passing alone and crashing in suite. A second container for one model is
    /// the defect; a scratch context is the fix.
    private func throwawayObjectID() throws -> NSManagedObjectID {
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = PersistenceController.shared.container.persistentStoreCoordinator
        let model = PersistenceController.shared.container.managedObjectModel
        guard let name = (model.entities.first(where: { $0.name == "Session" }) ?? model.entities.first)?.name else {
            throw NSError(domain: "test", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "no entities in model"])
        }
        let obj = NSEntityDescription.insertNewObject(forEntityName: name, into: ctx)
        let id = obj.objectID          // temporary id -- never persisted
        ctx.rollback()
        return id
    }

    private static func settle() async {
        // PublishService dispatches its delete into a detached Task.
        try? await Task.sleep(nanoseconds: 2_500_000_000)
    }

    // MARK: - JWT (local dev secret only)

    private static func mintJWT(sub: String) -> String {
        func b64url(_ d: Data) -> String {
            d.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let now = Int(Date().timeIntervalSince1970)
        let header = #"{"alg":"HS256","typ":"JWT"}"#
        let claims = """
        {"sub":"\(sub)","role":"authenticated","aud":"authenticated","iat":\(now),"exp":\(now + 3600)}
        """
        let signingInput = b64url(Data(header.utf8)) + "." + b64url(Data(claims.utf8))
        let key = SymmetricKey(data: Data(jwtSecret.utf8))
        let sig = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: key)
        return signingInput + "." + b64url(Data(sig))
    }

    // MARK: - Direct REST helpers (fixture setup + assertions, NOT the code under test)

    private static func send(_ req: URLRequest) async -> (Int, Data) {
        do {
            let (d, r) = try await URLSession.shared.data(for: req)
            return ((r as? HTTPURLResponse)?.statusCode ?? -1, d)
        } catch { return (-1, Data()) }
    }

    private static func request(_ path: String, _ method: String, as uid: String? = nil) -> URLRequest {
        var req = URLRequest(url: URL(string: baseURLString + "/" + path)!)
        req.httpMethod = method
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer " + mintJWT(sub: uid ?? ownerUID), forHTTPHeaderField: "Authorization")
        return req
    }

    private static func adminInsertPost(_ id: UUID, owner: String, objectPath: String) async throws {
        var req = request("rest/v1/posts", "POST", as: owner)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        let body: [String: Any] = [
            "id": id.uuidString,
            "owner_user_id": owner,
            "is_public": true,
            "attachments": [["bucket": "attachments", "path": objectPath]]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (code, data) = await send(req)
        guard (200..<300).contains(code) else {
            throw NSError(domain: "fixture", code: code, userInfo: [
                NSLocalizedDescriptionKey: "post insert failed \(code): \(String(data: data, encoding: .utf8) ?? "")"])
        }
    }

    private static func adminUploadObject(_ path: String, as uid: String) async throws {
        var req = request("storage/v1/object/attachments/" + path, "POST", as: uid)
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("p4-u2a-fixture".utf8)
        let (code, data) = await send(req)
        guard (200..<300).contains(code) else {
            throw NSError(domain: "fixture", code: code, userInfo: [
                NSLocalizedDescriptionKey: "object upload failed \(code): \(String(data: data, encoding: .utf8) ?? "")"])
        }
    }

    /// Reads is_public off the surviving row. Evidence for C-61: a failed
    /// unshare-delete leaves the row PUBLIC, not merely present.
    private static func postIsPublic(_ id: UUID) async -> Bool? {
        let req = request("rest/v1/posts?id=eq.\(id.uuidString)&select=is_public", "GET")
        let (code, data) = await send(req)
        guard code == 200,
              let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              let first = rows.first else { return nil }
        return first["is_public"] as? Bool
    }

    private static func postExists(_ id: UUID) async -> Bool {
        let req = request("rest/v1/posts?id=eq.\(id.uuidString)&select=id", "GET")
        let (code, data) = await send(req)
        guard code == 200 else { return false }
        let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        return (rows?.count ?? 0) > 0
    }

    private static func objectExists(_ path: String) async -> Bool {
        // Ask as the object's own owner so RLS cannot mask existence.
        let owner = path.split(separator: "/").count > 1 ? String(path.split(separator: "/")[1]) : ownerUID
        let req = request("storage/v1/object/attachments/" + path, "GET", as: owner)
        let (code, _) = await send(req)
        return code == 200
    }

    private static func adminDeleteObject(_ path: String) async -> Bool {
        let owner = path.split(separator: "/").count > 1 ? String(path.split(separator: "/")[1]) : ownerUID
        let (code, _) = await send(request("storage/v1/object/attachments/" + path, "DELETE", as: owner))
        return (200..<300).contains(code)
    }

    private static func adminDeletePost(_ id: UUID) async -> Bool {
        let (code, _) = await send(request("rest/v1/posts?id=eq.\(id.uuidString)", "DELETE"))
        return (200..<300).contains(code)
    }
}
