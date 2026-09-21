//
//  C70DirectoryWriteTransportTests.swift
//  MOTIVOTests
//
//  CHANGE-ID: 20260920_191000_C70_DirectoryWriteTransport
//  SCOPE: C-70 — the directory write on the real NetworkManager path. What the
//  pure tests cannot establish is the REQUEST: that an existing-row edit is an
//  owner-filtered PATCH asking for a representation, that creation is the only
//  POST, that a refusal provokes exactly one bounded probe and never a retry
//  loop, and that a 403 neither refreshes a session nor is re-sent.
//  SEARCH-TOKEN: 20260920_191000_C70_DirectoryWriteTransport
//

import XCTest
@testable import Etudes

/// Answers `account_directory` requests from a script and records each one.
final class C70DirectoryStub: URLProtocol {
    struct Recorded {
        let method: String
        let url: URL
        let prefer: String?
        let body: [String: Any]
    }
    /// `nil` status means "fail the request at the transport".
    struct Reply { let status: Int?; let body: String }

    static let lock = NSLock()
    static var replies: [Reply] = []
    static var recorded: [Recorded] = []
    /// Fired on the URLSession thread once the request has been SENT and before
    /// its response is delivered — the window in which an identity change or a
    /// newer submission can overtake a write that is already in flight.
    static var onRequest: (() -> Void)?

