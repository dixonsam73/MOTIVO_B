//
//  JournalSyncEngine.swift
//  MOTIVO — private iCloud sync. Compiled in every configuration; nothing
//  here runs until the person turns sync on (see JournalSyncCoordinator).
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

import Foundation
import CloudKit
import CoreData
import Network
import os
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
/// A little background time, so a send started as the app leaves the
/// foreground can finish. Ended by the caller or by the system's expiry.
@MainActor
final class JournalBackgroundTask {
    private var id: UIBackgroundTaskIdentifier = .invalid
    static func begin(_ name: String) -> JournalBackgroundTask {
        let task = JournalBackgroundTask()
        task.id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak task] in
            Task { @MainActor in task?.end() }
        }
        return task
    }
    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
#endif

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
    /// Stage J: media transfers are held right now (and why).
    @Published var mediaGated = false
    @Published var mediaHold: JournalMediaGate.Hold = .none
    /// "Media waiting for Wi-Fi: 2 to send (35 MB), 1 to receive", or nil.
    @Published var mediaWaiting: String?
    /// iCloud storage full: the current episode and the person-facing line.
    @Published var storageFull: JournalStorageFull.Episode?
    @Published var storageFullSummary: String?
    /// The network path is satisfied (false = offline, as iOS reports it).
    @Published var online = true
    /// The first complete fetch, while it runs.
    @Published var restoreProgress: JournalRestoreProgress?
    /// The last transient send failure since the last accepted send.
    @Published var lastTransientFailure: String?
    /// What the Profile screen shows: derived from the state file and the
    /// facts above by `JournalSyncStatusSummary` on every refresh.
    @Published var summary = JournalSyncStatusSummary(kind: .off, headline: "Off")
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
    /// Live facts for the status summary, guarded by `stateLock`: the last
    /// path report, the first fetch's progress and the last transient send
    /// failure. Status only; no rule reads them.
    private var onlineValue = true
    private var restoreValue: JournalRestoreProgress?
    private var transientFailureValue: String?
    /// Stage I: the Scores library's metadata scan debounce.
    private var scoreScanScheduled = false
    private var backgroundObserver: NSObjectProtocol?
    // Stage J: media over mobile data (JournalTransferPolicy).
    /// What the path monitor last reported: cellular-only, expensive, constrained.
    private var pathLink = JournalMediaGate.Link()
    private var mediaHoldValue: JournalMediaGate.Hold = .none
    private var mediaGatedValue: Bool { mediaHoldValue.holds }
    private var manualSendScheduled = false
    /// C-174: one `sendChanges` in flight; a request meanwhile runs once after it.
    private var sendGate = JournalSendGate()
    private var catchUpSerial = JournalCatchUpSerial()
    /// Stage J: while media is held the engine does not sync automatically, and
    /// a silent push is best effort (device, 2026-11-03: the iPad's four sends
    /// reached the iPhone eight minutes later, with the first push). While the
    /// app is active this looks for changes itself, as the engine does when it
    /// syncs automatically (about every 80 s in the logs).
    private var heldPollTask: Task<Void, Never>?
    /// Stage J: a rebuilt engine may inherit a save whose file the dropped
    /// engine's batch already finished uploading in CloudKit's daemon, which
    /// never tells this instance (device, 2026-11-03: a 132 MB video begun on
    /// Wi-Fi survived the cut to mobile data, was on the server by 12:08, and
    /// the new engine uploaded it again before the server rejected the save).
    /// Before its first batch the new engine asks the server which of those
    /// files it already holds, so a matching file is not sent twice.
    private var probeServerFilesBeforeFirstBatch = false
    static let heldPollInterval: UInt64 = 75_000_000_000
    /// Diagnostics only: until this time every send is refused as if the
    /// server had answered quotaExceeded; nothing reaches the server.
    private var quotaSimulationUntil: Date?
    /// B2: the outbox revision of each save as the batch was built.
    private var sentRevisions: [String: Int] = [:]
    /// R1: the removal marker could not be written; transport stays off for
    /// this process whatever the account says (the cleanup was not started).
    private var removalMarkerFailed = false
    /// R2: held while a record family is applied and while a removal begins,
    /// so a removal never lands between a family's guard and its mutation.
    private let importLock = NSLock()
    private var preferenceObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    /// While media is held the engine is built without automatic sync: the
    /// app sends on its own schedule and fetches records itself.
    var mediaGated: Bool { stateLock.lock(); defer { stateLock.unlock() }; return mediaGatedValue }
    var mediaHold: JournalMediaGate.Hold { stateLock.lock(); defer { stateLock.unlock() }; return mediaHoldValue }

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
        importer.viewerScope = { [weak self] in self?.viewerScope ?? "unknown" }
    }

    /// Stage F: favourites are keyed by the viewer; read on the main actor
    /// before each fetch and send cycle.
    private var viewerScopeValue = "unknown"
    private var viewerScope: String { stateLock.lock(); defer { stateLock.unlock() }; return viewerScopeValue }
    /// Stage H: the scopes the Profile screen presents (location under the
    /// backend id, avatar under the owner key), read with the viewer scope.
    private var profileScopeValue = JournalProfileScope.local
    var profileScope: JournalProfileScope { stateLock.lock(); defer { stateLock.unlock() }; return profileScopeValue }
    private func refreshViewerScope() async {
        let (scope, profile) = await MainActor.run {
            (JournalMetadataCodec.viewerScope(currentUserID: PersistenceController.shared.currentUserID),
             JournalProfileScope(locationUserID: JournalSyncCoordinator.shared.auth?.backendUserID,
                                 avatarUserID: PersistenceController.shared.currentUserID))
        }
        stateLock.lock(); viewerScopeValue = scope; profileScopeValue = profile; stateLock.unlock()
    }

    deinit {
        heldPollTask?.cancel()
        for o in [saveObserver, stampObserver, accountObserver, listObserver, backgroundObserver, preferenceObserver, foregroundObserver].compactMap({ $0 }) {
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
            // Stage H: location and avatar write points (ProfileStore).
            JournalProfileMirror.onChange = { [weak self] event in
                guard let self else { return }
                switch event {
                case .avatarRemoved: self.store.update { $0.avatarRemovedAt = Date() }
                case .primaryChosen: self.store.update { $0.profilePrimaryChosen = true }
                case .changed: break
                }
                self.scheduleProfileScan()
            }
            // Stage I: the Scores library's write points. Metadata after a short
            // pause. A reading position is saved locally on every page turn but
            // shared only at an explicit boundary: the viewer's dismissal or the
            // app going to the background (Samuel, 2026-10-26: no idle publishing,
            // so a page someone is sitting on never reaches the other device
            // until they leave it). The latest boundary wins; reopening reads
            // the latest synced page; an open viewer is never moved.
            JournalScoreMirror.onChange = { [weak self] change in
                guard let self else { return }
                switch change {
                case .library: self.scheduleScoreScan()
                case .position: break
                }
            }
            JournalScoreMirror.onViewerClosed = { [weak self] id in
                guard let self else { return }
                Task { await self.scanScores(reason: "viewer dismissed", positions: true, force: [id]) }
            }
            #if canImport(UIKit)
            backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
                guard let self else { return }
                Task {
                    // The app is about to be suspended: without background time
                    // the queued position only leaves at the next foreground
                    // (1861 on device: queued, not sent; the other device opened
                    // on its own page). Ask iOS for the seconds a send needs.
                    let open = await MainActor.run { ScoreLibraryStore.shared.openViewerID }
                    let task = await MainActor.run { JournalBackgroundTask.begin("score position") }
                    await self.scanScores(reason: "background", positions: true, force: open.map { [$0] } ?? [])
                    if open != nil, self.engine != nil, self.currentDecision().allowed {
                        if await self.performSend(userDriven: true, trigger: "background") { self.log("Background send finished") }
                    }
                    await MainActor.run { task.end() }
                }
            }
            // Stage J: media over mobile data. The path is watched from the
            // start (not only while a failed account check retries), the toggle
            // re-evaluates the gate, and a foreground while the app drives its
            // own fetches looks for changes the engine would otherwise fetch.
            installPathMonitorIfNeeded()
            preferenceObserver = NotificationCenter.default.addObserver(forName: JournalMediaPreference.changedNotification, object: nil, queue: nil) { [weak self] _ in
                Task { await self?.recomputeGate(trigger: "mobile data option changed") }
            }
            foregroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
                Task { await self?.manualRefresh(trigger: "foreground") }
            }
            heldPollTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: JournalSyncEngine.heldPollInterval)
                    guard let self, !Task.isCancelled, self.engine != nil else { continue }
                    let active = await MainActor.run { UIApplication.shared.applicationState == .active }
                    guard active else { continue }
                    await self.manualRefresh(trigger: "poll")
                }
            }
            #endif
        }
        stateLock.lock()
        mediaHoldValue = JournalMediaGate.hold(link: pathLink, allowMobileData: JournalMediaPreference.allowsMobileData())
        stateLock.unlock()
        await reconcile(trigger: "launch")
    }

    /// The current engine instance, or nil while dormant.
    var engine: CKSyncEngine? { stateLock.lock(); defer { stateLock.unlock() }; return engineInstance }

    /// Test seam: an engine that was never started has no iCloud user; tests
    /// of the apply paths assume the bound one so the account guard allows.
    func assumeCurrentUserForTesting(_ recordName: String?) {
        stateLock.lock(); currentUserRecordName = recordName; stateLock.unlock()
    }

    private func isCurrent(_ e: CKSyncEngine) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return engineInstance === e
    }

    /// The one rule every data path asks (`JournalAccountGuard`).
    func currentDecision() -> JournalAccountGuard.Decision {
        let st = store.state
        stateLock.lock(); let current = currentUserRecordName; let markerFailed = removalMarkerFailed; stateLock.unlock()
        if markerFailed {
            return .refuse(reason: "A removal could not be recorded on this device; sync is off until the app is relaunched", retry: false)
        }
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
        // Before any import: the catch-up writes favourites under this scope
        // (seen 2026-10-21: a heart imported by the catch-up at launch landed
        // under the placeholder scope and never showed).
        await refreshViewerScope()
        if wasDormant, store.state.engineState != nil {
            // Seen twice on 2026-10-21: a push that arrives while no engine
            // exists (dormant, or not yet built at a push-triggered launch)
            // is consumed with nobody to act on it, and CloudKit's daemon
            // then answers an engine built from saved state with "no
            // changes" from its cache. Ask the server ourselves; if the zone
            // moved since our own last check, import the delta with the app's
            // own zone token (stage G) and keep the engine's saved state. A
            // fresh engine is the fallback, with its reason logged.
            switch await catchUpCheck() {
            case .some(true):
                let ok = await deltaCatchUp(reason: "the zone changed while no engine was running")
                if !ok {
                    store.update { $0.engineState = nil; $0.catchUpZoneToken = nil }
                    log("Full recovery: the delta catch-up could not run (\(store.state.lastCatchUp ?? "")); building a fresh engine and reading the whole zone")
                }
            case .some(false):
                if store.state.catchUpZoneToken == nil {
                    // One-time: establish the zone token with a records-only pass.
                    _ = await deltaCatchUp(reason: "establishing the zone token")
                }
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
            // C-149: the engine never fetches. Its fetch brings every changed
            // record with its asset (104 MB of files this device already held,
            // on mobile data, 2026-11-03), so the app's records-only catch-up
            // is the only fetch and the engine only sends.
            configuration.automaticallySync = false
            engineInstance = CKSyncEngine(configuration)
            probeServerFilesBeforeFirstBatch = store.state.engineState != nil
        }
        let gated = mediaGatedValue
        let hold = mediaHoldValue
        retryPending = false
        retryAttempts = 0
        lastRefusal = nil
        stateLock.unlock()
        if wasDormant { log("Engine \(store.state.engineState == nil ? "built fresh" : "built from saved state") (\(trigger)); app-driven fetch\(gated ? ", \(hold.reason ?? "")" : "")") }
        await publish { $0.pausedReason = nil }

        let bootstrapped = tracker.bootstrapIfNeeded()
        if bootstrapped > 0 { log("Queued \(bootstrapped) existing record(s)") }
        let customs = tracker.bootstrapCustomsIfNeeded(customOwner: customOwner)
        if customs > 0 { log("Queued \(customs) custom row(s)") }
        let caughtUp = tracker.processHistory()
        if !caughtUp.isEmpty { log("Queued \(caughtUp.count) change(s) made while not syncing") }
        await refreshViewerScope()
        runMetadataMigrationIfNeeded()
        runFileNameTitlePassIfNeeded()
        runMetaTransitionIfNeeded()
        await scanLists()
        scanProfile(reason: "activation")
        await scanSettings()
        // Positions only at the transition (the pre-existing last-read pages,
        // once); afterwards they leave only at a dismissal or backgrounding.
        await scanScores(reason: "activation", positions: !store.state.scoreScanDone)
        requeueOutbox()
        // H5: queued after the reconcile above, so the send it schedules cannot
        // carry a restored pending change the outbox no longer holds.
        queueToEngine(databaseChanges: [.saveZone(CKRecordZone(zoneID: JournalRecordMapping.zoneID))])
        ensureAppSubscription()
        if store.state.catchUpZoneToken == nil {
            // A fresh state (first link, re-enable, recovery): the whole zone,
            // records only, then the files that are new here.
            _ = await deltaCatchUp(reason: "first fetch")
        } else if !gated, !store.state.awaitingMedia.isEmpty {
            await releaseHeldMedia()
        }
        scheduleManualSend(userDriven: true)
        await publish { $0.phase = "Running" }
        refreshCounts()
    }

    // MARK: Stage J: media over mobile data

    /// Re-evaluates the hold from the last path report and the option. The
    /// engine is not rebuilt (C-149): from allowed to held, the builder leaves
    /// files out and the catch-up holds records whose file is new from now on;
    /// from held to allowed, what waited is released and a send asked for. A
    /// change of reason alone (Wi-Fi only → Low Data Mode) is a status change.
    func recomputeGate(trigger: String) async {
        let allow = JournalMediaPreference.allowsMobileData()
        stateLock.lock()
        let previous = mediaHoldValue
        let next = JournalMediaGate.hold(link: pathLink, allowMobileData: allow)
        mediaHoldValue = next
        stateLock.unlock()
        guard previous != next else { return }
        log("Media transfers now \(next.reason ?? "allowed on this link") (\(trigger))")
        if !next.holds { store.update { $0.mediaWaitingUpload.removeAll() } }
        await publish { $0.mediaGated = next.holds; $0.mediaHold = next }
        refreshCounts()
        guard JournalMediaGate.releaseNeeded(from: previous, to: next), engine != nil, currentDecision().allowed else { return }
        await releaseHeldMedia()
        scheduleManualSend()
    }

    /// The app's own records-only fetch, then a send. Called from a push, the
    /// foreground, the poll and the diagnostics.
    func manualRefresh(trigger: String) async {
        guard engine != nil, currentDecision().allowed else { return }
        _ = await deltaCatchUp(reason: trigger)
        scheduleManualSend(userDriven: trigger == "foreground")
    }

    /// The app's own silent push landed. Returns whether the app acted on it
    /// (the engine acts for itself while it syncs automatically).
    func pushReceived() async -> Bool {
        guard engine != nil else { return false }
        #if canImport(UIKit)
        let task = await MainActor.run { JournalBackgroundTask.begin("push") }
        defer { Task { @MainActor in task.end() } }
        #endif
        await manualRefresh(trigger: "push")
        return true
    }

    /// One send per burst: the app asks the engine to send itself. A
    /// user-driven burst (a local change, the foreground, activation) may
    /// retry sooner while iCloud storage is full (`JournalStorageFull`).
    private func scheduleManualSend(userDriven: Bool = false) {
        stateLock.lock()
        guard !manualSendScheduled else { stateLock.unlock(); return }
        manualSendScheduled = true
        stateLock.unlock()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            self.stateLock.lock(); self.manualSendScheduled = false; self.stateLock.unlock()
            await self.performSend(userDriven: userDriven, trigger: userDriven ? "local change, foreground or activation" : "poll or push")
        }
    }

    /// THE send. While iCloud storage is full the attempt waits for its
    /// cadence (`JournalStorageFull.retryDue`: 2, 4, 8, then 15 minutes after
    /// each refusal, the floor for a user-driven trigger), then re-adds the
    /// outbox the engine dropped and sends it once, in the builder's order.
    /// Returns whether a send was attempted.
    @discardableResult
    func performSend(userDriven: Bool, bypassCadence: Bool = false, trigger: String = "unspecified") async -> Bool {
        guard let engine, currentDecision().allowed else { return false }
        let asked = Date()
        stateLock.lock()
        let mayRun = sendGate.enter(now: asked)
        let flightBegan = sendGate.inFlightSince
        let keptSoFar = sendGate.keptDuringFlight
        stateLock.unlock()
        guard mayRun else {
            // C-190, observation only: the request is kept exactly as before.
            let outbox = store.state.outbox
            JournalDeferredSend.record(JournalDeferredSend(
                trigger: trigger, activeFor: asked.timeIntervalSince(flightBegan ?? asked), ordinal: keptSoFar, outbox: outbox.count,
                attachmentsInOutbox: outbox.filter { $0.recordType == JournalSyncRecordType.attachment && $0.op == .save }.count), in: store)
            logger.notice("send request kept: \(trigger, privacy: .public)")
            return false
        }
        defer {
            stateLock.lock()
            let kept = sendGate.keptDuringFlight
            let again = sendGate.leave()
            stateLock.unlock()
            if again {
                log(JournalDeferredSend.ranText(kept: kept, flightLasted: Date().timeIntervalSince(asked)))
                Task { await self.performSend(userDriven: userDriven, bypassCadence: bypassCadence, trigger: "kept request") }
            }
        }
        if let episode = store.state.storageFull {
            let outbox = store.state.outbox
            if outbox.isEmpty && !episode.zoneSaveFailed {
                endStorageFull(sent: 0, reason: "nothing left to send")
            } else {
                guard bypassCadence || JournalStorageFull.retryDue(episode, now: Date(), userDriven: userDriven) else { return false }
                // The engine forgot the refused changes; the outbox did not.
                engine.state.add(pendingRecordZoneChanges: outbox.map(pendingChange))
                if episode.zoneSaveFailed { engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: JournalRecordMapping.zoneID))]) }
            }
        }
        stateLock.lock(); let simulation = quotaSimulationUntil; stateLock.unlock()
        if JournalStorageFull.simulationActive(until: simulation, now: Date()) {
            simulateStorageFullRefusal(engine)
            return true
        }
        do { try await engine.sendChanges() } catch {
            // A refused batch is reported per record in handleSent, once per
            // episode; the operation's own error adds nothing to the log.
            let code = (error as? CKError)?.code
            if store.state.storageFull != nil, code == .quotaExceeded || code == .partialFailure { return true }
            log("Send failed: \(error.localizedDescription); retried at the next change, push, poll or foreground")
        }
        return true
    }

    // MARK: iCloud storage full (JournalStorageFull)

    /// Saves (and possibly the zone) refused for lack of iCloud storage. The
    /// outbox keeps every change; the engine has dropped them; the next
    /// attempt on the cadence re-adds and sends them. Logged once per episode;
    /// later refusals are counted in the episode the diagnostics show.
    private func noteStorageFull(records: [String], zone: Bool, simulated: Bool) {
        let (episode, began) = JournalStorageFull.noting(failureAt: Date(), zone: zone, simulated: simulated, in: store.state.storageFull)
        store.update { $0.storageFull = episode; if began { $0.storageFullEpisodes += 1 } }
        if began {
            let waiting = store.state.outbox.count
            log("iCloud storage is full\(simulated ? " (simulated)" : ""): \(records.count) save(s)\(zone ? " and the zone" : "") refused; \(waiting) change(s) kept waiting, nothing removed; retried on a change, push, poll or foreground at most every few minutes (further refusals are counted, not logged)")
        }
        refreshCounts()
    }

    private func endStorageFull(sent: Int, reason: String) {
        guard let episode = store.state.storageFull else { return }
        store.update { $0.storageFull = nil }
        let left = store.state.outbox.count
        log("iCloud storage available again after \(episode.attempts) refused attempt(s)\(episode.simulated ? " (simulated)" : ""): \(reason); \(sent) record(s) sent\(left > 0 ? ", \(left) change(s) still pending go with the next send" : "")")
        refreshCounts()
    }

    /// Diagnostics only: exactly what a real refusal does to the app — the
    /// engine's pending saves (and a pending zone save) are dropped the way
    /// CKSyncEngine drops a non-retryable failure, and the failure handler
    /// runs. Nothing is sent.
    private func simulateStorageFullRefusal(_ engine: CKSyncEngine) {
        let saves = engine.state.pendingRecordZoneChanges.filter { if case .saveRecord = $0 { return true }; return false }
        let names = saves.compactMap { change -> String? in
            if case .saveRecord(let id) = change { return id.recordName }
            return nil
        }
        let zonePending = engine.state.pendingDatabaseChanges.contains { if case .saveZone = $0 { return true }; return false }
        guard !names.isEmpty || zonePending else { return }
        engine.state.remove(pendingRecordZoneChanges: saves)
        if zonePending { engine.state.remove(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: JournalRecordMapping.zoneID))]) }
        noteStorageFull(records: names, zone: zonePending, simulated: true)
    }

    /// Diagnostics: refuse every send for a bounded period, then let the next
    /// due attempt go to the server for real (the recovery path).
    func simulateStorageFull(minutes: Int) {
        let until = Date().addingTimeInterval(TimeInterval(minutes) * 60)
        stateLock.lock(); quotaSimulationUntil = until; stateLock.unlock()
        log("Storage-full simulation on for \(minutes) min: every send is refused as quotaExceeded until \(until.formatted(date: .omitted, time: .standard)); nothing reaches the server meanwhile")
        scheduleManualSend(userDriven: true)
    }

    func endStorageFullSimulation() {
        stateLock.lock(); let was = quotaSimulationUntil; quotaSimulationUntil = nil; stateLock.unlock()
        if was != nil { log("Storage-full simulation ended; the next due attempt goes to the server") }
    }

    var storageFullSimulationUntil: Date? { stateLock.lock(); defer { stateLock.unlock() }; return quotaSimulationUntil }

    /// Upload side of the gate: a record that would carry a file stays in the
    /// outbox (not in the engine) while media is held. nil here drops
    /// the pending change from the engine only; `requeueOutbox` restores it.
    private func gateUpload(_ record: CKRecord?) -> CKRecord? {
        guard let record, mediaGated, let asset = record[JournalRecordMapping.assetKey] as? CKAsset, let url = asset.fileURL else { return record }
        let name = record.recordID.recordName
        let size = JournalAssetHash.stamp(of: url)?.size ?? 0
        let first = store.state.mediaWaitingUpload[name] == nil
        store.update { if first { $0.mediaUploadsHeld += 1 }; $0.mediaWaitingUpload[name] = size }
        if first { log("Upload of \(name.prefix(14))… (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))) held: \(mediaHold.reason ?? "")") }
        refreshCounts()
        return nil
    }

    /// Download side: records held by name while media waited are fetched
    /// with their files and imported as a fetched batch would be.
    func releaseHeldMedia() async {
        let names = store.state.awaitingMedia
        guard !names.isEmpty, !mediaGated, currentDecision().allowed else { return }
        stateLock.lock(); let generation = dormantGeneration; stateLock.unlock()
        let ids = names.map { CKRecord.ID(recordName: $0, zoneID: JournalRecordMapping.zoneID) }
        let fetch = CKFetchRecordsOperation(recordIDs: ids)
        fetch.configuration.timeoutIntervalForResource = 600
        var full: [CKRecord] = []
        var gone: [String] = []
        fetch.perRecordResultBlock = { id, result in
            switch result {
            case .success(let r): full.append(r)
            case .failure(let error): if (error as? CKError)?.code == .unknownItem { gone.append(id.recordName) }
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            fetch.fetchRecordsResultBlock = { _ in continuation.resume() }
            container.privateCloudDatabase.add(fetch)
        }
        await applyReleasedMedia(full: full, gone: gone, generation: generation)
    }

    /// The apply half of a media release: the fetched records with their
    /// files, then the holds they settle. Returns the names released.
    @discardableResult
    func applyReleasedMedia(full: [CKRecord], gone: [String], generation: Int) async -> Set<String> {
        func abandoned() -> Set<String> { log("Media release abandoned: sync stopped while the files were fetched; nothing imported"); return [] }
        // R6 (2026-11-03): a hold is released only for a record that is now
        // durably applied — an attachment row the store committed, a score or
        // avatar whose file hash the state file now records — or gone from
        // the server; anything else stays held and is tried again.
        guard let journal = applyFamily(generation, { importModifications(full.filter { $0.recordType == JournalSyncRecordType.attachment }) }) else { return abandoned() }
        guard applyFamily(generation, { importProfileRecords(full.filter { JournalSyncRecordType.profileTypes.contains($0.recordType) }) }) != nil else { return abandoned() }
        guard await importScoreRecords(full.filter { JournalSyncRecordType.scoreTypes.contains($0.recordType) }, generation: generation) else { return abandoned() }
        var applied = journal.applied
        let hashes = store.state.assetHashes
        for record in full where record.recordType != JournalSyncRecordType.attachment {
            let name = record.recordID.recordName
            let serverHash = record[JournalRecordMapping.fileHashKey] as? String ?? ""
            if !serverHash.isEmpty, hashes[name] == serverHash { applied.insert(name) }
        }
        let done = applied.union(gone)
        let notApplied = full.map(\.recordID.recordName).filter { !done.contains($0) }
        guard applyFamily(generation, { store.update { $0.awaitingMedia.removeAll { done.contains($0) } } }) != nil else { return abandoned() }
        log("Media released: \(applied.count) of \(full.count) record(s) applied with their files\(gone.isEmpty ? "" : ", \(gone.count) gone from the server")\(notApplied.isEmpty ? "" : "; \(notApplied.count) not applied, still held"); \(store.state.awaitingMedia.count) still waiting")
        refreshCounts()
        return done
    }

    /// The app's own database subscription, so a push reaches the app while
    /// the engine does not sync automatically. Saved once per install.
    private func ensureAppSubscription() {
        guard !store.state.appSubscriptionSaved else { return }
        let subscription = CKDatabaseSubscription(subscriptionID: "etudes-journal-app-wake")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        let op = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
        op.modifySubscriptionsResultBlock = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success: self.store.update { $0.appSubscriptionSaved = true }; self.log("App push subscription saved")
            case .failure(let error): self.log("App push subscription not saved: \(error.localizedDescription) (retried at the next activation)")
            }
        }
        container.privateCloudDatabase.add(op)
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

    /// Stage F, once: side-store values join their records with the rows'
    /// existing stamps. Idempotent; the flag is set last. The diagnostics
    /// screen can clear the flag to run it again.
    func runMetadataMigrationIfNeeded() {
        guard !store.state.metadataMigrationDone else { return }
        let outcome = JournalMetadataMigration.run(container: persistence, privacyMap: AttachmentPrivacy.currentMap(),
                                                   pagesMap: PDFSelectedPagesStore.load(), viewerScope: viewerScope) { name, type in
            // Stage G: attachment metadata lives on the meta record.
            let change = type == JournalSyncRecordType.attachment
                ? JournalSyncPendingChange(recordName: JournalSyncRecordType.metaName(for: name), recordType: JournalSyncRecordType.attachmentMeta,
                                           op: .save, metadataOnly: true)
                : JournalSyncPendingChange(recordName: name, recordType: type, op: .save, metadataOnly: true)
            self.store.update { JournalChangeTracker.merge([change], into: &$0) }
            self.queueToEngine(zoneChanges: [self.pendingChange(change)])
        }
        store.update { $0.metadataMigrationDone = true }
        log("Metadata migration: \(outcome.titles) title(s) moved to displayName, \(outcome.privacy) privacy choice(s), \(outcome.pages) page selection(s), \(outcome.saves) favourite(s) queued")
        refreshCounts()
    }

    /// C-176: once, after the title migration (also on installs that ran it
    /// before this build): file-named legacy recordings take their stem.
    func runFileNameTitlePassIfNeeded() {
        guard store.state.metadataMigrationDone, !store.state.fileNameTitlesAdopted else { return }
        let adopted = JournalMetadataMigration.adoptFileNameTitles(container: persistence) { name, _ in
            let change = JournalSyncPendingChange(recordName: JournalSyncRecordType.metaName(for: name), recordType: JournalSyncRecordType.attachmentMeta,
                                                  op: .save, metadataOnly: true)
            self.store.update { JournalChangeTracker.merge([change], into: &$0) }
            self.queueToEngine(zoneChanges: [self.pendingChange(change)])
        }
        store.update { $0.fileNameTitlesAdopted = true }
        if adopted > 0 { log("File-name titles: \(adopted) recording(s) named only by their file took the name as displayName") }
        refreshCounts()
    }

    /// Stage G, once per device: every attachment gets its meta record
    /// (small, no media), queued as metadata-only so a copy from the other
    /// device wins a tie and an older build's content record never does.
    func runMetaTransitionIfNeeded() {
        guard !store.state.metaTransitionDone else { return }
        var changes: [JournalSyncPendingChange] = []
        importContext.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: JournalSyncRecordType.attachment)
            for row in (try? importContext.fetch(request)) ?? [] {
                guard let id = row.value(forKey: "id") as? UUID else { continue }
                changes.append(.init(recordName: JournalSyncRecordType.metaName(for: id.uuidString),
                                     recordType: JournalSyncRecordType.attachmentMeta, op: .save, metadataOnly: true))
            }
        }
        store.update { st in
            JournalChangeTracker.merge(changes, into: &st)
            st.metaTransitionDone = true
        }
        queueToEngine(zoneChanges: changes.map(pendingChange))
        log("Metadata record transition: \(changes.count) attachment(s) queued their meta record (no media)")
        refreshCounts()
    }

    /// Stage G: fetch the zone's changes since the app's own zone token,
    /// without the asset field, import them through the importer, and fetch
    /// the file only for attachment records whose hash this device does not
    /// already hold. Returns false when only a fresh engine can recover
    /// (expired token, zone gone); the reason is in `lastCatchUp`.
    func deltaCatchUp(reason: String) async -> Bool {
        stateLock.lock()
        let runNow = catchUpSerial.begin()
        stateLock.unlock()
        guard runNow else { log("Catch-up (\(reason)) waits for the one in progress"); return true }
        let result = await deltaCatchUpBody(reason: reason)
        stateLock.lock()
        let again = catchUpSerial.end()
        stateLock.unlock()
        return again ? await deltaCatchUp(reason: "\(reason), queued") : result
    }

    /// B5: whether a fetch that awaited may still import. The dormant
    /// generation moves on every removal, unlink or account refusal.
    private func mayStillImport(_ generation: Int) -> Bool {
        stateLock.lock(); let same = dormantGeneration == generation; stateLock.unlock()
        return same && currentDecision().allowed
    }

    private func deltaCatchUpBody(reason: String) async -> Bool {
        stateLock.lock(); let generation = dormantGeneration; stateLock.unlock()
        let writeFailuresBefore = store.writeFailures
        let previous = store.state.catchUpZoneToken.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0)
        }
        let zone = JournalRecordMapping.zoneID
        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration(previousServerChangeToken: previous, resultsLimit: nil,
                                                                          desiredKeys: JournalRecordMapping.keysWithoutAsset)
        let op = CKFetchRecordZoneChangesOperation(recordZoneIDs: [zone], configurationsByRecordZoneID: [zone: config])
        op.configuration.timeoutIntervalForRequest = 30
        op.configuration.timeoutIntervalForResource = 120
        var modified: [CKRecord] = []
        var deleted: [(CKRecord.ID, CKRecord.RecordType)] = []
        var newToken: CKServerChangeToken?
        var failure: CKError?
        // The first complete fetch is the restoration: say how far it is.
        let restoring = !store.state.initialFetchComplete
        var progress = JournalRestoreProgress()
        if restoring { publishRestore(progress) }
        op.recordWasChangedBlock = { [weak self] _, result in
            if case .success(let r) = result {
                modified.append(r)
                if restoring {
                    progress.recordsFetched += 1
                    if progress.recordsFetched % 25 == 0 { self?.publishRestore(progress) }
                }
            }
        }
        op.recordWithIDWasDeletedBlock = { id, type in deleted.append((id, type)) }
        op.recordZoneChangeTokensUpdatedBlock = { _, token, _ in newToken = token }
        op.recordZoneFetchResultBlock = { _, result in
            switch result {
            case .success(let r): newToken = r.serverChangeToken
            case .failure(let error): failure = error as? CKError
            }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            op.fetchRecordZoneChangesResultBlock = { result in
                if case .failure(let error) = result, failure == nil { failure = error as? CKError }
                continuation.resume()
            }
            container.privateCloudDatabase.add(op)
        }
        if let failure {
            let text = "Delta catch-up failed: \(failure.localizedDescription)"
            store.update { $0.lastCatchUp = text }
            if restoring { publishRestore(nil) }
            log(text)
            refreshCounts()   // the status says "Last check failed" (C-183)
            switch JournalCatchUp.recovery(for: failure.code) {
            case .retryLater:
                return true
            case .rereadZone:
                // The one unavoidable full fetch: records only, files by need.
                store.update { $0.catchUpZoneToken = nil }
                log("Zone token expired; the whole zone is read again, records only")
                return previous == nil ? true : await deltaCatchUpBody(reason: "\(reason), whole zone")
            case .zoneGone:
                return false
            }
        }

        guard mayStillImport(generation) else {
            if restoring { publishRestore(nil) }
            log("Catch-up (\(reason)) abandoned: sync stopped while the zone was read; nothing imported, token kept"); return true
        }
        // The file only where it is needed.
        var assetsFetched = 0
        let library = await MainActor.run { ScoreLibraryStore.shared.snapshot() }
        let needing = modified.filter { record in
            if record.recordType == JournalSyncRecordType.score {
                // Stage I: the PDF only when this device has no file for the
                // item, or the server's hash differs from what it last knew.
                let name = record.recordID.recordName
                guard let parsed = JournalSyncRecordType.scoreRecord(fromName: name), let uuid = UUID(uuidString: parsed.id),
                      let item = library.items.first(where: { $0.id == uuid }) else { return true }
                let url = library.url(for: item)
                let exists = FileManager.default.fileExists(atPath: url.path)
                let serverHash = record[JournalRecordMapping.fileHashKey] as? String
                var localHash: String?
                if exists, let cached = JournalAssetHash.cachedHash(of: url, cache: store.state.fileStampCache[name]) {
                    localHash = cached.hash
                    store.update { $0.fileStampCache[name] = cached.entry }
                }
                let needs = JournalCatchUp.needsAsset(serverHash: serverHash, knownHash: store.state.assetHashes[name], fileExists: exists, localHash: localHash)
                if !needs, let serverHash, localHash == serverHash { store.update { $0.assetHashes[name] = serverHash } }
                return needs
            }
            if record.recordType == JournalSyncRecordType.profileAvatar {
                // Stage H: the avatar's file only when its hash is new here.
                let serverHash = record[JournalRecordMapping.fileHashKey] as? String ?? ""
                return !serverHash.isEmpty && store.state.assetHashes[JournalProfileSync.avatarName] != serverHash
            }
            guard record.recordType == JournalSyncRecordType.attachment else { return false }
            let name = record.recordID.recordName
            var exists = false
            var localHash: String?
            importContext.performAndWait {
                if let id = UUID(uuidString: name), let object = importer.fetch(entity: JournalSyncRecordType.attachment, id: id),
                   let url = AttachmentPathResolver.resolve(object.value(forKey: "fileURL") as? String) {
                    exists = FileManager.default.fileExists(atPath: url.path)
                    if exists, let cached = JournalAssetHash.cachedHash(of: url, cache: store.state.fileStampCache[name]) {
                        localHash = cached.hash
                        store.update { $0.fileStampCache[name] = cached.entry }
                    }
                }
            }
            let serverHash = record[JournalRecordMapping.fileHashKey] as? String
            let needs = JournalCatchUp.needsAsset(serverHash: serverHash, knownHash: store.state.assetHashes[name], fileExists: exists, localHash: localHash)
            if !needs, let serverHash, localHash == serverHash { store.update { $0.assetHashes[name] = serverHash } }
            return needs
        }.map(\.recordID)
        if restoring { progress.filesTotal = mediaGated ? 0 : needing.count; publishRestore(progress) }
        if !needing.isEmpty, mediaGated {
            // Stage J: the files are held; the records wait with them
            // (an attachment, score or avatar is never imported without its
            // file). Everything else in the batch is imported now.
            let names = needing.map(\.recordName)
            let heldSet = Set(names)
            let before = store.state.awaitingMedia.count
            store.update { s in
                s.awaitingMedia = JournalMediaHold.adding(names, to: s.awaitingMedia)
                s.mediaDownloadsHeld += s.awaitingMedia.count - before
            }
            modified.removeAll { heldSet.contains($0.recordID.recordName) }
            log("\(names.count) record(s) with media held (\(mediaHold.reason ?? "")): \(names.map { $0.prefix(14) })")
            refreshCounts()
        } else if !needing.isEmpty {
            let fetch = CKFetchRecordsOperation(recordIDs: needing)
            fetch.configuration.timeoutIntervalForResource = 600
            var full: [CKRecord.ID: CKRecord] = [:]
            fetch.perRecordResultBlock = { [weak self] id, result in
                if case .success(let r) = result { full[id] = r }
                if restoring { progress.filesFetched += 1; self?.publishRestore(progress) }
            }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                fetch.fetchRecordsResultBlock = { _ in continuation.resume() }
                container.privateCloudDatabase.add(fetch)
            }
            modified = modified.map { full[$0.recordID] ?? $0 }
            assetsFetched = full.count
            let unfetched = needing.filter { full[$0] == nil }.map(\.recordName)
            if !unfetched.isEmpty {
                // B6: a record whose file did not arrive is not imported
                // without it; it waits by name, like a record under the media
                // hold, and is fetched again with the next catch-up or release.
                let set = Set(unfetched)
                let before = store.state.awaitingMedia.count
                store.update { s in
                    s.awaitingMedia = JournalMediaHold.adding(unfetched, to: s.awaitingMedia)
                    s.mediaDownloadsHeld += s.awaitingMedia.count - before
                }
                modified.removeAll { set.contains($0.recordID.recordName) }
                log("Catch-up: \(unfetched.count) file(s) could not be fetched; their records are held by name and fetched again")
                refreshCounts()
            }
        }
        guard mayStillImport(generation) else {
            if restoring { publishRestore(nil) }
            log("Catch-up (\(reason)) abandoned: sync stopped while files were fetched; nothing imported, token kept"); return true
        }
        if restoring { progress.applying = true; publishRestore(progress) }
        _ = await applyFetchedBatch(modified: modified, deleted: deleted, newToken: newToken, assetsFetched: assetsFetched,
                                    generation: generation, reason: reason, writeFailuresBefore: writeFailuresBefore)
        if restoring { publishRestore(nil) }
        return true
    }

    /// Status only: where the first complete fetch is (nil = not running).
    private func publishRestore(_ progress: JournalRestoreProgress?) {
        stateLock.lock(); restoreValue = progress; stateLock.unlock()
        refreshCounts()
    }

    /// Test hook: runs before each record family is applied (R2).
    static var testBeforeFamily: ((String) -> Void)?

    /// The import half of a catch-up, after the fetches: every record family
    /// in order, the deletions, then the zone token. Returns whether the batch
    /// was applied in full (the token moved).
    func applyFetchedBatch(modified modifiedIn: [CKRecord], deleted: [(CKRecord.ID, CKRecord.RecordType)], newToken: CKServerChangeToken?,
                           assetsFetched: Int, generation: Int, reason: String, writeFailuresBefore: Int) async -> Bool {
        // C-183: however this batch ends (applied, incomplete, abandoned),
        // the status is derived again from what the state file now says.
        defer { refreshCounts() }
        var modified = modifiedIn
        // Import exactly as a fetched batch would be.
        let records = modified.filter { $0.recordType != JournalSyncRecordType.savedList && !JournalSyncRecordType.profileTypes.contains($0.recordType)
                                        && !JournalSyncRecordType.scoreTypes.contains($0.recordType) && !JournalSyncRecordType.settingsTypes.contains($0.recordType) }
        let lists = modified.filter { $0.recordType == JournalSyncRecordType.savedList }
        // R2 (2026-11-03): every family checks the lifecycle at its own
        // boundary — the synchronous ones under the import lock, the
        // main-actor ones inside their main-actor step (a removal begins on
        // the main actor, so the two cannot interleave) — and the token is
        // committed only if every family ran.
        func abandoned(_ family: String) -> Bool {
            log("Catch-up (\(reason)) abandoned before \(family): sync stopped while it ran; token kept")
            return false
        }
        Self.testBeforeFamily?("journal")
        guard let journalOK = applyFamily(generation, { !importModifications(records).saveFailed }) else { return abandoned("journal") }
        let importOK = journalOK
        Self.testBeforeFamily?("profile")
        guard applyFamily(generation, { importProfileRecords(modified.filter { JournalSyncRecordType.profileTypes.contains($0.recordType) }) }) != nil else { return abandoned("profile") }
        Self.testBeforeFamily?("lists")
        if !lists.isEmpty {
            let ran = await MainActor.run { () -> Bool in
                guard self.mayStillImport(generation) else { return false }
                _ = JournalSavedListSync.apply(lists, store: self.store); return true
            }
            guard ran else { return abandoned("lists") }
        }
        Self.testBeforeFamily?("scores")
        guard await importScoreRecords(modified.filter { JournalSyncRecordType.scoreTypes.contains($0.recordType) }, generation: generation) else { return abandoned("scores") }
        Self.testBeforeFamily?("settings")
        guard await importSettingsRecords(modified.filter { JournalSyncRecordType.settingsTypes.contains($0.recordType) }, generation: generation) else { return abandoned("settings") }
        Self.testBeforeFamily?("deletions")
        guard applyFamily(generation, { importDeletions(deleted) }) != nil else { return abandoned("deletions") }
        let listDeletions = deleted.filter { $0.1 == JournalSyncRecordType.savedList }.map(\.0.recordName)
        if !listDeletions.isEmpty {
            let ran = await MainActor.run { () -> Bool in
                guard self.mayStillImport(generation) else { return false }
                _ = JournalSavedListSync.applyDeletions(listDeletions, store: self.store); return true
            }
            guard ran else { return abandoned("list deletions") }
        }
        guard await applyScoreDeletions(deleted.filter { JournalSyncRecordType.scoreTypes.contains($0.1) }.map(\.0.recordName), generation: generation) else { return abandoned("score deletions") }
        guard applyFamily(generation, { forgetSettings(deleted.filter { JournalSyncRecordType.settingsTypes.contains($0.1) }.map(\.0.recordName)) }) != nil else { return abandoned("settings deletions") }
        guard await applyHeldSettings(generation: generation) else { return abandoned("held settings") }
        let summary = "Catch-up (\(reason)): \(modified.count) changed record(s), \(deleted.count) deletion(s), \(assetsFetched) file(s) fetched"
        let first = !store.state.initialFetchComplete
        // C-151: a profile typed before this fetch was provisional; a cloud
        // profile in the batch has already settled it (applyProfile clears the
        // mark), so a mark still set means the cloud holds none and the typed
        // clock stands.
        let provisionalStands = first && store.state.profileStampProvisional
        // H1/H3: a hold or a conflict entry that did not reach the state file,
        // or a Core Data save that rolled back, means part of this batch is
        // not applied; the zone token stays so the batch is fetched again
        // (every import is idempotent).
        Self.testBeforeFamily?("commit")
        let complete = importOK && store.writeFailures == writeFailuresBefore
        let committed = applyFamily(generation) {
            store.update { st in
                if complete, let newToken, let data = try? NSKeyedArchiver.archivedData(withRootObject: newToken, requiringSecureCoding: true) {
                    st.catchUpZoneToken = data
                }
                st.catchUpRecords += modified.count
                st.catchUpAssets += assetsFetched
                st.lastCatchUp = summary + (complete ? "" : " — incomplete, fetched again")
                if complete { st.initialFetchComplete = true; st.profileStampProvisional = false }
            }
        }
        guard committed != nil else { return abandoned("the token commit") }
        log(summary + (complete ? "" : " — incomplete (a write failed); zone token kept, fetched again"))
        if first, complete { log("First complete fetch finished" + (provisionalStands ? "; no cloud profile, so the profile typed here keeps its clock" : "")) }
        if complete, let fetchCycleCompleted { await MainActor.run { fetchCycleCompleted() } }
        // B6: files that could not be fetched (this round or earlier) are
        // tried again now that the link may be back.
        if !mediaGated, !store.state.awaitingMedia.isEmpty { await releaseHeldMedia() }
        return complete
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
    /// R1 (2026-11-03): returns whether the marker is on disk. When it is not,
    /// the caller must not delete anything; transport is stopped regardless
    /// (engine dropped, every decision refused) so nothing moves meanwhile.
    /// R2: taken under the import lock, so no record family is between its
    /// guard and its mutation when the marker lands.
    @discardableResult
    func beginLocalRemoval(reason: String) -> Bool {
        importLock.lock(); defer { importLock.unlock() }
        let ok = JournalLocalRemoval.begin(store: store, reason: reason)
        if !ok {
            logger.error("Local removal marker could NOT be written; the removal is refused and sync stays off until relaunch")
            stateLock.lock(); removalMarkerFailed = true; stateLock.unlock()
        }
        goDormant(currentDecision(), trigger: "local removal")
        return ok
    }

    /// R2: runs one synchronous record family under the import lock, or not
    /// at all once the lifecycle moved (removal, unlink, account refusal).
    private func applyFamily<T>(_ generation: Int, _ body: () -> T) -> T? {
        importLock.lock(); defer { importLock.unlock() }
        guard mayStillImport(generation) else { return nil }
        return body()
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
            // Stage H: the Profile row (name, primary instrument) has no history
            // tracking; a save that touched it is scanned.
            let touchedProfile = [NSInsertedObjectsKey, NSUpdatedObjectsKey].contains { key in
                ((note.userInfo?[key] as? Set<NSManagedObject>) ?? []).contains { $0.objectID.entity.name == JournalSyncRecordType.profile }
            }
            if touchedProfile { self.scheduleProfileScan() }
        }
    }

    // MARK: Stage H: profile scan

    private var profileScanScheduled = false
    /// One scan per burst: the editor writes the avatar twice (owner and local
    /// scope), a Profile close rewrites the location, and Profile commits the
    /// name on every 650 ms typing pause (on device 2026-10-26 one name edit
    /// went up as five records, one per pause); 3 s makes a burst one record.
    func scheduleProfileScan() {
        stateLock.lock()
        if profileScanScheduled { stateLock.unlock(); return }
        profileScanScheduled = true
        stateLock.unlock()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self else { return }
            self.stateLock.lock(); self.profileScanScheduled = false; self.stateLock.unlock()
            if JournalProfileMirror.editingHold {
                // A field is still being edited; the blur triggers the scan.
                self.scheduleProfileScan()
                return
            }
            await self.refreshViewerScope()
            self.scanProfile(reason: "write point")
        }
    }

    /// Runs in every state except a local removal: the outbox is durable and an
    /// edit made while paused or unlinked keeps its clock. Transport waits for
    /// an engine, as for everything else.
    func scanProfile(reason: String) {
        guard !store.state.localRemovalInProgress else { return }
        let scope = profileScope
        var added: [JournalSyncPendingChange] = []
        importContext.performAndWait { added = JournalProfileSync.scan(context: importContext, scope: scope, store: store) }
        guard !added.isEmpty else { return }
        queueToEngine(zoneChanges: added.map(pendingChange))
        log("Queued \(added.count) profile change(s) (\(reason)): \(added.map(\.recordName))")
        refreshCounts()
    }

    // MARK: Stage I: Scores library scan

    /// One scan per burst of metadata writes (rename, favourite, cover, add, delete).
    func scheduleScoreScan() {
        stateLock.lock()
        if scoreScanScheduled { stateLock.unlock(); return }
        scoreScanScheduled = true
        stateLock.unlock()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self else { return }
            self.stateLock.lock(); self.scoreScanScheduled = false; self.stateLock.unlock()
            await self.scanScores(reason: "write point", positions: false)
        }
    }

    /// Runs in every state except a local removal (the outbox is durable and
    /// an offline edit keeps its clock). A damaged index sends nothing.
    func scanScores(reason: String, positions: Bool, force: Set<UUID> = []) async {
        guard !store.state.localRemovalInProgress else { return }
        let snapshot = await MainActor.run { ScoreLibraryStore.shared.snapshot() }
        let added = JournalScoreSync.scan(snapshot: snapshot, store: store, positions: positions, force: force) { self.log($0) }
        guard !added.isEmpty else { return }
        queueToEngine(zoneChanges: added.map(pendingChange))
        log("Queued \(added.count) score change(s) (\(reason))")
        refreshCounts()
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
            guard let self else { return }
            let online = path.status == .satisfied
            self.stateLock.lock()
            let onlineChanged = self.onlineValue != online
            self.onlineValue = online
            self.stateLock.unlock()
            if onlineChanged { self.refreshCounts() }   // the status says "Offline" in plain words
            guard online else { return }
            // Stage J: the link decides whether media waits.
            let link = JournalMediaGate.link(path: path)
            self.stateLock.lock()
            let pending = self.retryPending
            let linkChanged = link != self.pathLink
            self.pathLink = link
            self.stateLock.unlock()
            if linkChanged {
                let description = "network path: \(link.cellularOnly ? "mobile data" : "Wi-Fi or wired")\(link.expensive ? (link.cellularOnly ? ", expensive" : ", expensive (hotspot)") : "")\(link.constrained ? ", Low Data Mode" : "")"
                Task { await self.recomputeGate(trigger: description) }
            }
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
                await self.scanSettings()
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

    /// Stage J: settings, list contexts and the instrument colour map. Runs in
    /// every state except a local removal (the outbox is durable; an edit made
    /// while paused or unlinked keeps its clock).
    func scanSettings() async {
        guard !store.state.localRemovalInProgress else { return }
        let added = await MainActor.run { JournalSettingsSync.scan(store: store) }
        guard !added.isEmpty else { return }
        queueToEngine(zoneChanges: added.map(pendingChange))
        log("Queued \(added.count) settings change(s): \(added.map { $0.recordName.prefix(22) })")
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
        store.update { JournalChangeTracker.merge([change], into: &$0) }
        queueToEngine(zoneChanges: [pendingChange(change)])
    }

    func enqueueDelete(_ recordName: String, recordType: String) {
        let change = JournalSyncPendingChange(recordName: recordName, recordType: recordType, op: .delete)
        store.update { JournalChangeTracker.merge([change], into: &$0) }
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
        // An engine restored from saved state brings its own pending list; a
        // change the outbox no longer holds (dropped by the relaunch catch-up)
        // must not go up again (JournalPendingReconcile).
        if let engine {
            var saves: [String] = []
            var deletes: [String] = []
            for change in engine.state.pendingRecordZoneChanges {
                switch change {
                case .saveRecord(let id): saves.append(id.recordName)
                case .deleteRecord(let id): deletes.append(id.recordName)
                @unknown default: break
                }
            }
            let stale = JournalPendingReconcile.stale(engineSaves: saves, engineDeletes: deletes, outbox: outbox)
            let removals: [CKSyncEngine.PendingRecordZoneChange] =
                stale.saves.map { .saveRecord(CKRecord.ID(recordName: $0, zoneID: JournalRecordMapping.zoneID)) }
                + stale.deletes.map { .deleteRecord(CKRecord.ID(recordName: $0, zoneID: JournalRecordMapping.zoneID)) }
            if !removals.isEmpty {
                engine.state.remove(pendingRecordZoneChanges: removals)
                log("Dropped \(removals.count) pending change(s) the engine restored but the outbox no longer holds")
            }
        }
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
        // Stage J: without automatic sync the app asks for the send itself.
        if !zoneChanges.isEmpty || !databaseChanges.isEmpty { scheduleManualSend(userDriven: true) }
    }

    private func pendingChange(_ c: JournalSyncPendingChange) -> CKSyncEngine.PendingRecordZoneChange {
        let id = CKRecord.ID(recordName: c.recordName, zoneID: JournalRecordMapping.zoneID)
        return c.op == .save ? .saveRecord(id) : .deleteRecord(id)
    }

    // MARK: Manual controls (diagnostics screen)

    /// Stage H: forget what was last exchanged and send the current profile and
    /// avatar again (clocks kept). Repeatable; nothing local is changed.
    func rerunProfileTransition() {
        store.update { st in
            st.profileFingerprint = nil
            st.assetHashes.removeValue(forKey: JournalProfileSync.avatarName)
            st.log.append(.init(at: Date(), text: "Profile transition re-run requested"))
        }
        scanProfile(reason: "re-run")
    }

    /// Stage J diagnostics: one scan now (after a file was removed from the test screen).
    func rerunScoreScan() {
        Task { await scanScores(reason: "diagnostics", positions: false) }
    }

    /// Stage I: forget what was exchanged for the library and send it again.
    func rerunScoreTransition() {
        JournalScoreSync.rerunTransition(store: store)
        Task { await scanScores(reason: "re-run", positions: true) }
    }

    /// One small fetch of the file hashes the server holds for records about
    /// to go up with a file. A record the server has (this device's own
    /// upload finished by the dropped engine) gets its hash recorded, and its
    /// system fields where this device had none, so the builder sends the
    /// record without the file; a differing hash still uploads.
    private func probeServerFiles(_ ids: [CKRecord.ID]) async {
        let op = CKFetchRecordsOperation(recordIDs: ids)
        op.desiredKeys = [JournalRecordMapping.fileHashKey]
        op.configuration.timeoutIntervalForRequest = 15
        op.configuration.timeoutIntervalForResource = 30
        var found: [CKRecord] = []
        op.perRecordResultBlock = { _, result in if case .success(let r) = result { found.append(r) } }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            op.fetchRecordsResultBlock = { _ in continuation.resume() }
            container.privateCloudDatabase.add(op)
        }
        guard !found.isEmpty else { return }
        store.update { s in
            for record in found {
                let name = record.recordID.recordName
                s.assetHashes[name] = record[JournalRecordMapping.fileHashKey] as? String ?? ""
                if s.lastKnownRecords[name] == nil { s.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record) }
            }
        }
        log("Probe after rebuild: the server already holds \(found.count) of \(ids.count) record(s) due to go up with a file; a file it has is not sent again")
    }

    func fetchNow() async {
        guard engine != nil, currentDecision().allowed else { log("Fetch refused: \(currentDecision().reason ?? "no engine")"); return }
        _ = await deltaCatchUp(reason: "manual fetch")
    }

    func sendNow() async {
        guard engine != nil, currentDecision().allowed else { log("Send refused: \(currentDecision().reason ?? "no engine")"); return }
        noteLocalChanges()
        // The diagnostics tap ignores the storage-full cadence: one attempt now, counted like any other.
        await performSend(userDriven: true, bypassCadence: true, trigger: "manual")
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
            // C-134: the engine's saved state moves only on fetches, so after a
            // relaunch it hands back this device's own recent sends, files
            // included. Nothing new in them: skip the import work and count
            // what was delivered.
            let known = store.state.lastKnownRecords
            var records: [CKRecord] = []
            var echoCount = 0
            var echoBytes: Int64 = 0
            for record in e.modifications.map(\.record) {
                if JournalEcho.isKnown(changeTag: record.recordChangeTag, storedSystemFields: known[record.recordID.recordName]) {
                    echoCount += 1
                    if let url = (record[JournalRecordMapping.assetKey] as? CKAsset)?.fileURL {
                        echoBytes += JournalAssetHash.stamp(of: url)?.size ?? 0
                        // The hash the server holds for this device's own file, so no
                        // later catch-up treats the file as new (C-148).
                        if let hash = record[JournalRecordMapping.fileHashKey] as? String, !hash.isEmpty {
                            store.update { $0.assetHashes[record.recordID.recordName] = hash }
                        }
                    }
                } else {
                    records.append(record)
                }
            }
            if echoCount > 0 {
                store.update { $0.echoRecords += echoCount; $0.echoAssetBytes += echoBytes; $0.assetBytesDownloaded += echoBytes }
                log("Own-write echo: \(echoCount) record(s) already held, skipped; \(echoBytes) asset bytes delivered with them")
            }
            importModifications(records.filter { $0.recordType != JournalSyncRecordType.savedList && !JournalSyncRecordType.profileTypes.contains($0.recordType)
                                                 && !JournalSyncRecordType.scoreTypes.contains($0.recordType) && !JournalSyncRecordType.settingsTypes.contains($0.recordType) })
            importProfileRecords(records.filter { JournalSyncRecordType.profileTypes.contains($0.recordType) })
            let lists = records.filter { $0.recordType == JournalSyncRecordType.savedList }
            if !lists.isEmpty {
                let n = await MainActor.run { JournalSavedListSync.apply(lists, store: store) }
                log("Imported \(n) list(s)")
            }
            await importScoreRecords(records.filter { JournalSyncRecordType.scoreTypes.contains($0.recordType) })
            await importSettingsRecords(records.filter { JournalSyncRecordType.settingsTypes.contains($0.recordType) })
            importDeletions(e.deletions.map { ($0.recordID, $0.recordType) })
            let listDeletions = e.deletions.filter { $0.recordType == JournalSyncRecordType.savedList }.map(\.recordID.recordName)
            if !listDeletions.isEmpty {
                let n = await MainActor.run { JournalSavedListSync.applyDeletions(listDeletions, store: store) }
                log("Applied \(n) list deletion(s)")
            }
            await applyScoreDeletions(e.deletions.filter { JournalSyncRecordType.scoreTypes.contains($0.recordType) }.map(\.recordID.recordName))
            forgetSettings(e.deletions.filter { JournalSyncRecordType.settingsTypes.contains($0.recordType) }.map(\.recordID.recordName))
            await applyHeldSettings()
            await publish { $0.lastFetchAt = Date() }

        case .sentRecordZoneChanges(let e):
            handleSent(e)
            await publish { $0.lastSendAt = Date() }

        case .sentDatabaseChanges(let e):
            if e.failedZoneSaves.contains(where: { JournalStorageFull.isStorageFull($0.error.code) }) {
                noteStorageFull(records: [], zone: true, simulated: false)
            } else if !e.failedZoneSaves.isEmpty {
                log("Zone save failed: \(e.failedZoneSaves.map { $0.error.localizedDescription })")
            } else if store.state.storageFull != nil, !e.savedZones.isEmpty {
                // The zone exists again; the episode ends only when no save waits.
                let savesLeft = store.state.outbox.filter { $0.op == .save }.count
                if JournalStorageFull.recovered(savedRecords: 0, savedZones: e.savedZones.count, deletedRecords: 0, quotaFailures: 0, savesStillPending: savesLeft) {
                    endStorageFull(sent: 0, reason: "the zone was saved and nothing else waits")
                } else {
                    store.update { $0.storageFull?.zoneSaveFailed = false }
                }
            }

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
            await refreshViewerScope()
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
        // B2: remember which revision of each save this batch carries.
        let revisions = Dictionary(outbox.filter { $0.op == .save }.map { ($0.recordName, $0.revision) }, uniquingKeysWith: { a, _ in a })
        stateLock.lock(); sentRevisions.merge(revisions) { _, new in new }; stateLock.unlock()
        let ownerOnlyNames = Set(outbox.filter { $0.op == .save && $0.ownerOnly }.map(\.recordName))
        let assetFreeNames = Set(outbox.filter { $0.op == .save && $0.assetFree }.map(\.recordName))
        stateLock.lock()
        let probe = probeServerFilesBeforeFirstBatch
        probeServerFilesBeforeFirstBatch = false
        stateLock.unlock()
        if probe {
            let ids = pending.compactMap { change -> CKRecord.ID? in
                guard case .saveRecord(let id) = change,
                      JournalAssetPolicy.carriesFile(recordType: typeByName[id.recordName]), !assetFreeNames.contains(id.recordName) else { return nil }
                return id
            }
            if !ids.isEmpty { await probeServerFiles(ids) }
        }
        pending.sort { a, b in rank(a, typeByName) < rank(b, typeByName) }
        let listNames = pending.compactMap { change -> String? in
            if case .saveRecord(let id) = change, typeByName[id.recordName] == JournalSyncRecordType.savedList { return id.recordName }
            return nil
        }
        let bases = store.state.lastKnownRecords
        let listRecords = listNames.isEmpty ? [:] : await MainActor.run { JournalSavedListSync.records(for: listNames, bases: bases) }
        // Stage J: settings, list contexts and the colour map, read on the main actor.
        let settingNames = pending.compactMap { change -> String? in
            if case .saveRecord(let id) = change, JournalSyncRecordType.isSettingsRecordName(id.recordName) { return id.recordName }
            return nil
        }
        let settingRecords = settingNames.isEmpty ? [:] : await MainActor.run { JournalSettingsSync.records(for: settingNames, store: store) }
        // Stage I: a value copy of the library; files are hashed as records are built.
        let hasScores = pending.contains { if case .saveRecord(let id) = $0 { return JournalSyncRecordType.isScoreRecordName(id.recordName) }; return false }
        let library = hasScores ? await MainActor.run { ScoreLibraryStore.shared.snapshot() } : nil
        let eligibility = currentEligibility()
        await refreshViewerScope()
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            self.gateUpload(self.buildRecord(recordID, typeByName: typeByName, listRecords: listRecords, settingRecords: settingRecords,
                                             library: library, eligibility: eligibility, ownerOnlyNames: ownerOnlyNames, assetFreeNames: assetFreeNames))
        }
    }

    /// The record for one pending change, or nil (which also drops a stale save
    /// from the outbox). Stage J gates the result for the link.
    private func buildRecord(_ recordID: CKRecord.ID, typeByName: [String: String], listRecords: [String: CKRecord], settingRecords: [String: CKRecord],
                             library: ScoreLibrarySnapshot?, eligibility: Eligibility, ownerOnlyNames: Set<String>, assetFreeNames: Set<String>) -> CKRecord? {
        let name = recordID.recordName
        if typeByName[name] == JournalSyncRecordType.savedList {
            if let record = listRecords[name] { return record }
            store.update { $0.outbox.removeAll { $0.recordName == name && $0.op == .save } }
            return nil
        }
        if JournalSyncRecordType.isScoreRecordName(name) {
            if let library, let record = JournalScoreSync.record(for: name, snapshot: library, store: store, log: { self.log($0) }) {
                return record
            }
            store.update { $0.outbox.removeAll { $0.recordName == name && $0.op == .save } }
            return nil
        }
        if JournalSyncRecordType.isSettingsRecordName(name) {
            if let record = settingRecords[name] { return record }
            store.update { $0.outbox.removeAll { $0.recordName == name && $0.op == .save } }
            return nil
        }
        return record(for: recordID, type: typeByName[name], eligibility: eligibility,
                      ownerOnly: ownerOnlyNames.contains(name), assetFree: assetFreeNames.contains(name))
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
            case JournalSyncRecordType.attachmentMeta: return 2
            case JournalSyncRecordType.profileAvatar: return 2
            case JournalSyncRecordType.score: return 2
            default: return 1
            }
        case .deleteRecord: return 3
        @unknown default: return 4
        }
    }

    /// Builds the outgoing record from Core Data; nil removes the pending change.
    /// Entries this device's ownership rules make ineligible stay local.
    private func record(for recordID: CKRecord.ID, type: String?, eligibility: Eligibility, ownerOnly: Bool = false,
                        assetFree: Bool = false) -> CKRecord? {
        let name = recordID.recordName
        if JournalSyncRecordType.isProfileRecordName(name) {
            // Stage H: fixed-name records read from the stores, not by id.
            let scope = profileScope
            var record: CKRecord?
            importContext.performAndWait {
                if name == JournalProfileSync.profileName {
                    record = JournalProfileSync.profileRecord(context: importContext, scope: scope, store: store) { self.importer.instrument(named: $0) }
                } else {
                    record = JournalProfileSync.avatarRecord(scope: scope, store: store)
                }
            }
            if name == JournalProfileSync.avatarName, let built = record,
               JournalProfileMerge.avatarSendIsRedundant(localHash: built[JournalRecordMapping.fileHashKey] as? String ?? "",
                                                         knownHash: store.state.assetHashes[name]) {
                log("Avatar already on the server; nothing to send")
                store.update { $0.outbox.removeAll { $0.recordName == name && $0.op == .save } }
                return nil
            }
            return record
        }
        let isMeta = type == JournalSyncRecordType.attachmentMeta || JournalSyncRecordType.attachmentName(fromMeta: name) != nil
        guard let id = UUID(uuidString: isMeta ? (JournalSyncRecordType.attachmentName(fromMeta: name) ?? "") : name) else { return nil }
        var result: CKRecord?
        var ineligible = false
        importContext.performAndWait {
            if isMeta {
                // Stage G: the small record; eligibility follows the attachment's session.
                guard let object = self.importer.freshObject(entity: JournalSyncRecordType.attachment, id: id) else { return }
                let session = object.value(forKey: "session") as? NSManagedObject
                ineligible = session == nil || !JournalOwnership.isEligible(owner: session?.value(forKey: "ownerUserID") as? String,
                                                                             journalOwner: eligibility.journalOwner)
                if ineligible { return }
                let base = store.state.lastKnownRecords[name].flatMap(JournalSyncStateStore.recordFromSystemFields)
                result = JournalRecordMapping.metaRecord(for: object, base: base)
                return
            }
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
                                                              serverHash: store.state.assetHashes[name], localHash: localHash,
                                                              assetFree: assetFree)
                result = JournalRecordMapping.record(for: object, base: base, includeAsset: include, fileHash: localHash)
                if include, result?[JournalRecordMapping.assetKey] == nil {
                    log("Attachment \(name) sent without its file (not found locally)")
                }
            } else {
                result = JournalRecordMapping.record(for: object, base: base, ownerOnly: ownerOnly, viewerScope: viewerScope)
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

    /// The batch's summary; `saveFailed` means the Core Data save rolled back (H3).
    @discardableResult
    private func importModifications(_ records: [CKRecord]) -> JournalImporter.Summary {
        guard !records.isEmpty else { return JournalImporter.Summary() }
        var summary = JournalImporter.Summary()
        importContext.performAndWait { summary = importer.importModifications(records) }
        store.update { $0.recordsReceived += summary.received; $0.bytesReceived += summary.bytes; $0.echoRecords += summary.echoes }
        if summary.received > 0 { log("Imported \(summary.received) record(s)\(summary.customs > 0 ? ", \(summary.customs) custom" : "")") }
        return summary
    }

    private func importDeletions(_ deletions: [(CKRecord.ID, CKRecord.RecordType)]) {
        guard !deletions.isEmpty else { return }
        let journal = deletions.filter { !JournalSyncRecordType.scoreTypes.contains($0.1) }
        if !journal.isEmpty { importContext.performAndWait { importer.importDeletions(journal) } }
        // Stage H: a deleted profile record (a reset elsewhere) is forgotten,
        // never applied; the next scan sends this device's profile afresh.
        let profileNames = deletions.map(\.0.recordName).filter(JournalSyncRecordType.isProfileRecordName)
        if !profileNames.isEmpty {
            store.update { st in
                for name in profileNames {
                    st.lastKnownRecords.removeValue(forKey: name)
                    st.knownChangeTags.removeValue(forKey: name)
                    if name == JournalProfileSync.avatarName { st.assetHashes.removeValue(forKey: name) } else { st.profileFingerprint = nil }
                }
            }
        }
        log("Applied \(deletions.count) remote deletion(s)")
    }

    /// Stage H: Profile and ProfileAvatar records, after the batch's
    /// instruments (the primary resolves by id, alias or name).
    private func importProfileRecords(_ records: [CKRecord]) {
        guard !records.isEmpty else { return }
        let scope = profileScope
        var applied = 0
        var avatarBytes: Int64 = 0
        var avatarChanged = false
        var resend: [JournalSyncPendingChange] = []
        importContext.performAndWait {
            for record in records.sorted(by: { $0.recordType == JournalSyncRecordType.profile && $1.recordType != JournalSyncRecordType.profile }) {
                let outcome: JournalProfileSync.Outcome
                if record.recordType == JournalSyncRecordType.profile {
                    outcome = JournalProfileSync.applyProfile(record, context: importContext, scope: scope, store: store, importer: importer) { self.log($0) }
                } else {
                    outcome = JournalProfileSync.applyAvatar(record, scope: scope, store: store) { self.log($0) }
                }
                applied += outcome.applied
                avatarBytes += outcome.avatarBytes
                avatarChanged = avatarChanged || outcome.avatarChanged
                resend += outcome.resend
            }
        }
        store.update { st in
            st.recordsReceived += applied
            st.avatarAssetBytesDelivered += avatarBytes
            st.assetBytesDownloaded += avatarBytes
        }
        if !resend.isEmpty { queueToEngine(zoneChanges: resend.map(pendingChange)) }
        // A pending save the import dropped must leave the engine's own list
        // too, or the record goes up again with the values just taken (iPad,
        // 14:43:32: one redundant send after a lost conflict).
        let stillPending = Set(store.state.outbox.filter { $0.op == .save }.map(\.recordName))
        for name in [JournalProfileSync.profileName, JournalProfileSync.avatarName] where !stillPending.contains(name) {
            engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(CKRecord.ID(recordName: name, zoneID: JournalRecordMapping.zoneID))])
        }
        if applied > 0 || avatarChanged {
            Task { @MainActor in
                if avatarChanged { JournalSyncCoordinator.shared.auth?.noteAvatarChangedBySync() }
                NotificationCenter.default.post(name: JournalProfileSync.didApplyNotification, object: nil)
            }
        }
    }

    // MARK: Stage I: Scores library records

    @discardableResult
    private func importScoreRecords(_ records: [CKRecord], localPending: Bool? = nil, generation: Int? = nil) async -> Bool {
        guard !records.isEmpty else { return true }
        guard let outcome = await MainActor.run(body: { () -> JournalScoreSync.Outcome? in
            if let generation, !self.mayStillImport(generation) { return nil }
            return JournalScoreSync.apply(records, store: self.store, library: ScoreLibraryStore.shared, localPending: localPending) { self.log($0) }
        }) else { return false }
        store.update { st in
            st.recordsReceived += outcome.applied
            st.scoreAssetBytesDelivered += outcome.assetBytes
            st.assetBytesDownloaded += outcome.assetBytes
            st.bytesReceived += outcome.bytesWritten
        }
        if !outcome.resend.isEmpty { queueToEngine(zoneChanges: outcome.resend.map(pendingChange)) }
        // A pending save the import settled must leave the engine's own list too.
        for name in outcome.settled {
            engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(CKRecord.ID(recordName: name, zoneID: JournalRecordMapping.zoneID))])
        }
        if outcome.applied > 0 || outcome.held > 0 {
            log("Scores: \(outcome.applied) record(s) applied, \(outcome.held) held, \(outcome.bytesWritten) bytes written")
        }
        return true
    }

    @discardableResult
    private func applyScoreDeletions(_ names: [String], generation: Int? = nil) async -> Bool {
        guard !names.isEmpty else { return true }
        guard let removed = await MainActor.run(body: { () -> Int? in
            if let generation, !self.mayStillImport(generation) { return nil }
            return JournalScoreSync.applyDeletions(names, store: self.store, library: ScoreLibraryStore.shared) { self.log($0) }
        }) else { return false }
        log("Applied \(names.count) score record deletion(s): \(removed) item(s) removed")
        return true
    }

    // MARK: Stage J: settings records

    @discardableResult
    private func importSettingsRecords(_ records: [CKRecord], localPending: Bool? = nil, generation: Int? = nil) async -> Bool {
        guard !records.isEmpty else { return true }
        guard let outcome = await MainActor.run(body: { () -> JournalSettingsSync.Outcome? in
            if let generation, !self.mayStillImport(generation) { return nil }
            return JournalSettingsSync.apply(records, store: self.store, localPending: localPending) { self.log($0) }
        }) else { return false }
        settleSettings(outcome)
        if outcome.applied > 0 || outcome.held > 0 {
            log("Settings: \(outcome.applied) record(s) applied, \(outcome.held) held")
        }
        return true
    }

    /// List contexts held for an instrument that has since arrived.
    @discardableResult
    private func applyHeldSettings(generation: Int? = nil) async -> Bool {
        guard !store.state.awaitingListContext.isEmpty else { return true }
        guard let outcome = await MainActor.run(body: { () -> JournalSettingsSync.Outcome? in
            if let generation, !self.mayStillImport(generation) { return nil }
            return JournalSettingsSync.retryHeld(store: self.store) { self.log($0) }
        }) else { return false }
        settleSettings(outcome)
        return true
    }

    private func settleSettings(_ outcome: JournalSettingsSync.Outcome) {
        store.update { $0.recordsReceived += outcome.applied }
        if !outcome.resend.isEmpty { queueToEngine(zoneChanges: outcome.resend.map(pendingChange)) }
        // A pending save the import settled must leave the engine's own list too.
        for name in outcome.settled {
            engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(CKRecord.ID(recordName: name, zoneID: JournalRecordMapping.zoneID))])
        }
    }

    private func forgetSettings(_ names: [String]) {
        guard !names.isEmpty else { return }
        JournalSettingsSync.forget(names, store: store)
        log("Forgot \(names.count) deleted settings record(s); resent at the next scan")
    }

    /// Stage J diagnostics: send every setting, list context and the colour map again.
    func rerunSettingsTransition() {
        JournalSettingsSync.rerunTransition(store: store)
        Task { await scanSettings() }
    }

    // MARK: Sent

    private func handleSent(_ e: CKSyncEngine.Event.SentRecordZoneChanges) {
        var sent = 0
        var bytes: Int64 = 0
        var uploads = 0
        var withoutMedia = 0
        var editedInFlight: [String] = []
        for record in e.savedRecords {
            sent += 1
            let name = record.recordID.recordName
            if store.state.mediaWaitingUpload[name] != nil { store.update { $0.mediaWaitingUpload.removeValue(forKey: name) } }
            if record.recordType == JournalSyncRecordType.attachment {
                if let hash = record[JournalRecordMapping.fileHashKey] as? String,
                   let asset = record[JournalRecordMapping.assetKey] as? CKAsset, let url = asset.fileURL {
                    uploads += 1
                    bytes += JournalAssetHash.stamp(of: url)?.size ?? 0
                    store.update { $0.assetHashes[name] = hash }
                } else {
                    withoutMedia += 1
                }
            } else if record.recordType == JournalSyncRecordType.score {
                // Stage I: the PDF, once; metadata and positions never carry it.
                if let hash = record[JournalRecordMapping.fileHashKey] as? String,
                   let asset = record[JournalRecordMapping.assetKey] as? CKAsset, let url = asset.fileURL {
                    bytes += JournalAssetHash.stamp(of: url)?.size ?? 0
                    store.update { $0.scoreUploads += 1; $0.assetHashes[name] = hash }
                } else {
                    store.update { $0.scoreRecordsSentWithoutFile += 1 }
                }
            } else if record.recordType == JournalSyncRecordType.scoreMeta {
                store.update { $0.scoreRecordsSentWithoutFile += 1 }
            } else if record.recordType == JournalSyncRecordType.scorePosition {
                store.update { $0.scorePositionsSent += 1 }
            } else if record.recordType == JournalSyncRecordType.tintMap {
                // Stage J: what the server now holds is the baseline for "changed".
                if let map = JournalTintMapMerge.decode(record[JournalSettingsKeys.map] as? Data) {
                    store.update { $0.tintMapExchanged = map; $0.tintMapQueuedFingerprint = nil }
                }
            } else if record.recordType == JournalSyncRecordType.profileAvatar {
                // Stage H: the server now holds this hash ("" after a removal).
                let hash = record[JournalRecordMapping.fileHashKey] as? String ?? ""
                if let asset = record[JournalRecordMapping.assetKey] as? CKAsset, let url = asset.fileURL {
                    bytes += JournalAssetHash.stamp(of: url)?.size ?? 0
                    store.update { $0.avatarUploads += 1 }
                }
                store.update { $0.assetHashes[name] = hash }
            }
            stateLock.lock(); let sentRevision = sentRevisions.removeValue(forKey: name); stateLock.unlock()
            var keptNewer = false
            store.update {
                $0.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record)
                $0.knownChangeTags[name] = record.recordChangeTag
                let settled = JournalOutboxSettle.settle(name: name, sentRevision: sentRevision, outbox: $0.outbox)
                $0.outbox = settled.outbox
                keptNewer = settled.keptNewer
            }
            if keptNewer { editedInFlight.append(name) }
        }
        if !editedInFlight.isEmpty {
            // B2: the person edited these while their send was in flight; the
            // entry stays and the current values go up next.
            queueToEngine(zoneChanges: editedInFlight.map { .saveRecord(CKRecord.ID(recordName: $0, zoneID: JournalRecordMapping.zoneID)) })
            log("\(editedInFlight.count) record(s) edited again while their send was in flight: kept queued, sent again")
        }
        for recordID in e.deletedRecordIDs {
            store.update {
                $0.lastKnownRecords.removeValue(forKey: recordID.recordName)
                $0.knownChangeTags.removeValue(forKey: recordID.recordName)
                $0.outbox.removeAll { $0.recordName == recordID.recordName && $0.op == .delete }
            }
        }
        var quotaRefused: [String] = []
        for failure in e.failedRecordSaves {
            if JournalStorageFull.isStorageFull(failure.error.code) { quotaRefused.append(failure.record.recordID.recordName) }
            else { handleFailedSave(failure) }
        }
        for failure in e.failedRecordDeletes {
            if failure.value.code == .unknownItem {
                store.update { $0.outbox.removeAll { $0.recordName == failure.key.recordName && $0.op == .delete } }
            } else {
                log("Delete of \(failure.key.recordName) failed: \(failure.value.localizedDescription) (will retry)")
            }
        }
        store.update { $0.recordsSent += sent; $0.bytesSent += bytes; $0.assetUploads += uploads; $0.attachmentRecordsSentWithoutMedia += withoutMedia }
        if sent > 0 {
            stateLock.lock(); transientFailureValue = nil; stateLock.unlock()
            log("Sent \(sent) record(s); \(uploads) media upload(s), \(bytes) bytes; \(withoutMedia) attachment record(s) metadata only")
        }
        if !quotaRefused.isEmpty {
            noteStorageFull(records: quotaRefused, zone: false, simulated: false)
        } else if store.state.storageFull != nil {
            let savesLeft = store.state.outbox.filter { $0.op == .save }.count
            if JournalStorageFull.recovered(savedRecords: sent, savedZones: 0, deletedRecords: e.deletedRecordIDs.count, quotaFailures: 0, savesStillPending: savesLeft) {
                endStorageFull(sent: sent, reason: "a save was accepted")
            }
        }
        // C-134 / C-135: no manual `fetchChanges()` after a content send. Every
        // such call on 2026-10-26 (seven of seven, 1846 to 1849) trapped inside
        // CloudKit 3 s later. The engine's own push-triggered fetch after a send
        // moves its saved state past the write in the common case, and a
        // record handed back with a change tag this device holds is skipped as
        // an echo above (its asset bytes counted), so nothing is applied twice.
    }

    /// Test seam: the lifecycle generation a deferred handler snapshots.
    func generationForTesting() -> Int { stateLock.lock(); defer { stateLock.unlock() }; return dormantGeneration }
    /// Test seam: a media hold, so a test batch ends without a CloudKit release.
    func holdMediaForTesting(_ hold: JournalMediaGate.Hold) { stateLock.lock(); mediaHoldValue = hold; stateLock.unlock() }

    /// The deferred half of a rejected-send conflict for the families whose
    /// apply runs on the main actor (lists) or through their own stage
    /// (scores, settings): the server copy wins, with our save known to be
    /// pending. `generation` was snapshotted when the rejection was handled.
    func applyDeferredSendConflict(server: CKRecord, recordID: CKRecord.ID, generation: Int) async {
        let name = recordID.recordName
        // R10 (2026-11-03): this runs after the rejection was handled; a
        // removal, unlink or account refusal meanwhile means nothing is
        // applied, checked inside the apply step as the catch-up's families do.
        if server.recordType == JournalSyncRecordType.savedList {
            let applied = await MainActor.run { () -> Bool in
                guard self.mayStillImport(generation) else { return false }
                JournalSavedListSync.apply([server], store: self.store, overridePending: true)
                self.dropPendingSave(name)
                return true
            }
            log(applied ? "Conflict on list \(name): server kept" : "Conflict on list \(name): not resolved, sync stopped meanwhile")
            return
        }
        let applied: Bool
        if JournalSyncRecordType.isScoreRecordName(name) { applied = await importScoreRecords([server], localPending: true, generation: generation) }
        else { applied = await importSettingsRecords([server], localPending: true, generation: generation) }
        guard applied else { log("Conflict on \(name): not resolved, sync stopped meanwhile"); return }
        let stillPending = store.state.outbox.contains { $0.recordName == name && $0.op == .save }
        if stillPending { queueToEngine(zoneChanges: [.saveRecord(recordID)]) }
        else { engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)]) }
    }

    private func handleFailedSave(_ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave) {
        let record = failure.record
        let name = record.recordID.recordName
        switch JournalSendFailure.action(for: failure.error.code) {
        case .resolveConflict:
            guard let server = failure.error.serverRecord else { return }
            if record.recordType == JournalSyncRecordType.savedList {
                // Lists: the server copy wins a rejected send (whole list).
                stateLock.lock(); let generation = dormantGeneration; stateLock.unlock()
                Task { await self.applyDeferredSendConflict(server: server, recordID: record.recordID, generation: generation) }
                return
            }
            if JournalSyncRecordType.isProfileRecordName(name) {
                // Stage H: same rule as the import, with our save known to be pending.
                let scope = profileScope
                var outcome = JournalProfileSync.Outcome()
                importContext.performAndWait {
                    if name == JournalProfileSync.profileName {
                        outcome = JournalProfileSync.applyProfile(server, context: importContext, scope: scope, store: store, importer: importer,
                                                                  localPending: true) { self.log("Send conflict — " + $0) }
                    } else {
                        outcome = JournalProfileSync.applyAvatar(server, scope: scope, store: store, localPending: true) { self.log("Send conflict — " + $0) }
                    }
                }
                if !outcome.resend.isEmpty { queueToEngine(zoneChanges: [.saveRecord(record.recordID)]) }
                else { engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(record.recordID)]) }
                if outcome.applied > 0 || outcome.avatarChanged {
                    Task { @MainActor in
                        if outcome.avatarChanged { JournalSyncCoordinator.shared.auth?.noteAvatarChangedBySync() }
                        NotificationCenter.default.post(name: JournalProfileSync.didApplyNotification, object: nil)
                    }
                }
                return
            }
            if JournalSyncRecordType.isScoreRecordName(name) || JournalSyncRecordType.isSettingsRecordName(name) {
                // Stages I and J: the same rule as the import, with our save known to be pending.
                stateLock.lock(); let generation = dormantGeneration; stateLock.unlock()
                Task { await self.applyDeferredSendConflict(server: server, recordID: record.recordID, generation: generation) }
                return
            }
            var resend = false
            importContext.performAndWait {
                resend = importer.resolveSendConflict(recordType: record.recordType, recordName: name, server: server)
            }
            if resend { queueToEngine(zoneChanges: [.saveRecord(record.recordID)]) }
        case .recreateZone:
            queueToEngine(zoneChanges: [.saveRecord(record.recordID)],
                          databaseChanges: [.saveZone(CKRecordZone(zoneID: JournalRecordMapping.zoneID))])
            // While the storage is full the zone itself was refused and every
            // record fails this way; the episode's one line covers it.
            if store.state.storageFull == nil { log("Zone missing; re-creating and resending \(name)") }
        case .resendAsNew:
            // The server no longer has it: resend as a new record.
            store.update { $0.lastKnownRecords.removeValue(forKey: name) }
            queueToEngine(zoneChanges: [.saveRecord(record.recordID)])
        case .engineRetries:
            stateLock.lock(); transientFailureValue = failure.error.localizedDescription; stateLock.unlock()
            log("Save of \(name) deferred: \(failure.error.localizedDescription)") // the engine retries
        case .storageFull:
            // handleSent gathers these per batch; kept for a direct call.
            noteStorageFull(records: [name], zone: false, simulated: false)
        case .unexpected:
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

    /// Status only: counts, the live facts and the derived summary, published
    /// on the main actor. Internal so a test can seed the status from a state
    /// file; the engine calls it after every event, catch-up and import.
    func refreshCounts() {
        let st = store.state
        stateLock.lock()
        let online = onlineValue
        let restore = restoreValue
        let transientFailure = transientFailureValue
        stateLock.unlock()
        Task { @MainActor in
            self.status.online = online
            self.status.restoreProgress = restore
            self.status.lastTransientFailure = transientFailure
            self.status.outboxCount = st.outbox.count
            self.status.heldCount = st.awaitingParent.count
            self.status.conflictCount = st.conflicts.count
            self.status.recordsSent = st.recordsSent
            self.status.recordsReceived = st.recordsReceived
            self.status.bytesSent = st.bytesSent
            self.status.bytesReceived = st.bytesReceived
            self.status.boundUser = st.boundUserRecordName
            let hold = self.mediaHold
            self.status.mediaGated = hold.holds
            self.status.mediaHold = hold
            self.status.mediaWaiting = JournalMediaHold.summary(uploads: st.mediaWaitingUpload, downloads: st.awaitingMedia, hold: hold)
            self.status.storageFull = st.storageFull
            self.status.storageFullSummary = st.storageFull.map { episode in
                let saves = st.outbox.filter { $0.op == .save }
                let media = saves.filter { JournalAssetPolicy.carriesFile(recordType: $0.recordType) && !$0.assetFree }.count
                return JournalStorageFull.summary(episode: episode, pendingSaves: saves.count, pendingDeletes: st.outbox.count - saves.count, mediaFiles: media)
            }
            self.status.summary = JournalSyncStatusSummary.derive(JournalSyncStatusFacts(
                inUse: true, unlinked: st.unlinked, localRemovalInProgress: st.localRemovalInProgress,
                phase: self.status.phase, pausedReason: self.status.pausedReason, online: online,
                initialFetchComplete: st.initialFetchComplete, restore: restore,
                outbox: st.outbox, awaitingMedia: st.awaitingMedia,
                heldRecords: st.awaitingParent.count + st.awaitingMeta.count + st.awaitingScore.count + st.awaitingListContext.count,
                mediaWaitingUpload: st.mediaWaitingUpload,
                fileStampCache: st.fileStampCache, mediaHold: hold, storageFullSummary: self.status.storageFullSummary,
                lastTransientFailure: transientFailure, lastCatchUp: st.lastCatchUp, lastFetchAt: self.status.lastFetchAt))
        }
    }
}

