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
    static let tracked: Set<String> = [session, attachment]
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

    /// Reads history after the saved token, converts local transactions to
    /// outbox entries and advances the token, all in one durable write.
    /// Returns the entries added (already merged into the store's outbox).
    @discardableResult
    func processHistory() -> [JournalSyncPendingChange] {
        let after = JournalSyncStateStore.decodeToken(store.state.historyToken)
        var added: [JournalSyncPendingChange] = []
        var newToken: NSPersistentHistoryToken?

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
                    switch change.changeType {
                    case .insert, .update:
                        // The object may already be gone; its tombstone follows.
                        guard let object = try? context.existingObject(with: change.changedObjectID),
                              let id = object.value(forKey: "id") as? UUID else { continue }
                        // A save whose only changed key is the stamp itself is not a user edit.
                        if change.changeType == .update,
                           let keys = change.updatedProperties?.map(\.name), !keys.isEmpty,
                           Set(keys) == ["userModifiedAt"] { continue }
                        added.append(.init(recordName: id.uuidString, recordType: entity, op: .save))
                    case .delete:
                        guard let id = change.tombstone?["id"] as? UUID else { continue }
                        added.append(.init(recordName: id.uuidString, recordType: entity, op: .delete))
                    @unknown default:
                        continue
                    }
                }
            }
        }

        guard newToken != nil || !added.isEmpty else { return [] }
        let ok = store.update { st in
            Self.merge(added, into: &st.outbox)
            if let newToken { st.historyToken = JournalSyncStateStore.encode(token: newToken) }
        }
        return ok ? added : []
    }

    /// A delete supersedes a pending save of the same record; otherwise entries
    /// are unique by (name, op).
    static func merge(_ incoming: [JournalSyncPendingChange], into outbox: inout [JournalSyncPendingChange]) {
        for change in incoming {
            if change.op == .delete {
                outbox.removeAll { $0.recordName == change.recordName }
            }
            if !outbox.contains(change) { outbox.append(change) }
        }
    }
}

/// Stamps `userModifiedAt` on every Session and Attachment a LOCAL context is
/// about to save, so both devices carry a comparable user-edit time. The
/// import context (author `sync`) is skipped so server values are kept as-is.
enum JournalUserEditStamp {
    static func install() -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: .NSManagedObjectContextWillSave, object: nil, queue: nil) { note in
            guard let ctx = note.object as? NSManagedObjectContext,
                  ctx.transactionAuthor != JournalSyncAuthor.sync else { return }
            let now = Date()
            for object in ctx.insertedObjects.union(ctx.updatedObjects) {
                guard let name = object.entity.name, JournalSyncRecordType.tracked.contains(name) else { continue }
                let changed = Set(object.changedValues().keys)
                if object.isInserted || !changed.subtracting(["userModifiedAt"]).isEmpty {
                    object.setValue(now, forKey: "userModifiedAt")
                }
            }
        }
    }
}
#endif
