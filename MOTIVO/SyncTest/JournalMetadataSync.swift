//
//  JournalMetadataSync.swift
//  MOTIVO — private iCloud sync. Compiled in every configuration; nothing
//  here runs until the person turns sync on (see JournalSyncCoordinator).
//
//  JOURNAL METADATA THAT LIVES OUTSIDE CORE DATA (stage F): audio/video
//  titles, attachment privacy choices, favourites (saves) and selected PDF
//  pages. Each has a per-device side store and one write point in the app.
//
//  Rule: the side store becomes a FIELD of the owning record and Core Data
//  stays the clock. A user's metadata change touches the owning row under
//  the `metadata` author, so `userModifiedAt` stamps as a user edit, history
//  queues the row, and the record builder reads the side store. Titles also
//  write `Attachment.displayName`, the record's source of truth for a name.
//  Imports write the side stores through store-only setters (no hook, so no
//  loop); an absent field means "no information" and leaves the store alone,
//  so the existing private-by-default rule still applies where no choice
//  was ever made.
//
//  Representation of a cleared value, so the next sync cannot restore an
//  older one: title cleared = displayName "" (never nil once migrated);
//  favourite removed = isSaved 0; pages = JSON string, "[]" = whole document;
//  privacy = isPrivate 0/1 (there is no "cleared" privacy).
//
//  Migration (once per device, idempotent, flag set last): every row with
//  side-store values is queued with its EXISTING userModifiedAt (titles are
//  written to displayName under the unstamped `migration` author), so a later
//  real edit elsewhere still wins under the existing conflict rule.
//

import Foundation
import CoreData
import CloudKit

enum JournalMetadataKeys {
    static let isPrivate = "isPrivate"
    static let selectedPages = "selectedPages"
    static let isSaved = "isSaved"
}

/// Pure encodings of the side-store values on a record.
enum JournalMetadataCodec {
    static func pagesString(_ pages: [Int]?) -> String {
        let clean = PDFSelectedPagesStore.sanitized(pages) ?? []
        return (try? String(data: JSONEncoder().encode(clean), encoding: .utf8)) ?? "[]"
    }

    /// nil when the field is absent (no information); [] for "whole document".
    static func pages(from string: String?) -> [Int]? {
        guard let string, let data = string.data(using: .utf8),
              let pages = try? JSONDecoder().decode([Int].self, from: data) else { return nil }
        return pages
    }

    static func privacyKey(_ id: UUID) -> String { AttachmentPrivacy.privacyKey(id: id, url: nil) ?? "id://\(id.uuidString)" }

    /// The viewer scope favourites are keyed by (mirrors `effectiveViewerUserID`).
    static func viewerScope(currentUserID: String?) -> String {
        let trimmed = (currentUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    static func titleKind(for attachmentKind: String?) -> AttachmentTitlePersistenceKeys.Kind? {
        switch (attachmentKind ?? "").lowercased() {
        case "audio": return .audio
        case "video": return .video
        default: return nil
        }
    }
}

/// The app's write points call this after writing their side
/// store: the owning row is touched so the change is a user edit in history.
enum JournalMetadataMirror {
    /// Set by the sync import while it writes side stores, so the hooks that
    /// the public setters fire do not queue the import back out.
    nonisolated(unsafe) static var suppressed = false
    /// The container to stamp rows in. Set by `JournalSyncCoordinator` once
    /// sync is in use on this install (tests point it at their own); nil
    /// before, so with sync off the write points change nothing in Core Data.
    nonisolated(unsafe) static var container: NSPersistentContainer? = nil

    static func attachmentChanged(_ id: UUID) { touch(entity: JournalSyncRecordType.attachment, id: id) }
    static func sessionChanged(_ id: UUID) { touch(entity: JournalSyncRecordType.session, id: id) }

    /// A title write also lands on `Attachment.displayName`, the synced field.
    static func titleChanged(_ id: UUID, title: String?) {
        guard !suppressed else { return }
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        write(entity: JournalSyncRecordType.attachment, id: id) { object in
            // "" is the explicit cleared value; nil would read as "never migrated".
            object.setValue(trimmed, forKey: "displayName")
        }
    }

    private static func touch(entity: String, id: UUID) {
        guard !suppressed else { return }
        write(entity: entity, id: id) { $0.setValue(Date(), forKey: "userModifiedAt") }
    }

    private static func write(entity: String, id: UUID, _ body: @escaping (NSManagedObject) -> Void) {
        // Sync off (never turned on here): the side store was written and
        // nothing else happens, exactly as before the sync existed.
        guard let container else { return }
        let ctx = container.newBackgroundContext()
        ctx.name = "metadataMirror"
        ctx.transactionAuthor = JournalSyncAuthor.metadata
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        ctx.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            guard let object = (try? ctx.fetch(request))?.first else { return }
            body(object)
            if ctx.hasChanges { try? ctx.save() }
        }
    }
}

/// Reads side stores into records and writes records into side stores.
enum JournalMetadataFields {
    /// Whether a record was written by a build that syncs metadata.
    static func recordCarriesMetadata(_ record: CKRecord) -> Bool {
        switch record.recordType {
        case JournalSyncRecordType.session: return record[JournalMetadataKeys.isSaved] != nil
        case JournalSyncRecordType.attachment:
            return record[JournalMetadataKeys.selectedPages] != nil || record[JournalMetadataKeys.isPrivate] != nil
        default: return false
        }
    }

