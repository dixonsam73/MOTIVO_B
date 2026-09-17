//
//  P6I01AttemptScopedUndoTests.swift
//  MOTIVOTests
//
//  PHASE 6 · BATCH 1 · P6-I-01 — DOES ATTEMPT-SCOPED UNDO ACTUALLY WORK?
//
//  Codex's review supplied the recipe as CONSTRAINTS, explicitly not as a claim
//  that it works. These fixtures decide it, against an in-memory store built
//  from the app's own model, BEFORE either editor is wired to it.
//
//  Each case asserts the two halves that matter:
//    * the attempt's changes are restored — old values, relationships, deleted rows;
//    * pre-existing inserted / dirty / deleted objects and the caller's own undo
//      history are NOT touched.
//

import XCTest
import CoreData
@testable import Etudes

@MainActor
final class P6I01AttemptScopedUndoTests: XCTestCase {

    private var moc: NSManagedObjectContext!
    private var coordinator: NSPersistentStoreCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        let model = NSManagedObjectModel.mergedModel(from: [Bundle(for: PersistenceController.self)])
        guard let model, model.entitiesByName["Session"] != nil else {
            throw XCTSkip("managed object model unavailable")
        }
        coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
        moc = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        moc.persistentStoreCoordinator = coordinator
    }

    override func tearDown() async throws {
        moc = nil; coordinator = nil
        try await super.tearDown()
    }

    @discardableResult
    private func session(_ title: String?) -> Session {
        let s = Session(context: moc)
        s.setValue(UUID(), forKey: "id")
        s.setValue(Date(), forKey: "timestamp")
        if let title { s.setValue(title, forKey: "title") }
        return s
    }

    private func attachment(_ path: String, on s: Session) -> NSManagedObject {
        let a = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: moc)
        a.setValue(UUID(), forKey: "id")
        a.setValue(Date(), forKey: "createdAt")
        a.setValue(path, forKey: "fileURL")
        a.setValue("audio", forKey: "kind")
        a.setValue(false, forKey: "isThumbnail")
        a.setValue(s, forKey: "session")
        return a
    }

    /// SAVED rows only. `count(for:)` includes pending changes by default, which
    /// is why an earlier revision of this suite read 1 for an unsaved insert and
    /// failed on its own assertion rather than on the product.
    private func sessionCount() throws -> Int {
        let r = NSFetchRequest<NSFetchRequestResult>(entityName: "Session")
        r.includesPendingChanges = false
        return try moc.count(for: r)
    }

    // MARK: - Inserts made by the attempt are undone

    func testAttemptInsertsAreUndone() throws {
        let existing = session("kept")
        try moc.save()
        XCTAssertEqual(try sessionCount(), 1)

        struct Boom: Error {}
        XCTAssertThrowsError(try AttemptScopedUndo.run(in: moc) {
            _ = self.session("attempt")
            _ = self.attachment("/tmp/a.m4a", on: existing)
            throw Boom()
        })

        XCTAssertEqual(try sessionCount(), 1, "the attempt's inserted session must be gone")
        XCTAssertEqual((existing.value(forKey: "attachments") as? Set<NSManagedObject>)?.count ?? 0, 0,
                       "the attempt's inserted attachment must be gone")
        XCTAssertFalse(existing.isDeleted, "the pre-existing session must survive")
    }

    // MARK: - Scalar edits made by the attempt are restored

    func testAttemptScalarEditsAreRestoredToTheirOldValues() throws {
        let s = session("original")
        try moc.save()

        struct Boom: Error {}
        XCTAssertThrowsError(try AttemptScopedUndo.run(in: moc) {
            s.setValue("changed by the attempt", forKey: "title")
            throw Boom()
        })

        XCTAssertEqual(s.value(forKey: "title") as? String, "original",
                       "an edited scalar must be restored to its pre-attempt value")
    }

    // MARK: - Rows the attempt DELETED come back

    func testAttemptDeletesAreRestored() throws {
        let s = session("owner")
        let a = attachment("/tmp/keepme.m4a", on: s)
        try moc.save()
        let attachmentID = a.value(forKey: "id") as? UUID

        struct Boom: Error {}
        XCTAssertThrowsError(try AttemptScopedUndo.run(in: moc) {
            self.moc.delete(a)
            throw Boom()
        })

        let survivors = (s.value(forKey: "attachments") as? Set<NSManagedObject>) ?? []
        XCTAssertEqual(survivors.count, 1, "a row the attempt deleted must come back")
        XCTAssertEqual(survivors.first?.value(forKey: "id") as? UUID, attachmentID,
                       "and it must be the same row, with its relationship restored")
    }

    // MARK: - Pre-existing pending work is NOT touched

    func testPreExistingPendingInsertsAndEditsSurviveTheUndo() throws {
        let saved = session("saved")
        try moc.save()

        // Pending work that belongs to somebody else, made BEFORE the attempt.
        let pendingInsert = session("pending insert")
        saved.setValue("dirty before the attempt", forKey: "title")

        struct Boom: Error {}
        XCTAssertThrowsError(try AttemptScopedUndo.run(in: moc) {
            _ = self.session("attempt")
            throw Boom()
        })

        XCTAssertFalse(pendingInsert.isDeleted,
                       "a pre-existing pending insert must not be undone by the attempt's group")
        XCTAssertTrue(moc.insertedObjects.contains(pendingInsert),
                      "and it must still be pending")
        XCTAssertEqual(saved.value(forKey: "title") as? String, "dirty before the attempt",
                       "a pre-existing dirty value must not be reverted by the attempt's group")
    }

    func testPreExistingPendingDeleteIsNotResurrected() throws {
        let s = session("owner")
        let doomed = attachment("/tmp/doomed.m4a", on: s)
        try moc.save()

        moc.delete(doomed)   // pre-existing pending delete

        struct Boom: Error {}
        XCTAssertThrowsError(try AttemptScopedUndo.run(in: moc) {
            _ = self.session("attempt")
            throw Boom()
        })

        XCTAssertTrue(doomed.isDeleted,
                      "a delete made before the attempt must stay deleted")
    }
    func testANilUndoManagerIsRestoredAsNil() throws {
        moc.undoManager = nil
        _ = try AttemptScopedUndo.run(in: moc) { self.session("x") }
        XCTAssertNil(moc.undoManager, "a context that had no undo manager must not acquire one")
    }

    // MARK: - Success does NOT undo

    func testSuccessKeepsTheAttemptsChanges() throws {
        _ = try AttemptScopedUndo.run(in: moc) { self.session("kept") }
        XCTAssertEqual(try sessionCount(), 0, "not saved yet")   // saved rows only
        XCTAssertEqual(moc.insertedObjects.count, 1, "but still pending, not undone")
    }

    // MARK: - The ticket: undo AFTER a successful body, for a failed save

    func testTicketUndoesTheAttemptAfterASaveFailure() throws {
        let existing = session("kept")
        try moc.save()

        let (created, ticket) = try AttemptScopedUndo.begin(in: moc) { () -> Session in
            let s = self.session("attempt")
            _ = self.attachment("/tmp/b.m4a", on: existing)
            return s
        }
        XCTAssertFalse(created.isDeleted)
        XCTAssertEqual((existing.value(forKey: "attachments") as? Set<NSManagedObject>)?.count, 1)

        AttemptScopedUndo.undoAndRelease(ticket)

        XCTAssertEqual(try sessionCount(), 1, "the attempt's session must be gone after the ticket undo")
        XCTAssertEqual((existing.value(forKey: "attachments") as? Set<NSManagedObject>)?.count ?? 0, 0,
                       "the attempt's attachment must be gone too")
        XCTAssertFalse(existing.isDeleted)
    }

    func testTicketUndoRestoresScalarsAndDeletes() throws {
        let s = session("original")
        let a = attachment("/tmp/c.m4a", on: s)
        try moc.save()

        let (_, ticket) = try AttemptScopedUndo.begin(in: moc) {
            s.setValue("attempted", forKey: "title")
            self.moc.delete(a)
        }
        AttemptScopedUndo.undoAndRelease(ticket)

        XCTAssertEqual(s.value(forKey: "title") as? String, "original")
        XCTAssertEqual((s.value(forKey: "attachments") as? Set<NSManagedObject>)?.count, 1,
                       "the deleted attachment must be restored")
    }

    // MARK: - The caller's OPEN group (raised in review)
    //
    // The history test above closes the caller's group first. If the caller has a
    // group still OPEN, our `beginUndoGrouping` nests inside it and `undo()` may
    // close or undo the OUTER group. Measured here rather than assumed.
    private func assertContextRestored(_ expected: UndoManager?, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(moc.undoManager === expected, "undo manager not restored", file: file, line: line)
        if let expected { XCTAssertEqual(expected.groupingLevel, 0, "a group was left open", file: file, line: line) }
    }

    func testOpenReleaseSuccessLeavesNoOpenGroupWithNoManager() throws {
        moc.undoManager = nil
        let ticket = try AttemptScopedUndo.open(in: moc)
        let s = session("created")
        try moc.save()
        AttemptScopedUndo.release(ticket)

        assertContextRestored(nil)
        XCTAssertFalse(s.isDeleted, "a released attempt keeps its work")
        XCTAssertEqual(try sessionCount(), 1)

        // And the next save must be usable.
        let second = try AttemptScopedUndo.open(in: moc)
        _ = session("second")
        try moc.save()
        AttemptScopedUndo.release(second)
        XCTAssertEqual(try sessionCount(), 2, "a second attempt must work after the first released")
    }

    func testOpenUndoAndReleaseAfterARealSaveFailureWithNoManager() throws {
        moc.undoManager = nil
        let keeper = session("keeper")
        try moc.save()

        let ticket = try AttemptScopedUndo.open(in: moc)
        let doomed = session(nil)            // title is non-optional → save fails
        keeper.setValue("edited by the attempt", forKey: "title")
        var threw = false
        do { try moc.save() } catch { threw = true }
        XCTAssertTrue(threw, "the fixture must produce a real save failure")

        AttemptScopedUndo.undoAndRelease(ticket)

        assertContextRestored(nil)
        XCTAssertEqual(keeper.value(forKey: "title") as? String, "keeper", "the attempt's edit is reverted")
        XCTAssertTrue(doomed.isDeleted || !moc.insertedObjects.contains(doomed),
                      "the attempt's insert is gone")
        XCTAssertEqual(try sessionCount(), 1)

        // The context must still be usable for a retry.
        let retry = try AttemptScopedUndo.open(in: moc)
        _ = session("retry")
        try moc.save()
        AttemptScopedUndo.release(retry)
        XCTAssertEqual(try sessionCount(), 2)
    }

    /// A context that ALREADY has an undo manager is refused, before any mutation.
    ///
    /// The reuse branch was implemented and measured: it did not restore the
    /// caller's history or grouping state, so it is not shipped. Refusing is
    /// fail-closed — the save aborts and nothing has been changed.
    func testAnExistingUndoManagerIsRefusedBeforeAnythingIsMutated() throws {
        let caller = UndoManager()
        moc.undoManager = caller
        let prior = session("prior")
        try moc.save()
        let priorCanUndo = caller.canUndo

        XCTAssertThrowsError(try AttemptScopedUndo.open(in: moc)) {
            XCTAssertTrue($0 is AttemptScopedUndoUnavailable)
        }

        XCTAssertTrue(moc.undoManager === caller, "the caller's manager is left exactly as found")
        XCTAssertEqual(caller.canUndo, priorCanUndo, "and its history is untouched")
        // `groupingLevel` is deliberately NOT asserted: with the default
        // `groupsByEvent = true` the run loop opens and closes groups on this
        // manager on its own, so its level is not ours to predict. What matters is
        // that WE opened nothing on it — covered by the identity and history
        // assertions above and by nothing having been mutated below.
        XCTAssertFalse(prior.isDeleted)
        XCTAssertEqual(try sessionCount(), 1, "nothing was mutated or saved")
    }
}