/// Whether THIS build can run the private sync at all, and through which
/// CloudKit container. The container identifier is a BUILD SETTING
/// (`ETUDES_CLOUDKIT_CONTAINER`), carried into the bundle as the Info.plist
/// key `EtudesCloudKitContainer`, and set only in a configuration whose
/// entitlements name that container: today the isolated SyncTest
/// configuration (the development container
/// `iCloud.com.samueldixon.motivo.synctest`, `MOTIVO-SyncTest.entitlements`,
/// `Info-SyncTest.plist`). Debug and Release leave it unset, so the key
/// expands to "" and they never offer the control and never build an engine.
/// Release's production container (`iCloud.com.sdsongs.etudes`) is turned on
/// by setting the build setting in the same change as its entitlements and
/// `remote-notification` (`docs/sync-trial/production-configuration.md`);
/// `SyncOffByDefaultTests` keeps the setting and the entitlements consistent.
enum JournalSyncCapability {
    static let infoKey = "EtudesCloudKitContainer"
    static let trialContainerIdentifier = "iCloud.com.samueldixon.motivo.synctest"
    static let productionContainerIdentifier = "iCloud.com.sdsongs.etudes"
    /// The container this build syncs through; "" when this build cannot sync.
    static let containerIdentifier: String = {
        let raw = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // An unexpanded setting ("$(ETUDES_CLOUDKIT_CONTAINER)") is "unset".
        return trimmed.hasPrefix("iCloud.") ? trimmed : ""
    }()
    static var buildSupportsSync: Bool { !containerIdentifier.isEmpty }
}

