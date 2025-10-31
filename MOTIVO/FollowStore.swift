//
//  FollowStore.swift
//  MOTIVO
//
//  Created by ChatGPT on 2025-10-31 13:31:45 UTC
//
//  CHANGE-ID: v710H-FollowStore-20251031_133145
//  SCOPE: Local-first follow relationships (requests/approvals/blocks) for All/Mine gating.
//
//  Overview:
//  - Local-only, no backend. Persisted via UserDefaults ("follow.store.v1").
//  - Models 'Follow' relationships from the *viewer/owner* to *target* users.
//  - Enables feed gating (All = owner + approved follows; Mine = owner only).
//  - UI-agnostic. Callers provide the owner/viewer ID explicitly.
//
//  Invariants:
//  - No Core Data or schema changes.
//  - No networking or contacts access.
//  - Purely additive. Does not modify existing files.
//

import Foundation
import Combine

// MARK: - Types

public enum FollowStatus: String, Codable, CaseIterable { case pending, approved, blocked }
public enum FollowSource: String, Codable, CaseIterable { case manual, contacts, search }

public struct FollowRelation: Codable, Hashable, Identifiable { // owner -> target
    public var id: String { "\(ownerID)::\(targetID)" }
    public let ownerID: String         // the viewer/owner initiating the follow
    public let targetID: String        // who the owner wants to follow
    public var status: FollowStatus    // pending / approved / blocked
    public var source: FollowSource    // manual / contacts / search
    public var createdAt: Date
    public var updatedAt: Date
}

// MARK: - FollowStore (local-first)

@MainActor
public final class FollowStore: ObservableObject { // UI layer can observe changes
    public static let shared = FollowStore()
    
    private let storageKey = "follow.store.v1"
    @Published private(set) public var relations: [FollowRelation] = [] // all owner->target relations
    
    private init() {
        load()
    }
    
    // MARK: Persistence
    
    private func load() {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([FollowRelation].self, from: data)
            self.relations = decoded
        } catch {
            // If decoding fails, do not crash—start fresh
            self.relations = []
        }
    }
    
    private func save() {
        let defaults = UserDefaults.standard
        do {
            let data = try JSONEncoder().encode(relations)
            defaults.set(data, forKey: storageKey)
        } catch {
            // ignore write errors in local mode
        }
    }
    
    // MARK: Query helpers
    
    /// Return the current status between owner and target, if any.
    public func status(ownerID: String, targetID: String) -> FollowStatus? {
        relations.first(where: { $0.ownerID == ownerID && $0.targetID == targetID })?.status
    }
    
    /// All approved target IDs for the given owner/viewer.
    public func approvedIDs(for ownerID: String) -> [String] {
        relations.filter { $0.ownerID == ownerID && $0.status == .approved }.map { $0.targetID }
    }
    
    /// Pending requests the owner has initiated.
    public func pendingTargets(for ownerID: String) -> [String] {
        relations.filter { $0.ownerID == ownerID && $0.status == .pending }.map { $0.targetID }
    }
    
    /// All relations for a given owner (useful for inbox UI).
    public func relations(for ownerID: String) -> [FollowRelation] {
        relations.filter { $0.ownerID == ownerID }
    }
    
    // MARK: Mutations (owner acts on own outbound follows)
    
    /// Create a follow *request* (owner -> target). If exists, updates status/source.
    public func requestFollow(ownerID: String, targetID: String, source: FollowSource = .manual) {
        guard ownerID != targetID else { return } // no self-follow
        let now = Date()
        if let idx = relations.firstIndex(where: { $0.ownerID == ownerID && $0.targetID == targetID }) {
            // if blocked, keep blocked; otherwise set to pending
            if relations[idx].status != .blocked {
                relations[idx].status = .pending
                relations[idx].source = source
                relations[idx].updatedAt = now
                save()
                objectWillChange.send()
            }
            return
        }
        let rel = FollowRelation(ownerID: ownerID, targetID: targetID, status: .pending, source: source, createdAt: now, updatedAt: now)
        relations.append(rel)
        save()
        objectWillChange.send()
    }
    
    /// Approve a follow (owner -> target). Typically used when owner accepts an inbound request in a backend scenario.
    /// In local-first, this is used to model "I now follow target".
    public func approve(ownerID: String, targetID: String) {
        let now = Date()
        if let idx = relations.firstIndex(where: { $0.ownerID == ownerID && $0.targetID == targetID }) {
            relations[idx].status = .approved
            relations[idx].updatedAt = now
        } else {
            let rel = FollowRelation(ownerID: ownerID, targetID: targetID, status: .approved, source: .manual, createdAt: now, updatedAt: now)
            relations.append(rel)
        }
        save()
        objectWillChange.send()
    }
    
    /// Decline (or cancel) a pending follow request (removes relation if pending; otherwise no-op).
    public func decline(ownerID: String, targetID: String) {
        if let idx = relations.firstIndex(where: { $0.ownerID == ownerID && $0.targetID == targetID }) {
            if relations[idx].status == .pending {
                relations.remove(at: idx)
                save()
                objectWillChange.send()
            }
        }
    }
    
    /// Unfollow a previously approved relation.
    public func unfollow(ownerID: String, targetID: String) {
        if let idx = relations.firstIndex(where: { $0.ownerID == ownerID && $0.targetID == targetID }) {
            relations.remove(at: idx)
            save()
            objectWillChange.send()
        }
    }
    
    /// Block a target (prevents future suggestions; wins over other states).
    public func block(ownerID: String, targetID: String) {
        let now = Date()
        if let idx = relations.firstIndex(where: { $0.ownerID == ownerID && $0.targetID == targetID }) {
            relations[idx].status = .blocked
            relations[idx].updatedAt = now
        } else {
            let rel = FollowRelation(ownerID: ownerID, targetID: targetID, status: .blocked, source: .manual, createdAt: now, updatedAt: now)
            relations.append(rel)
        }
        save()
        objectWillChange.send()
    }
    
    /// Unblock reverts to no relation (caller can then request again if needed).
    public func unblock(ownerID: String, targetID: String) {
        if let idx = relations.firstIndex(where: { $0.ownerID == ownerID && $0.targetID == targetID }) {
            relations.remove(at: idx)
            save()
            objectWillChange.send()
        }
    }
    
    // MARK: Utilities
    
    /// Returns true if owner can see target's content given an approved follow.
    public func canSee(ownerID: String, targetID: String) -> Bool {
        return approvedIDs(for: ownerID).contains(targetID) || ownerID == targetID
    }
}
