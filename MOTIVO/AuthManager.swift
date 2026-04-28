////
//  AuthManager.swift
//  MOTIVO
//
//  Created by Samuel Dixon on 22/09/2025.
//

// CHANGE-ID: 20260213_210205_ConnectedOfflineResilience
// SCOPE: Connected-mode Offline Resilience — do not sign out on offline/transient refresh failures; preserve zombie fix for true auth invalidation.
// SEARCH-TOKEN: 20260213_210205_OfflineNotSignOut

// CHANGE-ID: 20260129_133308_14_3H_B5_SignInRaceGuard
// SCOPE: Phase 14.3H (B5) — Prevent foreground/launch session refresh from signing out during in-flight Supabase sign-in (missing refresh token race).
// SEARCH-TOKEN: 20260129_133308_14_3H_B5_SignInRaceGuard

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


// CHANGE-ID: 20260302_093339_ProfileHydrateDirectory_3b1f
// SCOPE: Profile privacy hydration — on sign-in/session restore, fetch account_directory self row and hydrate ProfileStore discoveryMode/account_id to match backend (fresh install consistency). No UI changes.
// SEARCH-TOKEN: 20260302_093339_ProfileHydrateDirectory_3b1f

// CHANGE-ID: 20260303_104100_DeleteAccountV2_Stage4B_AuthHydrationGuard
// SCOPE: Delete Account v2 Stage 4b — prevent directory hydration/ProfileStore writes during factory reset; cancel hydration task on signOut. No UI changes.
// SEARCH-TOKEN: 20260303_104100_DeleteAccountV2_AuthHydrationGuard


// CHANGE-ID: 20260303_172000_DeleteAccountV2_FinalHardening_AuthGuards
// SCOPE: Delete Account v2 final hardening — add guardrails in AuthManager to suppress backend identity/session/directory hydration work during/after LocalFactoryReset when BackendConfig is not configured. Prevents post-reset background tasks from emitting errors or mutating state. No UI changes.
// SEARCH-TOKEN: 20260303_172000_DeleteAccountV2_FinalHardening_AuthManagerGuards

// CHANGE-ID: 20260308_201400_MultiDeviceBootstrap_AuthManager
// SCOPE: Multi-device bootstrap hardening — track backend bootstrap state and hydrate canonical display_name/location/instruments from account_directory before setup gating on fresh second-device sign-in. No UI/layout changes.
// SEARCH-TOKEN: 20260308_201400_MultiDeviceBootstrap_AuthManager

