// CHANGE-ID: 20260213_210205_ConnectedOfflineResilience_FeedSnapshot
// SCOPE: Connected-mode Offline Resilience — preserve last-known feed snapshot on refresh failure; no UI changes; no backend/schema changes.
// SEARCH-TOKEN: 20260213_210205_FeedSnapshotRetention

// CHANGE-ID: 20260213_074012_ab077a83
// SCOPE: Fix duplicate post_shares insert mapping: return typed .alreadyShared outcome (409/23505) and propagate to UI; no backend/schema changes.
// SEARCH-TOKEN: 20260213_070034_PostShares_DuplicateOutcome

// CHANGE-ID: 20260212_224356_PostShares_AlreadyShared
// SCOPE: Map duplicate post_shares insert (409/23505) to BackendPostShareAlreadySharedError for UI "Already shared." handling.
// SEARCH-TOKEN: 20260212_224356_PostShares_AlreadyShared

// CHANGE-ID: 20260212_083300_PostSharesService_GREEN
// SCOPE: Add post_shares service surface (fetch/insert/mark-viewed/delete) and fix BackendEnvironment.follow/shares property placement.
// SEARCH-TOKEN: 20260212_083300_PostSharesService_GREEN

// CHANGE-ID: 20260206_104437_BackendShim_DisplayNameFromCoreData_972b4909
// SCOPE: Include attachment display_name in backend posts.attachments, preferring Core Data Attachment.title; fall back to persisted per-ID store.
// SEARCH-TOKEN: 20260206_092154_AttachDisplayNames_94a0e8

// CHANGE-ID: 20260205_072955_LiveIdentityCache_f1a8c7
// SCOPE: Live directory identity cache updates (merge on upsert + force-refresh on directory fetch)
// SEARCH-TOKEN: 20260205_072955_LiveIdentityCache_f1a8c7

// CHANGE-ID: 20260203_081447_IdentityHydrationSmoothing
// SCOPE: Non-owner identity hydration smoothing: preserve directory cache during fetch; merge identities before publishing posts

// SEARCH-TOKEN: 20260128_192500_14_3A_MainActorPublishingFix


// SEARCH-TOKEN: 20260121_180200_Phase14_Step3_DirectoryBatchCache
// SEARCH-TOKEN: 20260121_124000_P13F_BackendFollowersFetch

// SEARCH-TOKEN: P13D1-CONNECTED-MODE-20260121_114321

// SEARCH-TOKEN: ACTIVITY-READ-PARITY-20260119

//
// SEARCH-TOKEN: 20260112_141800_Step9B_BackendFollowGraph_Fix1
//
// SEARCH-TOKEN: 20260112_140516_Step9B_BackendFollowGraph
//
// SEARCH-TOKEN: 20260109_121500_Step8G_Phase3_Fix_8G3A
//
// Prior CHANGE-ID retained below for provenance:
// UNIQUE-TOKEN: 20260112_131015_backendshim_id_canon

// SEARCH-TOKEN: ACTIVITY-READ-PARITY-20260119

// SEARCH-TOKEN: 20260122_113000_Phase142_BackendShimIgnoreOverride

// SEARCH-TOKEN: 20260129_090937_14_3H_SignOutFeedReset_SignInReliability

// CHANGE-ID: 20260130_155652_ShareTogglePersist
// SCOPE: BackendShim: ensure idempotent publish updates is_public via PATCH metadata on every uploadPost attempt (including 409 existing-post path).
import Foundation
import CoreData
import SwiftUI

public enum BackendKeys {
    public static let modeKey = "backendMode_v1"
}

@inline(__always)
public func setBackendMode(_ mode: BackendMode) {
    UserDefaults.standard.set(mode.rawValue, forKey: BackendKeys.modeKey)
}

public enum BackendMode: String, CaseIterable, Identifiable {
    case localSimulation
    case backendConnected
    case backendPreview

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .localSimulation: return "Local Simulation"
        case .backendConnected: return "Connected"
        case .backendPreview: return "Backend Preview"
        }
    }
}

public struct BackendPost: Codable, Identifiable, Hashable {
    public let id: UUID
    public let ownerUserID: String?
    public let sessionID: UUID?
    public let sessionTimestamp: String?
    public let durationSeconds: Int?
    public let createdAt: String?
    public let updatedAt: String?
    public let isPublic: Bool?
    public let activityLabel: String?
    public let activityType: String?
    public let activityDetail: String?
    public let instrumentLabel: String?
    public let effort: Int?

    // Step 12 (beta parity): notes
    public let notes: String?

    // Step 8G: attachments (jsonb)
    public let attachments: [[String: String]]?

    public enum CodingKeys: String, CodingKey {
        case id
        case ownerUserID = "owner_user_id"
        case sessionID = "session_id"
        case sessionTimestamp = "session_timestamp"
        case durationSeconds = "duration_seconds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isPublic = "is_public"
        case activityLabel = "activity_label"
        case activityType = "activity_type"
        case activityDetail = "activity_detail"
        case instrumentLabel = "instrument_label"
        case notes = "notes"
        case attachments = "attachments"
        case effort = "effort"
    }
}

@MainActor
public final class BackendFeedStore: ObservableObject {
    public static let shared = BackendFeedStore()

    @Published public private(set) var minePosts: [BackendPost] = []
    @Published public private(set) var allPosts: [BackendPost] = []

    // Phase 14 Step 3: Directory identity cache (viewer-side)
    @Published public private(set) var directoryAccountsByUserID: [String: DirectoryAccount] = [:]

    @Published public private(set) var lastRawCount: Int = 0
    @Published public private(set) var lastMineCount: Int = 0
    @Published public private(set) var lastOwnerKey: String? = nil
    @Published public private(set) var lastOwnerSamples: [String] = []
    @Published public private(set) var lastCreatedAtSamples: [String] = []

