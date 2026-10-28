//
//  JournalSettingsSync.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
//
//  PERSONAL SETTINGS THROUGH THE BOUND JOURNAL (stage J).
//
//  Three small record kinds, all read from and written to UserDefaults:
//
//  - `Setting` ("setting-<key>"): one personal choice per record, with its own
//    clock, so a change to one never displaces another. Keys: the Journal
//    Tint preference and the primary activity ("core:<n>" or "custom:<name>";
//    a custom name is resolved to this device's spelling on arrival).
//  - `ListContext` ("listctx-<hash>"): the Lists default, autofill flag and
//    typed preset of ONE (activity, instrument) context. The record is keyed
//    by the activity reference and the instrument's NAME (never its local
//    id, which differs between devices for instruments that existed on both
//    before they met), so the same context shares a record everywhere; on
//    arrival the name resolves to this device's Instrument row and the
//    settings are written under its id. A record whose instrument is not
//    here yet is held until it is. Absent fields carry no information;
//    explicit clears ("" for no default, 0 for autofill off) do.
//  - `TintMap` ("tint-instrument"): the instrument colour map (normalised
//    label → palette slot). Merged by UNION, the server's value standing where
//    both assign the same label; removals are never sent, so a label this
//    device drops (its primary, or a move by the read-time sanitiser) is not a
//    change. Existing assignments are kept wherever possible, a clash is
//    settled once, and both devices run the same deterministic sanitiser, so
//    they converge. Thread colours need no record: they are rebuilt from
//    thread usage in the journal, which is itself synced.
//
//  Change detection is a fingerprint scan (the Lists and profile pattern) on
//  the defaults-change notification, at activation and after an import.
//  Settings and list contexts are clocked at the scan that finds the change;
//  the conflict rule is the existing one (newer clock wins, ties to the
//  server, an unclocked pre-existing value yields to any clocked one). Tool
//  visibility, layout and working settings stay per device (Samuel,
//  2026-10-27), as do the active timer, drafts and unfinished recordings.
//

#if SYNCTEST
import Foundation
import CloudKit
import CoreData
import CryptoKit

enum JournalSettingsKeys {
    static let value = "value"
    static let stamp = "userModifiedAt"
    static let activityRef = "activityRef"
    static let instrumentName = "instrumentName"
    static let defaultListID = "defaultListID"
    static let autofill = "autofill"
    static let preset = "preset"
    static let map = "map"
    static let all = [value, stamp, activityRef, instrumentName, defaultListID, autofill, preset, map]
}

/// The per-record personal choices. Each has a defaults key and a default
/// value; a value equal to the default on a device that never chose is not
/// sent at the transition (nothing to say), and a later change is an edit.
enum JournalSettingKey {
    static let tintMode = "tintMode"
    static let primaryActivity = "primaryActivity"
    static let all = [tintMode, primaryActivity]

    static func defaultsKey(_ key: String) -> String? {
        switch key {
        case tintMode: return "appSettings_tintMode"
        case primaryActivity: return "primaryActivityRef"
        default: return nil
        }
    }

    static func defaultValue(_ key: String) -> String {
        switch key {
        case tintMode: return Theme.TintMode.auto.rawValue
        case primaryActivity: return "core:0"
        default: return ""
        }
    }

    static func recordName(_ key: String) -> String { JournalSyncRecordType.settingPrefix + key }
    static func key(fromRecordName name: String) -> String? {
        guard name.hasPrefix(JournalSyncRecordType.settingPrefix) else { return nil }
        let key = String(name.dropFirst(JournalSyncRecordType.settingPrefix.count))
        return all.contains(key) ? key : nil
    }

    /// The stored value, normalised the way the screens read it.
    static func currentValue(_ key: String, defaults: UserDefaults) -> String {
        guard let dk = defaultsKey(key) else { return "" }
        let raw = (defaults.string(forKey: dk) ?? defaultValue(key)).trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case tintMode: return Theme.TintMode(rawValue: raw)?.rawValue ?? defaultValue(key)
        case primaryActivity: return (raw.hasPrefix("core:") || raw.hasPrefix("custom:")) ? raw : defaultValue(key)
        default: return raw
        }
    }

    static func label(_ key: String) -> String {
        switch key {
        case tintMode: return "Journal Tint"
        case primaryActivity: return "Primary activity"
        default: return key
        }
    }

    /// A value for people to read ("Thread", "Practice", "Scales (custom)").
    static func describe(_ key: String, value: String) -> String {
        switch key {
        case tintMode: return Theme.TintMode(rawValue: value)?.displayName ?? value
        case primaryActivity: return JournalListContextValues.activityLabel(value)
        default: return value
        }
    }
}

