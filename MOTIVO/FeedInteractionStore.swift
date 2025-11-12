//  FeedInteractionStore.swift
//  MOTIVO
//
//  v7.10F — Local-only feed interactions (Like · Comment) persisted via UserDefaults.
//  Keys are namespaced to avoid collisions.

import Foundation

struct FeedInteractionStore {
    private static let likeKeyPrefix = "feed.interact.v1.like."
    private static let likeCountKeyPrefix = "feed.interact.v1.likeCount."
    private static let commentCountKeyPrefix = "feed.interact.v1.commentCount."

    private static func likeKey(_ id: UUID) -> String { likeKeyPrefix + id.uuidString }
    private static func likeCountKey(_ id: UUID) -> String { likeCountKeyPrefix + id.uuidString }
    private static func commentCountKey(_ id: UUID) -> String { commentCountKeyPrefix + id.uuidString }

    static func isLiked(_ id: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: likeKey(id))
    }

    // Toggle like and adjust count accordingly. Returns the new liked state.
    @discardableResult
    static func toggleLike(_ id: UUID) -> Bool {
        let key = likeKey(id)
        let wasLiked = UserDefaults.standard.bool(forKey: key)
        let nowLiked = !wasLiked
        UserDefaults.standard.set(nowLiked, forKey: key)

        let countKey = likeCountKey(id)
        let current = max(0, UserDefaults.standard.integer(forKey: countKey))
        let updated = nowLiked ? current + 1 : max(0, current - 1)
        UserDefaults.standard.set(updated, forKey: countKey)
        return nowLiked
    }

    static func likeCount(_ id: UUID) -> Int {
        max(0, UserDefaults.standard.integer(forKey: likeCountKey(id)))
    }

    static func setLikeCount(_ id: UUID, _ n: Int) {
        UserDefaults.standard.set(max(0, n), forKey: likeCountKey(id))
    }

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
