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

    static func reset() {
        cond.lock(); rows = []; requestLog = []; holds = []; failing = []; cond.broadcast(); cond.unlock()
    }
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
        let key = "\(isDemote ? "DEMOTE" : method) \(id)"

        Self.cond.lock()
        Self.requestLog.append(key)
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
            while Self.holds.contains(key) {
                if !Self.cond.wait(until: deadline) { break }
            }
            var status = 204
            var data = Data()
            if Self.failing.contains(key) {
                status = 500
            } else {
                switch method {
                case "POST": Self.rows.insert(id); status = 201
                case "DELETE": Self.rows.remove(id)
                case "GET":
                    status = 200
                    data = Data((Self.rows.contains(id) ? #"[{"attachments":[]}]"# : "[]").utf8)
                default: break
                }
            }
            Self.requestLog.append("\(key) done \(status)")
            Self.cond.unlock()

            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !data.isEmpty { self.client?.urlProtocol(self, didLoad: data) }
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

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
        NetworkManager.shared.setBearerToken("stub-bearer")
        UserDefaults.standard.set(ownerUID, forKey: "supabaseUserID_v1")
        setBackendMode(.backendConnected)
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
