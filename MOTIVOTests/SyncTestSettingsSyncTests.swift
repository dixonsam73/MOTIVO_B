//
//  SyncTestSettingsSyncTests.swift
//  MOTIVOTests — compiled only in the SyncTest configuration (SYNCTEST).
//
//  Stage J: the Journal Tint and primary activity settings, the Lists default,
//  autofill and preset of each (activity, instrument) context, and the
//  instrument colour map through the bound journal. Pre-existing values go up
//  without a clock and yield to a clocked edit; an explicit clear travels as
//  a value; a context resolves by instrument NAME on the other device; a
//  record whose instrument is not here yet is held and lands when it arrives;
//  the colour map merges by union with the server standing on a clash and
//  converges with the real sanitiser; a wiped device after an erase sends
//  nothing; the recovery entries carry readable, restorable fields.
//

#if SYNCTEST
import XCTest
import CoreData
import CloudKit
@testable import Etudes

@MainActor
final class SyncTestSettingsSyncTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempDir: URL!
    private var store: JournalSyncStateStore!
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext { container.viewContext }
    private let scope = "test-scope"
    private let owner: String? = "test-owner"

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "synctest-j-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("synctest-j-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = JournalSyncStateStore(fileURL: tempDir.appendingPathComponent("state.json"))
        container = NSPersistentContainer(name: "MOTIVO")
        let description = NSPersistentStoreDescription(url: tempDir.appendingPathComponent("store.sqlite"))
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)
        JournalSettingsMirror.suppressed = false
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        container = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: helpers

    @discardableResult
    private func makeInstrument(_ name: String, id: UUID = UUID()) -> NSManagedObject {
        let row = NSEntityDescription.insertNewObject(forEntityName: "Instrument", into: context)
        row.setValue(id, forKey: "id"); row.setValue(name, forKey: "name")
        try? context.save()
        return row
    }

    private func scan() -> [JournalSyncPendingChange] {
        JournalSettingsSync.scan(store: store, defaults: defaults, context: context, scope: scope, tintOwner: .some(owner))
    }

    private func records(_ names: [String]) -> [String: CKRecord] {
        JournalSettingsSync.records(for: names, store: store, defaults: defaults, context: context, scope: scope, tintOwner: .some(owner))
    }

    private func apply(_ recs: [CKRecord], localPending: Bool? = nil) -> JournalSettingsSync.Outcome {
        JournalSettingsSync.apply(recs, store: store, defaults: defaults, context: context, scope: scope, tintOwner: .some(owner), localPending: localPending) { _ in }
    }

    /// A record as the other device would send it.
    private func settingRecord(_ key: String, value: String, stamp: Date?) -> CKRecord {
        let r = CKRecord(recordType: JournalSyncRecordType.setting,
                         recordID: CKRecord.ID(recordName: JournalSettingKey.recordName(key), zoneID: JournalRecordMapping.zoneID))
        r[JournalSettingsKeys.value] = value as CKRecordValue
        r[JournalSettingsKeys.stamp] = stamp.map { $0 as CKRecordValue }
        return r
    }

    private func contextRecord(activity: String, instrument: String, defaultList: String, autofill: Bool?, preset: [String], stamp: Date?) -> CKRecord {
        let name = JournalListContextValues.recordName(activityRef: activity, instrumentName: instrument)
        let r = CKRecord(recordType: JournalSyncRecordType.listContext, recordID: CKRecord.ID(recordName: name, zoneID: JournalRecordMapping.zoneID))
        r[JournalSettingsKeys.activityRef] = activity as CKRecordValue
        r[JournalSettingsKeys.instrumentName] = instrument as CKRecordValue
        r[JournalSettingsKeys.defaultListID] = defaultList as CKRecordValue
        r[JournalSettingsKeys.autofill] = autofill.map { NSNumber(value: $0) }
        r[JournalSettingsKeys.preset] = JournalListContextValues.normalisedPreset(preset).map { $0 as CKRecordValue }
        r[JournalSettingsKeys.stamp] = stamp.map { $0 as CKRecordValue }
        return r
    }

    private func tintRecord(_ map: [String: Int]) -> CKRecord {
        let r = CKRecord(recordType: JournalSyncRecordType.tintMap,
                         recordID: CKRecord.ID(recordName: JournalSyncRecordType.tintMapRecordName, zoneID: JournalRecordMapping.zoneID))
        r[JournalSettingsKeys.map] = JournalTintMapMerge.encode(map).map { $0 as CKRecordValue }
        return r
    }

    private func listsContext(_ activity: String, _ instrument: UUID?) -> ListsDefaultContext {
        ListsDefaultContext(ownerScope: scope, activityRef: activity, instrumentID: instrument)
    }

    // MARK: Settings

    func testDefaultsSendNothingAtTransitionAndAChoiceIsAClockedEdit() {
        XCTAssertTrue(scan().isEmpty, "defaults say nothing")
        XCTAssertTrue(store.state.settingsScanDone)
        defaults.set("thread", forKey: "appSettings_tintMode")
        let pending = scan()
        XCTAssertEqual(pending.map(\.recordName), [JournalSettingKey.recordName(JournalSettingKey.tintMode)])
        XCTAssertNotNil(store.state.settingStamps[JournalSettingKey.tintMode], "a choice after the transition is clocked")
        let record = records(pending.map(\.recordName))[pending[0].recordName]
        XCTAssertEqual(record?[JournalSettingsKeys.value] as? String, "thread")
        XCTAssertNotNil(record?[JournalSettingsKeys.stamp])
    }

    func testPreExistingValueGoesUpUnclockedAndYieldsToAClockedEdit() {
        defaults.set("instrument", forKey: "appSettings_tintMode")
        let pending = scan()
        XCTAssertEqual(pending.count, 1)
        XCTAssertTrue(pending[0].metadataOnly, "transition: no clock")
        XCTAssertNil(store.state.settingStamps[JournalSettingKey.tintMode])
        // The other device chose "thread" with a clock: it wins.
        let outcome = apply([settingRecord(JournalSettingKey.tintMode, value: "thread", stamp: Date())], localPending: true)
        XCTAssertEqual(outcome.applied, 1)
        XCTAssertEqual(defaults.string(forKey: "appSettings_tintMode"), "thread")
        XCTAssertTrue(outcome.settled.contains(JournalSettingKey.recordName(JournalSettingKey.tintMode)))
        XCTAssertFalse(store.state.outbox.contains { $0.recordName == JournalSettingKey.recordName(JournalSettingKey.tintMode) })
        XCTAssertTrue(scan().isEmpty, "the applied value is the new baseline, not an edit")
        // The displaced local value is readable.
        let entry = store.state.conflicts.last
        XCTAssertEqual(entry?.subject, "Journal Tint")
        XCTAssertEqual(entry?.displaced["Journal Tint (this device)"], Theme.TintMode.instrument.displayName)
    }

    func testTwoUnclockedValuesGoToTheServerAndANewerLocalEditIsKeptAndResent() {
        defaults.set("instrument", forKey: "appSettings_tintMode")
        _ = scan()
        _ = apply([settingRecord(JournalSettingKey.tintMode, value: "activity", stamp: nil)], localPending: true)
        XCTAssertEqual(defaults.string(forKey: "appSettings_tintMode"), "activity", "no clock on either side: server")
        // A later local edit beats an older server clock.
        defaults.set("off", forKey: "appSettings_tintMode")
        _ = scan()
        let older = Date().addingTimeInterval(-600)
        let outcome = apply([settingRecord(JournalSettingKey.tintMode, value: "thread", stamp: older)], localPending: true)
        XCTAssertEqual(defaults.string(forKey: "appSettings_tintMode"), "off")
        XCTAssertEqual(outcome.resend.map(\.recordName), [JournalSettingKey.recordName(JournalSettingKey.tintMode)])
        XCTAssertEqual(store.state.conflicts.last?.displaced["Journal Tint (other device)"], Theme.TintMode.thread.displayName)
    }

    func testPrimaryActivityResolvesACustomNameToThisDevicesSpelling() throws {
        let owner = try XCTUnwrap(PersistenceController.shared.ownerIDForCustoms)
        let row = NSEntityDescription.insertNewObject(forEntityName: "UserActivity", into: context)
        row.setValue(UUID(), forKey: "id"); row.setValue("Sight Reading", forKey: "displayName")
        row.setValue(PersistenceController.normalized("Sight Reading"), forKey: "normalizedName")
        row.setValue(owner, forKey: "ownerUserID"); row.setValue(Int16(0), forKey: "coreActivityCode")
        try context.save()
        defer { context.delete(row); try? context.save() }
        _ = scan()
        _ = apply([settingRecord(JournalSettingKey.primaryActivity, value: "custom:sight reading", stamp: Date())])
        XCTAssertEqual(defaults.string(forKey: "primaryActivityRef"), "custom:Sight Reading")
        XCTAssertEqual(store.state.settingFingerprints[JournalSettingKey.primaryActivity], "custom:Sight Reading", "fingerprint is what the device holds")
        XCTAssertTrue(scan().isEmpty, "the resolved spelling is not a phantom edit")
        // Explicit reset to the default travels as a value.
        defaults.set("core:0", forKey: "primaryActivityRef")
        let pending = scan()
        XCTAssertEqual(pending.map(\.recordName), [JournalSettingKey.recordName(JournalSettingKey.primaryActivity)])
        XCTAssertEqual(records(pending.map(\.recordName)).values.first?[JournalSettingsKeys.value] as? String, "core:0")
    }

    // MARK: List contexts

    func testContextIsKeyedByInstrumentNameAndAppliesUnderThisDevicesInstrumentID() throws {
        let cello = makeInstrument("Cello")
        let celloID = try XCTUnwrap(cello.value(forKey: "id") as? UUID)
        _ = scan()
        // The other device's Cello had a different id; the record names it.
        let listID = UUID().uuidString
        let record = contextRecord(activity: "core:0", instrument: "cello", defaultList: listID, autofill: true, preset: ["Scales", "Bach"], stamp: Date())
        let outcome = apply([record])
        XCTAssertEqual(outcome.applied, 1)
        let ctx = listsContext("core:0", celloID)
        XCTAssertEqual(defaults.string(forKey: ctx.defaultIDKey), listID)
        XCTAssertTrue(defaults.bool(forKey: ctx.autofillKey))
        XCTAssertEqual(JournalListContextValues.presetLines(JournalListContextValues.normalisedPreset(defaults.object(forKey: ctx.tasksKey))).map(\.text), ["Scales", "Bach"])
        XCTAssertTrue(scan().isEmpty, "applied values are the baseline")
        // The same context edited here goes up under the same record name.
        ctx.recordExplicitChoice(listID: nil, presetData: JournalListContextValues.normalisedPreset(["Scales"]), defaults: defaults)
        let pending = scan()
        XCTAssertEqual(pending.map(\.recordName), [record.recordID.recordName])
        let sent = try XCTUnwrap(records(pending.map(\.recordName))[record.recordID.recordName])
        XCTAssertEqual(sent[JournalSettingsKeys.defaultListID] as? String, "", "an explicit clear is a value")
        XCTAssertEqual((sent[JournalSettingsKeys.autofill] as? NSNumber)?.boolValue, false)
        XCTAssertEqual(sent[JournalSettingsKeys.instrumentName] as? String, "Cello")
        XCTAssertNotNil(sent[JournalSettingsKeys.stamp])
    }

    func testContextForAnUnknownInstrumentIsHeldAndLandsWhenItArrives() throws {
        _ = scan()
        let record = contextRecord(activity: "core:1", instrument: "Viola", defaultList: "", autofill: false, preset: ["Warm up"], stamp: Date())
        let first = apply([record])
        XCTAssertEqual(first.held, 1)
        XCTAssertEqual(first.applied, 0)
        XCTAssertEqual(store.state.awaitingListContext.count, 1)
        let viola = makeInstrument("Viola")
        let violaID = try XCTUnwrap(viola.value(forKey: "id") as? UUID)
        let retry = JournalSettingsSync.retryHeld(store: store, defaults: defaults, context: context, scope: scope) { _ in }
        XCTAssertEqual(retry.applied, 1)
        XCTAssertTrue(store.state.awaitingListContext.isEmpty)
        let ctx = listsContext("core:1", violaID)
        XCTAssertEqual(defaults.object(forKey: ctx.autofillKey) as? Bool, false, "an explicit off travels")
        XCTAssertEqual(JournalListContextValues.presetLines(JournalListContextValues.normalisedPreset(defaults.object(forKey: ctx.tasksKey))).map(\.text), ["Warm up"])
    }

    func testActivityOnlyContextAndLegacyArrayPresetTravel() throws {
        _ = scan()
        let ctx = listsContext("core:2", nil)
        defaults.set(["Mic check", "Takes"], forKey: ctx.tasksKey)   // legacy [String] shape
        let pending = scan()
        XCTAssertEqual(pending.count, 1)
        let sent = try XCTUnwrap(records(pending.map(\.recordName)).values.first)
        XCTAssertEqual(sent[JournalSettingsKeys.instrumentName] as? String, "")
        XCTAssertEqual(JournalListContextValues.presetLines(sent[JournalSettingsKeys.preset] as? Data).map(\.type), ["task", "task"])
    }

    func testPreExistingContextYieldsToAClockedOneAndTheDisplacedPresetIsReadable() throws {
        let cello = makeInstrument("Cello")
        let celloID = try XCTUnwrap(cello.value(forKey: "id") as? UUID)
        let ctx = listsContext("core:0", celloID)
        ctx.recordExplicitChoice(listID: nil, presetData: JournalListContextValues.normalisedPreset(["Old preset"]), defaults: defaults)
        let pending = scan()
        XCTAssertEqual(pending.count, 1)
        XCTAssertTrue(pending[0].metadataOnly, "transition: unclocked")
        let record = contextRecord(activity: "core:0", instrument: "Cello", defaultList: "", autofill: true, preset: ["New preset"], stamp: Date())
        let outcome = apply([record], localPending: true)
        XCTAssertEqual(outcome.applied, 1)
        XCTAssertEqual(JournalListContextValues.presetLines(JournalListContextValues.normalisedPreset(defaults.object(forKey: ctx.tasksKey))).map(\.text), ["New preset"])
        XCTAssertEqual(store.state.conflicts.last?.displaced["Preset (this device)"], "Old preset")
        XCTAssertNil(store.state.conflicts.last?.restore, "list settings are copy-only")
    }

    // MARK: Instrument colours

    func testColourMapMergesByUnionWithTheServerStandingOnAClashAndRemovalsNeverSend() {
        Theme.InstrumentTint.storeSlotMap(["oud": 2, "viola": 4], ownerID: owner, defaults: defaults)
        let pending = scan()
        XCTAssertEqual(pending.map(\.recordName), [JournalSyncRecordType.tintMapRecordName])
        // The other device: oud on a different slot, plus cello.
        let outcome = apply([tintRecord(["oud": 3, "cello": 5])])
        let merged = Theme.InstrumentTint.storedSlotMap(ownerID: owner, defaults: defaults)
        XCTAssertEqual(merged["oud"], 3, "clash: the server's slot stands")
        XCTAssertEqual(merged["cello"], 5)
        XCTAssertEqual(merged["viola"], 4, "existing assignment kept")
        XCTAssertEqual(outcome.resend.map(\.recordName), [JournalSyncRecordType.tintMapRecordName], "the union goes back up")
        XCTAssertEqual(store.state.tintMapExchanged, ["oud": 3, "cello": 5, "viola": 4])
        // A local removal is not a change.
        Theme.InstrumentTint.storeSlotMap(["oud": 3, "cello": 5], ownerID: owner, defaults: defaults)
        store.update { $0.tintMapQueuedFingerprint = nil; $0.outbox.removeAll() }
        XCTAssertTrue(scan().isEmpty)
        // A new label is.
        Theme.InstrumentTint.storeSlotMap(["oud": 3, "cello": 5, "harp": 2], ownerID: owner, defaults: defaults)
        XCTAssertEqual(scan().count, 1)
    }

    func testTwoDevicesConvergeThroughTheRealSanitiser() {
        // Device A and B each assigned colours before they met. Simulate the
        // exchange with the sanitiser both devices run on read.
        var a: [String: Int] = ["oud": 2, "viola": 4, "harp": 3]
        var b: [String: Int] = ["viola": 2, "cello": 4]
        func sanitise(_ m: [String: Int]) -> [String: Int] { Theme.InstrumentTint.sanitized(m, primaryLabel: nil) }
        var server = a                                  // A uploaded first
        for _ in 0..<4 {
            // B imports.
            let mergedB = JournalTintMapMerge.merge(local: b, server: server)
            b = sanitise(mergedB)
            if mergedB != server { server = b }         // B sends its (sanitised) map; server-wins semantics on A's next import
            // A imports.
            let mergedA = JournalTintMapMerge.merge(local: a, server: server)
            a = sanitise(mergedA)
            if mergedA != server { server = a }
        }
        XCTAssertEqual(a, b, "both devices hold the same map")
        XCTAssertEqual(Set(a.keys), ["oud", "viola", "harp", "cello"], "nothing lost")
        XCTAssertEqual(a["oud"], 2, "A's existing assignment kept where no clash")
        XCTAssertEqual(a["harp"], 3, "A's existing assignment kept where no clash")
        XCTAssertEqual(a["cello"], 4, "B's existing assignment kept where no clash")
        // viola clashed (A 4, B 2): the first upload's slot stood, and because
        // cello already held 4 the sanitiser moved viola once, on both devices.
        XCTAssertEqual(Set(a.values).count, a.count, "no two labels on one slot after the sanitiser")
        let again = sanitise(JournalTintMapMerge.merge(local: a, server: server))
        XCTAssertEqual(again, a, "stable: a further round changes nothing")
    }

    // MARK: Erase baseline and recovery entries

    func testAfterAnEraseTheWipedDefaultsSendNothing() {
        defaults.set("thread", forKey: "appSettings_tintMode")
        _ = scan()
        XCTAssertNotNil(store.state.settingFingerprints[JournalSettingKey.tintMode])
        // What JournalLocalRemoval.finish does to this stage's state.
        store.update { s in
            s.settingsScanDone = true
            s.settingFingerprints = Dictionary(uniqueKeysWithValues: JournalSettingKey.all.map { ($0, JournalSettingKey.defaultValue($0)) })
            s.settingStamps.removeAll(); s.listContextFingerprints.removeAll(); s.tintMapExchanged = nil; s.outbox.removeAll()
        }
        defaults.removePersistentDomain(forName: suiteName)
        XCTAssertTrue(scan().isEmpty, "wiped defaults are the baseline, nothing is sent")
        defaults.set("thread", forKey: "appSettings_tintMode")
        let pending = scan()
        XCTAssertEqual(pending.count, 1)
        XCTAssertFalse(pending[0].metadataOnly, "a choice after re-enable is a clocked edit")
    }

    func testRecoveryEntriesListOnlyUnresolvedTextAndCopyJoinsFields() {
        var text = JournalSyncConflict(at: Date(), recordName: "x", recordType: "Session", winner: "server",
                                       localUserModifiedAt: nil, serverUserModifiedAt: nil, losingTitle: nil, losingNotes: nil)
        text.subject = "Entry"; text.displaced = ["Title (this device)": "Mine", "Notes (this device)": "My notes"]; text.restore = "session:\(UUID().uuidString)"
        var empty = text; empty.displaced = ["Title (this device)": " "]
        var done = text; done.resolvedAt = Date()
        store.update { $0.conflicts = [text, empty, done] }
        let entries = JournalRecovery.entries(store: store)
        XCTAssertEqual(entries.map(\.id), [text.id])
        XCTAssertEqual(JournalRecovery.copyText(of: text), "Notes (this device): My notes\n\nTitle (this device): Mine")
        JournalRecovery.dismiss(text, store: store)
        XCTAssertTrue(JournalRecovery.entries(store: store).isEmpty)
    }

    func testRestoringASessionTitleIsANewEditOnTheRow() throws {
        let session = NSEntityDescription.insertNewObject(forEntityName: "Session", into: context)
        let id = UUID()
        session.setValue(id, forKey: "id"); session.setValue("Kept", forKey: "title"); session.setValue(Date(), forKey: "timestamp")
        try context.save()
        var entry = JournalSyncConflict(at: Date(), recordName: id.uuidString, recordType: "Session", winner: "server",
                                        localUserModifiedAt: nil, serverUserModifiedAt: nil, losingTitle: nil, losingNotes: nil)
        entry.displaced = ["Title (this device)": "Mine"]; entry.restore = "session:\(id.uuidString)"
        store.update { $0.conflicts = [entry] }
        let outcome = JournalRecovery.restore(entry, store: store, context: context, scope: .local)
        guard case .restored = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(session.value(forKey: "title") as? String, "Mine")
        XCTAssertNotNil(store.state.conflicts.first?.resolvedAt)
    }

    func testOlderStateFileDecodesConflictsWithoutTheNewFields() throws {
        let json = """
        {"conflicts":[{"id":"\(UUID().uuidString)","at":0,"recordName":"r","recordType":"Session","winner":"server"}]}
        """
        let decoded = try JSONDecoder().decode(JournalSyncPersistedState.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.conflicts.count, 1)
        XCTAssertEqual(decoded.conflicts[0].displaced, [:])
        XCTAssertNil(decoded.conflicts[0].restore)
    }
}
#endif