/// Owns the private sync for the app. OFF BY DEFAULT: nothing here runs until
/// the person turns sync on, and whether they have is one durable fact, the
/// state file. With no file `startIfNeeded` builds nothing: no state store, no
/// `JournalSyncEngine` (the only place a `CKContainer` is made), no push
/// registration, and the mirrors at the app's write points are inert. The
/// file is created by `enable()` and survives an unlink and a device-only
/// removal (both are "sync off, remembered"), so an interrupted removal is
/// always recovered at the next launch before any engine exists.
@MainActor
final class JournalSyncCoordinator {
    static let shared = JournalSyncCoordinator()
    /// Per configuration: see `JournalSyncCapability`.
    static var containerIdentifier: String { JournalSyncCapability.containerIdentifier }
    let status = JournalSyncStatus()
    private(set) var engine: JournalSyncEngine?
    private(set) var store: JournalSyncStateStore?
    /// Set by the app before `startIfNeeded`: adoption writes the owner key
    /// through it (and nothing else).
    weak var auth: AuthManager?
    private(set) var ownership: JournalOwnershipCoordinator?
    /// Where the switch and the sync state live. Tests point this at a
    /// temporary file; the app uses the default.
    let stateFileURL: URL
    /// Whether this build can sync (`JournalSyncCapability`). Tests pass it
    /// to play a build whose capability was withdrawn after sync was used.
    let supportsSync: Bool
    /// Set by the app: asks iOS for silent pushes. Called only once an engine
    /// exists, so a build or an install without sync never registers.
    var registerForPush: (() -> Void)?

