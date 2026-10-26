//
//  JournalProfileSync.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
//
//  PRIVATE PROFILE SYNC (stage H): name, location, primary instrument and
//  avatar, through the bound private iCloud journal, with no Connected login.
//
//  Two fixed-name records in the Journal zone. `Profile` ("profile") carries
//  name, location and the primary instrument (as the stage C instrument link:
//  reference by id plus the name). `ProfileAvatar` ("profile-avatar") carries
//  the derived 256 px PNG as a CKAsset with its SHA-256, on its own record so a
//  name or location edit never carries or delivers the avatar (stage G's
//  metadata/media separation). Clearing is explicit: "" for a text field, a
//  record with no asset and fileHash "" for a removed avatar. The avatar record
//  is never deleted, so a removal always has a clock.
//
//  Change detection is a fingerprint scan, as for saved Lists: the Profile row
//  has no stamp attribute and the location (UserDefaults) and avatar (files)
//  live outside Core Data. Write points call `JournalProfileMirror`; the engine
//  scans on a short debounce and at every activation. The profile's clock is
//  the scan time of the change (`profileStamp`); the avatar's clock is the
//  file's modification date, which the import also sets, so both devices hold
//  the same time for the same image.
//
//  Conflict rule: the existing one. The newer `userModifiedAt` wins the whole
//  record, ties go to the server, and the displaced values are kept in the
//  conflict log (text) or as a file (avatar, restorable from diagnostics). A
//  profile that existed before this build first ran is sent UNSTAMPED, so a
//  real edit anywhere beats it. Two unstamped established profiles meet
//  field by field: a blank never displaces a value; two different values
//  resolve to the longer one (equal length: Unicode order), whichever arrived
//  first, so both devices compute the same result and converge in one round.
//
//  A profile that was never meaningful (name and location both empty) and
//  never edited is not uploaded, and a change to it is not an edit: the app
//  writes a default primary instrument on its own, and that must never beat an
//  established profile from the other device.
//
//  Nothing here starts any Connected work. Imports write the avatar through
//  writers that set no pending Solo→Connected marker; the only paths that reach
//  Supabase (`ProfileMaintenancePolicy`, directory hydration) need a Connected
//  identity, and `ConnectedWriteWitness` counts every attempt for the record.
//

#if SYNCTEST
import Foundation
import CloudKit
import CoreData
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

extension JournalSyncRecordType {
    static let profile = "Profile"
    static let profileAvatar = "ProfileAvatar"
    static let profileRecordName = "profile"
    static let profileAvatarRecordName = "profile-avatar"
    static let profileTypes: Set<String> = [profile, profileAvatar]
    static func isProfileRecordName(_ name: String) -> Bool { name == profileRecordName || name == profileAvatarRecordName }
}

enum JournalProfileKeys {
    static let name = "name"
    static let location = "location"
    static let stamp = "userModifiedAt"
}

/// Which scopes the screens present (`ProfileView` reads the location under the
/// backend id, falling back to the local profile, and the avatar under the
/// owner key). Read on the main actor before each cycle, like the viewer scope.
struct JournalProfileScope: Equatable {
    var locationUserID: String?
    var avatarUserID: String?
    static let local = JournalProfileScope(locationUserID: nil, avatarUserID: nil)
}

/// The three text fields of the profile, trimmed. "" is "none / cleared".
struct JournalProfileValues: Equatable {
    var name = ""
    var location = ""
    var primaryInstrument = ""

    /// A profile with no name and no location is the app's default: the primary
    /// instrument alone is written by the app itself.
    var isMeaningful: Bool { !name.isEmpty || !location.isEmpty }

    private static let separator = "\u{1F}"
    var fingerprint: String { ["v1", name, location, primaryInstrument].joined(separator: Self.separator) }

