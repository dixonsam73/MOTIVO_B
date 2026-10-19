//
//  JournalOwnership.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
//
//  WHO OWNS THE SYNCED JOURNAL, AS PURE RULES (stage B).
//
//  The bound private iCloud zone is the journal. Sign in with Apple uses the
//  same Apple Account as iCloud, so one journal carries ONE Apple user id
//  (K1, `Session.ownerUserID`) or nil. That is a rule enforced here, not an
//  assumption: data that breaks it is kept intact and reported, never merged.
//
//  - A device without K1 adopts the journal's single owner, but only after a
//    complete fetch, so the decision never depends on which batch came first.
//  - A device that already has K1 never has it overwritten by synced data.
//  - Upload eligibility is ownership alone: ownerless entries, and entries of
//    the journal's owner. Anything else stays local and intact.
//  - Ownership only ever moves from nil to an owner through sync; it never
//    regresses to nil, and an owner-only change is not a user edit.
//
//  Custom instruments and activities (K2, `local:<install>`) are scoped per
//  install and never synced as an owner: imports are stamped with this
//  device's K2. Duplicates by normalised name resolve to the smallest id.
//

#if SYNCTEST
import Foundation

enum JournalOwnership {

    static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: Assessment

    enum Assessment: Equatable {
        /// Every entry is ownerless.
        case ownerless
        case single(String)
        /// More than one Apple user id. Kept intact and reported.
        case mixed(Set<String>)
    }

    static func assess(_ owners: Set<String>) -> Assessment {
        let cleaned = Set(owners.compactMap { normalized($0) })
        switch cleaned.count {
        case 0: return .ownerless
        case 1: return .single(cleaned.first!)
        default: return .mixed(cleaned)
        }
    }

    /// The owner this device's journal is under: K1 when set, otherwise the
    /// single owner found locally, otherwise none (ownerless or mixed).
    static func journalOwner(k1: String?, local: Assessment) -> String? {
        if let k1 = normalized(k1) { return k1 }
        if case .single(let owner) = local { return owner }
        return nil
    }

    /// Upload eligibility, by ownership only (never by a screen filter).
    static func isEligible(owner: String?, journalOwner: String?) -> Bool {
        guard let owner = normalized(owner) else { return true }
        return owner == normalized(journalOwner)
    }

    // MARK: Adoption

    enum AdoptionDecision: Equatable {
        /// Not yet: the first complete fetch has not finished.
        case wait
        case nothingToDo
        case adopt(String)
        /// Data owned by other Apple user ids: report, change nothing.
        case report(foreign: Set<String>)
    }

    /// Order-independent: evaluated over the WHOLE local store, and only once
    /// a complete fetch has finished. Never overwrites an existing K1.
    static func decideAdoption(k1: String?, localOwners: Set<String>, initialFetchComplete: Bool) -> AdoptionDecision {
        let owners = Set(localOwners.compactMap { normalized($0) })
        if let k1 = normalized(k1) {
            let foreign = owners.subtracting([k1])
            return foreign.isEmpty ? .nothingToDo : .report(foreign: foreign)
        }
        guard initialFetchComplete else { return .wait }
        switch assess(owners) {
        case .ownerless: return .nothingToDo
        case .single(let owner): return .adopt(owner)
        case .mixed(let all): return .report(foreign: all)
        }
    }

    // MARK: Owner merge (ownership is separate from content)

    /// The owner an entry should carry after combining a local and a server
    /// copy: an owner beats nil in either direction; two different owners keep
    /// the local one (the anomaly is reported, nothing is overwritten).
    static func mergedOwner(local: String?, server: String?) -> String? {
        normalized(local) ?? normalized(server)
    }

    /// Keys whose change alone is not a user edit.
    static let ownershipOnlyKeys: Set<String> = ["ownerUserID", "userModifiedAt"]

    static func isOwnershipOnly(_ changedKeys: Set<String>) -> Bool {
        !changedKeys.isEmpty && changedKeys.isSubset(of: ownershipOnlyKeys)
    }

    // MARK: Custom rows (K2)

    /// Deterministic winner among rows with the same normalised name: the
    /// smallest id. Every device picks the same one, whatever the arrival order.
    static func dedupeWinner(_ ids: [UUID]) -> UUID? {
        ids.min { $0.uuidString < $1.uuidString }
    }
}
#endif
