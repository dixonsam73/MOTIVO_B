//
// CHANGE-ID: 20251230_224600_Step7_BackendShim_ModeVisibilityFix
// SCOPE: Step 7 — Restore public currentBackendMode() visibility for existing UI/debug callers; keep BackendKeys/setBackendMode shim; keep JSON body encoding; no behavioral changes beyond fixing cross-file symbol visibility
// SEARCH-TOKEN: 20251230_224600_Step7_BackendShim_ModeVisibilityFix
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

// MARK: - Backend Services Protocols (Step 6A preview contract)

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

// MARK: - HTTP Publish Service (Step 7)

public final class HTTPBackendPublishService: BackendPublishService {
    public init() {}

    @MainActor
    public func uploadPost(_ postID: UUID) async -> Result<Void, Error> {
        // Supabase PostgREST insert into public.posts
        // Requires: NetworkManager bearer token set (Authorization: Bearer <access_token>)
        // Also requires: apikey header (publishable key) for the project

        guard let apiKey = BackendConfig.apiToken, !apiKey.isEmpty else {
            return .failure(NSError(domain: "Backend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing API key"]))
        }

        // Owner should be the Supabase auth user UUID string stored by AuthManager,
        // but we fall back to backendUserID_v1 for safety.
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

        let headers: [String: String] = [
            "apikey": apiKey,
            "Prefer": "return=minimal",
            "Content-Type": "application/json"
        ]

        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            return .failure(error)
        }

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
        await BackendDiagnostics.shared.simulatedCall("HTTPBackendPublishService.fetchFeed", meta: ["scope": scope])
        return .success(())
    }
}

// MARK: - Backend Environment

public final class BackendEnvironment {
    public static let shared = BackendEnvironment()

    // Note: publish service selection is intentionally *dynamic* so that switching
    // Backend Mode or applying BackendConfig does not require an app relaunch.
    public var publish: BackendPublishService {
        let mode = currentBackendMode()

        // Option B (Step 7): "Backend Preview" becomes real HTTP when configured.
        let hasHTTPConfig = BackendConfig.isConfigured && (NetworkManager.shared.baseURL != nil)

        if mode == .backendPreview && hasHTTPConfig {
            return HTTPBackendPublishService()
        }

        return SimulatedPublishService()
    }

    public let profile: BackendProfileService
    public let follow: BackendFollowService

    private init() {
        // Profile/follow remain simulated for Step 7.
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
