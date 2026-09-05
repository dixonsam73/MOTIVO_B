//
//  StalePathQueuedPublishTests.swift
//  MOTIVOTests
//
//  PHASE 4 · P4-U6 — C-51 RUNTIME VERIFICATION BY FAULT INJECTION.
//
//  C-51 is coverage, not a behavioural defect. The ONE route that can still
//  reach upload selection with stale paths is a publish enqueued in
//  `SessionSyncQueue` that flushes AFTER the container rotates:
//
//    * the queue is file-backed under the backup-EXCLUDED
//      `Application Support/MOTIVO/`, so it survives process death but NOT a
//      restore -- rotation is the only producer;
//    * `PostPublishPayload` carries `sessionID` and NO path, so the flush
//      re-reads Core Data and meets whatever `fileURL` holds at flush time;
//    * `loadIncludedAttachments` SILENTLY skips an unresolved path, so the
//      post arrives with its media missing and nothing reports it.
//
//  THE FAULT INJECTED IS THE ROTATION ITSELF: the persisted `fileURL` has its
//  container UUID replaced between enqueue and flush, while the real bytes stay
//  where they are. That is exactly what an in-place app update does.
//
//  LOCAL STACK ONLY.
//

import XCTest
import CoreData
import CryptoKit
@testable import Etudes

@MainActor
final class StalePathQueuedPublishTests: XCTestCase {

    private static let baseURLString = "http://127.0.0.1:54321"
    private static let offlineURL = URL(string: "http://127.0.0.1:9")!
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
    private var sessionObjectIDs: [UUID: NSManagedObjectID] = [:]

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
        for id in postIDs {
            let (code, data) = await Self.rest(
                "storage/v1/object/list/attachments", "POST",
                ["prefix": "users/\(Self.ownerUID)/\(id.uuidString)", "limit": 100])
            if code == 200,
               let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                for r in rows where r["name"] is String {
                    let n = r["name"] as! String
                    _ = await Self.rest("storage/v1/object/attachments/users/\(Self.ownerUID)/\(id.uuidString)/\(n)", "DELETE")
                }
            }
            _ = await Self.rest("rest/v1/posts?id=eq.\(id.uuidString)", "DELETE")
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

    // MARK: - P4. THE RESOLVER DISCRIMINATOR — pure, no stack, no fixture
    //
    // This is what makes the end-to-end result attributable to the fix rather
    // than to the harness. `preU2Resolve` replicates the pre-Phase-2 semantics
    // named in `BackendShim.resolveLocalFileURL`'s own header: any stored value
    // containing a slash was returned VERBATIM. The caller's `fileExists` check
    // then fails and the attachment is silently skipped.

    private func preU2Resolve(_ stored: String) -> URL? {
        stored.contains("/") ? URL(fileURLWithPath: stored) : nil
    }

