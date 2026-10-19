//
//  JournalOwnerStoreMigration.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
//
//  KEEPING LOCAL DATA WHEN A DEVICE ADOPTS THE JOURNAL'S OWNER (stage B).
//
//  Several local stores are looked up under K1, or under a fixed "no owner"
//  name when K1 is absent. When a device without K1 adopts the journal's
//  owner, those lookups move. This copies each "no owner" store into the K1
//  form WITHOUT overwriting anything already there and without deleting the
//  source, so it is idempotent and a re-run after an interruption is safe.
//
//  Stores covered: saved Lists ("device"), per-context list settings,
//  ensembles ("local-device"), instrument and thread tint maps
//  ("__anonymous__"), saves/favourites ("unknown"), and the local profile's
//  location and avatar files ("__local_etudes_profile__"). Attachment titles
//  need nothing: their writes are unscoped (C-47) and reads still see them.
//  Nothing here uploads, publishes or touches the backend.
//

#if SYNCTEST
import Foundation

@MainActor
enum JournalOwnerStoreMigration {

    static let listsNoOwnerScope = "device"
    static let ensemblesNoOwner = "local-device"
    static let tintNoOwner = "__anonymous__"
    static let savesNoOwner = "unknown"
    static let profileNoOwner = "__local_etudes_profile__"

    /// Returns one line per store for the diagnostics log.
    @discardableResult
    static func mergeNoOwnerStores(into rawOwner: String,
                                   defaults: UserDefaults = .standard,
                                   profilesDirectory: URL? = defaultProfilesDirectory()) -> [String] {
        guard let owner = JournalOwnership.normalized(rawOwner) else { return ["No owner given; nothing moved"] }
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
        notes.append(copyIfAbsent(from: "profile.\(profileNoOwner).location", to: "profile.\(owner).location",
                                  defaults: defaults, label: "Profile location"))
        if let dir = profilesDirectory {
            for suffix in ["-original.jpg", "-avatar.png"] {
                notes.append(copyFileIfAbsent(dir.appendingPathComponent(profileNoOwner + suffix),
                                              dir.appendingPathComponent(owner + suffix)))
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
#endif