    init(name: String = "", location: String = "", primaryInstrument: String = "") {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        self.primaryInstrument = primaryInstrument.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init?(fingerprint: String?) {
        guard let fingerprint else { return nil }
        let parts = fingerprint.components(separatedBy: Self.separator)
        guard parts.count == 4, parts[0] == "v1" else { return nil }
        self.init(name: parts[1], location: parts[2], primaryInstrument: parts[3])
    }

    func describe() -> String {
        "name “\(name)” · location “\(location)” · instrument “\(primaryInstrument)”"
    }
}

/// PURE. How a server profile record combines with this device's.
enum JournalProfileMerge {
    struct Decision: Equatable {
        /// The values this device should hold afterwards; nil = unchanged.
        var apply: JournalProfileValues?
        /// Whether this device must (re)send its values on top of the server copy.
        var send = false
        /// Values that lost, for the conflict log ("field: value").
        var displaced: [String] = []
        var summary = ""
    }

    /// Two different non-empty values with no clock between them: the longer
    /// wins, equal lengths by Unicode order. Deterministic and symmetric.
    static func tieBreak(_ a: String, _ b: String) -> String {
        if a.count != b.count { return a.count > b.count ? a : b }
        return a < b ? a : b
    }

    static func fieldMerge(_ local: String, _ server: String) -> String {
        if local == server { return local }
        if local.isEmpty { return server }
        if server.isEmpty { return local }
        return tieBreak(local, server)
    }

    static func decide(local: JournalProfileValues, localStamp: Date?, localPending: Bool,
                       server: JournalProfileValues, serverStamp: Date?) -> Decision {
        var d = Decision()
        if local == server {
            d.summary = "same values"
            return d
        }
        if localStamp == nil, serverStamp == nil {
            // Two established profiles that predate this build: field by field.
            let merged = JournalProfileValues(name: fieldMerge(local.name, server.name),
                                              location: fieldMerge(local.location, server.location),
                                              primaryInstrument: fieldMerge(local.primaryInstrument, server.primaryInstrument))
            for (label, l, s, m) in [("name", local.name, server.name, merged.name),
                                     ("location", local.location, server.location, merged.location),
                                     ("instrument", local.primaryInstrument, server.primaryInstrument, merged.primaryInstrument)] {
                if !l.isEmpty, l != m { d.displaced.append("\(label) (this device): \(l)") }
                if !s.isEmpty, s != m { d.displaced.append("\(label) (other device): \(s)") }
            }
            if merged != local { d.apply = merged }
            d.send = merged != server
            d.summary = "merged field by field (no clock on either side)"
            return d
        }
        switch JournalConflictRule.decide(localUserModifiedAt: localStamp, serverUserModifiedAt: serverStamp) {
        case .server:
            if !localPending, localStamp == serverStamp {
                // Already applied here (an echo of a copy we hold).
                d.summary = "same clock; nothing to do"
                return d
            }
            d.apply = server
            for (label, l, s) in [("name", local.name, server.name), ("location", local.location, server.location),
                                  ("instrument", local.primaryInstrument, server.primaryInstrument)] where l != s && !l.isEmpty {
                d.displaced.append("\(label) (this device): \(l)")
            }
            d.summary = "server newer; applied"
        case .local:
            d.send = true
            for (label, l, s) in [("name", local.name, server.name), ("location", local.location, server.location),
                                  ("instrument", local.primaryInstrument, server.primaryInstrument)] where l != s && !s.isEmpty {
                d.displaced.append("\(label) (other device): \(s)")
            }
            d.summary = "local newer; kept and resent"
        }
        return d
    }

    /// The avatar: one value (the file's hash; "" = none), always clocked.
    enum AvatarOutcome: Equatable { case nothing, takeServer, keepLocalAndSend }
    static func decideAvatar(localHash: String, localStamp: Date?, localPending: Bool,
                             serverHash: String, serverStamp: Date?) -> AvatarOutcome {
        if localHash == serverHash { return .nothing }
        switch JournalConflictRule.decide(localUserModifiedAt: localStamp, serverUserModifiedAt: serverStamp) {
        case .server: return .takeServer
        case .local: return .keepLocalAndSend
        }
    }

