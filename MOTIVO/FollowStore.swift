// CHANGE-ID: 20260116_223900_Phase10C_FollowOutgoingRequestsFix
// SCOPE: Phase 10C hardening — separate outgoing follow requests from incoming requests in local simulation.
// SEARCH-TOKEN: 20260116_223900_Phase10C_FollowOutgoingRequestsFix
//
// CHANGE-ID: 20260112_140516_Step9B_BackendFollowGraph
// SCOPE: Step 9B — Route FollowStore through backend follow service when in Backend Preview; keep local simulation unchanged.
// SEARCH-TOKEN: 20260112_140516_Step9B_BackendFollowGraph
//
// CHANGE-ID: v7.13A-FollowStore-DummyIdentities-20251201_1715
// SCOPE: Social Hardening — Dummy identities (local-device, user_B, user_C)
// Fixes: FollowStore now reloads follow/request sets after identity override.

import Foundation
import Combine

@MainActor
public final class FollowStore: ObservableObject {

    // MARK: - Singleton

    public static let shared = FollowStore()
    private init() {
        load()
    }

    // MARK: - Published Properties

    @Published private(set) public var following: Set<String> = []
    @Published private(set) public var requests: Set<String> = []              // incoming requests (people who want to follow me)
    @Published private(set) public var outgoingRequests: Set<String> = []      // outgoing requests (I asked to follow them)

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Core Data / Persistence Identity

    /// Returns the current user ID for follow maps.
    /// In DEBUG, respects Debug.currentUserIDOverride so each dummy identity
    /// (local-device, user_B, user_C) gets its own follow set.
    private var currentUserID: String {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "Debug.currentUserIDOverride"),
           !override.isEmpty {
            return override
        }
        #endif
        return (try? PersistenceController.shared.currentUserID) ?? "local-device"
    }

    // MARK: - Local UserDefaults Keys

    private var _followingKey: String { "FollowStore.following::\(currentUserID)" }
    private var _requestsKey: String { "FollowStore.requests::\(currentUserID)" }
    private var _outgoingRequestsKey: String { "FollowStore.outgoingRequests::\(currentUserID)" }

    // MARK: - Load / Save

    private func load() {
        let followArray = UserDefaults.standard.stringArray(forKey: _followingKey) ?? []
        let requestArray = UserDefaults.standard.stringArray(forKey: _requestsKey) ?? []
        let outgoingArray = UserDefaults.standard.stringArray(forKey: _outgoingRequestsKey) ?? []

        following = Set(followArray)
        requests = Set(requestArray)
        outgoingRequests = Set(outgoingArray)
    }

    private func save() {
        UserDefaults.standard.set(Array(following), forKey: _followingKey)
        UserDefaults.standard.set(Array(requests), forKey: _requestsKey)
        UserDefaults.standard.set(Array(outgoingRequests), forKey: _outgoingRequestsKey)
    }

    // MARK: - Backend Preview (Step 9B)

    private var isBackendPreviewActive: Bool {
        BackendEnvironment.shared.isPreview &&
        BackendConfig.isConfigured &&
        (NetworkManager.shared.baseURL != nil)
    }

    /// Refresh follow state from backend if we're in Backend Preview and configured.
    /// No-op in Local Simulation.
    @MainActor
    public func refreshFromBackendIfPossible() async {
        guard isBackendPreviewActive else { return }
        let follow = BackendEnvironment.shared.follow

        // Approved outgoing follows = "following"
        let followingResult = await follow.fetchFollowingApproved()
        // Incoming requests = "requests" (people who want to follow me)
        let incomingResult = await follow.fetchIncomingRequests()

        switch (followingResult, incomingResult) {
        case (.success(let followingIDs), .success(let incomingIDs)):
            // Backend is source of truth in preview — do not persist to UserDefaults.
            self.following = Set(followingIDs.map { $0.lowercased() })
            self.requests = Set(incomingIDs.map { $0.lowercased() })
            // Outgoing requests are not yet fetched in preview mode (backend wiring later).
            self.outgoingRequests = []
            objectWillChange.send()
            NSLog("[FollowStore] backend refresh ok (following=%d requests=%d)", self.following.count, self.requests.count)

        case (.failure(let e), _):
            NSLog("[FollowStore] backend refresh failed (following): %@", String(describing: e))

        case (_, .failure(let e)):
            NSLog("[FollowStore] backend refresh failed (incoming): %@", String(describing: e))
        }
    }

    // MARK: - Public API (Simulation Layer)

    @discardableResult
    public func requestFollow(to targetUserID: String) -> FollowState {
        if isBackendPreviewActive {
            Task { @MainActor in
                let result = await BackendEnvironment.shared.follow.requestFollow(to: targetUserID)
                switch result {
                case .success:
                    await self.refreshFromBackendIfPossible()
                case .failure(let e):
                    NSLog("[FollowStore] backend requestFollow failed: %@", String(describing: e))
                }
            }
            return .requested
        }

        // Local simulation: requesting to follow someone is an OUTGOING request.
        outgoingRequests.insert(targetUserID)
        save()
        objectWillChange.send()
        NSLog("[FollowStore] request → %@", targetUserID)
        return .requested
    }

    @discardableResult
    public func approveFollow(from requesterUserID: String) -> FollowState {
        if isBackendPreviewActive {
            Task { @MainActor in
                let result = await BackendEnvironment.shared.follow.approveFollow(from: requesterUserID)
                switch result {
                case .success:
                    await self.refreshFromBackendIfPossible()
                case .failure(let e):
                    NSLog("[FollowStore] backend approveFollow failed: %@", String(describing: e))
                }
            }
            return .following
        }

        // Local simulation: approving someone means accepting an INCOMING request.
        requests.remove(requesterUserID)
        following.insert(requesterUserID)
        save()
        objectWillChange.send()
        NSLog("[FollowStore] approve ← %@", requesterUserID)
        return .following
    }

    @discardableResult
    public func declineFollow(from requesterUserID: String) -> FollowState {
        if isBackendPreviewActive {
            Task { @MainActor in
                let result = await BackendEnvironment.shared.follow.declineFollow(from: requesterUserID)
                switch result {
                case .success:
                    await self.refreshFromBackendIfPossible()
                case .failure(let e):
                    NSLog("[FollowStore] backend declineFollow failed: %@", String(describing: e))
                }
            }
            return .none
        }

        requests.remove(requesterUserID)
        save()
        objectWillChange.send()
        NSLog("[FollowStore] decline ← %@", requesterUserID)
        return .none
    }

    @discardableResult
    public func unfollow(_ targetUserID: String) -> FollowState {
        if isBackendPreviewActive {
            Task { @MainActor in
                let result = await BackendEnvironment.shared.follow.unfollow(targetUserID)
                switch result {
                case .success:
                    await self.refreshFromBackendIfPossible()
                case .failure(let e):
                    NSLog("[FollowStore] backend unfollow failed: %@", String(describing: e))
                }
            }
            return .none
        }

        following.remove(targetUserID)
        // If we unfollow in local sim, also clear any outgoing request record to keep UI coherent.
        outgoingRequests.remove(targetUserID)
        save()
        objectWillChange.send()
        NSLog("[FollowStore] unfollow × %@", targetUserID)
        return .none
    }

    // MARK: - State Query

    /// Relationship state from the active viewer → target.
    /// IMPORTANT: incoming requests do NOT mean I have requested them.
    public func state(for targetUserID: String) -> FollowState {
        if following.contains(targetUserID) { return .following }
        if outgoingRequests.contains(targetUserID) { return .requested }
        return .none
    }

    public func followingIDs() -> [String] {
        Array(following)
    }

    // MARK: - Debug Utilities

    #if DEBUG
    public func _debug_resetLocalFollows() {
        UserDefaults.standard.removeObject(forKey: _followingKey)
        UserDefaults.standard.removeObject(forKey: _requestsKey)
        UserDefaults.standard.removeObject(forKey: _outgoingRequestsKey)
        following.removeAll()
        requests.removeAll()
        outgoingRequests.removeAll()
        objectWillChange.send()
        NSLog("[FollowStore] DEBUG reset local follows")
    }
    #endif
}

