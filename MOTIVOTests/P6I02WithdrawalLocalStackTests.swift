//
//  P6I02WithdrawalLocalStackTests.swift
//  MOTIVOTests
//
//  P6-I-02, Unit 2c — WHAT THE BACKEND'S ANSWERS ACTUALLY MEAN, measured on the
//  LOCAL authenticated stack (http://127.0.0.1:54321), never production.
//
//  T-L1…T-L4 need no change to the local stack. T-L5…T-L7 need an isolated
//  rehearsal (Samuel's D-4): they SKIP unless the rehearsal script has put the
//  local stack into the named mode, and each one verifies for itself that the
//  mode is really in effect. A skip leaves its gate UNMET.
//
//  Disposable synthetic identities and rows only.
//

import XCTest
import CryptoKit
@testable import Etudes

@MainActor
final class P6I02WithdrawalLocalStackTests: XCTestCase {

    private static let baseURLString = "http://127.0.0.1:54321"
    private static let jwtSecret = "super-secret-jwt-token-with-at-least-32-characters-long"
    private static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
        + "eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9."
        + "CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
    /// The Supabase CLI's public LOCAL demo service key — used only to OBSERVE
    /// rows as they really are, past RLS.
    private static let serviceKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
        + "eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0."
        + "EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"

    private static let ownerA = "00000000-0000-0000-0000-0000000c2c01"
    private static let ownerB = "00000000-0000-0000-0000-0000000c2c02"
    private static let ownerC = "00000000-0000-0000-0000-0000000c2c03"

    // Rehearsal fixtures — created by the rehearsal script, never by the test.
    private static let lapsed = "00000000-0000-0000-0000-0000000c2c05"
    private static let rowL1 = UUID(uuidString: "2c2c0000-0000-4000-8000-000000000001")!
    private static let rowL2 = UUID(uuidString: "2c2c0000-0000-4000-8000-000000000002")!
    private static let rowL3 = UUID(uuidString: "2c2c0000-0000-4000-8000-000000000003")!
    private static let neverInserted = UUID(uuidString: "2c2c0000-0000-4000-8000-000000000004")!

