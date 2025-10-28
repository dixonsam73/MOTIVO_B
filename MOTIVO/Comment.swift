import Foundation

/// A lightweight, local-only comment model.
/// UI-agnostic and easily swappable for a backend later.
public struct Comment: Identifiable, Codable, Equatable {
    public let id: UUID
    public let sessionID: UUID
    public var authorName: String
    public var text: String
    public var timestamp: Date

    public init(id: UUID, sessionID: UUID, authorName: String, text: String, timestamp: Date) {
        self.id = id
        self.sessionID = sessionID
        self.authorName = authorName
        self.text = text
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case authorName
        case text
        case timestamp
    }
}

public extension Comment {
    /// Factory for a new comment, injecting `now` for testability.
    static func new(sessionID: UUID, authorName: String, text: String, now: () -> Date = Date.init) -> Comment {
        Comment(
            id: UUID(),
            sessionID: sessionID,
            authorName: authorName,
            text: text,
            timestamp: now()
        )
    }
}
