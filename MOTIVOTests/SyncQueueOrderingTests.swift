//
//  SyncQueueOrderingTests.swift
//  MOTIVOTests
//
//  C-87 (independent audit A2) and C-91 (independent audit A7). FAILING-FIRST.
//
//  THREE CLASSES, DELIBERATELY SEPARATE (revised 2026-09-14 on review):
//
//  1. SyncQueueIntentAcceptanceTests — THE REQUIREMENTS, stated so that ANY
//     correct implementation passes them: the member's latest intent stays
//     durable until ITS OWN successful acknowledgement, a completed unshare
//     leaves no remote post, and an operation already in flight is not issued a
//     second time. None of them requires overlapping requests, so a single-flight
//     fix that prevents overlap is not penalised for it. These accept the fix.
//
//  2. SyncQueueOrderingReproductionTests — THE OLD ORDERINGS, as evidence of the
//     defect. Each case checks that its specific sequence ACTUALLY OCCURRED and
//     skips, saying so, when it did not — a failing assertion alone does not
//     prove the sequence happened, and a correct fix may make the sequence
//     unreachable. When the sequence did occur, the case asserts the correct
//     outcome. These are not acceptance criteria.
//
//  3. SyncQueueFactoryResetTests — C-91, running the real reset coordinator.
//
//  C-87. `flushNow()` iterates a snapshot of `items`, awaits the network, and
//  on success dequeues BY POST ID, so an older operation's acknowledgement
//  removes a newer intent that C-61's last-intent replacement put there. There
//  is no single-flight guard.
//
//  C-91. `stopForFactoryReset()` sets `isFactoryResetting` and nothing clears
//  it, so after a reset and re-onboarding in the same process every flush
//  returns immediately; and the pre-reset flush carries on through its snapshot.
//
//  NO NETWORK AND NO BACKEND. A URLProtocol stub answers only 127.0.0.1:9 and
//  models one `posts` table (POST creates, DELETE removes, GET reports). It can
//  HOLD a request mid-flight. Every case attaches its request timeline, with the
//  test's own steps marked into it, pass or fail.
//
//  BASELINE EVIDENCE IS RETAINED in docs/audit-findings.md (C-87, C-91),
//  including the two harness misses found on the way.
//
//  THE C-91 GATE IS GONE, AS PLANNED. At 3c68d81 resetting the shared queue
//  disabled it for every later test in the process -- the defect itself -- so
//  these cases ran only under TEST_RUNNER_ETUDES_QUEUE_RESET_ISOLATED=1, and
//  both failed there (recorded in the register). With the queue re-armed at
//  the end of LocalFactoryReset.perform they join the full suite, and that
//  full-suite run is itself evidence the reset no longer poisons later tests.
//

import XCTest
@testable import Etudes

// MARK: - Stub server

final class QueueStubServer: URLProtocol {
    static let baseURL = URL(string: "http://127.0.0.1:9")!

    private static let cond = NSCondition()
    private static var rows = Set<String>()
    private static var requestLog: [String] = []
    private static var holds = Set<String>()
    private static var failing = Set<String>()

    // P6-I-02 Unit 2b — ADDITIVE. Who each request was sent AS, the exact URL it
    // went to, one-shot forced statuses, and attachment refs a GET should report.
    private static var auth: [(key: String, sub: String?, jti: String?)] = []
    private static var urls: [(key: String, url: String)] = []
    private static var forced: [String: [Int]] = [:]
    private static var refs: [String: [String]] = [:]
    private static var rowOwners: [String: String] = [:]

    // P6-I-02 Unit 2c — ADDITIVE.
    private static var forcedBodies: [String: [String]] = [:]
    private static var dropAfterApply = Set<String>()
    private static var deferredCommits = Set<String>()

    // U3 — ADDITIVE, OFF BY DEFAULT. When on, a posts request carrying
    // `owner_user_id=eq.<X>` sees a row only if X owns it, as RLS plus the
    // client's owner filter would. Existing suites never turn it on.
    private static var enforceOwnerFilter = false
    static func enforceOwnerFilterForTest() { cond.lock(); enforceOwnerFilter = true; cond.unlock() }
    /// A row owned by `owner`, with these storage object paths as its refs.
    static func seedRow(_ id: UUID, objectPaths: [String], owner: String) {
        cond.lock()
        let k = id.uuidString.uppercased()
        rows.insert(k); refs[k] = objectPaths; rowOwners[k] = owner.lowercased()
        cond.unlock()
    }

