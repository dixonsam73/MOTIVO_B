////
//  AuthManager.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 22/09/2025.
//

// CHANGE-ID: 20260122_113000_Phase142_IgnoreBackendOverrideInConnected
// SCOPE: Phase 14.2 — Ignore Debug.backendUserIDOverride when BackendEnvironment.isConnected == true
// SEARCH-TOKEN: 20260122_113000_Phase142_AuthIgnoreOverride

// CHANGE-ID: 20260127_130352_AuthLiveness_RefreshRetry
// SCOPE: Phase 14.2.2 — Fix zombie auth by persisting refresh token, refreshing on launch/foreground, and supporting 401/403 refresh+retry once; no UI changes.
// SEARCH-TOKEN: 20260127_130352_AuthLiveness_RefreshRetry

// CHANGE-ID: 20260128_194500_14_3A_AuthMainActor
// SCOPE: Phase 14.3A — AuthManager: enforce MainActor for published state to eliminate background-thread publishing warnings; no UI changes.
// SEARCH-TOKEN: 20260128_194500_14_3A_AuthMainActor


// CHANGE-ID: 20260128_190000_14_3B_BackendOwnerID
// SCOPE: Phase 14.3B — Connected-mode owner identity: never fall back to Apple ID for backend ownership; hydrate backendUserID from stored Supabase access token when possible; no UI/layout changes.
// SEARCH-TOKEN: 20260128_190000_14_3B_BackendOwnerID


import Foundation
import AuthenticationServices
import CryptoKit
import Combine

// CHANGE-ID: 20260112_131015_9A_backend_identity_canonicalisation
// SCOPE: Step 9A — Canonicalise backend user identity lookup (single source for backend principal; DEBUG override key)
// UNIQUE-TOKEN: 20260112_131015_backend_id_canon

#if canImport(Supabase)
import Supabase
#endif

// CHANGE-ID: 20251230_Step7_SupabaseAuthBridge_193205-8f3c_fix1
// SCOPE: Step 7 — bridge native Sign in with Apple to Supabase Auth (native idToken flow); clarify missing module diagnostics (Supabase product needed for SupabaseClient)

// MARK: - Keychain helper

enum Keychain {
    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Auth Manager

@MainActor
final class AuthManager: NSObject, ObservableObject {
    @Published private(set) var currentUserID: String?
    @Published private(set) var displayName: String?
    @Published private(set) var backendUserID: String?

    private var currentNonce: String?
    private let identityService: IdentityService

    private static let backendUserDefaultsKey = "backendUserID_v1"

    // Step 7: Supabase session persistence (dev-only; no refresh logic yet)
    private static let supabaseAccessTokenKeychainKey = "supabaseAccessToken_v1"
    private static let supabaseUserIDDefaultsKey = "supabaseUserID_v1"
    private static let supabaseRefreshTokenKeychainKey = "supabaseRefreshToken_v1"

    /// Canonical backend principal used for all backend/RLS calls.
    ///
    /// Order:
    /// 1) DEBUG override ("Debug.backendUserIDOverride")
    /// 2) Supabase user ID ("supabaseUserID_v1")
    /// 3) Legacy backend stub ID ("backendUserID_v1")
    ///
    /// Returns a trimmed, lowercased string, or nil if unavailable.
    static func canonicalBackendUserID() -> String? {
        #if DEBUG
        if BackendEnvironment.shared.isConnected == false,
           let override = UserDefaults.standard.string(forKey: "Debug.backendUserIDOverride")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override.lowercased()
        }
        #endif

        let raw = (UserDefaults.standard.string(forKey: Self.supabaseUserIDDefaultsKey) ??
                   UserDefaults.standard.string(forKey: Self.backendUserDefaultsKey) ??
                   "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return raw.isEmpty ? nil : raw.lowercased()
    }

    override convenience init() {
        self.init(identityService: LocalStubIdentityService())
    }