    static func reset(_ replies: [Reply]) {
        lock.lock(); self.replies = replies; recorded = []; onRequest = nil; lock.unlock()
    }
    static var requests: [Recorded] {
        lock.lock(); defer { lock.unlock() }; return recorded
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path.contains("account_directory") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // `httpBody` is nil once URLSession has consumed it; the stream copy is
        // what a URLProtocol actually sees.
        var bodyData = request.httpBody
        if bodyData == nil, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 8192)
            var collected = Data()
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                collected.append(contentsOf: buffer[0..<read])
            }
            stream.close()
            bodyData = collected
        }
        let parsed = (try? JSONSerialization.jsonObject(with: bodyData ?? Data())) as? [String: Any] ?? [:]

        Self.lock.lock()
        Self.recorded.append(Recorded(method: request.httpMethod ?? "",
                                      url: request.url!,
                                      prefer: request.value(forHTTPHeaderField: "Prefer"),
                                      body: parsed))
        let reply = Self.replies.isEmpty
            ? Reply(status: 500, body: "unscripted")
            : Self.replies.removeFirst()
        let hook = Self.onRequest
        Self.lock.unlock()
        hook?()

        guard let status = reply.status else {
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class C70DirectoryWriteTransportTests: XCTestCase {

    private var owner = ""
    private var savedBaseURL: URL?
    private var savedAuthToken: String?
    private var savedChallenge: (() async -> Bool)?
    private var savedSupabaseUserID: String?
    private var savedMode: BackendMode = .localSimulation

    /// A token whose `sub` is the owner — `boundRequest` refuses to send
    /// without one, which is the outbound half of the identity binding.
    private func token(sub: String) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: ["sub": sub])
        let b64 = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(b64).signature"
    }

    override func setUp() async throws {
        try await super.setUp()
        owner = UUID().uuidString.lowercased()
        URLProtocol.registerClass(C70DirectoryStub.self)
        savedBaseURL = NetworkManager.shared.baseURL
        savedAuthToken = NetworkManager.shared.authToken
        savedChallenge = NetworkManager.shared.onAuthChallenge
        savedSupabaseUserID = UserDefaults.standard.string(forKey: "supabaseUserID_v1")
        savedMode = currentBackendMode()

        UserDefaults.standard.set(owner, forKey: "supabaseUserID_v1")
        setBackendMode(.backendConnected)
        NetworkManager.shared.configure(baseURL: URL(string: "https://c70.invalid")!,
                                        authToken: "c70-anon-key")
        NetworkManager.shared.setBearerToken(token(sub: owner))
        DirectoryWriteCoordinator.shared.resetForTesting()
    }

    override func tearDown() async throws {
        // The bearer cannot be read back, so it is CLEARED rather than restored —
        // leaving a fake token installed would contaminate every later test.
        NetworkManager.shared.setBearerToken(nil)
        NetworkManager.shared.onAuthChallenge = savedChallenge
        NetworkManager.shared.configure(baseURL: savedBaseURL, authToken: savedAuthToken)
        setBackendMode(savedMode)
        if let savedSupabaseUserID {
            UserDefaults.standard.set(savedSupabaseUserID, forKey: "supabaseUserID_v1")
        } else {
            UserDefaults.standard.removeObject(forKey: "supabaseUserID_v1")
        }
        DirectoryWriteCoordinator.shared.resetForTesting()
        URLProtocol.unregisterClass(C70DirectoryStub.self)
        try await super.tearDown()
    }

    private func row(_ userID: String,
                     displayName: String = "Ada",
                     accountID: String? = nil,
                     location: String? = "London",
                     instruments: [String] = ["piano"]) -> String {
        let acct = accountID.map { "\"\($0)\"" } ?? "null"
        let loc = location.map { "\"\($0)\"" } ?? "null"
        let inst = "[" + instruments.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        return "[{\"user_id\":\"\(userID)\",\"display_name\":\"\(displayName)\","
             + "\"account_id\":\(acct),\"location\":\(loc),\"instruments\":\(inst)}]"
    }

    // `selfRow(...)` was removed with the generation tests that were its only
    // callers. It built a `SelfDirectoryRow` fixture for `fetchSelfRow`, which
    // generation called before deriving a handle; nothing in this suite reads
    // the self row any more.

    /// **FIXTURE-HELPER EDIT, not a retired test.** `accountID:` is gone here
    /// because `upsertSelfRow` no longer accepts one. `row(...)` KEEPS its
    /// `accountID:` parameter deliberately — it models the SERVER's response,
    /// which still carries the column, and several tests rely on a response
    /// carrying a handle still decoding cleanly.
    private func write(displayName: String = "Ada",
                       location: String? = "London",
                       instruments: [String]? = ["piano"],
                       authChallenge: (() async -> Bool)? = nil) async -> DirectoryWriteResult {
        await AccountDirectoryService.shared.upsertSelfRow(userID: owner,
                                                           displayName: displayName,
                                                           location: location,
                                                           instruments: instruments,
                                                           authChallenge: authChallenge)
    }

    private func query(_ url: URL) -> [String: String] {
        var out: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            out[item.name] = item.value
        }
        return out
    }

    // MARK: - The existing-row edit

    /// An existing-row edit is an owner-filtered PATCH, which is what reaches
    /// the UNGATED owner-UPDATE policy D-U6-3 intends. The upsert it replaces
    /// was evaluated against the GATED insert policy even when only an update
    /// would occur.
    func testAnExistingRowEditIsAnOwnerBoundPatchAskingForEvidence() async {
        C70DirectoryStub.reset([.init(status: 200, body: row(owner))])
        let result = await write()

        let reqs = C70DirectoryStub.requests
        XCTAssertEqual(reqs.count, 1)
        XCTAssertEqual(reqs[0].method, "PATCH")
        XCTAssertEqual(query(reqs[0].url)["user_id"], "eq.\(owner)")
        XCTAssertEqual(query(reqs[0].url)["select"], DirectoryWriteEvidence.selectList)
        XCTAssertEqual(reqs[0].prefer, "return=representation")
        XCTAssertNil(reqs[0].body["user_id"],
                     "a PATCH must not carry user_id: this path cannot reassign a row's owner")
        // The handle is removed from the product but the COLUMN is still
        // deployed, with its UNIQUE constraint and its existing values. Sending
        // it is how a client would clear or clobber a value nobody can see any
        // more; omitting it is what leaves an existing value untouched, because
        // PostgREST does not write a column a payload does not carry.
        XCTAssertNil(reqs[0].body["account_id"],
                     "no directory write may carry account_id")
        XCTAssertTrue(result.isApplied)
    }

    /// CP-3: profile publishing cannot disturb a discovery preference, and now
    /// cannot even read one back.
    func testNoPrivacyOrAvatarColumnIsSentOrRequested() async {
        C70DirectoryStub.reset([.init(status: 200, body: row(owner))])
        _ = await write()
        let r = C70DirectoryStub.requests[0]
        let select = query(r.url)["select"] ?? ""
        for forbidden in ["lookup_enabled", "follow_requests_enabled", "avatar_key", "avatar_version"] {
            XCTAssertNil(r.body[forbidden], "\(forbidden) must never be written by a profile publish")
            XCTAssertFalse(select.contains(forbidden), "\(forbidden) must never be selected back")
        }
    }

    // MARK: - Missing row and its race

    func testNothingMatchedFallsThroughToGatedCreation() async {
        C70DirectoryStub.reset([.init(status: 200, body: "[]"),
                                .init(status: 201, body: row(owner))])
        let result = await write()

        let reqs = C70DirectoryStub.requests
        XCTAssertEqual(reqs.count, 2)
        XCTAssertEqual(reqs[0].method, "PATCH")
        XCTAssertEqual(reqs[1].method, "POST")
        XCTAssertEqual(query(reqs[1].url)["on_conflict"], "user_id")
        XCTAssertEqual(reqs[1].prefer, "resolution=merge-duplicates,return=representation")
        XCTAssertEqual(reqs[1].body["user_id"] as? String, owner,
                       "creation carries the owner; the policy's with_check pins it")
        // The creation fallback is a SECOND payload built by a different branch,
        // so asserting the PATCH alone would leave half the writer unchecked —
        // a first Connected establishment goes down exactly this path.
        XCTAssertNil(reqs[1].body["account_id"],
                     "the missing-row creation must not carry account_id either")
        XCTAssertTrue(result.isApplied)
    }

    /// **EXACTLY ONE bounded probe, and it PROBES rather than proves.** A
    /// refusal does not establish that a row now exists, so if the probe also
    /// matches nothing the write stays unconfirmed and the refusal that was
    /// actually observed is what is reported.
    func testARefusedCreationProvokesExactlyOneProbeAndThenStops() async {
        C70DirectoryStub.reset([.init(status: 200, body: "[]"),
                                .init(status: 403, body: #"{"code":"42501","message":"rls"}"#),
                                .init(status: 200, body: "[]")])
        let result = await write()

        let reqs = C70DirectoryStub.requests
        XCTAssertEqual(reqs.map(\.method), ["PATCH", "POST", "PATCH"],
                       "one probe, and no loop")
        guard case .refusedByPolicy = result.outcome else {
            return XCTFail("an unconfirmed probe leaves the observed refusal standing, got \(result.outcome)")
        }
    }

    func testAProbeThatFindsTheRowSucceeds() async {
        C70DirectoryStub.reset([.init(status: 200, body: "[]"),
                                .init(status: 403, body: #"{"code":"42501","message":"rls"}"#),
                                .init(status: 200, body: row(owner))])
        let result = await write()
        XCTAssertEqual(C70DirectoryStub.requests.count, 3)
        XCTAssertTrue(result.isApplied)
    }

    // MARK: - Refusals, ambiguity and retries

    /// C-57: a 403 is an AUTHORISATION denial. Refreshing cannot change it, and
    /// the refresh path signs the member out.
    func testAPolicyRefusalNeitherRefreshesNorRetries() async {
        var challenges = 0
        NetworkManager.shared.onAuthChallenge = { challenges += 1; return true }
        C70DirectoryStub.reset([.init(status: 403, body: #"{"code":"42501","message":"rls"}"#)])

        let result = await write()

        XCTAssertEqual(C70DirectoryStub.requests.count, 1, "a 403 is never re-sent")
        XCTAssertEqual(challenges, 0, "a 403 must never provoke a session refresh")
        guard case .refusedByPolicy = result.outcome else { return XCTFail("got \(result.outcome)") }
    }

    // MARK: - C-70 remaining gaps: the scoped 401 handler

    /// **NARROW CLAIM, named for what it actually shows: HANDLER SELECTION and
    /// the retry.** The stub handler returns `true` without rotating a bearer, so
    /// this establishes that the per-operation handler is the one consulted, that
    /// the global one is not, and that a successful challenge produces exactly one
    /// retry. **It does NOT establish that a real token refresh occurred** — that
    /// is `AuthManager`'s behaviour and is covered by `C98AuthRefreshLifecycleTests`
    /// against the scripted auth harness.
    func testAScoped401HandlerIsTheOneConsultedAndTheRetrySucceeds() async {
        var global = 0, scoped = 0
        NetworkManager.shared.onAuthChallenge = { global += 1; return true }
        C70DirectoryStub.reset([.init(status: 401, body: #"{"message":"JWT expired"}"#),
                                .init(status: 200, body: row(owner))])

        let result = await write(authChallenge: { scoped += 1; return true })

        XCTAssertEqual(scoped, 1, "the per-operation handler must be the one consulted")
        XCTAssertEqual(global, 0, "the global handler must not run when a scoped one is supplied")
        XCTAssertEqual(C70DirectoryStub.requests.count, 2, "one 401, one retry")
        XCTAssertTrue(result.isApplied)
    }

    /// Every OTHER caller is unchanged: with no scoped handler the global slot
    /// is used exactly as before.
    func testWithNoScopedHandlerTheGlobalOneIsStillUsed() async {
        var global = 0
        NetworkManager.shared.onAuthChallenge = { global += 1; return true }
        C70DirectoryStub.reset([.init(status: 401, body: #"{"message":"JWT expired"}"#),
                                .init(status: 200, body: row(owner))])

        let result = await write()

        XCTAssertEqual(global, 1, "the default path must fall back to the global slot")
        XCTAssertEqual(C70DirectoryStub.requests.count, 2)
        XCTAssertTrue(result.isApplied)
    }

    /// A 403 is a policy refusal, not an auth failure — neither handler runs.
    func testAScopedHandlerIsNotConsultedOnA403() async {
        var scoped = 0
        C70DirectoryStub.reset([.init(status: 403, body: #"{"code":"42501","message":"rls"}"#)])

        let result = await write(authChallenge: { scoped += 1; return true })

        XCTAssertEqual(scoped, 0, "a 403 must never provoke a refresh, scoped or global")
        XCTAssertEqual(C70DirectoryStub.requests.count, 1)
        guard case .refusedByPolicy = result.outcome else { return XCTFail("got \(result.outcome)") }
    }

    /// A refusal to refresh is not a retry: the original 401 stands.
    func testAScopedHandlerThatCannotRefreshDoesNotRetry() async {
        var scoped = 0
        C70DirectoryStub.reset([.init(status: 401, body: #"{"message":"JWT expired"}"#)])

        let result = await write(authChallenge: { scoped += 1; return false })

        XCTAssertEqual(scoped, 1)
        XCTAssertEqual(C70DirectoryStub.requests.count, 1, "a failed refresh must not be retried")
        XCTAssertFalse(result.isApplied)
    }

    /// **The C-98 boundary, on the scoped route.** An identity change DURING the
    /// refresh must abandon the operation rather than retry it under whoever
    /// replaced the owner — the scoped handler gains no latitude here, because
    /// `boundRequest` resolves it inside the same owner/generation guards.
    func testAnIdentityChangeDuringTheScopedRefreshAbandonsTheWrite() async {
        C70DirectoryStub.reset([.init(status: 401, body: #"{"message":"JWT expired"}"#),
                                .init(status: 200, body: row(owner))])

        let before = DirectoryWriteCoordinator.shared.identityGeneration
        let result = await write(authChallenge: {
            // A REAL transition: the generation ADVANCES. `resetForTesting()`
            // would set it back to 0 — this suite's own starting value — so it
            // would not be a transition at all, and the guard would be tested
            // against an unchanged generation.
            DirectoryWriteCoordinator.shared.noteIdentityTransition()
            XCTAssertGreaterThan(DirectoryWriteCoordinator.shared.identityGeneration, before,
                                 "the harness must actually advance the generation")
            return true
        })

        XCTAssertEqual(C70DirectoryStub.requests.count, 1,
                       "the retry must not be sent after the owner moved")
        XCTAssertFalse(result.isApplied)
    }

    /// The request was sent and its outcome is unknown. A blind replay could
    /// duplicate a server effect, so there is none.
    func testAnAmbiguousTransportFailureIsNeverReplayedOrCalledSaved() async {
        C70DirectoryStub.reset([.init(status: nil, body: "")])
        let result = await write()
        XCTAssertEqual(C70DirectoryStub.requests.count, 1, "an unknown outcome is never retried")
        XCTAssertFalse(result.isApplied)
        guard case .ambiguous = result.outcome else { return XCTFail("got \(result.outcome)") }
    }

    /// **CONVERTED when the handle was removed. The CLASSIFICATION is the point
    /// now, and the copy deliberately is not.**
    ///
    /// The new client never writes `account_id`, so it cannot provoke this
    /// itself — but the column, its UNIQUE constraint and every existing value
    /// are still deployed, and an older installed client still writes it. A
    /// 23505 naming that constraint therefore remains a real server answer that
    /// must be told apart from a primary-key conflict rather than degrading to
    /// an untyped failure.
    ///
    /// What changed is the COPY: with no Account ID field on screen, naming one
    /// would break C-70(a)'s own rule, so a collision now reads as the generic
    /// line. Asserted against `genericMessage` directly, not via the alias, so
    /// this still fails if the alias is ever pointed back at a field-naming
    /// string.
    func testANamedHandleCollisionIsStillTypedButNoLongerNamesAField() async {
        C70DirectoryStub.reset([.init(status: 409, body:
            #"{"code":"23505","message":"duplicate key value violates unique constraint \"account_directory_account_id_key\""}"#)])
        let result = await write()
        guard case .accountIDTaken = result.outcome else { return XCTFail("got \(result.outcome)") }
        XCTAssertEqual(DirectorySyncFailure.message(for: result.outcome),
                       DirectorySyncFailure.genericMessage,
                       "a member with no Account ID field must not be told one is taken")
    }

    // MARK: - No false success reaches the shared identity

    func testAnEvidencedWritePublishesTheServersRow() async {
        C70DirectoryStub.reset([.init(status: 200, body: row(owner, displayName: "Ada", location: "London"))])
        let result = await write(displayName: "Ada", location: "London")
        XCTAssertTrue(result.isApplied)
        XCTAssertEqual(BackendFeedStore.shared.directoryAccountsByUserID[owner]?.displayName, "Ada")
    }

    /// **A row we cannot account for is the last thing that belongs in the
    /// shared identity** — that publication is how a value the member never
    /// saved reached surfaces other than the one they edited.
    func testAnUnevidencedRowIsNeverPublished() async {
        C70DirectoryStub.reset([.init(status: 200, body: row(owner, displayName: "Somebody Else"))])
        let result = await write(displayName: "Ada")
        guard case .notEvidenced = result.outcome else { return XCTFail("got \(result.outcome)") }
        XCTAssertNil(BackendFeedStore.shared.directoryAccountsByUserID[owner],
                     "an unevidenced receipt must not reach the identity cache")
    }

    func testAZeroRowWriteIsNeverPublishedAndNeverSaved() async {
        C70DirectoryStub.reset([.init(status: 200, body: "[]"),
                                .init(status: 200, body: "[]")])
        let result = await write()
        XCTAssertFalse(result.isApplied)
        XCTAssertNil(BackendFeedStore.shared.directoryAccountsByUserID[owner])
    }

    /// A receipt naming another row is refused even though the request itself
    /// succeeded — the outbound binding and the returned row are two gates.
    func testAReceiptForAnotherRowIsNeverPublished() async {
        let stranger = UUID().uuidString.lowercased()
        C70DirectoryStub.reset([.init(status: 200, body: row(stranger))])
        let result = await write()
        XCTAssertFalse(result.isApplied)
        XCTAssertNil(BackendFeedStore.shared.directoryAccountsByUserID[stranger])
    }

    /// A missing selected column would read as nil and CLEAR a cached value the
    /// write never targeted.
    func testAReceiptMissingASelectedColumnIsNotAccepted() async {
        let partial = "[{\"user_id\":\"\(owner)\",\"display_name\":\"Ada\",\"account_id\":null}]"
        C70DirectoryStub.reset([.init(status: 200, body: partial)])
        let result = await write()
        XCTAssertFalse(result.isApplied)
        XCTAssertNil(BackendFeedStore.shared.directoryAccountsByUserID[owner])
    }

    // MARK: - Identity

    func testAWriteIsNotSentWhenTheBoundOwnerIsNoLongerSignedIn() async {
        C70DirectoryStub.reset([.init(status: 200, body: row(owner))])
        UserDefaults.standard.set(UUID().uuidString.lowercased(), forKey: "supabaseUserID_v1")

        let result = await write()

        XCTAssertEqual(C70DirectoryStub.requests.count, 0,
                       "the gate refuses before dispatch, not after the response")
        guard case .supersededIdentity = result.outcome else { return XCTFail("got \(result.outcome)") }
    }

    /// The bound credential must be the owner's. A token for somebody else is
    /// not a request this owner may send, whatever the response would say.
    func testAWriteIsNotSentUnderAnotherIdentitysToken() async {
        C70DirectoryStub.reset([.init(status: 200, body: row(owner))])
        NetworkManager.shared.setBearerToken(token(sub: UUID().uuidString.lowercased()))

        let result = await write()

        XCTAssertEqual(C70DirectoryStub.requests.count, 0)
        guard case .supersededIdentity = result.outcome else { return XCTFail("got \(result.outcome)") }
    }

    // MARK: - Staleness arriving while the write is in flight

    /// **An identity transition landing after the request was sent.** The write
    /// is applied on the SERVER and must not be applied HERE: its effects
    /// belong to a session that has since been torn down.
    ///
    /// The guard that stops it is inside the cache actor, not on the caller —
    /// the caller's check runs before a suspension the transition can slip
    /// through.
    func testAnIdentityTransitionAfterDispatchWithholdsEveryLocalEffect() async {
        let validity = DirectoryWriteCoordinator.shared.validity
        C70DirectoryStub.reset([.init(status: 200, body: row(owner))])
        C70DirectoryStub.onRequest = { validity.noteIdentityTransition() }

        let result = await write()

        XCTAssertEqual(C70DirectoryStub.requests.count, 1, "the request WAS sent")
        XCTAssertNil(BackendFeedStore.shared.directoryAccountsByUserID[owner],
                     "a receipt for a session that has ended must not reach the shared identity")
        XCTAssertFalse(DirectoryWriteCoordinator.shared.mayApplyEffects(owner: owner,
                                                                        capturedGeneration: result.generation,
                                                                        seq: result.seq),
                       "and the caller must be told its own effects are stale")
    }

    /// **A newer write submitted while this one is in flight.** The older
    /// receipt is valid and still must not be published: the newer intent is
    /// about to replace it.
    func testANewerSubmissionDuringFlightWithholdsTheOlderMerge() async {
        let validity = DirectoryWriteCoordinator.shared.validity
        C70DirectoryStub.reset([.init(status: 200, body: row(owner))])
        // Sequences are global and monotonic, so any larger value stands for a
        // submission this write has not seen.
        C70DirectoryStub.onRequest = { validity.noteSubmission(owner: self.owner, seq: 9_999) }

        let result = await write()

        XCTAssertTrue(result.isApplied, "the server did apply it")
        XCTAssertNil(BackendFeedStore.shared.directoryAccountsByUserID[owner],
                     "but a receipt stale against local intent is not published")
    }

    // MARK: - F2 — the reconciliation, driving the POLICY and the REAL WRITER
    //
    // These do not assert that a view is wired. They run the production decision
    // (`DirectoryReconciliationPolicy`) against the production writer
    // (`upsertSelfRow`) in the order the app would, so what is measured is the
    // SEQUENCE of real requests.

    private typealias Completion = MembershipAttestationCoordinator.AttestationCompletion

    /// The loop ProfileView runs, driving **the production evaluator itself** —
    /// `DirectoryReconciliationEvaluator`, the same instance type the view holds
    /// — rather than a reimplementation of its rules.
    ///
    /// **It does NOT establish that the view's observers are wired.** That is a
    /// separate structural assertion in `FreshJoinContinuationStructureTests`;
    /// this driver would keep passing with every `onChange` deleted, which is
    /// exactly why both exist.
    @MainActor
    private final class ReconcileDriver {
        let evaluator = DirectoryReconciliationEvaluator()
        var outstandingFailure = false
        var rowAbsence: AuthManager.DirectoryRowAbsence?
        private(set) var reconciliations = 0

        /// One production event: ask, and on a true answer write.
        func attempt(completion: Completion?, owner: String, generation: Int,
                     write: () async -> DirectoryWriteResult) async {
            guard evaluator.evaluateAndConsume(completion: completion,
                                               hasOutstandingFailure: outstandingFailure,
                                               rowAbsence: rowAbsence,
                                               currentOwner: owner,
                                               currentDirectoryGeneration: generation)
            else { return }
            reconciliations += 1
            record(await write(), owner: owner)
        }

        /// The message is set and cleared by the WRITE, exactly as in the view,
        /// and applied evidence is recorded only from an accepted result.
        func record(_ result: DirectoryWriteResult, owner: String) {
            outstandingFailure = DirectorySyncFailure.message(for: result.outcome) != nil
            if case .applied = result.outcome {
                evaluator.noteApplied(owner: owner, generation: result.generation)
            }
        }
    }

    private func completion(_ sequence: Int, owner: String, generation: Int,
                            establishes: Bool = true) -> Completion {
        Completion(sequence: sequence, owner: owner,
                   directoryGeneration: generation, establishesMembership: establishes)
    }

    private var currentGeneration: Int { DirectoryWriteCoordinator.shared.identityGeneration }

    /// **T4 — FAILURE THEN SUCCESS.** The create is refused while membership is
    /// absent; the establishing completion then arrives and one further REAL
    /// write succeeds.
    func testARefusedCreateIsRetriedOnceTheAttestationEstablishesMembership() async {
        C70DirectoryStub.reset([
            .init(status: 200, body: "[]"),
            .init(status: 403, body: #"{"code":"42501","message":"new row violates row-level security policy"}"#),
            .init(status: 200, body: "[]"),
            // the reconciliation
            .init(status: 200, body: "[]"),
            .init(status: 201, body: row(owner))
        ])
        let driver = ReconcileDriver()
        driver.record(await write(), owner: owner)
        XCTAssertTrue(driver.outstandingFailure, "a refused create is a truthful failure")

        await driver.attempt(completion: completion(1, owner: owner, generation: currentGeneration),
                             owner: owner, generation: currentGeneration) { await self.write() }

        XCTAssertEqual(driver.reconciliations, 1)
        XCTAssertFalse(driver.outstandingFailure, "an evidenced write clears the message")
        XCTAssertEqual(C70DirectoryStub.requests.map(\.method), ["PATCH", "POST", "PATCH", "PATCH", "POST"],
                       "one refused attempt with its probe, then one full retry")
    }

    /// **T5 — SUCCESS THEN FAILURE.** The order revision 2 of the scope missed:
    /// the completion lands while nothing is outstanding, correctly writes
    /// nothing, and the refusal arrives afterwards with NO further completion.
    func testAnEstablishingCompletionThatArrivesBeforeTheFailureStillReconciles() async {
        let c = completion(1, owner: owner, generation: currentGeneration)
        let driver = ReconcileDriver()

        // The completion arrives first. Nothing is outstanding, so nothing is
        // written -- and, critically, the completion is NOT consumed.
        C70DirectoryStub.reset([])
        await driver.attempt(completion: c, owner: owner, generation: currentGeneration) {
            XCTFail("no write may be made with nothing outstanding")
            return await self.write()
        }
        XCTAssertEqual(driver.reconciliations, 0)
        XCTAssertNil(driver.evaluator.lastConsumedSequence, "an unused completion must stay unspent")

        // Now the already-dispatched write's refusal lands.
        C70DirectoryStub.reset([
            .init(status: 200, body: "[]"),
            .init(status: 403, body: #"{"code":"42501","message":"rls"}"#),
            .init(status: 200, body: "[]"),
            .init(status: 200, body: "[]"),
            .init(status: 201, body: row(owner))
        ])
        driver.record(await write(), owner: owner)
        XCTAssertTrue(driver.outstandingFailure)

        // The SAME completion is still eligible, which is what closes this order.
        await driver.attempt(completion: c, owner: owner, generation: currentGeneration) { await self.write() }
        XCTAssertEqual(driver.reconciliations, 1)
        XCTAssertFalse(driver.outstandingFailure)
    }

    /// **T6 — BOUNDEDNESS.** A retry that is refused again cannot re-trigger
    /// itself: the completion that authorised it is spent.
    func testAPersistentlyRefusedCreateIsRetriedExactlyOnce() async {
        let refusal: [C70DirectoryStub.Reply] = [
            .init(status: 200, body: "[]"),
            .init(status: 403, body: #"{"code":"42501","message":"rls"}"#),
            .init(status: 200, body: "[]")
        ]
        C70DirectoryStub.reset(refusal + refusal)
        let driver = ReconcileDriver()
        let c = completion(1, owner: owner, generation: currentGeneration)

        driver.record(await write(), owner: owner)
        await driver.attempt(completion: c, owner: owner, generation: currentGeneration) { await self.write() }
        // The retry failed too. Asking again must change nothing.
        await driver.attempt(completion: c, owner: owner, generation: currentGeneration) {
            XCTFail("a spent completion must not authorise a third write")
            return await self.write()
        }

        XCTAssertEqual(driver.reconciliations, 1)
        XCTAssertTrue(driver.outstandingFailure, "and the member is still told, truthfully")
        XCTAssertEqual(C70DirectoryStub.requests.count, 6, "two attempts of three requests, and no more")
    }

    /// **T9 — NO OUTSTANDING FAILURE, NO WRITE.** This is what stops
    /// `alreadyEstablished` on every foreground from costing anything.
    func testAnEstablishingCompletionWritesNothingWhenNoFailureIsOutstanding() async {
        C70DirectoryStub.reset([])
        let driver = ReconcileDriver()
        await driver.attempt(completion: completion(1, owner: owner, generation: currentGeneration),
                             owner: owner, generation: currentGeneration) {
            XCTFail("no write")
            return await self.write()
        }
        XCTAssertEqual(driver.reconciliations, 0)
        XCTAssertTrue(C70DirectoryStub.requests.isEmpty, "zero requests")
    }

    /// **T11 — IDENTITY.** A completion from a superseded generation authorises
    /// nothing, even though the owner still matches.
    func testACompletionFromASupersededGenerationAuthorisesNoWrite() async {
        C70DirectoryStub.reset([])
        let driver = ReconcileDriver()
        driver.outstandingFailure = true
        // Captured BEFORE the transition, which is what makes it stale after it.
        let stale = completion(1, owner: owner, generation: currentGeneration)
        DirectoryWriteCoordinator.shared.noteIdentityTransition()
        XCTAssertNotEqual(stale.directoryGeneration, currentGeneration,
                          "the transition must actually advance the generation")

        await driver.attempt(completion: stale, owner: owner, generation: currentGeneration) {
            XCTFail("a stale-generation completion must authorise nothing")
            return await self.write()
        }
        XCTAssertEqual(driver.reconciliations, 0)
        XCTAssertTrue(C70DirectoryStub.requests.isEmpty)
    }

    /// **T12 — the two refusals of the fresh-join investigation.** Both render
    /// the same generic copy, and the suite can still tell them apart.
    func testTheTwoCreateRefusalsAreDistinguishableEvenThoughTheCopyIsShared() async {
        C70DirectoryStub.reset([
            .init(status: 200, body: "[]"),
            .init(status: 403, body: #"{"code":"42501","message":"new row violates row-level security policy"}"#),
            .init(status: 200, body: "[]")
        ])
        let rls = await write()
        guard case .refusedByPolicy = rls.outcome else { return XCTFail("got \(rls.outcome)") }

        C70DirectoryStub.reset([
            .init(status: 200, body: "[]"),
            .init(status: 400, body: #"{"code":"23514","message":"age band must be declared before a directory row is created"}"#),
            .init(status: 200, body: "[]")
        ])
        let band = await write()
        if case .refusedByPolicy = band.outcome {
            XCTFail("a 400/23514 is not an RLS refusal")
        }

        XCTAssertEqual(DirectorySyncFailure.message(for: rls.outcome), DirectorySyncFailure.genericMessage)
        XCTAssertEqual(DirectorySyncFailure.message(for: band.outcome), DirectorySyncFailure.genericMessage)
    }

    // MARK: - F3 — initial publication with NO foreground error

    private func absence(_ owner: String, _ generation: Int) -> AuthManager.DirectoryRowAbsence {
        .init(owner: owner, directoryGeneration: generation)
    }

    /// **F3-1a — ABSENCE KNOWN, THEN COMPLETION.** The device failure: a fresh
    /// join with no error at all, so nothing is outstanding and the repair path
    /// cannot reach it.
    func testAFreshJoinWithNoForegroundErrorPublishesOnceWhenAbsenceIsKnownFirst() async {
        C70DirectoryStub.reset([.init(status: 200, body: "[]"),
                                .init(status: 201, body: row(owner))])
        let driver = ReconcileDriver()
        XCTAssertFalse(driver.outstandingFailure, "no error was ever shown -- this is the point")
        driver.rowAbsence = absence(owner, currentGeneration)

        await driver.attempt(completion: completion(1, owner: owner, generation: currentGeneration),
                             owner: owner, generation: currentGeneration) { await self.write() }

        XCTAssertEqual(driver.reconciliations, 1)
        XCTAssertEqual(C70DirectoryStub.requests.map(\.method), ["PATCH", "POST"],
                       "one real write, creating the row")
        XCTAssertFalse(driver.outstandingFailure)
    }

    /// **F3-1b — COMPLETION, THEN ABSENCE.** The completion arrives while absence
    /// is still unknown; nothing is authorised yet, and the completion must stay
    /// UNSPENT so the later absence event can use it.
    func testAFreshJoinPublishesWhenTheCompletionArrivesBeforeAbsenceIsKnown() async {
        let c = completion(1, owner: owner, generation: currentGeneration)
        let driver = ReconcileDriver()

        C70DirectoryStub.reset([])
        await driver.attempt(completion: c, owner: owner, generation: currentGeneration) {
            XCTFail("absence is unknown; nothing may be written")
            return await self.write()
        }
        XCTAssertEqual(driver.reconciliations, 0)
        XCTAssertNil(driver.evaluator.lastConsumedSequence, "an unused completion must stay unspent")

        // Absence now arrives. In the app this is the same observer firing again.
        C70DirectoryStub.reset([.init(status: 200, body: "[]"),
                                .init(status: 201, body: row(owner))])
        driver.rowAbsence = absence(owner, currentGeneration)
        await driver.attempt(completion: c, owner: owner, generation: currentGeneration) { await self.write() }

        XCTAssertEqual(driver.reconciliations, 1)
        XCTAssertEqual(C70DirectoryStub.requests.map(\.method), ["PATCH", "POST"])
    }

    /// **F3-2.** Once a write is evidenced, later completions write nothing —
    /// even though absence evidence is still standing, because AuthManager never
    /// clears it on a successful publish.
    func testNoSecondWriteOnceTheRowHasBeenEvidenced() async {
        C70DirectoryStub.reset([.init(status: 200, body: "[]"),
                                .init(status: 201, body: row(owner))])
        let driver = ReconcileDriver()
        driver.rowAbsence = absence(owner, currentGeneration)
        await driver.attempt(completion: completion(1, owner: owner, generation: currentGeneration),
                             owner: owner, generation: currentGeneration) { await self.write() }
        XCTAssertEqual(driver.reconciliations, 1)

        C70DirectoryStub.reset([])
        for seq in [2, 3, 4] {
            await driver.attempt(completion: completion(seq, owner: owner, generation: currentGeneration),
                                 owner: owner, generation: currentGeneration) {
                XCTFail("the row is evidenced; nothing more may be written")
                return await self.write()
            }
        }
        XCTAssertEqual(driver.reconciliations, 1)
        XCTAssertTrue(C70DirectoryStub.requests.isEmpty)
    }

    /// **F3-3 — THE RETURNING MEMBER.** No absence evidence and no failure, so
    /// repeated foreground attestations cost ZERO requests.
    func testAReturningMemberWritesNothingAcrossRepeatedCompletions() async {
        C70DirectoryStub.reset([])
        let driver = ReconcileDriver()
        driver.rowAbsence = nil

        for seq in 1...5 {
            await driver.attempt(completion: completion(seq, owner: owner, generation: currentGeneration),
                                 owner: owner, generation: currentGeneration) {
                XCTFail("a member whose row exists must not be written on foreground")
                return await self.write()
            }
        }
        XCTAssertEqual(driver.reconciliations, 0)
        XCTAssertTrue(C70DirectoryStub.requests.isEmpty, "zero requests")
    }

    // MARK: - Generation — RETIRED WITH THE FEATURE
    //
    // Three tests lived here: `testGenerationWritesOnlyTheHandleAndOnlyWhile
    // ItIsAbsent`, `testGenerationStopsSilentlyWhenTheFilterMatchesNothing` and
    // `testGenerationRetriesOnlyOnAnEvidencedHandleCollision`. They exercised
    // `autoGenerateAccountIDIfMissing` over a stubbed transport.
    //
    // **Their coverage is genuinely REMOVED, not relocated, and that is stated
    // rather than absorbed into a total.** They tested a network-shaped
    // behaviour — read the self row, PATCH under `account_id=is.null`, retry on
    // an evidenced collision — that no longer exists anywhere in the client. No
    // surviving test covers it, because there is nothing left to cover.
    //
    // What replaces them is narrower and differently shaped: a structural
    // assertion in `AccountIDRemovalTests` that no generation entry point
    // survives at all.

}
