////
//  AuthManager.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 22/09/2025.
//

import Foundation
import AuthenticationServices
import CryptoKit
import Combine

#if canImport(Supabase)
import Supabase
#endif

// CHANGE-ID: 20251230_Step7_SupabaseAuthBridge_193205-8f3c
// SCOPE: Step 7 — bridge native Sign in with Apple to Supabase Auth (native idToken flow); persist Supabase session userID + access token; wire NetworkManager bearer token

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
        }

        // Existing users (signed in before Step 5): perform a one-time handshake
        // if we already have an Apple user ID but no backend ID yet.
        if let appleID = currentUserID, backendUserID == nil {
            ensureBackendIdentityIfNeeded(for: appleID)
        }
    }

    var isSignedIn: Bool { currentUserID != nil }

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
            // Ensure we publish on the main thread (UI updates)
            DispatchQueue.main.async {
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
        UserDefaults.standard.removeObject(forKey: Self.supabaseUserIDDefaultsKey)
        NetworkManager.shared.clearBearerToken()

        UserDefaults.standard.removeObject(forKey: Self.backendUserDefaultsKey)

        DispatchQueue.main.async {
            self.currentUserID = nil
            self.displayName = nil
            self.backendUserID = nil
        }
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
        // This is what makes `auth.uid()` non-null, unlocking RLS writes/reads to `public.posts`.
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
        // If you hit this path: add the Supabase Swift SDK (supabase-swift) via Swift Package Manager,
        // then rebuild. We intentionally avoid an undocumented REST fallback here.
        NSLog("[Auth] Supabase Swift SDK not present; add supabase-swift to use signInWithIdToken.")
        #endif
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
