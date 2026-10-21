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
//  Stage E: ONE account guard (`JournalAccountGuard`) decides whether this
//  device syncs right now, asked by sends, fetched changes (imports and
//  remote deletions), list imports and the manual controls. When it refuses,
//  the CKSyncEngine instance is DROPPED, not merely ignored, so nothing is
//  fetched from or sent to a non-bound account and its state serialization
//  is never saved; on return to the bound account a new instance is built
//  from the last state saved while bound. Account changes reach one
//  `reconcile` path from the engine's own event and from the system's
//  CKAccountChanged notification. Unlink and local removal are persisted
//  (`JournalLocalRemoval`) and need an explicit re-enable.
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
    /// The live CKSyncEngine, or nil while dormant (guard refused). Guarded by
    /// `stateLock`; delegate callbacks from a dropped instance are ignored.
    private var engineInstance: CKSyncEngine?
    private let importContext: NSManagedObjectContext
    private var saveObserver: NSObjectProtocol?
    private var stampObserver: NSObjectProtocol?
    private var accountObserver: NSObjectProtocol?
    private let stateLock = NSLock()
    private var currentUserRecordName: String?
    private var lastRefusal: String?
    let importer: JournalImporter
    /// This install's K2, read once on the main actor (see `JournalSyncCoordinator`).
    let customOwner: String?
    /// Called on the main actor after each complete fetch (ownership rules).
    var fetchCycleCompleted: (@MainActor () -> Void)?
    private var listObserver: NSObjectProtocol?
    private var listScanScheduled = false
    private var observersInstalled = false
    private var retryAttempts = 0
    /// A refusal that can clear on its own (no account yet) is retried on a
    /// backoff and when the network path is satisfied.
    private var retryPending = false
    private var reconcileInFlight = false
    private var reconcileQueued = false
    /// Bumped by every `goDormant`. An activation that awaited (the catch-up
    /// check) must find it unchanged before it builds an engine: seen
    /// 2026-10-21, an offline launch stalled in that check, an erase ran
    /// underneath it, and the stalled activation then built an engine for
    /// 20 ms on a removed copy.
    private var dormantGeneration = 0
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
        // Outgoing records must reflect the latest local save, not this
        // context's cached copy (see JournalImporter.freshObject).
        ctx.stalenessInterval = 0
        self.importContext = ctx
        self.importer = JournalImporter(context: ctx, store: store, customOwner: customOwner)
        super.init()
        importer.queue = self
        importer.log = { [weak self] in self?.log($0) }
    }

    deinit {
        for o in [saveObserver, stampObserver, accountObserver, listObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(o)
        }
        pathMonitor?.cancel()
    }

    // MARK: Lifecycle

    func start() async {
        if stampObserver == nil { stampObserver = JournalUserEditStamp.install() }
        if accountObserver == nil {
            // The system's account notification, independent of any engine
            // instance: while dormant there is no engine to tell us.
            accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { [weak self] _ in
                Task { await self?.reconcile(trigger: "iCloud account changed (system)") }
            }
        }
        if !observersInstalled {
            // Local saves feed the durable outbox in EVERY state (paused,
            // unlinked, waiting for iCloud); only transport waits for an engine.
            observersInstalled = true
            installSaveObserver()
            installListObserver()
        }
        await reconcile(trigger: "launch")
    }

    /// The current engine instance, or nil while dormant.
    var engine: CKSyncEngine? { stateLock.lock(); defer { stateLock.unlock() }; return engineInstance }

    private func isCurrent(_ e: CKSyncEngine) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return engineInstance === e
    }

    /// The one rule every data path asks (`JournalAccountGuard`).
    func currentDecision() -> JournalAccountGuard.Decision {
        let st = store.state
        stateLock.lock(); let current = currentUserRecordName; stateLock.unlock()
        return JournalAccountGuard.decide(bound: st.boundUserRecordName, current: current, unlinked: st.unlinked,
                                          localRemovalInProgress: st.localRemovalInProgress, localCopyRemoved: st.localCopyRemoved)
    }

    /// THE path that decides whether this device syncs right now: at launch,
    /// on every account change (engine event or system notification), on a
    /// retry, and after unlink / re-enable / removal. Serialised; a call that
    /// arrives mid-run queues one more run.
    func reconcile(trigger: String) async {
        stateLock.lock()
        if reconcileInFlight { reconcileQueued = true; stateLock.unlock(); return }
        reconcileInFlight = true
        stateLock.unlock()
        defer {
            stateLock.lock()
            reconcileInFlight = false
            let again = reconcileQueued
            reconcileQueued = false
            stateLock.unlock()
            if again { Task { await self.reconcile(trigger: "queued") } }
        }

        let st = store.state
        if st.localRemovalInProgress || st.unlinked {
            // Persisted refusals: no iCloud check needed, and no engine.
            goDormant(currentDecision(), trigger: trigger)
            return
        }
        await publish { $0.phase = "Checking iCloud account" }
        var me: String?
        var checkError: String?
        do { me = try await container.userRecordID().recordName } catch { checkError = error.localizedDescription }
        stateLock.lock(); currentUserRecordName = me; stateLock.unlock()
        if let me, store.state.boundUserRecordName == nil {
            store.update { $0.boundUserRecordName = me }
            log("Bound journal to iCloud user \(me)")
        }
        let decision = currentDecision()
        if let checkError, !decision.allowed {
            // Logged on the first failure and then every fifth retry, so the
            // diagnostics log stays readable while signed out.
            stateLock.lock(); let n = retryAttempts; stateLock.unlock()
            if n == 0 || n % 5 == 0 { log("iCloud check failed (\(checkError)); retry \(n)") }
        }
        guard decision.allowed else { goDormant(decision, trigger: trigger); return }
        await activate(trigger: trigger)
    }

    /// Drop the engine (if any), remember why, and retry only when the
    /// refusal can clear on its own.
    private func goDormant(_ decision: JournalAccountGuard.Decision, trigger: String) {
        guard case .refuse(let reason, let retry) = decision else { return }
        stateLock.lock()
        let hadEngine = engineInstance != nil
        engineInstance = nil
        dormantGeneration += 1
        retryPending = retry
        let changed = lastRefusal != reason
        lastRefusal = reason
        stateLock.unlock()
        if changed || hadEngine { log("PAUSED (\(trigger)): \(reason)\(hadEngine ? " — engine dropped" : "")") }
        Task { @MainActor in self.status.pausedReason = reason; self.status.phase = retry ? "Waiting for iCloud" : "Paused" }
        if retry { scheduleRetry() } else { stateLock.lock(); retryAttempts = 0; stateLock.unlock() }
        refreshCounts()
    }

    /// The guard allowed: build an engine from the last state saved while
    /// bound (or none, after a removal), queue the outbox and anything
    /// history holds, and run. Idempotent for an engine already running.
    private func activate(trigger: String) async {
        stateLock.lock()
        let wasDormant = engineInstance == nil
        let generation = dormantGeneration
        stateLock.unlock()
        if wasDormant, store.state.engineState != nil {
            // Seen twice on 2026-10-21: a push that arrives while no engine
            // exists (dormant, or not yet built at a push-triggered launch)
            // is consumed with nobody to act on it, and CloudKit's daemon
            // then answers an engine built from saved state with "no
            // changes" from its cache. Ask the server ourselves; if the zone
            // moved since our own last check, build the engine fresh.
            switch await catchUpCheck() {
            case .some(true):
                store.update { $0.engineState = nil }
                log("Catch-up: the zone changed while no engine was running; building a fresh engine to refetch it")
            case .some(false): break
            case .none: log("Catch-up check failed; engine built from saved state regardless")
            }
            // The check awaited: the state may have moved (unlink, removal,
            // account change) while it ran.
            stateLock.lock(); let moved = dormantGeneration != generation; stateLock.unlock()
            let decision = currentDecision()
            if moved || !decision.allowed {
                log("Activation abandoned (\(trigger)): the state changed during the catch-up check")
                if case .refuse = decision { goDormant(decision, trigger: trigger) }
                return
            }
        }
        stateLock.lock()
        if engineInstance == nil {
            var configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                           stateSerialization: store.state.engineState, delegate: self)
            configuration.automaticallySync = true
            engineInstance = CKSyncEngine(configuration)
        }
        retryPending = false
        retryAttempts = 0
        lastRefusal = nil
        stateLock.unlock()
        if wasDormant { log("Engine \(store.state.engineState == nil ? "built fresh" : "built from saved state") (\(trigger))") }
        await publish { $0.pausedReason = nil }

        queueToEngine(databaseChanges: [.saveZone(CKRecordZone(zoneID: JournalRecordMapping.zoneID))])
        let bootstrapped = tracker.bootstrapIfNeeded()
        if bootstrapped > 0 { log("Queued \(bootstrapped) existing record(s)") }
        let customs = tracker.bootstrapCustomsIfNeeded(customOwner: customOwner)
        if customs > 0 { log("Queued \(customs) custom row(s)") }
        let caughtUp = tracker.processHistory()
        if !caughtUp.isEmpty { log("Queued \(caughtUp.count) change(s) made while not syncing") }
        await scanLists()
        requeueOutbox()
        await publish { $0.phase = "Running" }
        refreshCounts()
    }

    /// Our own database-changes call against the token of our last check.
    /// Returns whether the Journal zone changed since (nil on error) and
    /// stores the new token. With no previous token it only sets a baseline.
    private func catchUpCheck() async -> Bool? {
        let previous = store.state.catchUpToken.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }
        let op = CKFetchDatabaseChangesOperation(previousServerChangeToken: previous)
        // Offline this would otherwise wait for the network indefinitely and
        // hold the activation open across whatever happens meanwhile.
        op.configuration.timeoutIntervalForRequest = 15
        op.configuration.timeoutIntervalForResource = 20
        var changed: [String] = []
        var deleted: [String] = []
        op.recordZoneWithIDChangedBlock = { changed.append($0.zoneName) }
        op.recordZoneWithIDWasDeletedBlock = { deleted.append($0.zoneName) }
        op.recordZoneWithIDWasPurgedBlock = { deleted.append($0.zoneName) }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool?, Never>) in
            op.fetchDatabaseChangesResultBlock = { result in
                switch result {
                case .success(let r):
                    let data = try? NSKeyedArchiver.archivedData(withRootObject: r.serverChangeToken, requiringSecureCoding: true)
                    self.store.update { $0.catchUpToken = data }
                    continuation.resume(returning: JournalCatchUp.mustRefetch(hadToken: previous != nil, changedZones: changed,
                                                                             deletedZones: deleted, zoneName: JournalRecordMapping.zoneID.zoneName))
                case .failure(let error):
                    self.log("Catch-up check error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
            self.container.privateCloudDatabase.add(op)
        }
    }

    // MARK: Stage E controls

    /// Unlink: persisted; the journal and its pending work stay, history keeps
    /// feeding the outbox, and nothing reaches an engine until re-enabled.
    func unlink() async {
        JournalLocalRemoval.unlink(store: store)
        await reconcile(trigger: "unlink")
    }

    /// Step 1 of a local removal, BEFORE any row is deleted. Synchronous and
    /// durable: the marker and the emptied outbox are on disk, and the engine
    /// is dropped, when this returns.
    func beginLocalRemoval(reason: String) {
        let ok = JournalLocalRemoval.begin(store: store, reason: reason)
        if !ok { logger.error("Local removal marker could NOT be written; relying on the in-memory engine drop only") }
        goDormant(currentDecision(), trigger: "local removal")
    }

    /// Step 2, after the cleanup. Leaves sync off until re-enabled.
    func finishLocalRemoval() {
        JournalLocalRemoval.finish(store: store, container: persistence)
        goDormant(currentDecision(), trigger: "local removal finished")
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

    /// A failed iCloud check (offline, signed out, or no account yet) is NOT
    /// an account change: the journal and pending work are kept and the check
    /// is retried on a 5/10/20/40/60 s backoff and as soon as the network
    /// path is satisfied, with no relaunch needed.
    private var retryTimerArmed = false
    private func scheduleRetry() {
        stateLock.lock()
        if retryTimerArmed { stateLock.unlock(); return }   // one timer at a time
        retryTimerArmed = true
        retryAttempts += 1
        let delay = JournalSyncStartRetry.delay(attempt: retryAttempts)
        stateLock.unlock()
        installPathMonitorIfNeeded()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            self.stateLock.lock(); self.retryTimerArmed = false; let pending = self.retryPending; self.stateLock.unlock()
            guard pending else { return }
            await self.reconcile(trigger: "retry")
        }
    }

    /// Retries at once when connectivity returns, instead of waiting out the backoff.
    private func installPathMonitorIfNeeded() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self, path.status == .satisfied else { return }
            self.stateLock.lock(); let pending = self.retryPending; self.stateLock.unlock()
            guard pending else { return }
            Task { await self.reconcile(trigger: "network path satisfied") }
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

    /// Lists are scanned only while syncing: after an erase the wiped library
    /// would otherwise read as "every list deleted".
    func scanLists() async {
        guard engine != nil, currentDecision().allowed else { return }
        let added = await MainActor.run { JournalSavedListSync.scan(store: store) }
        guard !added.isEmpty else { return }
        queueToEngine(zoneChanges: added.map(pendingChange))
        log("Queued \(added.count) list change(s)")
        refreshCounts()
    }

    /// The journal's owner changed: entries held back may now be eligible.
    func ownerChanged() {
        let added = tracker.requeueUnsent()
        if !added.isEmpty {
            queueToEngine(zoneChanges: added.map(pendingChange))
            log("Owner changed: queued \(added.count) entr\(added.count == 1 ? "y" : "ies") not yet uploaded")
        }
        Task { await scanLists() }
    }

    // MARK: JournalSendQueue

    func enqueueSave(_ recordName: String, recordType: String, ownerOnly: Bool) {
        let change = JournalSyncPendingChange(recordName: recordName, recordType: recordType, op: .save, ownerOnly: ownerOnly)
        store.update { JournalChangeTracker.merge([change], into: &$0.outbox) }
        queueToEngine(zoneChanges: [pendingChange(change)])
    }

    func enqueueDelete(_ recordName: String, recordType: String) {
        let change = JournalSyncPendingChange(recordName: recordName, recordType: recordType, op: .delete)
        store.update { JournalChangeTracker.merge([change], into: &$0.outbox) }
        queueToEngine(zoneChanges: [pendingChange(change)])
    }

    func removePendingSave(_ recordName: String) { dropPendingSave(recordName) }

    /// Local saves always reach the OUTBOX (durable, kept while paused or
    /// unlinked); they reach an engine only while one exists.
    func noteLocalChanges() {
        let added = tracker.processHistory()
        guard !added.isEmpty else { return }
        queueToEngine(zoneChanges: added.map(pendingChange))
        log("Queued \(added.count) local change(s)")
        refreshCounts()
    }

    private func requeueOutbox() {
        let outbox = store.state.outbox
        guard !outbox.isEmpty else { return }
        queueToEngine(zoneChanges: outbox.map(pendingChange))
    }

    /// No engine (dormant) means nothing is queued for transport; the outbox
    /// is the durable record and is requeued on activation.
    private func queueToEngine(zoneChanges: [CKSyncEngine.PendingRecordZoneChange] = [],
                               databaseChanges: [CKSyncEngine.PendingDatabaseChange] = []) {
        guard let engine else { return }
        if !zoneChanges.isEmpty { engine.state.add(pendingRecordZoneChanges: zoneChanges) }
        if !databaseChanges.isEmpty { engine.state.add(pendingDatabaseChanges: databaseChanges) }
    }

    private func pendingChange(_ c: JournalSyncPendingChange) -> CKSyncEngine.PendingRecordZoneChange {
        let id = CKRecord.ID(recordName: c.recordName, zoneID: JournalRecordMapping.zoneID)
        return c.op == .save ? .saveRecord(id) : .deleteRecord(id)
    }

    // MARK: Manual controls (diagnostics screen)

    func fetchNow() async {
        guard let engine, currentDecision().allowed else { log("Fetch refused: \(currentDecision().reason ?? "no engine")"); return }
        do { try await engine.fetchChanges() } catch { log("fetchChanges failed: \(error.localizedDescription)") }
    }

    func sendNow() async {
        guard let engine, currentDecision().allowed else { log("Send refused: \(currentDecision().reason ?? "no engine")"); return }
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
        stateLock.lock(); engineInstance = nil; stateLock.unlock()
        log("PAUSED: server zone deleted for a trial reset; engine dropped; uninstall this app next")
        await publish { $0.pausedReason = "Server zone deleted for a trial reset; uninstall this app next"; $0.phase = "Paused" }
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
        // A dropped instance may still finish an operation: nothing it reports
        // is applied, and its state is never saved.
        guard isCurrent(syncEngine) else {
            if case .accountChange = event { Task { await reconcile(trigger: "account change from a dropped engine") } }
            else { log("Event from a dropped engine ignored (\("\(event)".components(separatedBy: "(").first ?? ""))") }
            return
        }
        switch event {
        case .stateUpdate(let e):
            store.update { $0.engineState = e.stateSerialization }

        case .accountChange(let e):
            log("Engine account change: \(String(describing: e.changeType).components(separatedBy: "(").first ?? "")")
            Task { await reconcile(trigger: "engine account change") }

        case .fetchedDatabaseChanges(let e):
            // The account guard covers downloads too, not just uploads.
            let decision = currentDecision()
            guard decision.allowed else { log("Database changes ignored: \(decision.reason ?? "")"); return }
            log("Database changes: \(e.modifications.count) zone(s) changed \(e.modifications.map { $0.zoneID.zoneName }), \(e.deletions.count) deleted")
            for deletion in e.deletions where deletion.zoneID == JournalRecordMapping.zoneID {
                log("Server zone deleted (\(deletion.reason)). Local data kept; re-creating zone on next send.")
                queueToEngine(databaseChanges: [.saveZone(CKRecordZone(zoneID: JournalRecordMapping.zoneID))])
            }

        case .fetchedRecordZoneChanges(let e):
            let decision = currentDecision()
            guard decision.allowed else {
                log("Zone changes NOT imported (\(e.modifications.count) modified, \(e.deletions.count) deleted): \(decision.reason ?? "")")
                return
            }
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
            // Move our own baseline past what the engine has just fetched.
            _ = await catchUpCheck()
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
        guard isCurrent(syncEngine) else { return nil }
        // The guard that stops one account's journal entering another: no batch
        // unless the user we are talking to is the one the journal is bound to.
        let decision = currentDecision()
        guard decision.allowed else {
            log("Send refused: \(decision.reason ?? "")")
            return nil
        }
        let scope = context.options.scope
        var pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        // Sessions before their attachments, deletes last.
        let outbox = store.state.outbox
        let typeByName = Dictionary(outbox.map { ($0.recordName, $0.recordType) }, uniquingKeysWith: { a, _ in a })
        let ownerOnlyNames = Set(outbox.filter { $0.op == .save && $0.ownerOnly }.map(\.recordName))
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
            return self.record(for: recordID, type: typeByName[recordID.recordName], eligibility: eligibility,
                               ownerOnly: ownerOnlyNames.contains(recordID.recordName))
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
    private func record(for recordID: CKRecord.ID, type: String?, eligibility: Eligibility, ownerOnly: Bool = false) -> CKRecord? {
        guard let id = UUID(uuidString: recordID.recordName) else { return nil }
        let name = recordID.recordName
        var result: CKRecord?
        var ineligible = false
        importContext.performAndWait {
            let entities = type.map { [$0] } ?? [JournalSyncRecordType.session, JournalSyncRecordType.attachment,
                                                 JournalSyncRecordType.userInstrument, JournalSyncRecordType.userActivity,
                                                 JournalSyncRecordType.instrument]
            guard let object = entities.lazy.compactMap({ self.importer.freshObject(entity: $0, id: id) }).first else { return }
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
            let base = store.state.lastKnownRecords[name].flatMap(JournalSyncStateStore.recordFromSystemFields)
            if object.entity.name == JournalSyncRecordType.attachment {
                // The file travels only when it is new to the server or its
                // content changed; a metadata edit sends the record alone.
                var localHash: String?
                if let url = AttachmentPathResolver.resolve(object.value(forKey: "fileURL") as? String),
                   let cached = JournalAssetHash.cachedHash(of: url, cache: store.state.fileStampCache[name]) {
                    localHash = cached.hash
                    store.update { $0.fileStampCache[name] = cached.entry }
                }
                let include = JournalAssetPolicy.includeAsset(hasServerCopy: base != nil,
                                                              serverHash: store.state.assetHashes[name], localHash: localHash)
                result = JournalRecordMapping.record(for: object, base: base, includeAsset: include, fileHash: localHash)
                if include, result?[JournalRecordMapping.assetKey] == nil {
                    log("Attachment \(name) sent without its file (not found locally)")
                }
            } else {
                result = JournalRecordMapping.record(for: object, base: base, ownerOnly: ownerOnly)
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
        var uploads = 0
        var withoutMedia = 0
        for record in e.savedRecords {
            sent += 1
            let name = record.recordID.recordName
            if record.recordType == JournalSyncRecordType.attachment {
                if let hash = record[JournalRecordMapping.fileHashKey] as? String,
                   let asset = record[JournalRecordMapping.assetKey] as? CKAsset, let url = asset.fileURL {
                    uploads += 1
                    bytes += JournalAssetHash.stamp(of: url)?.size ?? 0
                    store.update { $0.assetHashes[name] = hash }
                } else {
                    withoutMedia += 1
                }
            }
            store.update {
                $0.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record)
                $0.outbox.removeAll { $0.recordName == name && $0.op == .save }
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
        store.update { $0.recordsSent += sent; $0.bytesSent += bytes; $0.assetUploads += uploads; $0.attachmentRecordsSentWithoutMedia += withoutMedia }
        if sent > 0 { log("Sent \(sent) record(s); \(uploads) media upload(s), \(bytes) bytes; \(withoutMedia) attachment record(s) metadata only") }
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
            if resend { queueToEngine(zoneChanges: [.saveRecord(record.recordID)]) }
        case .zoneNotFound:
            queueToEngine(zoneChanges: [.saveRecord(record.recordID)],
                          databaseChanges: [.saveZone(CKRecordZone(zoneID: JournalRecordMapping.zoneID))])
            log("Zone missing; re-creating and resending \(name)")
        case .unknownItem:
            // The server no longer has it: resend as a new record.
            store.update { $0.lastKnownRecords.removeValue(forKey: name) }
            queueToEngine(zoneChanges: [.saveRecord(record.recordID)])
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
        engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
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
        // Before any engine exists: a local removal the previous run did not
        // finish is completed here, so nothing it deleted can be queued.
        _ = JournalLocalRemoval.recoverIfInterrupted(store: store, container: persistence) {
            AttachmentStore.wipeDocumentsAttachmentsForFactoryReset()
        }
        let ownership = JournalOwnershipCoordinator(store: store, persistence: persistence, auth: auth)
        self.ownership = ownership
        makeEngine(persistence: persistence, store: store)
        // Finishes an interrupted adoption; a new adoption still waits for the
        // first complete fetch.
        ownership.evaluate(reason: "launch")
    }

    // MARK: Stage E

    /// Bracket of the production erase (`LocalFactoryReset.perform`, SYNCTEST
    /// only) and of the diagnostics control. Synchronous and durable before
    /// the first row is deleted.
    func beginLocalRemoval(reason: String) {
        guard let store else { return }
        if let engine { engine.beginLocalRemoval(reason: reason) } else { JournalLocalRemoval.begin(store: store, reason: reason) }
    }

    func finishLocalRemoval() {
        guard let store, let persistence else { return }
        if let engine { engine.finishLocalRemoval() } else { JournalLocalRemoval.finish(store: store, container: persistence) }
    }

    func unlink() async { await engine?.unlink() }

    /// Re-enable after an unlink or a removal. The JournalSyncEngine object is
    /// rebuilt: after an erase the install key (K2) and the import context
    /// are stale, and a removed copy needs a fresh CKSyncEngine anyway.
    func reenable() {
        guard let store, let persistence else { return }
        JournalLocalRemoval.reenable(store: store)
        makeEngine(persistence: persistence, store: store)
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

    /// Diagnostic for the interrupted-removal case: begins a removal, deletes
    /// the journal rows the way an erase would (tracked history, no finish),
    /// then exits. The next launch must recover and send no deletions.
    func simulateInterruptedLocalRemoval() {
        guard let persistence else { return }
        beginLocalRemoval(reason: "simulated interruption")
        let ctx = persistence.viewContext
        for entity in [JournalSyncRecordType.attachment, JournalSyncRecordType.session] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            for row in (try? ctx.fetch(request)) ?? [] { ctx.delete(row) }
        }
        try? ctx.save()
        store?.log("Simulated interruption: journal rows deleted, exiting before finish")
        exit(0)
    }
}
#endif
