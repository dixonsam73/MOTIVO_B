//
//  C27SignOutLocationTests.swift
//  MOTIVOTests
//
//  C-27 — AT SIGN-OUT, THE LOCAL ÉTUDES PROFILE KEEPS THE LOCATION THE SIGNED-IN
//  PROFILE PRESENTED, WITHOUT `ProfileView` MOUNTED.
//
//  `ProfileView` carries `presentedLocation` to the local scope when `currentUserID`
//  becomes nil, but only while it is mounted. These cases drive the real
//  `AuthManager.signOut()` and `clearConnectedIdentity(reason:)` with no view at all.
//
//  WHAT THIS DOES NOT SHOW: device behaviour, the SwiftUI observer, or the factory-reset
//  guard (its flag is private(set) and `LocalFactoryReset.perform` wipes the whole
//  defaults domain afterwards; the guard is verified by source review).
//
//  NO NETWORK, NO REAL IDENTITY. Interception is registered FIRST and removed LAST:
//  `C98DenyAll` fails and records any application http(s) request, which every case
//  asserts is empty; `C98AuthStub` answers only the deliberate bearer probes, counted
//  separately. The fixture holds a fabricated backend user id and NO tokens, so
//  `AuthManager.init` starts no session or identity work (its handshake needs
//  `backendUserID == nil`, and `onAuthChallenge` is assigned only when a token exists).
//
//  ISOLATION AND RESTORATION (C-98's pattern, on its internal support types). setUp
//  snapshots the four Keychain items, five defaults keys, NetworkManager baseURL /
//  authToken / onAuthChallenge presence, the ACTUAL in-memory bearer (by probe to the
//  stub), the SDK session item (compared, never written), the local-scope location key
//  and the backend mode. tearDown restores, re-probes the bearer with interception still
//  installed, verifies every item, and only then unregisters.
//

import XCTest
@testable import Etudes

@MainActor
final class C27SignOutLocationTests: XCTestCase {
    private static let keychainAccounts = ["appleUserID", "displayName", "supabaseAccessToken_v1", "supabaseRefreshToken_v1"]
    private static let defaultsKeys = ["supabaseUserID_v1", "backendUserID_v1", "api_base_url_v1", "api_token_v1", "backendMode_v1"]
    private static let localLocationKey = "profile.__local_etudes_profile__.location"

    private var snapshot: C98Snapshot?
    private var savedLocalLocation: Any?
    private var savedMode: BackendMode?
    private var uid = ""
    private var scopedKey: String { "profile.\(uid).location" }

    override func setUp() async throws {
        try await super.setUp()
        guard UnitTestHost.isActive else { throw C98NotEstablished(reason: "not a hosted unit-test run") }
        guard !LocalFactoryReset.isInProgress else { throw C98NotEstablished(reason: "a factory reset is in progress") }

        C98AuthStub.reset()
        URLProtocol.registerClass(C98DenyAll.self)
        URLProtocol.registerClass(C98AuthStub.self)   // registered last, so consulted first

        uid = "c27-" + UUID().uuidString
        UserDefaults.standard.removeObject(forKey: scopedKey)
        savedLocalLocation = UserDefaults.standard.object(forKey: Self.localLocationKey)
        savedMode = BackendEnvironment.shared.mode
        snapshot = try await captureSnapshot()
    }

