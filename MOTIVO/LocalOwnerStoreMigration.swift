//
//  LocalOwnerStoreMigration.swift
//  MOTIVO
//
//  C-116. Several local stores are looked up under the Apple user ID once the
//  person has signed in, and under a fixed "no owner" name before that:
//  saved Lists and their per-context settings ("device"), ensembles
//  ("local-device"), instrument and thread tint maps ("__anonymous__") and
//  saves ("unknown"). Signing in moved the lookup without moving the data, so
//  anything made before the first sign-in disappeared from view (the mirror
//  image of C-114, where leaving Connected moved it the other way).
//
//  This merges each "no owner" store into the owner's, ONCE per owner:
//  - union by id (Lists, ensembles) or by key (settings, tint entries, saves),
//    so content on both sides is kept and two Lists with the same name stay
//    two Lists;
//  - the owner's own value wins where the same id or key exists on both;
//  - the source is never deleted, and the once-per-owner marker is written
//    last, so an interrupted run is simply repeated and nothing is
//    duplicated or lost.
//  Nothing here touches the network or any cloud copy.
//

import Foundation

@MainActor
enum LocalOwnerStoreMigration {

    static let listsNoOwnerScope = "device"
    static let ensemblesNoOwner = "local-device"
    static let tintNoOwner = "__anonymous__"
    static let savesNoOwner = "unknown"
    static let profileNoOwner = "__local_etudes_profile__"

    static func markerKey(_ owner: String) -> String { "localOwnerStoresMerged_v1::" + owner }

    static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Merges once per owner. A later run for the same owner does nothing, so
    /// a List deleted after the merge is not brought back by the next sign-in.
    @discardableResult
    static func mergeNoOwnerStoresIfNeeded(into rawOwner: String, defaults: UserDefaults = .standard,
                                           includeProfile: Bool = false, profilesDirectory: URL? = nil) -> [String] {
        guard let owner = normalized(rawOwner) else { return ["No owner given; nothing moved"] }
        guard !defaults.bool(forKey: markerKey(owner)) else { return ["Already merged for this owner"] }
        let notes = mergeNoOwnerStores(into: owner, defaults: defaults, includeProfile: includeProfile, profilesDirectory: profilesDirectory)
        defaults.set(true, forKey: markerKey(owner))
        return notes
    }

    /// The unconditional merge: idempotent, never overwriting, never deleting.
    /// Returns one line per store for a log.
    @discardableResult
    static func mergeNoOwnerStores(into rawOwner: String, defaults: UserDefaults = .standard,
                                   includeProfile: Bool = false, profilesDirectory: URL? = nil) -> [String] {
        guard let owner = normalized(rawOwner) else { return ["No owner given; nothing moved"] }
        var notes: [String] = []
        notes.append(mergeSavedLists(into: owner, defaults: defaults))
        notes.append(copyPrefixedKeys(from: "practiceTasks_v1::\(listsNoOwnerScope)::",
                                      to: "practiceTasks_v1::\(owner)::", defaults: defaults, label: "List settings"))
        notes.append(copyPrefixedKeys(from: "practiceTasks_autofill_enabled::\(listsNoOwnerScope)::",
                                      to: "practiceTasks_autofill_enabled::\(owner)::", defaults: defaults, label: "List autofill"))
        notes.append(mergeEnsembles(into: owner.lowercased(), defaults: defaults))
        for prefix in ["theme.instrumentTint.slotMap.v1", "theme.threadTint.slotMap.v1"] {
            notes.append(mergeDictionary(from: "\(prefix).\(tintNoOwner)", to: "\(prefix).\(owner.lowercased())",
                                         defaults: defaults, label: prefix))
        }
        notes.append(copyTrueFlags(prefix: "feed.interact.v2.save.", fromPart: savesNoOwner,
                                   toPart: safeSaveKeyPart(owner), defaults: defaults))
        if includeProfile {
            notes.append(copyIfAbsent(from: "profile.\(profileNoOwner).location", to: "profile.\(owner).location",
                                      defaults: defaults, label: "Profile location"))
            if let dir = profilesDirectory {
                for suffix in ["-original.jpg", "-avatar.png"] {
                    notes.append(copyFileIfAbsent(dir.appendingPathComponent(profileNoOwner + suffix),
                                                  dir.appendingPathComponent(owner + suffix)))
                }
            }
        }
        return notes
    }

    // MARK: Lists — union by id, the owner's own entries win, nothing removed

