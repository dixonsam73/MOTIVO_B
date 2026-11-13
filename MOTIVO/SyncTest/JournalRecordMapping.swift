//
//  JournalRecordMapping.swift
//  MOTIVO — private iCloud sync. Compiled in every configuration; nothing
//  here runs until the person turns sync on (see JournalSyncCoordinator).
//
//  CORE DATA ↔ CKRECORD FOR SESSION AND ATTACHMENT, AND THE TRIAL CONFLICT RULE.
//
//  Media stays as files: an Attachment record carries a CKAsset built from the
//  resolved local file, and an imported asset is materialised at
//  Documents/<id>.<ext>, which is where AttachmentPathResolver and the viewers
//  already look. Nothing is stored in a Core Data binary attribute.
//
//  Conflict rule (TRIAL POLICY, not the shipping design): the record whose
//  `userModifiedAt` is later wins as a whole; ties go to the server; a missing
//  stamp counts as the distant past. The loser's title and notes are kept in
//  the state file's conflict log so nothing silently disappears during the
//  trial. Limits: device clocks can disagree, and a whole-record winner cannot
//  merge edits to different fields.
//

import Foundation
import CloudKit
import CoreData
import CryptoKit

/// SHA-256 of a file, with a "size|mtime|hash" cache so an unchanged file is
/// hashed once. Pure apart from reading the file.
enum JournalAssetHash {
    static func stamp(of url: URL) -> (size: Int64, mtime: TimeInterval)? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return (size, mtime)
    }

    static func hash(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Returns the hash and the cache entry to store ("size|mtime|hash").
    static func cachedHash(of url: URL, cache: String?) -> (hash: String, entry: String)? {
        guard let stamp = stamp(of: url) else { return nil }
        let prefix = "\(stamp.size)|\(Int(stamp.mtime))|"
        if let cache, cache.hasPrefix(prefix) { return (String(cache.dropFirst(prefix.count)), cache) }
        guard let hash = hash(of: url) else { return nil }
        return (hash, prefix + hash)
    }
}

/// PURE. Whether an outgoing attachment record carries its file.
enum JournalAssetPolicy {
    /// A new record (no server copy) always carries it; otherwise only when
    /// the server's hash is unknown or differs from the local file's.
    static func includeAsset(hasServerCopy: Bool, serverHash: String?, localHash: String?, assetFree: Bool = false) -> Bool {
        // Stage F: a metadata change never carries the file, whatever this
        // device knows about the server's hash; the server keeps its asset.
        if assetFree, hasServerCopy { return false }
        guard hasServerCopy, let serverHash, let localHash else { return true }
        return serverHash != localHash
    }

    /// The record types whose save can carry a file (stage J: the ones a
    /// rebuilt engine asks the server about before its first batch).
    static func carriesFile(recordType: String?) -> Bool {
        recordType == JournalSyncRecordType.attachment || recordType == JournalSyncRecordType.score
            || recordType == JournalSyncRecordType.profileAvatar
    }
}

enum JournalConflictWinner: Equatable { case server, local }

enum JournalConflictRule {
    static func decide(localUserModifiedAt: Date?, serverUserModifiedAt: Date?) -> JournalConflictWinner {
        let local = localUserModifiedAt ?? .distantPast
        let server = serverUserModifiedAt ?? .distantPast
        return local > server ? .local : .server
    }
}

extension CKRecord: CKRecordLike {
    func set(_ key: String, _ value: NSObject?) { self[key] = value as? CKRecordValue }
}

enum JournalRecordMapping {
    /// "Journal" in every build; see `JournalSyncCapability.zoneName` for the trial build's one exception.
    static let zoneID = CKRecordZone.ID(zoneName: JournalSyncCapability.zoneName, ownerName: CKCurrentUserDefaultName)

