//
//  OmissionIdentityTests.swift
//  MOTIVOTests
//
//  C-82 (REOPENED) — THE CONSENT LIST MUST NAME THE ATTACHMENT THE FLUSH SEES.
//
//  The member chooses "Share Without It" against a STAGED attachment id (A).
//  Saving creates a NEW attachment with a NEW id (B) — `AttachmentStore
//  .addAttachment` mints it — and the flush selects attachments by their SAVED
//  ids. So an omission for A matched nothing, and on Device B the omitted WAV
//  was converted. The previous tests used arbitrary ids: they proved the list
//  was carried, never that it named the right thing.
//
//  **These tests check identity, not carriage:** A becomes B before queueing, the
//  queue FILE carries B and not A, and a real flush skips B and never prepares
//  it. An attachment saved before editing (P) keeps its id.
//
//  **The editors cannot be driven from XCTest** — their staged attachments live
//  in SwiftUI `@State` — so each editor's wiring is pinned structurally, and the
//  chain after it runs on the real store, the real queue file and a real flush.
//
//  Flush tests: LOCAL STACK ONLY, skipped if it is not reachable.
//  Structural tests: **CODE ONLY — COMMENTS ARE STRIPPED FIRST** (`U5c-34`).
//

import XCTest
import CoreData
import CryptoKit
@testable import Etudes

@MainActor
final class OmissionIdentityTests: XCTestCase {

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

    // MARK: - Fixture

    private struct Saved {
        let sessionID: UUID
        /// The id the consent dialog saw.
        let stagedA: UUID
        /// The id the save minted for that attachment.
        let finalB: UUID
        /// An attachment saved BEFORE this edit began.
        let persistedP: UUID
    }

    /// A saved session holding P (saved before editing) and B (just created from
    /// staged A). **Both are WAVs that cannot be converted**, so if the flush
    /// ever selects either for preparation the publish FAILS — which is what
    /// makes "skipped" observable rather than inferred from a missing log line.
    private func makeSavedSession() throws -> Saved {
        let ctx = PersistenceController.shared.container.viewContext
        guard let session = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx) as? Session else {
            throw XCTSkip("fixture: Session entity unavailable")
        }
        let sessionID = UUID()
        session.setValue(sessionID, forKey: "id")
        session.setValue(Date(), forKey: "timestamp")
        session.setValue("c82 fixture", forKey: "title")
        session.setValue(Int64(60), forKey: "durationSeconds")
        session.setValue(Int16(0), forKey: "activityType")
        session.setValue(false, forKey: "areNotesPrivate")
        session.setValue(Int16(5), forKey: "effort")
        session.setValue(Int16(5), forKey: "mood")
        session.setValue(true, forKey: "isPublic")
        coreDataObjects.append(session)

        let persistedP = try addUnconvertibleWAV(to: session, ctx: ctx)
        let stagedA = UUID()
        let finalB = try addUnconvertibleWAV(to: session, ctx: ctx)

