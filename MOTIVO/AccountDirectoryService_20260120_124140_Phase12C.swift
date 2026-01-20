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