    @Published public private(set) var lastScope: String? = nil
    @Published public private(set) var lastAllCount: Int = 0
    @Published public private(set) var lastTargetOwnerCount: Int = 0
    @Published public private(set) var lastTargetOwnerSamples: [String] = []

    @Published public private(set) var isFetching: Bool = false
    @Published public private(set) var lastError: String? = nil
    @Published public private(set) var lastFetchAt: Date? = nil

    private init() {}

    // Phase 14.3H (A): Connected-mode sign-out must clear feed state.
    // This is a pure in-memory reset (no backend calls).
    public func resetForSignOut() {
        // NOTE: Do not clear directoryAccountsByUserID here.
        // Identity cache should survive in-flight refreshes to avoid non-owner name flips.

        lastRawCount = 0
        lastMineCount = 0
        lastOwnerKey = nil
        lastOwnerSamples = []
        lastCreatedAtSamples = []

        lastScope = nil
        lastAllCount = 0
        lastTargetOwnerCount = 0
        lastTargetOwnerSamples = []

        isFetching = false
        lastError = nil
        lastFetchAt = nil
    }


    public func beginFetch(ownerKey: String, scope: String, targetOwners: [String]) {
        isFetching = true
        lastError = nil

        lastOwnerKey = ownerKey
        lastScope = scope

        lastRawCount = 0
        lastMineCount = 0
        lastAllCount = 0

        lastOwnerSamples = []
        lastCreatedAtSamples = []

        lastTargetOwnerCount = targetOwners.count
        lastTargetOwnerSamples = Array(targetOwners.prefix(3))

        // NOTE: Do not clear directoryAccountsByUserID here.
        // Identity cache should survive in-flight refreshes to avoid non-owner name flips.
    }

    public func endFetchSuccess(rawPosts: [BackendPost], minePosts: [BackendPost], allPosts: [BackendPost]) {
        self.lastRawCount = rawPosts.count
        self.lastMineCount = minePosts.count
        self.lastAllCount = allPosts.count

        self.lastOwnerSamples = Array(rawPosts.prefix(3)).map { ($0.ownerUserID ?? "<nil>") }
        self.lastCreatedAtSamples = Array(rawPosts.prefix(3)).map { ($0.createdAt ?? "<nil>") }

        self.minePosts = minePosts
        self.allPosts = allPosts

        self.lastFetchAt = Date()
        self.isFetching = false
        self.lastError = nil
    }

    

    // Phase 14 Step 3: Merge directory accounts into the in-memory cache.
    public func mergeDirectoryAccounts(_ accounts: [String: DirectoryAccount]) {
        guard !accounts.isEmpty else { return }
        var merged = directoryAccountsByUserID
        for (k, v) in accounts { merged[k] = v }
        directoryAccountsByUserID = merged
    }
    public func endFetchFailure(_ error: Error) {
        isFetching = false
        lastError = error.localizedDescription
    }
    }


public protocol BackendPublishService {
    func uploadPost(_ payload: SessionSyncQueue.PostPublishPayload) async -> Result<Void, Error>
    func deletePost(_ postID: UUID) async -> Result<Void, Error>
    func updatePost(_ postID: UUID) async -> Result<Void, Error>
    func fetchFeed(scope: String) async -> Result<Void, Error>
}

public protocol BackendProfileService {}

public protocol BackendFollowService {
    func fetchFollowingApproved() async -> Result<[String], Error>
    func fetchFollowersApproved() async -> Result<[String], Error>
    func fetchIncomingRequests() async -> Result<[String], Error>
    func fetchOutgoingRequests() async -> Result<[String], Error>

    func requestFollow(to targetUserID: String) async -> Result<Void, Error>
    func approveFollow(from requesterUserID: String) async -> Result<Void, Error>
    func declineFollow(from requesterUserID: String) async -> Result<Void, Error>
    func unfollow(_ targetUserID: String) async -> Result<Void, Error>
}

public final class SimulatedPublishService: BackendPublishService {
    public init() {}

    @MainActor
    public func uploadPost(_ payload: SessionSyncQueue.PostPublishPayload) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("PublishService.uploadPost", meta: ["postID": payload.id.uuidString])
        return .success(())
    }

    @MainActor
    public func deletePost(_ postID: UUID) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("PublishService.deletePost", meta: ["postID": postID.uuidString])
        return .success(())
    }

    @MainActor
    public func updatePost(_ postID: UUID) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("PublishService.updatePost", meta: ["postID": postID.uuidString])
        return .success(())
    }

    @MainActor
    public func fetchFeed(scope: String) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("PublishService.fetchFeed", meta: ["scope": scope])
        return .success(())
    }
}

public final class SimulatedProfileService: BackendProfileService { public init() {} }

public final class SimulatedFollowService: BackendFollowService {
    public init() {}

    @MainActor
    public func fetchFollowingApproved() async -> Result<[String], Error> {
        await BackendDiagnostics.shared.simulatedCall("FollowService.fetchFollowingApproved")
        return .success([])
    }

    @MainActor
    public func fetchFollowersApproved() async -> Result<[String], Error> {
        await BackendDiagnostics.shared.simulatedCall("FollowService.fetchFollowersApproved")
        return .success([])
    }

    @MainActor
    public func fetchIncomingRequests() async -> Result<[String], Error> {
        await BackendDiagnostics.shared.simulatedCall("FollowService.fetchIncomingRequests")
        return .success([])
    }

    @MainActor
    public func fetchOutgoingRequests() async -> Result<[String], Error> {
        await BackendDiagnostics.shared.simulatedCall("FollowService.fetchOutgoingRequests")
        return .success([])
    }