import Foundation
import AuthenticationServices
import CryptoKit
import Combine
import CoreData

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
    enum BackendBootstrapState {
        case unknown
        case checking
        case existingAccount
        case newAccount
    }

    @Published private(set) var currentUserID: String?
    @Published private(set) var displayName: String?
    @Published private(set) var backendUserID: String?
    @Published private(set) var backendAvatarKey: String?
    @Published private(set) var isSigningIn: Bool = false
    @Published private(set) var backendBootstrapState: BackendBootstrapState = .unknown

    // Profile privacy hydration (fresh install consistency)
    private var directoryHydrationTask: Task<Void, Never>?
    private var lastHydratedDirectoryUserID: String?

    // Account ID auto-generation backfill (session-liveness anchored, best-effort).
    private var accountIDBackfillTask: Task<Void, Never>?
    private var accountIDBackfillAttemptedUserIDs = Set<String>()
    private var accountIDBackfillInFlightUserIDs = Set<String>()



    // CHANGE-ID: 20260129_221500_14_3H_B4_fixTokenGuard
    // SCOPE: Phase 14.3H (B4) — Provide explicit, truth-based helpers for UI gating:
    //  - isConnected mirrors BackendEnvironment.shared.isConnected
    //  - hasSupabaseAccessToken checks for a non-empty stored Supabase access token in Keychain
    var isConnected: Bool { BackendEnvironment.shared.isConnected }

    var hasSupabaseAccessToken: Bool {
        guard let token = Keychain.get(Self.supabaseAccessTokenKeychainKey) else { return false }
        return token.isEmpty == false
    }

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

        scheduleDirectoryHydrationIfNeeded(reason: "init")
        scheduleAccountIDBackfillIfNeeded(reason: "init")

}

        // Existing users (signed in before Step 5): perform a one-time handshake
        // if we already have an Apple user ID but no backend ID yet.
        if let appleID = currentUserID, backendUserID == nil {
            ensureBackendIdentityIfNeeded(for: appleID)
        }
    }

    var isSignedIn: Bool { currentUserID != nil }


    // MARK: - Directory hydration (ProfileStore defaults)

    /// Hydrate local ProfileStore values (discovery mode + account handle) from the backend account_directory row.
    /// This keeps Profile privacy UI consistent on fresh installs / new devices.
    private func scheduleDirectoryHydrationIfNeeded(reason: String) {
        // Delete Account v2: do not schedule hydration during/after factory reset or when backend not configured.
        guard !LocalFactoryReset.isInProgress else { return }
        guard BackendConfig.isConfigured else { return }
        guard self.currentUserID != nil else { return }

        guard let bid = backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !bid.isEmpty else { return }
        guard lastHydratedDirectoryUserID != bid else { return }

        self.backendBootstrapState = .checking
        directoryHydrationTask?.cancel()
        directoryHydrationTask = Task { [weak self] in
            guard let self else { return }
            await self.hydrateDirectoryStateFromBackend(userID: bid, reason: reason)
        }
    }

    private func scheduleAccountIDBackfillIfNeeded(reason: String) {
        // Account ID generation is only meaningful for an authenticated Connected backend user.
        guard !LocalFactoryReset.isInProgress else { return }
        guard BackendEnvironment.shared.isConnected else { return }
        guard BackendConfig.isConfigured else { return }
        guard self.currentUserID != nil else { return }
        guard self.hasSupabaseAccessToken else { return }

        guard let bid = backendUserID?.trimmingCharacters(in: .whitespacesAndNewlines), !bid.isEmpty else { return }
        guard accountIDBackfillAttemptedUserIDs.contains(bid) == false else { return }
        guard accountIDBackfillInFlightUserIDs.contains(bid) == false else { return }

        accountIDBackfillAttemptedUserIDs.insert(bid)
        accountIDBackfillInFlightUserIDs.insert(bid)

        accountIDBackfillTask?.cancel()
        accountIDBackfillTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.accountIDBackfillInFlightUserIDs.remove(bid)
                }
            }

            let localAccountID = ProfileStore.accountID(for: bid)
            let lookupEnabled = ProfileStore.discoveryModeRaw(for: bid) == 1

            guard let generated = await AccountDirectoryService.shared.autoGenerateAccountIDIfMissing(
                userID: bid,
                displayName: self.displayName ?? "",
                localAccountID: localAccountID,
                lookupEnabled: lookupEnabled,
                followRequestsEnabled: nil,
                location: nil,
                instruments: nil
            ) else { return }

            ProfileStore.setAccountID(generated, for: bid)
            NSLog("[Auth] account_id backfill generated user=%@ reason=%@ account_id=%@", bid, reason, generated)
        }
    }

    private func hydrateDirectoryStateFromBackend(userID: String, reason: String) async {
        // If backend config is not available (e.g., after factory reset), do not attempt hydration.
        guard BackendConfig.isConfigured else {
            NSLog("[Auth] directory hydration skipped user=%@ reason=%@ (BackendConfig not configured)", userID, reason)
            return
        }

        // Skip during factory reset or when signed out; avoids mutating ProfileStore/Core Data after wipe.
        guard !LocalFactoryReset.isInProgress else {
            NSLog("[Auth] directory hydration skipped user=%@ reason=%@ (factory reset in progress)", userID, reason)
            return
        }
        guard self.backendUserID == userID else { return }

        // Avoid spamming on repeated refreshes.
        guard lastHydratedDirectoryUserID != userID else { return }

        let result = await AccountDirectoryService.shared.fetchSelfRow(userID: userID)
        switch result {
        case .failure(let error):
            // Offline/not-configured is not fatal — leave local defaults as-is.
            NSLog("[Auth] directory hydration skipped user=%@ reason=%@ err=%@", userID, reason, String(describing: error))
        case .success(let row):
            guard let row else {
                self.backendBootstrapState = .newAccount
                self.backendAvatarKey = nil
                NSLog("[Auth] directory hydration no-row user=%@ reason=%@", userID, reason)
                return
            }

            // Backend is canonical for privacy defaults. Map lookup_enabled -> DiscoveryMode rawValue.
            let discoveryRaw = row.lookupEnabled ? 1 : 0
            ProfileStore.setDiscoveryModeRaw(discoveryRaw, for: userID)

            // Store handle/account_id (lowercased); empty clears.
            ProfileStore.setAccountID(row.accountID ?? "", for: userID)

            self.backendAvatarKey = row.avatarKey?.trimmingCharacters(in: .whitespacesAndNewlines)

            let viewContext = PersistenceController.shared.container.viewContext
            ProfileStore.hydrateMissingLocalIdentity(
                displayName: row.displayName,
                location: row.location,
                instruments: row.instruments,
                for: userID,
                in: viewContext
            )

            lastHydratedDirectoryUserID = userID
            self.backendBootstrapState = .existingAccount
            NSLog("[Auth] directory hydration applied user=%@ reason=%@ lookup=%@ account_id=%@",
                  userID, reason, row.lookupEnabled ? "1" : "0", row.accountID ?? "nil")
        }
    }


    // MARK: - Session liveness

    private var sessionRefreshInFlight: Task<Bool, Never>?

    /// Ensures the Supabase session is valid for connected-mode network calls.
    /// - Returns: true if a valid bearer token is available after the check.
    func ensureValidSession(reason: String) async -> Bool {
        // Delete Account v2: suppress auth/identity work during a local factory reset.
        guard !LocalFactoryReset.isInProgress else {
            NSLog("[Auth] %@ skipped (factory reset in progress) reason=%@", #function, reason)
            return false
        }

        // Only meaningful in Connected mode.
        guard BackendEnvironment.shared.isConnected else {
            return self.isSignedIn
        }

        // If the user is not locally signed in, nothing to refresh.
        guard self.currentUserID != nil else {
            return false
        }

        // If a sign-in is currently in-flight, do not attempt a refresh.
        // This avoids racing foreground/launch liveness refresh against the initial Supabase sign-in.
        guard !self.isSigningIn else {
            NSLog("[Auth] ensureValidSession: sign-in in flight; skipping refresh. reason=%@", reason)
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

private func isOfflineOrTransientNetworkError(_ error: Error) -> Bool {
    // We must not treat offline / transient transport failures as auth invalidation.
    // Supabase Swift may wrap URLError inside NSError userInfo; inspect recursively.
    func extractNSErrorChain(_ error: Error) -> [NSError] {
        var out: [NSError] = []
        var current: NSError? = error as NSError
        var seen = Set<ObjectIdentifier>()
        while let ns = current {
            let oid = ObjectIdentifier(ns)
            if seen.contains(oid) { break }
            seen.insert(oid)
            out.append(ns)
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                current = underlying
            } else {
                break
            }
        }
        return out
    }

    for ns in extractNSErrorChain(error) {
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorInternationalRoamingOff,
                 NSURLErrorCallIsActive,
                 NSURLErrorDataNotAllowed,
                 NSURLErrorSecureConnectionFailed:
                return true
            default:
                break
            }
        }
    }
    return false
}

    private func refreshSupabaseSession(reason: String) async -> Bool {
        // Delete Account v2: suppress refresh during a local factory reset.
        guard !LocalFactoryReset.isInProgress else {
            NSLog("[Auth] refreshSupabaseSession skipped (factory reset in progress) reason=%@", reason)
            return false
        }

        #if canImport(Supabase)
        guard let refreshToken = Keychain.get(Self.supabaseRefreshTokenKeychainKey), !refreshToken.isEmpty else {
            if self.isSigningIn {
                NSLog("[Auth] refreshSupabaseSession: missing refresh token while sign-in in flight; not signing out. reason=%@", reason)
                return false
            }
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
                self.backendAvatarKey = nil
                self.scheduleDirectoryHydrationIfNeeded(reason: "refreshSupabaseSession")
                self.scheduleAccountIDBackfillIfNeeded(reason: "refreshSupabaseSession")
            }

            NSLog("[Auth] refreshSupabaseSession OK user=%@ reason=%@", supaUserID, reason)
            return true
        } catch {
            NSLog("[Auth] refreshSupabaseSession FAILED: %@ reason=%@", String(describing: error), reason)
            if isOfflineOrTransientNetworkError(error) {
                NSLog("[Auth] refreshSupabaseSession: offline/transient failure; not signing out. reason=%@", reason)
                return false
            }
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
        // Cancel any in-flight hydration so it can't write into stores after sign-out/reset.
        directoryHydrationTask?.cancel()
        directoryHydrationTask = nil
        lastHydratedDirectoryUserID = nil
        accountIDBackfillTask?.cancel()
        accountIDBackfillTask = nil
        accountIDBackfillAttemptedUserIDs.removeAll()
        accountIDBackfillInFlightUserIDs.removeAll()

        let namespaceUserID = AttachmentTitlePersistenceKeys.normalize(
            BackendEnvironment.shared.isConnected
                ? Self.canonicalBackendUserID()
                : (self.currentUserID ?? ((try? PersistenceController.shared.currentUserID)))
        )
        if let userID = namespaceUserID {
            UserDefaults.standard.removeObject(forKey: AttachmentTitlePersistenceKeys.audioNamespacedKey(for: userID))
            UserDefaults.standard.removeObject(forKey: AttachmentTitlePersistenceKeys.videoNamespacedKey(for: userID))
        }

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
        self.backendAvatarKey = nil
        self.isSigningIn = false
        self.backendBootstrapState = .unknown
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
            self.isSigningIn = true
            Task {
                await self.signInToSupabaseIfPossible(credential: credential)
            }
        }

        // Step 5 fallback: Backend identity handshake (local stub): performed only if we don't already have a backendUserID.
        ensureBackendIdentityIfNeeded(for: userID)
    }

    private func ensureBackendIdentityIfNeeded(for appleID: String) {
        // Delete Account v2: never attempt identity handshake during/after a factory reset.
        guard !LocalFactoryReset.isInProgress else {
            NSLog("[Auth] ensureBackendIdentityIfNeeded skipped (factory reset in progress)")
            return
        }
        // If backend config is not configured (e.g., after factory reset), do not attempt backend identity.
        guard BackendConfig.isConfigured else {
            NSLog("[Auth] ensureBackendIdentityIfNeeded skipped (BackendConfig not configured)")
            return
        }

        guard backendUserID == nil else { return }

        Task { [weak self] in
            guard let self else { return }
            let identity = await self.identityService.ensureBackendIdentity(appleSubject: appleID)
            let backendID = identity.backendUserID
            UserDefaults.standard.set(backendID, forKey: Self.backendUserDefaultsKey)
            await MainActor.run {
                self.backendUserID = backendID
                self.backendAvatarKey = nil
                self.scheduleDirectoryHydrationIfNeeded(reason: "ensureBackendIdentityIfNeeded")
            }
        }
    }

    // MARK: - Supabase Auth (native idToken flow)

    private func signInToSupabaseIfPossible(credential: ASAuthorizationAppleIDCredential) async {
        defer { self.isSigningIn = false }
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

            NetworkManager.shared.setBearerToken(accessToken)

            await MainActor.run {
                self.backendUserID = supaUserID
                self.backendAvatarKey = nil
                self.scheduleDirectoryHydrationIfNeeded(reason: "supabaseSignIn")
                self.scheduleAccountIDBackfillIfNeeded(reason: "supabaseSignIn")
            }

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