    /// Fields an outgoing record carries beside the Core Data attributes.
    static func setAttachmentFields(on record: CKRecordLike, id: UUID) {
        if let choice = AttachmentPrivacy.currentMap()[JournalMetadataCodec.privacyKey(id)] {
            record.set(JournalMetadataKeys.isPrivate, NSNumber(value: choice))
        } else {
            record.set(JournalMetadataKeys.isPrivate, nil)
        }
        record.set(JournalMetadataKeys.selectedPages, JournalMetadataCodec.pagesString(PDFSelectedPagesStore.pages(for: id)) as NSString)
    }

    static func setSessionFields(on record: CKRecordLike, id: UUID, viewerScope: String) {
        record.set(JournalMetadataKeys.isSaved, NSNumber(value: FeedInteractionStore.isSaved(id, viewerUserID: viewerScope)))
    }

    /// Applies a received attachment record's side fields. `displayName` is
    /// already on the object; for audio/video it is mirrored into the title
    /// store the viewers read. Store-only: nothing here fires a hook.
    static func applyAttachment(isPrivate: NSNumber?, pages: String?, displayName: String?, kind: String?, id: UUID,
                                defaults: UserDefaults = .standard) {
        JournalMetadataMirror.suppressed = true
        defer { JournalMetadataMirror.suppressed = false }
        if let isPrivate { AttachmentPrivacy.setPrivate(id: id, url: nil, isPrivate.boolValue, mirror: false) }
        if let pages = JournalMetadataCodec.pages(from: pages) {
            PDFSelectedPagesStore.setPages(pages.isEmpty ? nil : pages, for: id, mirror: false)
        }
        if let titleKind = JournalMetadataCodec.titleKind(for: kind), let displayName {
            // "" removes the title everywhere; a name replaces every per-device override.
            AttachmentTitlePersistenceKeys.writeLocalTitle(displayName, kind: titleKind, attachmentID: id, defaults: defaults, mirror: false)
        }
    }

    static func applySession(isSaved: NSNumber?, id: UUID, viewerScope: String) {
        guard let isSaved else { return }
        JournalMetadataMirror.suppressed = true
        defer { JournalMetadataMirror.suppressed = false }
        FeedInteractionStore.setSaved(isSaved.boolValue, id, viewerUserID: viewerScope)
    }
}

/// Minimal record interface so the field helpers are testable without CloudKit.
protocol CKRecordLike: AnyObject {
    func set(_ key: String, _ value: NSObject?)
}

/// Once per device: every row with side-store values is queued with its
/// existing stamp. Title values move into `displayName` under the unstamped
/// `migration` author (a device-local title must not become a newer edit).
enum JournalMetadataMigration {
    struct Outcome: Equatable { var titles = 0; var privacy = 0; var pages = 0; var saves = 0 }

