//
//  FeedInteractionStore+SyncQueue.swift
//  MOTIVO
//
//  CHANGE-ID: 20251112-FeedInteractionStoreSync-0f52
//  SCOPE: v7.12D — additive helper to enqueue posts for publish
//
//  Usage: call `enqueueForPublish(postID)` at the point where a post is ready
//  to be uploaded (e.g., after finishing a session and marking it for sharing).
//  This file is additive and does not change existing behaviour by itself.
//

import Foundation

extension FeedInteractionStore {
    @MainActor
    func enqueueForPublish(_ postID: UUID) {
        SessionSyncQueue.shared.enqueue(postID: postID)
        Task { @MainActor in
            if BackendEnvironment.shared.isPreview {
                await BackendDiagnostics.shared.simulatedCall(
                    "Feed.enqueueForPublish",
                    meta: ["postID": postID.uuidString]
                )
            }
        }
    }
}
