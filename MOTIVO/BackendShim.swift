// CHANGE-ID: 20260128_192500_14_3A_MainActorPublishingFix
// SCOPE: Phase 14.3A — Fix runtime warning "Publishing changes from background threads" by ensuring all BackendFeedStore (@MainActor) mutations are performed via MainActor hops in HTTP feed fetch. No UI or logic changes.
// SEARCH-TOKEN: 20260128_192500_14_3A_MainActorPublishingFix

// CHANGE-ID: 20260121_181200_Phase14_Step3_FixUserIDType
// SCOPE: Phase 14 Step 3 — fix AccountDirectoryService resolveAccounts callsite to pass [String] user_id values (uuid strings), not [UUID].

// CHANGE-ID: 20260121_180200_Phase14_Step3_DirectoryBatchCache
// SCOPE: Phase 14 Step 3 — Batch directory identity lookup after feed fetch; in-memory cache in BackendFeedStore (no UI changes).
// SEARCH-TOKEN: 20260121_180200_Phase14_Step3_DirectoryBatchCache
// CHANGE-ID: 20260121_124000_P13F_BackendFollowersFetch
// SCOPE: Phase 13F — Add fetchFollowersApproved to BackendFollowService and HTTP/Simulated implementations.
// SEARCH-TOKEN: 20260121_124000_P13F_BackendFollowersFetch

// CHANGE-ID: 20260121_114321_P13D1_BackendConnectedMode
// SCOPE: Phase 13D.1 — Add BackendMode.backendConnected (shipping) distinct from backendPreview; enable HTTP services in connected/preview; add isConnected/isHTTPEnabled
// SEARCH-TOKEN: P13D1-CONNECTED-MODE-20260121_114321

// CHANGE-ID: 20260119_135600_Step12_ActivityReadFix
// SCOPE: Decode activity_type/activity_detail on BackendPost for backend preview parity
// SEARCH-TOKEN: ACTIVITY-READ-PARITY-20260119

//
// CHANGE-ID: 20260112_201800_9C_RLSFeed
// SCOPE: Step 9C — RLS-enforced feed visibility (All relies on server; no client allowlist filter)
// SEARCH-TOKEN: 20260112_141800_Step9B_BackendFollowGraph_Fix1
//
// CHANGE-ID: 20260112_140516_Step9B_BackendFollowGraph
// SCOPE: Step 9B — Backend follow table + client wiring (service + FollowStore refresh; no posts RLS changes).
// SEARCH-TOKEN: 20260112_140516_Step9B_BackendFollowGraph
//
// CHANGE-ID: 20260109_121500_Step8G_Phase3_Fix_8G3A
// SCOPE: Step 8G Phase 3 — Fix BackendShim compile errors (scope/brace hygiene + 409 idempotence NetworkError casting). No behavior changes beyond making Phase 3 compile.
// SEARCH-TOKEN: 20260109_121500_Step8G_Phase3_Fix_8G3A
//
// Prior CHANGE-ID retained below for provenance:
// CHANGE-ID: 20260101_141600_Step8B_AllFeed_DebugOnly
//

// CHANGE-ID: 20260112_131015_9A_backend_identity_canonicalisation
// SCOPE: Step 9A — Use AuthManager.canonicalBackendUserID() for all backend owner identity reads (publish + feed)
// UNIQUE-TOKEN: 20260112_131015_backendshim_id_canon

// CHANGE-ID: 20260119_135600_Step12_ActivityReadFix
// SCOPE: Add posts.notes decode + include notes in publish POST body (gated by areNotesPrivate)
// SEARCH-TOKEN: ACTIVITY-READ-PARITY-20260119

// CHANGE-ID: 20260122_113000_Phase142_IgnoreBackendOverrideInConnected_FollowService
// SCOPE: Phase 14.2 — Ignore Debug.backendUserIDOverride when BackendEnvironment.isConnected == true (HTTPBackendFollowService)
// SEARCH-TOKEN: 20260122_113000_Phase142_BackendShimIgnoreOverride

// CHANGE-ID: 20260129_090937_14_3H_SignOutFeedReset_SignInReliability
// SCOPE: Phase 14.3H — (A) Clear connected feed state on sign-out via auth transition; (B) Prevent first sign-in UI from staying signed-out due to missing refresh token when access token is present (fail closed on network-auth-challenge). No UI/layout changes; no backend/schema changes.
// SEARCH-TOKEN: 20260129_090937_14_3H_SignOutFeedReset_SignInReliability

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
        minePosts = []
        allPosts = []
        directoryAccountsByUserID = [:]

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

        minePosts = []
        allPosts = []
        directoryAccountsByUserID = [:]
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
           let override = UserDefaults.standard.string(forKey: "Debug.backendUserIDOverride")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override.lowercased()
        }
        #endif

        // Prefer Supabase user ID if present; fall back to legacy backendUserID.
        if let supa = UserDefaults.standard.string(forKey: "supabaseUserID_v1")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !supa.isEmpty {
            return supa.lowercased()
        }
        if let legacy = UserDefaults.standard.string(forKey: "backendUserID_v1")?.trimmingCharacters(in: .whitespacesAndNewlines),
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
            "is_public": true
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
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
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
                refs.append([
                    "kind": item.kind,
                    "bucket": "attachments",
                    "path": objectPath
                ])
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

    // MARK: - Step 8G Phase 3 helpers (publish-time Storage upload)

    private struct LocalAttachmentUpload {
        let id: UUID
        let kind: String
        let fileURL: URL
        let ext: String
        let contentType: String
        let createdAt: Date?
    }


    private func resolveLocalFileURL(from stored: String) -> URL? {
        let s = stored.trimmingCharacters(in: .whitespacesAndNewlines)
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
            let kind = ((a.value(forKey: "kind") as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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
        let safeOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func patchPostAttachments(postID: UUID, refs: [[String: String]]) async -> Result<Void, Error> {
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
        let normalized = scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
            let normalizedFollowing = following.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
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

                await MainActor.run {
                    BackendFeedStore.shared.endFetchSuccess(rawPosts: rawPosts, minePosts: sortedMine, allPosts: sortedAll)
                }

                // Phase 14 Step 3: Batch-resolve directory identities for authors visible in the feed.
                // AccountDirectoryService expects [String] user IDs (uuid strings) matching the RPC signature (uuid[]).
                let uniqueAuthorUserIDs: [String] = Array(Set(rawPosts.compactMap { post in
                    guard let s = post.ownerUserID, UUID(uuidString: s) != nil else { return nil }
                    return s
                }))

                if !uniqueAuthorUserIDs.isEmpty {
                    let resolved = await AccountDirectoryService.shared.resolveAccounts(userIDs: uniqueAuthorUserIDs)
                    if case .success(let map) = resolved {
                        await MainActor.run {
                            BackendFeedStore.shared.mergeDirectoryAccounts(map)
                        }
                    }
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
