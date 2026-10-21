//
//  JournalOwnershipCoordinator.swift
//  MOTIVO — Études Sync Test only (SYNCTEST configuration)
//
//  APPLIES THE OWNERSHIP RULES ON THE DEVICE (stage B).
//
//  Runs after every complete fetch, at launch and whenever K1 changes:
//  1. finishes an interrupted adoption;
//  2. decides adoption over the whole local store (`JournalOwnership`), only
//     once a complete fetch has finished; never overwrites an existing K1;
//     reports mixed owners and changes nothing for them;
//  3. on a device with K1, gives ownerless entries that owner, the same rule
//     a first Connected sign-in applies (`adoptOwnerlessLocalSessionsIfNeeded`),
//     so no entry on the device loses owner treatment (private notes, private
//     attachments, threads, tint).
//
//  Adoption is NOT a sign-in: it writes the Keychain owner key and nothing
//  else (`AuthManager.adoptOwnerForSyncTest`). No Supabase session, backend
//  id, publishing, directory or avatar work starts from it.
//

#if SYNCTEST
import Foundation
import CoreData
import Combine

@MainActor
final class JournalOwnershipCoordinator {
    let store: JournalSyncStateStore
    let persistence: NSPersistentContainer
    weak var auth: AuthManager?
    /// Called after K1 changes, so entries held back can be queued again.
    var onOwnerChanged: () -> Void = {}
    private var cancellable: AnyCancellable?
    private var lastSeenOwner: String?
    /// Trial resets only. Clearing the owner key while the journal still holds
    /// owned entries would otherwise re-adopt that owner at once (seen
    /// 2026-10-19); the app is deleted next, so this need not persist.
    private(set) var suspendedForReset = false

    func suspendForReset() {
        suspendedForReset = true
        store.log("Ownership rules suspended for a trial reset")
    }

    init(store: JournalSyncStateStore, persistence: NSPersistentContainer, auth: AuthManager?) {
        self.store = store
        self.persistence = persistence
        self.auth = auth
        lastSeenOwner = JournalOwnership.normalized(Keychain.get("appleUserID"))
        cancellable = auth?.$currentUserID.removeDuplicates().dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.evaluate(reason: "owner key changed") }
        }
    }

    func localOwners() -> Set<String> {
        var owners = Set<String>()
        let ctx = persistence.viewContext
        let request = NSFetchRequest<NSDictionary>(entityName: JournalSyncRecordType.session)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["ownerUserID"]
        request.returnsDistinctResults = true
        for row in (try? ctx.fetch(request)) ?? [] {
            if let owner = JournalOwnership.normalized(row["ownerUserID"] as? String) { owners.insert(owner) }
        }
        return owners
    }

    func evaluate(reason: String) {
        // During a local removal the erase deletes the owner key before the
        // rows; evaluating then re-adopts the owner from rows about to go
        // (seen 2026-10-21). Nothing to decide until the removal is over.
        guard !suspendedForReset, !store.state.localRemovalInProgress else { return }
        if let pending = store.state.pendingOwnerAdoption {
            let k1 = JournalOwnership.normalized(Keychain.get("appleUserID"))
            if k1 == nil || k1 == pending {
                store.log("Completing an interrupted owner adoption")
                adopt(pending)
            } else {
                store.update { $0.pendingOwnerAdoption = nil }
                store.log("Interrupted adoption dropped: this device now has a different owner key")
            }
        }

        let k1 = Keychain.get("appleUserID")
        let owners = localOwners()
        let decision = JournalOwnership.decideAdoption(k1: k1, localOwners: owners,
                                                       initialFetchComplete: store.state.initialFetchComplete)
        var report: String
        switch decision {
        case .wait:
            report = "Waiting for the first complete fetch before adopting an owner"
        case .nothingToDo:
            report = JournalOwnership.normalized(k1) == nil ? "Ownerless journal; no owner key" : "One owner; owner key matches"
        case .adopt(let owner):
            adopt(owner)
            report = "Adopted the journal's owner (\(owner.prefix(10))…)"
        case .report(let foreign):
            report = "Entries owned by \(foreign.count) other Apple user id(s) are kept and not uploaded; owner key unchanged"
        }

        if let k1 = JournalOwnership.normalized(Keychain.get("appleUserID")) {
            let ownerless = ownerlessCount()
            if ownerless > 0 {
                PersistenceController.shared.adoptOwnerlessLocalSessionsIfNeeded(for: k1, in: persistence.viewContext)
                store.log("Gave \(ownerless) ownerless entr\(ownerless == 1 ? "y" : "ies") the owner key")
            }
        }

        let owner = JournalOwnership.normalized(Keychain.get("appleUserID"))
        // Whatever route set the key (adoption, the sign-in step, or a launch
        // that already holds it): stores looked up under "no owner" move with
        // it, once per owner (C-116's production merge, plus the local
        // profile, which the trial has no sign-in flow to carry).
        if let owner { mergeNoOwnerStores(into: owner, tag: "Owner key set") }
        if owner != lastSeenOwner {
            lastSeenOwner = owner
            onOwnerChanged()
        }
        if store.state.ownershipReport != report {
            store.update { $0.ownershipReport = report }
            store.log("Ownership (\(reason)): \(report)")
        }
    }

    private func mergeNoOwnerStores(into owner: String, tag: String) {
        let notes = LocalOwnerStoreMigration.mergeNoOwnerStoresIfNeeded(
            into: owner, includeProfile: true, profilesDirectory: LocalOwnerStoreMigration.defaultProfilesDirectory())
        guard notes != ["Already merged for this owner"] else { return }
        for note in notes { store.log("\(tag): \(note)") }
        EnsembleStore.shared.load()
    }

    /// Recoverable: the marker is written first, every store merge is
    /// copy-if-absent, and the marker is cleared last.
    private func adopt(_ owner: String) {
        guard let auth else { store.log("Owner adoption deferred: no auth"); return }
        store.update { $0.pendingOwnerAdoption = owner }
        mergeNoOwnerStores(into: owner, tag: "Adoption")
        auth.adoptOwnerForSyncTest(owner)
        guard JournalOwnership.normalized(Keychain.get("appleUserID")) == owner else {
            store.log("Adoption stopped: the owner key holds a different value")
            store.update { $0.pendingOwnerAdoption = nil }
            return
        }
        store.update { $0.pendingOwnerAdoption = nil }
    }

    private func ownerlessCount() -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: JournalSyncRecordType.session)
        request.predicate = NSPredicate(format: "ownerUserID == nil OR ownerUserID == ''")
        return (try? persistence.viewContext.count(for: request)) ?? 0
    }
}
#endif
