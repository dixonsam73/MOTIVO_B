//
//  C98AuthRefreshLifecycleTests.swift
//  MOTIVOTests
//
//  C-98 — A SESSION REFRESH THAT COMPLETES AFTER THE IDENTITY CHANGED MUST NOT
//  RESURRECT OR DESTROY STATE IT NO LONGER OWNS, AND A FINISHING REFRESH MUST NOT
//  RELEASE A REFRESH SLOT THAT ANOTHER CALLER NOW OWNS.
//
//  WHAT RUNS. The real `AuthManager` refresh path and the real supabase-swift 2.5.1
//  `refreshSession` request (`POST /auth/v1/token?grant_type=refresh_token`),
//  intercepted by `C98AuthStub` on 127.0.0.1:8. The stub can HOLD a request, so a case
//  can sign out, withdraw, arrange a newer session or start another caller between the
//  request leaving and its response returning. This shows what that overlap DOES; it
//  says nothing about how often real use produces one.
//
//  NO NETWORK, NO BACKEND, NO REAL IDENTITY. `C98DenyAll` fails and records every other
//  http(s) request made through URLSession's protocol machinery. It is instrumentation
//  for the inspected URLSession.shared paths, not an OS firewall. Identities, subjects
//  and tokens are fabricated per case.
//
//  WITNESSES (Codex review 007 rev1 §5, §7). Before any behavioural assertion a case
//  checks the following, and otherwise throws `C98NotEstablished` (inconclusive, not a
//  product result):
//   - each expected SDK refresh was intercepted with its method, path, grant_type and
//     the refresh token it should present, and completed with its scripted reply rather
//     than by the 10 s safeguard;
//   - the timeline order of callers, arrivals, lifecycle steps and releases;
//   - for O-1, C's ACTUAL slot event, recorded by the Debug hosted-test hook while B is
//     still held;
//   - no stray request reached the stub or the deny-all protocol.
//  Callers are JOINED (their Task is awaited after its completion group), never
//  inferred from a `finished` slot event. The SDK decoding of the reply bodies runs
//  through the real path in every invocation: A-0 (success decode commits), F-1
//  (terminal classification withdraws), F-2 (transport classification retains) and R-1
//  ("Already Used" classification recovers). The lifecycle cases send replies built by
//  the same code.
//
//  ISOLATION AND RESTORATION (§1, §6).
//   - setUp registers interception FIRST, then snapshots, in memory only: four Keychain
//     items (raw bytes), five defaults keys (raw values, so an absent key stays absent),
//     NetworkManager baseURL / authToken / onAuthChallenge, the live bearer, and the SDK
//     session item (compared, never written). The bearer is captured by a probe sent to
//     the stub, never to the saved base URL.
//   - tearDown releases holds, joins every caller and stub callback, restores with
//     interception still installed, probes the restored bearer against the stub,
//     restores the exact saved baseURL again, and only THEN unregisters. Restoration is
//     reported as match booleans; values are never printed.
//   - If work cannot be joined, or the SDK session item changed, the unit STOPS. It logs
//     `C98-UNIT-STOP`, leaves interception and fixture state in place, restores nothing,
//     and parks the test so no later test in the invocation runs. The run wrapper
//     terminates the invocation on that marker.
//  The hosted-test seam suppresses post-session scheduling before any case arranges a
//  Connected refresh, so hydration and account-ID backfill never start.
//
//  LIMITS. The newer sign-in is modelled by persisted state only. The stub is not
//  GoTrue. Fixture users carry no confirmation dates, so the SDK's confirmed-session
//  storage path is not exercised. Evidence is tied to supabase-swift 2.5.1.
//

import XCTest
import Security
@testable import Etudes

struct C98NotEstablished: Error, CustomStringConvertible {
    let reason: String
    var description: String { "C-98 ARRANGEMENT NOT ESTABLISHED (not a product result): \(reason)" }
}

/// A timeline of LABELS only — never a credential or a captured value.
final class C98Timeline: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func reset() { lock.lock(); entries = []; lock.unlock() }
    func add(_ entry: String) { lock.lock(); entries.append(entry); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return entries }

    func firstIndex(prefix: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return entries.firstIndex { $0.hasPrefix(prefix) }
    }

    func entries(prefix: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return entries.filter { $0.hasPrefix(prefix) }
    }
}

enum C98Reply {
    case success(access: String, refresh: String, userID: String, expiresAt: Date)
    case apiError(status: Int, error: String, description: String)
    case transport(URLError.Code)

    static let alreadyUsed = C98Reply.apiError(status: 400, error: "invalid_grant",
                                               description: "Invalid Refresh Token: Already Used")
    static let terminal = C98Reply.apiError(status: 400, error: "invalid_grant",
                                            description: "Invalid Refresh Token: Refresh Token Not Found")

    var kind: String {
        switch self {
        case .success: return "success"
        case .apiError(let status, _, let description): return "http\(status) \(description)"
        case .transport(let code): return "transport \(code.rawValue)"
        }
    }
}

struct C98TokenRequest {
    let index: Int
    let method: String
    let path: String
    let grantType: String?
    let presentedLabel: String
    var delivered: String?
    var callbackDone = false
    var safeguardReleased = false
}

extension AuthRefreshSlotEvent {
    var c98Label: String {
        switch self {
        case .coalesced(let reason): return "slot coalesced \(reason)"
        case .startedNew(let reason): return "slot startedNew \(reason)"
        case .finished(let reason): return "slot finished \(reason)"
        }
    }
}

// MARK: - Stub and deny-all