    /// P6-I-02 Unit 2b. Set when the CLIENT abandons a request before its
    /// response was produced — the observable form of cancellation.
    private var loadingKey: String?
    private var responded = false
    private var abandoned = false

    static func reset() {
        cond.lock(); rows = []; requestLog = []; holds = []; failing = []
        auth = []; urls = []; forced = [:]; refs = [:]; rowOwners = [:]
        forcedBodies = [:]; dropAfterApply = []; deferredCommits = []
        enforceOwnerFilter = false
        cond.broadcast(); cond.unlock()
    }

    /// Answer `key` with `status` the next time it arrives (queued, one per arrival).
    static func respond(_ key: String, with status: Int) {
        cond.lock(); forced[key, default: []].append(status); cond.unlock()
    }
    /// Answer `key` with this exact 2xx BODY the next time (queued).
    static func respondBody(_ key: String, _ body: String) {
        cond.lock(); forcedBodies[key, default: []].append(body); cond.unlock()
    }
    /// APPLY `key`'s effect, then lose the response: the client gets a
    /// transport error although the server did the work.
    static func dropResponseAfterApplying(_ key: String) {
        cond.lock(); dropAfterApply.insert(key); cond.unlock()
    }
    /// The next POST for `id` answers a transport error WITHOUT committing; the
    /// row appears only when `commitDeferred(id)` is called — a late commit.
    static func deferCommit(_ id: UUID) {
        cond.lock(); deferredCommits.insert(id.uuidString.uppercased()); cond.unlock()
    }
    static func commitDeferred(_ id: UUID) {
        cond.lock(); rows.insert(id.uuidString.uppercased()); cond.unlock()
    }
    /// A row that already exists, with these storage object paths as its refs.
    static func seedRow(_ id: UUID, objectPaths: [String]) {
        cond.lock(); rows.insert(id.uuidString.uppercased()); refs[id.uuidString.uppercased()] = objectPaths; cond.unlock()
    }
    /// Every subject a request was sent as, in order.
    static var subjects: [String?] { cond.lock(); defer { cond.unlock() }; return auth.map { $0.sub } }
    static func subjects(for key: String) -> [String?] {
        cond.lock(); defer { cond.unlock() }; return auth.filter { $0.key == key }.map { $0.sub }
    }
    static func jtis(for key: String) -> [String?] {
        cond.lock(); defer { cond.unlock() }; return auth.filter { $0.key == key }.map { $0.jti }
    }
    static var allURLs: [(key: String, url: String)] { cond.lock(); defer { cond.unlock() }; return urls }
    static func rowOwner(_ id: UUID) -> String? { cond.lock(); defer { cond.unlock() }; return rowOwners[id.uuidString.uppercased()] }
    /// True if any request whose key starts with `prefix` arrived.
    static func arrived(prefix: String) -> Bool {
        cond.lock(); defer { cond.unlock() }
        return requestLog.contains { $0.hasPrefix(prefix) && !$0.contains(" done ") && !$0.hasSuffix(" abandoned") }
    }
    /// Keys of requests that arrived, in order, without the "done"/"abandoned" lines.
    static var arrivals: [String] {
        cond.lock(); defer { cond.unlock() }
        return requestLog.filter { !$0.hasPrefix("— ") && !$0.contains(" done ") && !$0.hasSuffix(" abandoned") }
    }
    /// Storage objects are keyed by their file name: "POST OBJ <name>", "DELETE OBJ <name>".
    static func objectKey(_ op: String, _ name: String) -> String { "\(op) OBJ \(name.uppercased())" }
    static func hold(_ key: String) { cond.lock(); holds.insert(key); cond.unlock() }
    static func release(_ key: String) { cond.lock(); holds.remove(key); cond.broadcast(); cond.unlock() }
    static func releaseAll() { cond.lock(); holds.removeAll(); cond.broadcast(); cond.unlock() }
    static func fail(_ key: String) { cond.lock(); failing.insert(key); cond.unlock() }
    static func unfail(_ key: String) { cond.lock(); failing.remove(key); cond.unlock() }
    /// A test step, written into the same timeline as the requests.
    static func mark(_ step: String) { cond.lock(); requestLog.append("— \(step)"); cond.unlock() }
    static func count(_ key: String) -> Int { cond.lock(); defer { cond.unlock() }; return requestLog.filter { $0 == key }.count }
    static func hasRow(_ id: UUID) -> Bool { cond.lock(); defer { cond.unlock() }; return rows.contains(id.uuidString.uppercased()) }
    static var log: [String] { cond.lock(); defer { cond.unlock() }; return requestLog }
    /// Timeline position, for "did X happen after this point".
    static var position: Int { cond.lock(); defer { cond.unlock() }; return requestLog.count }
    /// True if `<key> done <2xx>` was logged at or after `position`.
    static func succeeded(_ key: String, since position: Int) -> Bool {
        cond.lock(); defer { cond.unlock() }
        return requestLog.dropFirst(position).contains { $0.hasPrefix("\(key) done 2") }
    }
    static func arrived(_ key: String, since position: Int) -> Bool {
        cond.lock(); defer { cond.unlock() }
        return requestLog.dropFirst(position).contains(key)
    }

