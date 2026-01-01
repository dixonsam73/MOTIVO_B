//
// CHANGE-ID: 20260101_124700_Step8A_BackendFeedFetch_PathQueryFix
// SCOPE: Step 8A — Fix feed fetch URL construction by removing query string from path; filter/sort Mine client-side; debug-store only.
// SEARCH-TOKEN: 20260101_124700_Step8A_BackendFeedFetch_PathQueryFix
//

import Foundation
import SwiftUI

// MARK: - BackendKeys + Mode Setter (compat for BackendModeSection)

public enum BackendKeys {
    public static let modeKey = "backendMode_v1"
}

@inline(__always)
public func setBackendMode(_ mode: BackendMode) {
    UserDefaults.standard.set(mode.rawValue, forKey: BackendKeys.modeKey)
}

// MARK: - Backend Mode

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

// MARK: - Backend Feed Models (Step 8A)

/// Minimal representation of a Supabase `public.posts` row for debug feed fetch.
/// Keep fields optional/loose to avoid schema coupling.
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

/// Debug-only in-memory store for fetched backend posts.
/// Intentionally not persisted (no Core Data / no disk writes).
@MainActor
public final class BackendFeedStore: ObservableObject {
    public static let shared = BackendFeedStore()

    @Published public private(set) var minePosts: [BackendPost] = []
    @Published public private(set) var isFetching: Bool = false
    @Published public private(set) var lastError: String? = nil
    @Published public private(set) var lastFetchAt: Date? = nil
    @Published public private(set) var lastFetchCount: Int = 0

    private init() {}

    public func beginFetch() {
        isFetching = true
        lastError = nil
    }

    public func endFetchSuccess(posts: [BackendPost]) {
        minePosts = posts
        lastFetchCount = posts.count
        lastFetchAt = Date()
        isFetching = false
        lastError = nil
    }

    public func endFetchFailure(_ error: Error) {
        isFetching = false
        lastError = error.localizedDescription
    }
}

// MARK: - Backend Services Protocols (preview contract)

public protocol BackendPublishService {
    func uploadPost(_ postID: UUID) async -> Result<Void, Error>
    func deletePost(_ postID: UUID) async -> Result<Void, Error>
    func updatePost(_ postID: UUID) async -> Result<Void, Error>
    func fetchFeed(scope: String) async -> Result<Void, Error>
}

public protocol BackendProfileService {}
public protocol BackendFollowService {}

// MARK: - Simulated Services

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

public final class SimulatedProfileService: BackendProfileService {
    public init() {}
}

public final class SimulatedFollowService: BackendFollowService {
    public init() {}
}

// MARK: - HTTP Publish Service (Supabase PostgREST)

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

        // NOTE: delete endpoint here is unchanged; if NetworkManager path-encodes '?',
        // this may also need the same treatment later. For Step 8A we are fixing feed fetch first.
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
        // Step 8A: Mine-only debug fetch
        let normalized = scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized == "mine" else {
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

        BackendFeedStore.shared.beginFetch()

        // CRITICAL FIX:
        // Do NOT embed "?select=..." in `path:` because NetworkManager path-encodes it (turns "?" into "%3F").
        // Fetch the collection via a clean path, then Mine-filter + sort client-side for Step 8A.
        let headers: [String: String] = [
            "apikey": apiKey,
            "Accept": "application/json"
        ]

        let result = await NetworkManager.shared.request(
            path: "rest/v1/posts",
            method: "GET",
            query: nil,
            jsonBody: nil,
            headers: headers
        )

        switch result {
        case .success(let data):
            do {
                let decoder = JSONDecoder()
                let posts = try decoder.decode([BackendPost].self, from: data)

                // Mine filter (defensive even if RLS already restricts)
                let ownerLower = owner.lowercased()
                let mine = posts.filter { ($0.ownerUserID ?? "").lowercased() == ownerLower }

                // Best-effort sort by created_at desc
                let iso = ISO8601DateFormatter()
                let sorted = mine.sorted { a, b in
                    let da = a.createdAt.flatMap { iso.date(from: $0) } ?? Date.distantPast
                    let db = b.createdAt.flatMap { iso.date(from: $0) } ?? Date.distantPast
                    return da > db
                }

                BackendFeedStore.shared.endFetchSuccess(posts: sorted)
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

// MARK: - Backend Environment

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

    // Compatibility shim — required by existing green files
    @inline(__always)
    public var isPreview: Bool { mode == .backendPreview }
}

// MARK: - Backend Mode Resolution (MUST be public for other files)

@inline(__always)
public func currentBackendMode() -> BackendMode {
    if let raw = UserDefaults.standard.string(forKey: BackendKeys.modeKey),
       let mode = BackendMode(rawValue: raw) {
        return mode
    }
    return .localSimulation
}
