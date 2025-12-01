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
    @Published private(set) public var requests: Set<String> = []

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

    // MARK: - Load / Save

    private func load() {
        let followArray = UserDefaults.standard.stringArray(forKey: _followingKey) ?? []
        let requestArray = UserDefaults.standard.stringArray(forKey: _requestsKey) ?? []
        following = Set(followArray)
        requests = Set(requestArray)
    }

    private func save() {
        UserDefaults.standard.set(Array(following), forKey: _followingKey)
        UserDefaults.standard.set(Array(requests), forKey: _requestsKey)
    }

    // MARK: - Public API (Simulation Layer)

    @discardableResult
    public func requestFollow(to targetUserID: String) -> FollowState {
        requests.insert(targetUserID)
        save()
        objectWillChange.send()
        NSLog("[FollowStore] request → %@", targetUserID)
        return .requested
    }

    @discardableResult
    public func approveFollow(from requesterUserID: String) -> FollowState {
        requests.remove(requesterUserID)
        following.insert(requesterUserID)
        save()
        objectWillChange.send()
        NSLog("[FollowStore] approve ← %@", requesterUserID)
        return .following
    }

    @discardableResult
    public func declineFollow(from requesterUserID: String) -> FollowState {
        requests.remove(requesterUserID)
        save()
        objectWillChange.send()
        NSLog("[FollowStore] decline ← %@", requesterUserID)
        return .none
    }

    @discardableResult
    public func unfollow(_ targetUserID: String) -> FollowState {
        following.remove(targetUserID)
        save()
        objectWillChange.send()
        NSLog("[FollowStore] unfollow × %@", targetUserID)
        return .none
    }

    // MARK: - State Query

    public func state(for targetUserID: String) -> FollowState {
        if following.contains(targetUserID) { return .following }
        if requests.contains(targetUserID) { return .requested }
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
        following.removeAll()
        requests.removeAll()
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
