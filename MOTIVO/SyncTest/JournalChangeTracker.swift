//
//  JournalChangeTracker.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
//
//  LOCAL CHANGES → OUTBOX, FROM CORE DATA'S PERSISTENT HISTORY.
//
//  Every context that saves Sessions or Attachments is covered, including the
//  background contexts used for deletion and sharing hand-off, because the
//  history store records them all. The one exclusion is the import context,
//  whose transactions carry the author `sync`. Deletions are read from history
//  tombstones, which keep `id` because the model marks it "preserve after
//  deletion" (V11); no mapping table is needed.
//
//  Durability: new outbox entries and the advanced token are written in ONE
//  atomic update of the state file. If that write fails, neither moves.
//

#if SYNCTEST
import Foundation
import CoreData

enum JournalSyncRecordType {
    static let session = "Session"
    static let attachment = "Attachment"
    static let userInstrument = "UserInstrument"
    static let userActivity = "UserActivity"
    /// The profile's instruments, which sessions point at (`Session.instrument`).
    static let instrument = "Instrument"
    /// Not a Core Data entity: saved Lists live in UserDefaults.
    static let savedList = "SavedList"
    static let customs: Set<String> = [userInstrument, userActivity]
    /// Rows without a preserved id: deletions are found through the URI map.
    static let directory: Set<String> = customs.union([instrument])
    /// Entities that carry `userModifiedAt` and a preserved `id`.
    static let stamped: Set<String> = [session, attachment]
    /// Entities read from persistent history.
    static let tracked: Set<String> = stamped.union(directory)
}

final class JournalChangeTracker {
    private let container: NSPersistentContainer
    private let store: JournalSyncStateStore
    private let context: NSManagedObjectContext

    init(container: NSPersistentContainer, store: JournalSyncStateStore) {
        self.container = container
        self.store = store
        let ctx = container.newBackgroundContext()
        ctx.name = "syncHistoryReader"
        ctx.transactionAuthor = JournalSyncAuthor.sync
        self.context = ctx
    }

