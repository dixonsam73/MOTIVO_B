// CHANGE-ID: 20260209_213700_Phase15_Step1_AvatarKeyPlumb_25a97d6f
// SCOPE: Phase 15 Step 1 — plumb account_directory.avatar_key through DirectoryAccount decode + caches (no UI)
// SEARCH-TOKEN: 20260209_213700_Phase15_Step1_AvatarKeyPlumb_25a97d6f

// CHANGE-ID: 20260205_072955_LiveIdentityCache_f1a8c7
// SCOPE: Live directory identity cache updates (merge on upsert + force-refresh on directory fetch)
// SEARCH-TOKEN: 20260205_072955_LiveIdentityCache_f1a8c7

// CHANGE-ID: 20260121_172500_Phase14_Step2_DirectoryBatchCache
// SCOPE: Phase 14 Step 2 — add batch account_directory RPC lookup + in-memory cache for DirectoryAccount (user_id, display_name, account_id)
// SEARCH-TOKEN: 20260121_172500_Phase14_Step2_DirectoryBatchCache

// CHANGE-ID: 20260120_133525_Phase12C_Hygiene
// SCOPE: Phase 12C hygiene — sanitize account_id; fix upsert request call
// CHANGE-ID: 20260120_124800_Phase12C_AccountDirectoryService_ReadWrite
// SCOPE: Phase 12C — RPC-backed People search + owner-only upsert of account_directory row (lookup opt-in + account_id + display_name). No profile sync.
// SEARCH-TOKEN: 20260120_124800_Phase12C_AccountDirectoryService_ReadWrite

//
//  AccountDirectoryService.swift
//  MOTIVO
//
//  CHANGE-ID: 20260120_113000_Phase12C_AccountDirectorySearch
//  SCOPE: Phase 12C (read path) — RPC-backed People search against account_directory via search_account_directory(); no profile sync; no discovery.
//  SEARCH-TOKEN: 20260120_113000_Phase12C_AccountDirectorySearch
//

// CHANGE-ID: 20260210_182200_Phase15_Step3A_AvatarKeyWrite
// SCOPE: Phase 15 Step 3A — add owner-only PATCH helper to update/clear account_directory.avatar_key and merge into live identity caches.
// SEARCH-TOKEN: 20260210_182200_Phase15_Step3A_AvatarKeyWrite

import Foundation

public struct DirectoryAccount: Codable, Identifiable, Hashable {
    public var id: String { userID }

    public let userID: String
    public let accountID: String?
    public let displayName: String
    public let location: String?
    public let avatarKey: String?

    public enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case accountID = "account_id"
        case displayName = "display_name"
        case location = "location"
        case avatarKey = "avatar_key"
    }
}

public final class AccountDirectoryService {
    // Phase 12C hygiene: never POST invalid account_id values.
    // Rule: accept only [a-z0-9_] and length 3–24; otherwise send null.
    private func sanitizedLocation(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    private func sanitizedAccountID(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !s.isEmpty else { return nil }
        if s.hasPrefix("@") { s = String(s.dropFirst()) }
        let filtered = s.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
        guard filtered.count >= 3, filtered.count <= 24 else { return nil }
        return String(filtered)
    }

    public static let shared = AccountDirectoryService()
    private init() {}

    // Phase 14 Step 2 — batch directory lookup cache (viewer-local, in-memory only).
    // Note: This cache is intentionally ephemeral (clears on cold start).
    private actor DirectoryAccountCache {
        private var store: [String: DirectoryAccount] = [:]

        func getMany(_ userIDs: [String]) -> [String: DirectoryAccount] {
            var out: [String: DirectoryAccount] = [:]
            for id in userIDs {
                if let v = store[id] { out[id] = v }
            }
            return out
        }

        func setMany(_ accounts: [DirectoryAccount]) {
            for a in accounts {
                store[a.userID] = a
            }
        }
    }

    private let cache = DirectoryAccountCache()

    /// Resolve directory identity for a set of backend user IDs via SECURITY DEFINER RPC.
    /// - Returns: Map keyed by user_id (string UUID) for fast lookup in feed/profile-peek.
    /// - Important: This read path does NOT apply lookup_enabled filtering (People search only).
    public func resolveAccounts(userIDs: [String], forceRefresh: Bool = false) async -> Result<[String: DirectoryAccount], Error> {
        let trimmed = userIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmed.isEmpty else {
            return .success([:])
        }

        // Preserve first-seen order while de-duping.
        var orderedUnique: [String] = []
        var seen: Set<String> = []
        for id in trimmed {
            if !seen.contains(id) {
                seen.insert(id)
                orderedUnique.append(id)
            }
        }

        let cached = await cache.getMany(orderedUnique)
        let missing = forceRefresh ? orderedUnique : orderedUnique.filter { cached[$0] == nil }

        var merged = cached

        if !missing.isEmpty {
            let payload: [String: Any] = ["user_ids": missing]

            let body: Data
            do {
                body = try JSONSerialization.data(withJSONObject: payload, options: [])
            } catch {
                return .failure(error)
            }

            let path = "rest/v1/rpc/get_account_directory_by_user_ids"
            let result = await NetworkManager.shared.request(path: path, method: "POST", query: nil, jsonBody: body)

            switch result {
            case .success(let data):
                do {
                    let rows = try JSONDecoder().decode([DirectoryAccount].self, from: data)
                    await cache.setMany(rows)
                    for r in rows {
                        merged[r.userID] = r
                    }
                } catch {
                    return .failure(error)
                }

            case .failure(let error):
                return .failure(error)
            }
        }

        return .success(merged)
    }


    /// Search the backend account directory via RPC.
    /// - Important: This is the only non-owner read surface by design.
    public func search(query: String) async -> Result<[DirectoryAccount], Error> {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: [String: Any] = ["q": q]

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            return .failure(error)
        }

        let path = "rest/v1/rpc/search_account_directory"
        let result = await NetworkManager.shared.request(path: path, method: "POST", query: nil, jsonBody: body)

        switch result {
        case .success(let data):
            do {
                let rows = try JSONDecoder().decode([DirectoryAccount].self, from: data)
                return .success(rows)
            } catch {
                return .failure(error)
            }

        case .failure(let error):
            return .failure(error)
        }
    }

