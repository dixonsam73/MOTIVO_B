// CHANGE-ID: v8H-B-PrivateComments-20260109_180000
// SCOPE: Step 8H-B — private comments semantics (local-only; no counts; owner↔commenter visibility)
import Foundation
import Combine

/// A simple, local-only comments store that persists to disk as JSON.
/// Step 8H-B: comments are private (visible only to owner + commenter). No public thread.
@MainActor
public final class CommentsStore: ObservableObject {
    public static let shared = CommentsStore()

    @Published private(set) var commentsBySessionID: [UUID: [Comment]] = [:]

    /// Maps a comment id → author user id (string). Used for privacy gating without changing Comment shape.
    @Published private(set) var authorByCommentID: [UUID: String] = [:]

    private let defaultsKey = "commentsStore_v1"

    // MARK: - Persistence payload

    private struct PersistedV2: Codable {
        var commentsBySessionID: [UUID: [Comment]]
        var authorByCommentID: [UUID: String]
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
    /// Rule (8H-B): owner sees all. Non-owner sees only their own authored comments.
    public func visibleComments(for sessionID: UUID, viewerUserID: String?, ownerUserID: String?) -> [Comment] {
        let all = comments(for: sessionID)

        let viewer = (viewerUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = (ownerUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // If we can't determine identities, fail closed (show nothing).
        guard !viewer.isEmpty, !owner.isEmpty else { return [] }

        if viewer == owner {
            return all
        }

        // Non-owner: only show comments authored by this viewer.
        return all.filter { c in
            guard let author = authorByCommentID[c.id], !author.isEmpty else {
                // Legacy/unknown author: hide from non-owner to preserve privacy.
                return false
            }
            return author == viewer
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
    /// Step 8H-B: pass `authorUserID` so visibility can be gated.
    public func add(sessionID: UUID, authorUserID: String?, authorName: String, text: String) {
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

        // Maintain reverse-chronological order
        list.sort { $0.timestamp > $1.timestamp }
        commentsBySessionID[sessionID] = list
        save()
    }

    /// Back-compat API (legacy call sites). Adds without author mapping (will be owner-only visible).
    public func add(sessionID: UUID, authorName: String, text: String) {
        add(sessionID: sessionID, authorUserID: nil, authorName: authorName, text: text)
    }

    /// Deletes a comment by id within a session and saves.
    public func delete(commentID: UUID, in sessionID: UUID) {
        guard var list = commentsBySessionID[sessionID] else { return }
        list.removeAll { $0.id == commentID }
        commentsBySessionID[sessionID] = list.sorted { $0.timestamp > $1.timestamp }

        authorByCommentID.removeValue(forKey: commentID)
        save()
    }

    /// Developer aid to clear all comments. Not called anywhere by default.
    public func clearAll() {
        commentsBySessionID = [:]
        authorByCommentID = [:]
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let payload = PersistedV2(commentsBySessionID: commentsBySessionID, authorByCommentID: authorByCommentID)
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

                // Try v2 first
                if let decodedV2 = try? Self.makeDecoder().decode(PersistedV2.self, from: data) {
                    var normalized: [UUID: [Comment]] = [:]
                    for (key, list) in decodedV2.commentsBySessionID {
                        normalized[key] = list.sorted { $0.timestamp > $1.timestamp }
                    }
                    commentsBySessionID = normalized
                    authorByCommentID = decodedV2.authorByCommentID
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
                // Upgrade on disk
                save()
                return
            } catch {
                commentsBySessionID = [:]
                authorByCommentID = [:]
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
                save()
                UserDefaults.standard.removeObject(forKey: defaultsKey)
                return
            } catch {
                commentsBySessionID = [:]
                authorByCommentID = [:]
                return
            }
        } else {
            commentsBySessionID = [:]
            authorByCommentID = [:]
        }
    }
}
