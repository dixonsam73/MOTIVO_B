//
//  JournalRecovery.swift
//  MOTIVO — private iCloud sync. Compiled in every configuration; nothing
//  here runs until the person turns sync on (see JournalSyncCoordinator).
//
//  WHAT A CONFLICT DISPLACED, AND HOW A PERSON GETS IT BACK (stage J).
//
//  The winner rule stays simple (newer clock wins the whole record, ties to
//  the server). What it displaces is kept in the state file's conflict log
//  as readable fields, and `SyncRecoveryView` shows them with Copy and, where
//  it makes sense, Restore. A restoration is a deliberate NEW edit: it goes
//  through the app's own writers, so it is clocked now and wins everywhere.
//  This is not a version history: one displaced value per conflict, and an
//  entry leaves the list when it is restored or dismissed.
//

import Foundation
import CoreData
import UIKit

@MainActor
enum JournalRecovery {

    /// Entries worth showing: unresolved, with text to read back (or a
    /// displaced avatar file that still exists).
    static func entries(store: JournalSyncStateStore) -> [JournalSyncConflict] {
        store.state.conflicts.filter { entry in
            guard entry.resolvedAt == nil else { return false }
            if let restore = entry.restore, restore.hasPrefix("avatar:") {
                return FileManager.default.fileExists(atPath: String(restore.dropFirst("avatar:".count)))
            }
            if let restore = entry.restore, restore.hasPrefix("media:"), let file = restore.split(separator: "|").last {
                return FileManager.default.fileExists(atPath: JournalImporter.displacedMediaDirectory().appendingPathComponent(String(file)).path)
            }
            return entry.isRecoverable
        }.sorted { $0.at > $1.at }
    }

    static func dismiss(_ entry: JournalSyncConflict, store: JournalSyncStateStore) {
        store.update { s in
            if let i = s.conflicts.firstIndex(where: { $0.id == entry.id }) { s.conflicts[i].resolvedAt = Date() }
        }
    }

    static func copyText(of entry: JournalSyncConflict) -> String {
        entry.displaced.keys.sorted().map { key in
            let value = entry.displaced[key] ?? ""
            return entry.displaced.count == 1 ? value : "\(key): \(value)"
        }.joined(separator: "\n\n")
    }

    enum Outcome: Equatable { case restored(String), failed(String) }

    /// Applies the displaced values as this device's current edit.
    static func restore(_ entry: JournalSyncConflict, store: JournalSyncStateStore,
                        context: NSManagedObjectContext = PersistenceController.shared.container.viewContext,
                        scope: JournalProfileScope? = nil) -> Outcome {
        guard let restore = entry.restore else { return .failed("This entry can only be copied.") }
        let outcome: Outcome
        if restore.hasPrefix("session:") {
            outcome = restoreSession(entry, id: String(restore.dropFirst("session:".count)), context: context)
        } else if restore.hasPrefix("attachment:") {
            outcome = restoreAttachment(entry, id: String(restore.dropFirst("attachment:".count)), context: context)
        } else if restore.hasPrefix("deleted-attachment:") {
            outcome = restoreDeletedAttachment(entry, context: context)
        } else if restore.hasPrefix("deleted:") {
            outcome = restoreDeletedEntry(entry, context: context)
        } else if restore == "profile" {
            outcome = restoreProfile(entry, context: context, scope: scope ?? JournalSyncCoordinator.shared.engine?.profileScope ?? .local)
        } else if restore.hasPrefix("score:") {
            outcome = restoreScoreTitle(entry, id: String(restore.dropFirst("score:".count)))
        } else if restore.hasPrefix("media:") {
            outcome = restoreMedia(spec: String(restore.dropFirst("media:".count)), context: context)
        } else if restore.hasPrefix("avatar:") {
            let url = URL(fileURLWithPath: String(restore.dropFirst("avatar:".count)))
            let ok = JournalProfileSync.restoreDisplacedAvatar(url, scope: scope ?? JournalSyncCoordinator.shared.engine?.profileScope ?? .local)
            outcome = ok ? .restored("Profile photo restored") : .failed("The displaced photo could not be read.")
        } else {
            outcome = .failed("This entry can only be copied.")
        }
        if case .restored = outcome { dismiss(entry, store: store) }
        return outcome
    }

    // MARK: Field conventions

    /// Displaced text is keyed "<Field> (this device)" or "<Field> (other
    /// device)". A restoration applies the field whatever the side.
    static func value(_ entry: JournalSyncConflict, field: String) -> String? {
        for (key, value) in entry.displaced where key.hasPrefix(field) { return value }
        return nil
    }

