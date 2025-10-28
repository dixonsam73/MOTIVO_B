import Foundation
import Combine

/// A simple, local-only comments store that persists to UserDefaults as a JSON blob.
@MainActor
public final class CommentsStore: ObservableObject {
    public static let shared = CommentsStore()

    @Published private(set) var commentsBySessionID: [UUID: [Comment]] = [:]

    private let defaultsKey = "commentsStore_v1"

    // JSON encoder/decoder configured for ISO8601 dates and stable output
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public init() {
        load()
    }

    // MARK: - Public API

    /// Returns comments for a given session, sorted newest → oldest by timestamp.
    public func comments(for sessionID: UUID) -> [Comment] {
        let comments = commentsBySessionID[sessionID] ?? []
        return comments.sorted { $0.timestamp > $1.timestamp }
    }

    /// Appends a new comment and saves to persistence.
    public func add(sessionID: UUID, authorName: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = commentsBySessionID[sessionID] ?? []
        let comment = Comment.new(sessionID: sessionID, authorName: authorName, text: trimmed)
        list.append(comment)
        // Maintain reverse-chronological order
        list.sort { $0.timestamp > $1.timestamp }
        commentsBySessionID[sessionID] = list
        save()
    }

    /// Deletes a comment by id within a session and saves.
    public func delete(commentID: UUID, in sessionID: UUID) {
        guard var list = commentsBySessionID[sessionID] else { return }
        list.removeAll { $0.id == commentID }
        // Keep normalized order
        list.sort { $0.timestamp > $1.timestamp }
        commentsBySessionID[sessionID] = list
        save()
    }

    /// Developer aid to clear all comments. Not called anywhere by default.
    public func clearAll() {
        commentsBySessionID = [:]
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try Self.makeEncoder().encode(commentsBySessionID)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            // Intentionally silent to remain release-safe; consider logging if you have a logging facility.
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            commentsBySessionID = [:]
            return
        }
        do {
            let decoded = try Self.makeDecoder().decode([UUID: [Comment]].self, from: data)
            // Normalize ordering to newest → oldest per session
            var normalized: [UUID: [Comment]] = [:]
            for (key, list) in decoded {
                normalized[key] = list.sorted { $0.timestamp > $1.timestamp }
            }
            commentsBySessionID = normalized
        } catch {
            commentsBySessionID = [:]
        }
    }
}
