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

import Foundation

public struct DirectoryAccount: Codable, Identifiable, Hashable {
    public var id: String { userID }

    public let userID: String
    public let accountID: String?
    public let displayName: String

    public enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case accountID = "account_id"
        case displayName = "display_name"
    }
}

public final class AccountDirectoryService {
    // Phase 12C hygiene: never POST invalid account_id values.
    // Rule: accept only [a-z0-9_] and length 3–24; otherwise send null.
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
    public func resolveAccounts(userIDs: [String]) async -> Result<[String: DirectoryAccount], Error> {
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
        let missing = orderedUnique.filter { cached[$0] == nil }

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
    public func upsertSelfRow(userID: String, displayName: String, accountID: String?, lookupEnabled: Bool) async -> Result<Void, Error> {
        let payload: [String: Any] = [
            "user_id": userID,
            "display_name": displayName,
            "account_id": sanitizedAccountID(accountID) ?? NSNull(),
            "lookup_enabled": lookupEnabled
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
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

}
