// CHANGE-ID: v8H-C-PrivateOwnerReplies-20260109_215052
// SCOPE: Step 8H-C (Model 1) — private owner replies via recipient mapping (local-only; no counts; owner↔commenter isolation)
import Foundation
import Combine

/// A simple, local-only comments store that persists to disk as JSON.
/// Step 8H-B: comments are private (visible only to owner + commenter). No public thread.
/// Step 8H-C: owner replies are privately targeted to a single recipient (no broadcast).
@MainActor
public final class CommentsStore: ObservableObject {
    public static let shared = CommentsStore()

    @Published private(set) var commentsBySessionID: [UUID: [Comment]] = [:]

    /// Maps a comment id → author user id (string). Used for privacy gating without changing Comment shape.
    @Published private(set) var authorByCommentID: [UUID: String] = [:]

    /// Maps a comment id → recipient user id (string). Used for private owner replies (8H-C) without changing Comment shape.
    /// Semantics: recipientUserID == nil means "owner-only" when author is owner (no broadcast).
    @Published private(set) var recipientByCommentID: [UUID: String] = [:]

    private let defaultsKey = "commentsStore_v1"

    // MARK: - Persistence payload

    private struct PersistedV3: Codable {
        var commentsBySessionID: [UUID: [Comment]]
        var authorByCommentID: [UUID: String]
        var recipientByCommentID: [UUID: String]
    }

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

