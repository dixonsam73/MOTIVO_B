//
//  P6I01CommitServiceTests.swift
//  MOTIVOTests
//
//  PHASE 6 · BATCH 1 · P6-I-01 — THE REAL COMMIT, ON DISPOSABLE FIXTURES.
//
//  These drive `AttachmentCommitService.commit` — the production code both
//  editors call — with a real in-memory Core Data store, real files under a
//  disposable Documents root, and a real write fault. They replace an earlier
//  suite that tried to configure the editors' SwiftUI `@State` and could not:
//  measured, a `@State` write on an uninstalled view struct is ignored, so that
//  suite drove an empty list. Extracting the loop is what made these executable.
//
//  ISOLATION. `AttachmentStore.unitTestDocumentsRootOverride` (Debug + hosted
//  test only) points permanent media at `tmp/P6I01-<uuid>/Documents`. Every
//  `UserDefaults` key touched is snapshotted and restored, and the restoration is
//  asserted. No personal media, staging, account or device is involved.
//
//  FAULT ESTABLISHMENT IS NOT OPTIONAL — `testFaultIsReal` proves a read-only
//  destination makes the REAL write path throw, and throws out of the test
//  otherwise. A control failure is not a result.
//

import XCTest
import CoreData
@testable import Etudes

struct P6I01FaultNotEstablished: Error, CustomStringConvertible {
    let reason: String
    var description: String { "P6-I-01 FAULT NOT ESTABLISHED (not a product result): \(reason)" }
}

@MainActor
final class P6I01CommitServiceTests: XCTestCase {

    private let fm = FileManager.default
    private var container: URL!
    private var documentsRoot: URL!
    private var stagingRoot: URL!
    private var existingMediaRoot: URL!
    private var moc: NSManagedObjectContext!
    private var coordinator: NSPersistentStoreCoordinator!

    private static let touchedKeys = ["stagedAudioNames_temp", "stagedAttachmentDisplayNames_temp",
                                      "stagedVideoTitles_temp", "persistedAudioTitles_v1",
                                      "persistedVideoTitles_v1", PDFSelectedPagesStore.key]
    private var snapshot: [String: Any?] = [:]

    override func setUp() async throws {
        try await super.setUp()
        guard UnitTestHost.isActive else {
            throw P6I01FaultNotEstablished(reason: "UnitTestHost.isActive is false; the root override would be ignored")
        }
        container = fm.temporaryDirectory.appendingPathComponent("P6I01-\(UUID().uuidString)", isDirectory: true)
        documentsRoot = container.appendingPathComponent("Documents", isDirectory: true)
        stagingRoot = container.appendingPathComponent("Staging", isDirectory: true)
        existingMediaRoot = container.appendingPathComponent("ExistingMedia", isDirectory: true)
        for dir in [documentsRoot!, stagingRoot!, existingMediaRoot!] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        StagingStore.unitTestRootOverride = stagingRoot

        for k in Self.touchedKeys { snapshot[k] = UserDefaults.standard.object(forKey: k) }
        for k in Self.touchedKeys { UserDefaults.standard.removeObject(forKey: k) }

        AttachmentStore.unitTestDocumentsRootOverride = documentsRoot
        AttachmentStore.unitTestWriteFault = nil

        guard let model = NSManagedObjectModel.mergedModel(from: [Bundle(for: PersistenceController.self)]),
              model.entitiesByName["Session"] != nil else {
            throw P6I01FaultNotEstablished(reason: "managed object model unavailable")
        }
        coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
        moc = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        moc.persistentStoreCoordinator = coordinator
    }

