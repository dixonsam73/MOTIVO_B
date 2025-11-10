// PublishService.swift
// CHANGE-ID: 20251110_190650-PublishService_v712A-MainActor
// SCOPE: v7.12A — Social Pilot (local-only). Main-actor updates to avoid cross-thread publishes.
// SEARCH-TOKEN: PUBLISH-SVC-712A

import Foundation
import CoreData
import Combine

/// Local-only publishing registry for v7.12A (no backend).
/// Stores a set of published session identifiers (objectID URI strings) per user.
/// Main-actor isolated to ensure @Published changes are always delivered from the main thread.
@MainActor
final class PublishService: ObservableObject {
    static let shared = PublishService()

    /// Published set for any future UI/diagnostics.
    @Published private(set) var publishedURIs: Set<String> = []

    /// The current user scope key (e.g., user UUID). Provided by app layer; falls back to device-local.
    var ownerKey: String {
        UserDefaults.standard.string(forKey: "PublishService.ownerKey") ?? "local-device"
    }

    /// Storage key composed with current ownerKey.
    private var storeKey: String { "publishedSessions_v1::" + ownerKey }

    private init() {
        load()
        NSLog("[PublishService] init — loaded %d published items (owner=%@)", publishedURIs.count, ownerKey)
    }

    // MARK: - Public API

    /// Publish or unpublish based on `shouldPublish`.
    /// - Parameters:
    ///   - objectID: The saved Core Data object ID for the session.
    ///   - shouldPublish: If true, record as published; if false, remove from registry.
    func publishIfNeeded(objectID: NSManagedObjectID, shouldPublish: Bool) {
        let uri = objectID.uriRepresentation().absoluteString

        var set = publishedURIs
        let changed: Bool
        if shouldPublish {
            changed = set.insert(uri).inserted
        } else {
            changed = set.remove(uri) != nil
        }
        guard changed else { return }

        // Persist first, then publish new value (all on main actor).
        persist(set)
        publishedURIs = set

        NSLog("[PublishService] %@ session → %@", shouldPublish ? "Published" : "Unpublished", uri)
    }

    func publish(objectID: NSManagedObjectID) {
        publishIfNeeded(objectID: objectID, shouldPublish: true)
    }

    func unpublish(objectID: NSManagedObjectID) {
        publishIfNeeded(objectID: objectID, shouldPublish: false)
    }

    /// Read-only query.
    func isPublished(objectID: NSManagedObjectID) -> Bool {
        let uri = objectID.uriRepresentation().absoluteString
        return publishedURIs.contains(uri)
    }

    // MARK: - Persistence

    private func load() {
        if let arr = UserDefaults.standard.array(forKey: storeKey) as? [String] {
            publishedURIs = Set(arr)
        } else {
            publishedURIs = []
        }
    }

    private func persist(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: storeKey)
    }

    // MARK: - Owner Scope

    /// Update the owner scope key (e.g., on login). Triggers a reload.
    func setOwnerKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "PublishService.ownerKey")
        load()
        NSLog("[PublishService] owner scope changed → %@ | published=%d", key, publishedURIs.count)
    }
}
