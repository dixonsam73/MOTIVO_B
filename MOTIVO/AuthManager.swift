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

// MARK: - Minimal Keychain helpers

enum Keychain {
    static func set(_ value: String, for key: String, service: String = "MOTIVO.Auth") {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String, service: String = "MOTIVO.Auth") -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String, service: String = "MOTIVO.Auth") {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Auth Manager

final class AuthManager: NSObject, ObservableObject {
    @Published private(set) var currentUserID: String?
    @Published private(set) var displayName: String?

    private var currentNonce: String?

    override init() {
        super.init()
        self.currentUserID = Keychain.get("appleUserID")
        self.displayName = Keychain.get("displayName")
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
        DispatchQueue.main.async {
            self.currentUserID = nil
            self.displayName = nil
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
                // Keep previously stored display name if present
                self.displayName = existing
            }
        } else {
            // Subsequent sign-ins: keep any existing stored name (if any)
            self.displayName = Keychain.get("displayName")
        }
    }

    // MARK: - Nonce helpers

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.map { String(format: "%02x", $0) }.joined()
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
