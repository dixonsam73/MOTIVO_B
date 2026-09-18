//
//  SharingHandoff.swift
//  MOTIVO
//
//  P6-I-03 / C1 — a saved sharing choice survives a restart.
//
//  An editor writes the EXACT choice it is about to queue — captured owner, final
//  notes and notes privacy, mapped consent, a durable token — into the Session's
//  `sharingHandoff` marker in the SAME Core Data save as `isPublic`. Once the
//  queue has durably taken that choice, the marker is cleared, but only if it
//  still holds that same token. If the process dies in between, the next launch
//  replays the marker before anything is dispatched (the barrier in
//  `SessionSyncQueue.flushOnce`), so an older queued intent cannot go first.
//
//  SCOPE, stated so it is not over-read:
//  - Only choices saved through the two editors. `ContentView`'s direct delete
//    is not a queued choice and is not covered.
//  - Only on the SAME install with a readable or recoverable queue store. A
//    marker from another install — a restored or copied backup, or a store
//    lost on this install, which cannot be told apart — is HELD: its post is
//    withheld from dispatch and the marker is never replayed or cleared
//    automatically. A new choice on that session replaces it.
//  - No server ordering. A late request already in flight is not stopped here.
//

import Foundation
@preconcurrency import CoreData

/// What the marker holds. Ids and the member's own choice; nothing else.
struct SharingHandoffRecord: Codable, Equatable {
    static let currentVersion = 1

    let v: Int
    /// The install that made the choice. A marker from any other stream is held.
    let stream: UUID
    /// The choice's durable identity. Equal to `payload.choiceToken`.
    let token: UUID
    /// The exact payload the queue is given: replayed, never reconstructed.
    let payload: SessionSyncQueue.PostPublishPayload
}

enum SharingHandoff {
    static let attribute = "sharingHandoff"

    enum Decoded: Equatable {
        case record(SharingHandoffRecord)
        case unreadable
    }

    static func encode(_ record: SharingHandoffRecord) -> Data? {
        try? JSONEncoder().encode(record)
    }

    /// Anything not exactly a current-version record whose token agrees with its
    /// payload is unreadable, and unreadable is HELD, never guessed at.
    static func decode(_ data: Data) -> Decoded {
        guard let record = try? JSONDecoder().decode(SharingHandoffRecord.self, from: data),
              record.v == SharingHandoffRecord.currentVersion,
              record.payload.choiceToken == record.token else { return .unreadable }
        return .record(record)
    }

    /// Why a marker could not be written. Thrown from inside the editor's save
    /// step, so the attachment transaction treats it as a failed save: files are
    /// rolled back, the undo group is discarded, and the member is told the
    /// session was not saved. **A choice is never saved without its marker.**
    struct StageFailure: LocalizedError {
        let reason: String
        var errorDescription: String? { "The sharing choice could not be recorded (\(reason))." }
    }

    /// Writes the marker on `session` BEFORE the editor's save, so it commits in
    /// the same transaction as `isPublic` or not at all — a failed save's undo
    /// group takes it back with everything else.
    @MainActor
    static func stage(_ choice: SessionSyncQueue.PostPublishPayload,
                      on session: NSManagedObject) throws {
        try stage(choice, on: session, queue: .shared)
    }

    @MainActor
    static func stage(_ choice: SessionSyncQueue.PostPublishPayload,
                      on session: NSManagedObject,
                      queue: SessionSyncQueue) throws {
        #if DEBUG
        if unitTestFailNextStage { unitTestFailNextStage = false; throw StageFailure(reason: "test") }
        #endif
        guard session.entity.attributesByName[attribute] != nil else { throw StageFailure(reason: "model") }
        guard let token = choice.choiceToken else { throw StageFailure(reason: "no token") }
        let sessionID = session.value(forKey: "id") as? UUID
        guard sessionID == choice.id, choice.sessionID == nil || choice.sessionID == sessionID else {
            throw StageFailure(reason: "identity")
        }
        // No durable stream, no marker — and so no save. The member is told the
        // session was not saved and can try again; nothing is half-recorded.
        guard let stream = queue.streamForNewChoice() else { throw StageFailure(reason: "install stream not durable") }
        let record = SharingHandoffRecord(v: SharingHandoffRecord.currentVersion,
                                          stream: stream,
                                          token: token,
                                          payload: choice)
        guard let data = encode(record) else { throw StageFailure(reason: "encode") }
        session.setValue(data, forKey: attribute)
    }

    /// COMPARE-AND-CLEAR, isolated from the caller's context.
    ///
    /// A private context reads the marker as the store holds it, clears it only
    /// if it still carries `token`, and saves that one attribute. The editor's
    /// context is never refreshed, rolled back or saved here, so unrelated
    /// pending edits there are untouched; it learns of the change through its
    /// ordinary merge from the store. An older clear finds a newer token and
    /// does nothing. A conflicting concurrent write fails the save and the
    /// marker stays — a later replay is then a ledger no-op.
    @discardableResult
    static func clearIfMatches(objectID: NSManagedObjectID, token: UUID,
                               container: NSPersistentContainer) -> Bool {
        guard !objectID.isTemporaryID else { return false }
        #if DEBUG
        if unitTestFailNextClear { unitTestFailNextClear = false; return false }
        #endif
        let context = container.newBackgroundContext()
        context.name = "sharingHandoff.clear"
        var cleared = false
        context.performAndWait {
            guard let object = try? context.existingObject(with: objectID),
                  let data = object.value(forKey: attribute) as? Data,
                  case .record(let record) = decode(data),
                  record.token == token else { return }
            object.setValue(nil, forKey: attribute)
            do {
                try context.save()
                cleared = true
            } catch {
                context.rollback()
                BackendLogger.notice("Handoff clear not saved • marker kept • \(error.localizedDescription)")
            }
        }
        return cleared
    }