final class C98AuthStub: URLProtocol {
    static let baseURL = URL(string: "http://127.0.0.1:8")!
    static let probePath = "/c98-probe"
    static let timeline = C98Timeline()
    /// Entered when a request starts loading, left after its client callbacks.
    static let callbacks = DispatchGroup()

    private static let cond = NSCondition()
    private static var knownRefreshTokens: [String: String] = [:]
    private static var replies: [Int: C98Reply] = [:]
    private static var holds = Set<Int>()
    private static var requests: [C98TokenRequest] = []
    private static var probeHeaders: [String?] = []
    private static var strays: [String] = []

    static func reset() {
        cond.lock()
        knownRefreshTokens = [:]; replies = [:]; holds = []; requests = []; probeHeaders = []; strays = []
        cond.broadcast()
        cond.unlock()
        timeline.reset()
    }

    static func know(refreshToken: String, as label: String) {
        cond.lock(); knownRefreshTokens[refreshToken] = label; cond.unlock()
    }

    static func setReply(_ index: Int, _ reply: C98Reply) { cond.lock(); replies[index] = reply; cond.unlock() }
    /// Must be set BEFORE the request can arrive.
    static func hold(_ index: Int) { cond.lock(); holds.insert(index); cond.unlock() }

    static func release(_ index: Int) {
        timeline.add("token#\(index) released")
        cond.lock(); holds.remove(index); cond.broadcast(); cond.unlock()
    }

    static func releaseAll() { cond.lock(); holds.removeAll(); cond.broadcast(); cond.unlock() }

    static var tokenRequests: [C98TokenRequest] { cond.lock(); defer { cond.unlock() }; return requests }
    static var strayRequests: [String] { cond.lock(); defer { cond.unlock() }; return strays }
    static var probeCount: Int { cond.lock(); defer { cond.unlock() }; return probeHeaders.count }

    static func probeHeader(at index: Int) -> String? {
        cond.lock(); defer { cond.unlock() }
        return index < probeHeaders.count ? probeHeaders[index] : nil
    }

    static func recordStray(_ description: String) {
        cond.lock(); strays.append(description); cond.unlock()
        timeline.add("stray \(description)")
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "http" && request.url?.host == baseURL.host && request.url?.port == baseURL.port
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.callbacks.enter()
        let url = request.url!
        let method = request.httpMethod ?? "GET"

        if url.path == Self.probePath {
            let header = request.value(forHTTPHeaderField: "Authorization")
            Self.cond.lock(); Self.probeHeaders.append(header); Self.cond.unlock()
            Self.timeline.add("probe")
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                respond(url: url, status: 200, data: Data("[]".utf8))
                Self.callbacks.leave()
            }
            return
        }