    private static func restoreSession(_ entry: JournalSyncConflict, id: String, context: NSManagedObjectContext) -> Outcome {
        guard let uuid = UUID(uuidString: id), let session = fetch("Session", id: uuid, in: context) else {
            return .failed("That entry is no longer in the journal.")
        }
        // C-197: the whole losing version, when the entry holds it. The owner
        // stays this journal's, and the clock is now: a restore is a new edit.
        if let data = entry.losingRecord, let record = JournalSyncStateStore.decodeWholeRecord(data), record.recordType == JournalSyncRecordType.session {
            let owner = session.value(forKey: "ownerUserID")
            _ = JournalRecordMapping.apply(record, to: session)
            session.setValue(owner, forKey: "ownerUserID")
            session.setValue(Date(), forKey: "userModifiedAt")
            JournalMetadataFields.applySession(isSaved: record[JournalMetadataKeys.isSaved] as? NSNumber, id: uuid,
                                               viewerScope: JournalMetadataCodec.viewerScope(currentUserID: PersistenceController.shared.currentUserID))
            let request = NSFetchRequest<NSManagedObject>(entityName: JournalSyncRecordType.instrument)
            request.predicate = NSPredicate(format: "name ==[cd] %@", JournalRecordMapping.instrumentLink(of: record).name ?? "")
            session.setValue((try? context.fetch(request))?.first, forKey: "instrument")
            do { try context.save() } catch { context.rollback(); return .failed(error.localizedDescription) }
            return .restored("Restored the whole entry as a new edit")
        }
        var applied: [String] = []
        if let title = value(entry, field: "Title") { session.setValue(title, forKey: "title"); applied.append("title") }
        if let notes = value(entry, field: "Notes") { session.setValue(notes, forKey: "notes"); applied.append("notes") }
        guard !applied.isEmpty else { return .failed("Nothing to restore.") }
        do { try context.save() } catch { context.rollback(); return .failed(error.localizedDescription) }
        return .restored("Restored \(applied.joined(separator: " and ")) as a new edit")
    }

    /// C-197: everything the losing version of an attachment's details held:
    /// the name and the star on the row, the privacy choice and the page
    /// selection through their own stores, each as a new edit. An entry
    /// written before the kept version existed restores the name alone.
    private static func restoreAttachment(_ entry: JournalSyncConflict, id: String, context: NSManagedObjectContext) -> Outcome {
        // Older entries named the metadata record ("<id>-meta"), which is not an attachment id.
        guard let uuid = UUID(uuidString: JournalSyncRecordType.attachmentName(fromMeta: id) ?? id),
              let attachment = fetch("Attachment", id: uuid, in: context) else {
            return .failed("That attachment is no longer in the journal.")
        }
        var name = entry.displaced.contains { $0.key.hasPrefix("Name") } ? value(entry, field: "Name") : nil
        var star: Bool?, isPrivate: Bool?, pages: [Int]?
        if let data = entry.losingRecord, let record = JournalSyncStateStore.decodeWholeRecord(data) {
            name = record["displayName"] as? String ?? name
            star = (record["isThumbnail"] as? NSNumber)?.boolValue
            isPrivate = (record[JournalMetadataKeys.isPrivate] as? NSNumber)?.boolValue
            pages = JournalMetadataCodec.pages(from: record[JournalMetadataKeys.selectedPages] as? String)
        }
        var applied: [String] = []
        let titleKind = JournalMetadataCodec.titleKind(for: attachment.value(forKey: "kind") as? String)
        if let name {
            if titleKind == nil { attachment.setValue(name, forKey: "displayName") }
            applied.append("name")
        }
        if let star {
            // One star per entry, as the entry screen keeps it.
            let siblings = ((attachment.value(forKey: "session") as? NSManagedObject)?.value(forKey: "attachments") as? Set<NSManagedObject>) ?? [attachment]
            for row in siblings where star || row == attachment { row.setValue(star && row == attachment, forKey: "isThumbnail") }
            applied.append("star")
        }
        guard !applied.isEmpty || isPrivate != nil || pages != nil else { return .failed("Nothing to restore.") }
        attachment.setValue(Date(), forKey: "userModifiedAt")
        do { try context.save() } catch { context.rollback(); return .failed(error.localizedDescription) }
        // Audio and video: the app's own title writer (side store + displayName).
        if let name, let titleKind { AttachmentTitlePersistenceKeys.writeLocalTitle(name, kind: titleKind, attachmentID: uuid) }
        if let isPrivate { AttachmentPrivacy.setPrivate(id: uuid, url: nil, isPrivate); applied.append("privacy") }
        if let pages { PDFSelectedPagesStore.setPages(pages.isEmpty ? nil : pages, for: uuid); applied.append("pages") }
        return .restored("Restored the attachment's \(applied.joined(separator: ", ")) as a new edit")
    }