    /// PURE. Whether a change found by the scan is a user edit. The app's own
    /// default primary instrument on a profile nobody has filled in is not.
    static func isEdit(previous: JournalProfileValues?, current: JournalProfileValues, everEdited: Bool) -> Bool {
        everEdited || current.isMeaningful || (previous?.isMeaningful ?? false)
    }
}

/// The app's write points call this (SYNCTEST only). Installed by the engine.
enum JournalProfileMirror {
    /// Set by the sync import while it writes, so its own writes do not scan.
    nonisolated(unsafe) static var suppressed = false
    nonisolated(unsafe) static var onChange: ((_ avatarRemoved: Bool) -> Void)?

    static func locationChanged() { guard !suppressed else { return }; onChange?(false) }
    static func avatarChanged() { guard !suppressed else { return }; onChange?(false) }
    static func avatarRemoved() { guard !suppressed else { return }; onChange?(true) }
}

/// SYNCTEST only: counts every attempt to write the Connected directory or the
/// Connected avatar object, whatever the outcome, so the device run can show
/// that private sync started none. Incremented at the four entry points.
enum ConnectedWriteWitness {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    static let directoryUpsert = "directory upsert"
    static let directoryAvatarKey = "directory avatar key"
    static let avatarUpload = "avatar upload"
    static let avatarDelete = "avatar delete"

    static func note(_ kind: String) {
        lock.lock(); defer { lock.unlock() }
        counts[kind, default: 0] += 1
    }

    static func count(_ kind: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[kind] ?? 0
    }

    static var total: Int {
        lock.lock(); defer { lock.unlock() }
        return counts.values.reduce(0, +)
    }

    static func resetForTesting() {
        lock.lock(); defer { lock.unlock() }
        counts.removeAll()
    }
}

/// Reads the device's profile, builds and applies records, and scans for changes.
enum JournalProfileSync {
    /// Posted (any thread) after an import changed the profile or the avatar;
    /// `ProfileView` re-reads name, location, primary and avatar on it.
    static let didApplyNotification = Notification.Name("JournalProfileSync.didApply")

    static let avatarName = JournalSyncRecordType.profileAvatarRecordName
    static let profileName = JournalSyncRecordType.profileRecordName

    // MARK: Current values

    /// Must be called on `context`'s queue.
    static func currentValues(context: NSManagedObjectContext, scope: JournalProfileScope) -> JournalProfileValues {
        var name = ""
        var primary = ""
        if let profile = profileRow(in: context) {
            context.refresh(profile, mergeChanges: false)
            name = profile.value(forKey: "name") as? String ?? ""
            primary = profile.value(forKey: "primaryInstrument") as? String ?? ""
        }
        return JournalProfileValues(name: name, location: ProfileStore.presentedLocation(for: scope.locationUserID), primaryInstrument: primary)
    }

    static func profileRow(in context: NSManagedObjectContext) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: JournalSyncRecordType.profile)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    struct LocalAvatar: Equatable {
        var url: URL?
        /// "" when there is no file.
        var hash = ""
        var modifiedAt: Date?
    }

    /// The presented avatar file, hashed through the stamp cache.
    static func currentAvatar(scope: JournalProfileScope, store: JournalSyncStateStore) -> LocalAvatar {
        guard let url = ProfileStore.avatarDerivedURL(for: scope.avatarUserID),
              FileManager.default.fileExists(atPath: url.path),
              let cached = JournalAssetHash.cachedHash(of: url, cache: store.state.fileStampCache[avatarName]) else { return LocalAvatar() }
        store.update { $0.fileStampCache[avatarName] = cached.entry }
        return LocalAvatar(url: url, hash: cached.hash, modifiedAt: JournalAssetHash.stamp(of: url).map { Date(timeIntervalSince1970: $0.mtime) })
    }