    /// "POST <ID>", "PATCH <ID>", "DEMOTE <ID>" (a PATCH whose body is exactly
    /// `{"is_public":false}`), "GET <ID>", "DELETE <ID>". A request is logged
    /// on ARRIVAL; "<KEY> done <status>" when its response is produced.
    static func key(_ op: String, _ id: UUID) -> String { "\(op) \(id.uuidString.uppercased())" }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == baseURL.host && request.url?.port == baseURL.port
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let body = Self.bodyData(of: request)
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let id = ((method == "POST" ? json?["id"] as? String : Self.queryID(request.url)) ?? "").uppercased()
        let isDemote = method == "PATCH" && json?.count == 1 && (json?["is_public"] as? Bool) == false
        let isObject = request.url?.path.contains("/storage/v1/object/") == true
        // P6-I-02 Unit 2b. The attachment-refs PATCH is keyed apart from the
        // metadata PATCH, so each publish phase can be held and observed alone.
        let isRefs = method == "PATCH" && json?.count == 1 && json?["attachments"] != nil
        let key = isObject
            ? Self.objectKey(method, request.url!.lastPathComponent)
            : "\(isDemote ? "DEMOTE" : (isRefs ? "REFS" : method)) \(id)"
        let claims = Self.claims(request.value(forHTTPHeaderField: "Authorization"))

        Self.cond.lock()
        loadingKey = key
        Self.requestLog.append(key)
        Self.auth.append((key, claims.sub, claims.jti))
        Self.urls.append((key, request.url?.absoluteString ?? ""))
        if method == "POST", !isObject, let owner = json?["owner_user_id"] as? String { Self.rowOwners[id] = owner }
        Self.cond.broadcast()
        Self.cond.unlock()

