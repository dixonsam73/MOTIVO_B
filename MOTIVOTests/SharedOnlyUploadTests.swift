//
//  SharedOnlyUploadTests.swift
//  MOTIVOTests
//
//  PHASE 4 · P4-U2b — SHARED-ONLY UPLOADS.
//
//  These call `PublishService.publish(..., shouldPublish: payload.isPublic)`,
//  which is exactly what the two shipping call sites now pass. LOCAL STACK ONLY.
//
//  THE ATTACHMENT CASE USES A REAL CORE DATA FIXTURE, DELIBERATELY. Asserting
//  "Share OFF uploaded no object" against a session that has no attachment
//  proves nothing -- `loadIncludedAttachments` would return an empty array
//  either way. So the same fixture is proven CAPABLE of uploading (Share ON puts
//  the object in the bucket) before Share OFF is asserted not to. Without the
//  positive control the negative is vacuous.
//

import XCTest
import CoreData
import CryptoKit
@testable import Etudes

@MainActor
final class SharedOnlyUploadTests: XCTestCase {

    private static let baseURLString = "http://127.0.0.1:54321"
    private static let jwtSecret = "super-secret-jwt-token-with-at-least-32-characters-long"
    private static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
        + "eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9."
        + "CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
    private static let ownerUID = "00000000-0000-0000-0000-0000000f0001"

    private var postIDs: [UUID] = []
    private var coreDataObjects: [NSManagedObject] = []
    private var scratchFiles: [URL] = []
    private var privacyKeys: [(UUID, URL)] = []

    // MARK: - Lifecycle

    private func skipUnlessLocalStack() throws {
        guard URL(string: Self.baseURLString)!.host == "127.0.0.1" else { XCTFail("non-loopback"); return }
        guard Self.probe() else { throw XCTSkip("local Supabase stack not reachable — run `supabase start`") }
    }

    private static func probe() -> Bool {
        var r = URLRequest(url: URL(string: baseURLString + "/rest/v1/")!); r.timeoutInterval = 3
        r.setValue(anonKey, forHTTPHeaderField: "apikey")
        let sem = DispatchSemaphore(value: 0); var ok = false
        URLSession.shared.dataTask(with: r) { _, resp, _ in
            if let h = resp as? HTTPURLResponse { ok = h.statusCode < 500 }; sem.signal()
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
        for id in postIDs { _ = await Self.rest("rest/v1/posts?id=eq.\(id.uuidString)", "DELETE") }
        // Any object the fixture managed to upload, by explicit path.
        for id in postIDs {
            let (code, data) = await Self.rest(
                "storage/v1/object/list/attachments", "POST",
                ["prefix": "users/\(Self.ownerUID)/\(id.uuidString)", "limit": 100])
            if code == 200,
               let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                for r in rows {
                    if let n = r["name"] as? String {
                        _ = await Self.rest("storage/v1/object/attachments/users/\(Self.ownerUID)/\(id.uuidString)/\(n)", "DELETE")
                    }
                }
            }
        }
        let ctx = PersistenceController.shared.container.viewContext
        for o in coreDataObjects where !o.isDeleted { ctx.delete(o) }
        try? ctx.save()
        for f in scratchFiles { try? FileManager.default.removeItem(at: f) }
        for (id, url) in privacyKeys { AttachmentPrivacy.setPrivate(id: id, url: url, true) }
        postIDs = []; coreDataObjects = []; scratchFiles = []; privacyKeys = []
        SessionSyncQueue.shared.clear()
        NetworkManager.shared.setBearerToken(nil)
        UserDefaults.standard.removeObject(forKey: "supabaseUserID_v1")
        setBackendMode(.localSimulation)
        try await super.tearDown()
    }

    // MARK: - 1. Connected, Share OFF → no server post row

    func testConnectedShareOffCreatesNoPostRow() async throws {
        try skipUnlessLocalStack()
        let id = UUID(); postIDs.append(id)

        await Self.publishLikeTheApp(Self.payload(id, isPublic: false), oid: try throwawayObjectID())

        let exists = await Self.postExists(id)
        XCTAssertFalse(exists, "Share OFF must create NO server post row")
    }

    // MARK: - 2. Connected Thought → no server post row

    /// A Thought sets `isPublic = false` unconditionally
    /// (`AddEditSessionView:1829`), and the publish block is guarded only by
    /// `canShareWithFollowers`. Before U2b every Thought saved while Connected
    /// became a private server row — the most personal content the app holds.
    func testConnectedThoughtCreatesNoPostRow() async throws {
        try skipUnlessLocalStack()
        let id = UUID(); postIDs.append(id)

        let thought = SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: id, sessionTimestamp: Date(),
            title: nil, durationSeconds: nil, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil,
            isPublic: false, notes: "a private thought", areNotesPrivate: true)
        await Self.publishLikeTheApp(thought, oid: try throwawayObjectID())