    /// Upsert the caller's account_directory row (owner-only via RLS).
    /// - Important: This is the only write surface for Phase 12C.
    public func upsertSelfRow(userID: String, displayName: String, accountID: String?, lookupEnabled: Bool, location: String? = nil) async -> Result<Void, Error> {
        let payload: [String: Any] = [
            "user_id": userID,
            "display_name": displayName,
            "account_id": sanitizedAccountID(accountID) ?? NSNull(),
            "lookup_enabled": lookupEnabled,
            "location": sanitizedLocation(location) ?? NSNull()
        ]

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            return .failure(error)
        }

        // PostgREST upsert: merge on PK/unique constraint.
        let path = "rest/v1/account_directory?on_conflict=user_id"
        let headers = [
            "Prefer": "resolution=merge-duplicates,return=minimal"
        ]

        let result = await NetworkManager.shared.request(path: path, method: "POST", query: nil, jsonBody: body, headers: headers)
        switch result {
        case .success:
            // Live identity cache update: immediately merge the new identity values.
            let existing = await cache.getMany([userID])[userID]
            let merged = DirectoryAccount(userID: userID,
                                        accountID: sanitizedAccountID(accountID),
                                        displayName: displayName,
                                        location: sanitizedLocation(location),
                                        avatarKey: existing?.avatarKey)
            await cache.setMany([merged])
            await BackendFeedStore.shared.mergeDirectoryAccounts([userID: merged])
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }



    // MARK: - Phase 15 Step 3A (Avatars) — update self avatar_key

    /// Update the caller's `account_directory.avatar_key` (owner-only via RLS).
    /// - Parameter avatarKey: `users/<uid>/avatar.jpg` or nil to clear.
    /// - Important: This is an owner-only metadata update; no profile sync.
    public func updateSelfAvatarKey(userID: String, avatarKey: String?) async -> Result<Void, Error> {
        let uid = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else {
            return .failure(NSError(domain: "AccountDirectoryService", code: 1, userInfo: [NSLocalizedDescriptionKey: "empty userID"]))
        }

        let payload: [String: Any] = [
            "avatar_key": avatarKey ?? NSNull()
        ]

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            return .failure(error)
        }

        let path = "rest/v1/account_directory?user_id=eq.\(uid)"
        let headers = [
            "Prefer": "return=minimal"
        ]

        let result = await NetworkManager.shared.request(path: path, method: "PATCH", query: nil, jsonBody: body, headers: headers)
        switch result {
        case .success:
            // Live identity cache update: patch avatar_key in-memory so UI refreshes immediately.
            if let existing = await cache.getMany([uid])[uid] {
                let updated = DirectoryAccount(userID: existing.userID,
                                               accountID: existing.accountID,
                                               displayName: existing.displayName,
                                               location: existing.location,
                                               avatarKey: avatarKey)
                await cache.setMany([updated])
                await BackendFeedStore.shared.mergeDirectoryAccounts([uid: updated])
            }
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

}
