//  FeedInteractionStore.swift
//  MOTIVO
//
//  v7.10F — Local-only feed interactions persisted via UserDefaults.
//  v8H-A  — Hearts are binary only (no counts anywhere).
//  Keys are namespaced to avoid collisions.

import Foundation

struct FeedInteractionStore {
    // NOTE: We keep the existing key prefix for backwards compatibility.
    // Semantics changed in 8H-A: the stored boolean is a binary "heart given by me".
    private static let heartKeyPrefix = "feed.interact.v1.like."

    // Comment count remains for now (will be addressed in 8H-B).
    private static let commentCountKeyPrefix = "feed.interact.v1.commentCount."

    private static func heartKey(_ id: UUID) -> String { heartKeyPrefix + id.uuidString }
    private static func commentCountKey(_ id: UUID) -> String { commentCountKeyPrefix + id.uuidString }

    // MARK: - Hearts (binary, no counts)

    /// Returns whether the current viewer has hearted the post locally.
    static func isHearted(_ id: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: heartKey(id))
    }

    /// Toggle heart. Returns the new state.
    @discardableResult
    static func toggleHeart(_ id: UUID) -> Bool {
        let key = heartKey(id)
        let was = UserDefaults.standard.bool(forKey: key)
        let now = !was
        UserDefaults.standard.set(now, forKey: key)
        return now
    }

    // Back-compat shims (kept to avoid build breaks elsewhere in the project).
    // These MUST remain count-free.
    static func isLiked(_ id: UUID) -> Bool { isHearted(id) }
    @discardableResult static func toggleLike(_ id: UUID) -> Bool { toggleHeart(id) }
    static func likeCount(_ id: UUID) -> Int { 0 }
    static func setLikeCount(_ id: UUID, _ n: Int) { /* 8H-A: no-op (counts removed) */ }

    // MARK: - Comments (temporary legacy until 8H-B)

    static func commentCount(_ id: UUID) -> Int {
        max(0, UserDefaults.standard.integer(forKey: commentCountKey(id)))
    }

    static func setCommentCount(_ id: UUID, _ n: Int) {
        UserDefaults.standard.set(max(0, n), forKey: commentCountKey(id))
    }

    // MARK: - v7.12D additive

    /// Enqueue a post for backend publish. No effect in Local Simulation mode.
    @MainActor static func markForPublish(_ id: UUID) {
        let queue = SessionSyncQueue.shared
        queue.enqueue(postID: id)
        Task { @MainActor in
            if BackendEnvironment.shared.isPreview {
                await BackendDiagnostics.shared.simulatedCall(
                    "FeedInteractionStore.markForPublish",
                    meta: ["postID": id.uuidString]
                )
            }
        }
    }
}
