//
//  JournalLinkState.swift
//  MOTIVO — private iCloud sync. Compiled in every configuration; nothing
//  here runs until the person turns sync on (see JournalSyncCoordinator).
//
//  WHETHER THIS DEVICE MAY SYNC RIGHT NOW, AND THE LOCAL-REMOVAL LIFECYCLE
//  (stage E). Pure rules and state-file work, no CloudKit, so both are
//  unit-tested without an account.
//
//  The account guard is ONE rule asked by every path that moves data: the
//  outgoing batch, fetched zone and database changes (imports and remote
//  deletions), list imports, and the manual Fetch/Send controls. A refusal
//  pauses; it never deletes anything.
//
//  Local removal (the production erase, or the diagnostics control) must
//  never turn local cleanup into server deletions, including after a
//  relaunch, an interrupted cleanup or a later re-enable. The marker is
//  written BEFORE any row is deleted, in the same atomic write that empties
//  the outbox; while it is set, history is discarded and no engine exists;
//  "finish" fast-forwards the history token recording nothing and resets
//  what this device knew about the server, so re-enabling fetches the cloud
//  journal again as a fresh device would.
//

import Foundation
import CloudKit
import CoreData

enum JournalAccountGuard {
    enum Decision: Equatable {
        case allow
        /// Named so the diagnostics screen can say why. `retry` is true when
        /// the condition can clear on its own (no account yet); false when it
        /// needs the user (a different account, unlinked, removal).
        case refuse(reason: String, retry: Bool)

        var allowed: Bool { self == .allow }
        var reason: String? { if case .refuse(let r, _) = self { return r }; return nil }
    }

    /// `current` nil means the iCloud check failed or the account is gone.
    static func decide(bound: String?, current: String?, unlinked: Bool,
                       localRemovalInProgress: Bool, localCopyRemoved: Bool) -> Decision {
        if localRemovalInProgress {
            return .refuse(reason: "Local removal in progress; nothing is sent or fetched", retry: false)
        }
        if unlinked {
            return .refuse(reason: localCopyRemoved
                           ? "Local copy removed; sync is off until re-enabled (the cloud journal is untouched)"
                           : "Unlinked by the user; the journal is kept and nothing syncs until re-enabled", retry: false)
        }
        guard let current else {
            return .refuse(reason: bound == nil
                           ? "Waiting for iCloud; journal and pending changes kept"
                           : "Signed out of iCloud, or iCloud is off for this app; journal and pending changes kept", retry: true)
        }
        if let bound, bound != current {
            return .refuse(reason: "This journal is linked to a different iCloud account. Nothing is uploaded, downloaded or imported.", retry: false)
        }
        return .allow
    }
}

/// PURE. Whether a server-side database check means the engine missed
/// changes while it did not exist. Without a previous token the check only
/// establishes a baseline (every zone reads as "changed" on a first call).
/// PURE. One `CKSyncEngine.sendChanges` in flight per engine (C-174,
/// 2026-11-04: the overlay's entry precondition trapped when a second send
/// was asked for 1.5 s into a 760 MB first upload, after the engine's own
/// account-change event re-ran activation). A request made while a send runs
/// is remembered and run once, after it.
struct JournalSendGate {
    private(set) var inFlight = false
    private(set) var queued = false

    /// Whether the caller may send now. When not, the request is kept.
    mutating func enter() -> Bool {
        if inFlight { queued = true; return false }
        inFlight = true
        return true
    }

    /// The send finished. Returns whether a kept request should run now.
    mutating func leave() -> Bool {
        inFlight = false
        defer { queued = false }
        return queued
    }
}

enum JournalCatchUp {
    static func mustRefetch(hadToken: Bool, changedZones: [String], deletedZones: [String], zoneName: String) -> Bool {
        guard hadToken else { return false }
        return changedZones.contains(zoneName) || deletedZones.contains(zoneName)
    }

