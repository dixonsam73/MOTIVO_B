//  UnreadCommentsStore.swift
//  MOTIVO
//  CHANGE-ID: 20260215_120500_UnreadComments_PeoplePlus_ParseFix
//  SCOPE: Fix RPC boolean parsing for has_unread_private_comments (PostgREST returns top-level JSON boolean); keep viewer-local unread presence store + mark viewed RPC; DEBUG logs; no UI changes.
//  SEARCH-TOKEN: 20260215_120500_UnreadComments_PeoplePlus_ParseFix
//

import Foundation
import SwiftUI

@MainActor
public final class UnreadCommentsStore: ObservableObject {

    public static let shared = UnreadCommentsStore()

    @Published public private(set) var hasUnread: Bool = false

    private let ttlSeconds: TimeInterval = 60
    private var lastFetchAt: Date? = nil
    private var inFlight: Bool = false

    private init() {}

    /// Refresh global unread presence for the current authenticated user.
    /// - Parameter force: when true, bypasses TTL.
    public func refresh(force: Bool = false) async {
        if inFlight { return }

        if !force, let last = lastFetchAt, Date().timeIntervalSince(last) < ttlSeconds {
            return
        }

        inFlight = true
        defer { inFlight = false }

        let path = "rest/v1/rpc/has_unread_private_comments"

        // PostgREST RPC accepts POST with empty JSON object for a no-args function.
        let body = Data("{}".utf8)

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
            print("[UnreadCommentsStore][DEBUG] rpc has_unread_private_comments raw=\(raw)")
#endif
            let parsed = Self.parseBooleanRPCResponse(data: data, key: "has_unread_private_comments")
#if DEBUG
            print("[UnreadCommentsStore][DEBUG] rpc has_unread_private_comments parsed=\(String(describing: parsed))")
#endif
            if let v = parsed {
                hasUnread = v
                lastFetchAt = Date()
            } else {
                // Fail-closed: do not assert unread when we cannot parse.
                hasUnread = false
                lastFetchAt = Date()
            }

        case .failure(let error):
#if DEBUG
            print("[UnreadCommentsStore][DEBUG] rpc has_unread_private_comments FAILED error=\(String(describing: error))")
#endif
            // Fail-closed.
            hasUnread = false
            lastFetchAt = Date()
        }
    }

    /// Mark a post's comments as viewed for the current authenticated user, then refresh unread presence.
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