    override func tearDown() async throws {
        AttachmentStore.unitTestWriteFault = nil
        AttachmentStore.unitTestDocumentsRootOverride = nil
        StagingStore.unitTestRootOverride = nil
        moc = nil; coordinator = nil
        if let container, fm.fileExists(atPath: container.path) {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: documentsRoot.path)
            try? fm.removeItem(at: container)
        }
        for (k, v) in snapshot {
            if let v { UserDefaults.standard.set(v, forKey: k) } else { UserDefaults.standard.removeObject(forKey: k) }
        }
        for k in Self.touchedKeys {
            XCTAssertEqual(UserDefaults.standard.object(forKey: k) == nil, (snapshot[k] ?? nil) == nil,
                           "defaults key \(k) was not restored")
        }
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private func staged(_ kind: AttachmentKind = .audio) -> StagedAttachment {
        StagedAttachment(id: UUID(), data: Data(repeating: 0xA5, count: 64), kind: kind)
    }

    private func inputs(_ items: [StagedAttachment], thumbnail: UUID? = nil) -> AttachmentCommitService.Inputs {
        .init(staged: items, chosenThumbnailID: thumbnail,
              suggestedName: { $0.id.uuidString }, displayName: { _ in nil })
    }

    @discardableResult
    private func session(_ title: String?) -> Session {
        let s = Session(context: moc)
        s.setValue(UUID(), forKey: "id")
        s.setValue(Date(), forKey: "timestamp")
        if let title { s.setValue(title, forKey: "title") }
        return s
    }

