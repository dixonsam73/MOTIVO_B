//
//  C5ScoreAdoptionIdentityTests.swift
//  MOTIVOTests
//
//  C-5 — ADDING THE SAME RECEIVED PDF TO SCORES AGAIN MUST NOT DUPLICATE IT.
//
//  "Add to Scores" on a received attachment imported a fresh copy on every tap.
//  An adoption is identified by the received attachment's id together with its
//  file still existing: a repeat returns that Score untouched, while re-adoption
//  after the Score (or its file) is gone imports again. Ordinary imports keep
//  their existing behaviour.
//
//  WHAT THIS DOES NOT SHOW: the UI tap path (its one argument is reviewed in
//  source) or device behaviour. Scores adopted before the change carry no source
//  id and cannot be matched.
//
//  ISOLATION: the real `ScoreLibraryStore` singleton in the disposable hosted test
//  process. Its full in-memory state, raw persisted defaults and Scores file names
//  are snapshotted first; only test-created items and files are removed, the raw
//  defaults are restored exactly, and the state is verified equal afterwards.
//

import XCTest
import UIKit
@testable import Etudes

@MainActor
final class C5ScoreAdoptionIdentityTests: XCTestCase {

    private static let libraryKey = "scoreLibrary_v2"
    private static let activeKey = "scoreLibrary_activeScore_v2"

    private var store: ScoreLibraryStore { ScoreLibraryStore.shared }
    private var baselineItems: [ScoreLibraryItem] = []
    private var baselineActive: UUID?
    private var baselineLibraryDefault: Any?
    private var baselineActiveDefault: Any?
    private var baselineFiles: Set<String> = []
    private var tempDir: URL!

    // MARK: - The adoption under test

    /// Adopt a received attachment with id `attachmentID` into Scores, as
    /// `ConnectedAttachmentShareUI.saveToScores` does. Before the fix this shim called
    /// `importPDF(from:displayName:)`, which had no source identity.
    private func adopt(_ url: URL, _ attachmentID: UUID) throws -> ScoreLibraryItem {
        try store.importPDF(from: url, displayName: "C-5 adopted score", sourceAttachmentID: attachmentID)
    }

    // MARK: - Setup / teardown

    override func setUp() async throws {
        try await super.setUp()
        _ = store   // initialise the singleton (it loads persisted state) before the baseline
        baselineItems = store.items
        baselineActive = store.activeScoreID
        baselineLibraryDefault = UserDefaults.standard.object(forKey: Self.libraryKey)
        baselineActiveDefault = UserDefaults.standard.object(forKey: Self.activeKey)
        baselineFiles = scoresFileNames()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("C5-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        let baselineIDs = Set(baselineItems.map(\.id))
        for item in store.items where !baselineIDs.contains(item.id) {
            store.delete(item)
        }
        for name in scoresFileNames().subtracting(baselineFiles) {
            try? FileManager.default.removeItem(at: scoresDirectory().appendingPathComponent(name))
        }
        restore(baselineLibraryDefault, forKey: Self.libraryKey)
        restore(baselineActiveDefault, forKey: Self.activeKey)
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }

        XCTAssertEqual(store.items, baselineItems, "C-5 restoration: in-memory Scores metadata differs from the baseline")
        XCTAssertEqual(store.activeScoreID, baselineActive, "C-5 restoration: active Score selection differs from the baseline")
        XCTAssertEqual(scoresFileNames(), baselineFiles, "C-5 restoration: Scores file set differs from the baseline")
        try await super.tearDown()
    }

    // MARK: - Cases

    /// 1 — a repeated adoption of the same received attachment returns the existing
    /// Score untouched, and creates no second item or file.
    func testRepeatedAdoptionReturnsTheExistingScoreUntouched() throws {
        let source = try makePDF()
        let id = UUID()

        let first = try adopt(source, id)
        store.rename(first, to: "Renamed by member")
        store.toggleFavourite(store.items.first { $0.id == first.id }!)
        let filesAfterFirst = scoresFileNames()

        let second = try adopt(source, id)

        XCTAssertEqual(testItems().count, 1, "a repeated adoption must not add another Score")
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(second.title, "Renamed by member")
        XCTAssertTrue(second.isFavourite)
        XCTAssertEqual(scoresFileNames(), filesAfterFirst, "a repeated adoption must not copy the PDF again")
    }

    /// 2 — after the member deletes the adopted Score, adopting again imports it again.
    func testReadoptionAfterLocalDeletionImportsAgain() throws {
        let source = try makePDF()
        let id = UUID()

        let first = try adopt(source, id)
        store.delete(first)
        XCTAssertEqual(testItems().count, 0)

        let again = try adopt(source, id)
        XCTAssertEqual(testItems().count, 1)
        XCTAssertNotEqual(again.id, first.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: again).path))
    }

    /// 3 — an ordinary import (no source attachment) keeps today's behaviour.
    func testOrdinaryImportsAreUnchanged() throws {
        let source = try makePDF()
        _ = try store.importPDF(from: source, displayName: "C-5 manual import")
        _ = try store.importPDF(from: source, displayName: "C-5 manual import")
        XCTAssertEqual(testItems().count, 2, "manual imports are not deduplicated")
    }

    /// 4 — a saved library written before the change still decodes, and re-encodes
    /// without a source key.
    func testLegacySavedLibraryDecodes() throws {
        let legacy = """
        [{"createdAt":0,"fileName":"legacy.pdf","id":"\(UUID().uuidString)","isFavourite":true,\
        "lastViewedPage":3,"pageCount":4,"thumbnailPage":1,"title":"Legacy Score"}]
        """
        let items = try JSONDecoder().decode([ScoreLibraryItem].self, from: Data(legacy.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Legacy Score")
        XCTAssertEqual(items[0].lastViewedPage, 3)
        let reencoded = String(decoding: try JSONEncoder().encode(items), as: UTF8.self)
        XCTAssertFalse(reencoded.contains("sourceAttachmentID"), "an item without a source must not gain a source key")
    }

    /// 5 — an adopted Score whose file is gone does not block adoption: a new
    /// usable copy is imported, the missing-file item is left alone, and a further
    /// repeat returns the usable copy.
    func testMissingFileAdoptionImportsOnceThenDeduplicates() throws {
        let source = try makePDF()
        let id = UUID()

        let stale = try adopt(source, id)
        try FileManager.default.removeItem(at: store.url(for: stale))

        let usable = try adopt(source, id)
        XCTAssertNotEqual(usable.id, stale.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: usable).path))
        XCTAssertEqual(testItems().count, 2, "the missing-file item is left alone")

        let repeatAdoption = try adopt(source, id)
        XCTAssertEqual(testItems().count, 2, "a repeat must return the usable copy, not import a third")
        XCTAssertEqual(repeatAdoption.id, usable.id)
    }

    // MARK: - Helpers

    private func testItems() -> [ScoreLibraryItem] {
        let baselineIDs = Set(baselineItems.map(\.id))
        return store.items.filter { !baselineIDs.contains($0.id) }
    }

    private func makePDF() throws -> URL {
        let url = tempDir.appendingPathComponent("received.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            ("C-5" as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
        }
        return url
    }

    private func scoresDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scores", isDirectory: true)
    }

    private func scoresFileNames() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: scoresDirectory().path)) ?? [])
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