    @MainActor
    public func requestFollow(to targetUserID: String) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("FollowService.requestFollow", meta: ["to": targetUserID])
        return .success(())
    }

    @MainActor
    public func approveFollow(from requesterUserID: String) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("FollowService.approveFollow", meta: ["from": requesterUserID])
        return .success(())
    }

    @MainActor
    public func declineFollow(from requesterUserID: String) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("FollowService.declineFollow", meta: ["from": requesterUserID])
        return .success(())
    }

    @MainActor
    public func unfollow(_ targetUserID: String) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("FollowService.unfollow", meta: ["target": targetUserID])
        return .success(())
    }
}




public final class HTTPBackendFollowService: BackendFollowService {
    public init() {}

    private func currentBackendUserID() -> String? {
        #if DEBUG
        if BackendEnvironment.shared.isConnected == false,
           let override = UserDefaults.standard.string(forKey: "Debug.backendUserIDOverride")?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
           !override.isEmpty {
            return override.lowercased()
        }
        #endif

        // Prefer Supabase user ID if present; fall back to legacy backendUserID.
        if let supa = UserDefaults.standard.string(forKey: "supabaseUserID_v1")?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
           !supa.isEmpty {
            return supa.lowercased()
        }
        if let legacy = UserDefaults.standard.string(forKey: "backendUserID_v1")?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
           !legacy.isEmpty {
            return legacy.lowercased()
        }
        return nil
    }

    private func headers(apiKey: String) -> [String: String] {
        [
            "apikey": apiKey,
                        "Prefer": "return=minimal"
        ]
    }

    public func fetchFollowingApproved() async -> Result<[String], Error> {
        guard let apiKey = BackendConfig.apiToken, !apiKey.isEmpty else {
            return .failure(NSError(domain: "Backend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"]))
        }
        guard let me = currentBackendUserID(), !me.isEmpty else {
            return .success([])
        }

        let path = "rest/v1/follows?select=followed_user_id&follower_user_id=eq.\(me)&status=eq.approved"
        let result = await NetworkManager.shared.request(path: path, method: "GET", headers: headers(apiKey: apiKey))

        switch result {
        case .success(let data):
            do {
                let obj = try JSONSerialization.jsonObject(with: data, options: [])
                let rows = obj as? [[String: Any]] ?? []
                let ids = rows.compactMap { ($0["followed_user_id"] as? String)?.lowercased() }
                return .success(ids)
            } catch {
                return .failure(error)
            }

        case .failure(let e):
            return .failure(e)
        }
    }

    
public func fetchFollowersApproved() async -> Result<[String], Error> {
    guard let apiKey = BackendConfig.apiToken, !apiKey.isEmpty else {
        return .failure(NSError(domain: "Backend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"]))
    }
    guard let me = currentBackendUserID(), !me.isEmpty else {
        return .success([])
    }

    let path = "rest/v1/follows?select=follower_user_id&followed_user_id=eq.\(me)&status=eq.approved"
    let result = await NetworkManager.shared.request(path: path, method: "GET", headers: headers(apiKey: apiKey))

    switch result {
    case .success(let data):
        do {
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            let rows = obj as? [[String: Any]] ?? []
            let ids = rows.compactMap { ($0["follower_user_id"] as? String)?.lowercased() }
            return .success(ids)
        } catch {
            return .failure(error)
        }

    case .failure(let e):
        return .failure(e)
    }
}

