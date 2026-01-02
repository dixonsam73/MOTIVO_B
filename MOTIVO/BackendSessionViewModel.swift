import Foundation

// A lightweight, read-only adapter that maps a BackendPost into a UI-friendly “session-like” shape.
// This type contains no Core Data, no SwiftUI, and no business logic.
public struct BackendSessionViewModel: Identifiable {
    // MARK: - Display-ready properties
    public let id: UUID
    public let createdAtRaw: String?
    public let activityLabel: String
    public let instrumentLabel: String?
    public let notes: String?
    // Attachments are not defined in the given context; expose an empty collection for now to satisfy API.
    // Replace BackendAttachment with your concrete type if/when available.
    public let attachmentURLs: [URL]
    public let ownerUserID: String
    public let isMine: Bool

    // MARK: - Init
    // Initializes from BackendPost, with trivial mapping and minimal formatting.
    // - Parameters:
    //   - post: Source backend post.
    //   - currentUserID: The current user id used to compute ownership.
    public init(post: BackendPost, currentUserID: String?) {
        self.id = post.id
        self.createdAtRaw = post.createdAt

        // Map from backend if such a field exists; neutral fallback otherwise.
        // BackendPost currently does not expose activity fields; use a neutral placeholder.
        self.activityLabel = "—" // em dash as neutral fallback
        self.instrumentLabel = nil
        self.notes = nil
        self.attachmentURLs = []

        self.ownerUserID = post.ownerUserID ?? ""
        self.isMine = (post.ownerUserID ?? "") == (currentUserID ?? "")
    }
}