    // MARK: Scan (local changes → outbox)

    /// Compares the profile and avatar with what was last sent or received and
    /// queues what changed, recording the new fingerprint and clock in the same
    /// write. The first scan on a device (no fingerprint yet) is the
    /// transition: an established profile is queued UNSTAMPED, an empty one
    /// sets the baseline and sends nothing. Must be called on `context`'s queue.
    @discardableResult
    static func scan(context: NSManagedObjectContext, scope: JournalProfileScope, store: JournalSyncStateStore,
                     now: Date = Date()) -> [JournalSyncPendingChange] {
        let st = store.state
        guard !st.localRemovalInProgress else { return [] }
        let values = currentValues(context: context, scope: scope)
        let avatar = currentAvatar(scope: scope, store: store)
        var pending: [JournalSyncPendingChange] = []
        var newStamp = st.profileStamp
        var newFingerprint = st.profileFingerprint
        var note: String?

        if st.profileFingerprint == nil {
            newFingerprint = values.fingerprint
            if values.isMeaningful {
                pending.append(.init(recordName: profileName, recordType: JournalSyncRecordType.profile, op: .save, metadataOnly: true))
                note = "Profile transition: established profile queued without a clock (\(values.describe()))"
            } else {
                note = "Profile transition: default profile, nothing to send"
            }
        } else if st.profileFingerprint != values.fingerprint {
            let previous = JournalProfileValues(fingerprint: st.profileFingerprint)
            newFingerprint = values.fingerprint
            if JournalProfileMerge.isEdit(previous: previous, current: values, everEdited: st.profileStamp != nil) {
                newStamp = now
                pending.append(.init(recordName: profileName, recordType: JournalSyncRecordType.profile, op: .save))
                note = "Profile edited: \(values.describe())"
            } else {
                note = "Profile default changed on an empty profile (\(values.describe())); not an edit"
            }
        }

        var avatarRemovedAt = st.avatarRemovedAt
        if let known = st.assetHashes[avatarName] {
            if known != avatar.hash {
                if avatar.hash.isEmpty, avatarRemovedAt == nil { avatarRemovedAt = now }
                pending.append(.init(recordName: avatarName, recordType: JournalSyncRecordType.profileAvatar, op: .save))
            }
        } else if !avatar.hash.isEmpty, !st.outbox.contains(where: { $0.recordName == avatarName }) {
            // Never exchanged: send the file once it exists. Its clock is the file's.
            pending.append(.init(recordName: avatarName, recordType: JournalSyncRecordType.profileAvatar, op: .save))
        }

        let changed = !pending.isEmpty || newFingerprint != st.profileFingerprint || newStamp != st.profileStamp || avatarRemovedAt != st.avatarRemovedAt
        guard changed else { return [] }
        let ok = store.update { s in
            JournalChangeTracker.merge(pending, into: &s.outbox)
            s.profileFingerprint = newFingerprint
            s.profileStamp = newStamp
            s.avatarRemovedAt = avatarRemovedAt
            if let note { s.log.append(.init(at: now, text: note)) }
        }
        return ok ? pending : []
    }

    // MARK: Records (Core Data + stores → CKRecord)

