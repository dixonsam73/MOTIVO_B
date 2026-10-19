//
//  JournalSyncEngine.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
//
//  PRIVATE JOURNAL SYNC THROUGH CKSyncEngine, FOR THE TWO-DEVICE TRIAL.
//
//  Adapted from Apple's CKSyncEngine sample. The engine owns transport only;
//  this class owns what goes in and out of Core Data, the outbox, the bound
//  iCloud user, and the trial's conflict rule. It never deletes local data
//  because of an account event: a different or missing account PAUSES sync.
//
//  Stage B adds custom instruments/activities and saved Lists, ownership
//  rules (`JournalOwnership`) and upload eligibility by ownership. Still out
//  of scope: Scores, profile, attachment privacy map, Instrument/Tag links.
//

#if SYNCTEST
import Foundation
import CloudKit
import CoreData
import Network
import os

/// Backoff for a failed first iCloud check: 5, 10, 20, 40 s, then every 60 s.
enum JournalSyncStartRetry {
    static func delay(attempt: Int) -> TimeInterval {
        guard attempt >= 1 else { return 5 }
        return min(60, 5 * pow(2, Double(attempt - 1)))
    }
}

@MainActor
final class JournalSyncStatus: ObservableObject {
    @Published var phase: String = "Not started"
    @Published var pausedReason: String?
    @Published var boundUser: String?
    @Published var outboxCount = 0
    @Published var heldCount = 0
    @Published var conflictCount = 0
    @Published var recordsSent = 0
    @Published var recordsReceived = 0
    @Published var bytesSent: Int64 = 0
    @Published var bytesReceived: Int64 = 0
    @Published var lastEvent: String = "—"
    @Published var lastFetchAt: Date?
    @Published var lastSendAt: Date?
}