// MARK: - Enum

public enum FollowState: String, Codable {
    case none
    case requested
    case following
}

// MARK: - Local Simulation Extension

extension FollowStore {

    /// Simulate an INCOMING request (someone wants to follow me).
    @discardableResult
    public func simulateRequestFollow(to targetUserID: String) -> FollowState {
        var reqs = Set(UserDefaults.standard.stringArray(forKey: _requestsKey) ?? [])
        reqs.insert(targetUserID)
        UserDefaults.standard.set(Array(reqs), forKey: _requestsKey)
        objectWillChange.send()
        NSLog("[FollowStore] simulateRequestFollow → %@", targetUserID)
        return .requested
    }

    @discardableResult
    public func simulateAcceptFollow(from requesterUserID: String) -> FollowState {
        var reqs = Set(UserDefaults.standard.stringArray(forKey: _requestsKey) ?? [])
        var fol = Set(UserDefaults.standard.stringArray(forKey: _followingKey) ?? [])
        reqs.remove(requesterUserID)
        fol.insert(requesterUserID)
        UserDefaults.standard.set(Array(reqs), forKey: _requestsKey)
        UserDefaults.standard.set(Array(fol), forKey: _followingKey)
        objectWillChange.send()
        NSLog("[FollowStore] simulateAcceptFollow ← %@", requesterUserID)
        return .following
    }

    @discardableResult
    public func simulateUnfollow(_ targetUserID: String) -> FollowState {
        var fol = Set(UserDefaults.standard.stringArray(forKey: _followingKey) ?? [])
        fol.remove(targetUserID)
        UserDefaults.standard.set(Array(fol), forKey: _followingKey)
        objectWillChange.send()
        NSLog("[FollowStore] simulateUnfollow × %@", targetUserID)
        return .none
    }

    #if DEBUG
    /// DEBUG: Force-reload FollowStore for the active viewer (applies override if set).
    /// Ensures dummy identities actually switch follow/request sets.
    public func debugReload() {
        load()
        objectWillChange.send()
        NSLog("[FollowStore] debugReload → active user = %@", currentUserID)
    }
    #endif

    /// Returns true if the active viewer is following the given user ID.
    public func isFollowing(_ targetUserID: String) -> Bool {
        let set = Set(UserDefaults.standard.stringArray(forKey: _followingKey) ?? [])
        return set.contains(targetUserID)
    }

    /// Returns the current following set for the active viewer.
    public func followingSet() -> Set<String> {
        return Set(UserDefaults.standard.stringArray(forKey: _followingKey) ?? [])
    }
}
