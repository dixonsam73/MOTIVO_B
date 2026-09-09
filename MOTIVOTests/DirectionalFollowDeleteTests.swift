//
//  DirectionalFollowDeleteTests.swift
//  MOTIVOTests
//
//  PHASE 5 · P5-K / C-43 — A DIRECTIONAL RELATIONSHIP ACTION MUST NOT DESTROY
//  THE OPPOSITE DIRECTION.
//
//  `deleteRelationship(with:)` issued TWO unconditional DELETEs, so:
//
//    * A unfollows B  -> B's approved follow of A was destroyed too;
//    * A removes follower B -> A's own follow of B was cancelled;
//    * A declines B's request -> A's outgoing follow of B was cancelled.
//
//  The second delete existed as CRUDE DETECTION: PostgREST returns 204 on a
//  zero-match DELETE under `Prefer: return=minimal`, so a single delete could
//  report success having deleted nothing. **The fix must keep that detection**,
//  or it trades a destructive defect for a silent-success one.
//
//  These tests were written to FAIL against the pre-fix code and were run that
//  way first.
//
//  LOCAL STACK ONLY. No production fixtures are used or touched.
//

import XCTest
import CryptoKit
@testable import Etudes

@MainActor
final class DirectionalFollowDeleteTests: XCTestCase {

    private static let baseURLString = "http://127.0.0.1:54321"
    private static let jwtSecret = "super-secret-jwt-token-with-at-least-32-characters-long"
    /// Local-stack service role, used ONLY for fixture setup and read-back so
    /// the assertions do not depend on the same policy path under test.
    /// `follows_insert_requester` requires `follower_user_id = auth.uid()`, so
    /// seeding BOTH directions is impossible as either party.
    private static let serviceKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
        + "eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0."
        + "EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"

    private static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
        + "eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9."
        + "CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

    /// Dedicated C-43 identities. Never production ids.
    private static let A = "00000000-0000-0000-0000-00000000aaa1"
    private static let B = "00000000-0000-0000-0000-00000000bbb1"

    private func skipUnlessLocalStack() throws {
        guard URL(string: Self.baseURLString)!.host == "127.0.0.1" else { XCTFail("non-loopback"); return }
        guard Self.probe() else { throw XCTSkip("local Supabase stack not reachable — run `supabase start`") }
    }

    private static func probe() -> Bool {
        var r = URLRequest(url: URL(string: baseURLString + "/rest/v1/")!); r.timeoutInterval = 3
        r.setValue(anonKey, forHTTPHeaderField: "apikey")
        let sem = DispatchSemaphore(value: 0); var ok = false
        URLSession.shared.dataTask(with: r) { _, resp, _ in
            if let h = resp as? HTTPURLResponse { ok = h.statusCode < 500 }; sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 5)
        return ok
    }

    override func setUp() async throws {
        try await super.setUp()
        BackendConfig.apiBaseURL = URL(string: Self.baseURLString)
        BackendConfig.apiToken = Self.anonKey
        NetworkManager.shared.baseURL = URL(string: Self.baseURLString)
        NetworkManager.shared.setBearerToken(Self.mintJWT(sub: Self.A))
        UserDefaults.standard.set(Self.A, forKey: "supabaseUserID_v1")
        setBackendMode(.backendConnected)
        await Self.clearFixtures()
    }

    override func tearDown() async throws {
        await Self.clearFixtures()
        NetworkManager.shared.setBearerToken(nil)
        UserDefaults.standard.removeObject(forKey: "supabaseUserID_v1")
        try await super.tearDown()
    }

    // MARK: - THE INVARIANT

    /// P1 pre-fix (must fail) / P2 post-fix.
    func testUnfollowDeletesOnlyMyOutgoingFollow() async throws {
        try skipUnlessLocalStack()
        try await Self.seed(aToB: "approved", bToA: "approved")

        let r = await BackendEnvironment.shared.follow.unfollow(Self.B)
        guard case .success = r else { return XCTFail("unfollow failed: \(r)") }

        let (aToB, bToA) = await Self.rows()
        XCTAssertNil(aToB, "A→B should be gone")
        XCTAssertEqual(bToA, "approved",
                       "B→A MUST SURVIVE — B's follow of A is B's own state and A did not ask to remove it")
    }

