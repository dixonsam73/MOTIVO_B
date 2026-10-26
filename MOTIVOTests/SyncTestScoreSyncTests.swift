//
//  SyncTestScoreSyncTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  Stage I: the Scores library through the bound journal. The transition
//  queues every item with its file and unclocked metadata; a rename,
//  favourite or cover change queues the small meta record alone; libraries
//  combine by id (same titles stay two items; the same id never duplicates);
//  a restored copy with different metadata meets the existing conflict rule
//  with the displaced values logged; a differing file for the same id takes
//  the server's and keeps the local one; a damaged index sends nothing and
//  infers no deletion; positions travel on their own record, clamped, never
//  moving an open viewer; deletions in both directions keep a file a journal
//  attachment refers to; an erase resets the baseline.
//

#if SYNCTEST
import XCTest
import CoreData
import CloudKit
import UIKit
@testable import Etudes

@MainActor
final class SyncTestScoreSyncTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempDir: URL!
    private var store: JournalSyncStateStore!
    private var container: NSPersistentContainer!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "synctest-i-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-i-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("state.json"))
        container = NSPersistentContainer(name: "MOTIVO")
        let description = NSPersistentStoreDescription(url: tempDir.appendingPathComponent("store.sqlite"))
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)
        JournalScoreMirror.onChange = nil
        JournalScoreMirror.suppressed = false
        JournalScoreSync.clearDisplacedScores()
    }

    override func tearDown() async throws {
        JournalScoreMirror.onChange = nil
        JournalScoreMirror.suppressed = false
        JournalScoreSync.clearDisplacedScores()
        defaults.removePersistentDomain(forName: suiteName)
        container = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: helpers

    /// A library of its own (defaults suite + directory), like a device.
    private func makeLibrary(_ label: String = "A") -> ScoreLibraryStore {
        let library = ScoreLibraryStore(defaults: UserDefaults(suiteName: suiteName + label)!,
                                        scoresDirectory: tempDir.appendingPathComponent("Scores-\(label)", isDirectory: true))
        library.attachmentContext = { [container] in container?.viewContext }
        return library
    }

    private func makePDF(_ name: String, text: String = "stage I") throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            (text as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
            context.beginPage()
            ((text + " 2") as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
            context.beginPage()
            ((text + " 3") as NSString).draw(at: CGPoint(x: 20, y: 20), withAttributes: nil)
        }
        return url
    }

    private func scan(_ library: ScoreLibraryStore, positions: Bool = true, now: Date = Date()) -> [JournalSyncPendingChange] {
        JournalScoreSync.scan(snapshot: library.snapshot(), store: store, positions: positions, now: now)
    }

    private func record(_ name: String, _ library: ScoreLibraryStore) -> CKRecord? {
        JournalScoreSync.record(for: name, snapshot: library.snapshot(), store: store)
    }

    private func names(_ item: ScoreLibraryItem) -> (content: String, meta: String, position: String) {
        let id = item.id.uuidString
        return (JournalSyncRecordType.scoreName(for: id), JournalSyncRecordType.scoreMetaName(for: id), JournalSyncRecordType.scorePositionName(for: id))
    }

    /// A server copy of an item as the other device would send it.
    private func serverContent(id: UUID, fileURL: URL, fileName: String, title: String, pageCount: Int = 3) -> CKRecord {
        let r = CKRecord(recordType: JournalSyncRecordType.score,
                         recordID: CKRecord.ID(recordName: JournalSyncRecordType.scoreName(for: id.uuidString), zoneID: JournalRecordMapping.zoneID))
        r[JournalRecordMapping.assetKey] = CKAsset(fileURL: fileURL)
        r[JournalRecordMapping.fileHashKey] = (JournalAssetHash.hash(of: fileURL) ?? "") as CKRecordValue
        r[JournalRecordMapping.fileExtKey] = "pdf" as CKRecordValue
        r[JournalScoreKeys.fileName] = fileName as CKRecordValue
        r[JournalScoreKeys.pageCount] = NSNumber(value: pageCount)
        r[JournalScoreKeys.createdAt] = Date(timeIntervalSince1970: 1_700_000_000) as CKRecordValue
        r[JournalScoreKeys.initialTitle] = title as CKRecordValue
        return r
    }

    private func serverMeta(id: UUID, title: String, favourite: Bool, cover: Int, stamp: Date?) -> CKRecord {
        let r = CKRecord(recordType: JournalSyncRecordType.scoreMeta,
                         recordID: CKRecord.ID(recordName: JournalSyncRecordType.scoreMetaName(for: id.uuidString), zoneID: JournalRecordMapping.zoneID))
        r[JournalScoreKeys.title] = title as CKRecordValue
        r[JournalScoreKeys.isFavourite] = NSNumber(value: favourite)
        r[JournalScoreKeys.thumbnailPage] = NSNumber(value: cover)
        if let stamp { r[JournalScoreKeys.stamp] = stamp as CKRecordValue }
        return r
    }

    private func serverPosition(id: UUID, page: Int, stamp: Date?) -> CKRecord {
        let r = CKRecord(recordType: JournalSyncRecordType.scorePosition,
                         recordID: CKRecord.ID(recordName: JournalSyncRecordType.scorePositionName(for: id.uuidString), zoneID: JournalRecordMapping.zoneID))
        r[JournalScoreKeys.lastViewedPage] = NSNumber(value: page)
        if let stamp { r[JournalScoreKeys.stamp] = stamp as CKRecordValue }
        return r
    }

    private func apply(_ records: [CKRecord], _ library: ScoreLibraryStore, localPending: Bool? = nil) -> JournalScoreSync.Outcome {
        JournalScoreSync.apply(records, store: store, library: library, localPending: localPending) { _ in }
    }

    private func outboxNames(_ op: JournalSyncPendingChange.Op = .save) -> Set<String> {
        Set(store.state.outbox.filter { $0.op == op }.map(\.recordName))
    }

    // MARK: 1. Transition and edits

    func testTransitionQueuesEveryItemWithItsFileAndUnclockedMetadata() throws {
        let library = makeLibrary()
        let a = try library.importPDF(from: try makePDF("a.pdf"), displayName: "Bach")
        let b = try library.importPDF(from: try makePDF("b.pdf"), displayName: "Bach")   // same title, distinct item
        library.updateLastViewedPage(for: b.id, page: 2)

        let pending = scan(library)
        XCTAssertEqual(pending.count, 5, "2 files, 2 meta, 1 position")
        let aNames = names(a), bNames = names(b)
        XCTAssertTrue(outboxNames().isSuperset(of: [aNames.content, aNames.meta, bNames.content, bNames.meta, bNames.position]))
        XCTAssertTrue(pending.first { $0.recordName == aNames.meta }!.metadataOnly, "the transition's metadata is unclocked")
        XCTAssertNil(store.state.scoreStamps[a.id.uuidString])
        XCTAssertTrue(store.state.scoreScanDone)

        // The content record carries the file and its hash; the meta record carries no file, no clock.
        let content = try XCTUnwrap(record(aNames.content, library))
        XCTAssertNotNil(content[JournalRecordMapping.assetKey])
        XCTAssertEqual(content[JournalRecordMapping.fileHashKey] as? String, JournalAssetHash.hash(of: library.url(for: a)))
        XCTAssertEqual(content[JournalScoreKeys.initialTitle] as? String, "Bach")
        let meta = try XCTUnwrap(record(aNames.meta, library))
        XCTAssertNil(meta[JournalRecordMapping.assetKey])
        XCTAssertNil(meta[JournalScoreKeys.stamp])
        XCTAssertEqual(meta[JournalScoreKeys.title] as? String, "Bach")
        let position = try XCTUnwrap(record(bNames.position, library))
        XCTAssertEqual((position[JournalScoreKeys.lastViewedPage] as? NSNumber)?.intValue, 2)

        XCTAssertTrue(scan(library).isEmpty, "a repeat scan queues nothing")
    }

    func testRenameFavouriteAndCoverQueueTheMetaRecordAloneWithAClock() throws {
        let library = makeLibrary()
        let a = try library.importPDF(from: try makePDF("a.pdf"), displayName: "Bach")
        _ = scan(library)
        store.update { $0.outbox.removeAll(); $0.assetHashes[self.names(a).content] = "served" }

        library.rename(a, to: "Bach Suite 1")
        let t = Date()
        let pending = scan(library, now: t)
        XCTAssertEqual(pending.map(\.recordName), [names(a).meta])
        XCTAssertTrue(pending[0].metadataEdit)
        XCTAssertEqual(store.state.scoreStamps[a.id.uuidString], t)
        let meta = try XCTUnwrap(record(names(a).meta, library))
        XCTAssertEqual(meta[JournalScoreKeys.title] as? String, "Bach Suite 1")
        XCTAssertEqual(meta[JournalScoreKeys.stamp] as? Date, t)
        XCTAssertNil(meta[JournalRecordMapping.assetKey])
        XCTAssertFalse(outboxNames().contains(names(a).content), "the file is never requeued by a rename")

        store.update { $0.outbox.removeAll() }
        library.toggleFavourite(library.items[0])
        XCTAssertEqual(scan(library).map(\.recordName), [names(a).meta])
        store.update { $0.outbox.removeAll() }
        library.setThumbnailPage(3, for: a.id)
        XCTAssertEqual(scan(library).map(\.recordName), [names(a).meta])
        // Device-local state is not a change.
        store.update { $0.outbox.removeAll() }
        library.markOpened(library.items[0])
        library.clearActiveScore()
        XCTAssertTrue(scan(library).isEmpty)
    }

    func testAnItemAddedAfterTheTransitionIsAClockedEdit() throws {
        let library = makeLibrary()
        _ = scan(library)   // empty library: the transition is done
        let a = try library.importPDF(from: try makePDF("a.pdf"), displayName: "New")
        let pending = scan(library)
        XCTAssertEqual(Set(pending.map(\.recordName)), [names(a).content, names(a).meta])
        XCTAssertTrue(pending.first { $0.recordName == names(a).meta }!.metadataEdit)
        XCTAssertNotNil(store.state.scoreStamps[a.id.uuidString])
    }

    func testPositionsScanOnTheirOwnCadence() throws {
        let library = makeLibrary()
        let a = try library.importPDF(from: try makePDF("a.pdf"), displayName: "Bach")
        _ = scan(library)
        store.update { $0.outbox.removeAll() }
        library.updateLastViewedPage(for: a.id, page: 3)
        XCTAssertTrue(scan(library, positions: false).isEmpty, "a metadata scan leaves positions alone")
        let pending = scan(library, positions: true)
        XCTAssertEqual(pending.map(\.recordName), [names(a).position])
        XCTAssertNotNil(store.state.scorePositionStamps[a.id.uuidString])
    }

    // MARK: 2. Combining libraries

    func testTwoLibrariesCombineByIdAndSameTitlesStayTwoItems() throws {
        let phone = makeLibrary("phone")
        let pad = makeLibrary("pad")
        let p1 = try phone.importPDF(from: try makePDF("p1.pdf", text: "phone"), displayName: "Bach")
        let d1 = try pad.importPDF(from: try makePDF("d1.pdf", text: "pad"), displayName: "Bach")
        pad.toggleFavourite(d1)

        // The pad's records arrive on the phone.
        let records = [serverContent(id: d1.id, fileURL: pad.url(for: d1), fileName: d1.fileName, title: "Bach"),
                       serverMeta(id: d1.id, title: "Bach", favourite: true, cover: 1, stamp: nil)]
        let outcome = apply(records, phone)
        XCTAssertEqual(outcome.applied, 2)
        XCTAssertEqual(phone.items.count, 2, "both “Bach” items exist; nothing merged by title")
        let imported = try XCTUnwrap(phone.items.first { $0.id == d1.id })
        XCTAssertTrue(imported.isFavourite)
        XCTAssertTrue(FileManager.default.fileExists(atPath: phone.url(for: imported).path))
        XCTAssertNotEqual(phone.url(for: imported), pad.url(for: d1), "the file is a copy in this library's directory")
        XCTAssertEqual(phone.items.first { $0.id == p1.id }?.title, "Bach")

        // The same records again: still one item for that id.
        _ = apply(records, phone)
        XCTAssertEqual(phone.items.count, 2)
        XCTAssertEqual(phone.items.filter { $0.id == d1.id }.count, 1)

        // The imported item is already exchanged: the next scan sends nothing for it.
        let pending = scan(phone)
        XCTAssertFalse(pending.contains { $0.recordName.contains(d1.id.uuidString) })
    }

    func testTheFirstMetaRecordForAnItemMadeFromItsFileIsNotAConflict() throws {
        let phone = makeLibrary("phone")
        let id = UUID()
        _ = apply([serverContent(id: id, fileURL: try makePDF("c.pdf"), fileName: "c.pdf", title: "Initial")], phone)
        XCTAssertEqual(phone.items.first?.title, "Initial")
        let before = store.state.conflicts.count
        _ = apply([serverMeta(id: id, title: "Real title", favourite: true, cover: 1, stamp: nil)], phone)
        XCTAssertEqual(phone.items.first?.title, "Real title")
        XCTAssertTrue(phone.items.first!.isFavourite)
        XCTAssertEqual(store.state.conflicts.count, before, "the item had no metadata of its own yet")
    }

    func testHeldMetadataAndPositionLandWhenTheItemArrives() throws {
        let phone = makeLibrary("phone")
        let id = UUID()
        let source = try makePDF("held.pdf")
        let stamp = Date()
        var outcome = apply([serverMeta(id: id, title: "Held title", favourite: true, cover: 2, stamp: stamp),
                             serverPosition(id: id, page: 3, stamp: stamp)], phone)
        XCTAssertEqual(outcome.held, 2)
        XCTAssertEqual(store.state.awaitingScore.count, 2)
        XCTAssertTrue(phone.items.isEmpty)

        outcome = apply([serverContent(id: id, fileURL: source, fileName: "held.pdf", title: "Initial")], phone)
        XCTAssertEqual(outcome.applied, 3)
        let item = try XCTUnwrap(phone.items.first)
        XCTAssertEqual(item.title, "Held title")
        XCTAssertTrue(item.isFavourite)
        XCTAssertEqual(item.thumbnailPage, 2)
        XCTAssertEqual(item.lastViewedPage, 3)
        XCTAssertTrue(store.state.awaitingScore.isEmpty)
        XCTAssertEqual(store.state.scoreStamps[id.uuidString], stamp)
    }

    // MARK: 3. The same id with different versions (a restored copy)

    func testSameIdDifferentMetadataFollowsTheConflictRuleAndLogsTheDisplacedValues() throws {
        let library = makeLibrary()
        let a = try library.importPDF(from: try makePDF("a.pdf"), displayName: "Local title")
        _ = scan(library)   // transition: unclocked
        store.update { $0.outbox.removeAll() }

        // Both predate sync (no clock): ties go to the server; the local value is logged.
        _ = apply([serverMeta(id: a.id, title: "Server title", favourite: false, cover: 1, stamp: nil)], library)
        XCTAssertEqual(library.items[0].title, "Server title")
        XCTAssertTrue(store.state.conflicts.contains { $0.losingTitle?.contains("Local title") == true && $0.winner == "server" })

        // A clocked local edit beats an older server copy: kept and resent.
        let t1 = Date()
        library.rename(library.items[0], to: "Newer local")
        _ = scan(library, now: t1)
        store.update { $0.outbox.removeAll() }
        let outcome = apply([serverMeta(id: a.id, title: "Older server", favourite: true, cover: 2, stamp: t1.addingTimeInterval(-60))], library)
        XCTAssertEqual(library.items[0].title, "Newer local")
        XCTAssertFalse(library.items[0].isFavourite)
        XCTAssertEqual(outcome.resend.map(\.recordName), [names(a).meta])
        XCTAssertTrue(store.state.conflicts.contains { $0.losingTitle?.contains("Older server") == true && $0.winner == "local" })

        // A newer server copy displaces the local one (the whole record).
        _ = apply([serverMeta(id: a.id, title: "Newest server", favourite: true, cover: 3, stamp: t1.addingTimeInterval(60))], library)
        XCTAssertEqual(library.items[0].title, "Newest server")
        XCTAssertTrue(library.items[0].isFavourite)
        XCTAssertEqual(library.items[0].thumbnailPage, 3)
        XCTAssertTrue(store.state.conflicts.contains { $0.losingTitle?.contains("Newer local") == true })
        XCTAssertEqual(store.state.scoreStamps[a.id.uuidString], t1.addingTimeInterval(60))
        XCTAssertEqual(library.items.count, 1, "never a duplicate")
    }

    func testSameIdDifferentFileTakesTheServersAndKeepsTheLocalCopy() throws {
        let library = makeLibrary()
        let a = try library.importPDF(from: try makePDF("a.pdf", text: "local bytes"), displayName: "Score")
        _ = scan(library)
        let localHash = try XCTUnwrap(JournalAssetHash.hash(of: library.url(for: a)))
        let other = try makePDF("other.pdf", text: "server bytes")
        let serverHash = try XCTUnwrap(JournalAssetHash.hash(of: other))

        let outcome = apply([serverContent(id: a.id, fileURL: other, fileName: a.fileName, title: "Score")], library)
        XCTAssertEqual(outcome.applied, 1)
        XCTAssertEqual(library.items.count, 1)
        XCTAssertEqual(JournalAssetHash.hash(of: library.url(for: a)), serverHash, "the server's file is in place")
        XCTAssertEqual(store.state.assetHashes[names(a).content], serverHash)
        let kept = JournalScoreSync.displacedScores()
        XCTAssertEqual(kept.map { $0.deletingPathExtension().lastPathComponent }, [localHash], "the local file is set aside by hash")
        XCTAssertTrue(store.state.conflicts.contains { $0.recordType == JournalSyncRecordType.score })
        XCTAssertTrue(scan(library).isEmpty, "nothing bounces back")
    }

    // MARK: 4. Damaged index (C-139)

    func testADamagedIndexSendsNothingInfersNoDeletionAndIsNeverOverwritten() throws {
        let library = makeLibrary()
        let a = try library.importPDF(from: try makePDF("a.pdf"), displayName: "Kept")
        _ = scan(library)
        XCTAssertEqual(store.state.scoreFingerprints.count, 1)
        store.update { $0.outbox.removeAll() }

        // The index becomes unreadable (a later build's format, a corrupt write).
        let garbage = Data("{broken".utf8)
        let libraryDefaults = UserDefaults(suiteName: suiteName + "A")!
        libraryDefaults.set(garbage, forKey: "scoreLibrary_v2")
        let reloaded = makeLibrary()
        XCTAssertTrue(reloaded.indexDamaged)

        let pending = scan(reloaded)
        XCTAssertTrue(pending.isEmpty)
        XCTAssertTrue(outboxNames(.delete).isEmpty, "an unreadable library is not an empty one: no deletion inferred")
        XCTAssertEqual(store.state.scoreFingerprints.count, 1, "what was exchanged is remembered")
        XCTAssertTrue(store.state.scoreIndexDamagedNoted)

        // Imports refuse too, and the bytes stay.
        let outcome = apply([serverContent(id: UUID(), fileURL: try makePDF("x.pdf"), fileName: "x.pdf", title: "X"),
                             serverMeta(id: a.id, title: "Renamed elsewhere", favourite: true, cover: 1, stamp: Date())], reloaded)
        XCTAssertEqual(outcome.applied, 0)
        _ = JournalScoreSync.applyDeletions([names(a).content], store: store, library: reloaded) { _ in }
        XCTAssertEqual(libraryDefaults.data(forKey: "scoreLibrary_v2"), garbage)
    }

    // MARK: 5. Reading position

    func testPositionIsClampedAppliedWhenNewerAndKeptWhenOlderWithNoConflictEntry() throws {
        let library = makeLibrary()
        let a = try library.importPDF(from: try makePDF("a.pdf"), displayName: "Score")   // 3 pages
        _ = scan(library)
        store.update { $0.outbox.removeAll() }

        // Older than nothing: applied, clamped to the document.
        var outcome = apply([serverPosition(id: a.id, page: 40, stamp: Date(timeIntervalSince1970: 1_700_000_000))], library)
        XCTAssertEqual(outcome.applied, 1)
        XCTAssertEqual(library.items[0].lastViewedPage, 3)
        XCTAssertEqual(store.state.scorePositions[a.id.uuidString], 3)

        // A local page turn afterwards is newer: kept, and the server's older copy does not move it.
        let t = Date()
        library.updateLastViewedPage(for: a.id, page: 1)
        _ = scan(library, now: t)
        store.update { $0.outbox.removeAll() }
        outcome = apply([serverPosition(id: a.id, page: 2, stamp: t.addingTimeInterval(-30))], library)
        XCTAssertEqual(library.items[0].lastViewedPage, 1)
        XCTAssertEqual(outcome.resend.map(\.recordName), [names(a).position])

        // A newer remote page displaces it; no conflict entry, counted only.
        outcome = apply([serverPosition(id: a.id, page: 2, stamp: t.addingTimeInterval(30))], library)
        XCTAssertEqual(library.items[0].lastViewedPage, 2)
        XCTAssertEqual(store.state.scorePositionsDisplaced, 1)
        XCTAssertFalse(store.state.conflicts.contains { $0.recordType == JournalSyncRecordType.scorePosition })
        XCTAssertNil(library.activeScoreID, "the currently open score is never set by an import")
    }

    /// Seen on device 2026-10-26: with the viewer open on page 1, remote
    /// pages 3 then 2 were written into the saved page, and the dismissal
    /// published 2. Now an open viewer's score ignores imported positions and
    /// the dismissal publishes the page on screen even if unchanged.
    func testAnOpenViewerKeepsItsPageAndTheDismissalPublishesIt() throws {
        let library = makeLibrary()
        let a = try library.importPDF(from: try makePDF("a.pdf"), displayName: "Score")
        _ = scan(library)
        store.update { $0.outbox.removeAll() }
        library.viewerDidOpen(a.id)
        library.updateLastViewedPage(for: a.id, page: 1)
        _ = scan(library)                          // page 1 known
        store.update { $0.outbox.removeAll() }

        let t = Date()
        let outcome = apply([serverPosition(id: a.id, page: 3, stamp: t.addingTimeInterval(60))], library)
        XCTAssertEqual(outcome.applied, 0)
        XCTAssertEqual(library.items[0].lastViewedPage, 1, "the page on screen stays")
        XCTAssertNil(library.applyImportedPosition(id: a.id, page: 2))

        library.viewerDidClose(a.id)
        XCTAssertNil(library.openViewerID)
        let pending = JournalScoreSync.scan(snapshot: library.snapshot(), store: store, positions: true, force: [a.id], now: t.addingTimeInterval(120))
        XCTAssertEqual(pending.map(\.recordName), [names(a).position], "the dismissal publishes page 1 although it is unchanged")
        XCTAssertEqual(store.state.scorePositionStamps[a.id.uuidString], t.addingTimeInterval(120))
        let record = try XCTUnwrap(self.record(names(a).position, library))
        XCTAssertEqual((record[JournalScoreKeys.lastViewedPage] as? NSNumber)?.intValue, 1)
        // Closed now: the same remote page is applied as usual.
        _ = apply([serverPosition(id: a.id, page: 3, stamp: t.addingTimeInterval(180))], library)
        XCTAssertEqual(library.items[0].lastViewedPage, 3)
    }

    func testAPositionImportNeverTouchesMetadataOrTheCurrentlyOpenScore() throws {
        let library = makeLibrary()
        let a = try library.importPDF(from: try makePDF("a.pdf"), displayName: "Score")
        library.markOpened(a)
        _ = scan(library)
        store.update { $0.outbox.removeAll() }
        library.rename(library.items[0], to: "Renamed here")
        let t = Date()
        _ = scan(library, now: t)
        _ = apply([serverPosition(id: a.id, page: 2, stamp: t.addingTimeInterval(60))], library)
        XCTAssertEqual(library.items[0].title, "Renamed here", "a page turn elsewhere never displaces a rename")
        XCTAssertEqual(library.activeScoreID, a.id)
        XCTAssertEqual(library.items[0].lastViewedPage, 2)
    }

    // MARK: 6. Deletions and journal attachments

    private func attach(_ url: URL) throws -> NSManagedObject {
        let ctx = container.viewContext
        let session = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        session.setValue(UUID(), forKey: "id"); session.setValue("S", forKey: "title"); session.setValue(Date(), forKey: "timestamp")
        let attachment = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: ctx)
        attachment.setValue(UUID(), forKey: "id"); attachment.setValue("pdf", forKey: "kind"); attachment.setValue(Date(), forKey: "createdAt")
        attachment.setValue(url.path, forKey: "fileURL"); attachment.setValue(session, forKey: "session")
        try ctx.save()
        return attachment
    }

    func testALocalDeletionQueuesThreeDeletionsAndARemoteOneRemovesTheItemButKeepsAReferencedFile() throws {
        let library = makeLibrary()
        let a = try library.importPDF(from: try makePDF("a.pdf"), displayName: "Attached")
        let b = try library.importPDF(from: try makePDF("b.pdf"), displayName: "Plain")
        _ = scan(library)
        store.update { $0.outbox.removeAll() }
        let aURL = library.url(for: a), bURL = library.url(for: b)
        _ = try attach(aURL)

        // Local delete of the attached one: item gone, file kept, three deletions queued.
        library.delete(a)
        let pending = scan(library)
        XCTAssertEqual(Set(pending.filter { $0.op == .delete }.map(\.recordName)), [names(a).content, names(a).meta, names(a).position])
        XCTAssertTrue(FileManager.default.fileExists(atPath: aURL.path))
        XCTAssertNil(store.state.scoreFingerprints[a.id.uuidString])

        // Remote delete of the plain one: item and file gone.
        let removed = JournalScoreSync.applyDeletions([names(b).content, names(b).meta], store: store, library: library) { _ in }
        XCTAssertEqual(removed, 1)
        XCTAssertTrue(library.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: bURL.path))
        XCTAssertNil(store.state.scoreFingerprints[b.id.uuidString])

        // Remote delete of an item a journal attachment refers to: item gone, file kept.
        let c = try library.importPDF(from: try makePDF("c.pdf"), displayName: "Attached too")
        let cURL = library.url(for: c)
        _ = try attach(cURL)
        _ = JournalScoreSync.applyDeletions([names(c).content], store: store, library: library) { _ in }
        XCTAssertTrue(library.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cURL.path), "the journal attachment still opens")
    }

    /// The importer's remote attachment deletion goes through the guarded
    /// deletion: a library PDF the attachment pointed at survives.
    func testARemoteAttachmentDeletionNeverRemovesALibraryPDF() throws {
        // The guard names Documents/Scores, so this library lives there under a test file name.
        let scoresDir = ScoreLibraryStore.defaultScoresDirectory()
        try FileManager.default.createDirectory(at: scoresDir, withIntermediateDirectories: true)
        let fileName = "synctest-i-\(UUID().uuidString).pdf"
        let libraryFile = scoresDir.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: try makePDF("lib.pdf"), to: libraryFile)
        defer { try? FileManager.default.removeItem(at: libraryFile) }
        let attachment = try attach(libraryFile)
        let id = attachment.value(forKey: "id") as! UUID

        let ctx = container.newBackgroundContext()
        ctx.transactionAuthor = JournalSyncAuthor.sync
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let importer = JournalImporter(context: ctx, store: store, customOwner: "local:TEST")
        ctx.performAndWait {
            importer.importDeletions([(JournalRecordMapping.recordID(for: id), JournalSyncRecordType.attachment)])
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryFile.path), "the library's PDF survives the attachment's remote deletion")
        let request = NSFetchRequest<NSManagedObject>(entityName: "Attachment")
        XCTAssertEqual(try container.viewContext.count(for: request), 0, "the attachment row itself is removed")
    }

    // MARK: 7. Erase

    func testAnEraseResetsTheBaselineSoNothingErasedIsSentAndANewScoreIsAnEdit() throws {
        let library = makeLibrary()
        _ = try library.importPDF(from: try makePDF("a.pdf"), displayName: "Erased")
        _ = scan(library)
        XCTAssertEqual(store.state.scoreFingerprints.count, 1)

        JournalLocalRemoval.begin(store: store, reason: "test")
        library.wipeOnDiskAndCacheForFactoryReset()
        XCTAssertTrue(scan(library).isEmpty, "no scan during a removal")
        JournalLocalRemoval.finish(store: store, container: container)
        XCTAssertTrue(store.state.scoreFingerprints.isEmpty)
        XCTAssertTrue(store.state.scoreScanDone)
        XCTAssertTrue(outboxNames(.delete).isEmpty, "nothing erased becomes a cloud deletion")

        let fresh = try library.importPDF(from: try makePDF("n.pdf"), displayName: "After")
        let pending = scan(library)
        XCTAssertEqual(Set(pending.map(\.recordName)), [names(fresh).content, names(fresh).meta])
        XCTAssertNotNil(store.state.scoreStamps[fresh.id.uuidString], "a score added after the erase is a clocked edit")
    }

    // MARK: 8. Send conflicts

    func testASendConflictOnMetadataResolvesLikeAnImport() throws {
        let library = makeLibrary()
        let a = try library.importPDF(from: try makePDF("a.pdf"), displayName: "Mine")
        _ = scan(library)   // unclocked transition copy pending
        // The server already holds a clocked copy: ours yields, the pending save is settled.
        let outcome = apply([serverMeta(id: a.id, title: "Theirs", favourite: false, cover: 1, stamp: Date())], library, localPending: true)
        XCTAssertEqual(library.items[0].title, "Theirs")
        XCTAssertTrue(outcome.settled.contains(names(a).meta))
        XCTAssertFalse(outboxNames().contains(names(a).meta))
    }
}
#endif
