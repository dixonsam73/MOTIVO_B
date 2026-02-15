//  UnreadCommentsStore.swift
//  MOTIVO
//  CHANGE-ID: 20260215_150700_UnreadComments_ResponsesList_ActorFix
//  SCOPE: Fix actor isolation compile error by marking parseSupabaseTimestamp as nonisolated; no behavior/UI changes.
//  SEARCH-TOKEN: 20260215_150700_UnreadComments_ResponsesList_ActorFix
//

import Foundation
import SwiftUI


public struct UnreadCommentGroup: Identifiable, Equatable, Decodable {
    public var id: UUID { postID }

    public let postID: UUID
    public let latestUnreadAt: Date
    public let unreadRows: Int

    public let latestAuthorUserID: UUID?
    public let latestBody: String?

    private enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case latestUnreadAt = "latest_unread_at"
        case unreadRows = "unread_rows"
        case latestAuthorUserID = "latest_author_user_id"
        case latestBody = "latest_body"
    }

    public init(postID: UUID,
                latestUnreadAt: Date,
                unreadRows: Int,
                latestAuthorUserID: UUID?,
                latestBody: String?) {
        self.postID = postID
        self.latestUnreadAt = latestUnreadAt
        self.unreadRows = unreadRows
        self.latestAuthorUserID = latestAuthorUserID
        self.latestBody = latestBody
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        postID = try c.decode(UUID.self, forKey: .postID)

        // Supabase/PostgREST typically returns RFC3339/ISO8601 strings; SQL editor can show space-separated.
        let dateString = try c.decode(String.self, forKey: .latestUnreadAt)
        guard let parsed = UnreadCommentsStore.parseSupabaseTimestamp(dateString) else {
            throw DecodingError.dataCorruptedError(forKey: .latestUnreadAt, in: c, debugDescription: "Unparseable timestamp: \(dateString)")
        }
        latestUnreadAt = parsed

        // unread_rows is bigint on the wire
        if let i = try? c.decode(Int.self, forKey: .unreadRows) {
            unreadRows = i
        } else {
            let i64 = try c.decode(Int64.self, forKey: .unreadRows)
            unreadRows = Int(i64)
        }

        latestAuthorUserID = try? c.decode(UUID.self, forKey: .latestAuthorUserID)
        latestBody = try? c.decode(String.self, forKey: .latestBody)
    }
}

@MainActor
public final class UnreadCommentsStore: ObservableObject {


    public static let shared = UnreadCommentsStore()

    @Published public private(set) var hasUnread: Bool = false

    @Published public private(set) var unreadGroups: [UnreadCommentGroup] = []

    private let ttlSeconds: TimeInterval = 60
    private var lastFetchAt: Date? = nil
    private var inFlight: Bool = false

    private init() {}

    /// Refresh global unread presence for the current authenticated user.
    /// - Parameter force: when true, bypasses TTL.
        /// Refresh unread comment groups (for People → Responses) and global unread presence (for People “+”).
    /// - Parameter force: when true, bypasses TTL.
    public func refresh(force: Bool = false) async {
        if inFlight { return }

        if !force, let last = lastFetchAt, Date().timeIntervalSince(last) < ttlSeconds {
            return
        }

        inFlight = true
        defer { inFlight = false }

        // 1) List RPC (authoritative for unreadGroups; drives hasUnread when it succeeds)
        let listPath = "rest/v1/rpc/get_unread_private_comment_groups"
        let listPayload: [String: Any] = [
            "limit_count": 20
        ]

        if let listBody = try? JSONSerialization.data(withJSONObject: listPayload, options: []) {
            let listResult = await NetworkManager.shared.request(
                path: listPath,
                method: "POST",
                query: nil,
                jsonBody: listBody,
                headers: [:]
            )

            switch listResult {
            case .success(let data):
#if DEBUG
                let raw = String(data: data, encoding: .utf8) ?? "(non-utf8 \(data.count) bytes)"
                print("[UnreadCommentsStore][DEBUG] rpc get_unread_private_comment_groups raw=\(raw)")
#endif
                let decoder = JSONDecoder()
                // latest_unread_at is decoded manually in UnreadCommentGroup.init(from:).
                if let rows = try? decoder.decode([UnreadCommentGroup].self, from: data) {
                    let sorted = rows.sorted(by: { $0.latestUnreadAt > $1.latestUnreadAt })
                    unreadGroups = sorted
                    hasUnread = !sorted.isEmpty
                    lastFetchAt = Date()
                    return
                } else {
#if DEBUG
                    print("[UnreadCommentsStore][DEBUG] decode get_unread_private_comment_groups FAILED (shape mismatch)")
#endif
                    // Fall through to boolean presence as a conservative backup.
                }

            case .failure(let error):
#if DEBUG
                print("[UnreadCommentsStore][DEBUG] rpc get_unread_private_comment_groups FAILED error=\(String(describing: error))")
#endif
                // Fall through to boolean presence.
            }
        }

        // 2) Boolean RPC backup (maintains existing GREEN People “+” behavior)
        let presencePath = "rest/v1/rpc/has_unread_private_comments"
        let presenceBody = Data("{}".utf8)

        let presenceResult = await NetworkManager.shared.request(
            path: presencePath,
            method: "POST",
            query: nil,
            jsonBody: presenceBody,
            headers: [:]
        )

        switch presenceResult {
        case .success(let data):
#if DEBUG
            let raw = String(data: data, encoding: .utf8) ?? "(non-utf8 \(data.count) bytes)"
            print("[UnreadCommentsStore][DEBUG] rpc has_unread_private_comments raw=\(raw)")
#endif
            let parsed = Self.parseBooleanRPCResponse(data: data, key: "has_unread_private_comments")
#if DEBUG
            print("[UnreadCommentsStore][DEBUG] rpc has_unread_private_comments parsed=\(String(describing: parsed))")
#endif
            if let v = parsed {
                hasUnread = v
                if v == false {
                    unreadGroups = []
                }
                lastFetchAt = Date()
            } else {
                hasUnread = false
                unreadGroups = []
                lastFetchAt = Date()
            }

        case .failure(let error):
#if DEBUG
            print("[UnreadCommentsStore][DEBUG] rpc has_unread_private_comments FAILED error=\(String(describing: error))")
#endif
            hasUnread = false
            unreadGroups = []
            lastFetchAt = Date()
        }
    }

