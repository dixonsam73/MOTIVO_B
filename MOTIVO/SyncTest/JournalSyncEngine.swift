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
//  Out of scope here, by agreement: Scores, lists, profile, Connected, account
//  switching UI, push notifications (fetches run at launch, on foreground, on
//  the engine's own schedule and from the diagnostics screen).
//

#if SYNCTEST
import Foundation
import CloudKit
import CoreData
import os

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

final class JournalSyncEngine: NSObject, CKSyncEngineDelegate, @unchecked Sendable {

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

    init(containerIdentifier: String, persistence: NSPersistentContainer, store: JournalSyncStateStore, status: JournalSyncStatus) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.persistence = persistence
        self.store = store
        self.status = status
        self.tracker = JournalChangeTracker(container: persistence, store: store)
        let ctx = persistence.newBackgroundContext()
        ctx.name = "syncImport"
        ctx.transactionAuthor = JournalSyncAuthor.sync
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.importContext = ctx
        super.init()
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
        stampObserver = JournalUserEditStamp.install()
        await publish { $0.phase = "Checking iCloud account" }
        do {
            let me = try await container.userRecordID()
            currentUserRecordName = me.recordName
            if let bound = store.state.boundUserRecordName {
                if bound != me.recordName {
                    pause("This journal is linked to a different iCloud account. Nothing is uploaded.")
                    return
                }
            } else {
                store.update { $0.boundUserRecordName = me.recordName }
                log("Bound journal to iCloud user \(me.recordName)")
            }
        } catch {
            pause("iCloud unavailable: \(error.localizedDescription)")
            return
        }

        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: JournalRecordMapping.zoneID))])
        let bootstrapped = tracker.bootstrapIfNeeded()
        if bootstrapped > 0 { log("Queued \(bootstrapped) existing record(s)") }
        tracker.processHistory()
        requeueOutbox()
        installSaveObserver()
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
            importModifications(e.modifications.map(\.record))
            importDeletions(e.deletions.map { ($0.recordID, $0.recordType) })
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
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            self.record(for: recordID)
        }
    }

    private func rank(_ change: CKSyncEngine.PendingRecordZoneChange, _ types: [String: String]) -> Int {
        switch change {
        case .saveRecord(let id): return types[id.recordName] == JournalSyncRecordType.attachment ? 1 : 0
        case .deleteRecord: return 2
        @unknown default: return 3
        }
    }

    /// Builds the outgoing record from Core Data; nil removes the pending change.
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let id = UUID(uuidString: recordID.recordName) else { return nil }
        var result: CKRecord?
        importContext.performAndWait {
            guard let object = fetch(entity: JournalSyncRecordType.session, id: id, in: importContext)
                    ?? fetch(entity: JournalSyncRecordType.attachment, id: id, in: importContext) else { return }
            let base = store.state.lastKnownRecords[recordID.recordName].flatMap(JournalSyncStateStore.recordFromSystemFields)
            result = JournalRecordMapping.record(for: object, base: base)
            if object.entity.name == JournalSyncRecordType.attachment, result?[JournalRecordMapping.assetKey] == nil {
                log("Attachment \(recordID.recordName) sent without its file (not found locally)")
            }
        }
        if result == nil {
            // Nothing to send: drop a stale save from the outbox.
            store.update { $0.outbox.removeAll { $0.recordName == recordID.recordName && $0.op == .save } }
        }
        return result
    }

    // MARK: Account

    private func handleAccountChange(_ e: CKSyncEngine.Event.AccountChange) {
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

    // MARK: Import

    private func importModifications(_ records: [CKRecord]) {
        guard !records.isEmpty else { return }
        let sessions = records.filter { $0.recordType == JournalSyncRecordType.session }
        let attachments = records.filter { $0.recordType == JournalSyncRecordType.attachment }
        var received = 0
        var bytes: Int64 = 0
        importContext.performAndWait {
            for record in sessions { if importSession(record) { received += 1 } }
            for record in attachments {
                let outcome = importAttachment(record)
                if outcome.imported { received += 1 }
                bytes += outcome.bytes
            }
            // Any held attachment whose session has now arrived.
            for (name, held) in store.state.awaitingParent {
                guard let sid = UUID(uuidString: held.sessionRecordName),
                      fetch(entity: JournalSyncRecordType.session, id: sid, in: importContext) != nil,
                      let record = JournalSyncStateStore.decodeWholeRecord(held.recordData) else { continue }
                let outcome = importAttachment(record, heldFile: held.heldFilePath)
                if outcome.imported {
                    received += 1; bytes += outcome.bytes
                    store.update { $0.awaitingParent.removeValue(forKey: name) }
                    log("Linked held attachment \(name) to its session")
                }
            }
            saveImportContext()
        }
        store.update { $0.recordsReceived += received; $0.bytesReceived += bytes }
        if received > 0 { log("Imported \(received) record(s)") }
    }

    /// Returns true when the server record was applied.
    private func importSession(_ record: CKRecord) -> Bool {
        let name = record.recordID.recordName
        guard let id = UUID(uuidString: name) else { return false }
        let existing = fetch(entity: JournalSyncRecordType.session, id: id, in: importContext)
        if let existing, localChangePending(name) {
            let local = existing.value(forKey: "userModifiedAt") as? Date
            let server = JournalRecordMapping.userModifiedAt(of: record)
            if JournalConflictRule.decide(localUserModifiedAt: local, serverUserModifiedAt: server) == .local {
                // Keep ours; remember the server copy so our send carries its change tag.
                store.update { $0.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record) }
                recordConflict(record, winner: .local, local: existing)
                return false
            }
            recordConflict(record, winner: .server, local: existing)
            dropPendingSave(name)
        }
        let object = existing ?? NSEntityDescription.insertNewObject(forEntityName: JournalSyncRecordType.session, into: importContext)
        _ = JournalRecordMapping.apply(record, to: object)
        store.update { $0.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record) }
        return true
    }

    private func importAttachment(_ record: CKRecord, heldFile: String? = nil) -> (imported: Bool, bytes: Int64) {
        let name = record.recordID.recordName
        guard let id = UUID(uuidString: name) else { return (false, 0) }
        guard let sidName = JournalRecordMapping.sessionRecordName(of: record), let sid = UUID(uuidString: sidName) else {
            log("Attachment \(name) has no session reference; skipped")
            return (false, 0)
        }
        guard let session = fetch(entity: JournalSyncRecordType.session, id: sid, in: importContext) else {
            hold(record, sessionRecordName: sidName)
            return (false, 0)
        }
        let existing = fetch(entity: JournalSyncRecordType.attachment, id: id, in: importContext)
        if let existing, localChangePending(name) {
            let local = existing.value(forKey: "userModifiedAt") as? Date
            let server = JournalRecordMapping.userModifiedAt(of: record)
            if JournalConflictRule.decide(localUserModifiedAt: local, serverUserModifiedAt: server) == .local {
                store.update { $0.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record) }
                recordConflict(record, winner: .local, local: existing)
                return (false, 0)
            }
            recordConflict(record, winner: .server, local: existing)
            dropPendingSave(name)
        }
        let object = existing ?? NSEntityDescription.insertNewObject(forEntityName: JournalSyncRecordType.attachment, into: importContext)
        _ = JournalRecordMapping.apply(record, to: object)
        object.setValue(session, forKey: "session")

        // Bytes: materialise where the resolver looks, but ONLY when this device
        // has no usable file already. The device that created the attachment
        // keeps its own file (named <base>-<id>.<ext> by staging); rewriting its
        // path to <id>.<ext> would break the attachment it just made.
        var bytes: Int64 = 0
        let ext = (record[JournalRecordMapping.fileExtKey] as? String) ?? ""
        let destination = JournalRecordMapping.materialisedURL(recordName: name, ext: ext)
        let existingFile = AttachmentPathResolver.resolve(object.value(forKey: "fileURL") as? String)
        let sourceURL = heldFile.map { URL(fileURLWithPath: $0) } ?? (record[JournalRecordMapping.assetKey] as? CKAsset)?.fileURL
        if existingFile == nil {
            if let sourceURL, FileManager.default.fileExists(atPath: sourceURL.path) {
                let incoming = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? NSNumber)?.int64Value ?? 0
                let present = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value
                if present != incoming {
                    try? FileManager.default.removeItem(at: destination)
                    do { try FileManager.default.copyItem(at: sourceURL, to: destination); bytes = incoming }
                    catch { log("Could not materialise \(name): \(error.localizedDescription)") }
                }
            } else {
                log("Attachment \(name) arrived without a file")
            }
            // Point at the materialised path even if the copy failed, so the
            // resolver's filename match finds it once a later fetch supplies it.
            object.setValue(destination.path, forKey: "fileURL")
        }
        if heldFile != nil, let sourceURL { try? FileManager.default.removeItem(at: sourceURL) }
        store.update { $0.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record) }
        return (true, bytes)
    }

    private func hold(_ record: CKRecord, sessionRecordName: String) {
        let name = record.recordID.recordName
        var heldPath: String?
        if let asset = record[JournalRecordMapping.assetKey] as? CKAsset, let url = asset.fileURL,
           FileManager.default.fileExists(atPath: url.path) {
            let dest = JournalSyncStateStore.holdingDirectory().appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil { heldPath = dest.path }
        }
        guard let data = JournalSyncStateStore.encodeWholeRecord(record) else { return }
        store.update { $0.awaitingParent[name] = JournalSyncHeldAttachment(recordData: data, sessionRecordName: sessionRecordName, heldFilePath: heldPath) }
        log("Holding attachment \(name) until session \(sessionRecordName) arrives")
    }

    private func importDeletions(_ deletions: [(CKRecord.ID, CKRecord.RecordType)]) {
        guard !deletions.isEmpty else { return }
        importContext.performAndWait {
            for (recordID, type) in deletions {
                guard let id = UUID(uuidString: recordID.recordName) else { continue }
                if let object = fetch(entity: type, id: id, in: importContext) {
                    if type == JournalSyncRecordType.session {
                        for case let att as NSManagedObject in (object.value(forKey: "attachments") as? Set<NSManagedObject>) ?? [] {
                            removeFile(of: att)
                        }
                    } else {
                        removeFile(of: object)
                    }
                    importContext.delete(object)
                }
                store.update {
                    $0.lastKnownRecords.removeValue(forKey: recordID.recordName)
                    $0.outbox.removeAll { $0.recordName == recordID.recordName }
                    $0.awaitingParent.removeValue(forKey: recordID.recordName)
                }
            }
            saveImportContext()
        }
        log("Applied \(deletions.count) remote deletion(s)")
    }

    private func removeFile(of attachment: NSManagedObject) {
        if let url = AttachmentPathResolver.resolve(attachment.value(forKey: "fileURL") as? String) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func saveImportContext() {
        guard importContext.hasChanges else { return }
        do { try importContext.save() } catch {
            log("Import save failed: \(error.localizedDescription)")
            importContext.rollback()
        }
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
            var localDate: Date?
            var localObject: NSManagedObject?
            importContext.performAndWait {
                if let id = UUID(uuidString: name) {
                    localObject = fetch(entity: record.recordType, id: id, in: importContext)
                    localDate = localObject?.value(forKey: "userModifiedAt") as? Date
                }
            }
            let decision = JournalConflictRule.decide(localUserModifiedAt: localDate, serverUserModifiedAt: JournalRecordMapping.userModifiedAt(of: server))
            if decision == .server {
                importContext.performAndWait {
                    if let localObject {
                        recordConflict(server, winner: .server, local: localObject)
                        _ = JournalRecordMapping.apply(server, to: localObject)
                        saveImportContext()
                    }
                }
                store.update { $0.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(server) }
                dropPendingSave(name)
                log("Conflict on \(name): server won")
            } else {
                importContext.performAndWait { if let localObject { recordConflict(server, winner: .local, local: localObject) } }
                store.update { $0.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(server) }
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
                log("Conflict on \(name): local won, resending")
            }
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

    private func localChangePending(_ recordName: String) -> Bool {
        store.state.outbox.contains { $0.recordName == recordName && $0.op == .save }
    }

    private func recordConflict(_ server: CKRecord, winner: JournalConflictWinner, local: NSManagedObject) {
        let loserTitle: String?
        let loserNotes: String?
        if winner == .server {
            loserTitle = local.value(forKey: "title") as? String ?? local.value(forKey: "displayName") as? String
            loserNotes = local.value(forKey: "notes") as? String
        } else {
            loserTitle = server["title"] as? String ?? server["displayName"] as? String
            loserNotes = server["notes"] as? String
        }
        let conflict = JournalSyncConflict(at: Date(), recordName: server.recordID.recordName, recordType: server.recordType,
                                           winner: winner == .server ? "server" : "local",
                                           localUserModifiedAt: local.value(forKey: "userModifiedAt") as? Date,
                                           serverUserModifiedAt: JournalRecordMapping.userModifiedAt(of: server),
                                           losingTitle: loserTitle, losingNotes: loserNotes)
        store.update { $0.conflicts.append(conflict) }
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

    private var persistence: NSPersistentContainer?

    func startIfNeeded(persistence: NSPersistentContainer) {
        guard engine == nil else { return }
        self.persistence = persistence
        let store = JournalSyncStateStore(fileURL: JournalSyncStateStore.defaultURL())
        self.store = store
        let engine = JournalSyncEngine(containerIdentifier: Self.containerIdentifier, persistence: persistence, store: store, status: status)
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
        let engine = JournalSyncEngine(containerIdentifier: Self.containerIdentifier, persistence: persistence, store: store, status: status)
        self.engine = engine
        Task { await engine.start() }
    }
}
#endif