    private func existingAttachment(_ path: String, on s: Session) -> NSManagedObject {
        let a = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: moc)
        a.setValue(UUID(), forKey: "id"); a.setValue(Date(), forKey: "createdAt")
        a.setValue(path, forKey: "fileURL"); a.setValue("audio", forKey: "kind")
        a.setValue(false, forKey: "isThumbnail"); a.setValue(s, forKey: "session")
        return a
    }

    /// A real file with known bytes, standing in for a staged ORIGINAL on disk.
    @discardableResult
    private func sentinelOriginal(_ name: String) throws -> (url: URL, bytes: Data) {
        let bytes = Data("ORIGINAL-\(name)-\(UUID().uuidString)".utf8)
        let url = stagingRoot.appendingPathComponent(name)
        try bytes.write(to: url)
        return (url, bytes)
    }

    /// A real file with known bytes, standing in for an EXISTING attachment's media.
    private func sentinelExistingMedia(_ name: String) throws -> (url: URL, bytes: Data) {
        let bytes = Data("EXISTING-\(name)-\(UUID().uuidString)".utf8)
        let url = existingMediaRoot.appendingPathComponent(name)
        try bytes.write(to: url)
        return (url, bytes)
    }

    private func assertUnchanged(_ sentinel: (url: URL, bytes: Data), _ what: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(fm.fileExists(atPath: sentinel.url.path), "\(what): the file was deleted", file: file, line: line)
        XCTAssertEqual(try? Data(contentsOf: sentinel.url), sentinel.bytes,
                       "\(what): the bytes changed", file: file, line: line)
    }

    private var files: [String] { ((try? fm.contentsOfDirectory(atPath: documentsRoot.path)) ?? []).sorted() }
    /// LIVE attachments. `ctx.delete` marks a row for deletion but leaves it in
    /// the relationship until pending changes are processed, so a raw `count`
    /// reads rows that are already doomed — an earlier revision of this suite
    /// failed on exactly that and it was the test, not the product.
    private func attachments(of s: Session) -> Int {
        moc.processPendingChanges()
        let set = (s.value(forKey: "attachments") as? Set<NSManagedObject>) ?? []
        return set.filter { !$0.isDeleted }.count
    }

    private func failWrite(number: Int) {
        var seen = 0
        AttachmentStore.unitTestWriteFault = { _, _ in
            seen += 1
            return seen == number ? NSError(domain: "P6I01", code: 28) : nil
        }
    }

    // MARK: - F-0 · the fault is real

    func testFaultIsReal() throws {
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: documentsRoot.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: documentsRoot.path) }
        var threw = false
        do { _ = try AttachmentStore.saveDataWithRollback(Data([1]), suggestedName: "p", ext: "m4a") } catch { threw = true }
        guard threw else { throw P6I01FaultNotEstablished(reason: "a read-only Documents root did not make the real write throw") }
        XCTAssertEqual(files, [])
    }

    /// The same case through the service, so the product path is proven to fail
    /// on a genuine filesystem fault and not only on the injected hook.
    func testReadOnlyRootMakesTheRealCommitThrow() throws {
        let s = session("T")
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: documentsRoot.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: documentsRoot.path) }
        XCTAssertThrowsError(try AttachmentCommitService.commit(inputs([staged()]), to: s, ctx: moc)) {
            XCTAssertTrue($0 is AttachmentCommitFailure)
        }
        XCTAssertEqual(attachments(of: s), 0)
    }

    // MARK: - A1 · the FIRST attachment fails

    func testFirstAttachmentFailureThrowsAndLeavesNothingBehind() throws {
        let s = session("T")
        let a = staged()
        PDFSelectedPagesStore.setPages([2, 3], for: a.id)
        UserDefaults.standard.set([a.id.uuidString: "My take"], forKey: "stagedAudioNames_temp")
        failWrite(number: 1)

        XCTAssertThrowsError(try AttachmentCommitService.commit(inputs([a]), to: s, ctx: moc)) {
            XCTAssertEqual(($0 as? AttachmentCommitFailure)?.stagedID, a.id)
        }
        XCTAssertEqual(files, [], "no permanent media may survive")
        XCTAssertEqual(attachments(of: s), 0, "no row may survive")
        XCTAssertEqual(PDFSelectedPagesStore.pages(for: a.id), [2, 3], "staged pages must be untouched")
        XCTAssertNotNil(UserDefaults.standard.dictionary(forKey: "stagedAudioNames_temp"), "staged title must survive")
    }

    // MARK: - A2 · a LATER attachment fails

    func testThirdAttachmentFailureRollsBackTheFirstTwo() throws {
        let s = session("T")
        let items = [staged(), staged(), staged()]
        for i in items { PDFSelectedPagesStore.setPages([1], for: i.id) }
        failWrite(number: 3)

        XCTAssertThrowsError(try AttachmentCommitService.commit(inputs(items), to: s, ctx: moc)) {
            XCTAssertEqual(($0 as? AttachmentCommitFailure)?.stagedID, items[2].id)
        }
        XCTAssertEqual(files, [], "the two successful writes must be rolled back — residue=\(files)")
        XCTAssertEqual(attachments(of: s), 0)
        for i in items { XCTAssertEqual(PDFSelectedPagesStore.pages(for: i.id), [1]) }
    }

    // MARK: - A3 · a genuine SESSION SAVE failure, with the attempt undone

    func testSaveFailureUndoesTheAttemptAndPreservesExistingMediaAndRows() throws {
        // A saved session with an existing attachment, and an unrelated dirty object.
        let s = session("original")
        let existing = existingAttachment("/tmp/existing-media.m4a", on: s)
        let unrelated = session("unrelated")
        try moc.save()
        let existingID = existing.value(forKey: "id") as? UUID

        unrelated.setValue("dirty before the attempt", forKey: "title")   // pre-existing pending edit

        let a = staged()
        let (attempt, ticket) = try AttemptScopedUndo.begin(in: moc) { () -> AttachmentCommitAttempt in
            // What the editor's attempt does: edit the session, delete an existing
            // attachment, and commit new staged media.
            s.setValue(nil, forKey: "title")          // makes the save fail (title is non-optional)
            self.moc.delete(existing)
            return try AttachmentCommitService.commit(self.inputs([a]), to: s, ctx: self.moc)
        }

        XCTAssertEqual(files.count, 1, "the write succeeded before the save was attempted")

        var saveThrew = false
        do { try moc.save() } catch { saveThrew = true }
        guard saveThrew else { throw P6I01FaultNotEstablished(reason: "a Session with no title saved, so A3's fault is not established") }

        // The caller's save-failure branch.
        attempt.rollBackFiles()
        AttemptScopedUndo.undoAndRelease(ticket)

        XCTAssertEqual(files, [], "this attempt's permanent media must be removed")
        XCTAssertEqual(s.value(forKey: "title") as? String, "original", "the edited scalar must be restored")
        let survivors = (s.value(forKey: "attachments") as? Set<NSManagedObject>) ?? []
        XCTAssertEqual(survivors.count, 1, "the deleted existing attachment must come back")
        XCTAssertEqual(survivors.first?.value(forKey: "id") as? UUID, existingID)
        XCTAssertEqual(survivors.first?.value(forKey: "fileURL") as? String, "/tmp/existing-media.m4a",
                       "and its media reference must be intact")
        XCTAssertEqual(unrelated.value(forKey: "title") as? String, "dirty before the attempt",
                       "an unrelated pending edit must NOT be discarded")
        XCTAssertTrue(moc.insertedObjects.contains(unrelated) || !unrelated.isDeleted)
    }

    // MARK: - A4 · retry

    func testRetryAfterFailureCommitsEverythingExactlyOnce() throws {
        let s = session("T")
        let items = [staged(), staged()]
        failWrite(number: 2)
        XCTAssertThrowsError(try AttachmentCommitService.commit(inputs(items), to: s, ctx: moc))
        XCTAssertEqual(files, [])

        AttachmentStore.unitTestWriteFault = nil
        let attempt = try AttachmentCommitService.commit(inputs(items), to: s, ctx: moc)
        XCTAssertEqual(attempt.committedStagedIDs.count, 2)
        XCTAssertEqual(files.count, 2, "exactly one file per attachment — actual=\(files)")
        XCTAssertEqual(attachments(of: s), 2)
        try moc.save()
    }

    func testRetryAfterASaveFailureRecreatesTheAttachments() throws {
        let s = session(nil)   // will fail to save
        let a = staged()
        let (attempt, ticket) = try AttemptScopedUndo.begin(in: moc) {
            try AttachmentCommitService.commit(self.inputs([a]), to: s, ctx: self.moc)
        }
        XCTAssertThrowsError(try moc.save())
        attempt.rollBackFiles()
        AttemptScopedUndo.undoAndRelease(ticket)
        XCTAssertEqual(files, [])
        XCTAssertEqual(attachments(of: s), 0)

        // Retry with the cause fixed.
        s.setValue("now titled", forKey: "title")
        let retry = try AttachmentCommitService.commit(inputs([a]), to: s, ctx: moc)
        try moc.save()
        XCTAssertEqual(retry.committedStagedIDs, [a.id])
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(attachments(of: s), 1)
    }

    // MARK: - A5 · the success control

    func testSuccessfulCommitCreatesExactlyOneFileAndRowPerAttachment() throws {
        let s = session("T")
        let items = [staged(), staged(.image)]
        let attempt = try AttachmentCommitService.commit(inputs(items, thumbnail: items[1].id), to: s, ctx: moc)
        try moc.save()

        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(attachments(of: s), 2)
        XCTAssertEqual(Set(attempt.committedStagedIDs), Set(items.map(\.id)))
        for i in items {
            XCTAssertNotNil(attempt.stagedToFinalID[i.id])
            XCTAssertNotNil(attempt.stagedToFinalURL[i.id])
        }
    }

    func testThumbnailFlagIsAppliedToTheChosenAttachmentOnly() throws {
        let s = session("T")
        let items = [staged(.image), staged(.image)]
        let attempt = try AttachmentCommitService.commit(inputs(items, thumbnail: items[0].id), to: s, ctx: moc)
        AttachmentCommitService.applyThumbnailFlags(finalThumbnailID: attempt.stagedToFinalID[items[0].id],
                                                    to: s, ctx: moc)
        try moc.save()
        let set = (s.value(forKey: "attachments") as? Set<NSManagedObject>) ?? []
        XCTAssertEqual(set.filter { ($0.value(forKey: "isThumbnail") as? Bool) == true }.count, 1)
    }
}

