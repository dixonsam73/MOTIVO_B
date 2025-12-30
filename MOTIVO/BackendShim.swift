//
// CHANGE-ID: step-6A-http-publish
// SCOPE: Add HTTPBackendPublishService and wire into backendPreview selection
//

//
//  BackendShim.swift
//  MOTIVO
//
//  CHANGE-ID: 20251112-BackendShim-a1b2-fix1
//  SCOPE: v7.12C — Backend Handshake + API Shims (additive, offline)
//

import Foundation

// MARK: - Backend Mode

public enum BackendMode: String, CaseIterable, Codable {
    case localSimulation = "local"
    case backendPreview  = "preview"
}

public enum BackendKeys {
    public static let modeKey = "backendMode_v1"
}

@inline(__always)
public func currentBackendMode() -> BackendMode {
    let raw = (UserDefaults.standard.string(forKey: BackendKeys.modeKey) ?? BackendMode.localSimulation.rawValue)
    return BackendMode(rawValue: raw) ?? .localSimulation
}

@inline(__always)
public func setBackendMode(_ mode: BackendMode) {
    UserDefaults.standard.set(mode.rawValue, forKey: BackendKeys.modeKey)
}

// MARK: - Shim Protocols (namespaced to avoid collisions)

public protocol BackendPublishService {
    @MainActor
    func uploadPost(_ postID: UUID) async -> Result<Void, Error>
    @MainActor
    func updatePost(_ postID: UUID) async -> Result<Void, Error>
    @MainActor
    func deletePost(_ postID: UUID) async -> Result<Void, Error>
    @MainActor
    func fetchFeed(scope: String) async -> Result<Void, Error>
}

public protocol BackendProfileService {
    @MainActor
    func fetchProfile(userID: String) async -> Result<Void, Error>
    @MainActor
    func updateProfile(userID: String) async -> Result<Void, Error>
}

public protocol BackendFollowService {
    @MainActor
    func sendRequest(to userID: String) async -> Result<Void, Error>
    @MainActor
    func acceptRequest(from userID: String) async -> Result<Void, Error>
    @MainActor
    func removeFollow(userID: String) async -> Result<Void, Error>
    @MainActor
    func fetchRelations(for userID: String) async -> Result<Void, Error>
}

// MARK: - Simulated Implementations

public enum BackendSimError: Error {
    case simulatedFailure
}

public final class SimulatedPublishService: BackendPublishService {
    public init() {}
    @MainActor
    public func uploadPost(_ postID: UUID) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("PublishService.uploadPost", meta: ["postID": postID.uuidString])
        return .success(())
    }
    @MainActor
    public func updatePost(_ postID: UUID) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("PublishService.updatePost", meta: ["postID": postID.uuidString])
        return .success(())
    }
    @MainActor
    public func deletePost(_ postID: UUID) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("PublishService.deletePost", meta: ["postID": postID.uuidString])
        return .success(())
    }
    @MainActor
    public func fetchFeed(scope: String) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("PublishService.fetchFeed", meta: ["scope": scope])
        return .success(())
    }
}

public final class HTTPBackendPublishService: BackendPublishService {
    public init() {}

    @MainActor
    public func uploadPost(_ postID: UUID) async -> Result<Void, Error> {
        let path = "v1/publish/\(postID.uuidString)"
        let result = await NetworkManager.shared.request(
            path: path,
            method: "POST",
            query: nil,
            jsonBody: nil
        )
        switch result {
        case .success:
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    @MainActor
    public func updatePost(_ postID: UUID) async -> Result<Void, Error> {
        // Not part of Step 6A contract yet; keep simulated behavior
        await BackendDiagnostics.shared.simulatedCall("HTTPBackendPublishService.updatePost", meta: ["postID": postID.uuidString])
        return .success(())
    }

    @MainActor
    public func deletePost(_ postID: UUID) async -> Result<Void, Error> {
        let path = "v1/publish/\(postID.uuidString)"
        let result = await NetworkManager.shared.request(
            path: path,
            method: "DELETE",
            query: nil,
            jsonBody: nil
        )
        switch result {
        case .success:
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    @MainActor
    public func fetchFeed(scope: String) async -> Result<Void, Error> {
        // Not part of Step 6A contract yet; keep simulated behavior
        await BackendDiagnostics.shared.simulatedCall("HTTPBackendPublishService.fetchFeed", meta: ["scope": scope])
        return .success(())
    }
}

public final class SimulatedProfileService: BackendProfileService {
    public init() {}
    @MainActor
    public func fetchProfile(userID: String) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("ProfileService.fetchProfile", meta: ["userID": userID])
        return .success(())
    }
    @MainActor
    public func updateProfile(userID: String) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("ProfileService.updateProfile", meta: ["userID": userID])
        return .success(())
    }
}

public final class SimulatedFollowService: BackendFollowService {
    public init() {}
    @MainActor
    public func sendRequest(to userID: String) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("FollowService.sendRequest", meta: ["to": userID])
        return .success(())
    }
    @MainActor
    public func acceptRequest(from userID: String) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("FollowService.acceptRequest", meta: ["from": userID])
        return .success(())
    }
    @MainActor
    public func removeFollow(userID: String) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("FollowService.removeFollow", meta: ["userID": userID])
        return .success(())
    }
    @MainActor
    public func fetchRelations(for userID: String) async -> Result<Void, Error> {
        await BackendDiagnostics.shared.simulatedCall("FollowService.fetchRelations", meta: ["for": userID])
        return .success(())
    }
}

// MARK: - Backend Environment

public final class BackendEnvironment {
    public static let shared = BackendEnvironment()
    public let publish: BackendPublishService
    public let profile: BackendProfileService
    public let follow: BackendFollowService

    private init() {
        // All simulated by default. Real services can be swapped in later.
        let hasConfig = (NetworkManager.shared.baseURL != nil)
        let mode = currentBackendMode()
        if mode == .backendPreview && hasConfig {
            self.publish = HTTPBackendPublishService()
        } else {
            self.publish = SimulatedPublishService()
        }
        self.profile = SimulatedProfileService()
        self.follow  = SimulatedFollowService()
    }

    @inline(__always)
    public var mode: BackendMode { currentBackendMode() }

    @inline(__always)
    public var isPreview: Bool { mode == .backendPreview }
}