    /// The Profile record. `instrument(named:)` resolves the primary to this
    /// device's Instrument row for the reference. Must run on the context's queue.
    static func profileRecord(context: NSManagedObjectContext, scope: JournalProfileScope, store: JournalSyncStateStore,
                              instrument: (String) -> NSManagedObject?) -> CKRecord {
        let base = store.state.lastKnownRecords[profileName].flatMap(JournalSyncStateStore.recordFromSystemFields)
        let record = (base?.recordType == JournalSyncRecordType.profile ? base : nil)
            ?? CKRecord(recordType: JournalSyncRecordType.profile, recordID: CKRecord.ID(recordName: profileName, zoneID: JournalRecordMapping.zoneID))
        let values = currentValues(context: context, scope: scope)
        record[JournalProfileKeys.name] = values.name as CKRecordValue
        record[JournalProfileKeys.location] = values.location as CKRecordValue
        if !values.primaryInstrument.isEmpty, let row = instrument(values.primaryInstrument), let id = row.value(forKey: "id") as? UUID {
            record[JournalRecordMapping.instrumentRefKey] = CKRecord.Reference(recordID: JournalRecordMapping.recordID(for: id), action: .none)
        } else {
            record[JournalRecordMapping.instrumentRefKey] = nil
        }
        record[JournalRecordMapping.instrumentNameKey] = values.primaryInstrument as CKRecordValue
        record[JournalProfileKeys.stamp] = store.state.profileStamp.map { $0 as CKRecordValue }
        return record
    }

    /// The avatar record: the file and its hash, clocked by the file's
    /// modification date; or no asset, hash "" and the removal time.
    static func avatarRecord(scope: JournalProfileScope, store: JournalSyncStateStore, now: Date = Date()) -> CKRecord {
        let base = store.state.lastKnownRecords[avatarName].flatMap(JournalSyncStateStore.recordFromSystemFields)
        let record = (base?.recordType == JournalSyncRecordType.profileAvatar ? base : nil)
            ?? CKRecord(recordType: JournalSyncRecordType.profileAvatar, recordID: CKRecord.ID(recordName: avatarName, zoneID: JournalRecordMapping.zoneID))
        let avatar = currentAvatar(scope: scope, store: store)
        if let url = avatar.url {
            record[JournalRecordMapping.assetKey] = CKAsset(fileURL: url)
            record[JournalRecordMapping.fileHashKey] = avatar.hash as CKRecordValue
            record[JournalProfileKeys.stamp] = (avatar.modifiedAt ?? now) as CKRecordValue
        } else {
            record[JournalRecordMapping.assetKey] = nil
            record[JournalRecordMapping.fileHashKey] = "" as CKRecordValue
            record[JournalProfileKeys.stamp] = (store.state.avatarRemovedAt ?? now) as CKRecordValue
        }
        return record
    }

    static func values(of record: CKRecord) -> JournalProfileValues {
        JournalProfileValues(name: record[JournalProfileKeys.name] as? String ?? "",
                             location: record[JournalProfileKeys.location] as? String ?? "",
                             primaryInstrument: record[JournalRecordMapping.instrumentNameKey] as? String ?? "")
    }

    // MARK: Import (CKRecord → Core Data + stores)

    struct Outcome { var applied = 0; var resend: [JournalSyncPendingChange] = []; var avatarBytes: Int64 = 0; var avatarChanged = false }