    private static func applicationSupportDirectory() throws -> URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let appSupportURL = urls.first else {
            throw NSError(domain: "CommentsStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to locate Application Support directory"])
        }
        // Ensure directory exists
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        return appSupportURL
    }

    private static var fileURL: URL {
        (try? applicationSupportDirectory().appendingPathComponent("CommentsStore.json")) ?? URL(fileURLWithPath: "/dev/null")
    }

    public init() {
        LegacyDefaultsPurge.runOnce()
        load()
    }

    // MARK: - Public API

    /// Returns comments for a given session, sorted newest → oldest by timestamp (UNGATED).
    /// Prefer `visibleComments(for:viewerUserID:ownerUserID:)` for UI surfaces.
    public func comments(for sessionID: UUID) -> [Comment] {
        let comments = commentsBySessionID[sessionID] ?? []
        return comments.sorted { $0.timestamp > $1.timestamp }
    }

    /// Returns comments visible to `viewerUserID` for this session.
    /// Rule (8H-C):
    /// - Owner sees all.
    /// - Non-owner sees:
    ///   - comments they authored
    ///   - owner-authored comments where recipientUserID == viewer
    /// Note: owner-authored with recipientUserID == nil is treated as owner-only (no broadcast).
    public func visibleComments(for sessionID: UUID, viewerUserID: String?, ownerUserID: String?) -> [Comment] {
        let all = comments(for: sessionID)

        let viewer = (viewerUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = (ownerUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // If we can't determine identities, fail closed (show nothing).
        guard !viewer.isEmpty, !owner.isEmpty else { return [] }

        if viewer == owner {
            return all
        }

        return all.filter { c in
            guard let author = authorByCommentID[c.id], !author.isEmpty else {
                // Legacy/unknown author: hide from non-owner to preserve privacy.
                return false
            }

            // Viewer can always see their own authored comments.
            if author == viewer { return true }

            // Viewer can see owner-authored replies only when explicitly targeted to this viewer.
            if author == owner {
                let recipient = recipientByCommentID[c.id]
                return recipient == viewer
            }

            // No one else’s comments are visible.
            return false
        }
    }

    public func visibleCommentsCount(for sessionID: UUID, viewerUserID: String?, ownerUserID: String?) -> Int {
        visibleComments(for: sessionID, viewerUserID: viewerUserID, ownerUserID: ownerUserID).count
    }

    public func authorUserID(for commentID: UUID) -> String? {
        authorByCommentID[commentID]
    }

    public func canDelete(commentID: UUID, viewerUserID: String?, ownerUserID: String?) -> Bool {
        let viewer = (viewerUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = (ownerUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !viewer.isEmpty, !owner.isEmpty else { return false }

        if viewer == owner { return true }
        return authorByCommentID[commentID] == viewer
    }

    /// Appends a new comment and saves.
    /// Step 8H-B/C: pass `authorUserID` so visibility can be gated.
    /// Step 8H-C: optionally pass `recipientUserID` to target private delivery.
    public func add(sessionID: UUID, authorUserID: String?, authorName: String, text: String) {
        add(sessionID: sessionID, authorUserID: authorUserID, authorName: authorName, text: text, recipientUserID: nil)
    }

    /// Step 8H-C overload: targeted delivery via recipient user id.
    /// Semantics:
    /// - If author == owner and recipientUserID == nil → owner-only (no broadcast)
    /// - If author != owner, recipientUserID may still be stored (symmetry), but visibility already allows author’s own comments.
    public func add(sessionID: UUID, authorUserID: String?, authorName: String, text: String, recipientUserID: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var list = commentsBySessionID[sessionID] ?? []
        let comment = Comment.new(sessionID: sessionID, authorName: authorName, text: trimmed)
        list.append(comment)

        // Store author mapping when available (required for privacy gating).
        let author = (authorUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !author.isEmpty {
            authorByCommentID[comment.id] = author
        }

        // Store recipient mapping when provided (used for owner→commenter private replies).
        let recipient = (recipientUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !recipient.isEmpty {
            recipientByCommentID[comment.id] = recipient
        } else {
            // Ensure no stale recipient mapping for this comment
            recipientByCommentID.removeValue(forKey: comment.id)
        }

        // Maintain reverse-chronological order
        list.sort { $0.timestamp > $1.timestamp }
        commentsBySessionID[sessionID] = list
        save()
    }

    /// Back-compat API (legacy call sites). Adds without author mapping (will be owner-only visible to non-owners).
    public func add(sessionID: UUID, authorName: String, text: String) {
        add(sessionID: sessionID, authorUserID: nil, authorName: authorName, text: text)
    }

    /// Deletes a comment by id within a session and saves.
    public func delete(commentID: UUID, in sessionID: UUID) {
        guard var list = commentsBySessionID[sessionID] else { return }
        list.removeAll { $0.id == commentID }
        commentsBySessionID[sessionID] = list.sorted { $0.timestamp > $1.timestamp }

        authorByCommentID.removeValue(forKey: commentID)
        recipientByCommentID.removeValue(forKey: commentID)
        save()
    }

    /// Developer aid to clear all comments. Not called anywhere by default.
    public func clearAll() {
        commentsBySessionID = [:]
        authorByCommentID = [:]
        recipientByCommentID = [:]
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let payload = PersistedV3(
                commentsBySessionID: commentsBySessionID,
                authorByCommentID: authorByCommentID,
                recipientByCommentID: recipientByCommentID
            )
            let data = try Self.makeEncoder().encode(payload)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            // Intentionally silent to remain release-safe; consider logging if you have a logging facility.
        }
    }

    private func load() {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: Self.fileURL.path) {
            do {
                let data = try Data(contentsOf: Self.fileURL)

                // Try v3 first
                if let decodedV3 = try? Self.makeDecoder().decode(PersistedV3.self, from: data) {
                    var normalized: [UUID: [Comment]] = [:]
                    for (key, list) in decodedV3.commentsBySessionID {
                        normalized[key] = list.sorted { $0.timestamp > $1.timestamp }
                    }
                    commentsBySessionID = normalized
                    authorByCommentID = decodedV3.authorByCommentID
                    recipientByCommentID = decodedV3.recipientByCommentID
                    return
                }

                // Legacy v1: only commentsBySessionID
                let decodedV1 = try Self.makeDecoder().decode([UUID: [Comment]].self, from: data)
                var normalized: [UUID: [Comment]] = [:]
                for (key, list) in decodedV1 {
                    normalized[key] = list.sorted { $0.timestamp > $1.timestamp }
                }
                commentsBySessionID = normalized
                authorByCommentID = [:]
                recipientByCommentID = [:]
                // Upgrade on disk
                save()
                return
            } catch {
                commentsBySessionID = [:]
                authorByCommentID = [:]
                recipientByCommentID = [:]
                return
            }
        } else if let legacyData = UserDefaults.standard.data(forKey: defaultsKey) {
            do {
                let decoded = try Self.makeDecoder().decode([UUID: [Comment]].self, from: legacyData)
                var normalized: [UUID: [Comment]] = [:]
                for (key, list) in decoded {
                    normalized[key] = list.sorted { $0.timestamp > $1.timestamp }
                }
                commentsBySessionID = normalized
                authorByCommentID = [:]
                recipientByCommentID = [:]
                save()
                UserDefaults.standard.removeObject(forKey: defaultsKey)
                return
            } catch {
                commentsBySessionID = [:]
                authorByCommentID = [:]
                recipientByCommentID = [:]
                return
            }
        } else {
            commentsBySessionID = [:]
            authorByCommentID = [:]
            recipientByCommentID = [:]
        }
    }
}