final class JournalSyncEngine: NSObject, CKSyncEngineDelegate, JournalSendQueue, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.samueldixon.motivo.synctest", category: "JournalSync")
    let container: CKContainer
    let persistence: NSPersistentContainer
    let store: JournalSyncStateStore
    let tracker: JournalChangeTracker
    let status: JournalSyncStatus
    private(set) var engine: CKSyncEngine!
    private let importContext: NSManagedObjectContext
    private var saveObserver: NSObjectProtocol?
    private var stampObserver: NSObjectProtocol?
    private let stateLock = NSLock()
    private var paused = false
    private var currentUserRecordName: String?
    let importer: JournalImporter
    /// This install's K2, read once on the main actor (see `JournalSyncCoordinator`).
    let customOwner: String?
    /// Called on the main actor after each complete fetch (ownership rules).
    var fetchCycleCompleted: (@MainActor () -> Void)?
    private var listObserver: NSObjectProtocol?
    private var listScanScheduled = false
    /// The part of `start()` after the iCloud check has run once.
    private var started = false
    private var startAttempts = 0
    private var waitingForICloud = false
    private var startInFlight = false
    private var pathMonitor: NWPathMonitor?

    init(containerIdentifier: String, persistence: NSPersistentContainer, store: JournalSyncStateStore, status: JournalSyncStatus, customOwner: String?) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.customOwner = customOwner
        self.persistence = persistence
        self.store = store
        self.status = status
        self.tracker = JournalChangeTracker(container: persistence, store: store)
        let ctx = persistence.newBackgroundContext()
        ctx.name = "syncImport"
        ctx.transactionAuthor = JournalSyncAuthor.sync
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.importContext = ctx
        self.importer = JournalImporter(context: ctx, store: store, customOwner: customOwner)
        super.init()
        importer.queue = self
        importer.log = { [weak self] in self?.log($0) }
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: store.state.engineState,
            delegate: self
        )
        configuration.automaticallySync = true
        engine = CKSyncEngine(configuration)
    }

    // MARK: Lifecycle

    func start() async {
        if stampObserver == nil { stampObserver = JournalUserEditStamp.install() }
        await attemptStart()
    }

    /// The iCloud check, then the one-time remainder of start-up. A failed
    /// check (offline, or no iCloud account yet) is NOT an account change: the
    /// journal and pending work are kept and the check is retried on a backoff
    /// and as soon as the network path is satisfied, with no relaunch needed.
    /// A bound-account mismatch still pauses and is not retried here.
    private func attemptStart() async {
        guard !started, !startInFlight else { return }
        startInFlight = true
        defer { startInFlight = false }
        await publish { $0.phase = "Checking iCloud account" }
        do {
            let me = try await container.userRecordID()
            currentUserRecordName = me.recordName
            if let bound = store.state.boundUserRecordName {
                if bound != me.recordName {
                    waitingForICloud = false
                    pause("This journal is linked to a different iCloud account. Nothing is uploaded.")
                    return
                }
            } else {
                store.update { $0.boundUserRecordName = me.recordName }
                log("Bound journal to iCloud user \(me.recordName)")
            }
        } catch {
            scheduleStartRetry(after: error)
            return
        }
        if waitingForICloud { log("iCloud reachable again; starting without a relaunch") }
        waitingForICloud = false
        stateLock.lock(); paused = false; stateLock.unlock()
        await publish { $0.pausedReason = nil }
        started = true

        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: JournalRecordMapping.zoneID))])
        let bootstrapped = tracker.bootstrapIfNeeded()
        if bootstrapped > 0 { log("Queued \(bootstrapped) existing record(s)") }
        let customs = tracker.bootstrapCustomsIfNeeded(customOwner: customOwner)
        if customs > 0 { log("Queued \(customs) custom row(s)") }
        tracker.processHistory()
        await scanLists()
        requeueOutbox()
        installSaveObserver()
        installListObserver()
        await publish { $0.phase = "Running" }
        refreshCounts()
    }

    /// Any local save (author ≠ sync) feeds history → outbox → engine.
    private func installSaveObserver() {
        saveObserver = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextDidSave, object: nil, queue: nil) { [weak self] note in
            guard let self, let ctx = note.object as? NSManagedObjectContext,
                  ctx.transactionAuthor != JournalSyncAuthor.sync,
                  ctx.persistentStoreCoordinator === self.persistence.persistentStoreCoordinator else { return }
            self.noteLocalChanges()
        }
    }

    private func scheduleStartRetry(after error: Error) {
        waitingForICloud = true
        startAttempts += 1
        let delay = JournalSyncStartRetry.delay(attempt: startAttempts)
        log("iCloud check failed (\(error.localizedDescription)); journal and pending changes kept; retrying in \(Int(delay)) s")
        Task { @MainActor in self.status.pausedReason = "Waiting for iCloud (retrying)"; self.status.phase = "Waiting for iCloud" }
        installPathMonitorIfNeeded()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.waitingForICloud else { return }
            await self.attemptStart()
        }
    }

    /// Retries at once when connectivity returns, instead of waiting out the backoff.
    private func installPathMonitorIfNeeded() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self, path.status == .satisfied, self.waitingForICloud else { return }
            Task { await self.attemptStart() }
        }
        monitor.start(queue: DispatchQueue(label: "com.samueldixon.motivo.synctest.path"))
        pathMonitor = monitor
    }

    /// Lists live in UserDefaults; any defaults change schedules one scan.
    private func installListObserver() {
        listObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.listScanScheduled else { return }
            self.listScanScheduled = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                self.listScanScheduled = false
                await self.scanLists()
            }
        }
    }

    func scanLists() async {
        let added = await MainActor.run { JournalSavedListSync.scan(store: store) }
        guard !added.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: added.map(pendingChange))
        log("Queued \(added.count) list change(s)")
        refreshCounts()
    }

    /// The journal's owner changed: entries held back may now be eligible.
    func ownerChanged() {
        let added = tracker.requeueUnsent()
        if !added.isEmpty {
            engine.state.add(pendingRecordZoneChanges: added.map(pendingChange))
            log("Owner changed: queued \(added.count) entr\(added.count == 1 ? "y" : "ies") not yet uploaded")
        }
        Task { await scanLists() }
    }

    // MARK: JournalSendQueue

    func enqueueSave(_ recordName: String, recordType: String) {
        let change = JournalSyncPendingChange(recordName: recordName, recordType: recordType, op: .save)
        store.update { JournalChangeTracker.merge([change], into: &$0.outbox) }
        engine.state.add(pendingRecordZoneChanges: [pendingChange(change)])
    }

    func enqueueDelete(_ recordName: String, recordType: String) {
        let change = JournalSyncPendingChange(recordName: recordName, recordType: recordType, op: .delete)
        store.update { JournalChangeTracker.merge([change], into: &$0.outbox) }
        engine.state.add(pendingRecordZoneChanges: [pendingChange(change)])
    }

    func removePendingSave(_ recordName: String) { dropPendingSave(recordName) }

    func noteLocalChanges() {
        let added = tracker.processHistory()
        guard !added.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: added.map(pendingChange))
        log("Queued \(added.count) local change(s)")
        refreshCounts()
    }

    private func requeueOutbox() {
        let outbox = store.state.outbox
        guard !outbox.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: outbox.map(pendingChange))
    }

    private func pendingChange(_ c: JournalSyncPendingChange) -> CKSyncEngine.PendingRecordZoneChange {
        let id = CKRecord.ID(recordName: c.recordName, zoneID: JournalRecordMapping.zoneID)
        return c.op == .save ? .saveRecord(id) : .deleteRecord(id)
    }

    private func pause(_ reason: String) {
        stateLock.lock(); paused = true; stateLock.unlock()
        log("PAUSED: \(reason)")
        Task { @MainActor in self.status.pausedReason = reason; self.status.phase = "Paused" }
    }

    private func resume() {
        stateLock.lock(); paused = false; stateLock.unlock()
        log("Resumed")
        requeueOutbox()
        Task { @MainActor in self.status.pausedReason = nil; self.status.phase = "Running" }
    }

    private var isPaused: Bool { stateLock.lock(); defer { stateLock.unlock() }; return paused }

    // MARK: Manual controls (diagnostics screen)

    func fetchNow() async {
        do { try await engine.fetchChanges() } catch { log("fetchChanges failed: \(error.localizedDescription)") }
    }

    func sendNow() async {
        guard !isPaused else { return }
        noteLocalChanges()
        do { try await engine.sendChanges() } catch { log("sendChanges failed: \(error.localizedDescription)") }
    }

    /// Diagnostic: fetch the zone directly with CloudKit, bypassing the engine,
    /// and log what the server returns. Imports nothing.
    func probeZone() async {
        let zone = JournalRecordMapping.zoneID
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration(previousServerChangeToken: nil, resultsLimit: nil, desiredKeys: nil)
        let op = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zone], configurationsByRecordZoneID: [zone: config])
        var count = 0
        var types: [String] = []
        op.recordWasChangedBlock = { _, result in
            if case .success(let record) = result { count += 1; types.append(record.recordType) }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            op.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success: self.log("Probe: zone \(zone.zoneName) has \(count) record(s) \(types)")
                case .failure(let error): self.log("Probe failed: \(error.localizedDescription)")
                }
                continuation.resume()
            }
            self.container.privateCloudDatabase.add(op)
        }
    }

    /// Diagnostic: fetch DATABASE changes with a token kept only by this probe.
    /// First tap lists every zone; later taps list only zones changed since,
    /// which tests the server's change feed independently of the engine.
    private var probeDatabaseToken: CKServerChangeToken?
    func probeDatabaseChanges() async {
        let op = CKFetchDatabaseChangesOperation(previousServerChangeToken: probeDatabaseToken)
        var changed: [String] = []
        op.recordZoneWithIDChangedBlock = { id in changed.append(id.zoneName) }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            op.fetchDatabaseChangesResultBlock = { result in
                switch result {
                case .success(let r):
                    self.log("DB probe (\(self.probeDatabaseToken == nil ? "full" : "since token")): changed zones \(changed), more=\(r.moreComing)")
                    self.probeDatabaseToken = r.serverChangeToken
                case .failure(let error):
                    self.log("DB probe failed: \(error.localizedDescription)")
                }
                continuation.resume()
            }
            self.container.privateCloudDatabase.add(op)
        }
    }

    /// Diagnostic, trial resets only: delete the whole server zone, which also
    /// clears its tombstones. Deleting records one by one leaves tombstones
    /// that a fresh engine applies to a restored copy (seen 2026-10-19: 47
    /// real entries removed from the full-history copy). Pauses first so
    /// nothing is re-created or resent by this engine afterwards.
    func deleteServerZone() async {
        pause("Server zone deleted for a trial reset; uninstall this app next")
        let op = CKModifyRecordZonesOperation(recordZonesToSave: nil, recordZoneIDsToDelete: [JournalRecordMapping.zoneID])
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            op.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success: self.log("Server zone Journal deleted")
                case .failure(let error): self.log("Zone delete failed: \(error.localizedDescription)")
                }
                continuation.resume()
            }
            self.container.privateCloudDatabase.add(op)
        }
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let e):
            store.update { $0.engineState = e.stateSerialization }

        case .accountChange(let e):
            handleAccountChange(e)

        case .fetchedDatabaseChanges(let e):
            log("Database changes: \(e.modifications.count) zone(s) changed \(e.modifications.map { $0.zoneID.zoneName }), \(e.deletions.count) deleted")
            for deletion in e.deletions where deletion.zoneID == JournalRecordMapping.zoneID {
                log("Server zone deleted (\(deletion.reason)). Local data kept; re-creating zone on next send.")
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: JournalRecordMapping.zoneID))])
            }

        case .fetchedRecordZoneChanges(let e):
            log("Zone changes: \(e.modifications.count) modified \(e.modifications.map { $0.record.recordType }), \(e.deletions.count) deleted")
            let records = e.modifications.map(\.record)
            importModifications(records.filter { $0.recordType != JournalSyncRecordType.savedList })
            let lists = records.filter { $0.recordType == JournalSyncRecordType.savedList }
            if !lists.isEmpty {
                let n = await MainActor.run { JournalSavedListSync.apply(lists, store: store) }
                log("Imported \(n) list(s)")
            }
            importDeletions(e.deletions.map { ($0.recordID, $0.recordType) })
            let listDeletions = e.deletions.filter { $0.recordType == JournalSyncRecordType.savedList }.map(\.recordID.recordName)
            if !listDeletions.isEmpty {
                let n = await MainActor.run { JournalSavedListSync.applyDeletions(listDeletions, store: store) }
                log("Applied \(n) list deletion(s)")
            }
            await publish { $0.lastFetchAt = Date() }

        case .sentRecordZoneChanges(let e):
            handleSent(e)
            await publish { $0.lastSendAt = Date() }

        case .sentDatabaseChanges(let e):
            if !e.failedZoneSaves.isEmpty { log("Zone save failed: \(e.failedZoneSaves.map { $0.error.localizedDescription })") }

        case .didFetchRecordZoneChanges(let e):
            log("Did fetch zone \(e.zoneID.zoneName): \(e.error.map { "error \($0.localizedDescription)" } ?? "ok")")
        case .didFetchChanges(let e):
            log("Did fetch changes (\(e.context.reason))")
            if !store.state.initialFetchComplete {
                store.update { $0.initialFetchComplete = true }
                log("First complete fetch finished")
            }
            if let fetchCycleCompleted { await MainActor.run { fetchCycleCompleted() } }
        case .willFetchRecordZoneChanges(let e):
            log("Will fetch zone \(e.zoneID.zoneName)")
        case .willFetchChanges(let e):
            log("Will fetch changes (\(e.context.reason))")
        case .willSendChanges, .didSendChanges:
            await publish { $0.lastEvent = "\(event)".components(separatedBy: "(").first ?? "\(event)" }

        @unknown default:
            log("Unknown engine event")
        }
        refreshCounts()
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard !isPaused else { return nil }
        // The guard that stops one account's journal entering another: no batch
        // unless the user we are talking to is the one the journal is bound to.
        guard let bound = store.state.boundUserRecordName, bound == currentUserRecordName else {
            log("Send refused: current iCloud user is not the bound user")
            return nil
        }
        let scope = context.options.scope
        var pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        // Sessions before their attachments, deletes last.
        let outbox = store.state.outbox
        let typeByName = Dictionary(outbox.map { ($0.recordName, $0.recordType) }, uniquingKeysWith: { a, _ in a })
        pending.sort { a, b in rank(a, typeByName) < rank(b, typeByName) }
        let listNames = pending.compactMap { change -> String? in
            if case .saveRecord(let id) = change, typeByName[id.recordName] == JournalSyncRecordType.savedList { return id.recordName }
            return nil
        }
        let bases = store.state.lastKnownRecords
        let listRecords = listNames.isEmpty ? [:] : await MainActor.run { JournalSavedListSync.records(for: listNames, bases: bases) }
        let eligibility = currentEligibility()
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            if typeByName[recordID.recordName] == JournalSyncRecordType.savedList {
                if let record = listRecords[recordID.recordName] { return record }
                self.store.update { $0.outbox.removeAll { $0.recordName == recordID.recordName && $0.op == .save } }
                return nil
            }
            return self.record(for: recordID, type: typeByName[recordID.recordName], eligibility: eligibility)
        }
    }

    struct Eligibility {
        let journalOwner: String?
        let customOwner: String?
    }

    /// Upload eligibility is ownership only: K1, or the journal's single
    /// local owner when this device has no K1. Never a screen filter.
    func currentEligibility() -> Eligibility {
        var owners = Set<String>()
        importContext.performAndWait {
            let request = NSFetchRequest<NSDictionary>(entityName: JournalSyncRecordType.session)
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["ownerUserID"]
            request.returnsDistinctResults = true
            for row in (try? importContext.fetch(request)) ?? [] {
                if let o = row["ownerUserID"] as? String { owners.insert(o) }
            }
        }
        let owner = JournalOwnership.journalOwner(k1: Keychain.get("appleUserID"), local: JournalOwnership.assess(owners))
        return Eligibility(journalOwner: owner, customOwner: customOwner)
    }

    /// Instruments, then everything sessions need, then attachments, deletes last.
    private func rank(_ change: CKSyncEngine.PendingRecordZoneChange, _ types: [String: String]) -> Int {
        switch change {
        case .saveRecord(let id):
            switch types[id.recordName] {
            case JournalSyncRecordType.instrument: return 0
            case JournalSyncRecordType.attachment: return 2
            default: return 1
            }
        case .deleteRecord: return 3
        @unknown default: return 4
        }
    }

    /// Builds the outgoing record from Core Data; nil removes the pending change.
    /// Entries this device's ownership rules make ineligible stay local.
    private func record(for recordID: CKRecord.ID, type: String?, eligibility: Eligibility) -> CKRecord? {
        guard let id = UUID(uuidString: recordID.recordName) else { return nil }
        var result: CKRecord?
        var ineligible = false
        importContext.performAndWait {
            let entities = type.map { [$0] } ?? [JournalSyncRecordType.session, JournalSyncRecordType.attachment,
                                                 JournalSyncRecordType.userInstrument, JournalSyncRecordType.userActivity,
                                                 JournalSyncRecordType.instrument]
            guard let object = entities.lazy.compactMap({ self.fetch(entity: $0, id: id, in: self.importContext) }).first else { return }
            switch object.entity.name {
            case JournalSyncRecordType.session:
                ineligible = !JournalOwnership.isEligible(owner: object.value(forKey: "ownerUserID") as? String,
                                                          journalOwner: eligibility.journalOwner)
            case JournalSyncRecordType.attachment:
                let session = object.value(forKey: "session") as? NSManagedObject
                ineligible = session == nil || !JournalOwnership.isEligible(owner: session?.value(forKey: "ownerUserID") as? String,
                                                                             journalOwner: eligibility.journalOwner)
            case JournalSyncRecordType.instrument:
                ineligible = false   // profile instruments have no owner
            default:
                // Custom rows: only this install's own (K2). Rows under any other
                // owner (legacy, or the backend-id hydration bug) stay local.
                ineligible = (object.value(forKey: "ownerUserID") as? String) != eligibility.customOwner
            }
            if ineligible { return }
            let base = store.state.lastKnownRecords[recordID.recordName].flatMap(JournalSyncStateStore.recordFromSystemFields)
            result = JournalRecordMapping.record(for: object, base: base)
            if object.entity.name == JournalSyncRecordType.attachment, result?[JournalRecordMapping.assetKey] == nil {
                log("Attachment \(recordID.recordName) sent without its file (not found locally)")
            }
        }
        if result == nil {
            // Nothing to send: drop a stale save from the outbox.
            store.update {
                $0.outbox.removeAll { $0.recordName == recordID.recordName && $0.op == .save }
                if ineligible { $0.ineligibleCount += 1 }
            }
            if ineligible { log("Held back \(recordID.recordName.prefix(8))…: owned by another Apple user id") }
        }
        return result
    }

    // MARK: Account

    private func handleAccountChange(_ e: CKSyncEngine.Event.AccountChange) {
        if !started {
            // The first iCloud check never passed (offline, or signed in later):
            // this is the start we were waiting for, not a change of account.
            if case .signOut = e.changeType { return }
            Task { await attemptStart() }
            return
        }
        switch e.changeType {
        case .signIn(let user):
            currentUserRecordName = user.recordName
            if store.state.boundUserRecordName == nil {
                store.update { $0.boundUserRecordName = user.recordName }
                log("Signed in; bound to \(user.recordName)")
                resume()
            } else if store.state.boundUserRecordName == user.recordName {
                log("Signed back in to the bound account")
                resume()
            } else {
                pause("Signed in to a different iCloud account; journal kept, sync paused")
            }
        case .signOut:
            currentUserRecordName = nil
            pause("Signed out of iCloud; journal and pending changes kept")
        case .switchAccounts(_, let current):
            currentUserRecordName = current.recordName
            if store.state.boundUserRecordName == current.recordName { resume() }
            else { pause("Switched to a different iCloud account; journal kept, sync paused") }
        @unknown default:
            pause("Unknown account change")
        }
    }

    // MARK: Import (see JournalImporter)

    private func importModifications(_ records: [CKRecord]) {
        guard !records.isEmpty else { return }
        var summary = JournalImporter.Summary()
        importContext.performAndWait { summary = importer.importModifications(records) }
        store.update { $0.recordsReceived += summary.received; $0.bytesReceived += summary.bytes }
        if summary.received > 0 { log("Imported \(summary.received) record(s)\(summary.customs > 0 ? ", \(summary.customs) custom" : "")") }
    }

    private func importDeletions(_ deletions: [(CKRecord.ID, CKRecord.RecordType)]) {
        guard !deletions.isEmpty else { return }
        importContext.performAndWait { importer.importDeletions(deletions) }
        log("Applied \(deletions.count) remote deletion(s)")
    }

    // MARK: Sent

    private func handleSent(_ e: CKSyncEngine.Event.SentRecordZoneChanges) {
        var sent = 0
        var bytes: Int64 = 0
        for record in e.savedRecords {
            sent += 1
            if let asset = record[JournalRecordMapping.assetKey] as? CKAsset, let url = asset.fileURL,
               let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value {
                bytes += size
            }
            store.update {
                $0.lastKnownRecords[record.recordID.recordName] = JournalSyncStateStore.encodeSystemFields(record)
                $0.outbox.removeAll { $0.recordName == record.recordID.recordName && $0.op == .save }
            }
        }
        for recordID in e.deletedRecordIDs {
            store.update {
                $0.lastKnownRecords.removeValue(forKey: recordID.recordName)
                $0.outbox.removeAll { $0.recordName == recordID.recordName && $0.op == .delete }
            }
        }
        for failure in e.failedRecordSaves { handleFailedSave(failure) }
        for failure in e.failedRecordDeletes {
            if failure.value.code == .unknownItem {
                store.update { $0.outbox.removeAll { $0.recordName == failure.key.recordName && $0.op == .delete } }
            } else {
                log("Delete of \(failure.key.recordName) failed: \(failure.value.localizedDescription) (will retry)")
            }
        }
        store.update { $0.recordsSent += sent; $0.bytesSent += bytes }
        if sent > 0 { log("Sent \(sent) record(s), \(bytes) bytes of media") }
    }

    private func handleFailedSave(_ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave) {
        let record = failure.record
        let name = record.recordID.recordName
        switch failure.error.code {
        case .serverRecordChanged:
            guard let server = failure.error.serverRecord else { return }
            if record.recordType == JournalSyncRecordType.savedList {
                // Lists: the server copy wins a rejected send (whole list).
                Task { @MainActor in
                    JournalSavedListSync.apply([server], store: self.store, overridePending: true)
                    self.dropPendingSave(name)
                }
                log("Conflict on list \(name): server kept")
                return
            }
            var resend = false
            importContext.performAndWait {
                resend = importer.resolveSendConflict(recordType: record.recordType, recordName: name, server: server)
            }
            if resend { engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)]) }
        case .zoneNotFound:
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: JournalRecordMapping.zoneID))])
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            log("Zone missing; re-creating and resending \(name)")
        case .unknownItem:
            // The server no longer has it: resend as a new record.
            store.update { $0.lastKnownRecords.removeValue(forKey: name) }
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy, .notAuthenticated:
            log("Save of \(name) deferred: \(failure.error.localizedDescription)") // the engine retries
        default:
            log("Save of \(name) failed: \(failure.error.localizedDescription)")
        }
    }

    // MARK: Helpers

    /// When the server wins, the local edit must leave BOTH queues: our outbox
    /// and the engine's own pending list. Checkpoint 1 showed that clearing
    /// only the outbox lets the engine resend the record with the server's
    /// values, a redundant write that the other device then re-imports.
    private func dropPendingSave(_ recordName: String) {
        store.update { $0.outbox.removeAll { $0.recordName == recordName && $0.op == .save } }
        let id = CKRecord.ID(recordName: recordName, zoneID: JournalRecordMapping.zoneID)
        engine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
    }

    private func fetch(entity: String, id: UUID, in ctx: NSManagedObjectContext) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? ctx.fetch(request))?.first
    }

    private func log(_ text: String) {
        logger.notice("\(text, privacy: .public)")
        store.log(text)
        Task { @MainActor in self.status.lastEvent = text }
    }

    private func publish(_ change: @escaping @MainActor (JournalSyncStatus) -> Void) async {
        await MainActor.run { change(self.status) }
    }

    private func refreshCounts() {
        let st = store.state
        Task { @MainActor in
            self.status.outboxCount = st.outbox.count
            self.status.heldCount = st.awaitingParent.count
            self.status.conflictCount = st.conflicts.count
            self.status.recordsSent = st.recordsSent
            self.status.recordsReceived = st.recordsReceived
            self.status.bytesSent = st.bytesSent
            self.status.bytesReceived = st.bytesReceived
            self.status.boundUser = st.boundUserRecordName
        }
    }
}