        let exists = await Self.postExists(id)
        XCTAssertFalse(exists, "a Thought must create NO server post row")
    }

    // MARK: - 3. Included attachment + Share OFF → Storage is never reached

    /// WHAT THIS PROVES, AND WHAT IT DOES NOT.
    ///
    /// It proves the GATE: with an attachment explicitly marked included, a
    /// Share-OFF save creates **no post row** and enqueues **no `.publish`
    /// item**. Since `loadIncludedAttachments` has exactly one caller --
    /// `uploadPost` -- and `uploadPost` runs only for `.publish` items, the
    /// attachment upload is unreachable. That structural half is pinned by
    /// `u2b-acceptance.sh` (U2b-6/7), not asserted here.
    ///
    /// IT IS NOT AN END-TO-END UPLOAD CONTROL. An earlier revision tried to
    /// prove capability first -- same fixture, Share ON, object must appear --
    /// and the control FAILED: the post row was created with `attachments: []`,
    /// so `loadIncludedAttachments` returned nothing for a Core Data fixture
    /// whose privacy flag, file and relationship all verified correct.
    ///
    /// **THE CAUSE IS NOW ESTABLISHED -- P4-U6, 2026-09-05 -- AND IT WAS THIS
    /// FIXTURE, NOT THE PRODUCT.** It set `kind: "photo"`; `AttachmentKind` is
    /// audio|video|image|file|pdf, and `contentType(for:ext:)` maps anything
    /// unrecognised to `application/octet-stream`, which the attachments bucket
    /// refuses with 415 InvalidMimeType. `uploadPost` then returned failure and
    /// the row kept its default empty `attachments`. Production carries the
    /// SAME `allowed_mime_types`, so the local stack was faithful throughout.
    /// The `kind` is corrected above; the sentence it replaces read *"The cause
    /// was not established and is NOT claimed to be a product defect"*, which
    /// was the right disposition on the evidence then available.
    /// **U2c owns the direct attachment-path assertion.**
    func testIncludedAttachmentShareOffReachesNoUploadPath() async throws {
        try skipUnlessLocalStack()

        let offID = UUID(); postIDs.append(offID)
        try makeCoreDataSessionWithIncludedAttachment(sessionID: offID)

        await Self.publishLikeTheApp(Self.payload(offID, isPublic: false), oid: try objectID(for: offID))

        let offRow = await Self.postExists(offID)
        let offObjects = await Self.objectCount(prefix: "users/\(Self.ownerUID)/\(offID.uuidString)")
        XCTAssertFalse(offRow, "Share OFF creates no post row, so uploadPost is never reached")
        XCTAssertEqual(offObjects, 0, "and no Storage object exists under this post's prefix")
        XCTAssertFalse(SessionSyncQueue.shared.items.contains { $0.id == offID && $0.op == .publish },
                       "no .publish item is enqueued — the only thing that can invoke uploadPost")
    }

    // MARK: - 4. Share ON is unchanged

    func testShareOnStillPublishes() async throws {
        try skipUnlessLocalStack()
        let id = UUID(); postIDs.append(id)

        await Self.publishLikeTheApp(Self.payload(id, isPublic: true), oid: try throwawayObjectID())

        let exists = await Self.postExists(id)
        let pub = await Self.isPublic(id)
        XCTAssertTrue(exists, "Share ON still creates the row")
        XCTAssertEqual(pub, true, "…and it is public")
        XCTAssertFalse(SessionSyncQueue.shared.items.contains { $0.id == id }, "…and it dequeues")
    }

    // MARK: - 5. shared → Share OFF removes the post

    /// Storage-object removal on unshare is proven in `UnshareDurabilityTests`,
    /// whose fixtures upload real objects through REST; this case covers the
    /// SHIPPING CALL SHAPE -- existence following visibility across two saves.
    func testSharedThenUnsharedRemovesRow() async throws {
        try skipUnlessLocalStack()
        let id = UUID(); postIDs.append(id)

        await Self.publishLikeTheApp(Self.payload(id, isPublic: true), oid: try throwawayObjectID())
        let created = await Self.postExists(id)
        XCTAssertTrue(created, "precondition: Share ON created the row")

        // The member toggles Share OFF and saves. Same call; isPublic now false.
        await Self.publishLikeTheApp(Self.payload(id, isPublic: false), oid: try throwawayObjectID())

        let stillThere = await Self.postExists(id)
        XCTAssertFalse(stillThere, "shared → Share OFF removes the post row")
        XCTAssertFalse(SessionSyncQueue.shared.items.contains { $0.id == id }, "…and dequeues")
    }

    // MARK: - Fixtures

    /// Mirrors the shipping call sites: existence follows visibility.
    private static func publishLikeTheApp(_ p: SessionSyncQueue.PostPublishPayload,
                                          oid: NSManagedObjectID) async {
        PublishService.shared.publish(payload: p, objectID: oid, shouldPublish: p.isPublic)
        try? await Task.sleep(nanoseconds: 3_000_000_000)
    }

    private var sessionObjectIDs: [UUID: NSManagedObjectID] = [:]

    private func makeCoreDataSessionWithIncludedAttachment(sessionID: UUID) throws {
        let ctx = PersistenceController.shared.container.viewContext
        let session = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        // Every non-optional Session attribute must be set or `save()` throws
        // NSValidationMissingMandatoryProperty ("title is a required value").
        session.setValue(sessionID, forKey: "id")
        session.setValue(Date(), forKey: "timestamp")
        session.setValue("u2b fixture", forKey: "title")
        session.setValue(Int64(60), forKey: "durationSeconds")
        session.setValue(Int16(0), forKey: "activityType")
        session.setValue(false, forKey: "areNotesPrivate")
        session.setValue(Int16(5), forKey: "effort")
        session.setValue(Int16(5), forKey: "mood")
        session.setValue(true, forKey: "isPublic")

        let attID = UUID()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docs.appendingPathComponent("\(attID.uuidString).jpg")
        // A 1x1 JPEG is enough: the upload path only needs real bytes.
        let jpeg = Data(base64Encoded: "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==")!
        try jpeg.write(to: fileURL)
        scratchFiles.append(fileURL)

        let att = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: ctx)
        att.setValue(attID, forKey: "id")
        att.setValue(fileURL.path, forKey: "fileURL")
        // "image", NOT "photo" -- see the header note. `AttachmentKind` has no
        // "photo" case, and an unrecognised kind uploads as octet-stream, which
        // the bucket refuses.
        att.setValue("image", forKey: "kind")
        att.setValue(Date(), forKey: "createdAt")
        att.setValue(false, forKey: "isThumbnail")
        att.setValue(session, forKey: "session")

        try ctx.obtainPermanentIDs(for: [session, att])
        try ctx.save()
        coreDataObjects.append(contentsOf: [att, session])
        sessionObjectIDs[sessionID] = session.objectID

        // Attachments default to PRIVATE (`map[key] ?? true`); mark this one
        // explicitly INCLUDED, which is the condition under test.
        AttachmentPrivacy.setPrivate(id: attID, url: fileURL, false)
        privacyKeys.append((attID, fileURL))

        // Fixture preconditions. Without these a later "no object was uploaded"
        // assertion could pass because the fixture was never capable, not
        // because the gate worked.
        XCTAssertFalse(AttachmentPrivacy.isPrivate(id: attID, url: fileURL),
                       "fixture: the attachment must be marked INCLUDED")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
                      "fixture: the media file must exist on disk")
        let refetch = NSFetchRequest<NSManagedObject>(entityName: "Session")
        refetch.predicate = NSPredicate(format: "id == %@", sessionID as CVarArg)
        let found = (try? ctx.fetch(refetch))?.first
        let rel = found?.value(forKey: "attachments") as? Set<NSManagedObject>
        XCTAssertEqual(rel?.count, 1,
                       "fixture: the session must expose exactly one attachment through the relationship")
    }

    private func objectID(for sessionID: UUID) throws -> NSManagedObjectID {
        if let oid = sessionObjectIDs[sessionID] { return oid }
        return try throwawayObjectID()
    }

    private func throwawayObjectID() throws -> NSManagedObjectID {
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = PersistenceController.shared.container.persistentStoreCoordinator
        let model = PersistenceController.shared.container.managedObjectModel
        guard let name = (model.entities.first(where: { $0.name == "Session" }) ?? model.entities.first)?.name else {
            throw NSError(domain: "test", code: 1)
        }
        let o = NSEntityDescription.insertNewObject(forEntityName: name, into: ctx)
        let oid = o.objectID
        ctx.rollback()
        return oid
    }

    private static func payload(_ id: UUID, isPublic: Bool) -> SessionSyncQueue.PostPublishPayload {
        SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: id, sessionTimestamp: Date(), title: "u2b",
            durationSeconds: 60, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil,
            isPublic: isPublic, notes: nil, areNotesPrivate: false)
    }

    // MARK: - REST helpers

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
    private static func rest(_ path: String, _ method: String, _ body: [String: Any]? = nil) async -> (Int, Data) {
        var r = URLRequest(url: URL(string: baseURLString + "/" + path)!)
        r.httpMethod = method
        r.setValue(anonKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + mintJWT(sub: ownerUID), forHTTPHeaderField: "Authorization")
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        do { let (d, resp) = try await URLSession.shared.data(for: r)
             return ((resp as? HTTPURLResponse)?.statusCode ?? -1, d) }
        catch { return (-1, Data()) }
    }

    private static func postExists(_ id: UUID) async -> Bool {
        let (c, d) = await rest("rest/v1/posts?id=eq.\(id.uuidString)&select=id", "GET")
        guard c == 200, let rows = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return false }
        return !rows.isEmpty
    }

    private static func isPublic(_ id: UUID) async -> Bool? {
        let (c, d) = await rest("rest/v1/posts?id=eq.\(id.uuidString)&select=is_public", "GET")
        guard c == 200, let rows = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]],
              let f = rows.first else { return nil }
        return f["is_public"] as? Bool
    }

    private static func objectCount(prefix: String) async -> Int {
        let (c, d) = await rest("storage/v1/object/list/attachments", "POST",
                                ["prefix": prefix, "limit": 100])
        guard c == 200, let rows = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return -1 }
        return rows.count
    }
}