    /// Stage G: whether a changed attachment record needs its file fetched.
    /// Not when this device already holds a usable file whose hash matches
    /// what the server reports (or the server reports none: an old record).
    /// `localHash` is the file here when the caller has it: a file whose
    /// hash is the server's is never fetched, whatever this device last
    /// recorded (2026-11-03: the device's own 132 MB upload, finished by a
    /// dropped engine that never reported it, was fetched back on release).
    /// PURE. What a failed catch-up means (C-149: the app's catch-up is the
    /// only fetch, so recovery is defined here, not by a fresh engine's fetch).
    enum Recovery: Equatable { case retryLater, rereadZone, zoneGone }
    static func recovery(for code: CKError.Code) -> Recovery {
        switch code {
        case .changeTokenExpired: return .rereadZone
        case .zoneNotFound, .userDeletedZone: return .zoneGone
        default: return .retryLater
        }
    }

    static func needsAsset(serverHash: String?, knownHash: String?, fileExists: Bool, localHash: String? = nil) -> Bool {
        guard fileExists else { return true }
        guard let serverHash else { return false }
        if let localHash, localHash == serverHash { return false }
        return knownHash != serverHash
    }
}

/// PURE. What the set-up screen offers BEFORE it asks for a name (C-151).
/// After a device-only removal the binding is kept and the private iCloud
/// journal is untouched, so the person is offered the restoration first; while
/// sync is on and the first complete fetch is pending, the screen says so and
/// a name typed meanwhile is provisional (see `JournalProfileSync.scan`).
enum JournalRestoreOffer: Equatable {
    /// Sync was never turned on here and this build can sync: offer to turn it
    /// on, so a journal already in iCloud comes here before a name is typed.
    case turnOn
    /// Sync is off on this device (a removed local copy, or unlinked): offer to re-enable.
    case offer(localCopyRemoved: Bool)
    /// Sync is on; the first complete fetch has not finished (offline, or still running).
    case restoring(lastFailure: String?)
    /// Sync is on but refused for now (no iCloud account, a different account…).
    case waiting(reason: String)
    /// The first complete fetch finished and the cloud holds no profile name.
    case nothingFound
    /// The cloud profile is here (the set-up gate closes by itself), or sync never started.
    case none

    static func decide(started: Bool, supported: Bool = JournalSyncCapability.buildSupportsSync,
                       unlinked: Bool, localCopyRemoved: Bool, localRemovalInProgress: Bool,
                       pausedReason: String?, initialFetchComplete: Bool, lastCatchUp: String?, profileName: String) -> JournalRestoreOffer {
        guard started else { return supported ? .turnOn : .none }
        guard !localRemovalInProgress else { return .none }
        if unlinked { return .offer(localCopyRemoved: localCopyRemoved) }
        if let pausedReason, !pausedReason.isEmpty { return .waiting(reason: pausedReason) }
        if !initialFetchComplete {
            let failure = lastCatchUp.flatMap { $0.hasPrefix("Delta catch-up failed") ? $0 : nil }
            return .restoring(lastFailure: failure)
        }
        return profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .nothingFound : .none
    }
}

/// PURE. The outbox is the durable record of pending work; an engine built
/// from its saved state restores its own pending list too, which may hold a
/// save the catch-up dropped meanwhile (a lost conflict resolved before the
/// engine existed: on 2026-10-26 the iPad then sent the record once more with
/// the values it had just taken). Returns the record names to remove from the
/// engine's list: saves not pending in the outbox, deletes likewise.
enum JournalPendingReconcile {
    static func stale(engineSaves: [String], engineDeletes: [String], outbox: [JournalSyncPendingChange]) -> (saves: [String], deletes: [String]) {
        let saves = Set(outbox.filter { $0.op == .save }.map(\.recordName))
        let deletes = Set(outbox.filter { $0.op == .delete }.map(\.recordName))
        return (engineSaves.filter { !saves.contains($0) }, engineDeletes.filter { !deletes.contains($0) })
    }
}