    init(identityService: IdentityService) {
        self.identityService = identityService
        super.init()

        self.currentUserID = Keychain.get("appleUserID")
        self.displayName = Keychain.get("displayName")

        // Prefer Supabase user ID if present (Step 7). Otherwise fall back to Step 5 stub.
        if let supaUserID = UserDefaults.standard.string(forKey: Self.supabaseUserIDDefaultsKey), !supaUserID.isEmpty {
            self.backendUserID = supaUserID
            UserDefaults.standard.set(supaUserID, forKey: Self.backendUserDefaultsKey) // keep legacy key in sync
        } else {
            self.backendUserID = UserDefaults.standard.string(forKey: Self.backendUserDefaultsKey)
        }

        // If we have a stored Supabase access token, apply it to NetworkManager for RLS-protected calls.
        if let token = Keychain.get(Self.supabaseAccessTokenKeychainKey), !token.isEmpty {
            NetworkManager.shared.setBearerToken(token)

            // Phase 14.3B — If backendUserID is missing but we have a Supabase access token,
            // derive the user UUID from the JWT subject ("sub") so backend ownership checks
            // never fall back to the Apple ID.
            if (self.backendUserID ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let derived = Self.supabaseUserIDFromAccessToken(token)?.lowercased() {
                UserDefaults.standard.set(derived, forKey: Self.supabaseUserIDDefaultsKey)
                UserDefaults.standard.set(derived, forKey: Self.backendUserDefaultsKey)
                self.backendUserID = derived
            }
        
        // Phase 14.2.2 — Auth/session liveness: allow NetworkManager to challenge auth on 401/403.
        // This is intentionally lightweight: refresh once, retry once; otherwise collapse to signed-out.
        NetworkManager.shared.onAuthChallenge = { [weak self] in
            guard let self else { return false }
            return await self.ensureValidSession(reason: "network-auth-challenge")
        }

}

        // Existing users (signed in before Step 5): perform a one-time handshake
        // if we already have an Apple user ID but no backend ID yet.
        if let appleID = currentUserID, backendUserID == nil {
            ensureBackendIdentityIfNeeded(for: appleID)
        }
    }

    var isSignedIn: Bool { currentUserID != nil }

    // MARK: - Session liveness

    private var sessionRefreshInFlight: Task<Bool, Never>?

    /// Ensures the Supabase session is valid for connected-mode network calls.
    /// - Returns: true if a valid bearer token is available after the check.
    func ensureValidSession(reason: String) async -> Bool {
        // Only meaningful in Connected mode.
        guard BackendEnvironment.shared.isConnected else {
            return self.isSignedIn
        }

        // If the user is not locally signed in, nothing to refresh.
        guard self.currentUserID != nil else {
            return false
        }

        // If backend isn't configured, collapse state (prevents zombie UI in Connected builds).
        guard BackendConfig.isConfigured else {
            NSLog("[Auth] ensureValidSession: BackendConfig not configured; signing out. reason=%@", reason)
            await MainActor.run { self.signOut() }
            return false
        }

        // Coalesce concurrent refresh attempts.
        if let existing = sessionRefreshInFlight {
            return await existing.value
        }

        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            return await self.refreshSupabaseSession(reason: reason)
        }
        sessionRefreshInFlight = task
        let ok = await task.value
        sessionRefreshInFlight = nil
        return ok
    }

    private func refreshSupabaseSession(reason: String) async -> Bool {
        #if canImport(Supabase)
        guard let refreshToken = Keychain.get(Self.supabaseRefreshTokenKeychainKey), !refreshToken.isEmpty else {
            NSLog("[Auth] refreshSupabaseSession: missing refresh token; signing out. reason=%@", reason)
            await MainActor.run { self.signOut() }
            return false
        }
        guard let url = BackendConfig.apiBaseURL, let key = BackendConfig.apiToken else {
            NSLog("[Auth] refreshSupabaseSession: BackendConfig missing URL/key; signing out. reason=%@", reason)
            await MainActor.run { self.signOut() }
            return false
        }

        do {
            let supabase = SupabaseClient(supabaseURL: url, supabaseKey: key)
            let session = try await supabase.auth.refreshSession(refreshToken: refreshToken)

            let accessToken = session.accessToken
            let newRefresh = session.refreshToken
            let supaUserID = session.user.id.uuidString

            Keychain.set(accessToken, for: Self.supabaseAccessTokenKeychainKey)
            Keychain.set(newRefresh, for: Self.supabaseRefreshTokenKeychainKey)
            UserDefaults.standard.set(supaUserID, forKey: Self.supabaseUserIDDefaultsKey)
            UserDefaults.standard.set(supaUserID, forKey: Self.backendUserDefaultsKey)

            NetworkManager.shared.setBearerToken(accessToken)

            await MainActor.run {
                self.backendUserID = supaUserID
            }

            NSLog("[Auth] refreshSupabaseSession OK user=%@ reason=%@", supaUserID, reason)
            return true
        } catch {
            NSLog("[Auth] refreshSupabaseSession FAILED: %@ reason=%@", String(describing: error), reason)
            await MainActor.run { self.signOut() }
            return false
        }
        #else
        // If Supabase is not linked, we cannot refresh; sign out to avoid zombie UI.
        NSLog("[Auth] refreshSupabaseSession: Supabase module missing; signing out. reason=%@", reason)
        await MainActor.run { self.signOut() }
        return false
        #endif
    }