    static func run(container: NSPersistentContainer, defaults: UserDefaults = .standard,
                    privacyMap: [String: Bool], pagesMap: [String: [Int]], viewerScope: String,
                    enqueue: (String, String) -> Void) -> Outcome {
        var outcome = Outcome()
        let ctx = container.newBackgroundContext()
        ctx.transactionAuthor = JournalSyncAuthor.migration
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let audioTitles = (defaults.dictionary(forKey: AttachmentTitlePersistenceKeys.legacyKey(for: .audio)) as? [String: String]) ?? [:]
        let videoTitles = (defaults.dictionary(forKey: AttachmentTitlePersistenceKeys.legacyKey(for: .video)) as? [String: String]) ?? [:]
        ctx.performAndWait {
            let attachments = NSFetchRequest<NSManagedObject>(entityName: JournalSyncRecordType.attachment)
            for att in (try? ctx.fetch(attachments)) ?? [] {
                guard let id = att.value(forKey: "id") as? UUID else { continue }
                var queue = false
                let kind = att.value(forKey: "kind") as? String
                if let titleKind = JournalMetadataCodec.titleKind(for: kind), att.value(forKey: "displayName") == nil {
                    // Per-identity stores hold older overrides; the shared store is
                    // what the single writer maintains and the readers prefer only
                    // where a per-identity value exists. Shared wins here: it is the
                    // most recently written value for this id.
                    let titles = titleKind == .audio ? audioTitles : videoTitles
                    if let title = titles[id.uuidString]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                        att.setValue(title, forKey: "displayName")
                        outcome.titles += 1
                        queue = true
                    }
                }
                if privacyMap[JournalMetadataCodec.privacyKey(id)] != nil { outcome.privacy += 1; queue = true }
                if pagesMap[id.uuidString] != nil { outcome.pages += 1; queue = true }
                if queue { enqueue(id.uuidString, JournalSyncRecordType.attachment) }
            }
            let sessions = NSFetchRequest<NSManagedObject>(entityName: JournalSyncRecordType.session)
            for session in (try? ctx.fetch(sessions)) ?? [] {
                guard let id = session.value(forKey: "id") as? UUID else { continue }
                if FeedInteractionStore.isSaved(id, viewerUserID: viewerScope, defaults: defaults) {
                    outcome.saves += 1
                    enqueue(id.uuidString, JournalSyncRecordType.session)
                }
            }
            if ctx.hasChanges { try? ctx.save() }
        }
        return outcome
    }

    /// C-176 (upgrade trial, 2026-11-04): recordings made before the title
    /// store existed carry their typed name only as the FILE name (the
    /// editor shows the stem when no title is stored), and the sync carries
    /// `displayName` only, materialising files as `<id>.<ext>` on the other
    /// device, which then showed the id. Once, after the title migration: a
    /// row with no `displayName` and no stored title takes its file stem,
    /// unless the stem is the app's own id naming. Returns the rows changed.
    static func adoptFileNameTitles(container: NSPersistentContainer, defaults: UserDefaults = .standard,
                                    enqueue: (String, String) -> Void) -> Int {
        var adopted = 0
        let ctx = container.newBackgroundContext()
        ctx.transactionAuthor = JournalSyncAuthor.migration
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        let audioTitles = (defaults.dictionary(forKey: AttachmentTitlePersistenceKeys.legacyKey(for: .audio)) as? [String: String]) ?? [:]
        let videoTitles = (defaults.dictionary(forKey: AttachmentTitlePersistenceKeys.legacyKey(for: .video)) as? [String: String]) ?? [:]
        ctx.performAndWait {
            let attachments = NSFetchRequest<NSManagedObject>(entityName: JournalSyncRecordType.attachment)
            for att in (try? ctx.fetch(attachments)) ?? [] {
                guard let id = att.value(forKey: "id") as? UUID,
                      let titleKind = JournalMetadataCodec.titleKind(for: att.value(forKey: "kind") as? String),
                      att.value(forKey: "displayName") == nil,
                      let path = att.value(forKey: "fileURL") as? String, !path.isEmpty else { continue }
                let stored = ((titleKind == .audio ? audioTitles : videoTitles)[id.uuidString] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard stored.isEmpty, let stem = fileNameTitle(path: path) else { continue }
                att.setValue(stem, forKey: "displayName")
                adopted += 1
                enqueue(id.uuidString, JournalSyncRecordType.attachment)
            }
            if ctx.hasChanges { try? ctx.save() }
        }
        return adopted
    }

    /// PURE. The stem of a user-named file; nil for the app's `<id>.<ext>` naming or an empty stem.
    static func fileNameTitle(path: String) -> String? {
        let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stem.isEmpty, UUID(uuidString: stem) == nil else { return nil }
        return stem
    }
}