public func fetchIncomingRequests() async -> Result<[String], Error> {
        guard let apiKey = BackendConfig.apiToken, !apiKey.isEmpty else {
            return .failure(NSError(domain: "Backend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"]))
        }
        guard let me = currentBackendUserID(), !me.isEmpty else {
            return .success([])
        }

        let path = "rest/v1/follows?select=follower_user_id&followed_user_id=eq.\(me)&status=eq.requested"
        let result = await NetworkManager.shared.request(path: path, method: "GET", headers: headers(apiKey: apiKey))

        switch result {
        case .success(let data):
            do {
                let obj = try JSONSerialization.jsonObject(with: data, options: [])
                let rows = obj as? [[String: Any]] ?? []
                let ids = rows.compactMap { ($0["follower_user_id"] as? String)?.lowercased() }
                return .success(ids)
            } catch {
                return .failure(error)
            }

        case .failure(let e):
            return .failure(e)
        }
    }

    public func fetchOutgoingRequests() async -> Result<[String], Error> {
        guard let apiKey = BackendConfig.apiToken, !apiKey.isEmpty else {
            return .failure(NSError(domain: "Backend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"]))
        }
        guard let me = currentBackendUserID(), !me.isEmpty else {
            return .success([])
        }

        let path = "rest/v1/follows?select=followed_user_id&follower_user_id=eq.\(me)&status=eq.requested"
        let result = await NetworkManager.shared.request(path: path, method: "GET", headers: headers(apiKey: apiKey))

        switch result {
        case .success(let data):
            do {
                let obj = try JSONSerialization.jsonObject(with: data, options: [])
                let rows = obj as? [[String: Any]] ?? []
                let ids = rows.compactMap { ($0["followed_user_id"] as? String)?.lowercased() }
                return .success(ids)
            } catch {
                return .failure(error)
            }

        case .failure(let e):
            return .failure(e)
        }
    }

    public func requestFollow(to targetUserID: String) async -> Result<Void, Error> {
        guard let apiKey = BackendConfig.apiToken, !apiKey.isEmpty else {
            return .failure(NSError(domain: "Backend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"]))
        }
        guard let me = currentBackendUserID(), !me.isEmpty else {
            return .failure(NSError(domain: "Backend", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing backend user id"]))
        }

        let body: [String: Any] = [
            "follower_user_id": me,
            "followed_user_id": targetUserID.lowercased(),
            "status": "requested"
        ]
        do {
            let json = try JSONSerialization.data(withJSONObject: body, options: [])
            let result = await NetworkManager.shared.request(path: "rest/v1/follows", method: "POST", jsonBody: json, headers: headers(apiKey: apiKey))
            switch result {
            case .success:
                return .success(())
            case .failure(let e):
                // Idempotence: if already exists, treat as OK.
                if let ne = e as? NetworkManager.NetworkError, case .httpError(let status, _) = ne, status == 409 {
                    return .success(())
                }
                return .failure(e)
            }
        } catch {
            return .failure(error)
        }
    }

    public func approveFollow(from requesterUserID: String) async -> Result<Void, Error> {
        guard let apiKey = BackendConfig.apiToken, !apiKey.isEmpty else {
            return .failure(NSError(domain: "Backend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"]))
        }
        guard let me = currentBackendUserID(), !me.isEmpty else {
            return .failure(NSError(domain: "Backend", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing backend user id"]))
        }

        let patch: [String: Any] = [
            "status": "approved",
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        do {
            let json = try JSONSerialization.data(withJSONObject: patch, options: [])
            let path = "rest/v1/follows?follower_user_id=eq.\(requesterUserID.lowercased())&followed_user_id=eq.\(me)"
            let result = await NetworkManager.shared.request(path: path, method: "PATCH", jsonBody: json, headers: headers(apiKey: apiKey))
            switch result {
            case .success:
                return .success(())
            case .failure(let e):
                return .failure(e)
            }
        } catch {
            return .failure(error)
        }
    }

    public func declineFollow(from requesterUserID: String) async -> Result<Void, Error> {
        // Decline == delete request row.
        return await deleteRelationship(with: requesterUserID.lowercased())
    }

    public func unfollow(_ targetUserID: String) async -> Result<Void, Error> {
        // Unfollow == delete row.
        return await deleteRelationship(with: targetUserID.lowercased())
    }

    private func deleteRelationship(with otherUserID: String) async -> Result<Void, Error> {
        guard let apiKey = BackendConfig.apiToken, !apiKey.isEmpty else {
            return .failure(NSError(domain: "Backend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"]))
        }
        guard let me = currentBackendUserID(), !me.isEmpty else {
            return .failure(NSError(domain: "Backend", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing backend user id"]))
        }

        // Try both directions (either party can delete).
        let path1 = "rest/v1/follows?follower_user_id=eq.\(me)&followed_user_id=eq.\(otherUserID)"
        let r1 = await NetworkManager.shared.request(path: path1, method: "DELETE", headers: headers(apiKey: apiKey))
        switch r1 {
        case .success:
            return .success(())
        case .failure:
            break
        }

        let path2 = "rest/v1/follows?follower_user_id=eq.\(otherUserID)&followed_user_id=eq.\(me)"
        let r2 = await NetworkManager.shared.request(path: path2, method: "DELETE", headers: headers(apiKey: apiKey))
        switch r2 {
        case .success:
            return .success(())
        case .failure(let e2):
            return .failure(e2)
        }
    }
}

public final class HTTPBackendPublishService: BackendPublishService {
    public init() {}

    @MainActor
    public func uploadPost(_ payload: SessionSyncQueue.PostPublishPayload) async -> Result<Void, Error> {
        guard let apiKey = BackendConfig.apiToken, !apiKey.isEmpty else {
            return .failure(NSError(domain: "Backend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"]))
        }

        let owner = (AuthManager.canonicalBackendUserID() ?? "")

        if owner.isEmpty {
            return .failure(NSError(domain: "Backend", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing owner user id"]))
        }

        let createdAt = ISO8601DateFormatter().string(from: Date())
        var body: [String: Any] = [
            "id": payload.id.uuidString,
            "created_at": createdAt,
            "owner_user_id": owner,
            "is_public": payload.isPublic
        ]

        if let sid = payload.sessionID {
            body["session_id"] = sid.uuidString
        }
        if let ts = payload.sessionTimestamp {
            body["session_timestamp"] = ISO8601DateFormatter().string(from: ts)
        }
        if let title = payload.title {
            body["title"] = title
        }
        if let dur = payload.durationSeconds {
            body["duration_seconds"] = dur
        }
        if let at = payload.activityType {
            body["activity_type"] = at
        }
        if let ad = payload.activityDetail {
            body["activity_detail"] = ad
        }
        if let instr = payload.instrumentLabel {
            body["instrument_label"] = instr
        }
        if let mood = payload.mood {
            body["mood"] = mood
        }
        if let effort = payload.effort {
            body["effort"] = effort
        }

        // Step 12 parity: only publish notes when they are not marked private.
        // If notes are private (or empty), omit the key so the backend column remains NULL.
        if !payload.areNotesPrivate, let notes = payload.notes {
            let trimmed = notes.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !trimmed.isEmpty {
                body["notes"] = trimmed
            }
        }

        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            return .failure(error)
        }

        let headers: [String: String] = [
            "apikey": apiKey,
            "Prefer": "return=minimal"
        ]

        let result = await NetworkManager.shared.request(
            path: "rest/v1/posts",
            method: "POST",
            query: nil,
            jsonBody: jsonData,
            headers: headers
        )

        switch result {
        case .success:
            break

        case .failure(let e):
            // Idempotence: if the post already exists (e.g. retry after attachment upload failure),
            // treat 409 as "created" and continue into attachment upload + PATCH.
            if let ne = e as? NetworkManager.NetworkError {
                if case .httpError(let status, _) = ne, status == 409 {
                    break
                }
            }
            return .failure(e)
        }

        
        // Keep metadata in sync on every publish attempt (including the idempotent 409 path).
        let metaPatch = await patchPostMetadata(postID: payload.id, payload: payload)
        switch metaPatch {
        case .success:
            break
        case .failure(let e):
            return .failure(e)
        }

// Step 8G Phase 3: upload included attachments (owner-only by default) and PATCH posts.attachments.
        guard let sessionID = payload.sessionID else {
            // No local session reference → nothing to upload.
            return .success(())
        }

        let included = loadIncludedAttachments(for: sessionID)
        if included.isEmpty {
            // Keep backend row consistent: explicitly clear attachments.
            let patch = await patchPostAttachments(postID: payload.id, refs: [])
            switch patch {
            case .success:
                return .success(())
            case .failure(let e):
                return .failure(e)
            }
        }

        var refs: [[String: String]] = []
        refs.reserveCapacity(included.count)

        for item in included {
            let objectPath = storageObjectPath(owner: owner, postID: payload.id, attachmentID: item.id, ext: item.ext)
            let upload = await uploadStorageObject(from: item.fileURL, bucket: "attachments", objectPath: objectPath, contentType: item.contentType)
            switch upload {
            case .success:
                var ref: [String: String] = [
                    "kind": item.kind,
                    "bucket": "attachments",
                    "path": objectPath
                ]

                if let displayName = item.displayName ?? persistedDisplayNameForAttachment(kind: item.kind, attachmentID: item.id) {
                    ref["display_name"] = displayName
                }

                refs.append(ref)
            case .failure(let e):
                return .failure(e)
            }
        }

        let patch = await patchPostAttachments(postID: payload.id, refs: refs)
        switch patch {
        case .success:
            return .success(())
        case .failure(let e):
            return .failure(e)
        }
    }

    // MARK: - Step 8G Phase 3 helpers (p
    // MARK: - Display-name parity (remote attachments)

    /// Returns a user-facing display name for an attachment (audio/video only), or nil.
    /// Hard rule: never return file paths, sandbox URLs, or storage object keys as names.
    private func persistedDisplayNameForAttachment(kind: String, attachmentID: UUID) -> String? {
        let k = kind.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
        guard k == "audio" || k == "video" else { return nil }

        let defaultsKey: String
        if k == "audio" {
            defaultsKey = "persistedAudioTitles_v1"
        } else {
            defaultsKey = "persistedVideoTitles_v1"
        }

        guard let dict = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] else {
            return nil
        }

        let raw = dict[attachmentID.uuidString]
        let trimmed = (raw ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Publish-time Storage upload
    private struct LocalAttachmentUpload {
        let id: UUID
        let kind: String
        let fileURL: URL
        let ext: String
        let contentType: String
        let createdAt: Date?
    let displayName: String? = nil
    }


    private func resolveLocalFileURL(from stored: String) -> URL? {
        let s = stored.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // If we stored a file:// URL string, prefer parsing it directly.
        if s.lowercased().hasPrefix("file://"), let u = URL(string: s) {
            return u
        }

        // If the string already looks like a path (contains a slash), treat it as a path.
        if s.contains("/") {
            return URL(fileURLWithPath: s)
        }

        // Otherwise assume it's a filename in Documents/.
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent(s, isDirectory: false)
    }

    private func loadIncludedAttachments(for sessionID: UUID) -> [LocalAttachmentUpload] {
        let context = PersistenceController.shared.container.viewContext

        let request = NSFetchRequest<NSManagedObject>(entityName: "Session")
        request.predicate = NSPredicate(format: "id == %@", sessionID as CVarArg)
        request.fetchLimit = 1

        guard let session = (try? context.fetch(request))?.first else { return [] }
        let attachments = session.value(forKey: "attachments") as? Set<NSManagedObject> ?? []

        var items: [LocalAttachmentUpload] = []
        items.reserveCapacity(attachments.count)

        for a in attachments {
            guard let id = a.value(forKey: "id") as? UUID else { continue }
            let kind = ((a.value(forKey: "kind") as? String) ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard let filePath = a.value(forKey: "fileURL") as? String, !filePath.isEmpty else { continue }

            guard let url = resolveLocalFileURL(from: filePath) else { continue }

            // If the file no longer exists locally (e.g. user deleted storage), skip it rather than blocking publish.
            if !FileManager.default.fileExists(atPath: url.path) { continue }

            if AttachmentPrivacy.isPrivate(id: id, url: url) { continue }

            let ext = url.pathExtension.isEmpty ? defaultExtension(for: kind) : url.pathExtension.lowercased()
            let contentType = contentType(for: kind, ext: ext)
            let createdAt = a.value(forKey: "createdAt") as? Date
items.append(LocalAttachmentUpload(id: id, kind: kind, fileURL: url, ext: ext, contentType: contentType, createdAt: createdAt))
        }

        items.sort {
            let a = $0.createdAt ?? .distantPast
            let b = $1.createdAt ?? .distantPast
            if a != b { return a < b }
            return $0.id.uuidString < $1.id.uuidString
        }

        return items
    }

    private func storageObjectPath(owner: String, postID: UUID, attachmentID: UUID, ext: String) -> String {
        let safeOwner = owner.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let safeExt = ext.isEmpty ? "" : ".\(ext)"
        return "users/\(safeOwner)/\(postID.uuidString)/\(attachmentID.uuidString)\(safeExt)"
    }

    private func uploadStorageObject(from localURL: URL, bucket: String, objectPath: String, contentType: String) async -> Result<Void, Error> {
        let data: Data
        do {
            data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: localURL)
            }.value
        } catch {
            return .failure(error)
        }

        let uploadPath = "storage/v1/object/\(bucket)/\(objectPath)"
        let result = await NetworkManager.shared.request(
            path: uploadPath,
            method: "POST",
            query: nil,
            jsonBody: data,
            headers: [
                "Content-Type": contentType,
                // Allow safe retries (idempotent paths). If object already exists, overwrite.
                "x-upsert": "true"
            ]
        )

        switch result {
        case .success:
            return .success(())
        case .failure(let e):
            return .failure(e)
        }
    }

    private
    /// PATCH post metadata that may change across re-publishes (e.g., visibility).
    /// This is required because uploadPost uses idempotent POST (409 on existing),
    /// and without a PATCH the existing row would keep stale values (notably is_public).
    func patchPostMetadata(postID: UUID, payload: SessionSyncQueue.PostPublishPayload) async -> Result<Void, Error> {
        guard let apiKey = BackendConfig.apiToken, !apiKey.isEmpty else {
            return .failure(NSError(domain: "Backend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"]))
        }

        var meta: [String: Any] = [
            "is_public": payload.isPublic
        ]

        // Keep these fields in sync when they are present.
        if let sid = payload.sessionID {
            meta["session_id"] = sid.uuidString
        }
        if let ts = payload.sessionTimestamp {
            meta["session_timestamp"] = ISO8601DateFormatter().string(from: ts)
        }
        if let title = payload.title {
            meta["title"] = title
        }
        if let dur = payload.durationSeconds {
            meta["duration_seconds"] = dur
        }
        if let at = payload.activityType {
            meta["activity_type"] = at
        }
        if let ad = payload.activityDetail {
            meta["activity_detail"] = ad
        }
        if let instr = payload.instrumentLabel {
            meta["instrument_label"] = instr
        }

        // Notes: only include when not private (or omitted). If notes become private later,
        // this patch intentionally does not force-clear server notes (out of scope).
        if !payload.areNotesPrivate, let notes = payload.notes {
            let trimmed = notes.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !trimmed.isEmpty {
                meta["notes"] = trimmed
            }
        }

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: meta, options: [])
        } catch {
            return .failure(error)
        }

        let patchPath = "rest/v1/posts?id=eq.\(postID.uuidString)"
        let result = await NetworkManager.shared.request(
            path: patchPath,
            method: "PATCH",
            query: nil,
            jsonBody: body,
            headers: [
                "apikey": apiKey,
                "Prefer": "return=minimal"
            ]
        )

        switch result {
        case .success:
            return .success(())
        case .failure(let e):
            return .failure(e)
        }
    }

func patchPostAttachments(postID: UUID, refs: [[String: String]]) async -> Result<Void, Error> {
        let payload: [String: Any] = [
            "attachments": refs
        ]

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            return .failure(error)
        }

        let patchPath = "rest/v1/posts?id=eq.\(postID.uuidString)"
        let result = await NetworkManager.shared.request(
            path: patchPath,
            method: "PATCH",
            query: nil,
            jsonBody: body,
            headers: [
                    "Prefer": "return=minimal"
            ]
        )

        switch result {
        case .success:
            return .success(())
        case .failure(let e):
            return .failure(e)
        }
    }

    private func defaultExtension(for kind: String) -> String {
        switch kind.lowercased() {
        case "image": return "jpg"
        case "video": return "mp4"
        case "audio": return "m4a"
        default: return ""
        }
    }

    private func contentType(for kind: String, ext: String) -> String {
        let e = ext.lowercased()
        switch kind.lowercased() {
        case "image":
            if e == "png" { return "image/png" }
            if e == "heic" { return "image/heic" }
            return "image/jpeg"
        case "video":
            if e == "mov" { return "video/quicktime" }
            return "video/mp4"
        case "audio":
            if e == "mp3" { return "audio/mpeg" }
            if e == "wav" { return "audio/wav" }
            if e == "aac" { return "audio/aac" }
            return "audio/m4a"
        default:
            return "application/octet-stream"
        }
    }

    @MainActor
    public func deletePost(_ postID: UUID) async -> Result<Void, Error> {
        guard let apiKey = BackendConfig.apiToken, !apiKey.isEmpty else {
            return .failure(NSError(domain: "Backend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"]))
        }

        let path = "rest/v1/posts?id=eq.\(postID.uuidString)"
        let headers: [String: String] = [
            "apikey": apiKey,
            "Prefer": "return=minimal"
        ]

        let result = await NetworkManager.shared.request(
            path: path,
            method: "DELETE",
            query: nil,
            jsonBody: nil,
            headers: headers
        )

        switch result {
        case .success:
            return .success(())
        case .failure(let e):
            return .failure(e)
        }
    }

    @MainActor
    public func updatePost(_ postID: UUID) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("HTTPBackendPublishService.updatePost", meta: ["postID": postID.uuidString])
        return .success(())
    }

    @MainActor
    public func fetchFeed(scope: String) async -> Result<Void, Error> {
        let normalized = scope.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
        guard normalized == "mine" || normalized == "all" else {
            return .failure(NSError(domain: "Backend", code: 10, userInfo: [NSLocalizedDescriptionKey: "Unsupported feed scope: \(scope)"]))
        }

        guard let apiKey = BackendConfig.apiToken, !apiKey.isEmpty else {
            return .failure(NSError(domain: "Backend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"]))
        }

        let owner = (AuthManager.canonicalBackendUserID() ?? "")

        if owner.isEmpty {
            return .failure(NSError(domain: "Backend", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing owner user id"]))
        }

        let ownerLower = owner.lowercased()

        var targetOwnersLower: [String] = [ownerLower]
        if normalized == "all" {
            // Phase 9B: backend follow graph drives targetOwners in Backend Preview.
            if BackendEnvironment.shared.isPreview {
                await FollowStore.shared.refreshFromBackendIfPossible()
            }

            let following = FollowStore.shared.followingIDs()
            let normalizedFollowing = following.map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased() }
            var seen = Set<String>()
            var merged: [String] = []
            for id in ([ownerLower] + normalizedFollowing) {
                guard !id.isEmpty else { continue }
                if seen.insert(id).inserted { merged.append(id) }
            }
            targetOwnersLower = merged
        }

        await MainActor.run {
            BackendFeedStore.shared.beginFetch(ownerKey: owner, scope: normalized, targetOwners: targetOwnersLower)
        }

        let headers: [String: String] = [
            "apikey": apiKey,
            "Accept": "application/json"
        ]

        // Step 8C.1 sanity: Mine uses proper server-side filter + order.
        // NOTE: owner_user_id is uuid, so we MUST use eq., not ilike.
        let queryItems: [URLQueryItem]? = {
            if normalized == "mine" {
                return [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "owner_user_id", value: "eq.\(ownerLower)"),
                    URLQueryItem(name: "order", value: "created_at.desc")
                ]
            } else if normalized == "all" {
                // Phase 9C: rely on server-side RLS to enforce visibility for "All".
                return [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "order", value: "created_at.desc")
                ]
            } else {
                return nil
            }
        }()

        let result = await NetworkManager.shared.request(
            path: "rest/v1/posts",
            method: "GET",
            query: queryItems,
            jsonBody: nil,
            headers: headers
        )

        switch result {
        case .success(let data):
            do {
                let decoder = JSONDecoder()
                let rawPosts = try decoder.decode([BackendPost].self, from: data)

                let mine = rawPosts.filter { ($0.ownerUserID ?? "").lowercased() == ownerLower }

                let all: [BackendPost]
                if normalized == "all" {
                    // Phase 9C: server already enforces owner/follow visibility via RLS.
                    all = rawPosts
                } else {
                    all = mine
                }

                let iso = ISO8601DateFormatter()
                func sortByCreatedDesc(_ posts: [BackendPost]) -> [BackendPost] {
                    posts.sorted { a, b in
                        let da = a.createdAt.flatMap { iso.date(from: $0) } ?? Date.distantPast
                        let db = b.createdAt.flatMap { iso.date(from: $0) } ?? Date.distantPast
                        return da > db
                    }
                }

                let sortedMine = sortByCreatedDesc(mine)
                let sortedAll = sortByCreatedDesc(all)

                // Phase 14 Step 3: Batch-resolve directory identities for authors visible in the feed.
                // AccountDirectoryService expects [String] user IDs (uuid strings) matching the RPC signature (uuid[]).
                let uniqueAuthorUserIDs: [String] = Array(Set(rawPosts.compactMap { post in
                    guard let s = post.ownerUserID, UUID(uuidString: s) != nil else { return nil }
                    return s
                }))

                if !uniqueAuthorUserIDs.isEmpty {
                    let resolved = await AccountDirectoryService.shared.resolveAccounts(userIDs: uniqueAuthorUserIDs, forceRefresh: true)
                    if case .success(let map) = resolved {
                        await MainActor.run {
                            BackendFeedStore.shared.mergeDirectoryAccounts(map)
                        }
                    }
                }

                await MainActor.run {
                    BackendFeedStore.shared.endFetchSuccess(rawPosts: rawPosts, minePosts: sortedMine, allPosts: sortedAll)
                }

                return .success(())
            } catch {
                await MainActor.run {
                    BackendFeedStore.shared.endFetchFailure(error)
                }
                return .failure(error)
            }

        case .failure(let e):
            await MainActor.run {
                BackendFeedStore.shared.endFetchFailure(e)
            }
            return .failure(e)
        }
    }
}