/// App-wide holder so the diagnostics screen can reach the engine.
@MainActor
final class JournalSyncCoordinator {
    static let shared = JournalSyncCoordinator()
    static let containerIdentifier = "iCloud.com.samueldixon.motivo.synctest"
    let status = JournalSyncStatus()
    private(set) var engine: JournalSyncEngine?
    private(set) var store: JournalSyncStateStore?
    /// Set by the app before `startIfNeeded`: adoption writes the owner key
    /// through it (and nothing else).
    weak var auth: AuthManager?
    private(set) var ownership: JournalOwnershipCoordinator?

    private var persistence: NSPersistentContainer?

    func startIfNeeded(persistence: NSPersistentContainer) {
        guard engine == nil else { return }
        self.persistence = persistence
        let store = JournalSyncStateStore(fileURL: JournalSyncStateStore.defaultURL())
        self.store = store
        let ownership = JournalOwnershipCoordinator(store: store, persistence: persistence, auth: auth)
        self.ownership = ownership
        makeEngine(persistence: persistence, store: store)
        // Finishes an interrupted adoption; a new adoption still waits for the
        // first complete fetch.
        ownership.evaluate(reason: "launch")
    }

    private func makeEngine(persistence: NSPersistentContainer, store: JournalSyncStateStore) {
        let engine = JournalSyncEngine(containerIdentifier: Self.containerIdentifier, persistence: persistence, store: store, status: status,
                                       customOwner: PersistenceController.shared.ownerIDForCustoms)
        engine.fetchCycleCompleted = { [weak self] in self?.ownership?.evaluate(reason: "fetch") }
        ownership?.onOwnerChanged = { [weak engine] in engine?.ownerChanged() }
        self.engine = engine
        Task { await engine.start() }
    }

    /// Diagnostic: discard only the engine's own serialized state (its change
    /// tokens) and start a fresh engine. The journal, outbox, bound user and
    /// history token are all kept.
    func resetEngineState() {
        guard let store, let persistence else { return }
        store.update { $0.engineState = nil }
        store.log("Engine state reset; fresh engine")
        makeEngine(persistence: persistence, store: store)
    }
}
#endif
