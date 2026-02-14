// CHANGE-ID: 20260214_172200_CommentPresenceStore_ExistenceFetch
// SCOPE: Blocker B Option 2 — viewer-local comment presence cache + lightweight existence fetch (limit=1)
//
// Notes:
// - No schema / RLS / SQL changes.
// - Cache is viewer-local and in-memory (TTL).
// - Hydration is called after feed fetch for top N posts and may be called by detail views later if desired.

import Foundation
import SwiftUI

@MainActor
public final class CommentPresenceStore: ObservableObject {
    public static let shared = CommentPresenceStore()

    public struct Entry: Hashable {
        public let hasComments: Bool
        public let fetchedAt: Date
    }

    @Published private var entries: [UUID: Entry] = [:]
    private var inFlight: Set<UUID> = []

    // Keep short to avoid stale state; long enough to avoid spamming requests on pull-to-refresh.
    public var ttlSeconds: TimeInterval = 20 * 60  // 20 minutes

    private init() {}

    public func hasComments(postID: UUID) -> Bool {
        guard let e = entries[postID] else { return false }
        if Date().timeIntervalSince(e.fetchedAt) > ttlSeconds { return false }
        return e.hasComments
    }

    public func set(postID: UUID, hasComments: Bool, fetchedAt: Date = Date()) {
        entries[postID] = Entry(hasComments: hasComments, fetchedAt: fetchedAt)
    }

    public func invalidate(postID: UUID) {
        entries.removeValue(forKey: postID)
        inFlight.remove(postID)
    }

    /// Prime comment presence for a list of posts (typically the visible/top slice of the feed).
    /// This performs N lightweight "exists" requests using limit=1 and caches the boolean.
    public func primePresence(postIDs: [UUID], maxToCheck: Int = 20, concurrency: Int = 4) async {
        guard maxToCheck > 0 else { return }
        guard concurrency > 0 else { return }

        guard let apiKey = BackendConfig.apiToken, !apiKey.isEmpty else { return }

        // Filter: non-expired entries and in-flight are skipped.
        let now = Date()
        let candidates: [UUID] = postIDs
            .prefix(maxToCheck)
            .filter { id in
                if inFlight.contains(id) { return false }
                if let e = entries[id], now.timeIntervalSince(e.fetchedAt) <= ttlSeconds {
                    return false
                }
                return true
            }

        guard !candidates.isEmpty else { return }

        // Mark in-flight up front to dedupe.
        for id in candidates { inFlight.insert(id) }

        let headers: [String: String] = [
            "apikey": apiKey,
            "Accept": "application/json"
        ]

        // Chunked task groups to cap concurrency.
        var idx = 0
        while idx < candidates.count {
            let chunk = Array(candidates[idx..<min(idx + concurrency, candidates.count)])
            idx += concurrency

            await withTaskGroup(of: (UUID, Bool?).self) { group in
                for postID in chunk {
                    group.addTask {
                        // GET /post_comments?select=id&post_id=eq.<uuid>&limit=1
                        let query: [URLQueryItem] = [
                            URLQueryItem(name: "select", value: "id"),
                            URLQueryItem(name: "post_id", value: "eq.\(postID.uuidString.lowercased())"),
                            URLQueryItem(name: "limit", value: "1")
                        ]

                        let result = await NetworkManager.shared.request(
                            path: "rest/v1/post_comments",
                            method: "GET",
                            query: query,
                            jsonBody: nil,
                            headers: headers
                        )

                        switch result {
                        case .success(let data):
                            // We only care if any row exists.
                            // Decode as array of dictionaries or array of UUID wrappers.
                            do {
                                if let arr = try JSONSerialization.jsonObject(with: data) as? [Any] {
                                    return (postID, !arr.isEmpty)
                                }
                                return (postID, false)
                            } catch {
                                return (postID, nil)
                            }

                        case .failure:
                            return (postID, nil)
                        }
                    }
                }

                for await (postID, has) in group {
                    defer { inFlight.remove(postID) }
                    guard let has else {
                        // On failure: clear inFlight only, do not overwrite cache.
                        continue
                    }
                    self.set(postID: postID, hasComments: has)
                }
            }
        }
    }
}
