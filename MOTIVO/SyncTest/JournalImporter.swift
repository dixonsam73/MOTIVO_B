//
//  JournalImporter.swift
//  MOTIVO — private iCloud sync. Compiled in every configuration; nothing
//  here runs until the person turns sync on (see JournalSyncCoordinator).
//
//  SERVER RECORDS → CORE DATA, SEPARATE FROM THE ENGINE SO IT CAN BE TESTED
//  WITHOUT CLOUDKIT.
//
//  Content follows the trial conflict rule (`JournalConflictRule`, newest
//  user edit wins). Ownership does NOT: it is merged on its own
//  (`JournalOwnership.mergedOwner`), so an owner-only change never beats a
//  notes edit and a notes edit never erases an owner. When the merged owner
//  differs from what the server holds, the entry is queued to send it.
//
//  `Attachment.ownerUserID` is not synced; it follows its session locally.
//  Custom instruments and activities arrive without an owner and are stamped
//  with this install's K2; duplicates by normalised name collapse to the
//  smallest id on every device.
//
//  Profile instruments (`Instrument`, what `Session.instrument` points at)
//  sync by id and name. A session's link resolves by id, then by a recorded
//  alias, then by name against this device's instruments, and only then
//  creates the instrument under the local profile. Two devices that each
//  had "Cello" before they met keep their own rows; an alias maps the other
//  device's id to this one's, so nothing is deleted or re-keyed and the
//  per-instrument list settings keep working.
//

import Foundation
import CloudKit
import CoreData

/// What the importer asks the engine to send.
protocol JournalSendQueue: AnyObject {
    func enqueueSave(_ recordName: String, recordType: String, ownerOnly: Bool)
    func enqueueDelete(_ recordName: String, recordType: String)
    func removePendingSave(_ recordName: String)
}

final class JournalImporter {
    let context: NSManagedObjectContext
    let store: JournalSyncStateStore
    weak var queue: JournalSendQueue?
    var log: (String) -> Void = { _ in }
    /// This install's K2 (`PersistenceController.ownerIDForCustoms`), read once
    /// on the main actor by the owner of this importer; it never changes.
    let customOwner: String?
    /// Stage F: the viewer scope favourites are keyed by, refreshed by the
    /// engine on the main actor before each fetch cycle.
    var viewerScope: () -> String = { "unknown" }

    private func applySideStores(_ record: CKRecord, id: UUID) {
        switch record.recordType {
        case JournalSyncRecordType.session:
            JournalMetadataFields.applySession(isSaved: record[JournalMetadataKeys.isSaved] as? NSNumber, id: id, viewerScope: viewerScope())
        case JournalSyncRecordType.attachment, JournalSyncRecordType.attachmentMeta:
            let kind = record["kind"] as? String ?? fetch(entity: JournalSyncRecordType.attachment, id: id)?.value(forKey: "kind") as? String
            JournalMetadataFields.applyAttachment(isPrivate: record[JournalMetadataKeys.isPrivate] as? NSNumber,
                                                  pages: record[JournalMetadataKeys.selectedPages] as? String,
                                                  displayName: record["displayName"] as? String,
                                                  kind: kind, id: id)
        default: break
        }
    }

    /// Stage G: a meta record for this attachment has been seen (or is held),
    /// so the legacy metadata fields on its Attachment record are stale.
    private func metaKnown(_ attachmentName: String) -> Bool {
        let meta = JournalSyncRecordType.metaName(for: attachmentName)
        return store.state.lastKnownRecords[meta] != nil || store.state.awaitingMeta[meta] != nil || knownAfterSave[meta] != nil
    }

    // MARK: Attachment metadata records (stage G)

    /// Applies a meta record to its attachment, or holds it until the
    /// attachment arrives. Conflicts use the attachment row's stamp.
    @discardableResult
    func importAttachmentMeta(_ record: CKRecord) -> Bool {
        let name = record.recordID.recordName
        guard let attachmentName = JournalSyncRecordType.attachmentName(fromMeta: name),
              let id = UUID(uuidString: attachmentName) else { return false }
        guard let attachment = freshRow(entity: JournalSyncRecordType.attachment, id: id) else {
            if let data = JournalSyncStateStore.encodeWholeRecord(record) {
                store.update { $0.awaitingMeta[name] = data }
                log("Holding metadata \(name) until its attachment arrives")
            }
            return false
        }
        if let pending = pendingSave(name), !pending.metadataOnly {
            let local = attachment.value(forKey: "userModifiedAt") as? Date
            let server = JournalRecordMapping.userModifiedAt(of: record)
            if JournalConflictRule.decide(localUserModifiedAt: local, serverUserModifiedAt: server) == .local {
                noteKnown(record)
                recordConflict(record, winner: .local, local: attachment)
                return false
            }
            guard recordConflict(record, winner: .server, local: attachment) else { return false }
            queue?.removePendingSave(name)
        } else if pendingSave(name)?.metadataOnly == true {
            // The transition's copy meets a real one: the server's stands.
            queue?.removePendingSave(name)
        }
        JournalRecordMapping.applyMeta(record, to: attachment)
        applySideStores(record, id: id)
        noteKnownAfterSave(record)
        store.update { $0.awaitingMeta.removeValue(forKey: name) }
        appliedInBatch.insert(name)
        return true
    }

    private func applyHeldMeta(for attachmentName: String) {
        let name = JournalSyncRecordType.metaName(for: attachmentName)
        guard let data = store.state.awaitingMeta[name], let record = JournalSyncStateStore.decodeWholeRecord(data) else { return }
        if importAttachmentMeta(record) { log("Applied held metadata \(name)") }
    }

    init(context: NSManagedObjectContext, store: JournalSyncStateStore, customOwner: String?) {
        self.context = context
        self.store = store
        self.customOwner = customOwner
    }

    struct Summary { var received = 0; var bytes: Int64 = 0; var customs = 0
        /// H3: the Core Data save of this batch failed and was rolled back; the
        /// caller keeps its zone token so the batch is fetched again.
        var saveFailed = false
        var echoes = 0
        /// R6: record names whose row reached the store in this batch.
        var applied: Set<String> = [] }

    /// R3 seam: the server change tag of a record (tests assign their own).
    var changeTag: (CKRecord) -> String? = { $0.recordChangeTag }
    /// Names applied in the current batch, reported once the save succeeded.
    private var appliedInBatch: Set<String> = []

