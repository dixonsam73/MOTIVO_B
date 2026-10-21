//
//  SyncTestMetadataTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  Stage F: audio/video titles, attachment privacy, favourites and selected
//  PDF pages travel as fields of their records. Encodings; outgoing records
//  carry the side stores; imports write them store-only (clearing included);
//  a write point touches its row as a user edit; the one-off migration
//  queues rows with their existing stamps and does not beat a later edit.
//

#if SYNCTEST
import XCTest
import CoreData
import CloudKit
@testable import Etudes

final class SyncTestMetadataTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var store: JournalSyncStateStore!
    private var tempDir: URL!
    private var stamp: NSObjectProtocol?
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var keptContexts: [NSManagedObjectContext] = []
    private let scope = "viewer.test"

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-f-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        container = NSPersistentContainer(name: "MOTIVO")
        let description = NSPersistentStoreDescription(url: tempDir.appendingPathComponent("store.sqlite"))
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        try XCTUnwrap(loadError == nil ? () : nil)
        container.viewContext.transactionAuthor = JournalSyncAuthor.app
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        store = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("state.json"))
        stamp = JournalUserEditStamp.install()
        suiteName = "synctest-f-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        JournalMetadataMirror.container = container
    }

    override func tearDownWithError() throws {
        if let stamp { NotificationCenter.default.removeObserver(stamp) }
        JournalMetadataMirror.container = nil
        defaults.removePersistentDomain(forName: suiteName)
        keptContexts.removeAll()
        container = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: helpers

    @discardableResult
    private func makeSession(in ctx: NSManagedObjectContext, id: UUID = UUID(), stamp: Date? = nil) -> NSManagedObject {
        let s = NSEntityDescription.insertNewObject(forEntityName: "Session", into: ctx)
        s.setValue(id, forKey: "id"); s.setValue("T", forKey: "title"); s.setValue(Date(), forKey: "timestamp")
        if let stamp { s.setValue(stamp, forKey: "userModifiedAt") }
        return s
    }

    @discardableResult
    private func makeAttachment(session: NSManagedObject, in ctx: NSManagedObjectContext, id: UUID = UUID(), kind: String = "audio") -> NSManagedObject {
        let a = NSEntityDescription.insertNewObject(forEntityName: "Attachment", into: ctx)
        a.setValue(id, forKey: "id"); a.setValue(kind, forKey: "kind"); a.setValue(Date(), forKey: "createdAt")
        a.setValue("/tmp/\(id.uuidString).m4a", forKey: "fileURL"); a.setValue(session, forKey: "session")
        return a
    }

    private func importer(_ queue: RecordingSendQueue = RecordingSendQueue()) -> (JournalImporter, NSManagedObjectContext) {
        let ctx = container.newBackgroundContext()
        ctx.transactionAuthor = JournalSyncAuthor.sync
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        keptContexts.append(ctx)
        let imp = JournalImporter(context: ctx, store: store, customOwner: "local:TEST")
        imp.queue = queue
        imp.viewerScope = { self.scope }
        return (imp, ctx)
    }

    private func attachmentRecord(id: UUID, sessionID: UUID, kind: String = "audio", displayName: String?, isPrivate: Bool?, pages: String?,
                                  stamp: Date = Date(timeIntervalSince1970: 1_000)) -> CKRecord {
        let r = CKRecord(recordType: "Attachment", recordID: JournalRecordMapping.recordID(for: id))
        r["kind"] = kind as CKRecordValue
        r["createdAt"] = Date() as CKRecordValue
        r["userModifiedAt"] = stamp as CKRecordValue
        r["fileExt"] = "m4a" as CKRecordValue
        r[JournalRecordMapping.sessionRefKey] = CKRecord.Reference(recordID: JournalRecordMapping.recordID(for: sessionID), action: .none)
        if let displayName { r["displayName"] = displayName as CKRecordValue }
        if let isPrivate { r[JournalMetadataKeys.isPrivate] = NSNumber(value: isPrivate) }
        if let pages { r[JournalMetadataKeys.selectedPages] = pages as CKRecordValue }
        return r
    }

    /// What the viewers read, without the main-actor helper: the shared store entry.
    private func sharedTitle(_ id: UUID) -> String? {
        let raw = (defaults.dictionary(forKey: AttachmentTitlePersistenceKeys.legacyKey(for: .audio)) as? [String: String])?[id.uuidString] ?? ""
        return raw.isEmpty ? nil : raw
    }

    private func wait(for condition: @escaping () -> Bool, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertTrue(condition(), "condition not met within \(timeout)s")
    }

    // MARK: encodings

    func testEncodingsAndScopes() {
        XCTAssertEqual(JournalMetadataCodec.pagesString(nil), "[]")
        XCTAssertEqual(JournalMetadataCodec.pagesString([3, 1, 3, 0]), "[1,3]")
        XCTAssertEqual(JournalMetadataCodec.pages(from: "[1,3]"), [1, 3])
        XCTAssertEqual(JournalMetadataCodec.pages(from: "[]"), [], "whole document, explicitly")
        XCTAssertNil(JournalMetadataCodec.pages(from: nil), "absent = no information")
        XCTAssertEqual(JournalMetadataCodec.viewerScope(currentUserID: " Owner.A "), "owner.a")
        XCTAssertEqual(JournalMetadataCodec.viewerScope(currentUserID: nil), "unknown")
        XCTAssertEqual(JournalMetadataCodec.titleKind(for: "Video"), .video)
        XCTAssertNil(JournalMetadataCodec.titleKind(for: "pdf"))
    }

    // MARK: outgoing records

    func testOutgoingRecordsCarryTheSideStores() throws {
        let ctx = container.viewContext
        let s = makeSession(in: ctx)
        let a = makeAttachment(session: s, in: ctx)
        try ctx.save()
        let sid = s.value(forKey: "id") as! UUID, aid = a.value(forKey: "id") as! UUID
        AttachmentPrivacy.setPrivate(id: aid, url: nil, false, mirror: false)
        PDFSelectedPagesStore.setPages([2, 5], for: aid, mirror: false)
        FeedInteractionStore.setSaved(true, sid, viewerUserID: scope)
        defer { PDFSelectedPagesStore.setPages(nil, for: aid, mirror: false); FeedInteractionStore.setSaved(false, sid, viewerUserID: scope) }

        let ar = try XCTUnwrap(JournalRecordMapping.record(for: a, base: nil))
        XCTAssertEqual((ar[JournalMetadataKeys.isPrivate] as? NSNumber)?.boolValue, false)
        XCTAssertEqual(ar[JournalMetadataKeys.selectedPages] as? String, "[2,5]")
        let sr = try XCTUnwrap(JournalRecordMapping.record(for: s, base: nil, viewerScope: scope))
        XCTAssertEqual((sr[JournalMetadataKeys.isSaved] as? NSNumber)?.boolValue, true)
        let srOther = try XCTUnwrap(JournalRecordMapping.record(for: s, base: nil, viewerScope: "someone.else"))
        XCTAssertEqual((srOther[JournalMetadataKeys.isSaved] as? NSNumber)?.boolValue, false)

        // No explicit privacy choice: the field is absent, not false.
        let b = makeAttachment(session: s, in: ctx)
        try ctx.save()
        let br = try XCTUnwrap(JournalRecordMapping.record(for: b, base: nil))
        XCTAssertNil(br[JournalMetadataKeys.isPrivate])
        XCTAssertEqual(br[JournalMetadataKeys.selectedPages] as? String, "[]")
    }

    // MARK: imports write the stores, clearing included

    func testImportWritesTitlePrivacyPagesAndFavouriteAndClearsThem() throws {
        let sid = UUID(), aid = UUID()
        let (imp, ctx) = importer()
        ctx.performAndWait { makeSession(in: ctx, id: sid); try? ctx.save() }
        // Pre-existing per-device override that must not hide the synced title.
        defaults.set([aid.uuidString: "Old device name"], forKey: AttachmentTitlePersistenceKeys.namespacedKey(for: .audio, userID: "someone"))

        let r1 = attachmentRecord(id: aid, sessionID: sid, displayName: "Clip from the iPad", isPrivate: false, pages: "[4]")
        ctx.performAndWait { _ = imp.importAttachment(r1) }
        // Titles go through the real shared store (standard defaults) in the importer;
        // check the store-only writer on a private suite directly as well.
        JournalMetadataFields.applyAttachment(isPrivate: false, pages: "[4]", displayName: "Clip from the iPad", kind: "audio", id: aid, defaults: defaults)
        XCTAssertEqual((defaults.dictionary(forKey: AttachmentTitlePersistenceKeys.legacyKey(for: .audio)) as? [String: String])?[aid.uuidString], "Clip from the iPad")
        XCTAssertNil((defaults.dictionary(forKey: AttachmentTitlePersistenceKeys.namespacedKey(for: .audio, userID: "someone")) as? [String: String])?[aid.uuidString],
                     "the per-device override is removed so it cannot hide the synced title")
        XCTAssertFalse(AttachmentPrivacy.isPrivate(id: aid, url: nil))
        XCTAssertEqual(PDFSelectedPagesStore.pages(for: aid), [4])
        XCTAssertEqual(sharedTitle(aid), "Clip from the iPad")

        // Cleared on the other device: "" title, "[]" pages.
        JournalMetadataFields.applyAttachment(isPrivate: nil, pages: "[]", displayName: "", kind: "audio", id: aid, defaults: defaults)
        XCTAssertNil(sharedTitle(aid))
        XCTAssertNil(PDFSelectedPagesStore.pages(for: aid))
        XCTAssertFalse(AttachmentPrivacy.isPrivate(id: aid, url: nil), "absent privacy field leaves the choice alone")

        // Favourite: 1 then 0; absent leaves it.
        JournalMetadataFields.applySession(isSaved: 1, id: sid, viewerScope: scope)
        XCTAssertTrue(FeedInteractionStore.isSaved(sid, viewerUserID: scope))
        JournalMetadataFields.applySession(isSaved: nil, id: sid, viewerScope: scope)
        XCTAssertTrue(FeedInteractionStore.isSaved(sid, viewerUserID: scope))
        JournalMetadataFields.applySession(isSaved: 0, id: sid, viewerScope: scope)
        XCTAssertFalse(FeedInteractionStore.isSaved(sid, viewerUserID: scope))

        // The import context's transactions never enter the outbox.
        let tracker = JournalChangeTracker(container: container, store: store)
        XCTAssertTrue(tracker.processHistory().isEmpty)
    }

    func testDisplayNameOnTheRecordReachesCoreDataAndEmptyStringIsKept() throws {
        let sid = UUID(), aid = UUID()
        let (imp, ctx) = importer()
        ctx.performAndWait { makeSession(in: ctx, id: sid); try? ctx.save() }
        ctx.performAndWait { _ = imp.importAttachment(attachmentRecord(id: aid, sessionID: sid, displayName: "", isPrivate: nil, pages: nil)); imp.save() }
        ctx.performAndWait {
            let a = imp.fetch(entity: "Attachment", id: aid)
            XCTAssertEqual(a?.value(forKey: "displayName") as? String, "", "cleared is \"\", never nil, once synced")
        }
    }

    // MARK: write points touch their rows

    func testTitleWriteLandsOnDisplayNameAndQueuesTheAttachmentAsAUserEdit() throws {
        let ctx = container.viewContext
        let s = makeSession(in: ctx)
        let a = makeAttachment(session: s, in: ctx)
        try ctx.save()
        let aid = a.value(forKey: "id") as! UUID
        let tracker = JournalChangeTracker(container: container, store: store)
        tracker.bootstrapIfNeeded()
        let before = a.value(forKey: "userModifiedAt") as? Date

        AttachmentTitlePersistenceKeys.writeLocalTitle("Named on this device", kind: .audio, attachmentID: aid, defaults: defaults)
        wait(for: { !tracker.processHistory().isEmpty || self.store.state.outbox.contains { $0.recordName == aid.uuidString } })
        ctx.refreshAllObjects()
        XCTAssertEqual(a.value(forKey: "displayName") as? String, "Named on this device")
        XCTAssertGreaterThan(a.value(forKey: "userModifiedAt") as? Date ?? .distantPast, before ?? .distantPast, "a user edit")
        XCTAssertTrue(store.state.outbox.contains { $0.recordName == aid.uuidString && $0.op == .save })

        // Clearing writes "".
        AttachmentTitlePersistenceKeys.writeLocalTitle("", kind: .audio, attachmentID: aid, defaults: defaults)
        wait(for: { ctx.refreshAllObjects(); return (a.value(forKey: "displayName") as? String) == "" })
    }

    func testFavouriteToggleTouchesTheSessionAndAStampOnlyMetadataChangeIsQueued() throws {
        let ctx = container.viewContext
        let s = makeSession(in: ctx, stamp: Date(timeIntervalSince1970: 1_000))
        try ctx.save()
        let sid = s.value(forKey: "id") as! UUID
        let tracker = JournalChangeTracker(container: container, store: store)
        tracker.bootstrapIfNeeded()
        store.update { $0.outbox.removeAll() }

        FeedInteractionStore.toggleSaved(sid, viewerUserID: scope)
        defer { FeedInteractionStore.setSaved(false, sid, viewerUserID: scope) }
        wait(for: { tracker.processHistory(); return self.store.state.outbox.contains { $0.recordName == sid.uuidString } })
        ctx.refreshAllObjects()
        XCTAssertGreaterThan(s.value(forKey: "userModifiedAt") as? Date ?? .distantPast, Date(timeIntervalSince1970: 1_000))
        XCTAssertFalse(store.state.outbox.first { $0.recordName == sid.uuidString }!.ownerOnly, "a full record, not owner-only")
    }

    // MARK: migration rows meeting server copies

    func testMigrationRowSurvivesAnOldFormatServerCopyAndYieldsToOneWithMetadata() throws {
        let sid = UUID(), aid = UUID()
        let queue = RecordingSendQueue()
        let (imp, ctx) = importer(queue)
        let old = Date(timeIntervalSince1970: 1_000)
        ctx.performAndWait {
            let s = makeSession(in: ctx, id: sid, stamp: old)
            let a = makeAttachment(session: s, in: ctx, id: aid)
            a.setValue("Migrated name", forKey: "displayName"); a.setValue(old, forKey: "userModifiedAt")
            try? ctx.save()
        }
        store.update { $0.outbox = [.init(recordName: aid.uuidString, recordType: "Attachment", op: .save, metadataOnly: true),
                                    .init(recordName: sid.uuidString, recordType: "Session", op: .save, metadataOnly: true)] }

        // Same stamp, written by an older build: no displayName, no fields.
        let oldFormat = attachmentRecord(id: aid, sessionID: sid, displayName: nil, isPrivate: nil, pages: nil, stamp: old)
        var applied = false
        ctx.performAndWait { applied = imp.importAttachment(oldFormat).imported }
        XCTAssertTrue(applied, "server content applied")
        ctx.performAndWait { XCTAssertEqual(imp.fetch(entity: "Attachment", id: aid)?.value(forKey: "displayName") as? String, "Migrated name",
                                            "an absent displayName is no information") }
        XCTAssertTrue(queue.removed.isEmpty, "the migration row stays queued")
        XCTAssertNotNil(store.state.lastKnownRecords[aid.uuidString], "…and will go on top of the server's change tag")

        // A copy that carries the fields wins: the other device already migrated.
        let withFields = attachmentRecord(id: aid, sessionID: sid, displayName: "Their name", isPrivate: true, pages: "[]", stamp: old)
        ctx.performAndWait { _ = imp.importAttachment(withFields) }
        XCTAssertEqual(queue.removed, [aid.uuidString])
        ctx.performAndWait { XCTAssertEqual(imp.fetch(entity: "Attachment", id: aid)?.value(forKey: "displayName") as? String, "Their name") }
    }

    func testMergeKeepsAContentSaveOverAMetadataOnlyOne() {
        var outbox: [JournalSyncPendingChange] = [.init(recordName: "A", recordType: "Session", op: .save, metadataOnly: true)]
        JournalChangeTracker.merge([.init(recordName: "A", recordType: "Session", op: .save)], into: &outbox)
        XCTAssertFalse(outbox[0].metadataOnly, "a content save replaces a metadata-only one")
        JournalChangeTracker.merge([.init(recordName: "A", recordType: "Session", op: .save, metadataOnly: true)], into: &outbox)
        XCTAssertFalse(outbox[0].metadataOnly, "…and is never downgraded")
    }

    func testAttachmentRecordAlwaysCarriesDisplayNameOnceWrittenByThisBuild() throws {
        let ctx = container.viewContext
        let s = makeSession(in: ctx)
        let a = makeAttachment(session: s, in: ctx)
        try ctx.save()
        let r = try XCTUnwrap(JournalRecordMapping.record(for: a, base: nil))
        XCTAssertEqual(r["displayName"] as? String, "", "nil locally is sent as the explicit empty name")
    }

    // MARK: migration

    func testMigrationQueuesRowsWithTheirExistingStampsAndIsIdempotent() throws {
        let ctx = container.viewContext
        let old = Date(timeIntervalSince1970: 5_000)
        let s = makeSession(in: ctx, stamp: old)
        let a = makeAttachment(session: s, in: ctx)
        let b = makeAttachment(session: s, in: ctx, kind: "pdf")
        let c = makeAttachment(session: s, in: ctx, kind: "video")
        try ctx.save()
        let sid = s.value(forKey: "id") as! UUID, aid = a.value(forKey: "id") as! UUID
        let bid = b.value(forKey: "id") as! UUID, cid = c.value(forKey: "id") as! UUID
        ctx.performAndWait { for o in [s, a, b, c] { o.setValue(old, forKey: "userModifiedAt") }; try? ctx.save() }
        defaults.set([aid.uuidString: "Old clip name"], forKey: AttachmentTitlePersistenceKeys.legacyKey(for: .audio))
        PDFSelectedPagesStore.setPages([2], for: bid, mirror: false)
        FeedInteractionStore.setSaved(true, sid, viewerUserID: scope, defaults: defaults)
        defer { PDFSelectedPagesStore.setPages(nil, for: bid, mirror: false) }
        let privacy = [JournalMetadataCodec.privacyKey(cid): false]

        var queued: [(String, String)] = []
        let pagesMap = [bid.uuidString: [2]]
        let outcome = JournalMetadataMigration.run(container: container, defaults: defaults, privacyMap: privacy, pagesMap: pagesMap, viewerScope: scope) { queued.append(($0, $1)) }
        XCTAssertEqual(outcome, .init(titles: 1, privacy: 1, pages: 1, saves: 1))
        XCTAssertEqual(Set(queued.map(\.0)), Set([aid, bid, cid, sid].map(\.uuidString)))
        ctx.refreshAllObjects()
        XCTAssertEqual(a.value(forKey: "displayName") as? String, "Old clip name")
        XCTAssertEqual(a.value(forKey: "userModifiedAt") as? Date, old, "the migration is not a newer user edit")
        // History: the displayName write is queued (migration author is tracked, just not stamped).
        let tracker = JournalChangeTracker(container: container, store: store)
        tracker.bootstrapIfNeeded(); store.update { $0.outbox.removeAll() }
        // Re-run: nothing re-written, the same rows re-queued (harmless, deduplicated by the outbox).
        queued.removeAll()
        let again = JournalMetadataMigration.run(container: container, defaults: defaults, privacyMap: privacy, pagesMap: pagesMap, viewerScope: scope) { queued.append(($0, $1)) }
        XCTAssertEqual(again, .init(titles: 0, privacy: 1, pages: 1, saves: 1))
        XCTAssertEqual(a.value(forKey: "userModifiedAt") as? Date, old)
    }

    func testAMigratedRecordDoesNotBeatALaterLocalEdit() throws {
        let sid = UUID(), aid = UUID()
        let queue = RecordingSendQueue()
        let (imp, ctx) = importer(queue)
        ctx.performAndWait {
            let s = makeSession(in: ctx, id: sid)
            let a = makeAttachment(session: s, in: ctx, id: aid)
            a.setValue("Renamed here, later", forKey: "displayName")
            a.setValue(Date(timeIntervalSince1970: 9_000), forKey: "userModifiedAt")
            try? ctx.save()
        }
        store.update { $0.outbox = [.init(recordName: aid.uuidString, recordType: "Attachment", op: .save)] }
        defaults.set([aid.uuidString: "Renamed here, later"], forKey: AttachmentTitlePersistenceKeys.legacyKey(for: .audio))
        // The other device's migration carries its old per-device name with the OLD stamp.
        let migrated = attachmentRecord(id: aid, sessionID: sid, displayName: "Old name from the other device", isPrivate: nil, pages: nil,
                                        stamp: Date(timeIntervalSince1970: 1_000))
        var applied = true
        ctx.performAndWait { applied = imp.importAttachment(migrated).imported }
        XCTAssertFalse(applied, "local edit is newer: kept and resent")
        ctx.performAndWait {
            XCTAssertEqual(imp.fetch(entity: "Attachment", id: aid)?.value(forKey: "displayName") as? String, "Renamed here, later")
        }
        XCTAssertEqual(sharedTitle(aid), "Renamed here, later")
        XCTAssertTrue(queue.removed.isEmpty)
    }
}
#endif