    #if DEBUG
    /// TEST-ONLY, hosted test runs only: makes the next compare-and-clear save
    /// fail, as a failed write would.
    nonisolated(unsafe) static var unitTestFailNextClear = false
    /// TEST-ONLY: makes the next stage throw, as a failed marker write would.
    nonisolated(unsafe) static var unitTestFailNextStage = false
    #endif
}

// MARK: - Recovery

/// Replays saved choices the queue never durably took, then opens the dispatch
/// barrier. Runs on the main actor, in one turn, so no editor save interleaves.
@MainActor
enum SharingHandoffRecovery {

    private struct Marker {
        let objectID: NSManagedObjectID
        let sessionID: UUID?
        let data: Data
    }

    /// Read the markers without touching the editors' context: a private context,
    /// plain values out.
    private static func readMarkers(container: NSPersistentContainer) -> [Marker]? {
        let context = container.newBackgroundContext()
        context.name = "sharingHandoff.recovery"
        var result: [Marker]?
        context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "Session")
            request.predicate = NSPredicate(format: "%K != nil", SharingHandoff.attribute)
            request.returnsObjectsAsFaults = false
            guard let sessions = try? context.fetch(request) else { return }
            result = sessions.compactMap { session in
                guard let data = session.value(forKey: SharingHandoff.attribute) as? Data else { return nil }
                return Marker(objectID: session.objectID,
                              sessionID: session.value(forKey: "id") as? UUID,
                              data: data)
            }
        }
        return result
    }

    #if DEBUG
    /// TEST-ONLY: makes the next marker read fail, as a failed fetch would.
    nonisolated(unsafe) static var unitTestFailNextFetch = false
    #endif

    @discardableResult
    static func run(reason: String) -> SessionSyncQueue.HandoffRecoveryState {
        run(reason: reason, container: PersistenceController.shared.container, queue: .shared)
    }

    @discardableResult
    static func run(reason: String,
                    container: NSPersistentContainer,
                    queue: SessionSyncQueue) -> SessionSyncQueue.HandoffRecoveryState {
        // 1. A halted store takes nothing durably; dispatch is already refused.
        guard queue.reconcileState.isOK else {
            queue.setHandoffRecovery(.blocked("store halted"), blockedPosts: queue.handoffBlockedPosts)
            return queue.handoffRecovery
        }
        // A stream that is not yet verified on disk cannot tell own from foreign.
        guard let stream = queue.streamForNewChoice() else {
            queue.setHandoffRecovery(.blocked("install stream not durable"), blockedPosts: queue.handoffBlockedPosts)
            return queue.handoffRecovery
        }

        // 2. If the markers cannot be read, nothing may go first.
        var markers = readMarkers(container: container)
        #if DEBUG
        if unitTestFailNextFetch { unitTestFailNextFetch = false; markers = nil }
        #endif
        guard let markers else {
            queue.setHandoffRecovery(.blocked("markers unreadable"), blockedPosts: queue.handoffBlockedPosts)
            return queue.handoffRecovery
        }

        // 3. Per marker. The blocked set is RECOMPUTED from scratch every run.
        var blocked: Set<UUID> = []
        var replayed = 0, cleared = 0, foreign = 0, unreadable = 0
        for marker in markers {
            // A marker whose post cannot be identified could hold back ANY post's
            // older queued work, so nothing may be dispatched. Editors only ever
            // stage on a session that has an id; this is not a normal state.
            guard let sessionID = marker.sessionID else {
                queue.setHandoffRecovery(.blocked("marker on a session with no id"), blockedPosts: blocked)
                return queue.handoffRecovery
            }
            guard case .record(let record) = SharingHandoff.decode(marker.data),
                  record.payload.id == sessionID,
                  record.payload.sessionID == nil || record.payload.sessionID == sessionID else {
                unreadable += 1
                blocked.insert(sessionID)
                continue
            }
            let postID = record.payload.id
            guard record.stream == stream else {
                // Another install's choice — or this install's, from a store that
                // was lost. Held: never replayed, never cleared automatically.
                foreign += 1
                blocked.insert(postID)
                continue
            }
            if queue.verifiedHandoffToken(owner: record.payload.ownerUserID, postID: postID) == record.token {
                // Already durably taken. Only the marker is left.
                if clear(marker.objectID, record.token, container) { cleared += 1 }
                continue
            }
            // The exact failed call, with its own token and captured owner.
            switch queue.enqueueReportingSave(record.payload) {
            case .saved, .heldUnowned:
                replayed += 1
                if clear(marker.objectID, record.token, container) { cleared += 1 }
            case .notSaved:
                queue.setHandoffRecovery(.blocked("replay not saved"), blockedPosts: blocked)
                return queue.handoffRecovery
            }
        }

        BackendLogger.notice("Handoff recovery • \(reason) • markers=\(markers.count) replayed=\(replayed) cleared=\(cleared) foreign=\(foreign) unreadable=\(unreadable)")
        queue.setHandoffRecovery(.complete, blockedPosts: blocked)
        return .complete
    }

    private static func clear(_ objectID: NSManagedObjectID, _ token: UUID, _ container: NSPersistentContainer) -> Bool {
        SharingHandoff.clearIfMatches(objectID: objectID, token: token, container: container)
    }
}
