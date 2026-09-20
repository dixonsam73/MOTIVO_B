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

    /// `fetchSelfRow` decodes `SelfDirectoryRow`, whose `lookup_enabled` and
    /// `follow_requests_enabled` are NON-OPTIONAL — a fixture without them
    /// fails to decode and generation returns nil before writing anything.
    private func selfRow(_ userID: String, displayName: String, accountID: String?) -> String {
        let acct = accountID.map { "\"\($0)\"" } ?? "null"
        return "[{\"user_id\":\"\(userID)\",\"display_name\":\"\(displayName)\","
             + "\"account_id\":\(acct),\"location\":\"London\",\"instruments\":[\"piano\"],"
             + "\"lookup_enabled\":true,\"follow_requests_enabled\":true,\"avatar_key\":null,\"avatar_version\":null}]"
    }

    private func write(displayName: String = "Ada",
                       accountID: String? = nil,
                       location: String? = "London",
                       instruments: [String]? = ["piano"],
                       authChallenge: (() async -> Bool)? = nil) async -> DirectoryWriteResult {
        await AccountDirectoryService.shared.upsertSelfRow(userID: owner,
                                                           displayName: displayName,
                                                           accountID: accountID,
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

    func testANamedHandleCollisionIsTypedAndKeepsItsOwnCopy() async {
        C70DirectoryStub.reset([.init(status: 409, body:
            #"{"code":"23505","message":"duplicate key value violates unique constraint \"account_directory_account_id_key\""}"#)])
        let result = await write(accountID: "ada")
        guard case .accountIDTaken = result.outcome else { return XCTFail("got \(result.outcome)") }
        XCTAssertEqual(DirectorySyncFailure.message(for: result.outcome),
                       DirectorySyncFailure.accountIDTakenMessage)
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

    // MARK: - Generation

    /// Generation sends the handle ALONE and filters on `account_id=is.null`.
    ///
    /// The old path re-sent display name, location and instruments read from
    /// the row it had fetched, so an edit landing between the fetch and the
    /// write was reverted; it cannot revert a field it does not send. And the
    /// "do not overwrite an existing handle" rule moved from FETCH time into
    /// the database at WRITE time.
    func testGenerationWritesOnlyTheHandleAndOnlyWhileItIsAbsent() async {
        C70DirectoryStub.reset([
            .init(status: 200, body: selfRow(owner, displayName: "Ada Lovelace", accountID: nil)),
            .init(status: 200, body: row(owner, displayName: "Ada Lovelace", accountID: "adalovelace"))
        ])

        let generated = await AccountDirectoryService.shared.autoGenerateAccountIDIfMissing(
            userID: owner, displayName: "Ada Lovelace", localAccountID: nil)

        let reqs = C70DirectoryStub.requests
        XCTAssertEqual(reqs.count, 2, "one read, one write")
        XCTAssertEqual(reqs[0].method, "GET")
        XCTAssertEqual(reqs[1].method, "PATCH")
        XCTAssertEqual(query(reqs[1].url)["account_id"], "is.null",
                       "the missing-handle rule is a database predicate, not a client memory")
        XCTAssertEqual(query(reqs[1].url)["user_id"], "eq.\(owner)")
        XCTAssertEqual(Set(reqs[1].body.keys), ["account_id"],
                       "generation must not rewrite fields it did not read for")
        XCTAssertEqual(generated, "adalovelace")
    }

    /// Zero matched rows is an OBSERVATION — the row is absent OR the handle is
    /// already populated. Both mean "do not generate", so nothing is inferred
    /// and nothing is retried.
    func testGenerationStopsSilentlyWhenTheFilterMatchesNothing() async {
        C70DirectoryStub.reset([
            .init(status: 200, body: selfRow(owner, displayName: "Ada Lovelace", accountID: nil)),
            .init(status: 200, body: "[]")
        ])
        let generated = await AccountDirectoryService.shared.autoGenerateAccountIDIfMissing(
            userID: owner, displayName: "Ada Lovelace", localAccountID: nil)
        XCTAssertNil(generated)
        XCTAssertEqual(C70DirectoryStub.requests.count, 2, "no retry on an unmatched filter")
    }

    func testGenerationRetriesOnlyOnAnEvidencedHandleCollision() async {
        C70DirectoryStub.reset([
            .init(status: 200, body: selfRow(owner, displayName: "Ada", accountID: nil)),
            .init(status: 409, body: #"{"code":"23505","details":"Key (account_id)=(ada) already exists."}"#),
            .init(status: 200, body: row(owner, displayName: "Ada", accountID: "ada2"))
        ])
        let generated = await AccountDirectoryService.shared.autoGenerateAccountIDIfMissing(
            userID: owner, displayName: "Ada", localAccountID: nil)
        XCTAssertEqual(generated, "ada2")
        XCTAssertEqual(C70DirectoryStub.requests.count, 3)
    }
}