    override func tearDown() async throws {
        _ = await Self.joined(C98AuthStub.callbacks, within: 15)
        UserDefaults.standard.removeObject(forKey: scopedKey)
        if let savedLocalLocation {
            UserDefaults.standard.set(savedLocalLocation, forKey: Self.localLocationKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.localLocationKey)
        }

        var restoration: [(String, Bool)] = []
        if let snapshot {
            restore(snapshot)
            var probe: (ok: Bool, header: String?) = (false, nil)
            do { probe = (true, try await probeAuthorizationHeader()) } catch { probe = (false, nil) }
            _ = await Self.joined(C98AuthStub.callbacks, within: 15)
            restoration = verify(snapshot, probe: probe)
        }
        restoration.append(("backend mode", BackendEnvironment.shared.mode == savedMode))
        restoration.append(("local-scope location key", Self.same(UserDefaults.standard.object(forKey: Self.localLocationKey), savedLocalLocation)))
        restoration.append(("fixture scoped location key removed", UserDefaults.standard.object(forKey: scopedKey) == nil))
        let strays = C98AuthStub.strayRequests

        URLProtocol.unregisterClass(C98AuthStub.self)
        URLProtocol.unregisterClass(C98DenyAll.self)

        let evidence = (["C27-EVIDENCE \(name)", "  application requests (denied): \(strays)", "  bearer probes: \(C98AuthStub.probeCount)"]
                        + restoration.map { "  restored \($0.0): \($0.1 ? "yes" : "NO")" }).joined(separator: "\n")
        print(evidence)
        let attachment = XCTAttachment(string: evidence)
        attachment.name = "C-27 evidence"
        attachment.lifetime = .keepAlways
        add(attachment)

        for (item, ok) in restoration { XCTAssertTrue(ok, "C-27 restoration mismatch: \(item) (values withheld)") }
        XCTAssertTrue(strays.isEmpty, "an application request escaped to the deny-all protocol")
        try await super.tearDown()
    }

    // MARK: Cases

    /// 1 — a Connected location carries to the local profile on sign-out.
    func testSignOutCarriesThePresentedLocationToTheLocalProfile() throws {
        let auth = try makeManager(identity: true, scoped: "Paris", local: "London")
        auth.signOut()
        XCTAssertNil(auth.backendUserID, "signOut must have cleared the backend identity")
        XCTAssertEqual(ProfileStore.location(for: nil), "Paris")
        XCTAssertEqual(UserDefaults.standard.string(forKey: scopedKey), "Paris", "the scoped value must not be deleted")
        XCTAssertTrue(C98AuthStub.strayRequests.isEmpty)
    }

    /// 2 — the same on credential revocation or refresh withdrawal.
    func testClearConnectedIdentityCarriesThePresentedLocationToTheLocalProfile() throws {
        let auth = try makeManager(identity: true, scoped: "Paris", local: "London")
        auth.clearConnectedIdentity(reason: "c27")
        XCTAssertNil(auth.backendUserID, "clearConnectedIdentity must have cleared the backend identity")
        XCTAssertEqual(ProfileStore.location(for: nil), "Paris")
        XCTAssertEqual(UserDefaults.standard.string(forKey: scopedKey), "Paris", "the scoped value must not be deleted")
        XCTAssertTrue(C98AuthStub.strayRequests.isEmpty)
    }

    /// 3 — an identity whose scoped location was never written leaves the local value.
    func testSignOutWithoutAScopedLocationLeavesTheLocalProfileUnchanged() throws {
        let auth = try makeManager(identity: true, scoped: nil, local: "London")
        auth.signOut()
        XCTAssertNil(auth.backendUserID)
        XCTAssertEqual(ProfileStore.location(for: nil), "London")
        XCTAssertTrue(C98AuthStub.strayRequests.isEmpty)
    }

    /// 4 — an explicit "" (a deliberate clear) is what the profile presented, so it carries.
    func testSignOutCarriesADeliberatelyClearedLocation() throws {
        let auth = try makeManager(identity: true, scoped: "", local: "London")
        auth.signOut()
        XCTAssertNil(auth.backendUserID)
        XCTAssertEqual(UserDefaults.standard.object(forKey: Self.localLocationKey) as? String, "")
        XCTAssertEqual(UserDefaults.standard.object(forKey: scopedKey) as? String, "", "the scoped value must not be deleted")
        XCTAssertTrue(C98AuthStub.strayRequests.isEmpty)
    }

    /// 5 — with no backend identity there is nothing to carry and no scoped write.
    func testSignOutWithoutABackendIdentityLeavesTheLocalProfileUnchanged() throws {
        let auth = try makeManager(identity: false, scoped: nil, local: "London")
        auth.signOut()
        XCTAssertNil(auth.backendUserID)
        XCTAssertEqual(ProfileStore.location(for: nil), "London")
        XCTAssertNil(UserDefaults.standard.object(forKey: scopedKey), "no scoped location may be created")
        XCTAssertTrue(C98AuthStub.strayRequests.isEmpty)
    }

    // MARK: Fixture