    static let sessionKeys = ["title", "notes", "timestamp", "durationSeconds", "activityType", "activityDetail",
                              "mood", "effort", "threadLabel", "userInstrumentLabel", "userActivityLabel",
                              "areNotesPrivate", "isPublic", "ownerUserID", "userModifiedAt"]
    /// No `ownerUserID`: an attachment's owner follows its session locally, so
    /// giving a journal its owner never re-sends media. Stage G: content only;
    /// name and star live on the meta record.
    static let attachmentKeys = ["kind", "createdAt", "userModifiedAt"]
    /// Fields older builds wrote on the Attachment record; applied on import
    /// only until a meta record for that attachment has been seen.
    static let legacyAttachmentMetaKeys = ["displayName", "isThumbnail"]
    static let metaKeys = ["displayName", "isThumbnail", "userModifiedAt"]
    /// Custom rows: no owner either; an import is stamped with this install's K2.
    static let userInstrumentKeys = ["displayName", "normalizedName", "displayOrder", "isVisibleOnProfile"]
    static let userActivityKeys = ["displayName", "normalizedName", "coreActivityCode"]
    static let instrumentKeys = ["name"]
    /// A session's (or a custom instrument's) link to a profile instrument:
    /// the reference by id, plus the name so it resolves before, or without,
    /// the Instrument record itself.
    static let instrumentRefKey = "instrumentRef"
    static let instrumentNameKey = "instrumentName"
    static let savedListNameKey = "name"
    static let savedListItemsKey = "items"
    static let assetKey = "file"
    static let fileExtKey = "fileExt"
    /// SHA-256 of the media; set only together with the asset.
    static let fileHashKey = "fileHash"
    static let sessionRefKey = "session"
    /// Every field the importer reads, except the asset: the catch-up fetch
    /// asks for these so a changed record never brings its file along unless
    /// the hash says the file changed.
    static var keysWithoutAsset: [String] {
        Array(Set(sessionKeys + attachmentKeys + legacyAttachmentMetaKeys + metaKeys + instrumentKeys + userInstrumentKeys
                  + userActivityKeys + [instrumentRefKey, instrumentNameKey, savedListNameKey, savedListItemsKey,
                                        fileExtKey, fileHashKey, sessionRefKey, JournalProfileKeys.location,
                                        JournalMetadataKeys.isPrivate, JournalMetadataKeys.selectedPages, JournalMetadataKeys.isSaved]
                  + JournalScoreKeys.all + JournalSettingsKeys.all))
    }

    static func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    // MARK: Core Data → CKRecord

    /// Starts from the last known server copy (so the change tag matches) or a
    /// fresh record, then writes every mapped field. `ownerOnly` sends just
    /// the owner key on an existing session record. `includeAsset` decides
    /// whether an attachment record carries its file (and `fileHash`); when
    /// it does not, the server keeps the asset it has.
    static func record(for object: NSManagedObject, base: CKRecord?, ownerOnly: Bool = false,
                       includeAsset: Bool = true, fileHash: String? = nil, viewerScope: String? = nil) -> CKRecord? {
        guard let entity = object.entity.name, let id = object.value(forKey: "id") as? UUID else { return nil }
        let record = base ?? CKRecord(recordType: entity, recordID: recordID(for: id))
        guard record.recordType == entity else { return nil }
        switch entity {
        case JournalSyncRecordType.session:
            if ownerOnly, base != nil {
                record["ownerUserID"] = ckValue(object.value(forKey: "ownerUserID"))
                return record
            }
            for key in sessionKeys { record[key] = ckValue(object.value(forKey: key)) }
            setInstrumentLink(record, object.value(forKey: "instrument") as? NSManagedObject)
            if let viewerScope { JournalMetadataFields.setSessionFields(on: record, id: id, viewerScope: viewerScope) }
        case JournalSyncRecordType.instrument:
            for key in instrumentKeys { record[key] = ckValue(object.value(forKey: key)) }
        case JournalSyncRecordType.userInstrument:
            for key in userInstrumentKeys { record[key] = ckValue(object.value(forKey: key)) }
            setInstrumentLink(record, object.value(forKey: "coreInstrument") as? NSManagedObject)
        case JournalSyncRecordType.userActivity:
            for key in userActivityKeys { record[key] = ckValue(object.value(forKey: key)) }
        case JournalSyncRecordType.attachment:
            for key in attachmentKeys { record[key] = ckValue(object.value(forKey: key)) }
            if let session = object.value(forKey: "session") as? NSManagedObject,
               let sid = session.value(forKey: "id") as? UUID {
                record[sessionRefKey] = CKRecord.Reference(recordID: recordID(for: sid), action: .none)
            } else {
                record[sessionRefKey] = nil
            }
            let stored = object.value(forKey: "fileURL") as? String
            if let url = AttachmentPathResolver.resolve(stored) {
                if includeAsset {
                    record[assetKey] = CKAsset(fileURL: url)
                    record[fileExtKey] = url.pathExtension as CKRecordValue
                    record[fileHashKey] = fileHash.map { $0 as CKRecordValue }
                }
            } else if base == nil {
                record[fileExtKey] = (URL(fileURLWithPath: stored ?? "").pathExtension) as CKRecordValue
            }
        default:
            return nil
        }
        return record
    }

