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
    /// P6-I-02. SYMBOL PRESERVED. It has no callers today, and it must not become
    /// a way to create executable unowned work if one is ever added: the owner is
    /// captured here, synchronously, and the enqueue refuses when there is none.
    func enqueueForPublish(_ postID: UUID) {
        SessionSyncQueue.shared.enqueue(postID: postID, capturedOwner: SessionSyncQueue.currentOwner())
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
