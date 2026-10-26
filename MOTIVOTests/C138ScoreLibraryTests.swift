//
//  C138ScoreLibraryTests.swift
//  MOTIVOTests
//
//  C-138 — DELETING A LIBRARY SCORE MUST NOT BREAK A JOURNAL ATTACHMENT MADE
//  FROM IT. Attaching a score to an entry records the library file's own path
//  (no copy), so removing the library item used to delete the file under the
//  attachment. The file is now kept while any attachment refers to it.
//
//  C-139 — AN INDEX THIS BUILD CANNOT READ IS NOT AN EMPTY LIBRARY. The store
//  reports it, refuses every write, and leaves the stored bytes untouched.
//
//  ISOLATION: a private UserDefaults suite, a temporary Scores directory and a
//  temporary Core Data store; the app's own library is never touched.
//

import XCTest
import CoreData
import UIKit
@testable import Etudes

@MainActor
final class C138ScoreLibraryTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempDir: URL!
    private var container: NSPersistentContainer!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "c138-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("c138-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        container = NSPersistentContainer(name: "MOTIVO")
        let description = NSPersistentStoreDescription(url: tempDir.appendingPathComponent("store.sqlite"))
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        container = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func makeStore() -> ScoreLibraryStore {
        let store = ScoreLibraryStore(defaults: defaults, scoresDirectory: tempDir.appendingPathComponent("Scores", isDirectory: true))
        store.attachmentContext = { [container] in container?.viewContext }
        return store
    }

    private func makePDF(_ name: String = "source.pdf") throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            ("C-138" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
        }
        return url
    }

    /// The editor's path: an Attachment row whose stored path IS the library file.
    private func attachScore(_ url: URL) throws {
        let ctx = container.viewContext
        let session = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        session.setValue(UUID(), forKey: "id"); session.setValue("S", forKey: "title"); session.setValue(Date(), forKey: "timestamp")
        let attachment = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: ctx)
        attachment.setValue(UUID(), forKey: "id"); attachment.setValue("pdf", forKey: "kind"); attachment.setValue(Date(), forKey: "createdAt")
        attachment.setValue(url.path, forKey: "fileURL"); attachment.setValue(session, forKey: "session")
        try ctx.save()
    }

    // MARK: C-138

    func testDeletingAReferencedScoreKeepsItsFile() throws {
        let store = makeStore()
        let item = try store.importPDF(from: try makePDF(), displayName: "Referenced")
        let url = store.url(for: item)
        try attachScore(url)

        store.delete(item)

        XCTAssertTrue(store.items.isEmpty, "the library item is removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the attachment's file survives the library delete")
    }

    func testDeletingAnUnreferencedScoreRemovesItsFile() throws {
        let store = makeStore()
        let item = try store.importPDF(from: try makePDF(), displayName: "Unreferenced")
        let url = store.url(for: item)
        // Another attachment, a different file: not a reference to this one.
        try attachScore(tempDir.appendingPathComponent("other.pdf"))

        store.delete(item)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAnUnreadableStoreCountsAsReferenced() throws {
        let store = makeStore()
        store.attachmentContext = { nil }
        let item = try store.importPDF(from: try makePDF(), displayName: "Doubt")
        let url = store.url(for: item)
        store.delete(item)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "a doubt never deletes")
    }

    // MARK: C-139

    func testDamagedIndexIsReportedAndNeverOverwritten() throws {
        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: "scoreLibrary_v2")
        let store = makeStore()

        XCTAssertTrue(store.indexDamaged)
        XCTAssertTrue(store.items.isEmpty)

        XCTAssertThrowsError(try store.importPDF(from: try makePDF(), displayName: "Blocked")) { error in
            XCTAssertEqual(error as? ScoreLibraryError, .indexDamaged)
        }
        XCTAssertThrowsError(try store.addScannedPDF(data: Data([0x25, 0x50]), title: "Blocked"))
        let ghost = ScoreLibraryItem(title: "Ghost", fileName: "ghost.pdf", pageCount: 1)
        store.rename(ghost, to: "Renamed")
        store.toggleFavourite(ghost)
        store.delete(ghost)
        store.updateLastViewedPage(for: ghost.id, page: 2)
        store.setThumbnailPage(2, for: ghost.id)
        store.clearActiveScore()

        XCTAssertEqual(defaults.data(forKey: "scoreLibrary_v2"), garbage, "the stored bytes are left exactly as they were")
        XCTAssertTrue(store.items.isEmpty)
    }

    func testAReadableIndexIsNotDamaged() throws {
        let store = makeStore()
        _ = try store.importPDF(from: try makePDF(), displayName: "Fine")
        let reloaded = makeStore()
        XCTAssertFalse(reloaded.indexDamaged)
        XCTAssertEqual(reloaded.items.count, 1)
    }
}