    // MARK: Kept before a first-merge deletion (C-197)

    /// Makes an attachment again from what was kept, in `session`. The file
    /// is copied back into the journal before the row is saved.
    /// Why a kept attachment was not made again. Thrown, never skipped: a
    /// caller that went on would report success and remove the kept file.
    enum RestoreRefusal: LocalizedError {
        case unreadable, attachmentExists
        var errorDescription: String? {
            switch self {
            case .unreadable: return "The kept attachment could not be read. Nothing was restored."
            case .attachmentExists: return "An attachment with the same identity is already in the journal. Nothing was restored, and the kept copy is still here."
            }
        }
    }

    /// Throws before touching any row or file when the kept record cannot be
    /// read, or an attachment with its id already exists (it may have come
    /// back by sync since): that attachment and its file are left alone.
    private static func recreate(_ kept: JournalKeptAttachment, in session: NSManagedObject, context: NSManagedObjectContext, copied: inout [URL]) throws {
        guard let record = JournalSyncStateStore.decodeWholeRecord(kept.record), let uuid = UUID(uuidString: record.recordID.recordName) else {
            throw RestoreRefusal.unreadable
        }
        guard fetch("Attachment", id: uuid, in: context) == nil else { throw RestoreRefusal.attachmentExists }
        let row = NSEntityDescription.insertNewObject(forEntityName: JournalSyncRecordType.attachment, into: context)
        _ = JournalRecordMapping.apply(record, to: row)
        if let fileName = kept.keptFileName {
            let source = JournalImporter.displacedMediaDirectory().appendingPathComponent(fileName, isDirectory: false)
            let target = JournalRecordMapping.materialisedURL(recordName: uuid.uuidString, ext: source.pathExtension)
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: source, to: target)
            copied.append(target)
            row.setValue(target.path, forKey: "fileURL")
        } else if let fileURL = kept.fileURL {
            row.setValue(fileURL, forKey: "fileURL")
        }
        if let meta = kept.meta.flatMap(JournalSyncStateStore.decodeWholeRecord) {
            JournalRecordMapping.applyMeta(meta, to: row)
            JournalMetadataFields.applyAttachment(isPrivate: meta[JournalMetadataKeys.isPrivate] as? NSNumber, pages: meta[JournalMetadataKeys.selectedPages] as? String,
                                                  displayName: meta["displayName"] as? String, kind: row.value(forKey: "kind") as? String, id: uuid)
        }
        row.setValue(session, forKey: "session")
        row.setValue(session.value(forKey: "ownerUserID"), forKey: "ownerUserID")
        row.setValue(Date(), forKey: "userModifiedAt")
    }

    private static func removeKeptFiles(_ kept: [JournalKeptAttachment]) {
        for name in kept.compactMap(\.keptFileName) {
            try? FileManager.default.removeItem(at: JournalImporter.displacedMediaDirectory().appendingPathComponent(name, isDirectory: false))
        }
    }

    /// An entry a deletion removed in the first merge comes back whole, with
    /// its attachments and their files, as a NEW entry that goes up.
    private static func restoreDeletedEntry(_ entry: JournalSyncConflict, context: NSManagedObjectContext) -> Outcome {
        guard let record = entry.losingRecord.flatMap(JournalSyncStateStore.decodeWholeRecord), let uuid = UUID(uuidString: record.recordID.recordName) else {
            return .failed("The kept entry could not be read.")
        }
        guard fetch("Session", id: uuid, in: context) == nil else { return .failed("That entry is already in the journal.") }
        let session = NSEntityDescription.insertNewObject(forEntityName: JournalSyncRecordType.session, into: context)
        _ = JournalRecordMapping.apply(record, to: session)
        session.setValue(Date(), forKey: "userModifiedAt")
        let request = NSFetchRequest<NSManagedObject>(entityName: JournalSyncRecordType.instrument)
        request.predicate = NSPredicate(format: "name ==[cd] %@", JournalRecordMapping.instrumentLink(of: record).name ?? "")
        session.setValue((try? context.fetch(request))?.first, forKey: "instrument")
        let kept = entry.keptAttachments ?? []
        var copied: [URL] = []
        do {
            for one in kept { try recreate(one, in: session, context: context, copied: &copied) }
            try context.save()
        } catch {
            context.rollback()
            for url in copied { try? FileManager.default.removeItem(at: url) }
            return .failed(error.localizedDescription)
        }
        JournalMetadataFields.applySession(isSaved: record[JournalMetadataKeys.isSaved] as? NSNumber, id: uuid,
                                           viewerScope: JournalMetadataCodec.viewerScope(currentUserID: PersistenceController.shared.currentUserID))
        removeKeptFiles(kept)
        return .restored(kept.isEmpty ? "Restored the entry as a new entry" : "Restored the entry and \(kept.count) attachment\(kept.count == 1 ? "" : "s") as a new entry")
    }

    private static func restoreDeletedAttachment(_ entry: JournalSyncConflict, context: NSManagedObjectContext) -> Outcome {
        guard let kept = entry.keptAttachments?.first, let record = JournalSyncStateStore.decodeWholeRecord(kept.record) else {
            return .failed("The kept attachment could not be read.")
        }
        guard let sid = JournalRecordMapping.sessionRecordName(of: record).flatMap(UUID.init(uuidString:)), let session = fetch("Session", id: sid, in: context) else {
            return .failed("The entry this attachment belonged to is no longer in the journal.")
        }
        var copied: [URL] = []
        do {
            try recreate(kept, in: session, context: context, copied: &copied)
            try context.save()
        } catch {
            context.rollback()
            for url in copied { try? FileManager.default.removeItem(at: url) }
            return .failed(error.localizedDescription)
        }
        removeKeptFiles([kept])
        return .restored("Restored the attachment to its entry")
    }

    /// C-197: puts a kept file back as the attachment's file. It goes in under
    /// a new name, so the change is a content edit that carries the file to
    /// the other devices; the file it replaces was the cloud's and goes.
    private static func restoreMedia(spec: String, context: NSManagedObjectContext) -> Outcome {
        let parts = spec.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let uuid = UUID(uuidString: parts[0]), let attachment = fetch("Attachment", id: uuid, in: context) else {
            return .failed("That attachment is no longer in the journal.")
        }
        let kept = JournalImporter.displacedMediaDirectory().appendingPathComponent(parts[1], isDirectory: false)
        guard FileManager.default.fileExists(atPath: kept.path) else { return .failed("The kept file is no longer on this device.") }
        let ext = kept.pathExtension
        let target = JournalRecordMapping.materialisedURL(recordName: "\(uuid.uuidString)-restored-\(Int(Date().timeIntervalSince1970))", ext: ext)
        let previous = AttachmentPathResolver.resolve(attachment.value(forKey: "fileURL") as? String)
        do {
            try FileManager.default.copyItem(at: kept, to: target)
            attachment.setValue(target.path, forKey: "fileURL")
            attachment.setValue(Date(), forKey: "userModifiedAt")
            try context.save()
        } catch {
            context.rollback()
            try? FileManager.default.removeItem(at: target)
            return .failed(error.localizedDescription)
        }
        if let previous, previous.path != target.path { AttachmentStore.deleteAttachmentFile(at: previous) }
        try? FileManager.default.removeItem(at: kept)
        return .restored("Restored the file as a new edit")
    }

    private static func restoreProfile(_ entry: JournalSyncConflict, context: NSManagedObjectContext, scope: JournalProfileScope) -> Outcome {
        var applied: [String] = []
        if let name = value(entry, field: "Name"), !name.isEmpty, let profile = JournalProfileSync.profileRow(in: context) {
            profile.setValue(name, forKey: "name")
            do { try context.save() } catch { context.rollback(); return .failed(error.localizedDescription) }
            applied.append("name")
        }
        if let location = value(entry, field: "Location") {
            ProfileStore.commitLocation(location, for: scope.locationUserID)
            applied.append("location")
        }
        guard !applied.isEmpty else { return .failed("Only the instrument was displaced; choose it again in the instrument list.") }
        NotificationCenter.default.post(name: JournalProfileSync.didApplyNotification, object: nil)
        return .restored("Restored \(applied.joined(separator: " and ")) as a new edit")
    }

    private static func restoreScoreTitle(_ entry: JournalSyncConflict, id: String) -> Outcome {
        guard let uuid = UUID(uuidString: id), let item = ScoreLibraryStore.shared.items.first(where: { $0.id == uuid }) else {
            return .failed("That score is no longer in the library.")
        }
        guard let title = value(entry, field: "Title"), !title.isEmpty else { return .failed("Only the star or cover page was displaced; set it again in the library.") }
        ScoreLibraryStore.shared.rename(item, to: title)
        return .restored("Restored the title as a new edit")
    }

    private static func fetch(_ entity: String, id: UUID, in context: NSManagedObjectContext) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }
}

/// A short, readable name for a session, for the recovery list.
enum JournalRecoverySubject {
    static func session(_ object: NSManagedObject) -> String {
        let title = (object.value(forKey: "title") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let date = object.value(forKey: "timestamp") as? Date
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .short
        let when = date.map { formatter.string(from: $0) } ?? ""
        return title.isEmpty ? "Entry \(when)" : "\(title) · \(when)"
    }
}
