// CHANGE-ID: 20260121_124000_P13F_FollowStoreFollowersWire
// SCOPE: Phase 13F — Store followers set; refresh from backend; wire failure logging.
// SEARCH-TOKEN: 20260121_124000_P13F_FollowStoreFollowersWire

// CHANGE-ID: 20260121_121200_P13B1_FollowOptimisticRequestedState
// SCOPE: Phase 13B.1 — In HTTP backend modes, flip ProfilePeek follow state to "Request sent" immediately on tap by optimistic outgoingRequests insert; rollback on failure.
// SEARCH-TOKEN: 20260121_121200_P13B1_FollowOptimisticRequestedState
//
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

// CHANGE-ID: 20260128_193300_14_3A_FollowStore_RemoveManualObjectWillChange
// SCOPE: Phase 14.3A — FollowStore: remove manual objectWillChange.send() calls; rely on @Published + load() refresh to avoid background-thread publish warnings; no UI/layout changes.
// SEARCH-TOKEN: 20260128_193300_14_3A_FollowStore_RemoveManualObjectWillChange
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
    @Published private(set) public var followers: Set<String> = []
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

    private var isBackendHTTPActive: Bool {
        BackendEnvironment.shared.isHTTPEnabled
    }

    /// Refresh follow state from backend when the HTTP backend is enabled.
    /// No-op in Local Simulation.
    @MainActor
    public func refreshFromBackendIfPossible() async {
        guard isBackendHTTPActive else { return }
        let follow = BackendEnvironment.shared.follow

        // Approved outgoing follows = "following"
        let followingResult = await follow.fetchFollowingApproved()
        // Approved incoming follows = "followers"
        let followersResult = await follow.fetchFollowersApproved()
        // Incoming requests = "requests" (people who want to follow me)
        let incomingResult = await follow.fetchIncomingRequests()
        // Outgoing requests = "outgoingRequests" (people I asked to follow)
        let outgoingResult = await follow.fetchOutgoingRequests()

        switch (followingResult, followersResult, incomingResult, outgoingResult) {
        case (.success(let followingIDs), .success(let followerIDs), .success(let incomingIDs), .success(let outgoingIDs)):
            // Backend is source of truth when HTTP backend is enabled — do not persist to UserDefaults.
            self.following = Set(followingIDs.map { $0.lowercased() })
            self.followers = Set(followerIDs.map { $0.lowercased() })
            self.requests = Set(incomingIDs.map { $0.lowercased() })
            self.outgoingRequests = Set(outgoingIDs.map { $0.lowercased() })
            NSLog("[FollowStore] backend refresh ok (following=%d followers=%d incoming=%d outgoing=%d)",
                  self.following.count, self.followers.count, self.requests.count, self.outgoingRequests.count)

        case (.failure(let e), _, _, _):
            NSLog("[FollowStore] backend refresh failed (following): %@", String(describing: e))

        case (_, .failure(let e), _, _):
            NSLog("[FollowStore] backend refresh failed (followers): %@", String(describing: e))

        case (_, _, .failure(let e), _):
            NSLog("[FollowStore] backend refresh failed (incoming): %@", String(describing: e))

        case (_, _, _, .failure(let e)):
            NSLog("[FollowStore] backend refresh failed (outgoing): %@", String(describing: e))
        }
    }

    // MARK: - Public API (Simulation Layer)

    @discardableResult
    public func requestFollow(to targetUserID: String) -> FollowState {
        if isBackendHTTPActive {
            // Optimistic UI: flip to "requested" immediately.
            // Backend refresh will confirm/correct state, but we want instant feedback on tap.
            let normalized = targetUserID.lowercased()
            self.outgoingRequests.insert(normalized)

            Task { @MainActor in
                let result = await BackendEnvironment.shared.follow.requestFollow(to: targetUserID)
                switch result {
                case .success:
                    await self.refreshFromBackendIfPossible()
                case .failure(let e):
                    // Roll back optimistic state on failure.
                    self.outgoingRequests.remove(normalized)
                    NSLog("[FollowStore] backend requestFollow failed: %@", String(describing: e))
                }
            }
            return .requested
        }

        // Local simulation: requesting to follow someone is an OUTGOING request.
        outgoingRequests.insert(targetUserID)
        save()
        NSLog("[FollowStore] request → %@", targetUserID)
        return .requested
    }

    @discardableResult
    public func approveFollow(from requesterUserID: String) -> FollowState {
        if isBackendHTTPActive {
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
        NSLog("[FollowStore] approve ← %@", requesterUserID)
        return .following
    }

    @discardableResult
    public func declineFollow(from requesterUserID: String) -> FollowState {
        if isBackendHTTPActive {
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
        NSLog("[FollowStore] decline ← %@", requesterUserID)
        return .none
    }

    @discardableResult
    public func unfollow(_ targetUserID: String) -> FollowState {
        if isBackendHTTPActive {
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
        load()
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
        load()
        UserDefaults.standard.set(Array(fol), forKey: _followingKey)
        load()
        NSLog("[FollowStore] simulateAcceptFollow ← %@", requesterUserID)
        return .following
    }

    @discardableResult
    public func simulateUnfollow(_ targetUserID: String) -> FollowState {
        var fol = Set(UserDefaults.standard.stringArray(forKey: _followingKey) ?? [])
        fol.remove(targetUserID)
        UserDefaults.standard.set(Array(fol), forKey: _followingKey)
        load()
        load()
        NSLog("[FollowStore] simulateUnfollow × %@", targetUserID)
        return .none
    }

    #if DEBUG
    /// DEBUG: Force-reload FollowStore for the active viewer (applies override if set).
    /// Ensures dummy identities actually switch follow/request sets.
    public func debugReload() {
        load()
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
