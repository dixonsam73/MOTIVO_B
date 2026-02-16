// CHANGE-ID: 20260214_113225_8H_PersistComments
// SCOPE: Phase 8H persistence — connected-mode backend comments store (fetch/add/reply/fan-out/delete). Local CommentsStore remains unchanged.
// SEARCH-TOKEN: 20260214_113225_8H_PersistComments_BackendCommentsStore

import Foundation

@MainActor
public final class BackendCommentsStore: ObservableObject {
    @Published public private(set) var comments: [BackendPostComment] = []
    @Published public private(set) var isFetching: Bool = false
    @Published public private(set) var lastError: String? = nil
    @Published public private(set) var lastFetchAt: Date? = nil

    private let service: BackendPostCommentService

    public init(service: BackendPostCommentService = HTTPBackendPostCommentService()) {
        self.service = service
    }

    public func refresh(postID: UUID) async {
        isFetching = true
        lastError = nil

        let result = await service.fetchComments(postID: postID)
        switch result {
        case .success(let rows):
            comments = rows.sorted(by: { $0.createdAt < $1.createdAt })
            lastFetchAt = Date()
            // Viewer-local presence: keep comment icon state in sync with the latest fetched snapshot.
            CommentPresenceStore.shared.set(postID: postID, hasComments: !rows.isEmpty)
        case .failure(let e):
            // Fail-closed: keep existing comments snapshot and surface a gentle error string.
            lastError = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
        }

        isFetching = false
    }

    public func addComment(postID: UUID, body: String) async -> Result<Void, Error> {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success(()) }

        let result = await service.addPostComment(postID: postID, body: trimmed)
        switch result {
        case .success:
            await refresh(postID: postID)
            return .success(())
        case .failure(let e):
            lastError = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            return .failure(e)
        }
    }

    public func replyToCommenter(postID: UUID, recipientUserID: String, body: String) async -> Result<Void, Error> {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let rid = recipientUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !rid.isEmpty else { return .success(()) }

        let result = await service.replyToCommenter(postID: postID, recipientUserID: rid, body: trimmed)
        switch result {
        case .success:
            await refresh(postID: postID)
            return .success(())
        case .failure(let e):
            lastError = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            return .failure(e)
        }
    }

    public func respondToCommenters(postID: UUID, body: String) async -> Result<Void, Error> {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success(()) }

        let result = await service.respondToCommenters(postID: postID, body: trimmed)
        switch result {
        case .success:
            await refresh(postID: postID)
            return .success(())
        case .failure(let e):
            lastError = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            return .failure(e)
        }
    }

    public func deleteComment(commentID: UUID, postID: UUID) async -> Result<Void, Error> {
        let result = await service.deleteComment(commentID: commentID)
        switch result {
        case .success:
            await refresh(postID: postID)
            return .success(())
        case .failure(let e):
            lastError = (e as? LocalizedError)?.errorDescription ?? e.localizedDescription
            return .failure(e)
        }
    }
}