        try ctx.obtainPermanentIDs(for: coreDataObjects)
        try ctx.save()
        return Saved(sessionID: sessionID, stagedA: stagedA, finalB: finalB, persistedP: persistedP)
    }

    /// Through the REAL save path, so the id is the one `addAttachment` mints.
    private func addUnconvertibleWAV(to session: Session, ctx: NSManagedObjectContext) throws -> UUID {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("c82-\(UUID().uuidString).wav")
        try Data(repeating: 0x5A, count: 4096).write(to: url)
        scratchFiles.append(url)
        let att = try AttachmentStore.addAttachment(kind: .audio, filePath: url.path, to: session,
                                                    isThumbnail: false, ctx: ctx)
        coreDataObjects.append(att)
        guard let id = att.value(forKey: "id") as? UUID else {
            throw XCTSkip("fixture: addAttachment minted no id")
        }
        AttachmentPrivacy.setPrivate(id: id, url: url, false)
        privacyKeys.append((id, url))
        XCTAssertFalse(AttachmentPrivacy.isPrivate(id: id, url: url), "fixture: the WAV must be INCLUDED")
        return id
    }

    private func translated(_ f: Saved) -> [UUID]? {
        ConnectedSharePreflight.persistedOmissions([f.stagedA, f.persistedP],
                                                   stagedToFinal: [f.stagedA: f.finalB])
    }

    private static func payload(_ id: UUID, omissions: [UUID]?) -> SessionSyncQueue.PostPublishPayload {
        SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: id, sessionTimestamp: Date(), title: "c82",
            durationSeconds: 60, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil,
            isPublic: true, notes: nil, areNotesPrivate: false,
            authorisedOmissions: omissions)
    }

    /// What a relaunch reads.
    private func decodedQueueFile() throws -> [SessionSyncQueue.PostPublishPayload] {
        try JSONDecoder().decode([SessionSyncQueue.PostPublishPayload].self,
                                 from: Data(contentsOf: SessionSyncQueue.makeFileURL()))
    }

    // MARK: - Identity (real store, no network)

    /// A → B before queueing; P is not remapped; no consent stays no list.
    func testStagedOmissionBecomesTheSavedIDAndAPersistedOneKeepsItsID() throws {
        let f = try makeSavedSession()
        XCTAssertNotEqual(f.finalB, f.stagedA, "premise: the save mints its own id")

        let out = translated(f)
        XCTAssertEqual(out, [f.finalB, f.persistedP], "A must become B, and P must stay P")
        XCTAssertFalse(out?.contains(f.stagedA) ?? false, "the staged id must not reach the payload")
        XCTAssertNil(ConnectedSharePreflight.persistedOmissions([], stagedToFinal: [f.stagedA: f.finalB]),
                     "no consent → no omission list, as before")
    }

    /// The queue FILE carries B, not A, after re-decode.
    func testQueueFileCarriesTheSavedIDAfterRedecode() throws {
        let f = try makeSavedSession()
        SessionSyncQueue.shared.enqueue(Self.payload(f.sessionID, omissions: translated(f)))

        let fromDisk = try decodedQueueFile().first { $0.id == f.sessionID }
        XCTAssertEqual(fromDisk?.authorisedOmissions, [f.finalB, f.persistedP],
                       "persistence and re-decode must preserve the SAVED ids")
        XCTAssertFalse(fromDisk?.authorisedOmissions?.contains(f.stagedA) ?? false,
                       "the queued file must not name the staged id")
    }

    // MARK: - The flush (local stack)

    /// **THE DEVICE FAILURE, REPRODUCED — and the control.** Consent recorded
    /// against the STAGED id matches nothing, so the flush selects B, tries to
    /// convert it and fails. Passes before and after the fix: it proves the
    /// fixture WOULD be prepared if it were not skipped.
    func testUntranslatedStagedIDIsNotMatchedAtFlush() async throws {
        try skipUnlessLocalStack()
        let f = try makeSavedSession(); postIDs.append(f.sessionID)

        let result = await BackendEnvironment.shared.publish.uploadPost(
            Self.payload(f.sessionID, omissions: [f.stagedA, f.persistedP]))

        if case .success = result {
            XCTFail("CONTROL FAILED — B was not selected for preparation, so the skip test below proves nothing")
        }
        let exists = await Self.postExists(f.sessionID)
        XCTAssertFalse(exists, "preparation fails before the post row (C-65)")
    }

    /// **THE C-82 INVARIANT, END TO END.** Translated consent, from the decoded
    /// queue file through a real flush: B and P are skipped, never prepared, and
    /// the post publishes with no media.
    func testFlushSkipsTheSavedIDAndNeverPreparesIt() async throws {
        try skipUnlessLocalStack()
        let f = try makeSavedSession(); postIDs.append(f.sessionID)
        SessionSyncQueue.shared.enqueue(Self.payload(f.sessionID, omissions: translated(f)))

        guard let fromDisk = try decodedQueueFile().first(where: { $0.id == f.sessionID }) else {
            return XCTFail("the item must be in the queue file")
        }
        SessionSyncQueue.shared.clear()
        SessionSyncQueue.shared.enqueue(fromDisk)
        await SessionSyncQueue.shared.flushNow()

        XCTAssertFalse(SessionSyncQueue.shared.items.contains { $0.id == f.sessionID },
                       "the flush failed — an omitted, unconvertible WAV was selected for preparation")
        let exists = await Self.postExists(f.sessionID)
        XCTAssertTrue(exists, "the post publishes without the omitted media")
        let objects = await Self.objectCount(prefix: "users/\(Self.ownerUID)/\(f.sessionID.uuidString)")
        XCTAssertEqual(objects, 0, "nothing omitted may be uploaded")
        let refs = await Self.attachmentRefs(f.sessionID)
        XCTAssertEqual(refs.count, 0, "and no attachment ref is written")
    }

    // MARK: - The editors (structural — their staged state is SwiftUI @State)

    private let editors = [
        (view: "AddEditSessionView.swift", commit: "AddEditSessionView+Attachments.swift"),
        (view: "PostRecordDetailsView.swift", commit: "PostRecordDetailsView+Attachments.swift"),
    ]

    /// Each save keeps the map its own commit returns and passes the consent
    /// through the one shared helper.
    func testBothEditorsTranslateConsentThroughTheSharedHelper() {
        for e in editors {
            XCTAssertTrue(code(e.view).contains("let stagedToFinal = commitStagedAttachments(to: s, ctx: viewContext)"),
                          "\(e.view): the save must keep the map its commit returns")
            let payloads = constructions().filter { $0.file == e.view }
            XCTAssertEqual(payloads.count, 1, "\(e.view): exactly one payload construction")
            XCTAssertTrue(payloads.first?.args.contains(
                "authorisedOmissions: ConnectedSharePreflight.persistedOmissions(authorisedOmissions, stagedToFinal: stagedToFinal)") ?? false,
                "\(e.view): the payload must carry the TRANSLATED consent")
        }
    }

    /// **THE BYPASS GUARD.** Across the app, a payload's consent comes from the
    /// shared helper or from an existing payload (the publish rebuild and the
    /// queue merge) — never from anything else.
    func testNoPayloadConstructionBypassesTheHelper() {
        var offenders: [String] = []
        for (file, args) in constructions() {
            guard let r = args.range(of: "authorisedOmissions:") else { continue }
            let value = args[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            let allowed = value.hasPrefix("nil")
                || value.hasPrefix("ConnectedSharePreflight.persistedOmissions(")
                || value.hasPrefix("payload.authorisedOmissions")
            if !allowed { offenders.append("\(file): \(value.prefix(60))") }
        }
        XCTAssertTrue(offenders.isEmpty, "consent must cross from staged to saved ids in ONE place: \(offenders)")
    }

    /// Each commit returns staged → saved for the attachments it creates. AESV's
    /// map is written ONLY inside its new-attachments loop, so an attachment
    /// saved before editing never enters it and keeps its id.
    func testCommitsReturnTheStagedToSavedMap() {
        for e in editors {
            let body = commitBody(e.commit)
            XCTAssertFalse(body.isEmpty, "\(e.commit): commit must return the map")
            XCTAssertTrue(body.contains("return stagedToFinalID"), "\(e.commit): commit must return the map")
        }
        let aesv = commitBody("AddEditSessionView+Attachments.swift")
        XCTAssertEqual(aesv.components(separatedBy: "for att in stagedAttachments").count - 1, 1,
                       "AESV: one staged loop")
        guard let loop = aesv.range(of: "for att in stagedAttachments where existingAttachmentIDs.contains(att.id) == false"),
              let write = aesv.range(of: "stagedToFinalID[att.id] = newID"),
              let flags = aesv.range(of: "Attachment.fetchRequest()") else {
            return XCTFail("AESV: the map must be written inside the new-attachments-only loop")
        }
        XCTAssertTrue(loop.upperBound <= write.lowerBound && write.upperBound <= flags.lowerBound,
                      "AESV: the map must be written inside the new-attachments-only loop")
    }

    /// The raw consent state has exactly two uses per editor: the dialog's
    /// assignment and the helper's argument. Anything else is a way round.
    func testEditorConsentStateHasNoOtherUse() throws {
        let rx = try NSRegularExpression(pattern: #"(?<![.\w])authorisedOmissions\b(?!\s*:)"#)
        for e in editors {
            let s = code(e.view) + "\n" + code(e.commit)
            let uses = rx.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s))
            XCTAssertEqual(uses, 2, "\(e.view): only the dialog's assignment and the helper's argument")
            XCTAssertTrue(s.contains("authorisedOmissions = consentState.pendingOmissions"), "\(e.view): assignment")
            XCTAssertTrue(s.contains("persistedOmissions(authorisedOmissions,"), "\(e.view): helper argument")
        }
    }

    // MARK: - Source helpers

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MOTIVO")
    }

    private func code(_ file: String) -> String {
        let raw = (try? String(contentsOf: sourceRoot.appendingPathComponent(file), encoding: .utf8)) ?? ""
        return raw.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The commit function's body, or "" if its signature does not return the map.
    private func commitBody(_ file: String) -> String {
        let s = code(file)
        let sig = "func commitStagedAttachments(to session: Session, ctx: NSManagedObjectContext) -> [UUID: UUID] {"
        guard let start = s.range(of: sig) else { return "" }
        let end = s.range(of: "\n    func ", range: start.upperBound..<s.endIndex)?.lowerBound ?? s.endIndex
        return String(s[start.upperBound..<end])
    }

    private func constructions() -> [(file: String, args: String)] {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: sourceRoot.path)) ?? [])
            .filter { $0.hasSuffix(".swift") }.sorted()
        var out: [(String, String)] = []
        for f in files {
            let s = code(f)
            var search = s.startIndex
            while let r = s.range(of: "PostPublishPayload(", range: search..<s.endIndex) {
                var depth = 1
                var i = r.upperBound
                while i < s.endIndex, depth > 0 {
                    if s[i] == "(" { depth += 1 } else if s[i] == ")" { depth -= 1 }
                    i = s.index(after: i)
                }
                out.append((f, String(s[r.upperBound..<i])))
                search = i
            }
        }
        return out
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

    private static func postExists(_ id: UUID) async -> Bool {
        let (c, d) = await rest("rest/v1/posts?id=eq.\(id.uuidString)&select=id", "GET")
        guard c == 200, let rows = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return false }
        return !rows.isEmpty
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