    /// P3.
    func testRemoveFollowerDeletesOnlyTheirIncomingFollow() async throws {
        try skipUnlessLocalStack()
        try await Self.seed(aToB: "approved", bToA: "approved")

        let r = await BackendEnvironment.shared.follow.removeFollower(Self.B)
        guard case .success = r else { return XCTFail("removeFollower failed: \(r)") }

        let (aToB, bToA) = await Self.rows()
        XCTAssertNil(bToA, "B→A should be gone")
        XCTAssertEqual(aToB, "approved",
                       "A→B MUST SURVIVE — removing a follower does not cancel my own follow of them")
    }

    /// P4.
    func testDeclineDeletesOnlyTheIncomingRequest() async throws {
        try skipUnlessLocalStack()
        try await Self.seed(aToB: "approved", bToA: "requested")

        let r = await BackendEnvironment.shared.follow.declineFollow(from: Self.B)
        guard case .success = r else { return XCTFail("declineFollow failed: \(r)") }

        let (aToB, bToA) = await Self.rows()
        XCTAssertNil(bToA, "B→A request should be gone")
        XCTAssertEqual(aToB, "approved",
                       "A→B MUST SURVIVE — declining an incoming request does not cancel my own outgoing follow")
    }

    // MARK: - NO SILENT SUCCESS

    /// P5 — the detection the double delete existed to provide must survive.
    func testZeroMatchIsNotReportedAsSuccess() async throws {
        try skipUnlessLocalStack()
        try await Self.seed(aToB: nil, bToA: "approved")

        // A has no outgoing follow of B, so this must NOT report a relationship change.
        let r = await BackendEnvironment.shared.follow.unfollow(Self.B)
        if case .success = r {
            XCTFail("unfollow reported SUCCESS having deleted nothing — this is the silent-success defect the fix must not introduce")
        }

        let (_, bToA) = await Self.rows()
        XCTAssertEqual(bToA, "approved", "a zero-match must not delete the opposite direction either")
    }

    // MARK: - Fixtures (local stack only)

    private static func seed(aToB: String?, bToA: String?) async throws {
        var rows: [[String: Any]] = []
        if let s = aToB { rows.append(["follower_user_id": A, "followed_user_id": B, "status": s]) }
        if let s = bToA { rows.append(["follower_user_id": B, "followed_user_id": A, "status": s]) }
        guard !rows.isEmpty else { return }
        let (code, body) = await restRaw("rest/v1/follows", "POST", rows)
        guard code == 201 || code == 200 else {
            throw NSError(domain: "fixture", code: code,
                          userInfo: [NSLocalizedDescriptionKey: "seed failed \(code): \(String(data: body, encoding: .utf8) ?? "")"])
        }
    }

    /// Reads back both directions. Uses the service role so the fixture check is
    /// independent of the policy path under test.
    private static func rows() async -> (String?, String?) {
        func status(_ f: String, _ t: String) async -> String? {
            let (c, d) = await rest("rest/v1/follows?follower_user_id=eq.\(f)&followed_user_id=eq.\(t)&select=status", "GET")
            guard c == 200,
                  let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]],
                  let first = arr.first else { return nil }
            return first["status"] as? String
        }
        return (await status(A, B), await status(B, A))
    }

    private static func clearFixtures() async {
        _ = await rest("rest/v1/follows?follower_user_id=eq.\(A)&followed_user_id=eq.\(B)", "DELETE")
        _ = await rest("rest/v1/follows?follower_user_id=eq.\(B)&followed_user_id=eq.\(A)", "DELETE")
    }

    @discardableResult
    private static func rest(_ path: String, _ method: String) async -> (Int, Data) {
        await restRaw(path, method, nil)
    }

    private static func restRaw(_ path: String, _ method: String, _ body: Any?) async -> (Int, Data) {
        var r = URLRequest(url: URL(string: baseURLString + "/" + path)!)
        r.httpMethod = method
        r.setValue(serviceKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer " + serviceKey, forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { r.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        guard let (d, resp) = try? await URLSession.shared.data(for: r) else { return (-1, Data()) }
        return ((resp as? HTTPURLResponse)?.statusCode ?? -1, d)
    }

    private static func mintJWT(sub: String) -> String {
        func b64(_ d: Data) -> String {
            d.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = b64(Data(#"{"alg":"HS256","typ":"JWT"}"#.utf8))
        let exp = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let payload = b64(Data("{\"sub\":\"\(sub)\",\"role\":\"authenticated\",\"aud\":\"authenticated\",\"exp\":\(exp)}".utf8))
        let signing = "\(header).\(payload)"
        let sig = HMAC<SHA256>.authenticationCode(for: Data(signing.utf8),
                                                  using: SymmetricKey(data: Data(jwtSecret.utf8)))
        return "\(signing).\(b64(Data(sig)))"
    }
}