    /// Stage G: the small record a metadata edit sends. `base` is the last
    /// server copy of the META record.
    static func metaRecord(for attachment: NSManagedObject, base: CKRecord?) -> CKRecord? {
        guard attachment.entity.name == JournalSyncRecordType.attachment,
              let id = attachment.value(forKey: "id") as? UUID else { return nil }
        let name = JournalSyncRecordType.metaName(for: id.uuidString)
        let record = base ?? CKRecord(recordType: JournalSyncRecordType.attachmentMeta,
                                      recordID: CKRecord.ID(recordName: name, zoneID: zoneID))
        guard record.recordType == JournalSyncRecordType.attachmentMeta else { return nil }
        for key in metaKeys { record[key] = ckValue(attachment.value(forKey: key)) }
        // Always present once written by this build: "" is "no name / cleared".
        if record["displayName"] == nil { record["displayName"] = "" as CKRecordValue }
        JournalMetadataFields.setAttachmentFields(on: record, id: id)
        return record
    }

    /// Applies a meta record's Core Data part (name and star). An absent
    /// displayName is no information. Side stores are the importer's.
    static func applyMeta(_ record: CKRecord, to attachment: NSManagedObject) {
        if let name = record["displayName"] as? String { attachment.setValue(name, forKey: "displayName") }
        if let star = record["isThumbnail"] as? NSNumber { attachment.setValue(star.boolValue, forKey: "isThumbnail") }
    }

    private static func setInstrumentLink(_ record: CKRecord, _ instrument: NSManagedObject?) {
        if let instrument, let id = instrument.value(forKey: "id") as? UUID {
            record[instrumentRefKey] = CKRecord.Reference(recordID: recordID(for: id), action: .none)
            record[instrumentNameKey] = (instrument.value(forKey: "name") as? String).map { $0 as CKRecordValue }
        } else {
            record[instrumentRefKey] = nil
            record[instrumentNameKey] = nil
        }
    }

    /// The instrument a session or custom row points at, as (record name, name).
    static func instrumentLink(of record: CKRecord) -> (recordName: String?, name: String?) {
        ((record[instrumentRefKey] as? CKRecord.Reference)?.recordID.recordName, record[instrumentNameKey] as? String)
    }

    private static func ckValue(_ value: Any?) -> CKRecordValue? {
        switch value {
        case nil: return nil
        case let s as String: return s as CKRecordValue
        case let d as Date: return d as CKRecordValue
        case let b as Bool: return NSNumber(value: b)
        case let n as NSNumber: return n
        case let i as Int16: return NSNumber(value: i)
        case let i as Int64: return NSNumber(value: i)
        case let i as Int: return NSNumber(value: i)
        default: return nil
        }
    }

    // MARK: CKRecord → Core Data

    /// Writes the record's fields onto an existing or new object. Returns false
    /// when the record is of an unknown type.
    static func apply(_ record: CKRecord, to object: NSManagedObject, legacyMetadata: Bool = false) -> Bool {
        let keys: [String]
        switch record.recordType {
        case JournalSyncRecordType.session: keys = sessionKeys
        case JournalSyncRecordType.attachment: keys = legacyMetadata ? attachmentKeys + legacyAttachmentMetaKeys : attachmentKeys
        case JournalSyncRecordType.userInstrument: keys = userInstrumentKeys
        case JournalSyncRecordType.userActivity: keys = userActivityKeys
        case JournalSyncRecordType.instrument: keys = instrumentKeys
        default: return false
        }
        if object.value(forKey: "id") == nil, let id = UUID(uuidString: record.recordID.recordName) {
            object.setValue(id, forKey: "id")
        }
        let attributes = object.entity.attributesByName
        for key in keys {
            guard let attribute = attributes[key] else { continue }
            let raw = record[key]
            // An attachment record without displayName was written before
            // names synced: no information, so the local value stays.
            if key == "displayName", record.recordType == JournalSyncRecordType.attachment, raw == nil { continue }
            switch attribute.attributeType {
            case .booleanAttributeType:
                if let n = raw as? NSNumber { object.setValue(n.boolValue, forKey: key) }
                else if !attribute.isOptional { object.setValue(attribute.defaultValue ?? false, forKey: key) }
            case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
                if let n = raw as? NSNumber { object.setValue(n, forKey: key) }
                else if !attribute.isOptional { object.setValue(attribute.defaultValue ?? 0, forKey: key) }
            case .stringAttributeType:
                if let s = raw as? String { object.setValue(s, forKey: key) }
                else if attribute.isOptional { object.setValue(nil, forKey: key) }
                else { object.setValue("", forKey: key) }
            case .dateAttributeType:
                if let d = raw as? Date { object.setValue(d, forKey: key) }
                else if attribute.isOptional { object.setValue(nil, forKey: key) }
                else { object.setValue(Date(), forKey: key) }
            default:
                object.setValue(raw, forKey: key)
            }
        }
        // `fileURL` is required but device-specific: a fresh import points at the
        // materialised location so the resolver's filename match finds the bytes.
        if record.recordType == JournalSyncRecordType.attachment, object.value(forKey: "fileURL") == nil {
            let ext = (record[fileExtKey] as? String) ?? ""
            object.setValue(materialisedURL(recordName: record.recordID.recordName, ext: ext).path, forKey: "fileURL")
        }
        return true
    }

