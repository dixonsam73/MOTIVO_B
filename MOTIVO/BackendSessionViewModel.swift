import Foundation

// A lightweight, read-only adapter that maps a BackendPost into a UI-friendly “session-like” shape.
// This type contains no Core Data, no SwiftUI, and no business logic.
public struct BackendSessionViewModel: Identifiable {
    // MARK: - Display-ready properties
    public let id: UUID

    // Timestamps (raw strings from backend; parsing/formatting can be layered later)
    public let sessionTimestampRaw: String?
    public let createdAtRaw: String?
    public let updatedAtRaw: String?

    // Metadata parity (Step 8F)
    public let activityLabel: String
    public let instrumentLabel: String?

    // Optional content
    public let notes: String?

    // Attachments are out of scope for 8F; keep empty to satisfy downstream UI plumbing.
    public let attachmentURLs: [URL]

    // Ownership
    public let ownerUserID: String
    public let isMine: Bool

    public init(post: BackendPost, currentUserID: String?) {
        self.id = post.id

        self.sessionTimestampRaw = post.sessionTimestamp
        self.createdAtRaw = post.createdAt
        self.updatedAtRaw = post.updatedAt

        // Step 8F: map backend labels (safe if absent)
        let activity = (post.activityLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.activityLabel = activity.isEmpty ? "—" : activity

        let instrument = (post.instrumentLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.instrumentLabel = instrument.isEmpty ? nil : instrument

        self.notes = nil
        self.attachmentURLs = []

        self.ownerUserID = post.ownerUserID ?? ""
        self.isMine = (post.ownerUserID ?? "") == (currentUserID ?? "")
    }
}
