//
//  SyncTestProfileTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  Stage H: the private profile (name, location, primary instrument, avatar)
//  through the bound journal. The merge rule is pure and order-independent;
//  an empty/default profile is never sent and never beats an established one;
//  edits and clears are explicit on the record; the avatar travels on its own
//  record by hash and a text edit never carries it; imports write no
//  Solo→Connected marker and the only remote paths refuse without a Connected
//  identity; an erase resets what the scan knows.
//

#if SYNCTEST
import XCTest
import CoreData
import CloudKit
import UIKit
@testable import Etudes

final class SyncTestProfileTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var store: JournalSyncStateStore!
    private var tempDir: URL!
    private var keptContexts: [NSManagedObjectContext] = []
    /// Unique scopes so the test host's own profile stores are never touched.
    private var scope: JournalProfileScope!
    private var savedLocalLocation: String?
    private var savedLocalKeyExisted = false
    private var importerContext: NSManagedObjectContext!
    private var importer: JournalImporter!
    private var queue: RecordingSendQueue!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-h-\(UUID().uuidString)", isDirectory: true)
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
        let tag = "synctest.h.\(UUID().uuidString.prefix(8))"
        scope = JournalProfileScope(locationUserID: tag, avatarUserID: tag)
        // `presentedLocation` falls back to the local profile when the scoped key
        // is absent; pin the local value so the host's own does not leak in.
        savedLocalKeyExisted = UserDefaults.standard.object(forKey: "profile.__local_etudes_profile__.location") != nil
        savedLocalLocation = UserDefaults.standard.string(forKey: "profile.__local_etudes_profile__.location")
        UserDefaults.standard.set("", forKey: "profile.__local_etudes_profile__.location")
        UserDefaults.standard.removeObject(forKey: "profile.__local_etudes_profile__.avatarSyncState_v1")
        ProfileStore.removeSyncedAvatar(for: scope.avatarUserID)
        JournalProfileMirror.onChange = nil
        JournalProfileMirror.suppressed = false
        ConnectedWriteWitness.resetForTesting()
        queue = RecordingSendQueue()
        let ctx = container.newBackgroundContext()
        ctx.transactionAuthor = JournalSyncAuthor.sync
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        keptContexts.append(ctx)
        importerContext = ctx
        importer = JournalImporter(context: ctx, store: store, customOwner: "local:TEST")
        importer.queue = queue
    }

    override func tearDownWithError() throws {
        JournalProfileMirror.onChange = nil
        JournalProfileMirror.suppressed = false
        ProfileStore.removeSyncedAvatar(for: scope.avatarUserID)
        UserDefaults.standard.removeObject(forKey: "profile.\(scope.locationUserID!).location")
        if savedLocalKeyExisted { UserDefaults.standard.set(savedLocalLocation ?? "", forKey: "profile.__local_etudes_profile__.location") }
        else { UserDefaults.standard.removeObject(forKey: "profile.__local_etudes_profile__.location") }
        UserDefaults.standard.removeObject(forKey: "profile.__local_etudes_profile__.avatarSyncState_v1")
        JournalProfileSync.clearDisplacedAvatars()
        keptContexts.removeAll()
        container = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: helpers

    @discardableResult
    private func makeProfile(name: String, primary: String = "", instruments: [String] = []) -> NSManagedObject {
        let ctx = container.viewContext
        let p = NSEntityDescription.insertNewObject(forEntityName: "Profile", into: ctx)
        p.setValue(UUID(), forKey: "id"); p.setValue(name, forKey: "name"); p.setValue(primary, forKey: "primaryInstrument")
        p.setValue(false, forKey: "defaultPrivacy")
        for instrument in instruments {
            let i = NSEntityDescription.insertNewObject(forEntityName: "Instrument", into: ctx)
            i.setValue(UUID(), forKey: "id"); i.setValue(instrument, forKey: "name"); i.setValue(p, forKey: "profile")
        }
        try! ctx.save()
        return p
    }

    private func setLocation(_ value: String) { ProfileStore.setLocation(value, for: scope.locationUserID) }

    private func scan(now: Date = Date()) -> [JournalSyncPendingChange] {
        var out: [JournalSyncPendingChange] = []
        importerContext.performAndWait { out = JournalProfileSync.scan(context: importerContext, scope: scope, store: store, now: now) }
        return out
    }

    private func values() -> JournalProfileValues {
        var v = JournalProfileValues()
        importerContext.performAndWait { v = JournalProfileSync.currentValues(context: importerContext, scope: scope) }
        return v
    }

    private func profileRecordBuilt() -> CKRecord {
        var r: CKRecord!
        importerContext.performAndWait {
            r = JournalProfileSync.profileRecord(context: importerContext, scope: scope, store: store) { self.importer.instrument(named: $0) }
        }
        return r
    }

    private func serverProfile(name: String, location: String, primary: String, primaryID: UUID? = nil, stamp: Date?) -> CKRecord {
        let r = CKRecord(recordType: JournalSyncRecordType.profile,
                         recordID: CKRecord.ID(recordName: JournalProfileSync.profileName, zoneID: JournalRecordMapping.zoneID))
        r["name"] = name as CKRecordValue; r["location"] = location as CKRecordValue
        r[JournalRecordMapping.instrumentNameKey] = primary as CKRecordValue
        if let primaryID { r[JournalRecordMapping.instrumentRefKey] = CKRecord.Reference(recordID: JournalRecordMapping.recordID(for: primaryID), action: .none) }
        if let stamp { r["userModifiedAt"] = stamp as CKRecordValue }
        return r
    }

    private func applyProfile(_ record: CKRecord, localPending: Bool? = nil) -> JournalProfileSync.Outcome {
        var out = JournalProfileSync.Outcome()
        importerContext.performAndWait {
            out = JournalProfileSync.applyProfile(record, context: importerContext, scope: scope, store: store, importer: importer,
                                                  localPending: localPending) { _ in }
        }
        return out
    }

    private func pngData(_ shade: CGFloat, size: CGFloat = 64) -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
            UIColor(white: shade, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
        return image.pngData()!
    }

    private func serverAvatar(png: Data?, stamp: Date) -> CKRecord {
        let r = CKRecord(recordType: JournalSyncRecordType.profileAvatar,
                         recordID: CKRecord.ID(recordName: JournalProfileSync.avatarName, zoneID: JournalRecordMapping.zoneID))
        if let png {
            let url = tempDir.appendingPathComponent("server-\(UUID().uuidString).png")
            try! png.write(to: url)
            r[JournalRecordMapping.assetKey] = CKAsset(fileURL: url)
            r[JournalRecordMapping.fileHashKey] = JournalAssetHash.hash(of: url)! as CKRecordValue
        } else {
            r[JournalRecordMapping.fileHashKey] = "" as CKRecordValue
        }
        r["userModifiedAt"] = stamp as CKRecordValue
        return r
    }

    private func applyAvatar(_ record: CKRecord, localPending: Bool? = nil) -> JournalProfileSync.Outcome {
        JournalProfileSync.applyAvatar(record, scope: scope, store: store, localPending: localPending) { _ in }
    }

    private var avatarURL: URL { ProfileStore.avatarDerivedURL(for: scope.avatarUserID)! }
    private func outbox(_ name: String) -> JournalSyncPendingChange? { store.state.outbox.first { $0.recordName == name && $0.op == .save } }

    // MARK: the merge rule (pure)

    func testMergeRuleIsDeterministicOrderIndependentAndPreservesDisplacedValues() {
        let a = JournalProfileValues(name: "Sam", location: "", primaryInstrument: "Cello")
        let b = JournalProfileValues(name: "Samuel Dixon", location: "London", primaryInstrument: "Bass")
        // Two established profiles with no clock: field by field, a blank never
        // displaces a value, two values resolve to the longer one.
        let ab = JournalProfileMerge.decide(local: a, localStamp: nil, localPending: false, server: b, serverStamp: nil)
        let ba = JournalProfileMerge.decide(local: b, localStamp: nil, localPending: false, server: a, serverStamp: nil)
        let merged = JournalProfileValues(name: "Samuel Dixon", location: "London", primaryInstrument: "Cello")
        XCTAssertEqual(ab.apply, merged)
        XCTAssertEqual(ba.apply, merged)
        XCTAssertTrue(ab.send, "the merged values differ from the server's, so they are sent back")
        XCTAssertTrue(ba.send)
        XCTAssertEqual(ab.displaced.sorted(), ["instrument (other device): Bass", "name (this device): Sam"])
        XCTAssertEqual(ba.displaced.sorted(), ["instrument (this device): Bass", "name (other device): Sam"])
        // Equal length: Unicode order, both ways the same.
        XCTAssertEqual(JournalProfileMerge.tieBreak("Viola", "Cello"), "Cello")
        XCTAssertEqual(JournalProfileMerge.tieBreak("Cello", "Viola"), "Cello")
        // The merged record meeting the other side again: nothing left to do.
        let settled = JournalProfileMerge.decide(local: merged, localStamp: nil, localPending: false, server: merged, serverStamp: nil)
        XCTAssertNil(settled.apply); XCTAssertFalse(settled.send)

        // A clock beats no clock, whichever side holds it; a newer clock wins the whole record.
        let t1 = Date(timeIntervalSince1970: 1_000), t2 = Date(timeIntervalSince1970: 2_000)
        let stampedServer = JournalProfileMerge.decide(local: a, localStamp: nil, localPending: true, server: b, serverStamp: t1)
        XCTAssertEqual(stampedServer.apply, b); XCTAssertFalse(stampedServer.send)
        XCTAssertEqual(stampedServer.displaced, ["name (this device): Sam", "instrument (this device): Cello"])
        let stampedLocal = JournalProfileMerge.decide(local: a, localStamp: t1, localPending: true, server: b, serverStamp: nil)
        XCTAssertNil(stampedLocal.apply); XCTAssertTrue(stampedLocal.send)
        let newerServer = JournalProfileMerge.decide(local: a, localStamp: t1, localPending: true, server: b, serverStamp: t2)
        XCTAssertEqual(newerServer.apply, b)
        let newerLocal = JournalProfileMerge.decide(local: a, localStamp: t2, localPending: false, server: b, serverStamp: t1)
        XCTAssertNil(newerLocal.apply); XCTAssertTrue(newerLocal.send, "ours is newer: the server gets it again")
        // A tie with a pending local edit goes to the server (the existing rule); an echo of a copy we hold does nothing.
        XCTAssertEqual(JournalProfileMerge.decide(local: a, localStamp: t1, localPending: true, server: b, serverStamp: t1).apply, b)
        XCTAssertNil(JournalProfileMerge.decide(local: a, localStamp: t1, localPending: false, server: b, serverStamp: t1).apply)
        // A newer, stamped, EMPTY profile clears: cleared values stay cleared.
        let cleared = JournalProfileMerge.decide(local: b, localStamp: t1, localPending: false, server: JournalProfileValues(), serverStamp: t2)
        XCTAssertEqual(cleared.apply, JournalProfileValues())

        // The avatar: one clocked value.
        XCTAssertEqual(JournalProfileMerge.decideAvatar(localHash: "h", localStamp: t1, localPending: false, serverHash: "h", serverStamp: t2), .nothing)
        XCTAssertEqual(JournalProfileMerge.decideAvatar(localHash: "h", localStamp: t1, localPending: false, serverHash: "", serverStamp: t2), .takeServer)
        XCTAssertEqual(JournalProfileMerge.decideAvatar(localHash: "h", localStamp: t2, localPending: true, serverHash: "g", serverStamp: t1), .keepLocalAndSend)
        XCTAssertEqual(JournalProfileMerge.decideAvatar(localHash: "", localStamp: nil, localPending: false, serverHash: "g", serverStamp: t1), .takeServer)

        // What counts as an edit: never a default-only change on a profile nobody filled in.
        let empty = JournalProfileValues(), defaulted = JournalProfileValues(primaryInstrument: "Cello")
        XCTAssertFalse(JournalProfileMerge.isEdit(previous: empty, current: defaulted, everEdited: false))
        XCTAssertTrue(JournalProfileMerge.isEdit(previous: empty, current: JournalProfileValues(name: "S"), everEdited: false))
        XCTAssertTrue(JournalProfileMerge.isEdit(previous: b, current: empty, everEdited: false), "clearing an established profile is an edit")
        XCTAssertTrue(JournalProfileMerge.isEdit(previous: empty, current: defaulted, everEdited: true))
        // The fingerprint round-trips, including empties.
        XCTAssertEqual(JournalProfileValues(fingerprint: b.fingerprint), b)
        XCTAssertEqual(JournalProfileValues(fingerprint: empty.fingerprint), empty)
    }

    // MARK: default profiles and arrival

    func testADefaultProfileIsNeverSentAndAnEstablishedOneArrivesAndCreatesTheRow() throws {
        // No Profile row at all, no location: the first scan sets the baseline and sends nothing.
        XCTAssertTrue(scan().isEmpty)
        XCTAssertNotNil(store.state.profileFingerprint); XCTAssertNil(store.state.profileStamp)
        // The app writes its default primary instrument on the empty profile: not an edit.
        makeProfile(name: "", primary: "Cello", instruments: ["Cello"])
        XCTAssertTrue(scan().isEmpty, "a default-only change on a profile nobody filled in is not an edit")
        XCTAssertNil(store.state.profileStamp)
        // The other device's established profile arrives, clocked.
        let t1 = Date(timeIntervalSince1970: 1_000)
        let out = applyProfile(serverProfile(name: "Samuel Dixon", location: "London", primary: "Bass Guitar", stamp: t1))
        XCTAssertEqual(out.applied, 1); XCTAssertTrue(out.resend.isEmpty)
        let v = values()
        XCTAssertEqual(v, JournalProfileValues(name: "Samuel Dixon", location: "London", primaryInstrument: "Bass Guitar"))
        XCTAssertEqual(ProfileStore.presentedLocation(for: scope.locationUserID), "London")
        XCTAssertEqual(store.state.profileStamp, t1)
        XCTAssertEqual(store.state.profileFingerprint, v.fingerprint)
        // An unknown primary instrument is created under the profile once; the same row is used by a session.
        let instruments = try container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Instrument"))
        XCTAssertEqual(instruments.count, 2, "Cello and the new Bass Guitar")
        // Nothing to send after an import, and the import's own writes did not scan anything in.
        XCTAssertTrue(scan().isEmpty); XCTAssertNil(outbox(JournalProfileSync.profileName))
        // A fresh device with NO Profile row: the import creates it.
        for p in try container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Profile")) { container.viewContext.delete(p) }
        try container.viewContext.save()
        _ = applyProfile(serverProfile(name: "Second", location: "", primary: "", stamp: Date(timeIntervalSince1970: 3_000)))
        let rows = try container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Profile"))
        XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows.first?.value(forKey: "name") as? String, "Second")
        XCTAssertNotNil(rows.first?.value(forKey: "id"))
    }

    func testEditsQueueAClockedRecordClearsAreExplicitAndTheSameValueWrittenAgainIsNotAnEdit() throws {
        makeProfile(name: "Samuel", primary: "Cello", instruments: ["Cello"])
        setLocation("Bristol")
        // First sight of an established profile: queued WITHOUT a clock (the transition).
        let first = scan()
        XCTAssertEqual(first.map(\.recordName), [JournalProfileSync.profileName])
        XCTAssertNil(store.state.profileStamp)
        var record = profileRecordBuilt()
        XCTAssertEqual(record["name"] as? String, "Samuel"); XCTAssertEqual(record["location"] as? String, "Bristol")
        XCTAssertEqual(record[JournalRecordMapping.instrumentNameKey] as? String, "Cello")
        XCTAssertNotNil(record[JournalRecordMapping.instrumentRefKey], "the primary is linked by the Instrument row's id")
        XCTAssertNil(record["userModifiedAt"], "a profile that predates the build has no clock")
        XCTAssertNil(record[JournalRecordMapping.assetKey], "a text record never carries the avatar")
        store.update { $0.outbox.removeAll() }
        // The same location written again (every Profile close does this): no edit.
        var hookFired = 0
        JournalProfileMirror.onChange = { _ in hookFired += 1 }
        setLocation("Bristol")
        XCTAssertEqual(hookFired, 0)
        XCTAssertTrue(scan().isEmpty)
        // A real edit: clocked, queued; the hook fired.
        setLocation("")
        XCTAssertEqual(hookFired, 1)
        let now = Date(timeIntervalSince1970: 5_000)
        XCTAssertEqual(scan(now: now).map(\.recordName), [JournalProfileSync.profileName])
        XCTAssertEqual(store.state.profileStamp, now)
        record = profileRecordBuilt()
        XCTAssertEqual(record["location"] as? String, "", "clearing is explicit on the record")
        XCTAssertEqual(record["userModifiedAt"] as? Date, now)
        // Clearing everything is still an edit of an established profile, and is sent.
        let p = try XCTUnwrap(try container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Profile")).first)
        p.setValue("", forKey: "name"); p.setValue("", forKey: "primaryInstrument"); try container.viewContext.save()
        store.update { $0.outbox.removeAll() }
        XCTAssertEqual(scan(now: now.addingTimeInterval(1)).count, 1)
        record = profileRecordBuilt()
        XCTAssertEqual(record["name"] as? String, ""); XCTAssertEqual(record[JournalRecordMapping.instrumentNameKey] as? String, "")
        XCTAssertNil(record[JournalRecordMapping.instrumentRefKey])
    }

    func testImportedClearsStayClearedAndAnOlderValueNeverReappears() throws {
        makeProfile(name: "Samuel", primary: "Cello", instruments: ["Cello"])
        setLocation("Bristol")
        _ = scan()
        store.update { $0.outbox.removeAll(); $0.profileStamp = Date(timeIntervalSince1970: 1_000) }
        // The other device cleared the location, later.
        let t2 = Date(timeIntervalSince1970: 2_000)
        _ = applyProfile(serverProfile(name: "Samuel", location: "", primary: "Cello", stamp: t2))
        XCTAssertEqual(ProfileStore.presentedLocation(for: scope.locationUserID), "")
        // A relaunch's scan, and the screen closing with the same value: nothing sent back.
        setLocation("")
        XCTAssertTrue(scan().isEmpty)
        XCTAssertNil(outbox(JournalProfileSync.profileName))
        // The same record delivered again (an echo): nothing changes.
        let again = applyProfile(serverProfile(name: "Samuel", location: "", primary: "Cello", stamp: t2))
        XCTAssertEqual(again.applied, 0); XCTAssertTrue(again.resend.isEmpty)
        XCTAssertEqual(store.state.profileStamp, t2)
    }

    // MARK: the primary instrument against the stage C rules

    func testPrimaryInstrumentResolvesByAliasOrNameWithoutDuplicates() throws {
        makeProfile(name: "Samuel", primary: "Cello", instruments: ["Cello"])
        let localCello = try XCTUnwrap(try container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Instrument")).first)
        let otherID = UUID()   // the other device's own Cello row
        _ = applyProfile(serverProfile(name: "Samuel", location: "", primary: "cello", primaryID: otherID, stamp: Date(timeIntervalSince1970: 1_000)))
        let instruments = try container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Instrument"))
        XCTAssertEqual(instruments.count, 1, "the same-named instrument is aliased, not duplicated")
        XCTAssertEqual(store.state.instrumentAliases[otherID.uuidString], (localCello.value(forKey: "id") as? UUID)?.uuidString)
        XCTAssertEqual(values().primaryInstrument, "Cello", "the profile stores this device's row name")
        // A primary unknown here is created once, with the sender's id, and a repeat does not duplicate it.
        let violaID = UUID()
        _ = applyProfile(serverProfile(name: "Samuel", location: "", primary: "Viola", primaryID: violaID, stamp: Date(timeIntervalSince1970: 2_000)))
        _ = applyProfile(serverProfile(name: "Samuel", location: "", primary: "Viola", primaryID: violaID, stamp: Date(timeIntervalSince1970: 3_000)))
        let after = try container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Instrument"))
        XCTAssertEqual(after.count, 2)
        XCTAssertTrue(after.contains { ($0.value(forKey: "id") as? UUID) == violaID })
        XCTAssertEqual(values().primaryInstrument, "Viola")
    }

    // MARK: the avatar on its own record

    func testAvatarTravelsByHashOnItsOwnRecordAndATextEditDoesNotCarryIt() throws {
        makeProfile(name: "Samuel", primary: "", instruments: [])
        let image = UIImage(data: pngData(0.3))!
        // The editor's writer: the hook fires; the scan queues the avatar record.
        var hooks = 0
        JournalProfileMirror.onChange = { removed in XCTAssertFalse(removed); hooks += 1 }
        ProfileStore.saveAvatarDerived(image, for: scope.avatarUserID)
        XCTAssertEqual(hooks, 1)
        let queued = scan()
        XCTAssertEqual(Set(queued.map(\.recordName)), [JournalProfileSync.profileName, JournalProfileSync.avatarName])
        let avatarRecord = JournalProfileSync.avatarRecord(scope: scope, store: store)
        let localHash = JournalAssetHash.hash(of: avatarURL)!
        XCTAssertNotNil(avatarRecord[JournalRecordMapping.assetKey])
        XCTAssertEqual(avatarRecord[JournalRecordMapping.fileHashKey] as? String, localHash)
        let mtime = JournalAssetHash.stamp(of: avatarURL)!.mtime
        XCTAssertEqual((avatarRecord["userModifiedAt"] as? Date)?.timeIntervalSince1970 ?? 0, mtime, accuracy: 1, "the file's time is its clock")
        // As if sent: the server holds this hash.
        store.update { $0.outbox.removeAll(); $0.assetHashes[JournalProfileSync.avatarName] = localHash }
        // A text edit queues ONLY the profile record.
        setLocation("Bath")
        let textEdit = scan()
        XCTAssertEqual(textEdit.map(\.recordName), [JournalProfileSync.profileName])
        XCTAssertNil(profileRecordBuilt()[JournalRecordMapping.assetKey])
        // Removing the avatar: the hook says so; the record carries no asset, hash "", and a clock.
        store.update { $0.outbox.removeAll() }
        var removed = false
        JournalProfileMirror.onChange = { r in removed = removed || r }
        ProfileStore.deleteAvatar(for: scope.avatarUserID)
        XCTAssertTrue(removed)
        store.update { $0.avatarRemovedAt = Date(timeIntervalSince1970: 7_000) }   // what the engine's hook does
        XCTAssertEqual(scan().map(\.recordName), [JournalProfileSync.avatarName])
        let removal = JournalProfileSync.avatarRecord(scope: scope, store: store)
        XCTAssertNil(removal[JournalRecordMapping.assetKey])
        XCTAssertEqual(removal[JournalRecordMapping.fileHashKey] as? String, "")
        XCTAssertEqual(removal["userModifiedAt"] as? Date, Date(timeIntervalSince1970: 7_000))
    }

    func testAvatarImportWritesBytesVerbatimSetsNoConnectedMarkerAndRemovalAndConflictsFollowTheClock() throws {
        makeProfile(name: "Samuel")
        _ = scan(); store.update { $0.outbox.removeAll() }   // the profile text is already exchanged
        let png = pngData(0.6)
        let t1 = Date(timeIntervalSince1970: 1_000)
        let incoming = serverAvatar(png: png, stamp: t1)
        let out = applyAvatar(incoming)
        XCTAssertEqual(out.applied, 1); XCTAssertTrue(out.avatarChanged); XCTAssertEqual(out.avatarBytes, Int64(png.count))
        XCTAssertEqual(try Data(contentsOf: avatarURL), png, "written byte for byte, so the hash matches the server's")
        XCTAssertEqual(JournalAssetHash.stamp(of: avatarURL)!.mtime, t1.timeIntervalSince1970, accuracy: 1, "clocked with the sender's time")
        XCTAssertNotNil(ProfileStore.avatarImage(for: scope.avatarUserID))
        XCTAssertNotNil(ProfileStore.avatarOriginalImage(for: scope.avatarUserID), "the editor opens with a copy to re-crop")
        XCTAssertNotNil(ProfileStore.avatarImage(for: nil), "both scopes, as the editor writes")
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarSync(), "an import is not a local edit: no Solo→Connected marker")
        XCTAssertEqual(store.state.assetHashes[JournalProfileSync.avatarName], incoming[JournalRecordMapping.fileHashKey] as? String)
        XCTAssertTrue(scan().isEmpty, "the imported file is what the server holds; nothing goes back")
        // The same record again: nothing.
        XCTAssertEqual(applyAvatar(incoming).applied, 0)
        // Removed on the other device, later: removed here, displaced copy kept, clock recorded.
        let t2 = Date(timeIntervalSince1970: 2_000)
        let removal = applyAvatar(serverAvatar(png: nil, stamp: t2))
        XCTAssertEqual(removal.applied, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: avatarURL.path))
        XCTAssertNil(ProfileStore.avatarImage(for: nil))
        XCTAssertEqual(store.state.avatarRemovedAt, t2)
        XCTAssertEqual(store.state.assetHashes[JournalProfileSync.avatarName], "")
        XCTAssertEqual(JournalProfileSync.displacedAvatars().count, 1)
        XCTAssertTrue(scan().isEmpty, "removed stays removed: the next scan sends nothing")
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarSync())
        // A local avatar set AFTER that (newer clock) meets an older server image: kept, and resent.
        let local = UIImage(data: pngData(0.9))!
        ProfileStore.saveAvatarDerived(local, for: scope.avatarUserID)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 9_000)], ofItemAtPath: avatarURL.path)
        store.update { $0.fileStampCache.removeValue(forKey: JournalProfileSync.avatarName) }
        let localHash = JournalAssetHash.hash(of: avatarURL)!
        let older = applyAvatar(serverAvatar(png: pngData(0.1), stamp: Date(timeIntervalSince1970: 5_000)), localPending: true)
        XCTAssertEqual(older.applied, 0)
        XCTAssertEqual(older.resend.map(\.recordName), [JournalProfileSync.avatarName])
        XCTAssertEqual(JournalAssetHash.hash(of: avatarURL), localHash, "the local image stayed")
        XCTAssertNotNil(store.state.lastKnownRecords[JournalProfileSync.avatarName], "the resend goes on top of the server's change tag")
        // A record delivered without its file (the catch-up's shape) is not applied and not recorded as known.
        store.update { $0.assetHashes[JournalProfileSync.avatarName] = localHash }
        let bare = serverAvatar(png: pngData(0.2), stamp: Date(timeIntervalSince1970: 10_000))
        bare[JournalRecordMapping.assetKey] = nil
        let waited = applyAvatar(bare)
        XCTAssertEqual(waited.applied, 0)
        XCTAssertEqual(store.state.assetHashes[JournalProfileSync.avatarName], localHash)
        XCTAssertEqual(JournalAssetHash.hash(of: avatarURL), localHash)
    }

    // MARK: migration and two established profiles

    func testAnUnclockedMigrationYieldsToARealEditAndTwoEstablishedProfilesConvergeInOneRound() throws {
        // Device B (this store): established, unclocked, queued by the transition.
        makeProfile(name: "Sam", primary: "Bass", instruments: ["Bass", "Cello"])
        setLocation("London")
        _ = scan()
        XCTAssertNotNil(outbox(JournalProfileSync.profileName)); XCTAssertNil(store.state.profileStamp)
        // Device A's profile, also unclocked, reached the server first.
        let a = applyProfile(serverProfile(name: "Samuel Dixon", location: "", primary: "Cello", stamp: nil))
        XCTAssertEqual(a.applied, 1)
        XCTAssertEqual(values(), JournalProfileValues(name: "Samuel Dixon", location: "London", primaryInstrument: "Cello"))
        XCTAssertEqual(a.resend.count, 1, "the merged values differ from the server's: sent back on top of its tag")
        XCTAssertNotNil(outbox(JournalProfileSync.profileName))
        XCTAssertNil(store.state.profileStamp, "a merge of two unclocked profiles is still unclocked")
        let displaced = store.state.conflicts.filter { $0.recordType == JournalSyncRecordType.profile }
        XCTAssertEqual(displaced.count, 1)
        XCTAssertTrue(displaced[0].losingTitle?.contains("name (this device): Sam") == true)
        XCTAssertTrue(displaced[0].losingTitle?.contains("instrument (this device): Bass") == true)
        // Device A then receives the merged record: the same rule gives the same result, nothing more to send.
        let aStore = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("a.json"))
        let aLocal = JournalProfileValues(name: "Samuel Dixon", location: "", primaryInstrument: "Cello")
        let merged = JournalProfileValues(name: "Samuel Dixon", location: "London", primaryInstrument: "Cello")
        let onA = JournalProfileMerge.decide(local: aLocal, localStamp: aStore.state.profileStamp, localPending: false, server: merged, serverStamp: nil)
        XCTAssertEqual(onA.apply, merged); XCTAssertFalse(onA.send)
        // A real edit beats migration data: a clocked server copy over our unclocked pending send (a rejected save).
        let t1 = Date(timeIntervalSince1970: 1_000)
        let real = applyProfile(serverProfile(name: "Samuel D", location: "Leeds", primary: "Cello", stamp: t1), localPending: true)
        XCTAssertEqual(real.applied, 1); XCTAssertTrue(real.resend.isEmpty)
        XCTAssertNil(outbox(JournalProfileSync.profileName), "our migration row is dropped")
        XCTAssertEqual(values().location, "Leeds")
        XCTAssertEqual(store.state.profileStamp, t1)
        // And our own clocked edit later beats an unclocked copy from elsewhere.
        setLocation("Bath")
        _ = scan(now: Date(timeIntervalSince1970: 2_000))
        let stale = applyProfile(serverProfile(name: "Old", location: "Old", primary: "", stamp: nil), localPending: true)
        XCTAssertEqual(stale.applied, 0); XCTAssertEqual(stale.resend.count, 1)
        XCTAssertEqual(values().location, "Bath")
    }

    // MARK: Connected isolation

    func testPrivateSyncStartsNoConnectedWriteAndTheRemotePathsRefuseWithoutAnIdentity() throws {
        // The trial's identity state: an owner key, no Connected identity, no backend id, no token.
        XCTAssertFalse(ProfileMaintenancePolicy.mayAttemptRemoteMaintenance(
            hasConnectedIdentity: false, isBackendConfigured: BackendConfig.isConfigured, hasAccessToken: false, backendUserID: nil),
            "ProfileView's directory publish (debounce, blur, close, mount) stops at the policy")
        var remoteAsked = false
        let decision = ProfileMaintenanceGate.decide(commitLocally: { .success(()) },
                                                     mayAttemptRemote: { remoteAsked = true; return ProfileMaintenancePolicy.mayAttemptRemoteMaintenance(
                                                        hasConnectedIdentity: false, isBackendConfigured: true, hasAccessToken: false, backendUserID: nil) })
        XCTAssertNotEqual(decision, .remotePermitted)
        XCTAssertTrue(remoteAsked, "the gate consulted the real policy, which refused")
        // An import of profile text and an avatar, then the screen's own re-save of the same values.
        makeProfile(name: "")
        _ = applyProfile(serverProfile(name: "Samuel Dixon", location: "London", primary: "", stamp: Date(timeIntervalSince1970: 1_000)))
        _ = applyAvatar(serverAvatar(png: pngData(0.5), stamp: Date(timeIntervalSince1970: 1_000)))
        setLocation(ProfileStore.presentedLocation(for: scope.locationUserID))   // what persistProfileEdits does on close
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarUpload())
        XCTAssertFalse(ProfileStore.hasPendingLocalAvatarDeletion())
        XCTAssertEqual(ConnectedWriteWitness.total, 0, "no directory upsert, avatar key patch, avatar upload or delete was attempted")
        // The avatar hydration decision the Connected path uses has nothing pending to promote.
        XCTAssertEqual(OwnAvatarSync.decide(lastApplied: nil, backendVersion: nil, backendHasAvatar: false,
                                            hasPendingLocalChange: ProfileStore.hasPendingLocalAvatarSync()), .recordOnly)
        // A deliberate local edit keeps its legitimate marker (existing Solo→Connected behaviour is untouched).
        ProfileStore.saveAvatarDerived(UIImage(data: pngData(0.8))!, for: nil)
        XCTAssertTrue(ProfileStore.hasPendingLocalAvatarUpload())
    }

    // MARK: erase and the account boundary

    func testLocalRemovalResetsWhatTheScanKnowsAndTheErasedProfileIsNotSent() throws {
        makeProfile(name: "Samuel", primary: "Cello", instruments: ["Cello"])
        setLocation("Bristol")
        ProfileStore.saveAvatarDerived(UIImage(data: pngData(0.4))!, for: scope.avatarUserID)
        _ = scan(now: Date(timeIntervalSince1970: 1_000))
        store.update { $0.outbox.removeAll(); $0.profileStamp = Date(timeIntervalSince1970: 1_000); $0.assetHashes[JournalProfileSync.avatarName] = "h" }
        // The erase: marker set, then everything wiped. The scan does nothing while the marker is set.
        JournalLocalRemoval.begin(store: store, reason: "test")
        for p in try container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Profile")) { container.viewContext.delete(p) }
        try container.viewContext.save()
        setLocation(""); ProfileStore.deleteAvatar(for: scope.avatarUserID)
        XCTAssertTrue(scan().isEmpty)
        XCTAssertTrue(store.state.outbox.isEmpty)
        JournalLocalRemoval.finish(store: store, container: container)
        XCTAssertEqual(store.state.profileFingerprint, JournalProfileValues().fingerprint, "the baseline is the empty profile")
        XCTAssertNil(store.state.profileStamp); XCTAssertNil(store.state.avatarRemovedAt)
        XCTAssertNil(store.state.assetHashes[JournalProfileSync.avatarName])
        // After the erase nothing is sent: an empty profile, no avatar.
        XCTAssertTrue(scan().isEmpty)
        // Typing a new profile before re-enable IS a clocked edit (not migration data).
        makeProfile(name: "New")
        let typed = scan(now: Date(timeIntervalSince1970: 9_000))
        XCTAssertEqual(typed.map(\.recordName), [JournalProfileSync.profileName])
        XCTAssertEqual(store.state.profileStamp, Date(timeIntervalSince1970: 9_000))
        // Older state files decode with the stage H defaults.
        let old = try JSONSerialization.data(withJSONObject: ["bootstrapQueued": true, "outbox": [], "lastKnownRecords": [:]])
        let decoded = try JSONDecoder().decode(JournalSyncPersistedState.self, from: old)
        XCTAssertNil(decoded.profileFingerprint); XCTAssertNil(decoded.profileStamp); XCTAssertEqual(decoded.avatarUploads, 0)
    }
}
#endif
