//
//  SyncTestInstrumentBackfillTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  C-198, assessed 2026-11-13: the one-time instrument backfill
//  (`PersistenceController.runOneTimeBackfillIfNeeded`) on a device that has
//  just restored its journal from iCloud. Nothing here changes production
//  code. EVERY TEST PINS WHAT THE CODE DOES TODAY; a test whose name starts
//  `testFAULT_` asserts a behaviour that is wrong or doubtful.
//
//  When the backfill runs: once per install and owner id (a UserDefaults
//  flag), from three places, all keyed on an owner id being present:
//  `MOTIVOApp.init` (the owner key already in the Keychain at launch),
//  `MOTIVOApp`'s `onReceive(auth.$currentUserID)` (the key appears), and the
//  person's own profile peek (`ProfilePeekView`, under the backend id). On a
//  device that restores through the set-up screen there is no owner key until
//  the first complete fetch has been applied: `JournalOwnershipCoordinator`
//  then adopts the journal's owner, `currentUserID` changes, and the backfill
//  runs over the journal that has just arrived (Device A, 2026-11-13). On a
//  device whose owner key was set before the first fetch it ran over an empty
//  store, made nothing, and set its flag (the iPad, 2026-11-10). The first
//  two tests play those two orders with the real method.
//
//  The restore is played by the importer on an in-memory store; the "cloud"
//  is synthetic records.
//

#if SYNCTEST
import XCTest
import CoreData
import CloudKit
@testable import Etudes

@MainActor
final class SyncTestInstrumentBackfillTests: XCTestCase {