    static func mergeSavedLists(into owner: String, defaults: UserDefaults) -> String {
        guard case .lists(let source) = SavedListLibrary.load(ownerScope: listsNoOwnerScope, defaults: defaults) else {
            return "Lists: the no-owner library is unreadable; left as it is"
        }
        guard !source.isEmpty else { return "Lists: nothing to move" }
        guard case .lists(let target) = SavedListLibrary.load(ownerScope: owner, defaults: defaults) else {
            return "Lists: the owner's library is unreadable; nothing written"
        }
        let present = Set(target.map(\.id))
        let missing = source.filter { !present.contains($0.id) }
        guard !missing.isEmpty else { return "Lists: all \(source.count) already present" }
        do {
            try SavedListLibrary.commit(snapshot: target, updated: target + missing, ownerScope: owner, defaults: defaults)
            return "Lists: added \(missing.count) of \(source.count)"
        } catch {
            return "Lists: merge failed (\(error.localizedDescription)); nothing lost"
        }
    }

    // MARK: Ensembles — union by id, the owner's own entries win

    static func mergeEnsembles(into owner: String, defaults: UserDefaults) -> String {
        let fromKey = "EnsembleStore.items::\(ensemblesNoOwner)"
        let toKey = "EnsembleStore.items::\(owner)"
        guard let data = defaults.data(forKey: fromKey) else { return "Ensembles: nothing to move" }
        guard let source = try? JSONDecoder().decode([Ensemble].self, from: data) else {
            return "Ensembles: no-owner value unreadable; left as it is"
        }
        var target: [Ensemble] = []
        if let existing = defaults.data(forKey: toKey) {
            guard let decoded = try? JSONDecoder().decode([Ensemble].self, from: existing) else {
                return "Ensembles: owner's value unreadable; nothing written"
            }
            target = decoded
        }
        let present = Set(target.map(\.id))
        let missing = source.filter { !present.contains($0.id) }
        guard !missing.isEmpty else { return "Ensembles: all present" }
        guard let encoded = try? JSONEncoder().encode(target + missing) else { return "Ensembles: encode failed" }
        defaults.set(encoded, forKey: toKey)
        return "Ensembles: added \(missing.count)"
    }

    // MARK: Generic helpers (copy if absent, never delete the source)

    static func mergeDictionary(from: String, to: String, defaults: UserDefaults, label: String) -> String {
        guard let source = defaults.dictionary(forKey: from), !source.isEmpty else { return "\(label): nothing to move" }
        var target = defaults.dictionary(forKey: to) ?? [:]
        var added = 0
        for (k, v) in source where target[k] == nil { target[k] = v; added += 1 }
        if added > 0 { defaults.set(target, forKey: to) }
        return "\(label): added \(added) entr\(added == 1 ? "y" : "ies")"
    }

    static func copyPrefixedKeys(from: String, to: String, defaults: UserDefaults, label: String) -> String {
        var copied = 0
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(from) {
            let target = to + key.dropFirst(from.count)
            if defaults.object(forKey: target) == nil { defaults.set(value, forKey: target); copied += 1 }
        }
        return "\(label): copied \(copied)"
    }

    static func copyTrueFlags(prefix: String, fromPart: String, toPart: String, defaults: UserDefaults) -> String {
        let from = prefix + fromPart + "."
        var copied = 0
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(from) {
            guard (value as? Bool) == true else { continue }
            let target = prefix + toPart + "." + key.dropFirst(from.count)
            if defaults.object(forKey: target) == nil { defaults.set(true, forKey: target); copied += 1 }
        }
        return "Saves: copied \(copied)"
    }

    static func copyIfAbsent(from: String, to: String, defaults: UserDefaults, label: String) -> String {
        guard let value = defaults.object(forKey: from) else { return "\(label): nothing to move" }
        guard defaults.object(forKey: to) == nil else { return "\(label): already present" }
        defaults.set(value, forKey: to)
        return "\(label): copied"
    }

    static func copyFileIfAbsent(_ from: URL, _ to: URL) -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: from.path) else { return "\(from.lastPathComponent): nothing to move" }
        guard !fm.fileExists(atPath: to.path) else { return "\(to.lastPathComponent): already present" }
        do { try fm.copyItem(at: from, to: to); return "\(from.lastPathComponent): copied" }
        catch { return "\(from.lastPathComponent): copy failed (\(error.localizedDescription))" }
    }

    /// Mirrors `FeedInteractionStore.safeUserKeyPart`.
    static func safeSaveKeyPart(_ userID: String) -> String {
        userID.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    nonisolated static func defaultProfilesDirectory() -> URL? {
        ProfileStore.avatarDerivedURL(for: nil)?.deletingLastPathComponent()
    }
}
