import Foundation

/// Journal delete, Connected branch: the backend step that must succeed before
/// the entry is deleted locally. Called by `ContentView`, and by tests.
///
/// Order, fail-closed at each step:
/// 1. delete the backend post (and the objects its row names);
/// 2. supersede this owner's still-queued publish for the post, so a later flush
///    cannot re-create it.
///
/// Returns true only when local deletion may proceed. Local deletion is not
/// transactional with either step: if the Core Data save then fails, the
/// backend post is already gone and the withdrawal stays queued.
@MainActor
enum JournalDeleteBackendStep {
    static func run(postID: UUID, capturedOwner: String?) async -> Bool {
        let result = await BackendEnvironment.shared.publish.deletePost(postID)
        if case .failure(let err) = result {
            print("[Delete][FAIL-CLOSED] backend deletePost failed postID=\(postID) err=\(err)")
            return false
        }
        guard SessionSyncQueue.shared.supersedeQueuedPublishForJournalDelete(postID: postID, capturedOwner: capturedOwner) else {
            print("[Delete][FAIL-CLOSED] queued publish not superseded postID=\(postID)")
            return false
        }
        return true
    }
}