    private var created: [UUID] = []

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        guard URL(string: Self.baseURLString)!.host == "127.0.0.1" else { return XCTFail("non-loopback target") }
        guard LocalStackSupport.isReachable() else {
            throw XCTSkip("UNMET: local Supabase stack not reachable")
        }
        BackendConfig.apiBaseURL = URL(string: Self.baseURLString)
        BackendConfig.apiToken = Self.anonKey
        NetworkManager.shared.baseURL = URL(string: Self.baseURLString)
        signIn(Self.ownerA)
        setBackendMode(.backendConnected)
        try LocalStackSupport.requireRealBackend()
        try await LocalStackSupport.ensureIdentities([Self.ownerA, Self.ownerB, Self.ownerC])
    }

    override func tearDown() async throws {
        for id in created { _ = await Self.service("rest/v1/posts?id=eq.\(id.uuidString)", "DELETE") }
        NetworkManager.shared.setBearerToken(nil)
        UserDefaults.standard.removeObject(forKey: "supabaseUserID_v1")
        setBackendMode(.localSimulation)
        try await super.tearDown()
    }

    // MARK: - Fixture

    private func signIn(_ uid: String) {
        NetworkManager.shared.setBearerToken(Self.mintJWT(sub: uid))
        UserDefaults.standard.set(uid, forKey: "supabaseUserID_v1")
    }

    private func binding(_ owner: String) throws -> OperationBinding {
        try XCTUnwrap(OperationBinding(expectedOwner: owner, isStillCurrent: { true }))
    }

    /// A public post owned by `owner`, inserted AS that owner through PostgREST.
    private func insertPost(owner: String) async throws -> UUID {
        let id = UUID()
        let (code, body) = await Self.rest("rest/v1/posts", "POST", as: owner,
                                           body: ["id": id.uuidString, "owner_user_id": owner, "is_public": true])
        guard (200...299).contains(code) else {
            throw XCTSkip("UNMET: could not create a fixture row as \(owner.suffix(4)) (HTTP \(code) \(String(decoding: body, as: UTF8.self)))")
        }
        created.append(id)
        return id
    }

    /// The row as it really is, observed past RLS with the local service key.
    private static func observed(_ id: UUID) async -> [String: Any]? {
        let (c, d) = await service("rest/v1/posts?id=eq.\(id.uuidString)&select=id,is_public,owner_user_id", "GET")
        guard c == 200, let rows = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return nil }
        return rows.first
    }

    // MARK: - T-L1…T-L4 · no change to the local stack

    func testTL1_OwnerDeletesOwnExistingRow_IsExactlyThatRow() async throws {
        let id = try await insertPost(owner: Self.ownerA)
        let outcome = try await BackendEnvironment.shared.publish.unsharePost(id, binding: binding(Self.ownerA)).get()
        XCTAssertEqual(outcome, .rowDeleted)
        let row = await Self.observed(id)
        XCTAssertNil(row, "the row is really gone")
    }

    func testTL2_OwnerDeletesAbsentRow_IsEmptyArray() async throws {
        let absent = UUID()
        let (code, body) = await Self.rest(
            "rest/v1/posts?id=eq.\(absent.uuidString)&owner_user_id=eq.\(Self.ownerA)&select=id", "DELETE",
            as: Self.ownerA, prefer: "return=representation")
        XCTAssertEqual(code, 200)
        XCTAssertEqual(String(decoding: body, as: UTF8.self), "[]")
        let outcome = try await BackendEnvironment.shared.publish.unsharePost(absent, binding: binding(Self.ownerA)).get()
        XCTAssertEqual(outcome, .noRowMatched)
    }

    /// ZERO ROWS IS NOT ABSENCE: another owner's row answers exactly like an
    /// absent one, and is still there afterwards.
    func testTL3_AnotherOwnersRow_MatchesNothingAndStillExists() async throws {
        let id = try await insertPost(owner: Self.ownerB)
        let outcome = try await BackendEnvironment.shared.publish.unsharePost(id, binding: binding(Self.ownerA)).get()
        XCTAssertEqual(outcome, .noRowMatched)
        let row = await Self.observed(id)
        XCTAssertNotNil(row, "the row still exists")
        XCTAssertEqual(row?["is_public"] as? Bool, true, "and was not even demoted")
    }

    func testTL4_WrongIdentityEntirely_MatchesNothingAndTheRowStillExists() async throws {
        let id = try await insertPost(owner: Self.ownerA)
        signIn(Self.ownerC)
        let outcome = try await BackendEnvironment.shared.publish.unsharePost(id, binding: binding(Self.ownerC)).get()
        XCTAssertEqual(outcome, .noRowMatched)
        let row = await Self.observed(id)
        XCTAssertNotNil(row, "C's withdrawal left A's row in place")
    }

    // MARK: - T-L5…T-L7 · isolated rehearsal only (D-4)

    private func requireRehearsal(_ mode: String) throws {
        guard ProcessInfo.processInfo.environment["P6_2C_REHEARSAL"] == mode else {
            throw XCTSkip("UNMET unless run by the isolated rehearsal in mode '\(mode)'")
        }
    }

    /// ENFORCEMENT ACTIVE, delete policy as committed (ungated): a lapsed owner
    /// can still delete their own row — C-35's carve-out, measured.
    func testTL5_Rehearsal_LapsedOwnerDeletesOwnRow() async throws {
        try requireRehearsal("enforcement")
        signIn(Self.lapsed)
        let before = await Self.observed(Self.rowL1)
        XCTAssertNotNil(before, "fixture: the rehearsal created the lapsed owner's row")
        let outcome = try await BackendEnvironment.shared.publish.unsharePost(Self.rowL1, binding: binding(Self.lapsed)).get()
        XCTAssertEqual(outcome, .rowDeleted)
        let after = await Self.observed(Self.rowL1)
        XCTAssertNil(after)
    }

    /// ENFORCEMENT ACTIVE: the gated demote matches nothing for a lapsed owner,
    /// although the row is theirs. This is also the in-test proof that
    /// enforcement really is active: with it off, the same PATCH returns the row.
    func testTL6_Rehearsal_LapsedOwnerDemoteMatchesNothing() async throws {
        try requireRehearsal("enforcement")
        let (code, body) = await Self.rest(
            "rest/v1/posts?id=eq.\(Self.rowL2.uuidString)&owner_user_id=eq.\(Self.lapsed)&select=id", "PATCH",
            as: Self.lapsed, body: ["is_public": false], prefer: "return=representation")
        XCTAssertEqual(code, 200)
        XCTAssertEqual(String(decoding: body, as: UTF8.self), "[]", "the gated demote matched nothing")
        let row = await Self.observed(Self.rowL2)
        XCTAssertEqual(row?["is_public"] as? Bool, true, "the row is the lapsed owner's and still public")
    }

    /// DELETE GATED (a temporary local policy change): a DENIED delete of an
    /// existing row is byte-identical to a delete of an absent row. This is why
    /// the client must never read `[]` as absence.
    func testTL7_Rehearsal_GatedDeleteDenialIsIndistinguishableFromAbsence() async throws {
        try requireRehearsal("gatedDelete")
        let denied = await Self.rest(
            "rest/v1/posts?id=eq.\(Self.rowL3.uuidString)&owner_user_id=eq.\(Self.lapsed)&select=id", "DELETE",
            as: Self.lapsed, prefer: "return=representation")
        let absent = await Self.rest(
            "rest/v1/posts?id=eq.\(Self.neverInserted.uuidString)&owner_user_id=eq.\(Self.lapsed)&select=id", "DELETE",
            as: Self.lapsed, prefer: "return=representation")
        XCTAssertEqual(denied.0, absent.0, "same status")
        XCTAssertEqual(denied.1, absent.1, "byte-identical body")
        XCTAssertEqual(String(decoding: denied.1, as: UTF8.self), "[]")
        let row = await Self.observed(Self.rowL3)
        XCTAssertNotNil(row, "the denied row STILL EXISTS — proof the gate is really in effect")

        signIn(Self.lapsed)
        let outcome = try await BackendEnvironment.shared.publish.unsharePost(Self.rowL3, binding: binding(Self.lapsed)).get()
        XCTAssertEqual(outcome, .noRowMatched, "and the client reports it as what it is — not a withdrawal")
    }

    // MARK: - REST

    private static func mintJWT(sub: String) -> String {
        func b64(_ d: Data) -> String {
            d.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let now = Int(Date().timeIntervalSince1970)
        let si = b64(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8)) + "." + b64(Data("""
        {"sub":"\(sub)","role":"authenticated","aud":"authenticated","iat":\(now),"exp":\(now + 3600)}
        """.utf8))
        let sig = HMAC<SHA256>.authenticationCode(for: Data(si.utf8), using: SymmetricKey(data: Data(jwtSecret.utf8)))
        return si + "." + b64(Data(sig))
    }

    private static func rest(_ path: String, _ method: String, as sub: String,
                             body: [String: Any]? = nil, prefer: String? = nil) async -> (Int, Data) {
        var r = URLRequest(url: URL(string: baseURLString + "/" + path)!)
        r.httpMethod = method
        r.setValue(anonKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + mintJWT(sub: sub), forHTTPHeaderField: "Authorization")
        if let prefer { r.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        guard let (d, resp) = try? await URLSession.shared.data(for: r) else { return (-1, Data()) }
        return ((resp as? HTTPURLResponse)?.statusCode ?? -1, d)
    }

    private static func service(_ path: String, _ method: String) async -> (Int, Data) {
        var r = URLRequest(url: URL(string: baseURLString + "/" + path)!)
        r.httpMethod = method
        r.setValue(serviceKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + serviceKey, forHTTPHeaderField: "Authorization")
        guard let (d, resp) = try? await URLSession.shared.data(for: r) else { return (-1, Data()) }
        return ((resp as? HTTPURLResponse)?.statusCode ?? -1, d)
    }
}
