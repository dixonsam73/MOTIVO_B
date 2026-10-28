//
//  JournalRecovery.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
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

#if SYNCTEST
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
            return entry.hasRecoverableText
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
            outcome = restoreAttachmentName(entry, id: String(restore.dropFirst("attachment:".count)), context: context)
        } else if restore == "profile" {
            outcome = restoreProfile(entry, context: context, scope: scope ?? JournalSyncCoordinator.shared.engine?.profileScope ?? .local)
        } else if restore.hasPrefix("score:") {
            outcome = restoreScoreTitle(entry, id: String(restore.dropFirst("score:".count)))
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
        var applied: [String] = []
        if let title = value(entry, field: "Title") { session.setValue(title, forKey: "title"); applied.append("title") }
        if let notes = value(entry, field: "Notes") { session.setValue(notes, forKey: "notes"); applied.append("notes") }
        guard !applied.isEmpty else { return .failed("Nothing to restore.") }
        do { try context.save() } catch { context.rollback(); return .failed(error.localizedDescription) }
        return .restored("Restored \(applied.joined(separator: " and ")) as a new edit")
    }

    private static func restoreAttachmentName(_ entry: JournalSyncConflict, id: String, context: NSManagedObjectContext) -> Outcome {
        guard let uuid = UUID(uuidString: id), let attachment = fetch("Attachment", id: uuid, in: context) else {
            return .failed("That attachment is no longer in the journal.")
        }
        guard let name = value(entry, field: "Name") else { return .failed("Nothing to restore.") }
        let kind = attachment.value(forKey: "kind") as? String
        if let titleKind = JournalMetadataCodec.titleKind(for: kind) {
            // Audio and video: the app's own title writer (side store + displayName).
            AttachmentTitlePersistenceKeys.writeLocalTitle(name, kind: titleKind, attachmentID: uuid)
        } else {
            attachment.setValue(name, forKey: "displayName")
            do { try context.save() } catch { context.rollback(); return .failed(error.localizedDescription) }
        }
        return .restored("Restored the name as a new edit")
    }

    private static func restoreProfile(_ entry: JournalSyncConflict, context: NSManagedObjectContext, scope: JournalProfileScope) -> Outcome {
        var applied: [String] = []
        if let name = value(entry, field: "Name"), !name.isEmpty, let profile = JournalProfileSync.profileRow(in: context) {
            profile.setValue(name, forKey: "name")
            do { try context.save() } catch { context.rollback(); return .failed(error.localizedDescription) }
            applied.append("name")
        }
        if let location = value(entry, field: "Location") {
            ProfileStore.setLocation(location, for: scope.locationUserID)
            if scope.locationUserID != nil { ProfileStore.setLocation(location, for: nil) }
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
#endif