    // MARK: SavedList (UserDefaults, not Core Data)

    /// The list's lines as JSON. `sourceSendID` is local provenance and stays
    /// on the device.
    static func record(for list: SavedList, base: CKRecord?) -> CKRecord? {
        let record = base ?? CKRecord(recordType: JournalSyncRecordType.savedList, recordID: recordID(for: list.id))
        guard record.recordType == JournalSyncRecordType.savedList,
              let items = try? JSONEncoder().encode(list.items) else { return nil }
        record[savedListNameKey] = list.name as CKRecordValue
        record[savedListItemsKey] = items as CKRecordValue
        return record
    }

    static func savedList(from record: CKRecord) -> SavedList? {
        guard record.recordType == JournalSyncRecordType.savedList,
              let id = UUID(uuidString: record.recordID.recordName),
              let name = record[savedListNameKey] as? String,
              let data = record[savedListItemsKey] as? Data,
              let items = try? JSONDecoder().decode([SavedListLine].self, from: data) else { return nil }
        return SavedList(id: id, name: name, items: items)
    }

    static func userModifiedAt(of record: CKRecord) -> Date? { record["userModifiedAt"] as? Date }

    // MARK: Content comparison (C-197)

    /// The fields whose difference is a difference in content, for the type of
    /// `server`. Never the owner or the clock. A Session carries all of its
    /// Core Data fields, so an absent one is a cleared one. The side-store
    /// choices (a session's favourite; an attachment's privacy and pages) and
    /// an attachment's legacy name and star count only when BOTH records
    /// carry them: absent there means "no information".
    static func differingContentKeys(local: CKRecord, server: CKRecord) -> [String] {
        let always: [String], whenBothCarry: [String]
        switch server.recordType {
        case JournalSyncRecordType.session:
            always = sessionKeys.filter { $0 != "ownerUserID" && $0 != "userModifiedAt" } + [instrumentNameKey]
            whenBothCarry = [JournalMetadataKeys.isSaved]
        case JournalSyncRecordType.attachment:
            always = ["kind", "createdAt"]; whenBothCarry = legacyAttachmentMetaKeys
        case JournalSyncRecordType.attachmentMeta:
            always = ["displayName", "isThumbnail"]; whenBothCarry = [JournalMetadataKeys.isPrivate, JournalMetadataKeys.selectedPages]
        default:
            return []
        }
        func same(_ a: NSObject?, _ b: NSObject?) -> Bool {
            switch (a, b) {
            case (nil, nil): return true
            case (let x as NSString, nil), (nil, let x as NSString): return x.length == 0      // "" and absent are both "none"
            case (let x as NSDate, let y as NSDate): return abs(x.timeIntervalSince(y as Date)) < 0.001
            case (let x?, let y?): return x.isEqual(y)
            default: return false
            }
        }
        return always.filter { !same(local[$0] as? NSObject, server[$0] as? NSObject) }
            + whenBothCarry.filter { local[$0] != nil && server[$0] != nil && !same(local[$0] as? NSObject, server[$0] as? NSObject) }
    }

    /// A field's name for people ("Duration"), for the Displaced by sync list.
    static func fieldLabel(_ key: String) -> String {
        switch key {
        case "durationSeconds": return "Duration"
        case "timestamp", "createdAt": return "Date"
        case "activityType", "activityDetail", "userActivityLabel": return "Activity"
        case "userInstrumentLabel", instrumentNameKey: return "Instrument"
        case "threadLabel": return "Thread"
        case "areNotesPrivate": return "Notes privacy"
        case "isPublic": return "Sharing"
        case "isThumbnail": return "Star"
        case JournalMetadataKeys.isSaved: return "Favourite"
        case JournalMetadataKeys.isPrivate: return "Privacy"
        case JournalMetadataKeys.selectedPages: return "Pages"
        case "kind": return "Kind"
        default: return key.prefix(1).uppercased() + key.dropFirst()
        }
    }
    static func sessionRecordName(of attachment: CKRecord) -> String? {
        (attachment[sessionRefKey] as? CKRecord.Reference)?.recordID.recordName
    }

    /// Where an imported attachment's bytes live: the same convention the
    /// editor uses for its own files, so the resolver finds them by filename.
    static func materialisedURL(recordName: String, ext: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = ext.isEmpty ? recordName : "\(recordName).\(ext)"
        return docs.appendingPathComponent(name, isDirectory: false)
    }
}
