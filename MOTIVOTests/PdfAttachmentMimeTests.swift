//
//  PdfAttachmentMimeTests.swift
//  MOTIVOTests
//
//  PHASE 5 · P5-K / C-10 — CHARACTERISATION. THE PDF DEFECT DOES NOT EXIST.
//
//  C-10 predicted that a `.pdf` attachment uploads as
//  `application/octet-stream` and is refused. **MEASURED 2026-09-09: IT DOES
//  NOT, AND THERE IS NO PDF DEFECT.**
//
//  `contentType(for: "pdf", ext:)` does return `application/octet-stream` --
//  `pdf` falls to `default:`. But that value is **DISCARDED** for PDFs:
//  `prepareAttachmentForRemoteUpload` routes any `pdf` kind to
//  `preparePDFThumbnailForRemoteUpload`, which renders the PDF to a JPEG and
//  returns `contentType: "image/jpeg"`, `remoteKind: "image"`. The PDF itself
//  is never uploaded. So the computed content type for `pdf` is dead code on
//  this path, not a defect.
//
//  **THIS TEST NOW PINS THE MEASURED TRUTH** rather than the prediction, so the
//  behaviour cannot change silently: a shared PDF reaches other members as a
//  rendered thumbnail.
//
//  ── HOW THE FIXTURE ALMOST PRODUCED A FALSE POSITIVE ───────────────────────
//
//  The first fixture was a hand-written PDF stub with `/Count 0` -- no pages.
//  It could not be rendered, so the attachment was silently skipped, nothing
//  was uploaded, and `uploadPost` still returned SUCCESS. That looked like the
//  predicted defect and was not. **P4-U6's lesson exactly: its control failed
//  because the fixture set `kind: "photo"`, and the fixture was the finding.**
//
//  LOCAL STACK ONLY. No production state is touched.
//

import XCTest
import CoreData
import CryptoKit
import UIKit
@testable import Etudes

@MainActor
final class PdfAttachmentMimeTests: XCTestCase {

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
        for id in postIDs {
            let (code, data) = await Self.rest(
                "storage/v1/object/list/attachments", "POST",
                ["prefix": "users/\(Self.ownerUID)/\(id.uuidString)", "limit": 100])
            if code == 200,
               let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
                for r in rows {
                    guard let n = r["name"] as? String else { continue }
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
        try await super.tearDown()
    }

    // MARK: - THE UNIT UNDER TEST

    /// CHARACTERISATION: a PDF publishes as a rendered `image/jpeg` thumbnail.
    func testPdfAttachmentPublishesAsRenderedJpegThumbnail() async throws {
        try skipUnlessLocalStack()

        let id = UUID()
        postIDs.append(id)
        try makeSessionWithIncludedPDF(sessionID: id)

        let result = await BackendEnvironment.shared.publish.uploadPost(Self.payload(id))

        // P4 — the upload succeeds. PRE-FIX THIS FAILS with 415 InvalidMimeType,
        // which is the control.
        switch result {
        case .success:
            break
        case .failure(let error):
            XCTFail("PDF upload REFUSED — \(error); row=\(await Self.rowJSON(id))")
            return
        }

        // P6 — the post row carries a non-empty attachment reference.
        let attachments = await Self.attachmentsColumn(id)
        XCTAssertNotNil(attachments)
        XCTAssertFalse(attachments == "[]" || attachments == "",
                       "post published with an EMPTY attachments column — \(attachments ?? "nil"). " +
                       "`attachments: []` is also the schema default, so this is not proof of an empty selection (P4-U6 §4)")

        // P5 — THE STRONG ASSERTION: what the SERVER RECORDED, not what we sent.
        let recorded = await Self.recordedMimeTypes(prefix: "users/\(Self.ownerUID)/\(id.uuidString)")
        XCTAssertFalse(recorded.isEmpty, "no stored object found for the post")
        // THE MEASURED TRUTH, not the prediction. The prediction said
        // `application/pdf`; the server recorded `image/jpeg`, because the PDF
        // is uploaded as a rendered thumbnail. Asserting the measurement is what
        // makes this a characterisation test rather than a wish.
        XCTAssertEqual(recorded, ["image/jpeg"],
                       "a shared PDF is expected to reach storage as a rendered JPEG thumbnail; " +
                       "if this changes, C-10's disposition must be revisited")
    }

    /// P7/P8 — the other mappings are untouched by this unit. Asserted through
    /// the same server-recorded route, so it is the same class of evidence.
    func testImageMappingUnchanged() async throws {
        try skipUnlessLocalStack()

        let id = UUID()
        postIDs.append(id)
        try makeSessionWithIncludedJPEG(sessionID: id)

        let result = await BackendEnvironment.shared.publish.uploadPost(Self.payload(id))
        guard case .success = result else {
            return XCTFail("image upload regressed: \(result)")
        }
        let recorded = await Self.recordedMimeTypes(prefix: "users/\(Self.ownerUID)/\(id.uuidString)")
        XCTAssertEqual(recorded, ["image/jpeg"], "image mapping must be unchanged by the PDF fix")
    }

    // MARK: - Fixtures

    private func makeSession(_ sessionID: UUID, title: String) -> NSManagedObject {
        let ctx = PersistenceController.shared.container.viewContext
        let session = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        session.setValue(sessionID, forKey: "id")
        session.setValue(Date(), forKey: "timestamp")
        session.setValue(title, forKey: "title")
        session.setValue(Int64(60), forKey: "durationSeconds")
        session.setValue(Int16(0), forKey: "activityType")
        session.setValue(false, forKey: "areNotesPrivate")
        session.setValue(Int16(5), forKey: "effort")
        session.setValue(Int16(5), forKey: "mood")
        session.setValue(true, forKey: "isPublic")
        return session
    }

    private func attach(_ session: NSManagedObject, kind: AttachmentKind, ext: String, bytes: Data) throws {
        let ctx = PersistenceController.shared.container.viewContext
        let attID = UUID()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = docs.appendingPathComponent("\(attID.uuidString).\(ext)")
        try bytes.write(to: fileURL)
        scratchFiles.append(fileURL)

        let att = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: ctx)
        att.setValue(attID, forKey: "id")
        att.setValue(fileURL.path, forKey: "fileURL")
        att.setValue(kind.rawValue, forKey: "kind")
        att.setValue(Date(), forKey: "createdAt")
        att.setValue(false, forKey: "isThumbnail")
        att.setValue(session, forKey: "session")

        try ctx.obtainPermanentIDs(for: [session, att])
        try ctx.save()
        coreDataObjects.append(contentsOf: [att, session])

        AttachmentPrivacy.setPrivate(id: attID, url: fileURL, false)
        privacyKeys.append((attID, fileURL))
    }