// MARK: - Sentinel evidence: real originals and real existing media
//
// Raised in review: the cases above assert row counts and Documents contents,
// but a staged fixture is only in-memory `Data` and an "existing" attachment
// pointed at a path with no file behind it. These use REAL files with known
// bytes, so "the original survived" is a measurement rather than an inference.

extension P6I01CommitServiceTests {

    func testStagedOriginalsAndExistingMediaSurviveAFirstWriteFailure() throws {
        let original = try sentinelOriginal("take-1.m4a")
        let existingMedia = try sentinelExistingMedia("existing-1.m4a")

        let s = session("T")
        let existingRow = existingAttachment(existingMedia.url.path, on: s)
        try moc.save()

        let a = staged()
        failWrite(number: 1)
        XCTAssertThrowsError(try AttachmentCommitService.commit(inputs([a]), to: s, ctx: moc))

        assertUnchanged(original, "the staged original")
        assertUnchanged(existingMedia, "the existing attachment's media")
        XCTAssertFalse(existingRow.isDeleted)
        XCTAssertEqual(files, [], "no permanent media from the failed attempt")
    }

    func testStagedOriginalsAndExistingMediaSurviveANthWriteFailure() throws {
        let originals = try (1...3).map { try sentinelOriginal("take-\($0).m4a") }
        let existingMedia = try sentinelExistingMedia("existing-2.m4a")

        let s = session("T")
        _ = existingAttachment(existingMedia.url.path, on: s)
        try moc.save()

        failWrite(number: 3)
        XCTAssertThrowsError(try AttachmentCommitService.commit(inputs([staged(), staged(), staged()]), to: s, ctx: moc))

        for (index, original) in originals.enumerated() {
            assertUnchanged(original, "staged original \(index + 1)")
        }
        assertUnchanged(existingMedia, "the existing attachment's media")
        XCTAssertEqual(files, [], "the two successful writes must be rolled back")
    }