// MARK: - Post Shares (pointer-only "Shared with you")

public struct BackendPostSharePointer: Codable, Hashable, Identifiable {
    public let id: UUID
    public let postID: UUID
    public let ownerUserID: String
    public let recipientUserID: String
    public let createdAt: Date
    public let viewedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case ownerUserID = "owner_user_id"
        case recipientUserID = "recipient_user_id"
        case createdAt = "created_at"
        case viewedAt = "viewed_at"
    }
}

public protocol BackendPostShareService {
    func fetchUnreadShares() async -> Result<[BackendPostSharePointer], Error>
    func sharePost(postID: UUID, to recipientUserID: String) async -> Result<BackendPostShareOutcome, Error>
    func markShareViewed(shareID: UUID) async -> Result<Void, Error>
    func deleteShare(shareID: UUID) async -> Result<Void, Error>
}

public enum BackendPostShareOutcome: Equatable {
    case shared
    case alreadyShared
}

public struct BackendPostShareAlreadySharedError: LocalizedError {
    public init() {}
    public var errorDescription: String? { "Already shared." }
}


public struct SimulatedPostShareService: BackendPostShareService {
    public init() {}
    public func fetchUnreadShares() async -> Result<[BackendPostSharePointer], Error> { .success([]) }
    public func sharePost(postID: UUID, to recipientUserID: String) async -> Result<BackendPostShareOutcome, Error> { .success(.shared) }
    public func markShareViewed(shareID: UUID) async -> Result<Void, Error> { .success(()) }
    public func deleteShare(shareID: UUID) async -> Result<Void, Error> { .success(()) }
}