    func testPreU2ResolverMissesWhatTheCanonicalResolverRecovers() throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = "\(UUID().uuidString).jpg"
        let real = docs.appendingPathComponent(name)
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: real)
        defer { try? FileManager.default.removeItem(at: real) }

        let stale = Self.rotateContainer(of: real).path
        XCTAssertNotEqual(stale, real.path, "precondition: the injected path really did change")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale),
                       "precondition: nothing exists at the rotated path")

        // PRE-FIX: returns the stale path verbatim -> caller's fileExists fails -> SKIP.
        let pre = preU2Resolve(stale)
        XCTAssertNotNil(pre, "pre-U2 returned a URL (it never returned nil for a path)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: pre!.path),
                       "PRE-FIX: the returned path does not exist, so the attachment is skipped")

        // POST-FIX: recovers by filename within the eligible permanent locations.
        let post = AttachmentPathResolver.resolve(stale)
        XCTAssertNotNil(post, "POST-FIX: the canonical resolver recovers the file")
        XCTAssertEqual(post?.standardizedFileURL.path, real.standardizedFileURL.path,
                       "…and recovers the RIGHT file, in the current container")
    }

    // MARK: - P1/P2/P3/P5. THE QUEUED ROUTE, END TO END

    /// P1 is a POSITIVE CONTROL and is asserted first, deliberately.
    ///
    /// An earlier revision of `SharedOnlyUploadTests` recorded that this exact
    /// fixture shape once produced `attachments: []` on a Share-ON publish, for
    /// reasons never established. If that recurs, P1 fails LOUDLY here rather
    /// than letting P2 pass vacuously — a stale-path case that uploads nothing
    /// and a working case that uploads nothing are indistinguishable without it.
    func testQueuedSharedPublishSurvivesContainerRotation() async throws {
        try skipUnlessLocalStack()

        // ---------- P1. control: correct path, online, uploads its object
        let controlID = UUID(); postIDs.append(controlID)
        let control = try makeSessionWithIncludedAttachment(sessionID: controlID)
        await Self.publish(Self.payload(controlID), oid: try objectID(for: controlID))
        await Self.settle()

        let controlRow = await Self.postExists(controlID)
        let controlObjects = await Self.objectCount(prefix: "users/\(Self.ownerUID)/\(controlID.uuidString)")
        XCTAssertTrue(controlRow, "P1: the control publish created its row")
        let controlAttachmentsColumn = await Self.attachmentsColumn(controlID) ?? "nil"
        XCTAssertEqual(controlObjects, 1,
                       "P1 POSITIVE CONTROL: this fixture CAN upload its attachment. "
                       + "If this is 0 the fixture never reaches Storage and P2 below proves nothing. "
                       + "attachments column = \(controlAttachmentsColumn)")
        _ = control

        // ---------- P2. THE C-51 CONDITION
        let staleID = UUID(); postIDs.append(staleID)
        let fx = try makeSessionWithIncludedAttachment(sessionID: staleID)

        // offline: the publish becomes a durable queued intent
        NetworkManager.shared.baseURL = Self.offlineURL
        await Self.publish(Self.payload(staleID), oid: try objectID(for: staleID))
        await Self.settle()
        XCTAssertTrue(SessionSyncQueue.shared.items.contains { $0.id == staleID && $0.op == .publish },
                      "P2 precondition: the .publish intent is queued while offline")

        // P5 — the intent survives decode from the REAL queue file, so the route
        // is exercised through disk rather than through in-memory state.
        let onDisk = try Data(contentsOf: Self.queueFile)
        let reconstructed = try JSONDecoder().decode([SessionSyncQueue.PostPublishPayload].self, from: onDisk)
        XCTAssertTrue(reconstructed.contains { $0.id == staleID && $0.op == .publish },
                      "P5: the queued .publish survives reconstruction FROM DISK")

        // >>> THE FAULT: the container rotates while the publish sits in the queue.
        //     The bytes do not move; only the persisted path becomes stale.
        let stale = Self.rotateContainer(of: fx.fileURL)
        fx.attachment.setValue(stale.path, forKey: "fileURL")
        try PersistenceController.shared.container.viewContext.save()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path),
                       "fault injected: the persisted path no longer exists")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fx.fileURL.path),
                      "…while the real bytes are still in the current container")

        // reconnect and flush ONLY. The member never touches the session again,
        // so the editor's self-healing save cannot run.
        NetworkManager.shared.baseURL = URL(string: Self.baseURLString)
        await SessionSyncQueue.shared.flushNow()
        await Self.settle()

        let staleRow = await Self.postExists(staleID)
        let staleObjects = await Self.objectCount(prefix: "users/\(Self.ownerUID)/\(staleID.uuidString)")
        let staleAttachmentsColumn = await Self.attachmentsColumn(staleID) ?? "nil"
        XCTAssertTrue(staleRow, "P2: the queued publish still creates its row after rotation")
        XCTAssertEqual(staleObjects, 1,
                       "P2 — C-51: the attachment SURVIVES container rotation on the queued route. "
                       + "0 here is the silent-skip defect: post published, media missing, no error.")

        // ---------- P3. the assertion can SEE a skip
        let goneID = UUID(); postIDs.append(goneID)
        let gone = try makeSessionWithIncludedAttachment(sessionID: goneID)
        let goneStale = Self.rotateContainer(of: gone.fileURL)
        gone.attachment.setValue(goneStale.path, forKey: "fileURL")
        try PersistenceController.shared.container.viewContext.save()
        try FileManager.default.removeItem(at: gone.fileURL)   // unrecoverable: nowhere eligible

        await Self.publish(Self.payload(goneID), oid: try objectID(for: goneID))
        await Self.settle()

        let goneRow = await Self.postExists(goneID)
        let goneObjects = await Self.objectCount(prefix: "users/\(Self.ownerUID)/\(goneID.uuidString)")
        XCTAssertTrue(goneRow, "P3: an unresolvable attachment does not block the publish")
        XCTAssertEqual(goneObjects, 0,
                       "P3 DISCRIMINATOR: when resolution genuinely fails the count IS 0, "
                       + "so P2's 1 is a measurement and not a property of the harness")
    }

    // MARK: - Fixture

    private struct Fixture { let attachment: NSManagedObject; let fileURL: URL; let attID: UUID }

    /// Replaces the container UUID while preserving `Documents/<filename>`.
    /// `<...>/Application/<containerUUID>/Documents/<name>` — exactly the shape
    /// an in-place app update produces.
    private static func rotateContainer(of url: URL) -> URL {
        let name = url.lastPathComponent
        let documents = url.deletingLastPathComponent()          // .../<container>/Documents
        let container = documents.deletingLastPathComponent()    // .../<container>
        return container
            .deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(documents.lastPathComponent, isDirectory: true)
            .appendingPathComponent(name)
    }

    private func makeSessionWithIncludedAttachment(sessionID: UUID) throws -> Fixture {
        let ctx = PersistenceController.shared.container.viewContext
        let session = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        session.setValue(sessionID, forKey: "id")
        session.setValue(Date(), forKey: "timestamp")
        session.setValue("u6 c-51 fixture", forKey: "title")
        session.setValue(Int64(60), forKey: "durationSeconds")
        session.setValue(Int16(0), forKey: "activityType")
        session.setValue(false, forKey: "areNotesPrivate")
        session.setValue(Int16(5), forKey: "effort")
        session.setValue(Int16(5), forKey: "mood")
        session.setValue(true, forKey: "isPublic")

        let attID = UUID()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docs.appendingPathComponent("\(attID.uuidString).jpg")
        let jpeg = Data(base64Encoded: "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==")!
        try jpeg.write(to: fileURL)
        scratchFiles.append(fileURL)

        let att = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: ctx)
        att.setValue(attID, forKey: "id")
        att.setValue(fileURL.path, forKey: "fileURL")
        // "image", NOT "photo". `AttachmentKind` is audio|video|image|file|pdf,
        // and `BackendShim.contentType(for:ext:)` maps anything else to
        // application/octet-stream, which the attachments bucket REJECTS with
        // 415 InvalidMimeType. A "photo" fixture therefore fails to upload for a
        // reason that has nothing to do with what is under test.
        att.setValue(AttachmentKind.image.rawValue, forKey: "kind")
        att.setValue(Date(), forKey: "createdAt")
        att.setValue(false, forKey: "isThumbnail")
        att.setValue(session, forKey: "session")

        try ctx.obtainPermanentIDs(for: [session, att])
        try ctx.save()
        coreDataObjects.append(contentsOf: [att, session])
        sessionObjectIDs[sessionID] = session.objectID

        AttachmentPrivacy.setPrivate(id: attID, url: fileURL, false)
        privacyKeys.append((attID, fileURL))

        return Fixture(attachment: att, fileURL: fileURL, attID: attID)
    }

    // MARK: - Plumbing

    private static var queueFile: URL {
        let dir = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
            .appendingPathComponent("MOTIVO", isDirectory: true)
        return dir.appendingPathComponent("SessionSyncQueue_v1.json")
    }

    private static func settle() async { try? await Task.sleep(nanoseconds: 3_000_000_000) }

    private static func publish(_ p: SessionSyncQueue.PostPublishPayload, oid: NSManagedObjectID) async {
        PublishService.shared.publish(payload: p, objectID: oid, shouldPublish: p.isPublic)
    }

    private func objectID(for sessionID: UUID) throws -> NSManagedObjectID {
        if let oid = sessionObjectIDs[sessionID] { return oid }
        throw NSError(domain: "test", code: 2)
    }

    private static func payload(_ id: UUID) -> SessionSyncQueue.PostPublishPayload {
        SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: id, sessionTimestamp: Date(), title: "u6",
            durationSeconds: 60, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil,
            isPublic: true, notes: nil, areNotesPrivate: false)
    }

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

    /// Diagnostic only — names the cause when P1 fails.
    private static func attachmentsColumn(_ id: UUID) async -> String? {
        let (c, d) = await rest("rest/v1/posts?id=eq.\(id.uuidString)&select=attachments", "GET")
        guard c == 200 else { return "http \(c)" }
        return String(data: d, encoding: .utf8)
    }

    /// Diagnostic: how far did uploadPost get? `title` is written by
    /// patchPostMetadata, which runs BEFORE the attachment block.
    private static func rowJSON(_ id: UUID) async -> String {
        let (c, d) = await rest("rest/v1/posts?id=eq.\(id.uuidString)&select=title,notes,is_public,attachments", "GET")
        guard c == 200 else { return "http \(c)" }
        return String(data: d, encoding: .utf8) ?? "nil"
    }

    private static func objectCount(prefix: String) async -> Int {
        let (c, d) = await rest("storage/v1/object/list/attachments", "POST",
                                ["prefix": prefix, "limit": 100])
        guard c == 200, let rows = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return -1 }
        return rows.count
    }
}