/// PURE. How a server value combines with this device's. The same rule as
/// everywhere else: equal values settle; two unclocked values (both predate
/// sync) go to the server; otherwise the newer clock wins, ties to the server.
enum JournalSettingMerge {
    enum Outcome: Equatable { case nothing, takeServer, keepLocalAndSend }

    static func decide(localValue: String, localStamp: Date?, serverValue: String, serverStamp: Date?) -> Outcome {
        if localValue == serverValue { return .nothing }
        if localStamp == nil, serverStamp == nil { return .takeServer }
        switch JournalConflictRule.decide(localUserModifiedAt: localStamp, serverUserModifiedAt: serverStamp) {
        case .server: return .takeServer
        case .local: return .keepLocalAndSend
        }
    }
}

/// PURE. The instrument colour map's merge.
enum JournalTintMapMerge {
    /// Union; where both assign a label, the server's slot stands.
    static func merge(local: [String: Int], server: [String: Int]) -> [String: Int] {
        var result = server
        for (label, slot) in local where result[label] == nil { result[label] = slot }
        return result
    }

    /// Whether this device added a label or moved one since the last exchange.
    /// A label that is gone locally is never a change (removals do not travel).
    static func changed(local: [String: Int], exchanged: [String: Int]?) -> Bool {
        guard let exchanged else { return !local.isEmpty }
        return local.contains { exchanged[$0.key] != $0.value }
    }

    static func fingerprint(_ map: [String: Int]) -> String {
        map.keys.sorted().map { "\($0)=\(map[$0] ?? -1)" }.joined(separator: ";")
    }

    static func encode(_ map: [String: Int]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(map)
    }

    static func decode(_ data: Data?) -> [String: Int]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([String: Int].self, from: data)
    }
}

/// One line of a typed Lists preset, as the practice timer decodes it.
struct JournalPresetLine: Codable, Equatable {
    let text: String
    let type: String
}

/// The Lists settings of one (activity, instrument) context. `instrumentName`
/// is "" for the activity-only context (no instrument exists, or signed out).
struct JournalListContextValues: Equatable {
    var activityRef: String
    var instrumentName: String
    /// "" = no default List.
    var defaultListID: String = ""
    /// nil = the flag was never set explicitly.
    var autofill: Bool?
    /// Typed preset lines (`JournalPresetLine` JSON, sorted keys); nil = none.
    var preset: Data?

    static func instrumentKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
    }

    static func recordName(activityRef: String, instrumentName: String) -> String {
        let seed = activityRef.trimmingCharacters(in: .whitespacesAndNewlines) + "|" + instrumentKey(instrumentName)
        let digest = SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
        return JournalSyncRecordType.listContextPrefix + String(digest.prefix(24))
    }

    var recordName: String { Self.recordName(activityRef: activityRef, instrumentName: instrumentName) }

    var isEmpty: Bool { defaultListID.isEmpty && autofill == nil && preset == nil }

    private static let separator = "\u{1F}"
    var fingerprint: String {
        let presetHash = preset.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "-"
        return ["v1", activityRef, Self.instrumentKey(instrumentName), defaultListID,
                autofill.map { $0 ? "1" : "0" } ?? "-", presetHash].joined(separator: Self.separator)
    }

    /// Typed lines from either stored shape (typed JSON or a legacy `[String]`),
    /// re-encoded in one canonical form.
    static func normalisedPreset(_ stored: Any?) -> Data? {
        var lines: [JournalPresetLine] = []
        if let data = stored as? Data {
            struct Loose: Decodable { let text: String; let type: String? }
            guard let decoded = try? JSONDecoder().decode([Loose].self, from: data) else { return nil }
            lines = decoded.map { JournalPresetLine(text: $0.text, type: $0.type ?? TaskLineType.task.rawValue) }
        } else if let array = stored as? [String] {
            lines = array.map { JournalPresetLine(text: $0, type: TaskLineType.task.rawValue) }
        } else {
            return nil
        }
        guard !lines.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(lines)
    }

    static func presetLines(_ data: Data?) -> [JournalPresetLine] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([JournalPresetLine].self, from: data)) ?? []
    }

    static func activityLabel(_ ref: String) -> String {
        if ref.hasPrefix("core:"), let raw = ref.split(separator: ":").last, let value = Int16(raw),
           let type = SessionActivityType(rawValue: value) {
            return type.label
        }
        if ref.hasPrefix("custom:") { return String(ref.dropFirst("custom:".count)) }
        return ref
    }

    func describe() -> String {
        var parts = [Self.activityLabel(activityRef) + (instrumentName.isEmpty ? "" : " · \(instrumentName)")]
        if !defaultListID.isEmpty { parts.append("default list \(defaultListID.prefix(8))…") }
        if let autofill { parts.append(autofill ? "autofill on" : "autofill off") }
        if preset != nil { parts.append("\(Self.presetLines(preset).count) preset line(s)") }
        return parts.joined(separator: " · ")
    }
}

