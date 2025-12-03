////
//  IdentityService.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 03/12/2025.
//

import Foundation

// CHANGE-ID: 20251203_BackendIdentityHandshakeStep5
// SCOPE: Step 5 — IdentityService protocol + LocalStubIdentityService (UserDefaults-backed mapping)

struct BackendIdentity {
    let backendUserID: String
}

protocol IdentityService {
    func ensureBackendIdentity(appleSubject: String) async -> BackendIdentity
}

/// Local stub implementation used before a real backend exists.
/// - Generates a stable backendUserID per Apple subject.
/// - Persists mapping in UserDefaults.
/// - Performs no network calls.
final class LocalStubIdentityService: IdentityService {

    private let defaults: UserDefaults
    private let mappingKey = "backendIdentityMap_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func ensureBackendIdentity(appleSubject: String) async -> BackendIdentity {
        // Simple synchronous UserDefaults lookup/write inside async context.
        var map = defaults.dictionary(forKey: mappingKey) as? [String: String] ?? [:]
        if let existing = map[appleSubject] {
            return BackendIdentity(backendUserID: existing)
        }

        let newID = UUID().uuidString
        map[appleSubject] = newID
        defaults.set(map, forKey: mappingKey)
        return BackendIdentity(backendUserID: newID)
    }
}