    private var pc: PersistenceController!
    private var store: JournalSyncStateStore!
    private var tracker: JournalChangeTracker!
    private var tempDir: URL!
    private var ownerID: String!
    private var queues: [Step0Queue] = []
    private var hadInstallKey = false
    private static let installKey = "localCustomOwnerID_v1"

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-c198-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        hadInstallKey = UserDefaults.standard.string(forKey: Self.installKey) != nil
        pc = PersistenceController(inMemory: true)
        store = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("state.json"))
        tracker = JournalChangeTracker(container: pc.container, store: store)
        ownerID = "test-owner-\(UUID().uuidString)"
        // The set-up screen makes the empty Profile row when it appears
        // (AppSetUpView.ensureProfileExistsIfNeeded), before any fetch ends.
        let ctx = pc.container.viewContext
        let profile = NSEntityDescription.insertNewObject(forEntityName: "Profile", into: ctx)
        profile.setValue(UUID(), forKey: "id"); profile.setValue("", forKey: "name")
        profile.setValue("", forKey: "primaryInstrument"); profile.setValue(false, forKey: "defaultPrivacy")
        try ctx.save()
        // Sync is turned on: history before now is not read (JournalSyncCoordinator.enable).
        let token = pc.container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)
        store.update { $0.historyToken = JournalSyncStateStore.encode(token: token); $0.bootstrapQueued = true }
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "backfill_userInstruments_done_\(ownerID ?? "")")
        if !hadInstallKey { UserDefaults.standard.removeObject(forKey: Self.installKey) }
        queues.removeAll()
        tracker = nil; pc = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: helpers

    private var backfillDone: Bool { UserDefaults.standard.bool(forKey: "backfill_userInstruments_done_\(ownerID ?? "")") }

    /// The first fetch's import: the cloud's records into this store, as the engine's importer writes them.
    private func restore(_ records: [CKRecord]) throws {
        let ctx = pc.container.newBackgroundContext()
        ctx.name = "syncImport"; ctx.transactionAuthor = JournalSyncAuthor.sync
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy; ctx.stalenessInterval = 0
        let q = Step0Queue(store: store)
        queues.append(q)
        let imp = JournalImporter(context: ctx, store: store, customOwner: try XCTUnwrap(pc.ownerIDForCustoms))
        imp.queue = q
        var summary = JournalImporter.Summary()
        ctx.performAndWait { summary = imp.importModifications(records) }
        XCTAssertFalse(summary.saveFailed)
        pc.container.viewContext.refreshAllObjects()
    }

    private func instrumentRecord(_ id: UUID, _ name: String) -> CKRecord {
        let r = CKRecord(recordType: JournalSyncRecordType.instrument, recordID: JournalRecordMapping.recordID(for: id))
        r["name"] = name as CKRecordValue
        return r
    }

    /// The profile-list row ("custom instrument") the app keeps beside an Instrument.
    private func userInstrumentRecord(_ id: UUID, _ name: String, instrument: UUID) -> CKRecord {
        let r = CKRecord(recordType: JournalSyncRecordType.userInstrument, recordID: JournalRecordMapping.recordID(for: id))
        r["displayName"] = name as CKRecordValue
        r["normalizedName"] = PersistenceController.normalized(name) as CKRecordValue
        r["displayOrder"] = NSNumber(value: 0); r["isVisibleOnProfile"] = NSNumber(value: true)
        r[JournalRecordMapping.instrumentRefKey] = CKRecord.Reference(recordID: JournalRecordMapping.recordID(for: instrument), action: .none)
        r[JournalRecordMapping.instrumentNameKey] = name as CKRecordValue
        return r
    }

    private func sessionRecord(_ id: UUID, instrument: (id: UUID, name: String)?) -> CKRecord {
        let r = CKRecord(recordType: "Session", recordID: JournalRecordMapping.recordID(for: id))
        r["title"] = "Practice" as CKRecordValue; r["timestamp"] = Date(timeIntervalSince1970: 1_750_000_000) as CKRecordValue
        r["userModifiedAt"] = Date(timeIntervalSince1970: 1_760_000_000) as CKRecordValue
        if let instrument {
            r[JournalRecordMapping.instrumentRefKey] = CKRecord.Reference(recordID: JournalRecordMapping.recordID(for: instrument.id), action: .none)
            r[JournalRecordMapping.instrumentNameKey] = instrument.name as CKRecordValue
        }
        return r
    }

    private func names(_ entity: String, key: String) -> [String] {
        let rows = (try? pc.container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: entity))) ?? []
        return rows.compactMap { $0.value(forKey: key) as? String }.sorted()
    }

    private func id(of entity: String, named name: String, key: String) -> UUID? {
        let rows = (try? pc.container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: entity))) ?? []
        return rows.first { $0.value(forKey: key) as? String == name }?.value(forKey: "id") as? UUID
    }

    // MARK: when it runs

    /// The iPad on 2026-11-10: the owner key was there before the first fetch,
    /// so the backfill ran over the empty store, set its flag, and never ran
    /// over the journal that then arrived.
    func testBackfillThatRanBeforeTheFirstFetchMakesNothingAndDoesNotRunAgainOverTheRestoredJournal() async throws {
        await pc.runOneTimeBackfillIfNeeded(for: ownerID)
        XCTAssertTrue(backfillDone); XCTAssertTrue(names("UserInstrument", key: "displayName").isEmpty)
        let cello = UUID(), mandolin = UUID()
        try restore([instrumentRecord(cello, "Cello"), instrumentRecord(mandolin, "Mandolin"), userInstrumentRecord(UUID(), "Cello", instrument: cello)])
        await pc.runOneTimeBackfillIfNeeded(for: ownerID)
        XCTAssertEqual(names("Instrument", key: "name"), ["Cello", "Mandolin"])
        XCTAssertEqual(names("UserInstrument", key: "displayName"), ["Cello"], "only the row iCloud held; none made here")
        XCTAssertTrue(tracker.processHistory().isEmpty, "and nothing is queued for sync")
    }

    /// Device A on 2026-11-13: the owner was adopted after the first fetch, so
    /// the backfill ran over the restored journal. It made a profile-list row
    /// for each Instrument that had none in iCloud, and saving them touched
    /// those Instrument rows: four records queued, which is what the device
    /// sent ("4 instrument records").
    func testFAULT_BackfillAfterTheFirstFetchAddsARowForEveryInstrumentWithoutOneAndQueuesThemForSync() async throws {
        let cello = UUID(), mandolin = UUID(), tuba = UUID(), celloRow = UUID()
        try restore([instrumentRecord(cello, "Cello"), instrumentRecord(mandolin, "Mandolin"), instrumentRecord(tuba, "Tuba"),
                     userInstrumentRecord(celloRow, "Cello", instrument: cello), sessionRecord(UUID(), instrument: (cello, "Cello"))])
        XCTAssertEqual(names("UserInstrument", key: "displayName"), ["Cello"], "precondition: the journal as iCloud holds it")
        XCTAssertTrue(tracker.processHistory().isEmpty, "precondition: an import queues nothing")
        XCTAssertFalse(backfillDone)

        await pc.runOneTimeBackfillIfNeeded(for: ownerID)   // owner adopted → currentUserID published → MOTIVOApp.swift:442

        XCTAssertTrue(backfillDone)
        XCTAssertEqual(names("UserInstrument", key: "displayName"), ["Cello", "Mandolin", "Tuba"], "the restored device added two rows of its own")
        let queued = tracker.processHistory()
        XCTAssertTrue(queued.allSatisfy { $0.op == .save })
        let mandolinRow = try XCTUnwrap(id(of: "UserInstrument", named: "Mandolin", key: "displayName"))
        let tubaRow = try XCTUnwrap(id(of: "UserInstrument", named: "Tuba", key: "displayName"))
        XCTAssertEqual(Set(queued.map(\.recordName)), [mandolin.uuidString, tuba.uuidString, mandolinRow.uuidString, tubaRow.uuidString],
                       "the two new rows and the two Instrument records they point at go to every other device")
        XCTAssertEqual(id(of: "UserInstrument", named: "Cello", key: "displayName"), celloRow, "the row that came from iCloud is left alone")
    }

    // MARK: an instrument removed on another device

    /// What a removal leaves in iCloud. The instrument list deletes the
    /// Instrument row and its profile-list row together
    /// (InstrumentListView.delete, lines 196 and 208); the model clears the
    /// link on every session that used it. On a device that is syncing, both
    /// deletions and those sessions are queued, so iCloud keeps no record that
    /// names the instrument.
    func testRemovingAnInstrumentInTheInstrumentListQueuesBothDeletionsAndTheSessionsThatUsedIt() throws {
        let stamp = JournalUserEditStamp.install()   // this device is syncing
        defer { NotificationCenter.default.removeObserver(stamp) }
        let cello = UUID(), tuba = UUID(), celloRow = UUID(), tubaRow = UUID(), celloSession = UUID(), tubaSession = UUID()
        try restore([instrumentRecord(cello, "Cello"), instrumentRecord(tuba, "Tuba"),
                     userInstrumentRecord(celloRow, "Cello", instrument: cello), userInstrumentRecord(tubaRow, "Tuba", instrument: tuba),
                     sessionRecord(celloSession, instrument: (cello, "Cello")), sessionRecord(tubaSession, instrument: (tuba, "Tuba"))])
        XCTAssertTrue(tracker.processHistory().isEmpty)

        // InstrumentListView.delete, for "Tuba".
        let ctx = pc.container.viewContext
        let instruments = try ctx.fetch(NSFetchRequest<NSManagedObject>(entityName: "Instrument"))
        ctx.delete(try XCTUnwrap(instruments.first { $0.value(forKey: "id") as? UUID == tuba }))
        let rows = NSFetchRequest<NSManagedObject>(entityName: "UserInstrument")
        rows.predicate = NSPredicate(format: "ownerUserID == %@ AND normalizedName == %@", try XCTUnwrap(pc.ownerIDForCustoms), PersistenceController.normalized("Tuba"))
        for row in try ctx.fetch(rows) { ctx.delete(row) }
        try ctx.save()

        let queued = tracker.processHistory()
        XCTAssertEqual(Set(queued.filter { $0.op == .delete }.map(\.recordName)), [tuba.uuidString, tubaRow.uuidString],
                       "the Instrument record and its profile-list record are both deleted in iCloud")
        XCTAssertEqual(queued.filter { $0.op == .save }.map(\.recordName), [tubaSession.uuidString], "and the session that used it is sent again")
        let request = NSFetchRequest<NSManagedObject>(entityName: "Session"); request.predicate = NSPredicate(format: "id == %@", tubaSession as CVarArg)
        let session = try XCTUnwrap(try ctx.fetch(request).first)
        let outgoing = try XCTUnwrap(JournalRecordMapping.record(for: session, base: nil))
        XCTAssertNil(JournalRecordMapping.instrumentLink(of: outgoing).recordName); XCTAssertNil(JournalRecordMapping.instrumentLink(of: outgoing).name)
    }

    /// So a device that restores afterwards receives no Instrument to backfill
    /// from: a removal that reached iCloud is not undone by the backfill.
    func testAnInstrumentWhoseRemovalReachedICloudIsNotRecreatedByARestoreAndItsBackfill() async throws {
        let cello = UUID()
        // iCloud after the removal of "Tuba": no Instrument, no profile-list row, the session without its link.
        try restore([instrumentRecord(cello, "Cello"), userInstrumentRecord(UUID(), "Cello", instrument: cello),
                     sessionRecord(UUID(), instrument: (cello, "Cello")), sessionRecord(UUID(), instrument: nil)])
        await pc.runOneTimeBackfillIfNeeded(for: ownerID)
        XCTAssertTrue(backfillDone)
        XCTAssertEqual(names("Instrument", key: "name"), ["Cello"])
        XCTAssertEqual(names("UserInstrument", key: "displayName"), ["Cello"])
        XCTAssertTrue(tracker.processHistory().isEmpty)
    }

    /// The route by which a removed instrument does come back. If any session
    /// record in iCloud still names it (the removing device could not re-send
    /// that session, or removed the instrument before its sync was on), the
    /// IMPORTER recreates the Instrument under the local profile
    /// (JournalImporter.resolveInstrument), so it is in the instrument list
    /// again before any backfill. The backfill then gives it a profile-list
    /// row and, by touching it, queues both: the instrument returns to every
    /// device, including the one that removed it.
    func testFAULT_AnInstrumentASessionInICloudStillNamesComesBackAtARestoreAndTheBackfillSendsItToEveryDevice() async throws {
        let cello = UUID(), tuba = UUID()
        try restore([instrumentRecord(cello, "Cello"), userInstrumentRecord(UUID(), "Cello", instrument: cello),
                     sessionRecord(UUID(), instrument: (tuba, "Tuba"))])   // no Instrument or profile-list record for Tuba
        XCTAssertEqual(names("Instrument", key: "name"), ["Cello", "Tuba"], "the importer alone puts Tuba back in the instrument list here")
        XCTAssertEqual(names("UserInstrument", key: "displayName"), ["Cello"])
        XCTAssertTrue(tracker.processHistory().isEmpty, "but sends nothing: other devices are untouched so far")

        await pc.runOneTimeBackfillIfNeeded(for: ownerID)

        XCTAssertEqual(names("UserInstrument", key: "displayName"), ["Cello", "Tuba"])
        let queued = tracker.processHistory()
        let tubaRow = try XCTUnwrap(id(of: "UserInstrument", named: "Tuba", key: "displayName"))
        XCTAssertEqual(Set(queued.filter { $0.op == .save }.map(\.recordName)), [tuba.uuidString, tubaRow.uuidString],
                       "the backfill is what makes the instrument travel back")
    }
}
#endif