public final class HTTPBackendPostShareService: BackendPostShareService {
    public init() {}

    private func currentBackendUserID() -> String? {
        #if DEBUG
        if BackendEnvironment.shared.isConnected == false,
           let override = UserDefaults.standard.string(forKey: "Debug.backendUserIDOverride")?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
           !override.isEmpty {
            return override.lowercased()
        }
        #endif

        // Prefer Supabase user ID if present; fall back to legacy backendUserID.
        if let supa = UserDefaults.standard.string(forKey: "supabaseUserID_v1")?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
           !supa.isEmpty {
            return supa.lowercased()
        }
        if let legacy = UserDefaults.standard.string(forKey: "backendUserID_v1")?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
           !legacy.isEmpty {
            return legacy.lowercased()
        }
        return nil
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func fetchUnreadShares() async -> Result<[BackendPostSharePointer], Error> {
        guard let uid = currentBackendUserID(), !uid.isEmpty else {
            return .success([])
        }

        let path = "/rest/v1/post_shares"
        let query: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "recipient_user_id", value: "eq.\(uid)"),
            URLQueryItem(name: "viewed_at", value: "is.null"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]

        let result = await NetworkManager.shared.request(
            path: path,
            method: "GET",
            query: query,
            jsonBody: nil
        )

        switch result {
        case .success(let data):
            do {
                let shares = try decoder().decode([BackendPostSharePointer].self, from: data)
                return .success(shares)
            } catch {
                return .failure(error)
            }
        case .failure(let e):
            return .failure(e)
        }
    }