    /// Queues every existing Session and Attachment for its first upload.
    /// The token is captured BEFORE enumeration, so anything saved during the
    /// enumeration is seen again by `processHistory` (a duplicate save, which
    /// is harmless) rather than missed. Marks `bootstrapQueued` only in the
    /// same write that records the work.
    @discardableResult
    func bootstrapIfNeeded() -> Int {
        guard store.state.bootstrapQueued == false else { return 0 }
        let token = container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)
        var pending: [JournalSyncPendingChange] = []
        context.performAndWait {
            let sessions = NSFetchRequest<NSManagedObject>(entityName: JournalSyncRecordType.session)
            sessions.propertiesToFetch = ["id"]
            let attachments = NSFetchRequest<NSManagedObject>(entityName: JournalSyncRecordType.attachment)
            attachments.propertiesToFetch = ["id"]
            for s in (try? context.fetch(sessions)) ?? [] {
                if let id = s.value(forKey: "id") as? UUID {
                    pending.append(.init(recordName: id.uuidString, recordType: JournalSyncRecordType.session, op: .save))
                }
            }
            for a in (try? context.fetch(attachments)) ?? [] {
                if let id = a.value(forKey: "id") as? UUID {
                    pending.append(.init(recordName: id.uuidString, recordType: JournalSyncRecordType.attachment, op: .save))
                }
            }
        }
        let ok = store.update { st in
            Self.merge(pending, into: &st.outbox)
            st.bootstrapQueued = true
            st.historyToken = JournalSyncStateStore.encode(token: token)
            st.log.append(.init(at: Date(), text: "Bootstrap queued \(pending.count) record(s) for first upload"))
        }
        return ok ? pending.count : 0
    }

    /// Stage B: queues every custom instrument and activity of this install
    /// (K2) and every profile instrument once, recording each object's URI so
    /// a later local deletion can be sent. Rows under any other owner are
    /// left alone.
    @discardableResult
    func bootstrapCustomsIfNeeded(customOwner: String?) -> Int {
        guard let customOwner else { return 0 }
        let customs = store.state.customsBootstrapQueued == false
        let instruments = store.state.instrumentsBootstrapQueued == false
        guard customs || instruments else { return 0 }
        var pending: [JournalSyncPendingChange] = []
        var names: [String: String] = [:]
        context.performAndWait {
            var entities: [String] = []
            if customs { entities += [JournalSyncRecordType.userInstrument, JournalSyncRecordType.userActivity] }
            if instruments { entities.append(JournalSyncRecordType.instrument) }
            for entity in entities {
                let request = NSFetchRequest<NSManagedObject>(entityName: entity)
                if entity != JournalSyncRecordType.instrument {
                    request.predicate = NSPredicate(format: "ownerUserID == %@", customOwner)
                }
                for row in (try? context.fetch(request)) ?? [] {
                    guard let id = row.value(forKey: "id") as? UUID else { continue }
                    names[row.objectID.uriRepresentation().absoluteString] = id.uuidString
                    pending.append(.init(recordName: id.uuidString, recordType: entity, op: .save))
                }
            }
            if instruments, store.state.bootstrapQueued {
                // An existing store whose sessions were uploaded before links
                // existed: send each session with an instrument once more, so
                // the other device can resolve it. Attachments are untouched.
                let request = NSFetchRequest<NSManagedObject>(entityName: JournalSyncRecordType.session)
                request.predicate = NSPredicate(format: "instrument != nil")
                for row in (try? context.fetch(request)) ?? [] {
                    guard let id = row.value(forKey: "id") as? UUID else { continue }
                    pending.append(.init(recordName: id.uuidString, recordType: JournalSyncRecordType.session, op: .save))
                }
            }
        }
        let ok = store.update { st in
            Self.merge(pending, into: &st.outbox)
            st.customRecordNames.merge(names) { _, new in new }
            if customs { st.customsBootstrapQueued = true }
            if instruments { st.instrumentsBootstrapQueued = true }
            st.log.append(.init(at: Date(), text: "Bootstrap queued \(pending.count) directory row(s) / linked session(s)"))
        }
        return ok ? pending.count : 0
    }

    /// Queues every Session and Attachment the server has not seen and that is
    /// not already pending. Used when the journal's owner changes, because
    /// entries held back as ineligible may now be eligible.
    @discardableResult
    func requeueUnsent() -> [JournalSyncPendingChange] {
        var pending: [JournalSyncPendingChange] = []
        let known = Set(store.state.lastKnownRecords.keys)
        let queued = Set(store.state.outbox.map(\.recordName))
        context.performAndWait {
            for entity in [JournalSyncRecordType.session, JournalSyncRecordType.attachment] {
                let request = NSFetchRequest<NSManagedObject>(entityName: entity)
                for row in (try? context.fetch(request)) ?? [] {
                    guard let id = row.value(forKey: "id") as? UUID else { continue }
                    let name = id.uuidString
                    if known.contains(name) || queued.contains(name) { continue }
                    pending.append(.init(recordName: name, recordType: entity, op: .save))
                }
            }
        }
        guard !pending.isEmpty else { return [] }
        let ok = store.update { Self.merge(pending, into: &$0.outbox) }
        return ok ? pending : []
    }

    /// Reads history after the saved token, converts local transactions to
    /// outbox entries and advances the token, all in one durable write.
    /// Returns the entries added (already merged into the store's outbox).
    @discardableResult
    func processHistory() -> [JournalSyncPendingChange] {
        let after = JournalSyncStateStore.decodeToken(store.state.historyToken)
        var added: [JournalSyncPendingChange] = []
        var newToken: NSPersistentHistoryToken?
        var namesAdded: [String: String] = [:]
        var urisRemoved: [String] = []
        let knownCustomNames = store.state.customRecordNames

        context.performAndWait {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: after)
            request.resultType = .transactionsAndChanges
            guard let result = try? context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction] else { return }
            for transaction in transactions {
                newToken = transaction.token
                if transaction.author == JournalSyncAuthor.sync { continue }
                for change in transaction.changes ?? [] {
                    guard let entity = change.changedObjectID.entity.name,
                          JournalSyncRecordType.tracked.contains(entity) else { continue }
                    let uri = change.changedObjectID.uriRepresentation().absoluteString
                    switch change.changeType {
                    case .insert, .update:
                        // The object may already be gone; its tombstone follows.
                        guard let object = try? context.existingObject(with: change.changedObjectID),
                              let id = object.value(forKey: "id") as? UUID else { continue }
                        var ownerOnly = false
                        if change.changeType == .update, let keys = change.updatedProperties.map({ Set($0.map(\.name)) }) {
                            // A save whose only changed key is the stamp itself is not a user edit.
                            if keys == ["userModifiedAt"] { continue }
                            // An attachment's owner is not synced (it follows its session).
                            if entity == JournalSyncRecordType.attachment, JournalOwnership.isOwnershipOnly(keys) { continue }
                            ownerOnly = entity == JournalSyncRecordType.session && JournalOwnership.isOwnershipOnly(keys)
                        }
                        if JournalSyncRecordType.directory.contains(entity) { namesAdded[uri] = id.uuidString }
                        added.append(.init(recordName: id.uuidString, recordType: entity, op: .save, ownerOnly: ownerOnly))
                    case .delete:
                        if let id = change.tombstone?["id"] as? UUID {
                            added.append(.init(recordName: id.uuidString, recordType: entity, op: .delete))
                        } else if let name = namesAdded[uri] ?? knownCustomNames[uri] {
                            // Custom rows keep no id after deletion; the URI map has it.
                            added.append(.init(recordName: name, recordType: entity, op: .delete))
                            urisRemoved.append(uri)
                        }
                    @unknown default:
                        continue
                    }
                }
            }
        }

        guard newToken != nil || !added.isEmpty else { return [] }
        let ok = store.update { st in
            Self.merge(added, into: &st.outbox)
            st.customRecordNames.merge(namesAdded) { _, new in new }
            for uri in urisRemoved { st.customRecordNames.removeValue(forKey: uri) }
            if let newToken { st.historyToken = JournalSyncStateStore.encode(token: newToken) }
        }
        return ok ? added : []
    }

    /// A delete supersedes a pending save of the same record; otherwise entries
    /// are unique by (name, op). A content save absorbs a pending owner-only
    /// save; an owner-only save never downgrades a pending content save.
    static func merge(_ incoming: [JournalSyncPendingChange], into outbox: inout [JournalSyncPendingChange]) {
        for change in incoming {
            if change.op == .delete {
                outbox.removeAll { $0.recordName == change.recordName }
            }
            if let i = outbox.firstIndex(where: { $0.recordName == change.recordName && $0.op == change.op }) {
                if outbox[i].ownerOnly && !change.ownerOnly { outbox[i] = change }
            } else {
                outbox.append(change)
            }
        }
    }
}

/// Stamps `userModifiedAt` on every Session and Attachment a LOCAL context is
/// about to save, so both devices carry a comparable user-edit time. The
/// import context (author `sync`) is skipped so server values are kept as-is,
/// and so is an ownership-only change (stage B: giving an entry its owner is
/// not a user edit and must not beat one under the conflict rule).
enum JournalUserEditStamp {
    static func install() -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: .NSManagedObjectContextWillSave, object: nil, queue: nil) { note in
            guard let ctx = note.object as? NSManagedObjectContext,
                  ctx.transactionAuthor != JournalSyncAuthor.sync else { return }
            let now = Date()
            for object in ctx.insertedObjects.union(ctx.updatedObjects) {
                guard let name = object.entity.name, JournalSyncRecordType.stamped.contains(name) else { continue }
                let changed = Set(object.changedValues().keys)
                if object.isInserted || !changed.subtracting(JournalOwnership.ownershipOnlyKeys).isEmpty {
                    object.setValue(now, forKey: "userModifiedAt")
                }
            }
        }
    }
}
#endif