/// C-134: a record the server hands back whose change tag this device already
/// holds (its own last send, or a copy already imported) carries nothing new.
enum JournalEcho {
    static func isKnown(changeTag: String?, storedSystemFields: Data?) -> Bool {
        guard let changeTag, let storedSystemFields,
              let known = JournalSyncStateStore.recordFromSystemFields(storedSystemFields)?.recordChangeTag else { return false }
        return known == changeTag
    }
}

/// The local-removal lifecycle on the state file and the store. Every step
/// is idempotent, so a relaunch can repeat it.
enum JournalLocalRemoval {

    /// Step 1, BEFORE any deletion: one atomic write that sets the marker,
    /// empties the outbox and drops held attachments. Returns false when the
    /// write failed (the caller logs loudly; the in-memory marker still holds
    /// for this process).
    @discardableResult
    static func begin(store: JournalSyncStateStore, reason: String) -> Bool {
        store.update { st in
            st.localRemovalInProgress = true
            st.localRemovalReason = reason
            st.outbox.removeAll()
            st.awaitingParent.removeAll()
            st.log.append(.init(at: Date(), text: "Local removal begun (\(reason)): outbox emptied, engine dropped; history is discarded until it finishes"))
        }
    }

    /// Step 2, after the cleanup: fast-forward the history token past every
    /// transaction (recording nothing), forget what the server holds, and
    /// leave sync off until explicitly re-enabled. The bound account is kept
    /// so a different account still cannot adopt this device.
    @discardableResult
    static func finish(store: JournalSyncStateStore, container: NSPersistentContainer) -> Bool {
        let token = container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)
        clearHeldFiles()
        JournalProfileSync.clearDisplacedAvatars()
        JournalScoreSync.clearDisplacedScores()
        return store.update { st in
            st.historyToken = JournalSyncStateStore.encode(token: token)
            st.outbox.removeAll()
            st.lastKnownRecords.removeAll()
            st.knownChangeTags.removeAll()
            st.awaitingParent.removeAll()
            st.assetHashes.removeAll()
            st.fileStampCache.removeAll()
            st.customRecordNames.removeAll()
            st.instrumentAliases.removeAll()
            st.listFingerprints.removeAll()
            st.listScope = nil
            st.conflicts.removeAll()
            st.engineState = nil
            st.catchUpToken = nil
            st.catchUpZoneToken = nil
            st.awaitingMeta.removeAll()
            st.metaTransitionDone = false
            // Stage H: the erased profile is empty; the baseline is the EMPTY
            // profile (not "never scanned"), so anything typed before re-enable
            // is a clocked edit, and the wiped avatar is not a removal.
            st.profileFingerprint = JournalProfileValues().fingerprint
            st.profileStamp = nil
            st.profileStampProvisional = false
            st.avatarRemovedAt = nil
            st.profilePrimaryChosen = false
            // Stage I: the erased library is the baseline (nothing erased is
            // sent; a score added before re-enable is a clocked new item).
            st.scoreFingerprints.removeAll()
            st.scoreStamps.removeAll()
            st.scorePositions.removeAll()
            st.scorePositionStamps.removeAll()
            st.awaitingScore.removeAll()
            st.scoreAwaitingFirstMeta.removeAll()
            st.scoreScanDone = true
            st.scoreIndexDamagedNoted = false
            // Stage J: the wiped defaults are the baseline (nothing erased is
            // sent; a choice made before re-enable is a clocked edit).
            st.settingsScanDone = true
            st.settingFingerprints = Dictionary(uniqueKeysWithValues: JournalSettingKey.all.map { ($0, JournalSettingKey.defaultValue($0)) })
            st.settingStamps.removeAll()
            st.listContextFingerprints.removeAll()
            st.listContextStamps.removeAll()
            st.listContextScope = nil
            st.awaitingListContext.removeAll()
            st.tintMapExchanged = nil
            st.tintMapQueuedFingerprint = nil
            st.mediaWaitingUpload.removeAll()
            st.awaitingMedia.removeAll()
            st.scoresWithoutFile = 0
            st.initialFetchComplete = false
            st.pendingOwnerAdoption = nil
            st.ownershipReport = nil
            // The journal is gone, so the next launch has nothing to bootstrap;
            // rows made before re-enabling are picked up from history.
            st.bootstrapQueued = true
            st.customsBootstrapQueued = false
            st.instrumentsBootstrapQueued = false
            st.localRemovalInProgress = false
            st.localCopyRemoved = true
            st.unlinked = true
            st.log.append(.init(at: Date(), text: "Local removal finished: history fast-forwarded with no deletions queued; server knowledge cleared; sync off until re-enabled"))
        }
    }

    /// At launch, when the marker is still set: the previous cleanup did not
    /// reach `finish`. Removes the journal rows that are left (author
    /// `localRemoval`, which the tracker ignores anyway), sweeps media, and
    /// finishes. Nothing from the interrupted cleanup can reach the outbox:
    /// the tracker discards history while the marker is set, and `finish`
    /// moves the token past it.
    static func recoverIfInterrupted(store: JournalSyncStateStore, container: NSPersistentContainer,
                                     sweepMedia: () -> Void) -> Bool {
        guard store.state.localRemovalInProgress else { return false }
        let ctx = container.newBackgroundContext()
        ctx.transactionAuthor = JournalSyncAuthor.localRemoval
        var removed = 0
        ctx.performAndWait {
            for entity in [JournalSyncRecordType.attachment, JournalSyncRecordType.session,
                           JournalSyncRecordType.userInstrument, JournalSyncRecordType.userActivity] {
                let request = NSFetchRequest<NSManagedObject>(entityName: entity)
                for row in (try? ctx.fetch(request)) ?? [] { ctx.delete(row); removed += 1 }
            }
            if ctx.hasChanges { try? ctx.save() }
        }
        sweepMedia()
        store.log("Interrupted local removal recovered at launch: \(removed) leftover row(s) removed locally")
        let ok = finish(store: store, container: container)
        // H4 (2026-11-03): the recovery deletes fewer things than the removal
        // (the profile row, the Scores library and the index may survive a
        // kill before the defaults wipe). Those leftovers must not become
        // clocked edits at the next re-enable: leave the profile and the
        // library at "never scanned", so they go up as the unclocked
        // transition does and yield to anything clocked in the cloud.
        store.update { st in
            st.profileFingerprint = nil
            st.scoreScanDone = false
        }
        return ok
    }

    /// Re-enable after a removal or an unlink. The caller then reconciles the
    /// account; with `localCopyRemoved` cleared and no engine state, a fresh
    /// engine fetches everything.
    @discardableResult
    static func reenable(store: JournalSyncStateStore) -> Bool {
        store.update { st in
            let was = st.localCopyRemoved ? "a removed local copy" : "an unlinked device"
            if st.localCopyRemoved {
                // B4, second guard: a removed copy has nothing to delete
                // elsewhere; any deletion that reached the outbox during the
                // removal is the removal's own and must never go up.
                let bogus = st.outbox.filter { $0.op == .delete }.count
                if bogus > 0 {
                    st.outbox.removeAll { $0.op == .delete }
                    st.log.append(.init(at: Date(), text: "Dropped \(bogus) deletion(s) queued during the removal; a removed copy deletes nothing elsewhere"))
                }
            }
            st.unlinked = false
            st.localCopyRemoved = false
            st.log.append(.init(at: Date(), text: "Sync re-enabled for \(was)"))
        }
    }

    @discardableResult
    static func unlink(store: JournalSyncStateStore) -> Bool {
        store.update { st in
            st.unlinked = true
            st.log.append(.init(at: Date(), text: "Unlinked: journal kept locally, \(st.outbox.count) pending change(s) kept, nothing syncs until re-enabled"))
        }
    }

    private static func clearHeldFiles() {
        let dir = JournalSyncStateStore.holdingDirectory()
        for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