        // NEVER BLOCK HERE. URLSession starts every custom-protocol request on one
        // loader thread, so waiting inside startLoading serialised ALL requests
        // behind a held one. Measured 2026-09-14: the first version did exactly
        // that, and a case predicted to fail passed because the withdrawal could
        // not begin until the held publish finished. The hold now waits here.
        let url = request.url!
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            Self.cond.lock()
            let deadline = Date().addingTimeInterval(10)
            while Self.holds.contains(key) && !self.abandoned {
                if !Self.cond.wait(until: deadline) { break }
            }
            if self.abandoned {
                Self.cond.unlock()
                return
            }
            self.responded = true
            var status = 204
            var data = Data()
            var transportFailure = false
            let wantsRows = self.request.value(forHTTPHeaderField: "Prefer")?.contains("return=representation") == true
            // U3. Hidden from this request when the owner filter names someone else.
            let filterOwner = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .first(where: { $0.name == "owner_user_id" })?.value.map { $0.hasPrefix("eq.") ? String($0.dropFirst(3)) : $0 }
            let hidden = Self.enforceOwnerFilter && !isObject && filterOwner != nil
                && Self.rowOwners[id] != filterOwner?.lowercased()
            let rowJSON = #"[{"id":""# + id + #""}]"#
            if var bodies = Self.forcedBodies[key], !bodies.isEmpty {
                data = Data(bodies.removeFirst().utf8)
                Self.forcedBodies[key] = bodies
                status = 200
                if method == "DELETE" { Self.rows.remove(id) }
            } else if method == "POST", !isObject, Self.deferredCommits.contains(id) {
                // Received, NOT committed; the client is told it failed.
                Self.deferredCommits.remove(id)
                transportFailure = true
            } else if var queued = Self.forced[key], !queued.isEmpty {
                status = queued.removeFirst()
                Self.forced[key] = queued
            } else if Self.failing.contains(key) {
                status = 500
            } else if isObject {
                status = 200
            } else {
                switch method {
                case "POST": Self.rows.insert(id); status = 201
                case "DELETE":
                    let existed = !hidden && Self.rows.remove(id) != nil
                    if wantsRows { status = 200; data = Data((existed ? rowJSON : "[]").utf8) }
                case "PATCH" where wantsRows:
                    status = 200; data = Data((Self.rows.contains(id) && !hidden ? rowJSON : "[]").utf8)
                case "GET":
                    status = 200
                    if Self.rows.contains(id) && !hidden {
                        let paths = (Self.refs[id] ?? []).map { #"{"bucket":"attachments","path":""# + $0 + #""}"# }
                        let body = #"[{"attachments":["# + paths.joined(separator: ",") + "]}]"
                        data = Data(body.utf8)
                    } else {
                        data = Data("[]".utf8)
                    }
                default: break
                }
            }
            if Self.dropAfterApply.remove(key) != nil { transportFailure = true }
            Self.requestLog.append(transportFailure ? "\(key) lost" : "\(key) done \(status)")
            Self.cond.unlock()
            if transportFailure {
                self.client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                return
            }

            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty { self.client?.urlProtocol(self, didLoad: data) }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        Self.cond.lock()
        if !responded, let key = loadingKey, !abandoned {
            abandoned = true
            Self.requestLog.append("\(key) abandoned")
            Self.cond.broadcast()
        }
        Self.cond.unlock()
    }

    /// True if the client abandoned `key` before any response was produced.
    static func abandoned(_ key: String) -> Bool {
        cond.lock(); defer { cond.unlock() }
        return requestLog.contains("\(key) abandoned")
    }

    /// The bearer's `sub` and `jti`, read without verification — the stub only
    /// needs to know who a request CLAIMED to be.
    private static func claims(_ header: String?) -> (sub: String?, jti: String?) {
        guard let header, header.hasPrefix("Bearer ") else { return (nil, nil) }
        let parts = header.dropFirst(7).split(separator: ".")
        guard parts.count >= 2 else { return (nil, nil) }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return (nil, nil) }
        return ((obj["sub"] as? String)?.lowercased(), obj["jti"] as? String)
    }

    private static func queryID(_ url: URL?) -> String? {
        guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "id" })?.value else { return nil }
        return raw.hasPrefix("eq.") ? String(raw.dropFirst(3)) : raw
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

// MARK: - Shared fixture

@MainActor
enum QueueStubFixture {
    static let ownerUID = "00000000-0000-0000-0000-0000000c8701"

    /// `resetServer: false` is RE-ONBOARDING: configuration, identity and mode
    /// are set again, but held requests and the timeline are left alone.
    static func connect(resetServer: Bool = true) {
        URLProtocol.registerClass(QueueStubServer.self)
        if resetServer { QueueStubServer.reset() }
        BackendConfig.apiBaseURL = QueueStubServer.baseURL
        BackendConfig.apiToken = "stub-anon-key"
        NetworkManager.shared.baseURL = QueueStubServer.baseURL
        // P6-I-02 Unit 2b. A REAL TOKEN SHAPE. The queue now sends only as a
        // token whose subject is the work's owner; the old "stub-bearer" has no
        // subject, so every queued item would (correctly) be held. Unsigned — the
        // stub never verifies — with a synthetic subject on disposable data.
        NetworkManager.shared.setBearerToken(token(sub: ownerUID, jti: "fixture"))
        UserDefaults.standard.set(ownerUID, forKey: "supabaseUserID_v1")
        setBackendMode(.backendConnected)
    }

