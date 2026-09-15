//
//  NotesClearPublishTests.swift
//  MOTIVOTests
//
//  PHASE 5 · C-88 / weekend A3 — CLEARING NOTES WHILE A PUBLISH IS QUEUED.
//
//  The producer (`PublishService.publish(payload:objectID:shouldPublish:)`)
//  rebuilds the payload's notes from the saved Session. It used to turn an empty
//  or absent note into `nil`, and the queue merge reads `nil` as "unspecified"
//  (`payload.notes ?? existing.notes`), so a member's explicit clear was lost
//  whenever an older publish was still queued, and the old notes were published.
//
//  The views save notes to Core Data correctly; it is the PAYLOAD notes that
//  were lost. `nil` meaning "unspecified" is a producer/queue-merge contract
//  only: the metadata PATCH always writes notes (NULL for nil).
//
//  Two classes:
//   - `NotesClearProducerQueueTests` runs in LOCAL SIMULATION, where the flush is
//     skipped, so the queued item stays in place to be inspected. It is NOT an
//     offline-network test.
//   - `NotesClearEndToEndTests` runs against the LOCAL STACK, with a genuine
//     offline network (`127.0.0.1:1`) while the intent is queued, and reads the
//     row back.
//

import XCTest
import CoreData
import CryptoKit
@testable import Etudes

// MARK: - Shared fixtures

@MainActor
private enum NotesClearFixture {
    static var viewContext: NSManagedObjectContext { PersistenceController.shared.container.viewContext }

    /// A saved Session carrying the given notes. Every non-optional Session
    /// attribute is set, or `save()` throws.
    static func makeSession(notes: String?, notesPrivate: Bool) throws -> (id: UUID, object: NSManagedObject) {
        let ctx = viewContext
        let id = UUID()
        let s = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        s.setValue(id, forKey: "id")
        s.setValue(Date(), forKey: "timestamp")
        s.setValue("c88 fixture", forKey: "title")
        s.setValue(Int64(60), forKey: "durationSeconds")
        s.setValue(Int16(0), forKey: "activityType")
        s.setValue(Int16(5), forKey: "effort")
        s.setValue(Int16(5), forKey: "mood")
        s.setValue(true, forKey: "isPublic")
        s.setValue(notes, forKey: "notes")
        s.setValue(notesPrivate, forKey: "areNotesPrivate")
        try ctx.obtainPermanentIDs(for: [s])
        try ctx.save()
        return (id, s)
    }

    /// What the editor does: the member changes the notes and saves.
    static func save(_ s: NSManagedObject, notes: String?, notesPrivate: Bool) throws {
        s.setValue(notes, forKey: "notes")
        s.setValue(notesPrivate, forKey: "areNotesPrivate")
        try viewContext.save()
        XCTAssertEqual(s.value(forKey: "notes") as? String, notes, "fixture: Core Data holds the saved notes")
    }

    /// An object id the view context cannot resolve, so the producer's
    /// enrichment fails. Asserted, so a failure case can never pass by accident.
    static func unresolvableObjectID() throws -> NSManagedObjectID {
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = PersistenceController.shared.container.persistentStoreCoordinator
        let o = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        let oid = o.objectID
        ctx.rollback()
        XCTAssertThrowsError(try viewContext.existingObject(with: oid),
                             "fixture: the producer must NOT be able to resolve this object")
        return oid
    }

    /// The incoming payload. `notes` defaults to nil, the shape the detail view
    /// sends, so a resolved case can only pass through Core Data resolution and
    /// never because the incoming payload happened to carry the value.
    static func payload(_ id: UUID, title: String, notes: String? = nil, notesPrivate: Bool = false,
                        omissions: [UUID]? = nil) -> SessionSyncQueue.PostPublishPayload {
        SessionSyncQueue.PostPublishPayload(
            id: id, sessionID: id, sessionTimestamp: Date(), title: title,
            durationSeconds: 60, activityType: nil, activityDetail: nil,
            instrumentLabel: nil, mood: nil, effort: nil,
            isPublic: true, notes: notes, areNotesPrivate: notesPrivate,
            authorisedOmissions: omissions)
    }

