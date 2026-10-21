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
    /// Stage G: an attachment's frequently edited metadata (name, star,
    /// privacy, page selection) as its own small record, named "<id>-meta",
    /// so a metadata edit never makes a receiver download the file.
    static let attachmentMeta = "AttachmentMeta"
    static let metaSuffix = "-meta"
    static func metaName(for attachmentName: String) -> String { attachmentName + metaSuffix }
    static func attachmentName(fromMeta name: String) -> String? {
        name.hasSuffix(metaSuffix) ? String(name.dropLast(metaSuffix.count)) : nil
    }
    /// Attachment keys whose change is a content change (the record that carries the file).
    static let attachmentContentKeys: Set<String> = ["kind", "fileURL", "createdAt", "session"]
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
        guard store.state.bootstrapQueued == false, !store.state.localRemovalInProgress else { return 0 }
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
                    pending.append(.init(recordName: JournalSyncRecordType.metaName(for: id.uuidString),
                                         recordType: JournalSyncRecordType.attachmentMeta, op: .save, metadataEdit: true))
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
        guard let customOwner, !store.state.localRemovalInProgress else { return 0 }
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
        guard !store.state.localRemovalInProgress else { return [] }
        var pending: [JournalSyncPendingChange] = []
        let known = Set(store.state.lastKnownRecords.keys)
        let queued = Set(store.state.outbox.map(\.recordName))
        context.performAndWait {
            for entity in [JournalSyncRecordType.session, JournalSyncRecordType.attachment] {
                let request = NSFetchRequest<NSManagedObject>(entityName: entity)
                for row in (try? context.fetch(request)) ?? [] {
                    guard let id = row.value(forKey: "id") as? UUID else { continue }
                    let name = id.uuidString
                    if !(known.contains(name) || queued.contains(name)) {
                        pending.append(.init(recordName: name, recordType: entity, op: .save))
                    }
                    if entity == JournalSyncRecordType.attachment {
                        let meta = JournalSyncRecordType.metaName(for: name)
                        if !(known.contains(meta) || queued.contains(meta)) {
                            pending.append(.init(recordName: meta, recordType: JournalSyncRecordType.attachmentMeta, op: .save, metadataEdit: true))
                        }
                    }
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
    ///
    /// Stage E: while a local removal is in progress the history is DISCARDED
    /// (the token advances, nothing is queued), so an erase, interrupted or
    /// not, can never become server deletions. Transactions by the removal
    /// recovery's own author are skipped like the import context's.
    @discardableResult
    func processHistory() -> [JournalSyncPendingChange] {
        let after = JournalSyncStateStore.decodeToken(store.state.historyToken)
        var added: [JournalSyncPendingChange] = []
        var newToken: NSPersistentHistoryToken?
        var namesAdded: [String: String] = [:]
        var urisRemoved: [String] = []
        let knownCustomNames = store.state.customRecordNames
        let discard = store.state.localRemovalInProgress

        context.performAndWait {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: after)
            request.resultType = .transactionsAndChanges
            guard let result = try? context.execute(request) as? NSPersistentHistoryResult,
                  let transactions = result.result as? [NSPersistentHistoryTransaction] else { return }
            for transaction in transactions {
                newToken = transaction.token
                if discard { continue }
                if transaction.author == JournalSyncAuthor.sync || transaction.author == JournalSyncAuthor.localRemoval { continue }
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
                        // A metadata write point's save (a touch, or displayName): the file is unchanged.
                        let metadataEdit = change.changeType == .update && transaction.author == JournalSyncAuthor.metadata
                        var attachmentContentChanged = change.changeType == .insert
                        var attachmentMetaChanged = change.changeType == .insert
                        if change.changeType == .update, let keys = change.updatedProperties.map({ Set($0.map(\.name)) }) {
                            // A save whose only changed key is the stamp itself is not a user
                            // edit, unless a metadata write point made it (stage F): then the
                            // edit lives in a side store and the stamp is its clock.
                            if keys == ["userModifiedAt"], transaction.author != JournalSyncAuthor.metadata { continue }
                            // An attachment's owner is not synced (it follows its session);
                            // a metadata write point's touch, though, is a user edit (stage F).
                            if entity == JournalSyncRecordType.attachment, JournalOwnership.isOwnershipOnly(keys),
                               transaction.author != JournalSyncAuthor.metadata { continue }
                            // A metadata write point's touch is a full-record user edit, not owner-only.
                            ownerOnly = entity == JournalSyncRecordType.session && JournalOwnership.isOwnershipOnly(keys)
                                && transaction.author != JournalSyncAuthor.metadata
                            // Stage G: which of an attachment's two records changed.
                            attachmentContentChanged = !keys.intersection(JournalSyncRecordType.attachmentContentKeys).isEmpty
                            attachmentMetaChanged = !attachmentContentChanged
                                || !keys.intersection(["displayName", "isThumbnail"]).isEmpty
                        }
                        if JournalSyncRecordType.directory.contains(entity) { namesAdded[uri] = id.uuidString }
                        if entity == JournalSyncRecordType.attachment {
                            if attachmentContentChanged {
                                added.append(.init(recordName: id.uuidString, recordType: entity, op: .save))
                            }
                            if attachmentMetaChanged {
                                added.append(.init(recordName: JournalSyncRecordType.metaName(for: id.uuidString),
                                                   recordType: JournalSyncRecordType.attachmentMeta, op: .save, metadataEdit: true))
                            }
                            continue
                        }
                        added.append(.init(recordName: id.uuidString, recordType: entity, op: .save, ownerOnly: ownerOnly, metadataEdit: metadataEdit))
                    case .delete:
                        if let id = change.tombstone?["id"] as? UUID {
                            added.append(.init(recordName: id.uuidString, recordType: entity, op: .delete))
                            if entity == JournalSyncRecordType.attachment {
                                added.append(.init(recordName: JournalSyncRecordType.metaName(for: id.uuidString),
                                                   recordType: JournalSyncRecordType.attachmentMeta, op: .delete))
                            }
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
                // Partial or asset-free saves never downgrade a content save; a
                // content save absorbs them (and will carry the file if it changed).
                let existingPartial = outbox[i].ownerOnly || outbox[i].metadataOnly || outbox[i].metadataEdit
                let incomingPartial = change.ownerOnly || change.metadataOnly || change.metadataEdit
                if existingPartial && !incomingPartial { outbox[i] = change }
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
    /// Value equality for Core Data attribute and to-one relationship values.
    static func equal(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil):
            if let n = (a ?? b) as? NSNull { _ = n; return true }
            return false
        case (let x as NSManagedObject, let y as NSManagedObject): return x.objectID == y.objectID
        case (let x as NSObject, let y as NSObject): return x.isEqual(y)
        default: return false
        }
    }

    static func install() -> NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: .NSManagedObjectContextWillSave, object: nil, queue: nil) { note in
            guard let ctx = note.object as? NSManagedObjectContext,
                  ctx.transactionAuthor != JournalSyncAuthor.sync,
                  ctx.transactionAuthor != JournalSyncAuthor.migration else { return }
            let now = Date()
            for object in ctx.insertedObjects.union(ctx.updatedObjects) {
                guard let name = object.entity.name, JournalSyncRecordType.stamped.contains(name) else { continue }
                if !object.isInserted {
                    // A key set to the value it already holds is not a change:
                    // drop such keys, and the whole update when nothing is left,
                    // so history never records an edit that did not happen.
                    let changes = object.changedValues()
                    let committed = object.committedValues(forKeys: Array(changes.keys))
                    let real = changes.filter { key, value in
                        !JournalUserEditStamp.equal(value, committed[key] as Any?)
                    }
                    if real.isEmpty { ctx.refresh(object, mergeChanges: false); continue }
                }
                let changed = Set(object.changedValues().keys)
                if object.isInserted || !changed.subtracting(JournalOwnership.ownershipOnlyKeys).isEmpty {
                    object.setValue(now, forKey: "userModifiedAt")
                }
            }
        }
    }
}
#endif