    /// Applies a Profile record. `localPending` is true for a rejected send
    /// (serverRecordChanged). Must run on `context`'s queue (author `sync`).
    static func applyProfile(_ record: CKRecord, context: NSManagedObjectContext, scope: JournalProfileScope, store: JournalSyncStateStore,
                             importer: JournalImporter, localPending: Bool? = nil, log: (String) -> Void) -> Outcome {
        var outcome = Outcome()
        let st = store.state
        let pending = localPending ?? st.outbox.contains { $0.recordName == profileName && $0.op == .save }
        let local = currentValues(context: context, scope: scope)
        let server = values(of: record)
        let serverStamp = record[JournalProfileKeys.stamp] as? Date
        let decision = JournalProfileMerge.decide(local: local, localStamp: st.profileStamp, localPending: pending, server: server, serverStamp: serverStamp)
        if !decision.displaced.isEmpty {
            let conflict = JournalSyncConflict(at: Date(), recordName: profileName, recordType: JournalSyncRecordType.profile,
                                               winner: decision.apply == nil ? "local" : (decision.send ? "merged" : "server"),
                                               localUserModifiedAt: st.profileStamp, serverUserModifiedAt: serverStamp,
                                               losingTitle: "displaced: " + decision.displaced.joined(separator: " · "), losingNotes: nil)
            store.update { $0.conflicts.append(conflict) }
        }
        if let apply = decision.apply {
            let link = JournalRecordMapping.instrumentLink(of: record)
            // Resolve the primary against this device's instruments (id → alias
            // → name → create), never making a duplicate; the row's name is
            // what the profile then stores.
            var primary = ""
            if !apply.primaryInstrument.isEmpty {
                let row = importer.resolveInstrument(recordName: link.recordName, name: apply.primaryInstrument)
                primary = (row?.value(forKey: "name") as? String ?? apply.primaryInstrument).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let profile = profileRow(in: context) ?? {
                let created = NSEntityDescription.insertNewObject(forEntityName: JournalSyncRecordType.profile, into: context)
                created.setValue(UUID(), forKey: "id")
                created.setValue(false, forKey: "defaultPrivacy")
                return created
            }()
            if (profile.value(forKey: "name") as? String) != apply.name { profile.setValue(apply.name, forKey: "name") }
            if (profile.value(forKey: "primaryInstrument") as? String) != primary { profile.setValue(primary, forKey: "primaryInstrument") }
            if profile.value(forKey: "id") == nil { profile.setValue(UUID(), forKey: "id") }
            importer.save()
            JournalProfileMirror.suppressed = true
            ProfileStore.setLocation(apply.location, for: scope.locationUserID)
            if scope.locationUserID != nil { ProfileStore.setLocation(apply.location, for: nil) }
            JournalProfileMirror.suppressed = false
            outcome.applied = 1
        }
        let applied = decision.apply ?? local
        if decision.send {
            outcome.resend.append(.init(recordName: profileName, recordType: JournalSyncRecordType.profile, op: .save,
                                        metadataOnly: st.profileStamp == nil && serverStamp == nil))
        }
        store.update { s in
            s.lastKnownRecords[profileName] = JournalSyncStateStore.encodeSystemFields(record)
            s.profileFingerprint = applied.fingerprint
            if decision.apply != nil { s.profileStamp = serverStamp }
            if !decision.send { s.outbox.removeAll { $0.recordName == profileName && $0.op == .save } }
            else { JournalChangeTracker.merge(outcome.resend, into: &s.outbox) }
        }
        log("Profile record: \(decision.summary)\(decision.apply.map { " → \($0.describe())" } ?? "")")
        return outcome
    }

    /// Applies a ProfileAvatar record. A record without its asset (the
    /// catch-up fetches without the asset field) whose hash we need is skipped
    /// here; the engine fetches the full record first.
    static func applyAvatar(_ record: CKRecord, scope: JournalProfileScope, store: JournalSyncStateStore,
                            localPending: Bool? = nil, log: (String) -> Void) -> Outcome {
        var outcome = Outcome()
        let st = store.state
        let pending = localPending ?? st.outbox.contains { $0.recordName == avatarName && $0.op == .save }
        let local = currentAvatar(scope: scope, store: store)
        let serverHash = record[JournalRecordMapping.fileHashKey] as? String ?? ""
        let serverStamp = record[JournalProfileKeys.stamp] as? Date
        let localStamp = local.url == nil ? st.avatarRemovedAt : local.modifiedAt
        let asset = record[JournalRecordMapping.assetKey] as? CKAsset
        if let url = asset?.fileURL { outcome.avatarBytes = JournalAssetHash.stamp(of: url)?.size ?? 0 }
        switch JournalProfileMerge.decideAvatar(localHash: local.hash, localStamp: localStamp, localPending: pending,
                                                serverHash: serverHash, serverStamp: serverStamp) {
        case .nothing:
            log("Avatar record: same image\(serverHash.isEmpty ? " (none)" : "")")
        case .keepLocalAndSend:
            outcome.resend.append(.init(recordName: avatarName, recordType: JournalSyncRecordType.profileAvatar, op: .save))
            log("Avatar record: local newer; kept and resent")
        case .takeServer:
            if !local.hash.isEmpty, let url = local.url { keepDisplacedAvatar(from: url, hash: local.hash, store: store) }
            JournalProfileMirror.suppressed = true
            defer { JournalProfileMirror.suppressed = false }
            if serverHash.isEmpty {
                ProfileStore.removeSyncedAvatar(for: scope.avatarUserID)
                store.update { $0.avatarRemovedAt = serverStamp }
                outcome.avatarChanged = true
                log("Avatar record: removed on the other device; removed here")
            } else {
                guard let url = asset?.fileURL, let data = try? Data(contentsOf: url) else {
                    log("Avatar record arrived without its file; waiting for a fetch that carries it")
                    return outcome
                }
                guard ProfileStore.writeSyncedAvatar(pngData: data, for: scope.avatarUserID, modifiedAt: serverStamp ?? Date()) else {
                    log("Avatar record: file could not be written")
                    return outcome
                }
                store.update { $0.fileStampCache.removeValue(forKey: avatarName) }
                outcome.avatarChanged = true
                log("Avatar record: new image from the other device (\(data.count) bytes)")
            }
            outcome.applied = 1
        }
        let settled = outcome.resend.isEmpty
        store.update { s in
            s.lastKnownRecords[avatarName] = JournalSyncStateStore.encodeSystemFields(record)
            if settled {
                s.assetHashes[avatarName] = serverHash
                s.outbox.removeAll { $0.recordName == avatarName && $0.op == .save }
            } else {
                JournalChangeTracker.merge(outcome.resend, into: &s.outbox)
            }
        }
        return outcome
    }

    // MARK: Displaced avatars (recovery)

    static func displacedAvatarsDirectory() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SyncTest/DisplacedAvatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func keepDisplacedAvatar(from url: URL, hash: String, store: JournalSyncStateStore) {
        let dir = displacedAvatarsDirectory()
        let target = dir.appendingPathComponent("\(hash).png", isDirectory: false)
        if !FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.copyItem(at: url, to: target)
        }
        // Keep the five most recent.
        let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .sorted { (JournalAssetHash.stamp(of: $0)?.mtime ?? 0) > (JournalAssetHash.stamp(of: $1)?.mtime ?? 0) }
        for old in files.dropFirst(5) { try? FileManager.default.removeItem(at: old) }
        let conflict = JournalSyncConflict(at: Date(), recordName: avatarName, recordType: JournalSyncRecordType.profileAvatar, winner: "server",
                                           localUserModifiedAt: JournalAssetHash.stamp(of: url).map { Date(timeIntervalSince1970: $0.mtime) },
                                           serverUserModifiedAt: nil, losingTitle: "displaced avatar kept: \(hash.prefix(12))…", losingNotes: nil)
        store.update { $0.conflicts.append(conflict) }
    }

    static func displacedAvatars() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: displacedAvatarsDirectory(), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func clearDisplacedAvatars() {
        for url in displacedAvatars() { try? FileManager.default.removeItem(at: url) }
    }

    #if canImport(UIKit)
    /// Restoring is a deliberate user edit: it goes through the editor's own
    /// writers, so it is clocked now and wins everywhere.
    static func restoreDisplacedAvatar(_ url: URL, scope: JournalProfileScope) -> Bool {
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return false }
        ProfileStore.saveAvatarDerived(image, for: scope.avatarUserID)
        ProfileStore.saveAvatarOriginal(image, for: scope.avatarUserID)
        if scope.avatarUserID != nil {
            ProfileStore.saveAvatarDerived(image, for: nil)
            ProfileStore.saveAvatarOriginal(image, for: nil)
        }
        try? FileManager.default.removeItem(at: url)
        return true
    }
    #endif
}
#endif