    /// Remember the server copy this device now holds (its system fields for
    /// the next send's change tag, and its change tag for the echo filter).
    /// Immediate: used where nothing is applied (the local copy won), so the
    /// resend carries the server's change tag.
    func noteKnown(_ record: CKRecord) {
        let name = record.recordID.recordName
        let tag = changeTag(record)
        store.update { st in
            st.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record)
            st.knownChangeTags[name] = tag
        }
    }

    /// R3 (2026-11-03): where the server copy is APPLIED, the knowledge is
    /// written only once the batch's Core Data save succeeded; a rolled-back
    /// save leaves the record unknown, so the retry imports it instead of
    /// skipping it as an echo.
    private var knownAfterSave: [String: (Data, String?)] = [:]
    private func noteKnownAfterSave(_ record: CKRecord) {
        knownAfterSave[record.recordID.recordName] = (JournalSyncStateStore.encodeSystemFields(record), changeTag(record))
    }
    /// R7 (2026-11-03): what else becomes true only with the save — the hash
    /// of a media file put in place for a row, and the files that row no
    /// longer needs (the previous file of a replaced attachment, a held copy
    /// once linked). A rolled-back save keeps them.
    private var hashesAfterSave: [String: String] = [:]
    private var removeAfterSave: [URL] = []
    /// R12 (2026-11-03): a replacement written over the row's own file keeps
    /// the previous bytes beside it until the save; a rolled-back save puts
    /// them back.
    private var restoreOnRollback: [(previous: URL, destination: URL)] = []
    private func commitKnown() {
        let pending = knownAfterSave, hashes = hashesAfterSave, removals = removeAfterSave
        knownAfterSave.removeAll(); hashesAfterSave.removeAll(); removeAfterSave.removeAll(); restoreOnRollback.removeAll()
        if !pending.isEmpty || !hashes.isEmpty {
            store.update { st in
                for (name, entry) in pending { st.lastKnownRecords[name] = entry.0; st.knownChangeTags[name] = entry.1 }
                for (name, hash) in hashes { st.assetHashes[name] = hash; st.fileStampCache.removeValue(forKey: name) }
            }
        }
        for url in removals { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: Modifications

    /// Imports Session, Attachment and custom-row records (not SavedList).
    /// Must be called on the context's queue (`performAndWait`).
    func importModifications(_ incoming: [CKRecord]) -> Summary {
        var summary = Summary()
        // B5 (2026-11-03): a fetch that was in flight when the person removed
        // Études data from this device must not put the journal back.
        let st = store.state
        if st.localRemovalInProgress || st.localCopyRemoved {
            log("Import refused: \(incoming.count) record(s) arrived \(st.localRemovalInProgress ? "during" : "after") a local removal; nothing applied")
            return summary
        }
        // B1 (2026-11-03): this device's own accepted writes come back through
        // the records-only catch-up with the change tag it already holds;
        // applying them would overwrite an edit made since. Skipped unless a
        // save is pending (then the conflict rule decides).
        let pendingNames = Set(st.outbox.filter { $0.op == .save }.map(\.recordName))
        let records = incoming.filter { record in
            let name = record.recordID.recordName
            let tag = changeTag(record)
            let echo = !pendingNames.contains(name) && tag != nil && st.knownChangeTags[name] == tag
            if echo { summary.echoes += 1 }
            return !echo
        }
        if summary.echoes > 0 { log("Own-write echo: \(summary.echoes) record(s) already held, skipped") }
        let sessions = records.filter { $0.recordType == JournalSyncRecordType.session }
        let attachments = records.filter { $0.recordType == JournalSyncRecordType.attachment }
        let metas = records.filter { $0.recordType == JournalSyncRecordType.attachmentMeta }
        let customs = records.filter { JournalSyncRecordType.customs.contains($0.recordType) }
        let instruments = records.filter { $0.recordType == JournalSyncRecordType.instrument }
        // Instruments first, so sessions and custom rows resolve them by id.
        var importedInstruments: [NSManagedObject] = []
        for record in instruments { if let o = importInstrument(record) { importedInstruments.append(o); summary.received += 1 } }
        appliedInBatch.removeAll()
        for record in sessions { if importSession(record) { summary.received += 1; appliedInBatch.insert(record.recordID.recordName) } }
        for record in attachments {
            let outcome = importAttachment(record)
            if outcome.imported { summary.received += 1; appliedInBatch.insert(record.recordID.recordName) }
            summary.bytes += outcome.bytes
        }
        for record in metas { if importAttachmentMeta(record) { summary.received += 1 } }
        // Any held attachment whose session has now arrived.
        for (name, held) in store.state.awaitingParent {
            guard let sid = UUID(uuidString: held.sessionRecordName),
                  fetch(entity: JournalSyncRecordType.session, id: sid) != nil,
                  let record = JournalSyncStateStore.decodeWholeRecord(held.recordData) else { continue }
            let outcome = importAttachment(record, heldFile: held.heldFilePath)
            if outcome.imported {
                summary.received += 1; summary.bytes += outcome.bytes
                store.update { $0.awaitingParent.removeValue(forKey: name) }
                log("Linked held attachment \(name) to its session")
            }
        }
        var importedCustoms: [NSManagedObject] = []
        for record in customs {
            if let object = importCustom(record) { importedCustoms.append(object); summary.received += 1; summary.customs += 1 }
        }
        if save() { summary.applied = appliedInBatch }
        else { summary.saveFailed = true; summary.received = 0; summary.bytes = 0 }
        appliedInBatch.removeAll()
        if !importedInstruments.isEmpty {
            store.update { st in
                for object in importedInstruments where !object.objectID.isTemporaryID {
                    if let id = object.value(forKey: "id") as? UUID {
                        st.customRecordNames[object.objectID.uriRepresentation().absoluteString] = id.uuidString
                    }
                }
            }
        }
        if !importedCustoms.isEmpty {
            store.update { st in
                for object in importedCustoms where !object.objectID.isTemporaryID {
                    if let id = object.value(forKey: "id") as? UUID {
                        st.customRecordNames[object.objectID.uriRepresentation().absoluteString] = id.uuidString
                    }
                }
            }
            dedupeCustoms()
        }
        return summary
    }

    /// Returns true when the server record was applied.
    func importSession(_ record: CKRecord) -> Bool {
        let name = record.recordID.recordName
        guard let id = UUID(uuidString: name) else { return false }
        let existing = freshRow(entity: JournalSyncRecordType.session, id: id)
        let localOwner = existing?.value(forKey: "ownerUserID") as? String
        let serverOwner = record["ownerUserID"] as? String
        if let existing, pendingSave(name) == nil, !keepsNewerLocal(existing, over: record, type: JournalSyncRecordType.session) {
            return false
        }
        if existing != nil, let pending = pendingSave(name), pending.metadataOnly {
            // A migrated row meets its server copy: dropped only when that copy
            // already carries metadata fields; an older build's copy has less
            // information, so ours stays queued and goes on top of its tag.
            if JournalMetadataFields.recordCarriesMetadata(record) { queue?.removePendingSave(name) }
        } else if let existing, let pending = pendingSave(name), !pending.ownerOnly {
            let local = existing.value(forKey: "userModifiedAt") as? Date
            let server = JournalRecordMapping.userModifiedAt(of: record)
            if JournalConflictRule.decide(localUserModifiedAt: local, serverUserModifiedAt: server) == .local {
                // Keep our content; take the server's owner if we have none, so
                // the resend carries both. Remember the server copy's change tag.
                absorbOwner(serverOwner, into: existing, localOwner: localOwner, recordName: name)
                noteKnown(record)
                recordConflict(record, winner: .local, local: existing)
                return false
            }
            guard recordConflict(record, winner: .server, local: existing) else { return false }
            queue?.removePendingSave(name)
        } else if existing != nil, pendingSave(name)?.ownerOnly == true {
            // Only the owner key is pending here: the server's content is
            // simply newer knowledge, not a conflict. The owner is merged below
            // and re-sent if the server lacks it.
            queue?.removePendingSave(name)
        }
        let object = existing ?? NSEntityDescription.insertNewObject(forEntityName: JournalSyncRecordType.session, into: context)
        _ = JournalRecordMapping.apply(record, to: object)
        applySideStores(record, id: id)
        let link = JournalRecordMapping.instrumentLink(of: record)
        object.setValue(resolveInstrument(recordName: link.recordName, name: link.name), forKey: "instrument")
        let merged = JournalOwnership.mergedOwner(local: localOwner, server: serverOwner)
        object.setValue(merged, forKey: "ownerUserID")
        if let l = JournalOwnership.normalized(localOwner), let s = JournalOwnership.normalized(serverOwner), l != s {
            log("Owner differs on \(name): kept this device's owner; reported")
            store.update { $0.ownerConflicts += 1 }
        }
        followSessionOwner(object)
        noteKnownAfterSave(record)
        if JournalOwnership.normalized(merged) != JournalOwnership.normalized(serverOwner) {
            // The server lost an owner this device holds (an edit from a device
            // that had not yet seen the ownership): send it back, owner only.
            queue?.enqueueSave(name, recordType: JournalSyncRecordType.session, ownerOnly: true)
            log("Kept owner on \(name) over an ownerless server copy; resending the owner")
        }
        return true
    }

    /// Local content won a conflict: carry the server's owner if we have none.
    private func absorbOwner(_ serverOwner: String?, into object: NSManagedObject, localOwner: String?, recordName: String) {
        let merged = JournalOwnership.mergedOwner(local: localOwner, server: serverOwner)
        guard JournalOwnership.normalized(merged) != JournalOwnership.normalized(localOwner) else { return }
        object.setValue(merged, forKey: "ownerUserID")
        followSessionOwner(object)
        log("Took owner from the server copy of \(recordName) while keeping local content")
    }

    /// Attachments carry their session's owner locally (not synced).
    private func followSessionOwner(_ session: NSManagedObject) {
        let owner = session.value(forKey: "ownerUserID") as? String
        for case let att as NSManagedObject in (session.value(forKey: "attachments") as? Set<NSManagedObject>) ?? [] {
            if (att.value(forKey: "ownerUserID") as? String) != owner { att.setValue(owner, forKey: "ownerUserID") }
        }
    }

    func importAttachment(_ record: CKRecord, heldFile: String? = nil) -> (imported: Bool, bytes: Int64) {
        let name = record.recordID.recordName
        guard let id = UUID(uuidString: name) else { return (false, 0) }
        guard let sidName = JournalRecordMapping.sessionRecordName(of: record), let sid = UUID(uuidString: sidName) else {
            log("Attachment \(name) has no session reference; skipped")
            return (false, 0)
        }
        guard let session = fetch(entity: JournalSyncRecordType.session, id: sid) else {
            hold(record, sessionRecordName: sidName)
            return (false, 0)
        }
        let existing = freshRow(entity: JournalSyncRecordType.attachment, id: id)
        // B6 (2026-11-03): a record the server holds a file for, arriving
        // without it (a failed per-record fetch), is not a row yet; the
        // catch-up holds it by name and fetches it again. A sender that had
        // no file at all (no hash) still delivers its row.
        let serverHashNow = record[JournalRecordMapping.fileHashKey] as? String ?? ""
        let carriesFile = heldFile != nil || (record[JournalRecordMapping.assetKey] as? CKAsset)?.fileURL != nil
        if existing == nil, !carriesFile, !serverHashNow.isEmpty {
            log("Attachment \(name) arrived without its file although the server holds one; not imported until the file is fetched")
            return (false, 0)
        }
        if let existing, pendingSave(name) == nil, !keepsNewerLocal(existing, over: record, type: JournalSyncRecordType.attachment) {
            return (false, 0)
        }
        // The conflict is decided first; nothing is applied, dropped or
        // deleted until the file is in place.
        var dropsTransitionCopy = false
        var serverWinsPendingEdit = false
        if existing != nil, let pending = pendingSave(name), pending.metadataOnly {
            dropsTransitionCopy = JournalMetadataFields.recordCarriesMetadata(record)
        } else if let existing, localChangePending(name) {
            let local = existing.value(forKey: "userModifiedAt") as? Date
            let server = JournalRecordMapping.userModifiedAt(of: record)
            if JournalConflictRule.decide(localUserModifiedAt: local, serverUserModifiedAt: server) == .local {
                noteKnown(record)
                recordConflict(record, winner: .local, local: existing)
                return (false, 0)
            }
            serverWinsPendingEdit = true
        }

        // Media. CloudKit downloads the asset of every fetched attachment record
        // (transport; counted as such). It is written into place only when this
        // device has no usable file, or when the server's hash says the file was
        // replaced on the other device. The device that created the attachment
        // otherwise keeps its own file (named <base>-<id>.<ext> by staging).
        // R7 (2026-11-03): the file is put in place BEFORE the row is touched,
        // through a staging copy, so a failed copy changes nothing: the row, its
        // previous file, the known hash and any hold stay as they were and the
        // record is fetched again. The previous file goes, and the new hash is
        // recorded, only with the row's save.
        var bytes: Int64 = 0
        let ext = (record[JournalRecordMapping.fileExtKey] as? String) ?? ""
        let destination = JournalRecordMapping.materialisedURL(recordName: name, ext: ext)
        let existingFile = AttachmentPathResolver.resolve(existing?.value(forKey: "fileURL") as? String)
        let sourceURL = heldFile.map { URL(fileURLWithPath: $0) } ?? (record[JournalRecordMapping.assetKey] as? CKAsset)?.fileURL
        let serverHash = record[JournalRecordMapping.fileHashKey] as? String
        let knownHash = store.state.assetHashes[name]
        if heldFile == nil, let sourceURL, let size = JournalAssetHash.stamp(of: sourceURL)?.size {
            store.update { $0.assetBytesDownloaded += size }
        }
        // C-197 (2026-11-13): the bytes actually here. Where no hash was ever
        // exchanged (sync turned on over a journal iCloud already holds) the
        // file here is compared by its own hash: equal, the server's hash is
        // recorded for it; different, it is REPLACED like any other, never
        // recorded under the server's hash while the old bytes stay.
        var localHash: String?
        if let existingFile, let cached = JournalAssetHash.cachedHash(of: existingFile, cache: store.state.fileStampCache[name]) {
            localHash = cached.hash
            store.update { $0.fileStampCache[name] = cached.entry }
        }
        let replaced = existingFile != nil && serverHash != nil
            && (knownHash == nil ? (localHash != nil && serverHash != localHash) : serverHash != knownHash)
        let sourceReady = sourceURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        func holdByName(_ why: String) -> (imported: Bool, bytes: Int64) {
            if heldFile == nil {
                store.update { st in
                    let before = st.awaitingMedia.count
                    st.awaitingMedia = JournalMediaHold.adding([name], to: st.awaitingMedia)
                    st.mediaDownloadsHeld += st.awaitingMedia.count - before
                }
            }
            log("Attachment \(name) not imported: \(why); held by name and fetched again")
            return (false, 0)
        }
        if replaced, !sourceReady {
            // The server holds a different file and it is not here yet: nothing
            // is applied, and the row keeps the file and the hash it has.
            return holdByName("the server's file differs and did not come with the record")
        }
        // Bytes the server never held (never exchanged, or changed here and
        // not sent) are kept before the server's replace them.
        if replaced, let existingFile, let localHash, localHash != knownHash, !AttachmentStore.isLibraryScoreFile(existingFile) {
            guard keepDisplacedMedia(existingFile, hash: localHash, record: record, local: existing) else {
                return holdByName("this device's own file could not be kept first")
            }
        }
        var fileURLAfterCopy: String?
        var hashAfterSave: String?
        var previousFile: URL?
        // R12: when the row's own file IS the destination, its bytes are kept
        // beside it (named by the hash they belong to) until the row is saved.
        var keptInPlace: URL?
        if existingFile == nil || replaced {
            if let sourceURL, FileManager.default.fileExists(atPath: sourceURL.path) {
                let incoming = JournalAssetHash.stamp(of: sourceURL)?.size ?? 0
                let present = JournalAssetHash.stamp(of: destination)?.size
                if present != incoming || replaced {
                    let previous: URL? = (replaced && existingFile?.path == destination.path && knownHash != nil)
                        ? Self.previousURL(for: destination, hash: knownHash ?? "") : nil
                    guard materialise(sourceURL, at: destination, keeping: previous) else {
                        // R11: the record waits by name, like a file that could
                        // not be fetched, and is fetched again with the next
                        // catch-up or release; a hold that cannot be written
                        // leaves the batch incomplete (H1), so the token is kept.
                        return holdByName(replaced ? "the previous file is kept" : "no file in place")
                    }
                    keptInPlace = previous
                    bytes = incoming
                }
                if replaced, let old = existingFile, old.path != destination.path {
                    // Never a library PDF (C-138): a score attached from the library is its file.
                    if !AttachmentStore.isLibraryScoreFile(old) { previousFile = old }
                    log("Replaced media for \(name) from the other device")
                }
                hashAfterSave = serverHash ?? JournalAssetHash.hash(of: destination)
            } else if existingFile == nil {
                log("Attachment \(name) arrived without a file")
            }
            // Point at the materialised path even without a file, so the
            // resolver's filename match finds it once a later fetch supplies it.
            fileURLAfterCopy = destination.path
        } else if knownHash == nil, let serverHash, localHash == serverHash {
            // The same bytes, never exchanged before: the server's hash is this file's.
            store.update { $0.assetHashes[name] = serverHash }
        }

        if serverWinsPendingEdit, let existing {
            guard recordConflict(record, winner: .server, local: existing) else {
                if let keptInPlace { Self.restore(previous: keptInPlace, to: destination) }
                return (false, 0)
            }
            queue?.removePendingSave(name)
        }
        if dropsTransitionCopy { queue?.removePendingSave(name) }
        let object = existing ?? NSEntityDescription.insertNewObject(forEntityName: JournalSyncRecordType.attachment, into: context)
        // Legacy metadata on the content record counts only until this
        // attachment has a meta record (the stage G transition).
        let legacy = !metaKnown(name)
        _ = JournalRecordMapping.apply(record, to: object, legacyMetadata: legacy)
        if legacy { applySideStores(record, id: id) }
        object.setValue(session, forKey: "session")
        object.setValue(session.value(forKey: "ownerUserID") as? String, forKey: "ownerUserID")
        if let fileURLAfterCopy { object.setValue(fileURLAfterCopy, forKey: "fileURL") }
        if let hashAfterSave { hashesAfterSave[name] = hashAfterSave }
        if let previousFile { removeAfterSave.append(previousFile) }
        if let keptInPlace { removeAfterSave.append(keptInPlace); restoreOnRollback.append((keptInPlace, destination)) }
        if heldFile != nil, let sourceURL { removeAfterSave.append(sourceURL) }
        noteKnownAfterSave(record)
        applyHeldMeta(for: name)
        return (true, bytes)
    }

    /// R7: copies beside the destination and moves into place, so a copy that
    /// fails leaves whatever was at the destination as it was. R12: with
    /// `keeping`, the bytes at the destination are moved there first (an
    /// earlier attempt's copy of the same hash is kept as it is; any other
    /// stale copy is removed), so a rolled-back save can put them back.
    private func materialise(_ source: URL, at destination: URL, keeping previous: URL?) -> Bool {
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).part")
        try? fm.removeItem(at: staging)
        do {
            try fm.copyItem(at: source, to: staging)
            if let previous {
                let dir = destination.deletingLastPathComponent(), prefix = destination.lastPathComponent + Self.previousInfix
                for stale in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where stale.hasPrefix(prefix) && stale != previous.lastPathComponent {
                    try? fm.removeItem(at: dir.appendingPathComponent(stale))
                }
                if fm.fileExists(atPath: destination.path) {
                    if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: destination) }
                    else { try fm.moveItem(at: destination, to: previous) }
                }
            } else if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: staging, to: destination)
            return true
        } catch {
            log("Could not materialise \(destination.lastPathComponent): \(error.localizedDescription)")
            try? fm.removeItem(at: staging)
            return false
        }
    }

    private static let previousInfix = ".previous-"
    static func previousURL(for destination: URL, hash: String) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(destination.lastPathComponent + previousInfix + String(hash.prefix(12)))
    }

    /// Puts the kept bytes back after a rolled-back save or a refused conflict.
    static func restore(previous: URL, to destination: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: previous.path) else { return }
        try? fm.removeItem(at: destination)
        try? fm.moveItem(at: previous, to: destination)
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

    // MARK: Custom instruments and activities

    /// Applies a custom row and stamps this install's K2. Server wins a
    /// conflict (custom rows carry no edit stamp; ties go to the server).
    private func importCustom(_ record: CKRecord) -> NSManagedObject? {
        let name = record.recordID.recordName
        guard let id = UUID(uuidString: name), let owner = customOwner else { return nil }
        let existing = fetch(entity: record.recordType, id: id)
        if let existing, localChangePending(name) {
            keepDisplacedName(of: existing, against: record)
            log("Custom \(record.recordType) \(name): server copy applied over a pending local change")
            queue?.removePendingSave(name)
        }
        let object = existing ?? NSEntityDescription.insertNewObject(forEntityName: record.recordType, into: context)
        guard JournalRecordMapping.apply(record, to: object) else { return nil }
        object.setValue(owner, forKey: "ownerUserID")
        if record.recordType == JournalSyncRecordType.userInstrument {
            let link = JournalRecordMapping.instrumentLink(of: record)
            if let core = resolveInstrument(recordName: link.recordName, name: link.name) { object.setValue(core, forKey: "coreInstrument") }
        }
        noteKnownAfterSave(record) // R8: known only once the batch's save succeeds
        return object
    }

    // MARK: Profile instruments

    /// Applies an Instrument record: by id, else by alias, else by name (an
    /// alias is recorded and no row is made), else a new row under the local
    /// profile with the record's id.
    private func importInstrument(_ record: CKRecord) -> NSManagedObject? {
        let name = record.recordID.recordName
        guard UUID(uuidString: name) != nil, let instrumentName = record["name"] as? String else { return nil }
        let object = resolveInstrument(recordName: name, name: instrumentName, applyName: true)
        noteKnownAfterSave(record) // R8: known only once the batch's save succeeds
        return object
    }

    /// The local Instrument for a link. With `applyName` the resolved row takes
    /// the record's name (a rename on the other device); otherwise the name is
    /// only used to find or create the row.
    func resolveInstrument(recordName: String?, name: String?, applyName: Bool = false) -> NSManagedObject? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let recordName, let id = UUID(uuidString: recordName) {
            if let byID = fetch(entity: JournalSyncRecordType.instrument, id: id) {
                if applyName, !trimmed.isEmpty, (byID.value(forKey: "name") as? String) != trimmed { byID.setValue(trimmed, forKey: "name") }
                return byID
            }
            if let alias = store.state.instrumentAliases[recordName], let aliasID = UUID(uuidString: alias),
               let byAlias = fetch(entity: JournalSyncRecordType.instrument, id: aliasID) {
                if applyName, !trimmed.isEmpty, (byAlias.value(forKey: "name") as? String) != trimmed { byAlias.setValue(trimmed, forKey: "name") }
                return byAlias
            }
        }
        guard !trimmed.isEmpty else { return nil }
        if let byName = instrument(named: trimmed) {
            if let recordName, let localID = byName.value(forKey: "id") as? UUID, localID.uuidString != recordName {
                store.update { $0.instrumentAliases[recordName] = localID.uuidString }
                log("Instrument \"\(trimmed)\" exists here as \(localID.uuidString.prefix(8))…; aliasing \(recordName.prefix(8))… to it")
            }
            return byName
        }
        let created = NSEntityDescription.insertNewObject(forEntityName: JournalSyncRecordType.instrument, into: context)
        created.setValue(recordName.flatMap(UUID.init(uuidString:)) ?? UUID(), forKey: "id")
        created.setValue(trimmed, forKey: "name")
        created.setValue(localProfile(), forKey: "profile")
        log("Created instrument \"\(trimmed)\" from the journal")
        return created
    }

    func instrument(named name: String) -> NSManagedObject? {
        let wanted = PersistenceController.normalized(name)
        let request = NSFetchRequest<NSManagedObject>(entityName: JournalSyncRecordType.instrument)
        let rows = (try? context.fetch(request)) ?? []
        return rows.first { PersistenceController.normalized($0.value(forKey: "name") as? String ?? "") == wanted }
    }

    private func localProfile() -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Profile")
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Collapses custom rows of this install that share a normalised name to
    /// the smallest id, keeping the other rows' settings where the winner has
    /// none. The losers are deleted here and on the server; every device picks
    /// the same winner, so no row is lost or bounced between devices.
    func dedupeCustoms() {
        guard let owner = customOwner else { return }
        var deletes: [(String, String)] = []
        var saves: [(String, String)] = []
        for entity in [JournalSyncRecordType.userInstrument, JournalSyncRecordType.userActivity] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.predicate = NSPredicate(format: "ownerUserID == %@", owner)
            let rows = (try? context.fetch(request)) ?? []
            let groups = Dictionary(grouping: rows) { row -> String in
                (row.value(forKey: "normalizedName") as? String)
                    ?? PersistenceController.normalized(row.value(forKey: "displayName") as? String ?? "")
            }
            for (_, group) in groups where group.count > 1 {
                let ids = group.compactMap { $0.value(forKey: "id") as? UUID }
                guard let winnerID = JournalOwnership.dedupeWinner(ids),
                      let winner = group.first(where: { ($0.value(forKey: "id") as? UUID) == winnerID }) else { continue }
                var changed = false
                for loser in group where loser !== winner {
                    if entity == JournalSyncRecordType.userInstrument {
                        if (winner.value(forKey: "displayOrder") as? Int16 ?? 0) == 0,
                           let order = loser.value(forKey: "displayOrder") as? Int16, order != 0 {
                            winner.setValue(order, forKey: "displayOrder"); changed = true
                        }
                        let wVisible = winner.value(forKey: "isVisibleOnProfile") as? Bool ?? true
                        let lVisible = loser.value(forKey: "isVisibleOnProfile") as? Bool ?? true
                        if !wVisible && lVisible { winner.setValue(true, forKey: "isVisibleOnProfile"); changed = true }
                        if winner.value(forKey: "coreInstrument") == nil, let core = loser.value(forKey: "coreInstrument") {
                            winner.setValue(core, forKey: "coreInstrument")
                        }
                    }
                    if let lid = loser.value(forKey: "id") as? UUID { deletes.append((lid.uuidString, entity)) }
                    let uri = loser.objectID.uriRepresentation().absoluteString
                    store.update { $0.customRecordNames.removeValue(forKey: uri) }
                    context.delete(loser)
                }
                if changed { saves.append((winnerID.uuidString, entity)) }
                log("Merged \(group.count) \(entity) rows named \"\(winner.value(forKey: "displayName") as? String ?? "")\" into \(winnerID.uuidString.prefix(8))…")
            }
        }
        save()
        for (name, type) in saves { queue?.enqueueSave(name, recordType: type, ownerOnly: false) }
        for (name, type) in deletes { queue?.enqueueDelete(name, recordType: type) }
    }

    // MARK: Deletions

    /// Returns false when a deletion was NOT applied because the content it
    /// would destroy could not be kept first (C-197); the caller then leaves
    /// the batch incomplete, so it is fetched again.
    @discardableResult
    func importDeletions(_ deletions: [(CKRecord.ID, CKRecord.RecordType)]) -> Bool {
        // C-197 (2026-11-13): in the FIRST merge only (no complete fetch yet),
        // a deletion that reaches a row this device has not sent would destroy
        // the only copy of it. The entry, its attachments' details and their
        // files are kept first, listed on Displaced by sync with Restore; if
        // that fails, the row is not deleted. Afterwards a deletion is an
        // ordinary synced deletion, as before. Sessions first, so an entry
        // deleted with its attachments is kept as one.
        let initialMerge = !store.state.initialFetchComplete
        var complete = true
        var notDeleted = Set<UUID>()
        let ordered = deletions.filter { $0.1 == JournalSyncRecordType.session } + deletions.filter { $0.1 != JournalSyncRecordType.session }
        for (recordID, type) in ordered where type != JournalSyncRecordType.savedList {
            if type == JournalSyncRecordType.attachmentMeta {
                // The attachment's own deletion removes the row; its meta just stops being known.
                if let attachmentName = JournalSyncRecordType.attachmentName(fromMeta: recordID.recordName), let aid = UUID(uuidString: attachmentName),
                   notDeleted.contains(aid) { continue }
                store.update {
                    $0.lastKnownRecords.removeValue(forKey: recordID.recordName)
                    $0.awaitingMeta.removeValue(forKey: recordID.recordName)
                    $0.outbox.removeAll { $0.recordName == recordID.recordName }
                }
                continue
            }
            guard let id = UUID(uuidString: recordID.recordName) else { continue }
            if let object = fetch(entity: type, id: id) {
                if initialMerge, type == JournalSyncRecordType.session || type == JournalSyncRecordType.attachment {
                    let parent = (type == JournalSyncRecordType.attachment ? object.value(forKey: "session") as? NSManagedObject : nil)?.value(forKey: "id") as? UUID
                    if parent.map(notDeleted.contains) ?? false || (hasUnsentContent(object, type: type) && !keepBeforeDeletion(object, type: type)) {
                        log("Deletion of \(recordID.recordName.prefix(8))… not applied: this device's copy could not be kept first; fetched again")
                        notDeleted.insert(id)
                        if type == JournalSyncRecordType.session {
                            for case let att as NSManagedObject in (object.value(forKey: "attachments") as? Set<NSManagedObject>) ?? [] {
                                if let aid = att.value(forKey: "id") as? UUID { notDeleted.insert(aid) }
                            }
                        }
                        complete = false
                        continue
                    }
                }
                if type == JournalSyncRecordType.session {
                    for case let att as NSManagedObject in (object.value(forKey: "attachments") as? Set<NSManagedObject>) ?? [] {
                        removeFile(of: att)
                    }
                } else if type == JournalSyncRecordType.attachment {
                    removeFile(of: object)
                }
                // An Instrument deleted on the other device goes here only when
                // it is the same row (same id); an aliased row of this device's
                // own stays, and its alias is dropped.
                let uri = object.objectID.uriRepresentation().absoluteString
                context.delete(object)
                store.update { $0.customRecordNames.removeValue(forKey: uri) }
            } else if notDeleted.contains(id) {
                continue
            }
            store.update {
                $0.lastKnownRecords.removeValue(forKey: recordID.recordName)
                $0.outbox.removeAll { $0.recordName == recordID.recordName }
                $0.awaitingParent.removeValue(forKey: recordID.recordName)
                if type == JournalSyncRecordType.attachment {
                    let meta = JournalSyncRecordType.metaName(for: recordID.recordName)
                    $0.lastKnownRecords.removeValue(forKey: meta)
                    $0.awaitingMeta.removeValue(forKey: meta)
                    $0.outbox.removeAll { $0.recordName == meta }
                }
                $0.instrumentAliases.removeValue(forKey: recordID.recordName)
                $0.assetHashes.removeValue(forKey: recordID.recordName)
                $0.fileStampCache.removeValue(forKey: recordID.recordName)
            }
        }
        return save() && complete
    }

    // MARK: Kept before a first-merge deletion (C-197)

    /// The row, or for an entry any of its attachments, has a save this device has not sent.
    private func hasUnsentContent(_ object: NSManagedObject, type: String) -> Bool {
        func pending(_ row: NSManagedObject) -> Bool {
            guard let name = (row.value(forKey: "id") as? UUID)?.uuidString else { return false }
            return pendingSave(name) != nil || (row.entity.name == JournalSyncRecordType.attachment && pendingSave(JournalSyncRecordType.metaName(for: name)) != nil)
        }
        if pending(object) { return true }
        guard type == JournalSyncRecordType.session else { return false }
        return ((object.value(forKey: "attachments") as? Set<NSManagedObject>) ?? []).contains(where: pending)
    }

    /// An attachment as it can be put back: both records, and its file copied aside.
    private func keptAttachment(_ attachment: NSManagedObject) -> JournalKeptAttachment? {
        guard let id = attachment.value(forKey: "id") as? UUID,
              let record = JournalRecordMapping.record(for: attachment, base: nil, includeAsset: false),
              let data = JournalSyncStateStore.encodeWholeRecord(record) else { return nil }
        let meta = JournalRecordMapping.metaRecord(for: attachment, base: nil).flatMap(JournalSyncStateStore.encodeWholeRecord)
        let stored = attachment.value(forKey: "fileURL") as? String
        guard let url = AttachmentPathResolver.resolve(stored), !AttachmentStore.isLibraryScoreFile(url) else {
            return JournalKeptAttachment(record: data, meta: meta, keptFileName: nil, fileURL: stored)   // no file, or one a deletion never removes
        }
        let ext = url.pathExtension
        let fileName = "\(id.uuidString)-deleted" + (ext.isEmpty ? "" : ".\(ext)")
        let target = Self.displacedMediaDirectory().appendingPathComponent(fileName, isDirectory: false)
        do {
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: url, to: target)
        } catch {
            log("Could not keep \(url.lastPathComponent) before its deletion: \(error.localizedDescription)")
            return nil
        }
        return JournalKeptAttachment(record: data, meta: meta, keptFileName: fileName, fileURL: nil)
    }

    /// Keeps an entry with its attachments, or one attachment, and lists it.
    /// False when a file or the entry could not be written.
    private func keepBeforeDeletion(_ object: NSManagedObject, type: String) -> Bool {
        guard let id = object.value(forKey: "id") as? UUID else { return false }
        let isSession = type == JournalSyncRecordType.session
        let rows = isSession ? Array((object.value(forKey: "attachments") as? Set<NSManagedObject>) ?? []) : [object]
        var kept: [JournalKeptAttachment] = []
        for row in rows {
            guard let one = keptAttachment(row) else { return false }
            kept.append(one)
        }
        let title = (Self.value(object, isSession ? "title" : "displayName") as? String) ?? ""
        let notes = (Self.value(object, "notes") as? String) ?? ""
        var conflict = JournalSyncConflict(at: Date(), recordName: id.uuidString, recordType: type, winner: "deleted",
                                           localUserModifiedAt: Self.value(object, "userModifiedAt") as? Date, serverUserModifiedAt: nil,
                                           losingTitle: title, losingNotes: isSession ? notes : nil)
        if isSession {
            guard let record = JournalRecordMapping.record(for: object, base: nil, viewerScope: viewerScope()),
                  let whole = JournalSyncStateStore.encodeWholeRecord(record) else { return false }
            conflict.losingRecord = whole
            conflict.subject = JournalRecoverySubject.session(object)
            if !title.isEmpty { conflict.displaced["Title (this device)"] = title }
            if !notes.isEmpty { conflict.displaced["Notes (this device)"] = notes }
            if !kept.isEmpty { conflict.displaced["Attachments (this device)"] = "\(kept.count) kept with \(kept.count == 1 ? "its file" : "their files")" }
            conflict.restore = "deleted:\(id.uuidString)"
        } else {
            let sessionRow = object.value(forKey: "session") as? NSManagedObject
            conflict.subject = "Attachment" + (sessionRow.map { " in " + JournalRecoverySubject.session($0) } ?? "")
            if !title.isEmpty { conflict.displaced["Name (this device)"] = title }
            conflict.displaced["File (this device)"] = "Kept. Restore puts the attachment back in its entry."
            conflict.restore = "deleted-attachment:\(id.uuidString)"
        }
        conflict.keptAttachments = kept
        return store.update { $0.conflicts.append(conflict) }
    }

    /// Through the guarded deletion: nothing outside Documents, and never a
    /// library PDF (`Documents/Scores`), which a score attachment made from the
    /// library points at directly. Before stage I a remote deletion of such an
    /// attachment deleted the library's file.
    private func removeFile(of attachment: NSManagedObject) {
        if let url = AttachmentPathResolver.resolve(attachment.value(forKey: "fileURL") as? String) {
            AttachmentStore.deleteAttachmentFile(at: url)
        }
    }

    // MARK: Send conflicts (serverRecordChanged)

    /// Resolves a rejected save against the server copy. Returns true when the
    /// local record should be resent (on top of the server's change tag).
    func resolveSendConflict(recordType: String, recordName: String, server: CKRecord) -> Bool {
        if recordType == JournalSyncRecordType.attachmentMeta {
            noteKnown(server)
            guard let attachmentName = JournalSyncRecordType.attachmentName(fromMeta: recordName), let id = UUID(uuidString: attachmentName),
                  let local = freshObject(entity: JournalSyncRecordType.attachment, id: id) else { return false }
            let transition = pendingSave(recordName)?.metadataOnly == true
            if !transition,
               JournalConflictRule.decide(localUserModifiedAt: local.value(forKey: "userModifiedAt") as? Date,
                                          serverUserModifiedAt: JournalRecordMapping.userModifiedAt(of: server)) == .local {
                recordConflict(server, winner: .local, local: local)
                log("Conflict on metadata \(recordName): local kept, resending")
                return true
            }
            // R9 (2026-11-03): the same contract as a session or attachment —
            // the displaced name is on disk before it is overwritten, and the
            // pending send goes only once the server copy is committed. A
            // transition copy (migrated metadata, not a person's edit) is
            // simply superseded.
            if !transition, !recordConflict(server, winner: .server, local: local) {
                log("Conflict on metadata \(recordName): the recovery entry could not be saved; local name kept and the send tried again")
                return true
            }
            JournalRecordMapping.applyMeta(server, to: local)
            applySideStores(server, id: id)
            guard save() else {
                log("Conflict on metadata \(recordName): the server copy could not be saved; local name kept, resolved again later")
                return false
            }
            queue?.removePendingSave(recordName)
            log("Conflict on metadata \(recordName): server kept")
            return false
        }
        guard let id = UUID(uuidString: recordName), let local = freshObject(entity: recordType, id: id) else { return false }
        if JournalSyncRecordType.customs.contains(recordType) || recordType == JournalSyncRecordType.instrument {
            // R13 (2026-11-03): the pending send goes only once the server copy
            // is committed, and the copy is known only then, so a send that is
            // tried again meanwhile is rejected and resolved again.
            keepDisplacedName(of: local, against: server)
            _ = JournalRecordMapping.apply(server, to: local)
            if JournalSyncRecordType.customs.contains(recordType), let owner = customOwner { local.setValue(owner, forKey: "ownerUserID") }
            noteKnownAfterSave(server)
            guard save() else {
                log("Conflict on \(recordType) \(recordName): the server copy could not be saved; local row kept, resolved again later")
                return false
            }
            queue?.removePendingSave(recordName)
            log("Conflict on \(recordType) \(recordName): server kept")
            return false
        }
        noteKnown(server)
        let localOwner = local.value(forKey: "ownerUserID") as? String
        let serverOwner = server["ownerUserID"] as? String
        if pendingSave(recordName)?.metadataOnly == true {
            // Migration meets a newer server copy: its content is taken; the
            // metadata stays queued unless that copy already carries the fields.
            _ = JournalRecordMapping.apply(server, to: local)
            if recordType == JournalSyncRecordType.session {
                let link = JournalRecordMapping.instrumentLink(of: server)
                local.setValue(resolveInstrument(recordName: link.recordName, name: link.name), forKey: "instrument")
                local.setValue(JournalOwnership.mergedOwner(local: localOwner, server: serverOwner), forKey: "ownerUserID")
                followSessionOwner(local)
            }
            applySideStores(server, id: id)
            save()
            if JournalMetadataFields.recordCarriesMetadata(server) {
                queue?.removePendingSave(recordName)
                log("Migration of \(recordName) superseded by a server copy that carries metadata")
                return false
            }
            log("Migration of \(recordName) resent on top of a newer server copy without metadata")
            return true
        }
        if recordType == JournalSyncRecordType.session, pendingSave(recordName)?.ownerOnly == true {
            // Only the owner key was being sent: take the server's content, keep
            // the owner, and send the owner again on top of the new change tag.
            _ = JournalRecordMapping.apply(server, to: local)
            applySideStores(server, id: id)
            let link = JournalRecordMapping.instrumentLink(of: server)
            local.setValue(resolveInstrument(recordName: link.recordName, name: link.name), forKey: "instrument")
            let merged = JournalOwnership.mergedOwner(local: localOwner, server: serverOwner)
            local.setValue(merged, forKey: "ownerUserID")
            followSessionOwner(local)
            save()
            queue?.removePendingSave(recordName)
            if JournalOwnership.normalized(merged) != JournalOwnership.normalized(serverOwner) {
                queue?.enqueueSave(recordName, recordType: recordType, ownerOnly: true)
            }
            log("Owner-only send of \(recordName) met a newer server copy: content taken, owner kept")
            return false
        }
        let decision = JournalConflictRule.decide(localUserModifiedAt: local.value(forKey: "userModifiedAt") as? Date,
                                                  serverUserModifiedAt: JournalRecordMapping.userModifiedAt(of: server))
        if decision == .server {
            // R5 (2026-11-03): the loser's text must be on disk before it is
            // overwritten; otherwise the edit stays queued and is tried again.
            guard recordConflict(server, winner: .server, local: local) else {
                log("Conflict on \(recordName): the recovery entry could not be saved; local content kept and the send tried again")
                return true
            }
            _ = JournalRecordMapping.apply(server, to: local)
            applySideStores(server, id: id)
            var resend = false
            if recordType == JournalSyncRecordType.session {
                let link = JournalRecordMapping.instrumentLink(of: server)
                local.setValue(resolveInstrument(recordName: link.recordName, name: link.name), forKey: "instrument")
                let merged = JournalOwnership.mergedOwner(local: localOwner, server: serverOwner)
                local.setValue(merged, forKey: "ownerUserID")
                followSessionOwner(local)
                resend = JournalOwnership.normalized(merged) != JournalOwnership.normalized(serverOwner)
            } else if recordType == JournalSyncRecordType.attachment {
                local.setValue(localOwner, forKey: "ownerUserID")
            }
            guard save() else {
                // The overwrite rolled back: the edit stays queued (re-resolved
                // at the next activation) and the server copy is not applied.
                log("Conflict on \(recordName): the server copy could not be saved; local content kept, resolved again later")
                return false
            }
            queue?.removePendingSave(recordName)
            if resend { queue?.enqueueSave(recordName, recordType: recordType, ownerOnly: true) }
            log("Conflict on \(recordName): server content kept\(resend ? "; resending owner" : "")")
            return false
        }
        recordConflict(server, winner: .local, local: local)
        if recordType == JournalSyncRecordType.session {
            absorbOwner(serverOwner, into: local, localOwner: localOwner, recordName: recordName)
            save()
        }
        log("Conflict on \(recordName): local content kept, resending")
        return true
    }

    // MARK: Helpers

    private func localChangePending(_ recordName: String) -> Bool {
        pendingSave(recordName) != nil
    }

    private func pendingSave(_ recordName: String) -> JournalSyncPendingChange? {
        store.state.outbox.first { $0.recordName == recordName && $0.op == .save }
    }

    /// B1 (2026-11-03): no save is pending for this row, yet the server copy is
    /// older than what this device holds (an own write echoed back after a
    /// later edit, or another device's older edit uploaded late). The local
    /// copy stands and goes up; the server's is the previous version, not a
    /// conflict the person needs to see. Returns false when the local copy is
    /// kept (the caller applies nothing).
    private func keepsNewerLocal(_ existing: NSManagedObject, over record: CKRecord, type: String) -> Bool {
        let local = existing.value(forKey: "userModifiedAt") as? Date
        let server = JournalRecordMapping.userModifiedAt(of: record)
        guard JournalConflictRule.decide(localUserModifiedAt: local, serverUserModifiedAt: server) == .local else { return true }
        let name = record.recordID.recordName
        noteKnown(record)
        queue?.enqueueSave(name, recordType: type, ownerOnly: false)
        log("Kept this device's newer copy of \(name.prefix(8))… over an older server copy; queued to go up")
        return false
    }

    /// H2 (2026-11-03): returns whether the entry reached the state file. A
    /// server win is applied only when it did, so the loser's text is on disk
    /// before it is overwritten.
    @discardableResult
    private func recordConflict(_ server: CKRecord, winner: JournalConflictWinner, local: NSManagedObject) -> Bool {
        // C-197 (2026-11-13): a conflict is a difference in CONTENT, read over
        // the fields this record type carries. The local row is compared as
        // the record it would send, so a field the record does not carry (an
        // attachment's name lives on its metadata record) is never compared
        // with nothing. Identical content writes no entry: on a device whose
        // journal iCloud already holds, that was one entry per record.
        let isSession = server.recordType == JournalSyncRecordType.session
        let isMeta = server.recordType == JournalSyncRecordType.attachmentMeta
        guard let mine = isMeta ? JournalRecordMapping.metaRecord(for: local, base: nil)
                                : JournalRecordMapping.record(for: local, base: nil, includeAsset: false, viewerScope: viewerScope()) else { return true }
        if !isSession, !isMeta {
            // An older build's content record still carried the name and star.
            for key in JournalRecordMapping.legacyAttachmentMetaKeys { mine[key] = Self.value(local, key) as? CKRecordValue }
        }
        let differing = JournalRecordMapping.differingContentKeys(local: mine, server: server)
        guard !differing.isEmpty else { return true }
        let loser = winner == .server ? mine : server
        let side = winner == .server ? "this device" : "other device"
        let titleKey = isSession ? "title" : "displayName"
        let loserTitle = loser[titleKey] as? String
        var conflict = JournalSyncConflict(at: Date(), recordName: server.recordID.recordName, recordType: server.recordType,
                                           winner: winner == .server ? "server" : "local",
                                           localUserModifiedAt: Self.value(local, "userModifiedAt") as? Date,
                                           serverUserModifiedAt: JournalRecordMapping.userModifiedAt(of: server),
                                           losingTitle: loserTitle, losingNotes: loser["notes"] as? String)
        // What the person can read back and restore. Title and notes as text;
        // every other field that differs by name, with the whole losing
        // version kept beside it so a restore puts all of it back.
        var others: [String] = []
        for key in differing {
            // An empty value is listed too: the losing edit cleared the text,
            // and that version is as restorable as any other.
            let text = (loser[key] as? String) ?? ""
            if key == titleKey { conflict.displaced["\(isSession ? "Title" : "Name") (\(side))"] = text }
            else if key == "notes" { conflict.displaced["Notes (\(side))"] = text }
            else if !others.contains(JournalRecordMapping.fieldLabel(key)) { others.append(JournalRecordMapping.fieldLabel(key)) }
        }
        if !others.isEmpty { conflict.displaced["Other details (\(side))"] = others.joined(separator: ", ") }
        if let whole = loser.copy() as? CKRecord {
            whole[JournalRecordMapping.assetKey] = nil
            conflict.losingRecord = JournalSyncStateStore.encodeWholeRecord(whole)
        }
        if isSession {
            conflict.subject = JournalRecoverySubject.session(local)
            conflict.restore = "session:\(server.recordID.recordName)"
        } else {
            let sessionRow = local.value(forKey: "session") as? NSManagedObject
            conflict.subject = "Attachment" + (sessionRow.map { " in " + JournalRecoverySubject.session($0) } ?? "")
            // The ATTACHMENT's id: a metadata record is named "<id>-meta".
            let name = server.recordID.recordName
            conflict.restore = "attachment:\(JournalSyncRecordType.attachmentName(fromMeta: name) ?? name)"
        }
        let saved = store.update { $0.conflicts.append(conflict) }
        if !saved { log("Recovery entry for \(server.recordID.recordName.prefix(8))… could not be saved; the \(winner == .server ? "server copy is not applied" : "entry is lost") this round") }
        return saved
    }

    /// C-197: a custom instrument, activity or profile instrument has no clock,
    /// so the server's row stands; the name it replaces here is kept to read back.
    private func keepDisplacedName(of local: NSManagedObject, against server: CKRecord) {
        let key = server.recordType == JournalSyncRecordType.instrument ? "name" : "displayName"
        let mine = (Self.value(local, key) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let theirs = (server[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mine.isEmpty, mine != theirs else { return }
        let name = server.recordID.recordName
        // A resolution tried again (its save failed the first time) lists the name once.
        if store.state.conflicts.contains(where: { $0.recordName == name && $0.resolvedAt == nil && $0.losingTitle == mine }) { return }
        var conflict = JournalSyncConflict(at: Date(), recordName: name, recordType: server.recordType, winner: "server",
                                           localUserModifiedAt: nil, serverUserModifiedAt: nil, losingTitle: mine, losingNotes: nil)
        conflict.subject = server.recordType == JournalSyncRecordType.userActivity ? "Activity" : "Instrument"
        conflict.displaced["Name (this device)"] = mine
        store.update { $0.conflicts.append(conflict) }
    }

    // MARK: Displaced media (C-197)

    static func displacedMediaDirectory() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SyncTest/DisplacedMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func clearDisplacedMedia() {
        try? FileManager.default.removeItem(at: displacedMediaDirectory())
    }

    /// Copies this device's file aside and lists it on Displaced by sync,
    /// BEFORE the server's file takes its place. False when either the copy
    /// or the entry could not be written; the caller then replaces nothing.
    private func keepDisplacedMedia(_ url: URL, hash: String, record: CKRecord, local: NSManagedObject?) -> Bool {
        let name = record.recordID.recordName
        let ext = url.pathExtension
        let fileName = "\(name)-\(hash.prefix(12))" + (ext.isEmpty ? "" : ".\(ext)")
        let target = Self.displacedMediaDirectory().appendingPathComponent(fileName, isDirectory: false)
        if !FileManager.default.fileExists(atPath: target.path) {
            do { try FileManager.default.copyItem(at: url, to: target) } catch {
                log("Could not keep \(url.lastPathComponent) before replacing it: \(error.localizedDescription)")
                return false
            }
        }
        let restore = "media:\(name)|\(fileName)"
        if store.state.conflicts.contains(where: { $0.restore == restore && $0.resolvedAt == nil }) { return true }
        var conflict = JournalSyncConflict(at: Date(), recordName: name, recordType: record.recordType, winner: "server",
                                           localUserModifiedAt: local.flatMap { Self.value($0, "userModifiedAt") as? Date },
                                           serverUserModifiedAt: JournalRecordMapping.userModifiedAt(of: record),
                                           losingTitle: "displaced file kept: \(fileName)", losingNotes: nil)
        let sessionRow = local?.value(forKey: "session") as? NSManagedObject
        conflict.subject = "Attachment" + (sessionRow.map { " in " + JournalRecoverySubject.session($0) } ?? "")
        conflict.displaced["File (this device)"] = "A different file was on this device. It is kept, and Restore puts it back."
        conflict.restore = restore
        return store.update { $0.conflicts.append(conflict) }
    }

    /// `value(forKey:)` raises for a key the entity lacks (Attachment has no
    /// title or notes).
    static func value(_ object: NSManagedObject, _ key: String) -> Any? {
        object.entity.propertiesByName[key] == nil ? nil : object.value(forKey: key)
    }

    /// A FRESH copy for an outgoing record or a send conflict. The import
    /// context is long-lived and keeps what it last imported; a later local
    /// edit made in another context is not seen unless the object is
    /// refreshed (seen 2026-10-20: an iPad notes edit to a synced session was
    /// sent with the notes it had imported, so the iPhone never saw the edit).
    func freshObject(entity: String, id: UUID) -> NSManagedObject? {
        guard let object = fetch(entity: entity, id: id) else { return nil }
        context.refresh(object, mergeChanges: false)
        if object.entity.relationshipsByName["session"] != nil,
           let session = object.value(forKey: "session") as? NSManagedObject { context.refresh(session, mergeChanges: false) }
        return object
    }

    func fetch(entity: String, id: UUID) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// R3: knowledge of the records applied since the last save is committed
    /// here, with the save, and discarded with a rollback.
    @discardableResult
    func save() -> Bool {
        guard context.hasChanges else { commitKnown(); return true }
        do { try context.save(); commitKnown(); return true } catch {
            log("Import save failed: \(error.localizedDescription); the batch is fetched again")
            context.rollback()
            for entry in restoreOnRollback { Self.restore(previous: entry.previous, to: entry.destination) }
            knownAfterSave.removeAll(); hashesAfterSave.removeAll(); removeAfterSave.removeAll(); restoreOnRollback.removeAll()
            return false
        }
    }

    /// B3 (2026-11-03): the row as the store holds it NOW. The import context
    /// is long-lived and keeps what it last imported, so an object it still
    /// registers carries the clock and text of that import, not the person's
    /// later edit (C-118 proved it for sends; the conflict decision read the
    /// same stale copy). An object inserted or changed in this batch is left
    /// as it is: nothing local can have touched it meanwhile.
    func freshRow(entity: String, id: UUID) -> NSManagedObject? {
        guard let object = fetch(entity: entity, id: id) else { return nil }
        if !object.isInserted, !object.hasChanges { context.refresh(object, mergeChanges: false) }
        return object
    }
}