    /// A REAL, RENDERABLE, one-page PDF, produced by UIKit rather than
    /// hand-written.
    ///
    /// **THE FIRST VERSION OF THIS FIXTURE WAS A HAND-WRITTEN STUB WITH
    /// `/Count 0` — NO PAGES — AND IT MADE THE CONTROL FAIL FOR THE WRONG
    /// REASON.** The publish path renders a PDF to a thumbnail, so an
    /// unrenderable PDF is silently skipped and nothing is uploaded at all.
    /// That is P4-U6's lesson repeating: its control failed because the fixture
    /// set `kind: "photo"`, and the fixture was the finding.
    private func makeSessionWithIncludedPDF(sessionID: UUID) throws {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let pdf = renderer.pdfData { ctx in
            ctx.beginPage()
            UIColor.darkGray.setFill()
            ctx.cgContext.fill(CGRect(x: 40, y: 40, width: 120, height: 120))
        }
        try attach(makeSession(sessionID, title: "c-10 pdf fixture"),
                   kind: .pdf, ext: "pdf", bytes: pdf)
    }

    private func makeSessionWithIncludedJPEG(sessionID: UUID) throws {
        let jpeg = Data(base64Encoded: "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==")!
        try attach(makeSession(sessionID, title: "c-10 image control"),
                   kind: .image, ext: "jpg", bytes: jpeg)
    }

    // MARK: - Plumbing

    private static func payload(_ id: UUID) -> SessionSyncQueue.PostPublishPayload {
        SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: id, sessionTimestamp: Date(), title: "c-10",
            durationSeconds: 60, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil,
            isPublic: true, notes: nil, areNotesPrivate: false)
    }

    /// Server-recorded content types for every object under `prefix`.
    /// Supabase Storage returns the stored object's own `metadata`, so this is
    /// what the SERVER holds rather than what the client claimed.
    private static func recordedMimeTypes(prefix: String) async -> [String] {
        let (c, d) = await rest("storage/v1/object/list/attachments", "POST",
                                ["prefix": prefix, "limit": 100])
        guard c == 200,
              let rows = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]]
        else { return [] }
        return rows.compactMap { row in
            guard let meta = row["metadata"] as? [String: Any] else { return nil }
            return (meta["mimetype"] as? String) ?? (meta["contentType"] as? String)
        }
    }

    private static func attachmentsColumn(_ id: UUID) async -> String? {
        let (c, d) = await rest("rest/v1/posts?id=eq.\(id.uuidString)&select=attachments", "GET")
        guard c == 200 else { return "http \(c)" }
        return String(data: d, encoding: .utf8)
    }

    private static func rowJSON(_ id: UUID) async -> String {
        let (c, d) = await rest("rest/v1/posts?id=eq.\(id.uuidString)&select=title,is_public,attachments", "GET")
        guard c == 200 else { return "http \(c)" }
        return String(data: d, encoding: .utf8) ?? "nil"
    }

    @discardableResult
    private static func rest(_ path: String, _ method: String,
                             _ body: [String: Any]? = nil) async -> (Int, Data) {
        var r = URLRequest(url: URL(string: baseURLString + "/" + path)!)
        r.httpMethod = method
        r.setValue(anonKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + mintJWT(sub: ownerUID), forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { r.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        guard let (d, resp) = try? await URLSession.shared.data(for: r) else { return (-1, Data()) }
        return ((resp as? HTTPURLResponse)?.statusCode ?? -1, d)
    }

    private static func mintJWT(sub: String) -> String {
        func b64(_ d: Data) -> String {
            d.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = b64(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
        let exp = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let payload = b64(Data("{\"sub\":\"\(sub)\",\"role\":\"authenticated\",\"aud\":\"authenticated\",\"exp\":\(exp)}".utf8))
        let signing = "\(header).\(payload)"
        let sig = HMAC<SHA256>.authenticationCode(for: Data(signing.utf8),
                                                  using: SymmetricKey(data: Data(jwtSecret.utf8)))
        return "\(signing).\(b64(Data(sig)))"
    }
}
