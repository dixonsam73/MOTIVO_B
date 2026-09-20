import Foundation
@preconcurrency import CoreData

/// Why a journal delete was refused. The entry is kept in every case, and the
/// messages promise nothing about server state.
enum JournalDeleteRefusal: Equatable {
    /// Connected: the backend delete did not succeed.
    case backendDeleteUnconfirmed
    /// The signed-in identity changed between the swipe and the queue step.
    case identityChanged
    /// The queue could not be saved, so pending shares could not be stopped.
    case queueNotSaved
    /// The local Core Data save failed. Nothing local was deleted.
    case localSaveFailed
    /// Connected: the session has no id to name its post.
    case missingIdentifier
    /// S1: the captured owner is not a backend identity, so nothing was sent.
    case ownerUnavailable

    static let title = "Session not deleted"

    var message: String {
        switch self {
        case .backendDeleteUnconfirmed:
            return "Études couldn’t confirm that this session’s shared post was removed, so the session has been kept. Try again."
        case .identityChanged:
            return "Your Études account changed while this session was being deleted, so it has been kept. Try again."
        case .queueNotSaved, .localSaveFailed, .missingIdentifier, .ownerUnavailable:
            return "Études couldn’t finish deleting this session, so it has been kept. Try again."
        }
    }
}

/// Journal delete. Called by `ContentView`, and by tests.
///
/// Order, fail-closed at each step:
/// 1. Connected only: delete the backend post (and the objects its row names).
/// 2. Replace every queued publish for the post, of any owner and in quarantine,
///    by a withdrawal owned by that same owner, and give candidate owners of an
///    already-acknowledged post a withdrawal attempt (`SessionSyncQueue`).
/// 3. In the SAME synchronous turn, delete the session locally.
///
/// Step 3 follows step 2 with no suspension point, so a handoff replay cannot run
/// between them and re-enqueue a saved choice over the withdrawal.
@MainActor
enum JournalDeleteBackendStep {
    enum Outcome: Equatable {
        case deleted
        case refused(JournalDeleteRefusal)
    }

    /// Connected.
    ///
    /// S1. The backend delete is OWNER-BOUND before any request goes out, and the
    /// gate is re-checked after the last await, before anything local or queued is
    /// touched. The binding captures the identity generation, so an A→B→A switch or
    /// a factory reset invalidates it.
    ///
    /// A validated empty result is SUCCESS: a never-shared entry deletes locally,
    /// exactly as before. `[]` is never read as "another owner holds it". Only a
    /// malformed or mismatched response refuses.
    static func run(postID: UUID, capturedOwner: String?, sessionWasShared: Bool = false,
                    deleteLocally: () -> Bool) async -> Outcome {
        guard let binding = SessionSyncQueue.shared.journalDeleteBinding(capturedOwner: capturedOwner) else {
            print("[Delete][FAIL-CLOSED] no backend identity for the captured owner; nothing sent postID=\(postID)")
            return .refused(.ownerUnavailable)
        }
        let result = await BackendEnvironment.shared.publish.deletePost(postID, binding: binding)
        if case .failure(let err) = result {
            print("[Delete][FAIL-CLOSED] backend deletePost failed postID=\(postID) err=\(err)")
            return .refused(.backendDeleteUnconfirmed)
        }
        // The identity may have changed while the last request was in flight.
        guard binding.isStillCurrent() else {
            print("[Delete][FAIL-CLOSED] identity changed during the backend delete postID=\(postID)")
            return .refused(.identityChanged)
        }
        return finish(postID: postID, capturedOwner: capturedOwner, sessionWasShared: sessionWasShared, deleteLocally: deleteLocally)
    }

    /// Solo, lapsed or signed out: no backend call.
    static func runLocalOnly(postID: UUID, capturedOwner: String?, sessionWasShared: Bool = false,
                             deleteLocally: () -> Bool) -> Outcome {
        finish(postID: postID, capturedOwner: capturedOwner, sessionWasShared: sessionWasShared, deleteLocally: deleteLocally)
    }

    private static func finish(postID: UUID, capturedOwner: String?, sessionWasShared: Bool,
                               deleteLocally: () -> Bool) -> Outcome {
        switch SessionSyncQueue.shared.supersedeQueuedPublishForJournalDelete(postID: postID, capturedOwner: capturedOwner,
                                                                            sessionWasShared: sessionWasShared) {
        case .identityChanged:
            return .refused(.identityChanged)
        case .notSaved:
            print("[Delete][FAIL-CLOSED] queued publishes not superseded postID=\(postID)")
            return .refused(.queueNotSaved)
        case .proceed:
            return deleteLocally() ? .deleted : .refused(.localSaveFailed)
        }
    }

    /// Deletes one session in its OWN context and saves only that change, so a
    /// failed save leaves nothing pending in the editors' context for an
    /// unrelated later save to commit, and discards none of their edits. The
    /// session's media files are removed only after the save succeeded.
    /// The view context learns of the deletion through its ordinary merge.
    static func deleteSessionLocally(objectID: NSManagedObjectID,
                                     container: NSPersistentContainer = PersistenceController.shared.container) -> Bool {
        guard !objectID.isTemporaryID else { return false }
        let context = container.newBackgroundContext()
        context.name = "journalDelete.local"
        var paths: [String] = []
        var saved = false
        context.performAndWait {
            guard let session = try? context.existingObject(with: objectID) else { return }
            let attachments = (session.value(forKey: "attachments") as? Set<NSManagedObject>) ?? []
            paths = attachments.compactMap { att in
                guard let s = att.value(forKey: "fileURL") as? String, !s.isEmpty else { return nil }
                return s
            }
            context.delete(session)
            do {
                #if DEBUG
                if unitTestFailNextLocalSave {
                    unitTestFailNextLocalSave = false
                    throw NSError(domain: "JournalDelete", code: 1, userInfo: [NSLocalizedDescriptionKey: "test"])
                }
                #endif
                try context.save()
                saved = true
            } catch {
                context.rollback()
                print("Delete error: \(error)")
            }
        }
        if saved, !paths.isEmpty {
            AttachmentStore.deleteAttachmentFiles(atPaths: paths)
        }
        return saved
    }

    #if DEBUG
    /// TEST-ONLY: makes the next local delete's save fail, as a failed write would.
    nonisolated(unsafe) static var unitTestFailNextLocalSave = false
    #endif
}
