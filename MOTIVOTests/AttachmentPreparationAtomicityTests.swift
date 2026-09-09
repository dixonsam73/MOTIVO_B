//
//  AttachmentPreparationAtomicityTests.swift
//  MOTIVOTests
//
//  PHASE 5 · C-65 — A PUBLISH MUST NOT REPORT SUCCESS WHILE SILENTLY OMITTING
//  AN ATTACHMENT THE MEMBER SELECTED.
//
//  LOCAL STACK ONLY. Skips if it is not reachable; no production is touched.
//
//  **THE POSITIVE CONTROL IS NOT OPTIONAL.** Asserting "no post row was created"
//  against a fixture that could never publish proves nothing — P4-U6 recorded
//  exactly that trap, where `kind: "photo"` made every upload 415 and the
//  negative assertion passed for the wrong reason. So a VALID PDF is proven to
//  publish through the JPEG representation path first, with the same wiring.
//

import XCTest
import CoreData
import CryptoKit
@testable import Etudes

@MainActor
final class AttachmentPreparationAtomicityTests: XCTestCase {

    private static let baseURLString = "http://127.0.0.1:54321"
    private static let jwtSecret = "super-secret-jwt-token-with-at-least-32-characters-long"
    private static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
        + "eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9."
        + "CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
    private static let ownerUID = "00000000-0000-0000-0000-0000000f0065"

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
            ok = (resp as? HTTPURLResponse).map { (200...499).contains($0.statusCode) } ?? false
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
        for id in postIDs {
            let (code, data) = await Self.rest(
                "storage/v1/object/list/attachments", "POST",
                ["prefix": "users/\(Self.ownerUID)/\(id.uuidString)", "limit": 100])
            if code == 200, let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                for r in rows where (r["name"] as? String) != nil {
                    _ = await Self.rest("storage/v1/object/attachments/users/\(Self.ownerUID)/\(id.uuidString)/\(r["name"] as! String)", "DELETE")
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

    // MARK: - PDF fixtures

    /// A real, renderable one-page PDF.
    private static func renderablePDF() -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        return renderer.pdfData { ctx in
            ctx.beginPage()
            UIColor.darkGray.setFill()
            ctx.cgContext.fill(CGRect(x: 20, y: 20, width: 160, height: 160))
        }
    }

    /// Structurally a PDF, but with NO PAGES — `/Count 0`. `generatePDFThumbnail`
    /// cannot render it, which is exactly C-65's preparation failure.
    private static func unrenderablePDF() -> Data {
        Data("""
        %PDF-1.4
        1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
        2 0 obj<</Type/Pages/Kids[]/Count 0>>endobj
        trailer<</Root 1 0 R>>
        %%EOF
        """.utf8)
    }

    // MARK: - THE POSITIVE CONTROL

    /// Without this the negative assertions are vacuous: it proves the fixture
    /// wiring, the PDF→JPEG representation path and the bucket all work.
    func test1_ValidPDFPublishesThroughTheJPEGRepresentation() async throws {
        try skipUnlessLocalStack()
        let id = UUID(); postIDs.append(id)
        try makeSessionWithIncludedPDF(sessionID: id, pdf: Self.renderablePDF())

        let result = await BackendEnvironment.shared.publish.uploadPost(Self.payload(id))

        guard case .success = result else {
            return XCTFail("POSITIVE CONTROL FAILED — a valid PDF must publish: \(result)")
        }
        let exists = await Self.postExists(id)
        XCTAssertTrue(exists, "positive control: the post row must exist")
        let refs = await Self.attachmentRefs(id)
        XCTAssertEqual(refs.count, 1, "positive control: exactly one attachment ref")
        XCTAssertEqual(refs.first?["kind"] as? String, "image",
                       "a PDF publishes as its JPEG representation")
        let objects = await Self.objectCount(prefix: "users/\(Self.ownerUID)/\(id.uuidString)")
        XCTAssertEqual(objects, 1, "positive control: exactly one storage object")
    }

    // MARK: - C-65 ITSELF

    /// **THE INVARIANT.** An attachment the member selected cannot be prepared,
    /// so the publish must not report complete success.
    ///
    /// **Against pre-fix code all three of these fail**, and that is the
    /// finding: `uploadPost` returned `.success`, the post row existed, and its
    /// `attachments` array was empty.
    func test2_UnpreparableAttachmentDoesNotPublishAPartialPost() async throws {
        try skipUnlessLocalStack()
        let id = UUID(); postIDs.append(id)
        try makeSessionWithIncludedPDF(sessionID: id, pdf: Self.unrenderablePDF())

        let result = await BackendEnvironment.shared.publish.uploadPost(Self.payload(id))

        if case .success = result {
            XCTFail("C-65: a publish that could not prepare a selected attachment reported SUCCESS")
        }
        let exists = await Self.postExists(id)
        XCTAssertFalse(exists, "C-65: no post row may be created when preparation fails")
        let objects = await Self.objectCount(prefix: "users/\(Self.ownerUID)/\(id.uuidString)")
        XCTAssertEqual(objects, 0, "C-65: no storage object may be uploaded when preparation fails")
    }

    /// The queue must keep the item rather than dequeue it as success.
    func test3_FailedPreparationLeavesTheItemQueued() async throws {
        try skipUnlessLocalStack()
        let id = UUID(); postIDs.append(id)
        try makeSessionWithIncludedPDF(sessionID: id, pdf: Self.unrenderablePDF())

        SessionSyncQueue.shared.enqueue(Self.payload(id))

        await SessionSyncQueue.shared.flushNow()

        XCTAssertTrue(SessionSyncQueue.shared.items.contains { $0.id == id },
                      "C-65: a failed publish must stay queued, not dequeue as success")
        let exists = await Self.postExists(id)
        XCTAssertFalse(exists, "C-65: and still no post row")
    }

    /// Retry must not duplicate anything — the 409-as-created branch,
    /// `x-upsert: true` and the idempotent PATCH must all survive the hoist.
    func test4_RetryOfAValidPublishIsIdempotent() async throws {
        try skipUnlessLocalStack()
        let id = UUID(); postIDs.append(id)
        try makeSessionWithIncludedPDF(sessionID: id, pdf: Self.renderablePDF())

        _ = await BackendEnvironment.shared.publish.uploadPost(Self.payload(id))
        let second = await BackendEnvironment.shared.publish.uploadPost(Self.payload(id))

        guard case .success = second else { return XCTFail("retry must succeed: \(second)") }
        let rows = await Self.postRowCount(id)
        XCTAssertEqual(rows, 1, "retry must not duplicate the post row")
        let objects = await Self.objectCount(prefix: "users/\(Self.ownerUID)/\(id.uuidString)")
        XCTAssertEqual(objects, 1, "retry must not duplicate the storage object")
        let refs = await Self.attachmentRefs(id)
        XCTAssertEqual(refs.count, 1, "retry must not duplicate the attachment ref")
    }

    // MARK: - Fixture

    private func makeSessionWithIncludedPDF(sessionID: UUID, pdf: Data) throws {
        let ctx = PersistenceController.shared.container.viewContext
        let session = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        session.setValue(sessionID, forKey: "id")
        session.setValue(Date(), forKey: "timestamp")
        session.setValue("c65 fixture", forKey: "title")
        session.setValue(Int64(60), forKey: "durationSeconds")
        session.setValue(Int16(0), forKey: "activityType")
        session.setValue(false, forKey: "areNotesPrivate")
        session.setValue(Int16(5), forKey: "effort")
        session.setValue(Int16(5), forKey: "mood")
        session.setValue(true, forKey: "isPublic")

        let attID = UUID()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docs.appendingPathComponent("\(attID.uuidString).pdf")
        try pdf.write(to: fileURL)
        scratchFiles.append(fileURL)

        let att = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: ctx)
        att.setValue(attID, forKey: "id")
        att.setValue(fileURL.path, forKey: "fileURL")
        att.setValue("pdf", forKey: "kind")
        att.setValue(Date(), forKey: "createdAt")
        att.setValue(false, forKey: "isThumbnail")
        att.setValue(session, forKey: "session")

        try ctx.obtainPermanentIDs(for: [session, att])
        try ctx.save()
        coreDataObjects.append(contentsOf: [att, session])

        AttachmentPrivacy.setPrivate(id: attID, url: fileURL, false)
        privacyKeys.append((attID, fileURL))

        XCTAssertFalse(AttachmentPrivacy.isPrivate(id: attID, url: fileURL),
                       "fixture: the attachment must be marked INCLUDED")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
                      "fixture: the PDF must exist on disk")
    }

    private static func payload(_ id: UUID) -> SessionSyncQueue.PostPublishPayload {
        SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: id, sessionTimestamp: Date(), title: "c65",
            durationSeconds: 60, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil,
            isPublic: true, notes: nil, areNotesPrivate: false)
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

    private static func rest(_ path: String, _ method: String, _ body: [String: Any]? = nil) async -> (Int, Data) {
        var r = URLRequest(url: URL(string: baseURLString + "/" + path)!)
        r.httpMethod = method
        r.setValue(anonKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + mintJWT(sub: ownerUID), forHTTPHeaderField: "Authorization")
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        guard let (d, resp) = try? await URLSession.shared.data(for: r) else { return (-1, Data()) }
        return ((resp as? HTTPURLResponse)?.statusCode ?? -1, d)
    }

    private static func postExists(_ id: UUID) async -> Bool { await postRowCount(id) > 0 }

    private static func postRowCount(_ id: UUID) async -> Int {
        let (c, d) = await rest("rest/v1/posts?id=eq.\(id.uuidString)&select=id", "GET")
        guard c == 200, let rows = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return 0 }
        return rows.count
    }

    private static func attachmentRefs(_ id: UUID) async -> [[String: Any]] {
        let (c, d) = await rest("rest/v1/posts?id=eq.\(id.uuidString)&select=attachments", "GET")
        guard c == 200, let rows = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]],
              let first = rows.first, let atts = first["attachments"] as? [[String: Any]] else { return [] }
        return atts
    }

    private static func objectCount(prefix: String) async -> Int {
        let (c, d) = await rest("storage/v1/object/list/attachments", "POST",
                                ["prefix": prefix, "limit": 100])
        guard c == 200, let rows = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return -1 }
        return rows.count
    }
}