    public func sharePost(postID: UUID, to recipientUserID: String) async -> Result<BackendPostShareOutcome, Error> {
        guard let uid = currentBackendUserID(), !uid.isEmpty else {
            return .failure(NSError(domain: "BackendPostShareService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing user ID"]))
        }

        let payload: [String: Any] = [
            "post_id": postID.uuidString,
            "owner_user_id": uid,
            "recipient_user_id": recipientUserID.lowercased()
        ]

        do {
            let body = try JSONSerialization.data(withJSONObject: payload, options: [])
            let result = await NetworkManager.shared.request(
                path: "/rest/v1/post_shares",
                method: "POST",
                query: nil,
                jsonBody: body,
                headers: ["Prefer": "return=minimal"]
            )

            switch result {
            case .success:
                return .success(.shared)

            case .failure(let e):
                // Duplicate share attempts should surface as a non-fatal "Already shared." outcome.
                if case NetworkManager.NetworkError.httpError(let status, let bodyString) = e, status == 409 {
                    if let bodyString, let bodyData = bodyString.data(using: .utf8) {
                        if let obj = try? JSONSerialization.jsonObject(with: bodyData, options: []),
                           let dict = obj as? [String: Any] {
                            let code = dict["code"] as? String
                            let message = dict["message"] as? String
                            if code == "23505" || (message?.contains("post_shares_unique") == true) {
                                return .success(.alreadyShared)
                            }
                        }
                    }
                }

                return .failure(e)
            }
        } catch {
            return .failure(error)
        }
    }

    public func markShareViewed(shareID: UUID) async -> Result<Void, Error> {
        let payload: [String: Any] = [
            "viewed_at": ISO8601DateFormatter().string(from: Date())
        ]

        do {
            let body = try JSONSerialization.data(withJSONObject: payload, options: [])
            let result = await NetworkManager.shared.request(
                path: "/rest/v1/post_shares",
                method: "PATCH",
                query: [URLQueryItem(name: "id", value: "eq.\(shareID.uuidString)")],
                jsonBody: body,
                headers: ["Prefer": "return=minimal"]
            )

            switch result {
            case .success:
                return .success(())
            case .failure(let e):
                return .failure(e)
            }
        } catch {
            return .failure(error)
        }
    }

    public func deleteShare(shareID: UUID) async -> Result<Void, Error> {
        let result = await NetworkManager.shared.request(
            path: "/rest/v1/post_shares",
            method: "DELETE",
            query: [URLQueryItem(name: "id", value: "eq.\(shareID.uuidString)")],
            jsonBody: nil,
            headers: ["Prefer": "return=minimal"]
        )

        switch result {
        case .success:
            return .success(())
        case .failure(let e):
            return .failure(e)
        }
    }
}