    /// An unsigned JWT carrying `sub` and `jti`. Synthetic; never a real credential.
    static func token(sub: String, jti: String) -> String {
        func b64(_ s: String) -> String {
            Data(s.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return b64(#"{"alg":"none","typ":"JWT"}"#) + "." + b64(#"{"sub":""# + sub + #"","jti":""# + jti + #""}"#) + ".unsigned"
    }

    static func disconnect() {
        QueueStubServer.releaseAll()
        URLProtocol.unregisterClass(QueueStubServer.self)
        NetworkManager.shared.setBearerToken(nil)
        UserDefaults.standard.removeObject(forKey: "supabaseUserID_v1")
        setBackendMode(.localSimulation)
    }

    static func payload(_ id: UUID, shared: Bool) -> SessionSyncQueue.PostPublishPayload {
        // P6-I-02. The production capture site now binds the owner at the
        // member's action, so a fixture that enqueues directly must do the same
        // or it is modelling a path the app no longer has. The owner is NOT
        // defaulted in production — adopting the current login is the defect.

        SessionSyncQueue.PostPublishPayload(id: id, sessionID: nil, sessionTimestamp: nil, title: "c87",
                                            durationSeconds: 60, activityType: nil, activityDetail: nil,
                                            instrumentLabel: nil, mood: nil, effort: nil, isPublic: shared).withOwner(SessionSyncQueue.currentOwner())
    }

    /// Poll without asserting: used where a correct implementation may never
    /// reach the condition, so a timeout is an expected outcome, not a failure.
    static func poll(timeout: TimeInterval = 1.5, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !condition() && Date() < end { try? await Task.sleep(nanoseconds: 5_000_000) }
        return condition()
    }

    /// Flush until nothing for `id` remains queued, or give up. Converges
    /// whatever intent is left, as later foregrounds would.
    static func drain(_ queue: SessionSyncQueue, _ id: UUID, attempts: Int = 5) async {
        for _ in 0..<attempts where queue.items.contains(where: { $0.id == id }) {
            await queue.flushNow()
        }
    }

    static func attachTimeline(to testCase: XCTestCase) {
        let attachment = XCTAttachment(string: QueueStubServer.log.joined(separator: "\n"))
        attachment.name = "request timeline"
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
    }

    static func hasUnshare(_ queue: SessionSyncQueue, _ id: UUID) -> Bool {
        queue.items.contains(where: { $0.id == id && $0.op == .unshare })
    }

    struct SetupNotEstablished: Error, CustomStringConvertible {
        let description: String
    }

    /// Start a publish of `id` and return once its POST is held in flight.
    ///
    /// THROWS IF THE INITIAL UPLOAD IS NOT OBSERVED. Every race test below is
    /// about what happens WHILE this publish is in flight; if the POST never
    /// arrived, nothing after this line tests the race at all, and a pass or a
    /// failure would both be meaningless. The test fails at setup instead.
    static func publishHeldInFlight(_ queue: SessionSyncQueue, _ id: UUID) async throws -> Task<Void, Never> {
        QueueStubServer.hold(QueueStubServer.key("POST", id))
        queue.enqueue(payload(id, shared: true))
        let flush = Task { await queue.flushNow() }
        guard await poll(timeout: 5, { QueueStubServer.count(QueueStubServer.key("POST", id)) == 1 }) else {
            QueueStubServer.releaseAll()
            await flush.value
            throw SetupNotEstablished(description: "setup: the initial POST was never observed in flight. Requests: \(QueueStubServer.log)")
        }
        QueueStubServer.mark("setup: initial POST held in flight")
        return flush
    }
}

// MARK: - C-87 / A2 — ACCEPTANCE (implementation-agnostic requirements)

@MainActor
final class SyncQueueIntentAcceptanceTests: XCTestCase {

    /// C-100: fails the test if the host app's launch activation writes the backend mode.
    private let activationSentinel = AppActivationWriteSentinel()

    private var queue: SessionSyncQueue { SessionSyncQueue.shared }

    override func setUp() async throws {
        try await super.setUp()
        activationSentinel.start()
        QueueStubFixture.connect()
        // C-100: really wired to the stub, or this test fails here.
        try LocalStackSupport.requireRealBackend(baseURL: QueueStubServer.baseURL.absoluteString)
        queue.clear()
    }

    override func tearDown() async throws {
        activationSentinel.assertNoHostActivationWrites()
        QueueStubFixture.attachTimeline(to: self)
        QueueStubServer.releaseAll()
        queue.clear()
        QueueStubFixture.disconnect()
        try await super.tearDown()
    }

    /// REQUIREMENT: the latest intent leaves the queue only through its OWN
    /// successful acknowledgement, and once it converges the post is absent.
    /// A fix that processes the unshare within the same flush passes.
    func testLatestIntentIsDurableUntilItsOwnSuccessfulAcknowledgement() async throws {
        let a = UUID()
        let flush = try await QueueStubFixture.publishHeldInFlight(queue, a)

        QueueStubServer.mark("enqueue unshare")
        let since = QueueStubServer.position
        queue.enqueue(QueueStubFixture.payload(a, shared: false))
        QueueStubServer.mark("release POST")
        QueueStubServer.release(QueueStubServer.key("POST", a))
        await flush.value

        let ownSuccess = QueueStubServer.succeeded(QueueStubServer.key("DELETE", a), since: since)
        QueueStubServer.mark("flush returned; unshare queued=\(QueueStubFixture.hasUnshare(queue, a)); unshare succeeded=\(ownSuccess)")
        XCTAssertTrue(QueueStubFixture.hasUnshare(queue, a) || ownSuccess,
                      "the unshare may leave the queue only through its own successful completion")

        await QueueStubFixture.drain(queue, a)
        XCTAssertFalse(queue.items.contains(where: { $0.id == a }), "the unshare converges")
        XCTAssertFalse(QueueStubServer.hasRow(a), "a converged unshare leaves no remote post. Requests: \(QueueStubServer.log)")
    }

    /// REQUIREMENT: a withdrawal whose own attempts have all failed stays
    /// queued, however the older publish ends; it converges once it can.
    /// Does not require the withdrawal to be attempted while the publish is held.
    func testFailingWithdrawalIsNeverDroppedBeforeItSucceeds() async throws {
        let a = UUID()
        QueueStubServer.fail(QueueStubServer.key("DEMOTE", a))
        let flush = try await QueueStubFixture.publishHeldInFlight(queue, a)

        queue.enqueue(QueueStubFixture.payload(a, shared: false))
        let second = Task { await queue.flushNow() }   // permitted, never required, to overlap
        QueueStubServer.release(QueueStubServer.key("POST", a))
        await flush.value
        await second.value
        await queue.flushNow()                          // a further attempt, still failing

        XCTAssertTrue(QueueStubFixture.hasUnshare(queue, a),
                      "a withdrawal that has never succeeded must remain queued. Requests: \(QueueStubServer.log)")

        QueueStubServer.mark("withdrawal can now succeed")
        QueueStubServer.unfail(QueueStubServer.key("DEMOTE", a))
        await QueueStubFixture.drain(queue, a)
        XCTAssertFalse(queue.items.contains(where: { $0.id == a }), "the withdrawal converges once it can")
        XCTAssertFalse(QueueStubServer.hasRow(a), "and leaves no remote post")
    }

    /// REQUIREMENT: whatever the interleaving, when the member's final choice is
    /// unshare and it converges, no post remains.
    func testConvergedUnshareLeavesNoRemotePostWhateverTheOrder() async throws {
        let a = UUID()
        let flush = try await QueueStubFixture.publishHeldInFlight(queue, a)

        let since = QueueStubServer.position
        queue.enqueue(QueueStubFixture.payload(a, shared: false))
        let second = Task { await queue.flushNow() }
        let reverseOrder = await QueueStubFixture.poll { QueueStubServer.succeeded(QueueStubServer.key("DELETE", a), since: since) }
        QueueStubServer.mark("withdrawal completed before the older upload = \(reverseOrder)")

        QueueStubServer.release(QueueStubServer.key("POST", a))
        await flush.value
        await second.value
        await QueueStubFixture.drain(queue, a)

        XCTAssertFalse(queue.items.contains(where: { $0.id == a }), "the unshare converges")
        XCTAssertFalse(QueueStubServer.hasRow(a), "no post may remain. Requests: \(QueueStubServer.log)")
    }

    /// REQUIREMENT: an operation already in flight is not issued a second time.
    /// Does not require a second flush to overlap; it only forbids a duplicate.
    func testAnInFlightOperationIsNotIssuedTwice() async throws {
        let a = UUID()
        let flush = try await QueueStubFixture.publishHeldInFlight(queue, a)

        let second = Task { await queue.flushNow() }
        _ = await QueueStubFixture.poll { QueueStubServer.count(QueueStubServer.key("POST", a)) >= 2 }
        QueueStubServer.release(QueueStubServer.key("POST", a))
        await flush.value
        await second.value

        XCTAssertEqual(QueueStubServer.count(QueueStubServer.key("POST", a)), 1,
                       "one queued publish must produce one upload while it is in flight. Requests: \(QueueStubServer.log)")
    }
}

// MARK: - C-87 / A2 — REPRODUCTION (old orderings; skip when not exercised)

@MainActor
final class SyncQueueOrderingReproductionTests: XCTestCase {

    /// C-100: fails the test if the host app's launch activation writes the backend mode.
    private let activationSentinel = AppActivationWriteSentinel()

    private var queue: SessionSyncQueue { SessionSyncQueue.shared }

    override func setUp() async throws {
        try await super.setUp()
        activationSentinel.start()
        QueueStubFixture.connect()
        // C-100: really wired to the stub, or this test fails here.
        try LocalStackSupport.requireRealBackend(baseURL: QueueStubServer.baseURL.absoluteString)
        queue.clear()
    }

    override func tearDown() async throws {
        activationSentinel.assertNoHostActivationWrites()
        QueueStubFixture.attachTimeline(to: self)
        QueueStubServer.releaseAll()
        queue.clear()
        QueueStubFixture.disconnect()
        try await super.tearDown()
    }

    /// SEQUENCE: the older publish's flush returns having sent NO request for the
    /// newer unshare. Only then can its acknowledgement be the thing that removed it.
    func testReproOlderPublishAcknowledgementRemovesNewerUnshare() async throws {
        let a = UUID()
        let flush = try await QueueStubFixture.publishHeldInFlight(queue, a)
        let since = QueueStubServer.position
        queue.enqueue(QueueStubFixture.payload(a, shared: false))
        QueueStubServer.release(QueueStubServer.key("POST", a))
        await flush.value

        let exercised = !QueueStubServer.arrived(QueueStubServer.key("DEMOTE", a), since: since)
        QueueStubServer.mark("sequence exercised (no unshare request in that flush) = \(exercised)")
        try XCTSkipUnless(exercised, "sequence not exercised: the unshare was attempted within the same flush")
        XCTAssertTrue(QueueStubFixture.hasUnshare(queue, a),
                      "the older publish's acknowledgement removed the newer, never-attempted unshare")
    }

    /// SEQUENCE: the withdrawal is SENT and FAILS while the publish is still
    /// held, then the publish succeeds. Measured 2026-09-14 at 3c68d81: occurred
    /// in 2 of 3 repeats; in the third no withdrawal was sent, cause not established.
    func testReproFailedWithdrawalThenOlderPublishSuccess() async throws {
        let a = UUID()
        QueueStubServer.fail(QueueStubServer.key("DEMOTE", a))
        let flush = try await QueueStubFixture.publishHeldInFlight(queue, a)
        queue.enqueue(QueueStubFixture.payload(a, shared: false))
        let since = QueueStubServer.position
        let second = Task { await queue.flushNow() }
        let exercised = await QueueStubFixture.poll(timeout: 5) {
            QueueStubServer.log.dropFirst(since).contains(QueueStubServer.key("DEMOTE", a) + " done 500")
        }
        QueueStubServer.mark("sequence exercised (withdrawal failed while publish held) = \(exercised)")
        QueueStubServer.release(QueueStubServer.key("POST", a))
        await flush.value
        await second.value

        try XCTSkipUnless(exercised, "sequence not exercised: no withdrawal was sent and failed while the publish was held")
        XCTAssertTrue(QueueStubFixture.hasUnshare(queue, a),
                      "the older publish's success removed a withdrawal that had only failed")
    }

    /// SEQUENCE: the withdrawal COMPLETES (row deleted) while the publish is
    /// still held; then the older upload lands.
    func testReproCompletedWithdrawalThenOlderUpload() async throws {
        let a = UUID()
        let flush = try await QueueStubFixture.publishHeldInFlight(queue, a)
        let since = QueueStubServer.position
        queue.enqueue(QueueStubFixture.payload(a, shared: false))
        let second = Task { await queue.flushNow() }
        let exercised = await QueueStubFixture.poll(timeout: 5) {
            QueueStubServer.succeeded(QueueStubServer.key("DELETE", a), since: since)
        }
        QueueStubServer.mark("sequence exercised (withdrawal completed while publish held) = \(exercised)")
        QueueStubServer.release(QueueStubServer.key("POST", a))
        await flush.value
        await second.value
        await QueueStubFixture.drain(queue, a)

        try XCTSkipUnless(exercised, "sequence not exercised: the withdrawal did not complete while the publish was held")
        XCTAssertFalse(QueueStubServer.hasRow(a), "the older upload recreated a post the member had withdrawn")
    }
}

// MARK: - C-91 / A7

@MainActor
final class SyncQueueFactoryResetTests: XCTestCase {

    /// C-100: fails the test if the host app's launch activation writes the backend mode.
    private let activationSentinel = AppActivationWriteSentinel()

    private var queue: SessionSyncQueue { SessionSyncQueue.shared }

    override func setUp() async throws {
        try await super.setUp()
        activationSentinel.start()
        QueueStubFixture.connect()
        // C-100: really wired to the stub, or this test fails here.
        try LocalStackSupport.requireRealBackend(baseURL: QueueStubServer.baseURL.absoluteString)
        queue.clear()
    }

    override func tearDown() async throws {
        activationSentinel.assertNoHostActivationWrites()
        QueueStubFixture.attachTimeline(to: self)
        QueueStubServer.releaseAll()
        queue.clear()
        QueueStubFixture.disconnect()
        try await super.tearDown()
    }

    /// Reset and re-onboard in the SAME process, then publish. Runs the real
    /// reset coordinator against the simulator test host only.
    func testPublishingWorksAfterFactoryResetWithoutRestart() async throws {
        let before = UUID(), after = UUID()
        queue.enqueue(QueueStubFixture.payload(before, shared: true))

        QueueStubServer.mark("factory reset")
        await LocalFactoryReset.perform(reason: "C-91 test", auth: AuthManager(identityService: LocalStubIdentityService()))
        XCTAssertTrue(queue.items.isEmpty, "control: the reset clears queued items")

        QueueStubServer.mark("re-onboard; enqueue and flush")
        QueueStubFixture.connect(resetServer: false)
        queue.enqueue(QueueStubFixture.payload(after, shared: true))
        await queue.flushNow()
        QueueStubServer.mark("flush returned")

        XCTAssertEqual(QueueStubServer.count(QueueStubServer.key("POST", before)), 0, "control: pre-reset work never uploads")
        XCTAssertEqual(QueueStubServer.count(QueueStubServer.key("POST", after)), 1,
                       "a publish after re-onboarding must upload without an app restart. Requests: \(QueueStubServer.log)")
    }

    /// A flush that was mid-flight when the reset began must not carry on
    /// uploading the rest of its pre-reset snapshot once it resumes.
    func testInFlightFlushDoesNotContinueAfterReset() async throws {
        let a = UUID(), c = UUID()
        QueueStubServer.hold(QueueStubServer.key("POST", a))
        queue.enqueue(QueueStubFixture.payload(a, shared: true))
        queue.enqueue(QueueStubFixture.payload(c, shared: true))
        let flush = Task { await queue.flushNow() }
        guard await QueueStubFixture.poll(timeout: 5, { QueueStubServer.count(QueueStubServer.key("POST", a)) == 1 }) else {
            QueueStubServer.releaseAll(); await flush.value
            throw QueueStubFixture.SetupNotEstablished(description: "setup: POST a was never observed in flight. Requests: \(QueueStubServer.log)")
        }

        QueueStubServer.mark("factory reset while POST a is held")
        await LocalFactoryReset.perform(reason: "C-91 test", auth: AuthManager(identityService: LocalStubIdentityService()))
        QueueStubFixture.connect(resetServer: false)
        QueueStubServer.mark("re-onboarded; release POST a")
        QueueStubServer.release(QueueStubServer.key("POST", a))
        await flush.value
        QueueStubServer.mark("pre-reset flush returned")

        XCTAssertEqual(QueueStubServer.count(QueueStubServer.key("POST", c)), 0,
                       "pre-reset queued work must not upload after the reset. Requests: \(QueueStubServer.log)")
    }
}