/// The app's write points need no hook: every store here is UserDefaults, and
/// the engine scans on the defaults-change notification. This flag stops the
/// import's own writes from looking like edits while they happen.
enum JournalSettingsMirror {
    nonisolated(unsafe) static var suppressed = false
}

@MainActor
enum JournalSettingsSync {

    /// Lists and list contexts share the Lists screen's owner scope.
    static func currentScope() -> String { JournalSavedListSync.currentScope() }

    /// The instrument colour map's namespace: the current owner, as the
    /// Journal passes it.
    static func tintOwnerID() -> String? { PersistenceController.shared.currentUserID }

    // MARK: Local reads

    static func instrumentName(for id: UUID, context: NSManagedObjectContext) -> String? {
        let request = NSFetchRequest<NSManagedObject>(entityName: JournalSyncRecordType.instrument)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return ((try? context.fetch(request))?.first?.value(forKey: "name") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func instrumentID(named name: String, context: NSManagedObjectContext) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let request = NSFetchRequest<NSManagedObject>(entityName: JournalSyncRecordType.instrument)
        request.predicate = NSPredicate(format: "name ==[cd] %@", trimmed)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first?.value(forKey: "id") as? UUID
    }

    /// This device's spelling of a custom activity, by normalised name.
    static func customActivityDisplayName(_ name: String, context: NSManagedObjectContext) -> String? {
        guard let owner = PersistenceController.shared.ownerIDForCustoms else { return nil }
        let request = NSFetchRequest<NSManagedObject>(entityName: JournalSyncRecordType.userActivity)
        request.predicate = NSPredicate(format: "ownerUserID == %@ AND normalizedName == %@", owner, PersistenceController.normalized(name))
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first?.value(forKey: "displayName") as? String
    }

    static func listName(_ id: String, scope: String, defaults: UserDefaults) -> String? {
        guard let uuid = UUID(uuidString: id), case .lists(let lists) = SavedListLibrary.load(ownerScope: scope, defaults: defaults) else { return nil }
        return lists.first { $0.id == uuid }?.name
    }

    /// Every (activity, instrument) context with any setting under `scope`,
    /// from the keys the Lists manager and timer write. A context whose
    /// instrument row is gone is skipped (nothing to map it to).
    static func localContexts(scope: String, defaults: UserDefaults, context: NSManagedObjectContext) -> [JournalListContextValues] {
        let tasksPrefix = "practiceTasks_v1::\(scope)::"
        let autofillPrefix = "practiceTasks_autofill_enabled::\(scope)::"
        let defaultSuffix = "::default_set_id_v1"
        struct ContextID: Hashable { let activityRef: String; let instrumentID: UUID? }
        var found = Set<ContextID>()
        for key in defaults.dictionaryRepresentation().keys {
            var rest: String
            if key.hasPrefix(tasksPrefix) { rest = String(key.dropFirst(tasksPrefix.count)) }
            else if key.hasPrefix(autofillPrefix) { rest = String(key.dropFirst(autofillPrefix.count)) }
            else { continue }
            if rest.hasSuffix(defaultSuffix) { rest = String(rest.dropLast(defaultSuffix.count)) }
            let parts = rest.components(separatedBy: "::inst:")
            let activityRef = parts[0]
            guard activityRef.hasPrefix("core:") || activityRef.hasPrefix("custom:") else { continue }
            var instrumentID: UUID?
            if parts.count > 1 {
                guard let id = UUID(uuidString: parts[1]) else { continue }
                instrumentID = id
            }
            found.insert(ContextID(activityRef: activityRef, instrumentID: instrumentID))
        }
        var out: [JournalListContextValues] = []
        for id in found {
            var name = ""
            if let instrumentID = id.instrumentID {
                guard let found = instrumentName(for: instrumentID, context: context), !found.isEmpty else { continue }
                name = found
            }
            let values = currentValues(activityRef: id.activityRef, instrumentID: id.instrumentID, instrumentName: name, scope: scope, defaults: defaults)
            if !values.isEmpty { out.append(values) }
        }
        return out.sorted { $0.recordName < $1.recordName }
    }

    static func currentValues(activityRef: String, instrumentID: UUID?, instrumentName: String, scope: String,
                              defaults: UserDefaults) -> JournalListContextValues {
        let ctx = ListsDefaultContext(ownerScope: scope, activityRef: activityRef, instrumentID: instrumentID)
        var values = JournalListContextValues(activityRef: activityRef, instrumentName: instrumentName)
        values.defaultListID = defaults.string(forKey: ctx.defaultIDKey) ?? ""
        values.autofill = defaults.object(forKey: ctx.autofillKey) == nil ? nil : defaults.bool(forKey: ctx.autofillKey)
        values.preset = JournalListContextValues.normalisedPreset(defaults.object(forKey: ctx.tasksKey))
        return values
    }

    /// Writes a context's settings under this device's keys. Only fields the
    /// record carries are written; a preset is replaced, never merged.
    static func write(_ values: JournalListContextValues, instrumentID: UUID?, scope: String, defaults: UserDefaults) {
        let ctx = ListsDefaultContext(ownerScope: scope, activityRef: values.activityRef, instrumentID: instrumentID)
        if values.defaultListID.isEmpty { defaults.removeObject(forKey: ctx.defaultIDKey) }
        else { defaults.set(values.defaultListID, forKey: ctx.defaultIDKey) }
        if let autofill = values.autofill { defaults.set(autofill, forKey: ctx.autofillKey) }
        if let preset = values.preset { defaults.set(preset, forKey: ctx.tasksKey) }
    }

    // MARK: Scan (local changes → outbox)

    /// Compares every setting, list context and the colour map with what was
    /// last sent or received and queues what changed. The first scan is the
    /// transition: pre-existing non-default values go up WITHOUT a clock.
    @discardableResult
    static func scan(store: JournalSyncStateStore, defaults: UserDefaults = .standard,
                     context: NSManagedObjectContext = PersistenceController.shared.container.viewContext,
                     scope: String? = nil, tintOwner: String?? = nil, now: Date = Date()) -> [JournalSyncPendingChange] {
        let st = store.state
        guard !st.localRemovalInProgress, !JournalSettingsMirror.suppressed else { return [] }
        let scope = scope ?? currentScope()
        let owner = tintOwner ?? tintOwnerID()
        let transition = !st.settingsScanDone
        var pending: [JournalSyncPendingChange] = []
        var settingFingerprints = st.settingFingerprints
        var settingStamps = st.settingStamps
        var notes: [String] = []

        // Settings.
        for key in JournalSettingKey.all {
            let value = JournalSettingKey.currentValue(key, defaults: defaults)
            let name = JournalSettingKey.recordName(key)
            if let known = settingFingerprints[key] {
                if known != value {
                    settingFingerprints[key] = value
                    settingStamps[key] = now
                    pending.append(.init(recordName: name, recordType: JournalSyncRecordType.setting, op: .save))
                    notes.append("\(JournalSettingKey.label(key)) edited: \(JournalSettingKey.describe(key, value: value))")
                }
            } else {
                settingFingerprints[key] = value
                if value != JournalSettingKey.defaultValue(key) {
                    if transition {
                        pending.append(.init(recordName: name, recordType: JournalSyncRecordType.setting, op: .save, metadataOnly: true))
                        notes.append("\(JournalSettingKey.label(key)) transition: pre-existing value queued without a clock (\(JournalSettingKey.describe(key, value: value)))")
                    } else {
                        settingStamps[key] = now
                        pending.append(.init(recordName: name, recordType: JournalSyncRecordType.setting, op: .save))
                        notes.append("\(JournalSettingKey.label(key)) set: \(JournalSettingKey.describe(key, value: value))")
                    }
                }
            }
        }

        // List contexts. A scope change is a change of lookup, never a deletion
        // (and deletions are never inferred for contexts anyway).
        let scopeChanged = st.listContextScope != nil && st.listContextScope != scope
        var contextFingerprints = scopeChanged ? [:] : st.listContextFingerprints
        var contextStamps = st.listContextStamps
        if scopeChanged { notes.append("List contexts: owner scope changed; fingerprints reset, nothing inferred") }
        for values in localContexts(scope: scope, defaults: defaults, context: context) {
            let name = values.recordName
            let print = values.fingerprint
            guard contextFingerprints[name] != print else { continue }
            contextFingerprints[name] = print
            if transition || scopeChanged {
                // Pre-existing values (or the same values looked up under a new
                // scope) go up without a clock, so a real edit anywhere beats them.
                pending.append(.init(recordName: name, recordType: JournalSyncRecordType.listContext, op: .save, metadataOnly: true))
                notes.append("List context transition: \(values.describe()) queued without a clock")
            } else {
                contextStamps[name] = now
                pending.append(.init(recordName: name, recordType: JournalSyncRecordType.listContext, op: .save))
                notes.append("List context edited: \(values.describe())")
            }
        }

        // Instrument colours: additions and moves only.
        let local = Theme.InstrumentTint.storedSlotMap(ownerID: owner, defaults: defaults)
        var queuedTint = st.tintMapQueuedFingerprint
        if JournalTintMapMerge.changed(local: local, exchanged: st.tintMapExchanged) {
            let print = JournalTintMapMerge.fingerprint(local)
            if queuedTint != print {
                queuedTint = print
                pending.append(.init(recordName: JournalSyncRecordType.tintMapRecordName, recordType: JournalSyncRecordType.tintMap, op: .save))
                notes.append("Instrument colours: \(local.count) label(s) queued")
            }
        }

        let changed = !pending.isEmpty || transition || scopeChanged || settingFingerprints != st.settingFingerprints
            || contextFingerprints != st.listContextFingerprints || queuedTint != st.tintMapQueuedFingerprint
        guard changed else { return [] }
        let ok = store.update { s in
            JournalChangeTracker.merge(pending, into: &s.outbox)
            s.settingsScanDone = true
            s.settingFingerprints = settingFingerprints
            s.settingStamps = settingStamps
            s.listContextFingerprints = contextFingerprints
            s.listContextStamps = contextStamps
            s.listContextScope = scope
            s.tintMapQueuedFingerprint = queuedTint
            for note in notes { s.log.append(.init(at: now, text: note)) }
        }
        return ok ? pending : []
    }

    // MARK: Records (stores → CKRecord)

    static func records(for names: [String], store: JournalSyncStateStore, defaults: UserDefaults = .standard,
                        context: NSManagedObjectContext = PersistenceController.shared.container.viewContext,
                        scope: String? = nil, tintOwner: String?? = nil) -> [String: CKRecord] {
        let scope = scope ?? currentScope()
        let owner = tintOwner ?? tintOwnerID()
        var out: [String: CKRecord] = [:]
        var contexts: [JournalListContextValues]?
        for name in names {
            guard let type = JournalSyncRecordType.settingsType(forName: name) else { continue }
            let base = store.state.lastKnownRecords[name].flatMap(JournalSyncStateStore.recordFromSystemFields)
            let record = (base?.recordType == type ? base : nil)
                ?? CKRecord(recordType: type, recordID: CKRecord.ID(recordName: name, zoneID: JournalRecordMapping.zoneID))
            switch type {
            case JournalSyncRecordType.setting:
                guard let key = JournalSettingKey.key(fromRecordName: name) else { continue }
                record[JournalSettingsKeys.value] = JournalSettingKey.currentValue(key, defaults: defaults) as CKRecordValue
                record[JournalSettingsKeys.stamp] = store.state.settingStamps[key].map { $0 as CKRecordValue }
            case JournalSyncRecordType.listContext:
                if contexts == nil { contexts = localContexts(scope: scope, defaults: defaults, context: context) }
                guard let values = contexts?.first(where: { $0.recordName == name }) else { continue }
                record[JournalSettingsKeys.activityRef] = values.activityRef as CKRecordValue
                record[JournalSettingsKeys.instrumentName] = values.instrumentName as CKRecordValue
                record[JournalSettingsKeys.defaultListID] = values.defaultListID as CKRecordValue
                record[JournalSettingsKeys.autofill] = values.autofill.map { NSNumber(value: $0) }
                record[JournalSettingsKeys.preset] = values.preset.map { $0 as CKRecordValue }
                record[JournalSettingsKeys.stamp] = store.state.listContextStamps[name].map { $0 as CKRecordValue }
            case JournalSyncRecordType.tintMap:
                let map = Theme.InstrumentTint.storedSlotMap(ownerID: owner, defaults: defaults)
                record[JournalSettingsKeys.map] = JournalTintMapMerge.encode(map).map { $0 as CKRecordValue }
            default:
                continue
            }
            out[name] = record
        }
        return out
    }

    // MARK: Import (CKRecord → stores)

    struct Outcome { var applied = 0; var held = 0; var resend: [JournalSyncPendingChange] = []; var settled: [String] = [] }

    static func apply(_ records: [CKRecord], store: JournalSyncStateStore, defaults: UserDefaults = .standard,
                      context: NSManagedObjectContext = PersistenceController.shared.container.viewContext,
                      scope: String? = nil, tintOwner: String?? = nil, localPending: Bool? = nil,
                      log: (String) -> Void) -> Outcome {
        var outcome = Outcome()
        let scope = scope ?? currentScope()
        let owner = tintOwner ?? tintOwnerID()
        JournalSettingsMirror.suppressed = true
        defer { JournalSettingsMirror.suppressed = false }
        for record in records {
            let name = record.recordID.recordName
            let partial: Outcome
            switch record.recordType {
            case JournalSyncRecordType.setting:
                partial = applySetting(record, store: store, defaults: defaults, context: context, localPending: localPending, log: log)
            case JournalSyncRecordType.listContext:
                partial = applyListContext(record, store: store, defaults: defaults, context: context, scope: scope, localPending: localPending, log: log)
            case JournalSyncRecordType.tintMap:
                partial = applyTintMap(record, store: store, defaults: defaults, context: context, owner: owner, log: log)
            default:
                log("Settings: unknown record \(name) ignored")
                continue
            }
            outcome.applied += partial.applied
            outcome.held += partial.held
            outcome.resend += partial.resend
            outcome.settled += partial.settled
        }
        return outcome
    }

    private static func isPending(_ name: String, store: JournalSyncStateStore, override: Bool?) -> Bool {
        override ?? store.state.outbox.contains { $0.recordName == name && $0.op == .save }
    }

    static func applySetting(_ record: CKRecord, store: JournalSyncStateStore, defaults: UserDefaults, context: NSManagedObjectContext,
                             localPending: Bool?, log: (String) -> Void) -> Outcome {
        var outcome = Outcome()
        let name = record.recordID.recordName
        guard let key = JournalSettingKey.key(fromRecordName: name), let dk = JournalSettingKey.defaultsKey(key) else { return outcome }
        let st = store.state
        let pending = isPending(name, store: store, override: localPending)
        let local = JournalSettingKey.currentValue(key, defaults: defaults)
        var server = (record[JournalSettingsKeys.value] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if server.isEmpty { server = JournalSettingKey.defaultValue(key) }
        let serverStamp = record[JournalSettingsKeys.stamp] as? Date
        let decision = JournalSettingMerge.decide(localValue: local, localStamp: st.settingStamps[key], serverValue: server, serverStamp: serverStamp)
        switch decision {
        case .nothing:
            log("\(JournalSettingKey.label(key)): same value")
        case .takeServer:
            var value = server
            if key == JournalSettingKey.primaryActivity, value.hasPrefix("custom:") {
                // The other device's spelling resolves to this device's row.
                let customName = String(value.dropFirst("custom:".count))
                if let here = customActivityDisplayName(customName, context: context) { value = "custom:\(here)" }
            }
            defaults.set(value, forKey: dk)
            outcome.applied = 1
            if !local.isEmpty, local != JournalSettingKey.defaultValue(key) || st.settingStamps[key] != nil {
                var conflict = JournalSyncConflict(at: Date(), recordName: name, recordType: JournalSyncRecordType.setting, winner: "server",
                                                   localUserModifiedAt: st.settingStamps[key], serverUserModifiedAt: serverStamp,
                                                   losingTitle: nil, losingNotes: nil)
                conflict.subject = JournalSettingKey.label(key)
                conflict.displaced = ["\(JournalSettingKey.label(key)) (this device)": JournalSettingKey.describe(key, value: local)]
                store.update { $0.conflicts.append(conflict) }
            }
            log("\(JournalSettingKey.label(key)): \(serverStamp == nil ? "no clock on either side; server's kept" : "server newer; applied") → \(JournalSettingKey.describe(key, value: value))")
        case .keepLocalAndSend:
            outcome.resend.append(.init(recordName: name, recordType: JournalSyncRecordType.setting, op: .save))
            var conflict = JournalSyncConflict(at: Date(), recordName: name, recordType: JournalSyncRecordType.setting, winner: "local",
                                               localUserModifiedAt: st.settingStamps[key], serverUserModifiedAt: serverStamp,
                                               losingTitle: nil, losingNotes: nil)
            conflict.subject = JournalSettingKey.label(key)
            conflict.displaced = ["\(JournalSettingKey.label(key)) (other device)": JournalSettingKey.describe(key, value: server)]
            store.update { $0.conflicts.append(conflict) }
            log("\(JournalSettingKey.label(key)): local newer; kept and resent")
        }
        let held = JournalSettingKey.currentValue(key, defaults: defaults)
        let send = decision == .keepLocalAndSend
        store.update { s in
            s.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record)
            s.settingFingerprints[key] = held
            if decision == .takeServer { s.settingStamps[key] = serverStamp }
            if !send {
                if !pending || decision == .takeServer { s.outbox.removeAll { $0.recordName == name && $0.op == .save } }
            } else {
                JournalChangeTracker.merge(outcome.resend, into: &s.outbox)
            }
        }
        if !send, !pending || decision == .takeServer { outcome.settled.append(name) }
        return outcome
    }

    static func applyListContext(_ record: CKRecord, store: JournalSyncStateStore, defaults: UserDefaults, context: NSManagedObjectContext,
                                 scope: String, localPending: Bool?, log: (String) -> Void) -> Outcome {
        var outcome = Outcome()
        let name = record.recordID.recordName
        let st = store.state
        guard let activityRef = record[JournalSettingsKeys.activityRef] as? String,
              activityRef.hasPrefix("core:") || activityRef.hasPrefix("custom:") else {
            log("List context \(name.prefix(14))… has no activity; ignored")
            return outcome
        }
        let instrumentName = (record[JournalSettingsKeys.instrumentName] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var resolvedInstrumentID: UUID?
        if !instrumentName.isEmpty {
            guard let id = Self.instrumentID(named: instrumentName, context: context) else {
                // Not here yet: held until the Instrument record lands.
                if let data = JournalSyncStateStore.encodeWholeRecord(record) {
                    store.update { $0.awaitingListContext[name] = data }
                }
                outcome.held = 1
                log("List context for \(JournalListContextValues.activityLabel(activityRef)) · \(instrumentName) held: no such instrument here yet")
                return outcome
            }
            resolvedInstrumentID = id
        }
        let instrumentID = resolvedInstrumentID
        var server = JournalListContextValues(activityRef: activityRef, instrumentName: instrumentName)
        server.defaultListID = (record[JournalSettingsKeys.defaultListID] as? String) ?? ""
        server.autofill = (record[JournalSettingsKeys.autofill] as? NSNumber)?.boolValue
        server.preset = JournalListContextValues.normalisedPreset(record[JournalSettingsKeys.preset] as? Data)
        let serverStamp = record[JournalSettingsKeys.stamp] as? Date
        let local = currentValues(activityRef: activityRef, instrumentID: instrumentID, instrumentName: instrumentName, scope: scope, defaults: defaults)
        let pending = isPending(name, store: store, override: localPending)
        let decision = JournalSettingMerge.decide(localValue: local.fingerprint, localStamp: st.listContextStamps[name],
                                                  serverValue: server.fingerprint, serverStamp: serverStamp)
        let subject = "Lists default: " + JournalListContextValues.activityLabel(activityRef) + (instrumentName.isEmpty ? "" : " · \(instrumentName)")
        func displaced(_ v: JournalListContextValues, _ side: String) -> [String: String] {
            var d: [String: String] = [:]
            if !v.defaultListID.isEmpty { d["Default list (\(side))"] = listName(v.defaultListID, scope: scope, defaults: defaults) ?? v.defaultListID }
            if let autofill = v.autofill { d["Autofill (\(side))"] = autofill ? "on" : "off" }
            let lines = JournalListContextValues.presetLines(v.preset)
            if !lines.isEmpty { d["Preset (\(side))"] = lines.map(\.text).joined(separator: "\n") }
            return d
        }
        switch decision {
        case .nothing:
            log("\(subject): same values")
        case .takeServer:
            write(server, instrumentID: instrumentID, scope: scope, defaults: defaults)
            outcome.applied = 1
            if !local.isEmpty {
                var conflict = JournalSyncConflict(at: Date(), recordName: name, recordType: JournalSyncRecordType.listContext, winner: "server",
                                                   localUserModifiedAt: st.listContextStamps[name], serverUserModifiedAt: serverStamp, losingTitle: nil, losingNotes: nil)
                conflict.subject = subject
                conflict.displaced = displaced(local, "this device")
                if conflict.hasRecoverableText { store.update { $0.conflicts.append(conflict) } }
            }
            log("\(subject): \(serverStamp == nil ? "no clock on either side; server's kept" : "server newer; applied") → \(server.describe())")
        case .keepLocalAndSend:
            outcome.resend.append(.init(recordName: name, recordType: JournalSyncRecordType.listContext, op: .save))
            var conflict = JournalSyncConflict(at: Date(), recordName: name, recordType: JournalSyncRecordType.listContext, winner: "local",
                                               localUserModifiedAt: st.listContextStamps[name], serverUserModifiedAt: serverStamp, losingTitle: nil, losingNotes: nil)
            conflict.subject = subject
            conflict.displaced = displaced(server, "other device")
            if conflict.hasRecoverableText { store.update { $0.conflicts.append(conflict) } }
            log("\(subject): local newer; kept and resent")
        }
        let held = currentValues(activityRef: activityRef, instrumentID: instrumentID, instrumentName: instrumentName, scope: scope, defaults: defaults)
        let send = decision == .keepLocalAndSend
        store.update { s in
            s.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record)
            s.listContextFingerprints[name] = held.fingerprint
            s.listContextScope = scope
            if decision == .takeServer { s.listContextStamps[name] = serverStamp }
            s.awaitingListContext.removeValue(forKey: name)
            if !send {
                if !pending || decision == .takeServer { s.outbox.removeAll { $0.recordName == name && $0.op == .save } }
            } else {
                JournalChangeTracker.merge(outcome.resend, into: &s.outbox)
            }
        }
        if !send, !pending || decision == .takeServer { outcome.settled.append(name) }
        return outcome
    }

    static func applyTintMap(_ record: CKRecord, store: JournalSyncStateStore, defaults: UserDefaults, context: NSManagedObjectContext,
                             owner: String?, log: (String) -> Void) -> Outcome {
        var outcome = Outcome()
        let name = record.recordID.recordName
        guard let server = JournalTintMapMerge.decode(record[JournalSettingsKeys.map] as? Data) else {
            log("Instrument colours: record without a map; ignored")
            return outcome
        }
        let local = Theme.InstrumentTint.storedSlotMap(ownerID: owner, defaults: defaults)
        let merged = JournalTintMapMerge.merge(local: local, server: server)
        let moved = local.filter { merged[$0.key] != $0.value }
        if merged != local {
            // Written the way this device will read it: without its primary,
            // and with no two labels on one slot (the sanitiser's own rule).
            let primary = JournalProfileSync.profileRow(in: context)?.value(forKey: "primaryInstrument") as? String
            let toWrite = Theme.InstrumentTint.sanitized(merged, primaryLabel: Theme.InstrumentTint.normalizedLabel(primary))
            Theme.InstrumentTint.storeSlotMap(toWrite, ownerID: owner, defaults: defaults)
            outcome.applied = 1
        }
        let send = merged != server
        if send { outcome.resend.append(.init(recordName: name, recordType: JournalSyncRecordType.tintMap, op: .save)) }
        store.update { s in
            s.lastKnownRecords[name] = JournalSyncStateStore.encodeSystemFields(record)
            s.tintMapExchanged = merged
            s.tintMapQueuedFingerprint = send ? JournalTintMapMerge.fingerprint(Theme.InstrumentTint.storedSlotMap(ownerID: owner, defaults: defaults)) : nil
            if send { JournalChangeTracker.merge(outcome.resend, into: &s.outbox) }
            else { s.outbox.removeAll { $0.recordName == name && $0.op == .save } }
        }
        if !send { outcome.settled.append(name) }
        log("Instrument colours: \(server.count) from the server, \(local.count) here → \(merged.count) merged" +
            (moved.isEmpty ? "" : "; settled once for \(moved.keys.sorted())") + (send ? "; sending the union" : ""))
        return outcome
    }

    /// Records held for an instrument that was not here: tried again after
    /// every import batch. Returns what was applied or resent.
    static func retryHeld(store: JournalSyncStateStore, defaults: UserDefaults = .standard,
                          context: NSManagedObjectContext = PersistenceController.shared.container.viewContext,
                          scope: String? = nil, log: (String) -> Void) -> Outcome {
        let held = store.state.awaitingListContext
        guard !held.isEmpty else { return Outcome() }
        let records = held.values.compactMap(JournalSyncStateStore.decodeWholeRecord)
        var outcome = apply(records, store: store, defaults: defaults, context: context, scope: scope, log: log)
        outcome.held = store.state.awaitingListContext.count
        return outcome
    }

    /// A deleted settings record (a reset elsewhere) is forgotten, never
    /// applied; the next scan sends this device's value afresh.
    nonisolated static func forget(_ names: [String], store: JournalSyncStateStore) {
        store.update { s in
            for name in names {
                s.lastKnownRecords.removeValue(forKey: name)
                if let key = JournalSettingKey.key(fromRecordName: name) { s.settingFingerprints.removeValue(forKey: key) }
                s.listContextFingerprints.removeValue(forKey: name)
                if name == JournalSyncRecordType.tintMapRecordName { s.tintMapExchanged = nil; s.tintMapQueuedFingerprint = nil }
                s.awaitingListContext.removeValue(forKey: name)
            }
        }
    }

    /// Stage J diagnostics: forget what was exchanged and send everything again.
    nonisolated static func rerunTransition(store: JournalSyncStateStore) {
        store.update { s in
            s.settingsScanDone = false
            s.settingFingerprints = [:]
            s.listContextFingerprints = [:]
            s.tintMapExchanged = nil
            s.tintMapQueuedFingerprint = nil
            s.log.append(.init(at: Date(), text: "Settings transition re-run requested"))
        }
    }
}
#endif