public final class BackendEnvironment {
    public static let shared = BackendEnvironment()

    public var publish: BackendPublishService {
        let mode = currentBackendMode()
        let hasHTTPConfig = BackendConfig.isConfigured && (NetworkManager.shared.baseURL != nil)

        if (mode == .backendPreview || mode == .backendConnected) && hasHTTPConfig {
            return HTTPBackendPublishService()
        }
        return SimulatedPublishService()
    }

    public var profile: BackendProfileService { SimulatedProfileService() }

    public var follow: BackendFollowService {
        let mode = currentBackendMode()
        let hasHTTPConfig = BackendConfig.isConfigured && (NetworkManager.shared.baseURL != nil)
        if (mode == .backendPreview || mode == .backendConnected) && hasHTTPConfig {
            return HTTPBackendFollowService()
        }
        return SimulatedFollowService()
    }

    public var shares: BackendPostShareService {
        let mode = currentBackendMode()
        let hasHTTPConfig = BackendConfig.isConfigured && (NetworkManager.shared.baseURL != nil)
        if (mode == .backendPreview || mode == .backendConnected) && hasHTTPConfig {
            return HTTPBackendPostShareService()
        }
        return SimulatedPostShareService()
    }

    private init() {}

    @inline(__always)
    public var mode: BackendMode { currentBackendMode() }

    @inline(__always)
    public var isPreview: Bool { mode == .backendPreview }

    @inline(__always)
    public var isConnected: Bool { mode == .backendConnected }

    @inline(__always)
    public var isHTTPEnabled: Bool { (mode == .backendPreview || mode == .backendConnected) }
}

@inline(__always)
public func currentBackendMode() -> BackendMode {
    if let raw = UserDefaults.standard.string(forKey: BackendKeys.modeKey),
       let mode = BackendMode(rawValue: raw) {
        return mode
    }
    return .localSimulation
}