    /// Mark a post's comments as viewed for the current authenticated user, then refresh unread presence. for the current authenticated user, then refresh unread presence.
    public func markViewed(postID: UUID) async {
        let path = "rest/v1/rpc/mark_post_comments_viewed"

        let payload: [String: Any] = [
            "p_post_id": postID.uuidString.lowercased()
        ]

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
#if DEBUG
            print("[UnreadCommentsStore][DEBUG] markViewed encode FAILED error=\(String(describing: error))")
#endif
            return
        }

        let result = await NetworkManager.shared.request(
            path: path,
            method: "POST",
            query: nil,
            jsonBody: body,
            headers: [:]
        )

        switch result {
        case .success(let data):
#if DEBUG
            let raw = String(data: data, encoding: .utf8) ?? "(non-utf8 \(data.count) bytes)"
            print("[UnreadCommentsStore][DEBUG] rpc mark_post_comments_viewed ok raw=\(raw)")
#endif
            // After marking viewed, force refresh.
            await refresh(force: true)

        case .failure(let error):
#if DEBUG
            print("[UnreadCommentsStore][DEBUG] rpc mark_post_comments_viewed FAILED error=\(String(describing: error))")
#endif
        }
    }

    // MARK: - Parsing


/// Parses Supabase/PostgREST timestamps, tolerating both RFC3339 and space-separated SQL editor formats.
fileprivate nonisolated static func parseSupabaseTimestamp(_ s: String) -> Date? {
    // RFC3339 / ISO8601 (with and without fractional seconds)
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: s) { return d }

    let isoNoFrac = ISO8601DateFormatter()
    isoNoFrac.formatOptions = [.withInternetDateTime]
    if let d = isoNoFrac.date(from: s) { return d }

    // SQL editor often displays: "2026-02-15 14:23:38.898004+00"
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone(secondsFromGMT: 0)

    // With microseconds + numeric TZ
    df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX"
    if let d = df.date(from: s) { return d }

    // With milliseconds + numeric TZ
    df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSXXXXX"
    if let d = df.date(from: s) { return d }

    // Without fractional seconds + numeric TZ
    df.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"
    if let d = df.date(from: s) { return d }

    return nil
}

    /// Parses PostgREST RPC responses that may be:
    /// - a top-level JSON boolean: `true`
    /// - an object: `{"has_unread_private_comments": true}`
    /// - an array with first object: `[{"has_unread_private_comments": true}]`
    private static func parseBooleanRPCResponse(data: Data, key: String) -> Bool? {
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])

            if let b = obj as? Bool { return b }

            if let dict = obj as? [String: Any] {
                if let b = dict[key] as? Bool { return b }
                if let b = dict["result"] as? Bool { return b }
            }

            if let arr = obj as? [Any], let first = arr.first {
                if let b = first as? Bool { return b }
                if let dict = first as? [String: Any] {
                    if let b = dict[key] as? Bool { return b }
                    if let b = dict["result"] as? Bool { return b }
                }
            }

            return nil
        } catch {
            return nil
        }
    }
}