        let grantType = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "grant_type" }?.value
        let json = Self.bodyData(of: request).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let presented = json?["refresh_token"] as? String

        Self.cond.lock()
        let label = presented.flatMap { Self.knownRefreshTokens[$0] }
        guard method == "POST", url.path == "/auth/v1/token", let label else {
            Self.cond.unlock()
            // Never a test-scripted refresh (for example the SDK refreshing a stored
            // session of its own). Refused with a non-2xx, so the SDK writes nothing.
            Self.recordStray("\(method) \(url.path) grant_type=\(grantType ?? "nil") knownToken=\(label != nil)")
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                respond(url: url, status: 503, data: Data(#"{"error":"c98_stray","error_description":"C-98 stray request"}"#.utf8))
                Self.callbacks.leave()
            }
            return
        }
        let index = Self.requests.count
        Self.requests.append(C98TokenRequest(index: index, method: method, path: url.path,
                                             grantType: grantType, presentedLabel: label))
        Self.timeline.add("token#\(index) arrived \(label)")
        Self.cond.unlock()

        // NEVER BLOCK IN startLoading (see QueueStubServer): the hold waits here.
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            Self.cond.lock()
            let deadline = Date().addingTimeInterval(10)
            var safeguard = false
            while Self.holds.contains(index) {
                if !Self.cond.wait(until: deadline) { safeguard = true; Self.holds.remove(index); break }
            }
            let reply = Self.replies[index]
            Self.requests[index].safeguardReleased = safeguard
            Self.cond.unlock()
            if safeguard { Self.timeline.add("token#\(index) SAFEGUARD RELEASE") }

            let delivered: String
            if let reply {
                deliver(reply, url: url)
                delivered = reply.kind
            } else {
                respond(url: url, status: 503, data: Data(#"{"error":"c98_unscripted","error_description":"C-98 unscripted"}"#.utf8))
                delivered = "unscripted"
            }
            Self.cond.lock()
            Self.requests[index].delivered = delivered
            Self.requests[index].callbackDone = true
            Self.cond.unlock()
            Self.timeline.add("token#\(index) delivered \(delivered)")
            Self.callbacks.leave()
        }
    }

    override func stopLoading() {}

    private func deliver(_ reply: C98Reply, url: URL) {
        switch reply {
        case let .success(access, refresh, userID, expiresAt):
            let body: [String: Any] = [
                "access_token": access,
                "token_type": "bearer",
                "expires_in": 3600,
                "expires_at": Int(expiresAt.timeIntervalSince1970),
                "refresh_token": refresh,
                "user": [
                    "id": userID,
                    "aud": "authenticated",
                    "app_metadata": [String: Any](),
                    "user_metadata": [String: Any](),
                    "created_at": "2026-09-15T00:00:00Z",
                    "updated_at": "2026-09-15T00:00:00Z",
                ] as [String: Any],
            ]
            respond(url: url, status: 200, data: try! JSONSerialization.data(withJSONObject: body))
        case let .apiError(status, error, description):
            let body = ["error": error, "error_description": description]
            respond(url: url, status: status, data: try! JSONSerialization.data(withJSONObject: body))
        case let .transport(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    private func respond(url: URL, status: Int, data: Data) {
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Fails, and records by method, host and path only, any other http(s) request.
final class C98DenyAll: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url, let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return !(url.host == C98AuthStub.baseURL.host && url.port == C98AuthStub.baseURL.port)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        C98AuthStub.callbacks.enter()
        C98AuthStub.recordStray("denied \(request.httpMethod ?? "GET") \(request.url?.host ?? "?")\(request.url?.path ?? "")")
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            client?.urlProtocol(self, didFailWithError: NSError(
                domain: "C98DenyAll", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "C-98 deny-all: unexpected request rejected"]))
            C98AuthStub.callbacks.leave()
        }
    }

    override func stopLoading() {}
}

// MARK: - Keychain (the product's own queries, plus the SDK session item read-only)

enum C98Keychain {
    /// Same query shape as the app's `Keychain` helper (class + account).
    static func appItem(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess ? item as? Data : nil
    }

    static func setAppItem(_ account: String, _ data: Data?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let data else { return }
        var add = base
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func setAppString(_ account: String, _ value: String?) { setAppItem(account, value.map { Data($0.utf8) }) }
    static func appString(_ account: String) -> String? { appItem(account).flatMap { String(data: $0, encoding: .utf8) } }

    /// supabase-swift 2.5.1 `KeychainLocalStorage(service: "supabase.gotrue.swift")`,
    /// key "supabase.session" (KeychainAccess query: class, service, account,
    /// synchronizable any). READ ONLY: this suite never writes or removes it.
    static func sdkSessionItem() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "supabase.gotrue.swift",
            kSecAttrAccount as String: "supabase.session",
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess ? item as? Data : nil
    }
}

// MARK: - Fixture

@MainActor
final class C98Fixture {
    let tag = String(UUID().uuidString.prefix(8)).lowercased()
    /// Upper-case, exactly as the product writes `session.user.id.uuidString`.
    let userA = UUID().uuidString
    let userB = UUID().uuidString
    private var labels: [String: String] = [:]
    private var expiries: [String: Date] = [:]

    init() {
        labels[userA] = "userA"
        labels[userB] = "userB"
    }

    func refresh(_ label: String) -> String {
        let token = "c98-\(tag)-\(label)"
        labels[token] = label
        C98AuthStub.know(refreshToken: token, as: label)
        return token
    }

    /// An unsigned JWT whose `exp` the product's expiry reader accepts.
    func access(_ label: String, sub: String, expiresIn: TimeInterval) -> String {
        func b64(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let expiry = Date().addingTimeInterval(expiresIn)
        let header = b64(Data(#"{"alg":"none","typ":"JWT"}"#.utf8))
        let payload = b64(try! JSONSerialization.data(withJSONObject: [
            "sub": sub, "exp": Int(expiry.timeIntervalSince1970), "c98": "\(tag)-\(label)",
        ]))
        let token = "\(header).\(payload).c98"
        labels[token] = label
        expiries[token] = expiry
        return token
    }

    func success(access: String, refresh: String, user: String) -> C98Reply {
        .success(access: access, refresh: refresh, userID: user, expiresAt: expiries[access] ?? Date())
    }

    func label(_ value: String?) -> String {
        guard let value else { return "nil" }
        return labels[value] ?? "other"
    }
}

struct C98Snapshot {
    let keychain: [(String, Data?)]
    let defaults: [(String, Any?)]
    let baseURL: URL?
    let authToken: String?
    let onAuthChallenge: (() async -> Bool)?
    let authorizationHeader: String?
    let sdkSession: Data?
}

struct C98State {
    var access: String
    var refresh: String
    var apple: String
    var supabaseUserID: String
    var backendUserIDDefault: String
    var backendUserID: String
    var bearer: String
    var signedIn: Bool
}

// MARK: - Tests

@MainActor
final class C98AuthRefreshLifecycleTests: XCTestCase {
    private static let keychainAccounts = ["appleUserID", "displayName", "supabaseAccessToken_v1", "supabaseRefreshToken_v1"]
    private static let defaultsKeys = ["supabaseUserID_v1", "backendUserID_v1", "api_base_url_v1", "api_token_v1", "backendMode_v1"]
    private static var unitStopped = false

    private var snapshot: C98Snapshot?
    private var auth: AuthManager?
    private var callers: [String: (task: Task<Void, Never>, group: DispatchGroup)] = [:]
    private var callerOrder: [String] = []
    private var results: [String: Bool] = [:]
    private var verificationProbeCompleted = false

    override func setUp() async throws {
        try await super.setUp()
        guard !Self.unitStopped else { throw C98NotEstablished(reason: "the C-98 unit was stopped by an earlier case") }
        guard UnitTestHost.isActive else { throw C98NotEstablished(reason: "not a hosted unit-test run") }
        guard !LocalFactoryReset.isInProgress else { throw C98NotEstablished(reason: "a factory reset is in progress") }

        C98AuthStub.reset()
        URLProtocol.registerClass(C98DenyAll.self)
        URLProtocol.registerClass(C98AuthStub.self)   // registered last, so consulted first

        AuthManager.unitTestSuppressesPostSessionScheduling = true
        AuthManager.unitTestRefreshSlotHook = { event in C98AuthStub.timeline.add(event.c98Label) }

        snapshot = try await captureSnapshot()
    }

    override func tearDown() async throws {
        if Self.unitStopped { try await super.tearDown(); return }

        C98AuthStub.releaseAll()
        for label in callerOrder { await join(label, within: 20) }
        if !(await Self.joined(C98AuthStub.callbacks, within: 15)) {
            stopUnit("stub callbacks did not finish after the case")
        }
        auth = nil

        var restoration: [(String, Bool)] = []
        var sdkUnchanged = true
        if let snapshot {
            sdkUnchanged = C98Keychain.sdkSessionItem() == snapshot.sdkSession
            if !sdkUnchanged {
                // Stop BEFORE restoring anything or unregistering interception.
                print(evidenceText(restoration: [], sdkUnchanged: false))
                stopUnit("the Supabase SDK session item changed during the case; it was not rewritten or removed")
            }
            restore(snapshot)
            var probe: (ok: Bool, header: String?) = (false, nil)
            // Not `try?`: it flattens `String?`, so an absent bearer would read as a failed probe.
            do { probe = (true, try await probeAuthorizationHeader()) } catch { probe = (false, nil) }
            verificationProbeCompleted = probe.ok
            if !(await Self.joined(C98AuthStub.callbacks, within: 15)) {
                stopUnit("the verification probe did not finish")
            }
            NetworkManager.shared.baseURL = snapshot.baseURL
            restoration = verify(snapshot, probe: probe)
        }

        URLProtocol.unregisterClass(C98AuthStub.self)
        URLProtocol.unregisterClass(C98DenyAll.self)
        AuthManager.unitTestRefreshSlotHook = nil
        AuthManager.unitTestSuppressesPostSessionScheduling = false

        let evidence = evidenceText(restoration: restoration, sdkUnchanged: sdkUnchanged)
        print(evidence)
        let attachment = XCTAttachment(string: evidence)
        attachment.name = "C-98 evidence"
        attachment.lifetime = .keepAlways
        add(attachment)

        for (name, ok) in restoration { XCTAssertTrue(ok, "C-98 restoration mismatch: \(name) (values withheld)") }

        callers = [:]; callerOrder = []; results = [:]; snapshot = nil; verificationProbeCompleted = false
        try await super.tearDown()
    }

    // MARK: Controls

    /// A-0 — no overlap: a current-token success commits the new session.
    func testA0_currentTokenSuccessCommitsTheNewSession() async throws {
        let f = C98Fixture()
        let r1 = f.refresh("R1")
        let a2 = f.access("A2", sub: f.userA, expiresIn: 3600)
        try arrange(f, mode: .localSimulation, access: f.access("A1", sub: f.userA, expiresIn: -30), refresh: r1)
        C98AuthStub.setReply(0, f.success(access: a2, refresh: f.refresh("RA2"), user: f.userA))

        try start("A") { await $0.ensureValidBackendSession(reason: "A") }
        await join("A")

        try await requireValid(tokens: ["R1"], order: ["caller A started", "token#0 arrived R1", "caller A returned"])
        let s = try await readState(f)
        XCTAssertEqual(results["A"], true)
        XCTAssertEqual(s.access, "A2"); XCTAssertEqual(s.refresh, "RA2"); XCTAssertEqual(s.bearer, "A2")
        XCTAssertEqual(s.supabaseUserID, "userA"); XCTAssertEqual(s.backendUserIDDefault, "userA")
        XCTAssertEqual(s.backendUserID, "userA"); XCTAssertEqual(s.apple, "present"); XCTAssertTrue(s.signedIn)
    }

    /// F-1 — a terminal failure of the still-current token withdraws the identity.
    func testF1_currentTokenTerminalFailureWithdraws() async throws {
        let f = C98Fixture()
        try arrange(f, mode: .localSimulation, access: f.access("A1", sub: f.userA, expiresIn: -30), refresh: f.refresh("R1"))
        C98AuthStub.setReply(0, .terminal)

        try start("A") { await $0.ensureValidBackendSession(reason: "A") }
        await join("A")

        try await requireValid(tokens: ["R1"], order: ["caller A started", "token#0 arrived R1", "caller A returned"])
        let s = try await readState(f)
        XCTAssertEqual(results["A"], false)
        XCTAssertEqual(s.access, "nil"); XCTAssertEqual(s.refresh, "nil"); XCTAssertEqual(s.bearer, "nil")
        XCTAssertEqual(s.supabaseUserID, "nil"); XCTAssertEqual(s.backendUserIDDefault, "nil")
        XCTAssertEqual(s.backendUserID, "nil"); XCTAssertEqual(s.apple, "nil"); XCTAssertFalse(s.signedIn)
    }

    /// F-2 — a transport failure of the still-current token retains everything and reports failure.
    func testF2_currentTokenTransientFailureRetains() async throws {
        let f = C98Fixture()
        try arrange(f, mode: .localSimulation, access: f.access("A1", sub: f.userA, expiresIn: -30), refresh: f.refresh("R1"))
        C98AuthStub.setReply(0, .transport(.notConnectedToInternet))

        try start("A") { await $0.ensureValidBackendSession(reason: "A") }
        await join("A")

        try await requireValid(tokens: ["R1"], order: ["caller A started", "token#0 arrived R1", "caller A returned"])
        let s = try await readState(f)
        XCTAssertEqual(results["A"], false)
        XCTAssertEqual(s.access, "A1"); XCTAssertEqual(s.refresh, "R1"); XCTAssertEqual(s.bearer, "A1")
        XCTAssertEqual(s.supabaseUserID, "userA"); XCTAssertEqual(s.backendUserIDDefault, "userA")
        XCTAssertEqual(s.backendUserID, "userA"); XCTAssertEqual(s.apple, "present"); XCTAssertTrue(s.signedIn)
    }

    /// R-1 — an older refresh answered "Already Used" after a newer forced refresh committed a
    /// session that is valid but inside the 60 s preflight skew recovers that session (skew 0).
    func testR1_alreadyUsedAfterNewerForcedCommitRecoversTheNewerSession() async throws {
        let f = C98Fixture()
        let b2 = f.access("B2", sub: f.userA, expiresIn: 30)
        try arrange(f, mode: .backendConnected, access: f.access("A1", sub: f.userA, expiresIn: -30), refresh: f.refresh("R1"))
        C98AuthStub.hold(0)
        C98AuthStub.setReply(1, f.success(access: b2, refresh: f.refresh("RB2"), user: f.userA))

        try start("A") { await $0.ensureValidBackendSession(reason: "A") }
        try await waitFor("request #0") { C98AuthStub.tokenRequests.count >= 1 }
        try start("B") { await $0.ensureValidSession(reason: "B", force: true) }
        await join("B")
        C98AuthStub.setReply(0, .alreadyUsed)
        C98AuthStub.release(0)
        await join("A")

        try await requireValid(tokens: ["R1", "R1"], order: [
            "caller A started", "slot startedNew A", "token#0 arrived R1", "caller B started", "slot startedNew B",
            "token#1 arrived R1", "caller B returned", "token#0 released", "caller A returned",
        ])
        let s = try await readState(f)
        XCTAssertEqual(results["B"], true)
        XCTAssertEqual(results["A"], true, "the older caller must recover the newer usable session")
        XCTAssertEqual(s.access, "B2"); XCTAssertEqual(s.refresh, "RB2"); XCTAssertEqual(s.bearer, "B2")
        XCTAssertEqual(s.supabaseUserID, "userA"); XCTAssertEqual(s.backendUserIDDefault, "userA")
        XCTAssertEqual(s.backendUserID, "userA"); XCTAssertEqual(s.apple, "present"); XCTAssertTrue(s.signedIn)
        XCTAssertEqual(C98AuthStub.tokenRequests.count, 2)
    }

    // MARK: Lifecycle

    /// L-1 — sign-out while a refresh is in flight; the refresh then succeeds.
    func testL1_signOutDuringRefreshIsNotUndoneBySuccess() async throws {
        try await lifecycleCase(step: "signOut", newer: nil, releaseTerminal: false) { $0.signOut() }
    }

    /// L-2 — identity withdrawal while a refresh is in flight; the refresh then succeeds.
    func testL2_identityWithdrawalDuringRefreshIsNotUndoneBySuccess() async throws {
        try await lifecycleCase(step: "clearConnectedIdentity", newer: nil, releaseTerminal: false) {
            $0.clearConnectedIdentity(reason: "c98-L2")
        }
    }

    /// L-3 — sign-out, then a newer unexpired session is persisted; the stale refresh succeeds.
    func testL3_staleSuccessDoesNotOverwriteANewerSession() async throws {
        try await lifecycleCase(step: "signOut", newer: 3600, releaseTerminal: false) { $0.signOut() }
    }

    /// L-4 — as L-3, but the stale refresh fails terminally.
    func testL4_staleTerminalFailureDoesNotWithdrawANewerSession() async throws {
        try await lifecycleCase(step: "signOut", newer: 3600, releaseTerminal: true) { $0.signOut() }
    }

    /// F-3 — sign-out, then a newer but EXPIRED session is persisted; the stale refresh succeeds.
    func testF3_staleSuccessPreservesAnExpiredNewerSession() async throws {
        try await lifecycleCase(step: "signOut", newer: -30, releaseTerminal: false) { $0.signOut() }
    }

    /// F-4 — as F-3, but the stale refresh fails terminally.
    func testF4_staleTerminalFailurePreservesAnExpiredNewerSession() async throws {
        try await lifecycleCase(step: "signOut", newer: -30, releaseTerminal: true) { $0.signOut() }
    }

    // MARK: Ownership and ordering

    /// O-1a — A and C from `ensureValidBackendSession`, B a forced `ensureValidSession`.
    func testO1a_finishingBackendSessionRefreshDoesNotReleaseANewerOwnersSlot() async throws {
        try await ownershipCase { auth, label in await auth.ensureValidBackendSession(reason: label) }
    }

    /// O-1b — A and C from `ensureValidSession`, B a forced `ensureValidSession`.
    func testO1b_finishingSessionRefreshDoesNotReleaseANewerOwnersSlot() async throws {
        try await ownershipCase { auth, label in await auth.ensureValidSession(reason: label) }
    }

    /// O-2 — a stale success arriving after a newer forced refresh committed must not overwrite it.
    func testO2_staleSuccessAfterNewerForcedCommitKeepsTheNewerSession() async throws {
        let f = C98Fixture()
        let a2 = f.access("A2", sub: f.userA, expiresIn: 3600)
        let b2 = f.access("B2", sub: f.userA, expiresIn: 3600)
        try arrange(f, mode: .backendConnected, access: f.access("A1", sub: f.userA, expiresIn: -30), refresh: f.refresh("R1"))
        C98AuthStub.hold(0)
        C98AuthStub.setReply(0, f.success(access: a2, refresh: f.refresh("RA2"), user: f.userA))
        C98AuthStub.setReply(1, f.success(access: b2, refresh: f.refresh("RB2"), user: f.userA))

        try start("A") { await $0.ensureValidBackendSession(reason: "A") }
        try await waitFor("request #0") { C98AuthStub.tokenRequests.count >= 1 }
        try start("B") { await $0.ensureValidSession(reason: "B", force: true) }
        await join("B")
        C98AuthStub.release(0)
        await join("A")

        try await requireValid(tokens: ["R1", "R1"], order: [
            "caller A started", "slot startedNew A", "token#0 arrived R1", "caller B started", "slot startedNew B",
            "token#1 arrived R1", "caller B returned", "token#0 released", "caller A returned",
        ])
        let s = try await readState(f)
        XCTAssertEqual(results["B"], true)
        XCTAssertEqual(results["A"], true, "a usable newer session is present, so the stale caller reports it")
        XCTAssertEqual(s.access, "B2", "the stale success must not overwrite the newer committed session")
        XCTAssertEqual(s.refresh, "RB2"); XCTAssertEqual(s.bearer, "B2")
        XCTAssertEqual(s.supabaseUserID, "userA"); XCTAssertEqual(s.backendUserIDDefault, "userA")
        XCTAssertEqual(s.backendUserID, "userA"); XCTAssertEqual(s.apple, "present"); XCTAssertTrue(s.signedIn)
        XCTAssertEqual(C98AuthStub.tokenRequests.count, 2)
    }

    // MARK: Shared case bodies

    /// `newer`: nil = no newer session; otherwise the newer access token's expiry offset.
    private func lifecycleCase(step: String, newer: TimeInterval?, releaseTerminal: Bool,
                               _ lifecycle: (AuthManager) -> Void) async throws {
        let f = C98Fixture()
        let a2 = f.access("A2", sub: f.userA, expiresIn: 3600)
        try arrange(f, mode: .localSimulation, access: f.access("A1", sub: f.userA, expiresIn: -30), refresh: f.refresh("R1"))
        C98AuthStub.hold(0)
        C98AuthStub.setReply(0, releaseTerminal ? .terminal : f.success(access: a2, refresh: f.refresh("RA2"), user: f.userA))

        try start("A") { await $0.ensureValidBackendSession(reason: "A") }
        try await waitFor("request #0") { C98AuthStub.tokenRequests.count >= 1 }

        guard let auth else { throw C98NotEstablished(reason: "no AuthManager arranged") }
        C98AuthStub.timeline.add("step \(step)")
        lifecycle(auth)
        if let newer {
            // A newer sign-in, modelled by persisted state only (currentUserID stays nil).
            let b = f.access("B", sub: f.userB, expiresIn: newer)
            C98Keychain.setAppString("supabaseAccessToken_v1", b)
            C98Keychain.setAppString("supabaseRefreshToken_v1", f.refresh("RB"))
            UserDefaults.standard.set(f.userB, forKey: "supabaseUserID_v1")
            UserDefaults.standard.set(f.userB, forKey: "backendUserID_v1")
            NetworkManager.shared.setBearerToken(b)
            C98AuthStub.timeline.add("step newer session arranged")
        }
        C98AuthStub.release(0)
        await join("A")

        try await requireValid(tokens: ["R1"], order: [
            "caller A started", "token#0 arrived R1", "step \(step)", "token#0 released", "caller A returned",
        ])
        let s = try await readState(f)
        XCTAssertEqual(results["A"], false, "no locally signed-in identity remains, so the stale caller must report failure")
        XCTAssertFalse(s.signedIn)
        XCTAssertEqual(s.apple, "nil")
        XCTAssertEqual(s.backendUserID, "nil", "the stale refresh must not repopulate the in-memory backend user id")
        if newer == nil {
            XCTAssertEqual(s.access, "nil", "the stale refresh must not resurrect an access token")
            XCTAssertEqual(s.refresh, "nil", "the stale refresh must not resurrect a refresh token")
            XCTAssertEqual(s.bearer, "nil", "the stale refresh must not resurrect the bearer")
            XCTAssertEqual(s.supabaseUserID, "nil"); XCTAssertEqual(s.backendUserIDDefault, "nil")
        } else {
            XCTAssertEqual(s.access, "B", "the newer session's access token must be preserved")
            XCTAssertEqual(s.refresh, "RB", "the newer session's refresh token must be preserved")
            XCTAssertEqual(s.bearer, "B", "the newer session's bearer must be preserved")
            XCTAssertEqual(s.supabaseUserID, "userB"); XCTAssertEqual(s.backendUserIDDefault, "userB")
        }
        XCTAssertEqual(C98AuthStub.tokenRequests.count, 1)
    }

    private func ownershipCase(_ call: @escaping @MainActor (AuthManager, String) async -> Bool) async throws {
        let f = C98Fixture()
        // A2 is issued already expired, so a slot-less C must spend a token again.
        let a2 = f.access("A2", sub: f.userA, expiresIn: -30)
        let b2 = f.access("B2", sub: f.userA, expiresIn: 3600)
        let c2 = f.access("C2", sub: f.userA, expiresIn: 3600)
        try arrange(f, mode: .backendConnected, access: f.access("A1", sub: f.userA, expiresIn: -30), refresh: f.refresh("R1"))
        C98AuthStub.hold(0)
        C98AuthStub.hold(1)
        C98AuthStub.setReply(0, f.success(access: a2, refresh: f.refresh("RA2"), user: f.userA))
        C98AuthStub.setReply(1, f.success(access: b2, refresh: f.refresh("RB2"), user: f.userA))
        C98AuthStub.setReply(2, f.success(access: c2, refresh: f.refresh("RC2"), user: f.userA))

        try start("A") { await call($0, "A") }
        try await waitFor("request #0") { C98AuthStub.tokenRequests.count >= 1 }
        try start("B") { await $0.ensureValidSession(reason: "B", force: true) }
        try await waitFor("request #1 and B's slot event") {
            C98AuthStub.tokenRequests.count >= 2 && C98AuthStub.timeline.firstIndex(prefix: "slot startedNew B") != nil
        }
        C98AuthStub.release(0)
        await join("A")

        try start("C") { await call($0, "C") }
        try await waitFor("C's slot event") { !Self.slotEvents(for: "C").isEmpty }
        C98AuthStub.timeline.add("step C slot observed while B held")
        C98AuthStub.release(1)
        await join("B")
        await join("C")

        var tokens = ["R1", "R1"]
        if C98AuthStub.tokenRequests.count > 2 { tokens.append("RA2") }
        try await requireValid(tokens: tokens, order: [
            "caller A started", "slot startedNew A", "token#0 arrived R1", "caller B started", "slot startedNew B",
            "token#1 arrived R1", "token#0 released", "caller A returned", "caller C started",
            "step C slot observed while B held", "token#1 released",
        ])
        XCTAssertEqual(Self.slotEvents(for: "C"), ["slot coalesced C"],
                       "B still owns the in-flight refresh, so C must join it rather than start its own")
        XCTAssertEqual(C98AuthStub.tokenRequests.count, 2, "C must not spend another refresh token")
    }

    private static func slotEvents(for reason: String) -> [String] {
        C98AuthStub.timeline.entries(prefix: "slot ").filter {
            $0.hasSuffix(" \(reason)") && !$0.hasPrefix("slot finished")
        }
    }

    // MARK: Arrangement

    private func arrange(_ f: C98Fixture, mode: BackendMode, access: String, refresh: String) throws {
        setBackendMode(mode)
        BackendConfig.apiBaseURL = C98AuthStub.baseURL
        BackendConfig.apiToken = "c98-anon-key"
        NetworkManager.shared.configure(baseURL: C98AuthStub.baseURL, authToken: "c98-anon-key")
        NetworkManager.shared.setBearerToken(nil)
        C98Keychain.setAppString("appleUserID", "c98-apple-\(f.tag)")
        C98Keychain.setAppItem("displayName", nil)
        C98Keychain.setAppString("supabaseAccessToken_v1", access)
        C98Keychain.setAppString("supabaseRefreshToken_v1", refresh)
        UserDefaults.standard.set(f.userA, forKey: "supabaseUserID_v1")
        UserDefaults.standard.set(f.userA, forKey: "backendUserID_v1")

        let manager = AuthManager(identityService: LocalStubIdentityService())
        guard manager.currentUserID != nil, manager.backendUserID == f.userA,
              BackendEnvironment.shared.mode == mode, BackendConfig.isConfigured else {
            throw C98NotEstablished(reason: "the AuthManager fixture did not load the arranged identity, mode and configuration")
        }
        auth = manager
    }

    private func start(_ label: String, _ call: @escaping @MainActor (AuthManager) async -> Bool) throws {
        guard let auth else { throw C98NotEstablished(reason: "no AuthManager arranged") }
        let group = DispatchGroup()
        group.enter()
        C98AuthStub.timeline.add("caller \(label) started")
        let task = Task { @MainActor [weak self] in
            let ok = await call(auth)
            self?.results[label] = ok
            C98AuthStub.timeline.add("caller \(label) returned \(ok)")
            group.leave()
        }
        callers[label] = (task, group)
        callerOrder.append(label)
    }

    /// A real join: the completion group first (bounded), then the Task itself.
    private func join(_ label: String, within seconds: Double = 15) async {
        guard let entry = callers[label] else { return }
        guard await Self.joined(entry.group, within: seconds) else {
            stopUnit("caller \(label) did not finish within \(Int(seconds)) s")
        }
        await entry.task.value
    }

    private func waitFor(_ what: String, timeout: Double = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                throw C98NotEstablished(reason: "timed out waiting for \(what); timeline: \(C98AuthStub.timeline.all)")
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    nonisolated private static func joined(_ group: DispatchGroup, within seconds: Double) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: group.wait(timeout: .now() + seconds) == .success)
            }
        }
    }

    // MARK: Witnesses

    private func requireValid(tokens: [String], order: [String]) async throws {
        guard await Self.joined(C98AuthStub.callbacks, within: 15) else {
            stopUnit("stub callbacks did not finish")
        }
        let requests = C98AuthStub.tokenRequests
        for (i, presented) in tokens.enumerated() {
            guard i < requests.count else {
                throw C98NotEstablished(reason: "the real SDK refresh request #\(i) was not intercepted")
            }
            let r = requests[i]
            guard r.method == "POST", r.path == "/auth/v1/token", r.grantType == "refresh_token",
                  r.presentedLabel == presented else {
                throw C98NotEstablished(reason: "request #\(i) was \(r.method) \(r.path) grant_type=\(r.grantType ?? "nil") presenting \(r.presentedLabel); expected the SDK refresh presenting \(presented)")
            }
        }
        for r in requests {
            guard !r.safeguardReleased else {
                throw C98NotEstablished(reason: "request #\(r.index) was released by the 10 s safeguard, not by the case")
            }
            guard r.callbackDone, let delivered = r.delivered, delivered != "unscripted" else {
                throw C98NotEstablished(reason: "request #\(r.index) did not complete with its scripted reply")
            }
        }
        let strays = C98AuthStub.strayRequests
        guard strays.isEmpty else { throw C98NotEstablished(reason: "stray requests: \(strays)") }
        var last = -1
        for entry in order {
            guard let index = C98AuthStub.timeline.firstIndex(prefix: entry), index > last else {
                throw C98NotEstablished(reason: "ordering witness failed at '\(entry)'; timeline: \(C98AuthStub.timeline.all)")
            }
            last = index
        }
    }

    private func readState(_ f: C98Fixture) async throws -> C98State {
        let header = try await probeAuthorizationHeader()
        let bearer = header.map { $0.hasPrefix("Bearer ") ? String($0.dropFirst("Bearer ".count)) : "malformed" }
        return C98State(
            access: f.label(C98Keychain.appString("supabaseAccessToken_v1")),
            refresh: f.label(C98Keychain.appString("supabaseRefreshToken_v1")),
            apple: C98Keychain.appItem("appleUserID") == nil ? "nil" : "present",
            supabaseUserID: f.label(UserDefaults.standard.string(forKey: "supabaseUserID_v1")),
            backendUserIDDefault: f.label(UserDefaults.standard.string(forKey: "backendUserID_v1")),
            backendUserID: f.label(auth?.backendUserID),
            bearer: f.label(bearer),
            signedIn: auth?.currentUserID != nil)
    }

    /// The live bearer as NetworkManager sends it. Only `baseURL` is retargeted, to the
    /// stub, for the probe, and the value in effect before it is put back.
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

    // MARK: Snapshot and restoration

    private func captureSnapshot() async throws -> C98Snapshot {
        let keychain = Self.keychainAccounts.map { ($0, C98Keychain.appItem($0)) }
        let defaults: [(String, Any?)] = Self.defaultsKeys.map { ($0, UserDefaults.standard.object(forKey: $0)) }
        let baseURL = NetworkManager.shared.baseURL
        let authToken = NetworkManager.shared.authToken
        let challenge = NetworkManager.shared.onAuthChallenge
        let sdk = C98Keychain.sdkSessionItem()
        let header = try await probeAuthorizationHeader()
        return C98Snapshot(keychain: keychain, defaults: defaults, baseURL: baseURL, authToken: authToken,
                           onAuthChallenge: challenge, authorizationHeader: header, sdkSession: sdk)
    }

    private func restore(_ s: C98Snapshot) {
        for (account, data) in s.keychain { C98Keychain.setAppItem(account, data) }
        for (key, value) in s.defaults {
            if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        NetworkManager.shared.baseURL = s.baseURL
        NetworkManager.shared.authToken = s.authToken
        NetworkManager.shared.onAuthChallenge = s.onAuthChallenge
        let header = s.authorizationHeader
        NetworkManager.shared.setBearerToken(header.flatMap {
            $0.hasPrefix("Bearer ") ? String($0.dropFirst("Bearer ".count)) : nil
        })
    }

    private func verify(_ s: C98Snapshot, probe: (ok: Bool, header: String?)) -> [(String, Bool)] {
        var out: [(String, Bool)] = []
        for (account, data) in s.keychain { out.append(("keychain \(account)", C98Keychain.appItem(account) == data)) }
        for (key, value) in s.defaults {
            out.append(("defaults \(key)", Self.same(UserDefaults.standard.object(forKey: key), value)))
        }
        out.append(("NetworkManager.baseURL", NetworkManager.shared.baseURL == s.baseURL))
        out.append(("NetworkManager.authToken", NetworkManager.shared.authToken == s.authToken))
        out.append(("NetworkManager.onAuthChallenge presence (closure identity is not comparable)",
                    (NetworkManager.shared.onAuthChallenge != nil) == (s.onAuthChallenge != nil)))
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

    private func evidenceText(restoration: [(String, Bool)], sdkUnchanged: Bool) -> String {
        var lines = ["C98-EVIDENCE \(name)"]
        lines.append("  timeline: " + C98AuthStub.timeline.all.joined(separator: " → "))
        for r in C98AuthStub.tokenRequests {
            lines.append("  request #\(r.index): \(r.method) \(r.path) grant_type=\(r.grantType ?? "nil") presented=\(r.presentedLabel) delivered=\(r.delivered ?? "nil") callbackDone=\(r.callbackDone) safeguard=\(r.safeguardReleased)")
        }
        lines.append("  strays: \(C98AuthStub.strayRequests)")
        lines.append("  results: " + callerOrder.map { "\($0)=\(results[$0].map(String.init) ?? "nil")" }.joined(separator: " "))
        lines.append("  SDK session item present at start: \(snapshot?.sdkSession != nil); unchanged: \(sdkUnchanged)")
        lines.append("  saved bearer present: \(snapshot?.authorizationHeader != nil); verification probe completed: \(verificationProbeCompleted)")
        for (name, ok) in restoration { lines.append("  restored \(name): \(ok)") }
        return lines.joined(separator: "\n")
    }

    /// An unjoinable task, an unfinished callback or a changed SDK session item STOPS the
    /// unit: nothing is restored, interception and fixture state stay installed, and this
    /// thread is parked so no later test in the invocation runs. The run wrapper
    /// terminates the invocation when it sees the marker.
    private func stopUnit(_ why: String) -> Never {
        Self.unitStopped = true
        let marker = "C98-UNIT-STOP: \(why). Interception, hooks and fixture state are left installed; nothing is restored."
        print(marker)
        NSLog("%@", marker)
        XCTFail(marker)
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline { Thread.sleep(forTimeInterval: 1) }
        fatalError(marker)
    }
}
