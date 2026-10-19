//
//  JournalSavedListSync.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
//
//  SAVED LISTS ↔ CLOUDKIT (stage B).
//
//  Lists live in UserDefaults (`SavedListLibrary`), under the same owner
//  scope the Lists screen uses: K1, or "device" without it. They have no
//  persistent history, so changes are found by comparing each list's content
//  hash with the hash last sent or received. Every list is its own record,
//  keyed by its id, so two lists with the same name both survive. All writes
//  go through `SavedListLibrary.commit`, which never replaces a damaged
//  library and keeps entries it did not change.
//

#if SYNCTEST
import Foundation
import CloudKit
import CryptoKit

@MainActor
enum JournalSavedListSync {

    /// Mirrors `TasksManagerView.ownerScope`.
    static func currentScope() -> String {
        if let id = JournalOwnership.normalized(PersistenceController.shared.currentUserID) { return id }
        return JournalOwnerStoreMigration.listsNoOwnerScope
    }

    static func fingerprint(_ list: SavedList) -> String {
        // Sorted keys: the hash must not depend on the encoder's key order.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(list.items)) ?? Data()
        var hasher = SHA256()
        hasher.update(data: Data(list.name.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Lists changed or removed since the last exchange, as pending changes.
    /// Records the new hashes in the same write as the outbox entries. When
    /// the owner scope has changed since the last scan, nothing is treated as
    /// removed: the lists are looked up elsewhere, not gone.
    static func scan(store: JournalSyncStateStore, defaults: UserDefaults = .standard,
                     scope: String? = nil) -> [JournalSyncPendingChange] {
        let scope = scope ?? currentScope()
        guard case .lists(let lists) = SavedListLibrary.load(ownerScope: scope, defaults: defaults) else {
            store.log("Lists: library unreadable; nothing sent")
            return []
        }
        let scopeChanged = store.state.listScope != nil && store.state.listScope != scope
        let known = scopeChanged ? [:] : store.state.listFingerprints
        if scopeChanged { store.log("Lists: owner scope changed; no deletions inferred") }
        var pending: [JournalSyncPendingChange] = []
        var next: [String: String] = [:]
        for list in lists {
            let name = list.id.uuidString
            let print = fingerprint(list)
            next[name] = print
            if known[name] != print {
                pending.append(.init(recordName: name, recordType: JournalSyncRecordType.savedList, op: .save))
            }
        }
        for name in known.keys where next[name] == nil {
            pending.append(.init(recordName: name, recordType: JournalSyncRecordType.savedList, op: .delete))
        }
        guard !pending.isEmpty || scopeChanged || store.state.listScope == nil else { return [] }
        let ok = store.update { st in
            JournalChangeTracker.merge(pending, into: &st.outbox)
            st.listFingerprints = next
            st.listScope = scope
        }
        return ok ? pending : []
    }

    static func records(for names: [String], bases: [String: Data], defaults: UserDefaults = .standard,
                        scope: String? = nil) -> [String: CKRecord] {
        guard case .lists(let lists) = SavedListLibrary.load(ownerScope: scope ?? currentScope(), defaults: defaults) else { return [:] }
        let byName = Dictionary(lists.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [String: CKRecord] = [:]
        for name in names {
            guard let list = byName[name] else { continue }
            let base = bases[name].flatMap(JournalSyncStateStore.recordFromSystemFields)
            if let record = JournalRecordMapping.record(for: list, base: base) { out[name] = record }
        }
        return out
    }

    /// Writes server lists into the library: replaces by id or appends. A list
    /// with a pending local change keeps the local version (it will be sent).
    @discardableResult
    static func apply(_ records: [CKRecord], store: JournalSyncStateStore, defaults: UserDefaults = .standard,
                      scope: String? = nil, overridePending: Bool = false) -> Int {
        let incoming = records.compactMap(JournalRecordMapping.savedList(from:))
        guard !incoming.isEmpty else { return 0 }
        let scope = scope ?? currentScope()
        guard case .lists(let current) = SavedListLibrary.load(ownerScope: scope, defaults: defaults) else {
            store.log("Lists: library unreadable; \(incoming.count) incoming list(s) not written")
            return 0
        }
        let pending = Set(store.state.outbox.filter { $0.op == .save }.map(\.recordName))
        var updated = current
        var applied: [String: String] = [:]
        for var list in incoming {
            let name = list.id.uuidString
            if !overridePending, pending.contains(name) { continue }
            if let i = updated.firstIndex(where: { $0.id == list.id }) {
                list.sourceSendID = updated[i].sourceSendID
                updated[i] = list
            } else {
                updated.append(list)
            }
            applied[name] = fingerprint(list)
        }
        do {
            try SavedListLibrary.commit(snapshot: current, updated: updated, ownerScope: scope, defaults: defaults)
        } catch {
            store.log("Lists: write failed (\(error.localizedDescription)); nothing replaced")
            return 0
        }
        store.update { st in
            st.listFingerprints.merge(applied) { _, new in new }
            for r in records { st.lastKnownRecords[r.recordID.recordName] = JournalSyncStateStore.encodeSystemFields(r) }
            if overridePending { st.outbox.removeAll { applied[$0.recordName] != nil && $0.op == .save } }
        }
        return applied.count
    }

    @discardableResult
    static func applyDeletions(_ names: [String], store: JournalSyncStateStore, defaults: UserDefaults = .standard,
                               scope: String? = nil) -> Int {
        guard !names.isEmpty else { return 0 }
        let scope = scope ?? currentScope()
        guard case .lists(let current) = SavedListLibrary.load(ownerScope: scope, defaults: defaults) else { return 0 }
        let gone = Set(names)
        let updated = current.filter { !gone.contains($0.id.uuidString) }
        if updated.count != current.count {
            do { try SavedListLibrary.commit(snapshot: current, updated: updated, ownerScope: scope, defaults: defaults) }
            catch { store.log("Lists: delete failed (\(error.localizedDescription))"); return 0 }
        }
        store.update { st in
            for name in names {
                st.listFingerprints.removeValue(forKey: name)
                st.lastKnownRecords.removeValue(forKey: name)
                st.outbox.removeAll { $0.recordName == name }
            }
        }
        return current.count - updated.count
    }
}
#endif
