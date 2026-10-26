//
//  JournalImporter.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
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

#if SYNCTEST
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
        return store.state.lastKnownRecords[meta] != nil || store.state.awaitingMeta[meta] != nil
    }

    // MARK: Attachment metadata records (stage G)

    /// Applies a meta record to its attachment, or holds it until the
    /// attachment arrives. Conflicts use the attachment row's stamp.
    @discardableResult
    func importAttachmentMeta(_ record: CKRecord) -> Bool {
        let name = record.recordID.recordName
        guard let attachmentName = JournalSyncRecordType.attachmentName(fromMeta: name),
              let id = UUID(uuidString: attachmentName) else { return false }
        guard let attachment = fetch(entity: JournalSyncRecordType.attachment, id: id) else {
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
                store.update { $0.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record) }
                recordConflict(record, winner: .local, local: attachment)
                return false
            }
            recordConflict(record, winner: .server, local: attachment)
            queue?.removePendingSave(name)
        } else if pendingSave(name)?.metadataOnly == true {
            // The transition's copy meets a real one: the server's stands.
            queue?.removePendingSave(name)
        }
        JournalRecordMapping.applyMeta(record, to: attachment)
        applySideStores(record, id: id)
        store.update { st in
            st.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record)
            st.awaitingMeta.removeValue(forKey: name)
        }
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

    struct Summary { var received = 0; var bytes: Int64 = 0; var customs = 0 }

    // MARK: Modifications

    /// Imports Session, Attachment and custom-row records (not SavedList).
    /// Must be called on the context's queue (`performAndWait`).
    func importModifications(_ records: [CKRecord]) -> Summary {
        var summary = Summary()
        let sessions = records.filter { $0.recordType == JournalSyncRecordType.session }
        let attachments = records.filter { $0.recordType == JournalSyncRecordType.attachment }
        let metas = records.filter { $0.recordType == JournalSyncRecordType.attachmentMeta }
        let customs = records.filter { JournalSyncRecordType.customs.contains($0.recordType) }
        let instruments = records.filter { $0.recordType == JournalSyncRecordType.instrument }
        // Instruments first, so sessions and custom rows resolve them by id.
        var importedInstruments: [NSManagedObject] = []
        for record in instruments { if let o = importInstrument(record) { importedInstruments.append(o); summary.received += 1 } }
        for record in sessions { if importSession(record) { summary.received += 1 } }
        for record in attachments {
            let outcome = importAttachment(record)
            if outcome.imported { summary.received += 1 }
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
        save()
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
        let existing = fetch(entity: JournalSyncRecordType.session, id: id)
        let localOwner = existing?.value(forKey: "ownerUserID") as? String
        let serverOwner = record["ownerUserID"] as? String
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
                store.update { $0.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record) }
                recordConflict(record, winner: .local, local: existing)
                return false
            }
            recordConflict(record, winner: .server, local: existing)
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
        store.update { $0.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record) }
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
        let existing = fetch(entity: JournalSyncRecordType.attachment, id: id)
        if existing != nil, let pending = pendingSave(name), pending.metadataOnly {
            if JournalMetadataFields.recordCarriesMetadata(record) { queue?.removePendingSave(name) }
        } else if let existing, localChangePending(name) {
            let local = existing.value(forKey: "userModifiedAt") as? Date
            let server = JournalRecordMapping.userModifiedAt(of: record)
            if JournalConflictRule.decide(localUserModifiedAt: local, serverUserModifiedAt: server) == .local {
                store.update { $0.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record) }
                recordConflict(record, winner: .local, local: existing)
                return (false, 0)
            }
            recordConflict(record, winner: .server, local: existing)
            queue?.removePendingSave(name)
        }
        let object = existing ?? NSEntityDescription.insertNewObject(forEntityName: JournalSyncRecordType.attachment, into: context)
        // Legacy metadata on the content record counts only until this
        // attachment has a meta record (the stage G transition).
        let legacy = !metaKnown(name)
        _ = JournalRecordMapping.apply(record, to: object, legacyMetadata: legacy)
        if legacy { applySideStores(record, id: id) }
        object.setValue(session, forKey: "session")
        object.setValue(session.value(forKey: "ownerUserID") as? String, forKey: "ownerUserID")

        // Media. CloudKit downloads the asset of every fetched attachment record
        // (transport; counted as such). It is written into place only when this
        // device has no usable file, or when the server's hash says the file was
        // replaced on the other device. The device that created the attachment
        // otherwise keeps its own file (named <base>-<id>.<ext> by staging).
        var bytes: Int64 = 0
        let ext = (record[JournalRecordMapping.fileExtKey] as? String) ?? ""
        let destination = JournalRecordMapping.materialisedURL(recordName: name, ext: ext)
        let existingFile = AttachmentPathResolver.resolve(object.value(forKey: "fileURL") as? String)
        let sourceURL = heldFile.map { URL(fileURLWithPath: $0) } ?? (record[JournalRecordMapping.assetKey] as? CKAsset)?.fileURL
        let serverHash = record[JournalRecordMapping.fileHashKey] as? String
        let knownHash = store.state.assetHashes[name]
        if heldFile == nil, let sourceURL, let size = JournalAssetHash.stamp(of: sourceURL)?.size {
            store.update { $0.assetBytesDownloaded += size }
        }
        let replaced = existingFile != nil && serverHash != nil && knownHash != nil && serverHash != knownHash
        if existingFile == nil || replaced {
            if let sourceURL, FileManager.default.fileExists(atPath: sourceURL.path) {
                let incoming = JournalAssetHash.stamp(of: sourceURL)?.size ?? 0
                let present = JournalAssetHash.stamp(of: destination)?.size
                if present != incoming || replaced {
                    try? FileManager.default.removeItem(at: destination)
                    do { try FileManager.default.copyItem(at: sourceURL, to: destination); bytes = incoming }
                    catch { log("Could not materialise \(name): \(error.localizedDescription)") }
                }
                if replaced, let old = existingFile, old.path != destination.path {
                    // Never a library PDF (C-138): a score attached from the library is its file.
                    if !AttachmentStore.isLibraryScoreFile(old) { try? FileManager.default.removeItem(at: old) }
                    log("Replaced media for \(name) from the other device")
                }
                let hash = serverHash ?? JournalAssetHash.hash(of: destination)
                store.update { st in
                    if let hash { st.assetHashes[name] = hash }
                    st.fileStampCache.removeValue(forKey: name)
                }
            } else if existingFile == nil {
                log("Attachment \(name) arrived without a file")
            }
            // Point at the materialised path even if the copy failed, so the
            // resolver's filename match finds it once a later fetch supplies it.
            object.setValue(destination.path, forKey: "fileURL")
        } else if knownHash == nil, let serverHash {
            // Our own file, sent before hashes existed: adopt the server's.
            store.update { $0.assetHashes[name] = serverHash }
        }
        if heldFile != nil, let sourceURL { try? FileManager.default.removeItem(at: sourceURL) }
        store.update { $0.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record) }
        applyHeldMeta(for: name)
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

    // MARK: Custom instruments and activities

    /// Applies a custom row and stamps this install's K2. Server wins a
    /// conflict (custom rows carry no edit stamp; ties go to the server).
    private func importCustom(_ record: CKRecord) -> NSManagedObject? {
        let name = record.recordID.recordName
        guard let id = UUID(uuidString: name), let owner = customOwner else { return nil }
        let existing = fetch(entity: record.recordType, id: id)
        if existing != nil, localChangePending(name) {
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
        store.update { $0.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record) }
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
        store.update { $0.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record) }
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

    func importDeletions(_ deletions: [(CKRecord.ID, CKRecord.RecordType)]) {
        for (recordID, type) in deletions where type != JournalSyncRecordType.savedList {
            if type == JournalSyncRecordType.attachmentMeta {
                // The attachment's own deletion removes the row; its meta just stops being known.
                store.update {
                    $0.lastKnownRecords.removeValue(forKey: recordID.recordName)
                    $0.awaitingMeta.removeValue(forKey: recordID.recordName)
                    $0.outbox.removeAll { $0.recordName == recordID.recordName }
                }
                continue
            }
            guard let id = UUID(uuidString: recordID.recordName) else { continue }
            if let object = fetch(entity: type, id: id) {
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
        save()
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
            store.update { $0.lastKnownRecords[recordName] = JournalSyncStateStore.encodeSystemFields(server) }
            guard let attachmentName = JournalSyncRecordType.attachmentName(fromMeta: recordName), let id = UUID(uuidString: attachmentName),
                  let local = freshObject(entity: JournalSyncRecordType.attachment, id: id) else { return false }
            if pendingSave(recordName)?.metadataOnly != true,
               JournalConflictRule.decide(localUserModifiedAt: local.value(forKey: "userModifiedAt") as? Date,
                                          serverUserModifiedAt: JournalRecordMapping.userModifiedAt(of: server)) == .local {
                recordConflict(server, winner: .local, local: local)
                log("Conflict on metadata \(recordName): local kept, resending")
                return true
            }
            JournalRecordMapping.applyMeta(server, to: local)
            applySideStores(server, id: id)
            save()
            queue?.removePendingSave(recordName)
            log("Conflict on metadata \(recordName): server kept")
            return false
        }
        guard let id = UUID(uuidString: recordName), let local = freshObject(entity: recordType, id: id) else { return false }
        store.update { $0.lastKnownRecords[recordName] = JournalSyncStateStore.encodeSystemFields(server) }
        if JournalSyncRecordType.customs.contains(recordType) || recordType == JournalSyncRecordType.instrument {
            _ = JournalRecordMapping.apply(server, to: local)
            if JournalSyncRecordType.customs.contains(recordType), let owner = customOwner { local.setValue(owner, forKey: "ownerUserID") }
            save()
            queue?.removePendingSave(recordName)
            log("Conflict on \(recordType) \(recordName): server kept")
            return false
        }
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
            recordConflict(server, winner: .server, local: local)
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
            save()
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

    private func recordConflict(_ server: CKRecord, winner: JournalConflictWinner, local: NSManagedObject) {
        let loserTitle: String?
        let loserNotes: String?
        if winner == .server {
            loserTitle = Self.value(local, "title") as? String ?? Self.value(local, "displayName") as? String
            loserNotes = Self.value(local, "notes") as? String
        } else {
            loserTitle = server["title"] as? String ?? server["displayName"] as? String
            loserNotes = server["notes"] as? String
        }
        let conflict = JournalSyncConflict(at: Date(), recordName: server.recordID.recordName, recordType: server.recordType,
                                           winner: winner == .server ? "server" : "local",
                                           localUserModifiedAt: Self.value(local, "userModifiedAt") as? Date,
                                           serverUserModifiedAt: JournalRecordMapping.userModifiedAt(of: server),
                                           losingTitle: loserTitle, losingNotes: loserNotes)
        store.update { $0.conflicts.append(conflict) }
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

    func save() {
        guard context.hasChanges else { return }
        do { try context.save() } catch {
            log("Import save failed: \(error.localizedDescription)")
            context.rollback()
        }
    }
}
#endif