    // Configure SwiftUI Sign in with Apple button
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    // Handle SwiftUI button completion
    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure:
            return
        case .success(let authorization):
            // Ensure we publish on MainActor (UI updates)
            Task { @MainActor in
                self.process(authorization)
            }
        }
    }

    // Local sign-out
    func signOut() {
        Keychain.delete("appleUserID")
        Keychain.delete("displayName")

        // Step 7: clear Supabase session (dev-only)
        Keychain.delete(Self.supabaseAccessTokenKeychainKey)
        Keychain.delete(Self.supabaseRefreshTokenKeychainKey)
        UserDefaults.standard.removeObject(forKey: Self.supabaseUserIDDefaultsKey)
        NetworkManager.shared.clearBearerToken()

        UserDefaults.standard.removeObject(forKey: Self.backendUserDefaultsKey)

        self.currentUserID = nil
        self.displayName = nil
        self.backendUserID = nil
    }

    // MARK: - Internal processing

    private func process(_ authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }

        // Persist stable Apple user ID (always present)
        let userID = credential.user
        Keychain.set(userID, for: "appleUserID")
        self.currentUserID = userID

        // Apple only provides fullName on the very first authorization.
        // On subsequent sign-ins it's usually nil — handle safely without force unwraps.
        if let fullName = credential.fullName {
            let given = fullName.givenName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let family = fullName.familyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
            if !name.isEmpty {
                Keychain.set(name, for: "displayName")
                self.displayName = name
            } else if let existing = Keychain.get("displayName") {
                self.displayName = existing
            }
        } else {
            self.displayName = Keychain.get("displayName")
        }

        // Step 7: If backend config is present, bridge Apple → Supabase Auth (native idToken flow).
        if BackendConfig.isConfigured {
            Task {
                await self.signInToSupabaseIfPossible(credential: credential)
            }
        }

        // Step 5 fallback: Backend identity handshake (local stub): performed only if we don't already have a backendUserID.
        ensureBackendIdentityIfNeeded(for: userID)
    }

    private func ensureBackendIdentityIfNeeded(for appleID: String) {
        guard backendUserID == nil else { return }

        Task { [weak self] in
            guard let self else { return }
            let identity = await self.identityService.ensureBackendIdentity(appleSubject: appleID)
            let backendID = identity.backendUserID
            UserDefaults.standard.set(backendID, forKey: Self.backendUserDefaultsKey)
            await MainActor.run {
                self.backendUserID = backendID
            }
        }
    }

    // MARK: - Supabase Auth (native idToken flow)

    private func signInToSupabaseIfPossible(credential: ASAuthorizationAppleIDCredential) async {
        guard let nonce = currentNonce, !nonce.isEmpty else {
            NSLog("[Auth] Supabase sign-in skipped: missing nonce")
            return
        }
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              !idToken.isEmpty else {
            NSLog("[Auth] Supabase sign-in skipped: missing identityToken")
            return
        }
        guard let url = BackendConfig.apiBaseURL, let key = BackendConfig.apiToken else {
            NSLog("[Auth] Supabase sign-in skipped: BackendConfig not configured")
            return
        }

        #if canImport(Supabase)
        do {
            let supabase = SupabaseClient(supabaseURL: url, supabaseKey: key)

            let session = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )

            let accessToken = session.accessToken
            let supaUserID = session.user.id.uuidString

            Keychain.set(accessToken, for: Self.supabaseAccessTokenKeychainKey)
            Keychain.set(session.refreshToken, for: Self.supabaseRefreshTokenKeychainKey)
            UserDefaults.standard.set(supaUserID, forKey: Self.supabaseUserIDDefaultsKey)
            UserDefaults.standard.set(supaUserID, forKey: Self.backendUserDefaultsKey)

            await MainActor.run {
                self.backendUserID = supaUserID
            }

            NetworkManager.shared.setBearerToken(accessToken)
            NSLog("[Auth] Supabase sign-in success user=%@", supaUserID)
        } catch {
            NSLog("[Auth] Supabase sign-in failed: %@", String(describing: error))
        }
        #else
        // You have supabase-swift installed, but the MOTIVO target is missing the *Supabase* product/library.
        // In Xcode: Package Dependencies → supabase-swift → add the "Supabase" product to the MOTIVO target
        // (often below the visible list—scroll).
        NSLog("[Auth] Supabase module not present. Add supabase-swift product 'Supabase' to the MOTIVO app target (not just 'Auth'), then rebuild.")
        #endif
    }

    
    // MARK: - Token parsing (hydration)

    /// Best-effort: derive the Supabase user UUID from a stored Supabase access token (JWT).
    /// This avoids transient nil backendUserID during cold launch when the access token is present
    /// but the user ID defaults key is missing.
    private static func supabaseUserIDFromAccessToken(_ accessToken: String) -> String? {
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad base64 string to a multiple of 4.
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: payload) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = obj as? [String: Any] else { return nil }

        guard let sub = dict["sub"] as? String else { return nil }
        guard UUID(uuidString: sub) != nil else { return nil }
        return sub
    }


// MARK: - Nonce helpers

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms) == errSecSuccess else {
                fatalError("Unable to generate nonce.")
            }
            for random in randoms {
                if remaining == 0 { break }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }
}
