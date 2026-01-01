//
// CHANGE-ID: 20260101_141600_Step8B_AllFeed_DebugOnly
// SCOPE: Step 8B — Add "all" scope fetch (debug-only) using local FollowStore followingIDs; keep Step 8A Mine intact; add minimal diagnostics.
// SEARCH-TOKEN: 20260101_141600_Step8B_AllFeed_DebugOnly
//

import Foundation
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
    case backendPreview

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .localSimulation: return "Local Simulation"
        case .backendPreview: return "Backend Preview"
        }
    }
}

public struct BackendPost: Codable, Identifiable, Hashable {
    public let id: UUID
    public let ownerUserID: String?
    public let sessionID: UUID?
    public let sessionTimestamp: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let isPublic: Bool?

    public enum CodingKeys: String, CodingKey {
        case id
        case ownerUserID = "owner_user_id"
        case sessionID = "session_id"
        case sessionTimestamp = "session_timestamp"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isPublic = "is_public"
    }
}

@MainActor
public final class BackendFeedStore: ObservableObject {
    public static let shared = BackendFeedStore()

    @Published public private(set) var minePosts: [BackendPost] = []
    @Published public private(set) var allPosts: [BackendPost] = []

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

    public func endFetchFailure(_ error: Error) {
        isFetching = false
        lastError = error.localizedDescription
    }
}

public protocol BackendPublishService {
    func uploadPost(_ postID: UUID) async -> Result<Void, Error>
    func deletePost(_ postID: UUID) async -> Result<Void, Error>
    func updatePost(_ postID: UUID) async -> Result<Void, Error>
    func fetchFeed(scope: String) async -> Result<Void, Error>
}

public protocol BackendProfileService {}
public protocol BackendFollowService {}

public final class SimulatedPublishService: BackendPublishService {
    public init() {}

    @MainActor
    public func uploadPost(_ postID: UUID) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("PublishService.uploadPost", meta: ["postID": postID.uuidString])
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
public final class SimulatedFollowService: BackendFollowService { public init() {} }

public final class HTTPBackendPublishService: BackendPublishService {
    public init() {}

    @MainActor
    public func uploadPost(_ postID: UUID) async -> Result<Void, Error> {
        guard let apiKey = BackendConfig.apiToken, !apiKey.isEmpty else {
            return .failure(NSError(domain: "Backend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"]))
        }

        let owner = (UserDefaults.standard.string(forKey: "supabaseUserID_v1") ??
                     UserDefaults.standard.string(forKey: "backendUserID_v1") ??
                     "").trimmingCharacters(in: .whitespacesAndNewlines)

        if owner.isEmpty {
            return .failure(NSError(domain: "Backend", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing owner user id"]))
        }

        let createdAt = ISO8601DateFormatter().string(from: Date())
        let body: [String: Any] = [
            "id": postID.uuidString,
            "created_at": createdAt,
            "owner_user_id": owner,
            "is_public": true
        ]

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
            return .success(())
        case .failure(let e):
            return .failure(e)
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

        let owner = (UserDefaults.standard.string(forKey: "supabaseUserID_v1") ??
                     UserDefaults.standard.string(forKey: "backendUserID_v1") ??
                     "").trimmingCharacters(in: .whitespacesAndNewlines)

        if owner.isEmpty {
            return .failure(NSError(domain: "Backend", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing owner user id"]))
        }

        let ownerLower = owner.lowercased()

        var targetOwnersLower: [String] = [ownerLower]
        if normalized == "all" {
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

        BackendFeedStore.shared.beginFetch(ownerKey: owner, scope: normalized, targetOwners: targetOwnersLower)

        let headers: [String: String] = [
            "apikey": apiKey,
            "Accept": "application/json"
        ]

        // Step 8C.1 sanity: Mine uses proper server-side filter + order.
        // NOTE: owner_user_id is uuid, so we MUST use eq., not ilike.
        let queryItems: [URLQueryItem]? = {
            guard normalized == "mine" else { return nil }
            return [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "owner_user_id", value: "eq.\(ownerLower)"),
                URLQueryItem(name: "order", value: "created_at.desc")
            ]
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
                    let allow = Set(targetOwnersLower)
                    all = rawPosts.filter { allow.contains(($0.ownerUserID ?? "").lowercased()) }
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

                BackendFeedStore.shared.endFetchSuccess(rawPosts: rawPosts, minePosts: sortedMine, allPosts: sortedAll)
                return .success(())
            } catch {
                BackendFeedStore.shared.endFetchFailure(error)
                return .failure(error)
            }

        case .failure(let e):
            BackendFeedStore.shared.endFetchFailure(e)
            return .failure(e)
        }
    }
}

public final class BackendEnvironment {
    public static let shared = BackendEnvironment()

    public var publish: BackendPublishService {
        let mode = currentBackendMode()
        let hasHTTPConfig = BackendConfig.isConfigured && (NetworkManager.shared.baseURL != nil)

        if mode == .backendPreview && hasHTTPConfig {
            return HTTPBackendPublishService()
        }
        return SimulatedPublishService()
    }

    public let profile: BackendProfileService
    public let follow: BackendFollowService

    private init() {
        self.profile = SimulatedProfileService()
        self.follow = SimulatedFollowService()
    }

    @inline(__always)
    public var mode: BackendMode { currentBackendMode() }

    @inline(__always)
    public var isPreview: Bool { mode == .backendPreview }
}

@inline(__always)
public func currentBackendMode() -> BackendMode {
    if let raw = UserDefaults.standard.string(forKey: BackendKeys.modeKey),
       let mode = BackendMode(rawValue: raw) {
        return mode
    }
    return .localSimulation
}
