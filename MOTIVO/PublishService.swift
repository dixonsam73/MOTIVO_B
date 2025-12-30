// CHANGE-ID: 20251230_6A-PublishService-SessionIDOverload
// SCOPE: Step 6A — add sessionID overload; make local-only default; remove heuristics
// CHANGE-ID: 20251230_6A-PublishService-PreviewBackend
// CHANGE-ID: 20251230_210900-PublishService-NSLogPreviewGate
// SCOPE: Step 7 — add explicit logs for preview gate + ensure flush is attempted
// SCOPE: Step 6A — backend preview wiring for publish/unpublish (non-blocking)
// CHANGE-ID: v7.12B-PublishService-DebugGlobal-20251112_133247
// SCOPE: Add DEBUG helper to read other owners' published sets
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

    /// Overload with explicit sessionID for backend preview wiring.
    /// Performs the same local registry update, then (in preview) enqueues or deletes via backend using the provided sessionID.
    func publishIfNeeded(objectID: NSManagedObjectID, sessionID: UUID, shouldPublish: Bool) {
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

        // Step 6A: Preview-only backend wiring (non-blocking) using explicit sessionID.
        Task { @MainActor in
            let mode = BackendEnvironment.shared.mode
            let hasBaseURL = (NetworkManager.shared.baseURL != nil)
            let configured = BackendConfig.isConfigured
            NSLog("[PublishService] preview-gate check • mode=%@ • hasBaseURL=%@ • isConfigured=%@", String(describing: mode), String(describing: hasBaseURL), String(describing: configured))
            if (mode == .backendPreview) && hasBaseURL && configured {
                if shouldPublish {
                    SessionSyncQueue.shared.enqueue(postID: sessionID)
                    await SessionSyncQueue.shared.flushNow()
                    NSLog("[PublishService] Preview enqueue + flush for published session → %@", sessionID.uuidString)
                } else {
                    let result = await BackendEnvironment.shared.publish.deletePost(sessionID)
                    switch result {
                    case .success:
                        NSLog("[PublishService] Preview deletePost success → %@", sessionID.uuidString)
                    case .failure(let error):
                        NSLog("[PublishService] Preview deletePost failed → %@ | error=%@", sessionID.uuidString, String(describing: error))
                    }
                }
            }
        }
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
#if DEBUG
    /// DEBUG: Check if an objectID is published by a specific owner (reads that owner's store directly).
    func debugIsPublishedBy(owner: String, objectID: NSManagedObjectID) -> Bool {
        let key = "publishedSessions_v1::" + owner
        let arr = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
        let uri = objectID.uriRepresentation().absoluteString
        return arr.contains(uri)
    }
#endif
}