// MARK: - FIXTURE INTEGRITY GUARDS
//
// `SharedOnlyUploadTests` recorded that this fixture shape once published with
// `attachments: []` and left the cause UNESTABLISHED. It blocked C-51's
// end-to-end verification, so it was diagnosed rather than worked around.
//
// THE CAUSE WAS THE FIXTURE, NOT THE PRODUCT: it set `kind: "photo"`, and
// `AttachmentKind` is audio|video|image|file|pdf. `contentType(for:ext:)` maps
// any unrecognised kind to `application/octet-stream`, which is absent from the
// attachments bucket's `allowed_mime_types` -- so Storage answered 415
// InvalidMimeType, `uploadPost` returned failure, and the row kept its default
// empty `attachments`. Production carries the IDENTICAL mime restriction, so
// the local stack was faithful and the fixture was simply wrong.
//
// These two guards replicate `loadIncludedAttachments` stage by stage, before
// and after a real publish, so the same silent fixture rot cannot return and be
// mistaken for a product defect a second time.

extension StalePathQueuedPublishTests {

    func testFixtureReachesLoadIncludedAttachmentsCleanly() throws {
        let sessionID = UUID()
        let fx = try makeSessionWithIncludedAttachment(sessionID: sessionID)
        postIDs.append(sessionID)

        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Session")
        request.predicate = NSPredicate(format: "id == %@", sessionID as CVarArg)
        request.fetchLimit = 1

        let fetched = (try? context.fetch(request))?.first
        guard let session = fetched else { return XCTFail("stage 1: Session not fetched by id") }

        let raw = session.value(forKey: "attachments")
        let asSet = raw as? Set<NSManagedObject>

        let attachments = asSet ?? []
        for a in attachments {
            let id = a.value(forKey: "id") as? UUID
            let path = a.value(forKey: "fileURL") as? String
            let kind = a.value(forKey: "kind") as? String
            let resolved = AttachmentPathResolver.resolve(path)
            let exists = resolved.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            let priv = AttachmentPrivacy.isPrivate(id: id, url: resolved)
        }

        XCTAssertNotNil(asSet, "stage 2: `attachments` did not cast to Set<NSManagedObject>")
        XCTAssertEqual(attachments.count, 1, "stage 2: the fixture's attachment is on the relationship")

        // Stages 3-5, each asserted so a failure NAMES the stage that drops it.
        guard let a = attachments.first else { return XCTFail("no attachment") }
        let id = a.value(forKey: "id") as? UUID
        let path = a.value(forKey: "fileURL") as? String
        XCTAssertNotNil(id, "stage 3: attachment has an id")
        XCTAssertNotNil(path, "stage 3: attachment has a fileURL")
        let resolved = AttachmentPathResolver.resolve(path)
        XCTAssertNotNil(resolved, "stage 4: the path resolves")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved?.path ?? ""),
                      "stage 4: the resolved file exists")
        XCTAssertFalse(AttachmentPrivacy.isPrivate(id: id, url: resolved),
                       "stage 5: the attachment is INCLUDED (not private). "
                       + "isPrivate fails CLOSED, so a key miss here silently drops it from publish.")
        _ = fx
    }

    /// Re-inspects the SAME fixture immediately AFTER a real publish, so the
    /// failing stage is named rather than guessed. If every stage still holds
    /// here while the row carries `attachments: []`, the fixture is sound and
    /// the divergence is inside `uploadPost`'s own call.
    func testPublishThenReinspectFixture() async throws {
        try skipUnlessLocalStack()
        let sessionID = UUID(); postIDs.append(sessionID)
        let fx = try makeSessionWithIncludedAttachment(sessionID: sessionID)

        await Self.publish(Self.payload(sessionID), oid: try objectID(for: sessionID))
        await Self.settle()

        let col = await Self.attachmentsColumn(sessionID) ?? "nil"
        let meta = await Self.rowJSON(sessionID)
        let stillQueued = SessionSyncQueue.shared.items.contains { $0.id == sessionID }
        let objects = await Self.objectCount(prefix: "users/\(Self.ownerUID)/\(sessionID.uuidString)")

        // Re-run every stage AFTER the publish.
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Session")
        request.predicate = NSPredicate(format: "id == %@", sessionID as CVarArg)
        request.fetchLimit = 1
        let session = (try? context.fetch(request))?.first

        let set = session?.value(forKey: "attachments") as? Set<NSManagedObject>
        let a = set?.first
        let id = a?.value(forKey: "id") as? UUID
        let path = a?.value(forKey: "fileURL") as? String
        let resolved = AttachmentPathResolver.resolve(path)
        let exists = resolved.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let priv = AttachmentPrivacy.isPrivate(id: id, url: resolved)

        let report = "AFTER PUBLISH — sessionFetched=\(session != nil) "
            + "relCast=\(set != nil) relCount=\(set?.count ?? -1) "
            + "hasID=\(id != nil) resolved=\(resolved != nil) exists=\(exists) isPrivate=\(priv) "
            + "| server attachments=\(col) objects=\(objects) stillQueued=\(stillQueued) row=\(meta)"

        XCTAssertNotNil(session, report)
        XCTAssertEqual(set?.count, 1, report)
        XCTAssertNotNil(resolved, report)
        XCTAssertTrue(exists, report)
        XCTAssertFalse(priv, report)
        XCTAssertEqual(objects, 1, report)
        _ = fx
    }
}