    private func makeManager(identity: Bool, scoped: String?, local: String?) throws -> AuthManager {
        for account in Self.keychainAccounts { C98Keychain.setAppItem(account, nil) }
        if identity {
            UserDefaults.standard.set(uid, forKey: "supabaseUserID_v1")
            UserDefaults.standard.set(uid, forKey: "backendUserID_v1")
        } else {
            UserDefaults.standard.removeObject(forKey: "supabaseUserID_v1")
            UserDefaults.standard.removeObject(forKey: "backendUserID_v1")
        }
        if let scoped { UserDefaults.standard.set(scoped, forKey: scopedKey) } else { UserDefaults.standard.removeObject(forKey: scopedKey) }
        if let local { UserDefaults.standard.set(local, forKey: Self.localLocationKey) } else { UserDefaults.standard.removeObject(forKey: Self.localLocationKey) }

        let manager = AuthManager(identityService: LocalStubIdentityService())
        guard manager.backendUserID == (identity ? uid : nil), manager.currentUserID == nil else {
            throw C98NotEstablished(reason: "the AuthManager fixture did not load the arranged identity")
        }
        return manager
    }

    // MARK: Snapshot and restoration (C-98's pattern; its helpers are private to that class)

    private func probeAuthorizationHeader() async throws -> String? {
        let before = C98AuthStub.probeCount
        let saved = NetworkManager.shared.baseURL
        NetworkManager.shared.baseURL = C98AuthStub.baseURL
        let outcome = await NetworkManager.shared.request(path: C98AuthStub.probePath, method: "GET")
        NetworkManager.shared.baseURL = saved
        guard case .success = outcome, C98AuthStub.probeCount == before + 1 else {
            throw C98NotEstablished(reason: "the bearer probe did not reach the stub exactly once")
        }
        return C98AuthStub.probeHeader(at: before)
    }

    private func captureSnapshot() async throws -> C98Snapshot {
        let keychain = Self.keychainAccounts.map { ($0, C98Keychain.appItem($0)) }
        let defaults: [(String, Any?)] = Self.defaultsKeys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        return C98Snapshot(keychain: keychain, defaults: defaults,
                           baseURL: NetworkManager.shared.baseURL, authToken: NetworkManager.shared.authToken,
                           onAuthChallenge: NetworkManager.shared.onAuthChallenge,
                           authorizationHeader: try await probeAuthorizationHeader(),
                           sdkSession: C98Keychain.sdkSessionItem())
    }

    private func restore(_ s: C98Snapshot) {
        for (account, data) in s.keychain { C98Keychain.setAppItem(account, data) }
        for (key, value) in s.defaults {
            if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        NetworkManager.shared.baseURL = s.baseURL
        NetworkManager.shared.authToken = s.authToken
        NetworkManager.shared.onAuthChallenge = s.onAuthChallenge
        NetworkManager.shared.setBearerToken(s.authorizationHeader.flatMap {
            $0.hasPrefix("Bearer ") ? String($0.dropFirst("Bearer ".count)) : nil
        })
    }

    private func verify(_ s: C98Snapshot, probe: (ok: Bool, header: String?)) -> [(String, Bool)] {
        var out: [(String, Bool)] = []
        for (account, data) in s.keychain { out.append(("keychain \(account)", C98Keychain.appItem(account) == data)) }
        for (key, value) in s.defaults { out.append(("defaults \(key)", Self.same(UserDefaults.standard.object(forKey: key), value))) }
        out.append(("NetworkManager.baseURL", NetworkManager.shared.baseURL == s.baseURL))
        out.append(("NetworkManager.authToken", NetworkManager.shared.authToken == s.authToken))
        out.append(("NetworkManager.onAuthChallenge presence", (NetworkManager.shared.onAuthChallenge != nil) == (s.onAuthChallenge != nil)))
        out.append(("bearer, by verification probe to the stub", probe.ok && probe.header == s.authorizationHeader))
        out.append(("SDK session item", C98Keychain.sdkSessionItem() == s.sdkSession))
        return out
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return (x as? NSObject)?.isEqual(y) ?? false
        default: return false
        }
    }

    private static func joined(_ group: DispatchGroup, within seconds: Double) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: group.wait(timeout: .now() + seconds) == .success)
            }
        }
    }
}