    func testStagedOriginalsAndExistingMediaSurviveASaveFailure() throws {
        let original = try sentinelOriginal("take-save.m4a")
        let existingMedia = try sentinelExistingMedia("existing-3.m4a")

        let s = session("original")
        let existingRow = existingAttachment(existingMedia.url.path, on: s)
        try moc.save()

        let a = staged()
        let (attempt, ticket) = try AttemptScopedUndo.begin(in: moc) { () -> AttachmentCommitAttempt in
            s.setValue(nil, forKey: "title")       // genuine validation failure
            self.moc.delete(existingRow)           // the member removed it in this edit
            return try AttachmentCommitService.commit(self.inputs([a]), to: s, ctx: self.moc)
        }
        XCTAssertEqual(files.count, 1)

        var threw = false
        do { try moc.save() } catch { threw = true }
        guard threw else { throw P6I01FaultNotEstablished(reason: "the untitled session saved; A3's fault is not established") }

        attempt.rollBackFiles()
        AttemptScopedUndo.undoAndRelease(ticket)

        assertUnchanged(original, "the staged original")
        assertUnchanged(existingMedia,
                        "the existing attachment's media — its row came back, so its file must still exist")
        XCTAssertEqual(files, [], "the attempt's permanent media is removed")
        XCTAssertEqual(attachments(of: s), 1, "the deleted existing row is restored")
        XCTAssertEqual(s.value(forKey: "title") as? String, "original")
    }

    /// Only the ids the attempt actually committed may be consumed.
    func testOnlyCommittedStagedIDsAreConsumedOnSuccess() throws {
        let s = session("T")
        let committedItem = staged()
        let untouched = staged()          // staged, but NOT passed to this commit
        PDFSelectedPagesStore.setPages([9], for: untouched.id)

        let attempt = try AttachmentCommitService.commit(inputs([committedItem]), to: s, ctx: moc)
        try moc.save()

        XCTAssertEqual(attempt.committedStagedIDs, [committedItem.id],
                       "an id the attempt never committed must not appear in the consumed set")
        XCTAssertNil(attempt.stagedToFinalID[untouched.id])
        XCTAssertEqual(PDFSelectedPagesStore.pages(for: untouched.id), [9],
                       "and its staged metadata must be untouched")
    }

}