    /// Waits until the asynchronous publish task has merged THIS save into the
    /// queue, recognised by its distinct title.
    /// A timeout throws, and a thrown error is recorded as a failure.
    static func queued(_ id: UUID, title: String) async throws -> SessionSyncQueue.PostPublishPayload {
        for _ in 0..<200 {
            if let item = SessionSyncQueue.shared.items.first(where: { $0.id == id }), item.title == title {
                return item
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw LocalStackRequirementError.unmet("the publish task never merged the save titled \(title)")
    }

    static func describe(_ notes: String?) -> String { notes.map { "\"\($0)\"" } ?? "nil" }
}

// MARK: - Producer → queue (local simulation)

@MainActor
final class NotesClearProducerQueueTests: XCTestCase {

    private let activationSentinel = AppActivationWriteSentinel()
    private var sessions: [NSManagedObject] = []

    override func setUp() async throws {
        try await super.setUp()
        activationSentinel.start()
        setBackendMode(.localSimulation)
        SessionSyncQueue.shared.clear()
        XCTAssertEqual(BackendEnvironment.shared.mode, .localSimulation,
                       "precondition: local simulation, so the flush is skipped and the queued item stays")
    }

    override func tearDown() async throws {
        activationSentinel.assertNoHostActivationWrites()
        SessionSyncQueue.shared.clear()
        for s in sessions where !s.isDeleted { NotesClearFixture.viewContext.delete(s) }
        try? NotesClearFixture.viewContext.save()
        sessions = []
        try await super.tearDown()
    }

    private func session(notes: String?, notesPrivate: Bool) throws -> (id: UUID, object: NSManagedObject) {
        let made = try NotesClearFixture.makeSession(notes: notes, notesPrivate: notesPrivate)
        sessions.append(made.object)
        return made
    }

    private func publish(_ p: SessionSyncQueue.PostPublishPayload, _ oid: NSManagedObjectID) {
        PublishService.shared.publish(payload: p, objectID: oid, shouldPublish: p.isPublic)
    }

    /// P-0 then the clear. The first queued item must really hold the old notes.
    private func assertClear(to saved: String?, notesPrivate: Bool, id caseID: String,
                             file: StaticString = #filePath, line: UInt = #line) async throws {
        let s = try session(notes: "old", notesPrivate: false)
        publish(NotesClearFixture.payload(s.id, title: "\(caseID)-1"), s.object.objectID)
        let first = try await NotesClearFixture.queued(s.id, title: "\(caseID)-1")
        XCTAssertEqual(first.notes, "old", "P-0 (\(caseID)): the first queued item holds the old notes", file: file, line: line)
        XCTAssertFalse(first.areNotesPrivate, "P-0 (\(caseID)): …and they are not private", file: file, line: line)

        try NotesClearFixture.save(s.object, notes: saved, notesPrivate: notesPrivate)
        publish(NotesClearFixture.payload(s.id, title: "\(caseID)-2"), s.object.objectID)
        let after = try await NotesClearFixture.queued(s.id, title: "\(caseID)-2")

        XCTAssertEqual(after.notes, "",
                       "\(caseID): a saved clear (\(NotesClearFixture.describe(saved))) must queue an explicit empty value, found \(NotesClearFixture.describe(after.notes))",
                       file: file, line: line)
        XCTAssertEqual(after.areNotesPrivate, notesPrivate,
                       "\(caseID): the saved privacy flag must travel with the clear", file: file, line: line)
        XCTAssertEqual(SessionSyncQueue.shared.items.filter { $0.id == s.id }.count, 1,
                       "\(caseID): still one item for the post", file: file, line: line)
    }

    // P-1
    func testP1_clearToEmptyStringQueuesExplicitEmpty() async throws {
        try await assertClear(to: "", notesPrivate: false, id: "P-1")
    }

    // P-2
    func testP2_clearToWhitespaceQueuesExplicitEmpty() async throws {
        try await assertClear(to: "  \n\t ", notesPrivate: false, id: "P-2")
    }

    // P-3
    func testP3_clearToActualNilQueuesExplicitEmpty() async throws {
        try await assertClear(to: nil, notesPrivate: false, id: "P-3")
    }

    // P-4
    func testP4_clearPlusPrivateQueuesEmptyAndPrivate() async throws {
        try await assertClear(to: "", notesPrivate: true, id: "P-4")
    }

    // P-5
    func testP5_textReplacement() async throws {
        let s = try session(notes: "old", notesPrivate: false)
        publish(NotesClearFixture.payload(s.id, title: "P-5-1"), s.object.objectID)
        let first = try await NotesClearFixture.queued(s.id, title: "P-5-1")
        XCTAssertEqual(first.notes, "old", "P-0 (P-5)")

        try NotesClearFixture.save(s.object, notes: "  new  ", notesPrivate: false)
        publish(NotesClearFixture.payload(s.id, title: "P-5-2"), s.object.objectID)
        let after = try await NotesClearFixture.queued(s.id, title: "P-5-2")
        XCTAssertEqual(after.notes, "new", "P-5: replacement text is queued, trimmed")
        XCTAssertFalse(after.areNotesPrivate, "P-5: privacy unchanged")
    }

    // P-6
    func testP6_privacyTogglesWithExistingText() async throws {
        let s = try session(notes: "old", notesPrivate: false)
        publish(NotesClearFixture.payload(s.id, title: "P-6-1"), s.object.objectID)
        let first = try await NotesClearFixture.queued(s.id, title: "P-6-1")
        XCTAssertEqual(first.notes, "old", "P-0 (P-6)")
        XCTAssertFalse(first.areNotesPrivate)

        try NotesClearFixture.save(s.object, notes: "old", notesPrivate: true)
        publish(NotesClearFixture.payload(s.id, title: "P-6-2"), s.object.objectID)
        let priv = try await NotesClearFixture.queued(s.id, title: "P-6-2")
        XCTAssertEqual(priv.notes, "old", "P-6: text kept when made private")
        XCTAssertTrue(priv.areNotesPrivate, "P-6: private takes effect")

        try NotesClearFixture.save(s.object, notes: "old", notesPrivate: false)
        publish(NotesClearFixture.payload(s.id, title: "P-6-3"), s.object.objectID)
        let pub = try await NotesClearFixture.queued(s.id, title: "P-6-3")
        XCTAssertEqual(pub.notes, "old", "P-6: text kept when made public again")
        XCTAssertFalse(pub.areNotesPrivate, "P-6: public again takes effect")
    }

    // P-7
    func testP7_unspecifiedPartialPayloadKeepsQueuedValue() async throws {
        let s = try session(notes: "old", notesPrivate: true)
        publish(NotesClearFixture.payload(s.id, title: "P-7-1"), s.object.objectID)
        let first = try await NotesClearFixture.queued(s.id, title: "P-7-1")
        XCTAssertEqual(first.notes, "old", "P-0 (P-7)")
        XCTAssertTrue(first.areNotesPrivate)

        // A partial payload that says nothing about notes.
        SessionSyncQueue.shared.enqueue(NotesClearFixture.payload(s.id, title: "P-7-2", notes: nil, notesPrivate: false))
        let after = try await NotesClearFixture.queued(s.id, title: "P-7-2")
        XCTAssertEqual(after.notes, "old", "P-7: unspecified notes keep the queued value")
        XCTAssertTrue(after.areNotesPrivate, "P-7: …and its privacy")
    }

    // P-8
    func testP8_resolutionFailureKeepsIncomingNotesAndPrivacy() async throws {
        let id = UUID()
        let oid = try NotesClearFixture.unresolvableObjectID()
        publish(NotesClearFixture.payload(id, title: "P-8", notes: "incoming", notesPrivate: true), oid)
        let item = try await NotesClearFixture.queued(id, title: "P-8")
        XCTAssertEqual(item.notes, "incoming",
                       "P-8: when the Session cannot be read, the incoming notes are kept, found \(NotesClearFixture.describe(item.notes))")
        XCTAssertTrue(item.areNotesPrivate, "P-8: …and the incoming privacy flag")
    }

    // P-9
    func testP9_resolutionFailureWithUnspecifiedNotesIsNotAClear() async throws {
        let s = try session(notes: "old", notesPrivate: true)
        publish(NotesClearFixture.payload(s.id, title: "P-9-1"), s.object.objectID)
        let first = try await NotesClearFixture.queued(s.id, title: "P-9-1")
        XCTAssertEqual(first.notes, "old", "P-0 (P-9)")

        let oid = try NotesClearFixture.unresolvableObjectID()
        publish(NotesClearFixture.payload(s.id, title: "P-9-2", notes: nil, notesPrivate: false), oid)
        let after = try await NotesClearFixture.queued(s.id, title: "P-9-2")
        XCTAssertEqual(after.notes, "old", "P-9: an unknown value must not become a clear, found \(NotesClearFixture.describe(after.notes))")
        XCTAssertTrue(after.areNotesPrivate, "P-9: …and the queued privacy is kept")
    }

    // P-9b
    func testP9b_resolutionFailureWithNothingQueuedStaysUnspecified() async throws {
        let id = UUID()
        let oid = try NotesClearFixture.unresolvableObjectID()
        publish(NotesClearFixture.payload(id, title: "P-9b", notes: nil, notesPrivate: false), oid)
        let item = try await NotesClearFixture.queued(id, title: "P-9b")
        XCTAssertNil(item.notes, "P-9b: an unknown value stays unspecified, never \"\"")
        XCTAssertFalse(item.areNotesPrivate)
    }

    // P-10
    func testP10_pendingClearSurvivesTheQueueFile() async throws {
        let omitted = [UUID(), UUID()]
        let s = try session(notes: "old", notesPrivate: false)
        publish(NotesClearFixture.payload(s.id, title: "P-10-1", omissions: omitted), s.object.objectID)
        let first = try await NotesClearFixture.queued(s.id, title: "P-10-1")
        XCTAssertEqual(first.notes, "old", "P-0 (P-10)")

        try NotesClearFixture.save(s.object, notes: "", notesPrivate: true)
        publish(NotesClearFixture.payload(s.id, title: "P-10-2", omissions: omitted), s.object.objectID)
        _ = try await NotesClearFixture.queued(s.id, title: "P-10-2")

        // The file the queue actually writes, through the decoder `load` uses.
        let data = try Data(contentsOf: SessionSyncQueue.makeFileURL())
        let onDisk = try JSONDecoder().decode([SessionSyncQueue.PostPublishPayload].self, from: data)
        let item = try XCTUnwrap(onDisk.first { $0.id == s.id }, "P-10: the item is in the queue file")
        XCTAssertEqual(item.title, "P-10-2", "P-10: the file holds the latest save")
        XCTAssertEqual(item.notes, "", "P-10: the pending clear survives persistence, found \(NotesClearFixture.describe(item.notes))")
        XCTAssertTrue(item.areNotesPrivate, "P-10: …with its privacy flag")
        XCTAssertEqual(item.authorisedOmissions, omitted, "P-10: …and the authorised omissions")
    }

    // P-10b
    func testP10b_legacyPayloadWithoutNotesDecodesAsUnspecified() throws {
        let json = #"[{"id":"\#(UUID().uuidString)","isPublic":true,"areNotesPrivate":false,"title":"legacy"}]"#
        let decoded = try JSONDecoder().decode([SessionSyncQueue.PostPublishPayload].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertNil(decoded[0].notes, "P-10b: a payload with no notes key is unspecified, not a clear")
        XCTAssertFalse(decoded[0].areNotesPrivate)
    }
}

// MARK: - End to end (local stack, genuine offline network)

@MainActor
final class NotesClearEndToEndTests: XCTestCase {

    private let activationSentinel = AppActivationWriteSentinel()

    private static let baseURLString = LocalStackSupport.baseURLString
    private static let offlineURL = URL(string: "http://127.0.0.1:1")!
    private static let jwtSecret = "super-secret-jwt-token-with-at-least-32-characters-long"
    private static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
        + "eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9."
        + "CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
    /// Disposable identity for this unit, created by `ensureIdentities`.
    private static let ownerUID = "00000000-0000-0000-0000-0000000f0088"

    private var postIDs: [UUID] = []
    private var sessions: [NSManagedObject] = []

    override func setUp() async throws {
        try await super.setUp()
        activationSentinel.start()
        BackendConfig.apiBaseURL = URL(string: Self.baseURLString)
        BackendConfig.apiToken = Self.anonKey
        NetworkManager.shared.baseURL = URL(string: Self.baseURLString)
        NetworkManager.shared.setBearerToken(Self.mintJWT(sub: Self.ownerUID))
        UserDefaults.standard.set(Self.ownerUID, forKey: "supabaseUserID_v1")
        SessionSyncQueue.shared.clear()
        setBackendMode(.backendConnected)
        if LocalStackSupport.isReachable() {
            try await LocalStackSupport.ensureIdentities([Self.ownerUID])
            try LocalStackSupport.requireRealBackend()
        }
    }

    override func tearDown() async throws {
        activationSentinel.assertNoHostActivationWrites()
        NetworkManager.shared.baseURL = URL(string: Self.baseURLString)
        for id in postIDs { _ = await Self.rest("rest/v1/posts?id=eq.\(id.uuidString)", "DELETE") }
        postIDs = []
        for s in sessions where !s.isDeleted { NotesClearFixture.viewContext.delete(s) }
        try? NotesClearFixture.viewContext.save()
        sessions = []
        SessionSyncQueue.shared.clear()
        NetworkManager.shared.setBearerToken(nil)
        UserDefaults.standard.removeObject(forKey: "supabaseUserID_v1")
        setBackendMode(.localSimulation)
        try await super.tearDown()
    }

    private func skipUnlessLocalStack() throws {
        guard URL(string: Self.baseURLString)!.host == "127.0.0.1" else { XCTFail("non-loopback host"); return }
        guard LocalStackSupport.isReachable() else {
            throw XCTSkip("local Supabase stack not reachable — run `supabase start`")
        }
    }

    private func session(notes: String?, notesPrivate: Bool) throws -> (id: UUID, object: NSManagedObject) {
        let made = try NotesClearFixture.makeSession(notes: notes, notesPrivate: notesPrivate)
        sessions.append(made.object)
        postIDs.append(made.id)
        return made
    }

    private func publish(_ p: SessionSyncQueue.PostPublishPayload, _ oid: NSManagedObjectID) {
        PublishService.shared.publish(payload: p, objectID: oid, shouldPublish: p.isPublic)
    }

    // MARK: E-1 / E-2 — first publication after a queued clear

    private func firstPublicationAfterQueuedClear(notesPrivate: Bool, id caseID: String) async throws {
        try skipUnlessLocalStack()
        let s = try session(notes: "old", notesPrivate: false)

        NetworkManager.shared.baseURL = Self.offlineURL
        publish(NotesClearFixture.payload(s.id, title: "\(caseID)-1"), s.object.objectID)
        let first = try await NotesClearFixture.queued(s.id, title: "\(caseID)-1")
        XCTAssertEqual(first.notes, "old", "\(caseID) precondition: the queued publish carries the old notes")
        await Self.settle()

        try NotesClearFixture.save(s.object, notes: "", notesPrivate: notesPrivate)
        publish(NotesClearFixture.payload(s.id, title: "\(caseID)-2"), s.object.objectID)
        _ = try await NotesClearFixture.queued(s.id, title: "\(caseID)-2")
        await Self.settle()

        NetworkManager.shared.baseURL = URL(string: Self.baseURLString)
        let offlineRows = try await Self.rows(s.id)
        XCTAssertEqual(offlineRows.count, 0, "\(caseID) precondition: nothing reached the server while offline")

        await SessionSyncQueue.shared.flushNow()
        await Self.settle()

        let rows = try await Self.rows(s.id)
        XCTAssertEqual(rows.count, 1, "\(caseID): the post was published, exactly one row")
        XCTAssertEqual(rows.first?["title"] as? String, "\(caseID)-2", "\(caseID): the row carries the latest save")
        XCTAssertTrue(rows.first?["notes"] is NSNull,
                      "\(caseID): server notes must be JSON null after the clear, found \(String(describing: rows.first?["notes"]))")
        XCTAssertFalse(SessionSyncQueue.shared.items.contains { $0.id == s.id }, "\(caseID): dequeued")
    }

    func testE1_firstPublicationAfterQueuedClear() async throws {
        try await firstPublicationAfterQueuedClear(notesPrivate: false, id: "E-1")
    }

    func testE2_firstPublicationAfterQueuedClearPlusPrivate() async throws {
        try await firstPublicationAfterQueuedClear(notesPrivate: true, id: "E-2")
    }

    // MARK: E-3 / E-4 — clearing a post that already has old notes on the server

    private func existingRowCleared(notesPrivate: Bool, id caseID: String) async throws {
        try skipUnlessLocalStack()
        let s = try session(notes: "old", notesPrivate: false)

        // Online publish; the row exists with the old notes. An online publish
        // flushes and dequeues at once, so wait for the ROW, not the queue.
        publish(NotesClearFixture.payload(s.id, title: "\(caseID)-1"), s.object.objectID)
        var before = try await Self.rows(s.id)
        for _ in 0..<40 where before.isEmpty || SessionSyncQueue.shared.items.contains(where: { $0.id == s.id }) {
            try await Task.sleep(nanoseconds: 250_000_000)
            before = try await Self.rows(s.id)
        }
        XCTAssertEqual(before.count, 1, "\(caseID) precondition: the post exists on the server")
        XCTAssertEqual(before.first?["notes"] as? String, "old", "\(caseID) precondition: with the old notes")

        // Offline: an edit that leaves the notes alone is queued, still carrying them.
        NetworkManager.shared.baseURL = Self.offlineURL
        publish(NotesClearFixture.payload(s.id, title: "\(caseID)-2"), s.object.objectID)
        let edit = try await NotesClearFixture.queued(s.id, title: "\(caseID)-2")
        XCTAssertEqual(edit.notes, "old", "\(caseID) precondition: the queued edit carries the old notes")
        await Self.settle()

        // Offline: the member clears the notes.
        try NotesClearFixture.save(s.object, notes: "", notesPrivate: notesPrivate)
        publish(NotesClearFixture.payload(s.id, title: "\(caseID)-3"), s.object.objectID)
        _ = try await NotesClearFixture.queued(s.id, title: "\(caseID)-3")
        await Self.settle()

        // Reconnect: the POST answers 409 and the metadata PATCH updates the row.
        NetworkManager.shared.baseURL = URL(string: Self.baseURLString)
        await SessionSyncQueue.shared.flushNow()
        await Self.settle()

        let rows = try await Self.rows(s.id)
        XCTAssertEqual(rows.count, 1, "\(caseID): exactly one row")
        XCTAssertEqual(rows.first?["title"] as? String, "\(caseID)-3",
                       "\(caseID): the metadata PATCH reached the existing row")
        XCTAssertTrue(rows.first?["notes"] is NSNull,
                      "\(caseID): server notes must be JSON null after the clear, found \(String(describing: rows.first?["notes"]))")
        XCTAssertFalse(SessionSyncQueue.shared.items.contains { $0.id == s.id }, "\(caseID): dequeued")
    }

    func testE3_existingRowWithOldNotesIsCleared() async throws {
        try await existingRowCleared(notesPrivate: false, id: "E-3")
    }

    func testE4_existingRowWithOldNotesIsClearedPlusPrivate() async throws {
        try await existingRowCleared(notesPrivate: true, id: "E-4")
    }

    // MARK: Helpers

    private static func settle() async { try? await Task.sleep(nanoseconds: 2_500_000_000) }

    /// The post's row(s). A failed read throws rather than looking like "no row".
    private static func rows(_ id: UUID) async throws -> [[String: Any]] {
        let (code, data) = await rest("rest/v1/posts?id=eq.\(id.uuidString)&select=id,title,notes", "GET")
        guard code == 200, let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw LocalStackRequirementError.unmet("reading post \(id) failed (HTTP \(code): \(String(data: data, encoding: .utf8) ?? ""))")
        }
        return rows
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
}