    private var persistence: NSPersistentContainer?

    init(stateFileURL: URL = JournalSyncStateStore.defaultURL(), supportsSync: Bool = JournalSyncCapability.buildSupportsSync) {
        self.stateFileURL = stateFileURL
        self.supportsSync = supportsSync
    }

    /// Sync has been turned on on this install at some point: the state file
    /// exists and was opened at launch (or by `enable`).
    var isInUse: Bool { store != nil }

    /// Sync is on right now: in use, not unlinked, not mid-removal.
    var isEnabled: Bool {
        guard let store else { return false }
        let st = store.state
        return !st.unlinked && !st.localRemovalInProgress
    }

    /// Launch. Returns whether sync is in use on this install. With no state
    /// file (sync never turned on here) nothing is built or touched.
    @discardableResult
    func startIfNeeded(persistence: NSPersistentContainer) -> Bool {
        if engine != nil { return true }
        self.persistence = persistence
        guard supportsSync,
              FileManager.default.fileExists(atPath: stateFileURL.path) else { return false }
        start(persistence: persistence, store: JournalSyncStateStore(fileURL: stateFileURL))
        return true
    }

    /// The person turns sync on. The first time, the state file is created
    /// (the switch) with the history token fast-forwarded to now: everything
    /// that happened before this moment is not sync's business (the bootstrap
    /// queues the rows that exist; a deletion made before the switch must
    /// never go up, since without a token the history is read from its
    /// beginning). After an unlink or a removal it re-enables. False when this
    /// build cannot sync or the switch could not be written.
    @discardableResult
    func enable(persistence: NSPersistentContainer) -> Bool {
        guard supportsSync else { return false }
        self.persistence = persistence
        if let store {
            if store.state.unlinked { reenable() }
            return true
        }
        let store = JournalSyncStateStore(fileURL: stateFileURL)
        let token = persistence.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)
        let written = store.update { st in
            st.historyToken = JournalSyncStateStore.encode(token: token)
            st.log.append(.init(at: Date(), text: "Private sync turned on on this device; history before now is not read"))
        }
        guard written else { return false }
        start(persistence: persistence, store: store)
        return true
    }

    /// The person turns sync off: the journal and pending work are kept and
    /// edits go on being tracked; nothing is sent or fetched until enabled again.
    func disable() async { await engine?.unlink() }

    private func start(persistence: NSPersistentContainer, store: JournalSyncStateStore) {
        self.store = store
        // The metadata write points stamp their rows only once sync is in use.
        JournalMetadataMirror.container = persistence
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

    /// Bracket of the production erase (`LocalFactoryReset.perform`) and of
    /// the diagnostics control. Synchronous and durable before the first row
    /// is deleted. With sync never used on this install there is nothing to
    /// bracket and the erase proceeds. C-181: with a state file on a build
    /// that cannot sync (the capability withdrawn after sync was used), the
    /// store is opened for the bracket alone, so the erase is recorded as a
    /// local removal and a later build that can sync never reads its batch
    /// deletes from history as deletions to send.
    @discardableResult
    func beginLocalRemoval(reason: String) -> Bool {
        if store == nil, FileManager.default.fileExists(atPath: stateFileURL.path) {
            store = JournalSyncStateStore(fileURL: stateFileURL)
        }
        guard let store else { return true }
        if let engine { return engine.beginLocalRemoval(reason: reason) } else { return JournalLocalRemoval.begin(store: store, reason: reason) }
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
        // C-182: never an engine on a build that cannot sync, whatever the
        // caller (the set-up screen's restore card, `enable`).
        guard supportsSync, let store, let persistence else { return }
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
        // Silent CloudKit pushes are what tell the app the database moved;
        // without them the daemon answers "no changes" from its cache (seen in
        // Checkpoint 1). Asked for only now, with an engine to act on them.
        registerForPush?()
    }

    #if DEBUG
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
    #endif
}
