//
//  DirectorySyncFailureTests.swift
//  MOTIVOTests
//
//  PHASE 5 · C-70(a).
//
//  The load-bearing assertion is `testNoNonCollisionFailureNamesTheAccountID`:
//  it asserts the ABSENCE of the defect — that no failure the classifier can
//  produce blames the Account ID unless the server named it — rather than the
//  presence of one particular string.
//

import XCTest
@testable import Etudes

final class DirectorySyncFailureTests: XCTestCase {

    private func http(_ status: Int, _ body: String?) -> Error {
        NetworkManager.NetworkError.httpError(status: status, body: body)
    }

    private struct Unrelated: Error {}

    // MARK: - The server attributed it

    func testNamedUniqueConstraintIsACollision() {
        XCTAssertTrue(DirectorySyncFailure.isAccountIDCollision(
            http(409, "duplicate key value violates unique constraint \"account_directory_account_id_key\"")))
    }

    func testNamedAccountIDColumnIsACollision() {
        XCTAssertTrue(DirectorySyncFailure.isAccountIDCollision(
            http(409, #"{"code":"23505","details":"Key (account_id)=(ada) already exists."}"#)))
    }

    func testCollisionKeepsItsOwnCopy() {
        XCTAssertEqual(DirectorySyncFailure.message(
            for: http(409, #"{"code":"23505","message":"violates unique constraint \"account_directory_account_id_key\""}"#)),
                       DirectorySyncFailure.accountIDTakenMessage)
    }

    // MARK: - C-70: the code alone is not the evidence

    /// **RE-EXPRESSED, AND STRICTLY STRONGER.** This used to assert that a BARE
    /// `23505` was a handle collision. `account_directory` carries TWO unique
    /// constraints — `account_directory_account_id_key` on `account_id` and
    /// `account_directory_pkey` on `user_id` — and both raise `23505`, so the
    /// old reading blamed the Account ID for a primary-key conflict. That is
    /// this file's own rule broken inside its own classifier. The assertion is
    /// not weakened to pass: it now discriminates a case it could not see
    /// before.
    func testABareUniqueViolationCodeIsNotEnough() {
        XCTAssertFalse(DirectorySyncFailure.isAccountIDCollision(
            http(409, #"{"code":"23505","message":"duplicate key value"}"#)),
            "23505 names SOME constraint; this table has two")
        XCTAssertEqual(DirectorySyncFailure.message(for: http(409, #"{"code":"23505"}"#)),
                       DirectorySyncFailure.genericMessage)
    }

    func testAPrimaryKeyViolationNeverBlamesTheAccountID() {
        let pk = http(409, #"{"code":"23505","message":"duplicate key value violates unique constraint \"account_directory_pkey\""}"#)
        XCTAssertFalse(DirectorySyncFailure.isAccountIDCollision(pk))
        XCTAssertEqual(DirectorySyncFailure.message(for: pk), DirectorySyncFailure.genericMessage)
    }

    // MARK: - The server did NOT attribute it

    /// A 409 that is not the account_id unique violation is not a collision —
    /// the status alone must never be the evidence.
    func testUnrelated409IsNotACollision() {
        XCTAssertFalse(DirectorySyncFailure.isAccountIDCollision(
            http(409, #"{"code":"23514","message":"some other conflict"}"#)))
    }

    func testEmptyAndMissingBodiesAreNotCollisions() {
        XCTAssertFalse(DirectorySyncFailure.isAccountIDCollision(http(409, nil)))
        XCTAssertFalse(DirectorySyncFailure.isAccountIDCollision(http(409, "")))
    }

    func testOtherNetworkErrorsAreGeneric() {
        for e in [http(401, "unauthorised"),
                  http(403, "row-level security"),
                  http(400, "bad request"),
                  http(500, "server"),
                  NetworkManager.NetworkError.transportError("offline"),
                  NetworkManager.NetworkError.notConfigured] {
            XCTAssertFalse(DirectorySyncFailure.isAccountIDCollision(e))
            XCTAssertEqual(DirectorySyncFailure.message(for: e), DirectorySyncFailure.genericMessage)
        }
    }

    func testNonNetworkErrorIsGeneric() {
        XCTAssertEqual(DirectorySyncFailure.message(for: Unrelated()), DirectorySyncFailure.genericMessage)
    }

    // MARK: - THE DEFECT ITSELF

    /// **C-70(a).** Three of the five triggers — a `name` edit, a `location`
    /// edit and the instrument manager closing — never touch the Account ID.
    /// No message produced for them may name it.
    func testNoNonCollisionFailureNamesTheAccountID() {
        let nonCollisions: [Error] = [
            http(401, "unauthorised"),
            http(403, "new row violates row-level security policy"),
            http(400, "age band must be declared before a directory row is created"),
            http(409, #"{"code":"23514"}"#),
            http(500, nil),
            NetworkManager.NetworkError.transportError("The Internet connection appears to be offline."),
            NetworkManager.NetworkError.decodingError("bad json"),
            Unrelated(),
        ]
        for e in nonCollisions {
            let msg = DirectorySyncFailure.message(for: e).lowercased()
            XCTAssertFalse(msg.contains("account id"), "must not blame the Account ID: \(msg)")
            XCTAssertFalse(msg.contains("account_id"), "must not blame the Account ID: \(msg)")
        }
    }

    /// The generic copy must stay truthful for every trigger, so it names no
    /// field at all — not the name, the location or the instruments either.
    func testGenericCopyNamesNoField() {
        let m = DirectorySyncFailure.genericMessage.lowercased()
        for field in ["account id", "account_id", "display name", "location", "instrument"] {
            XCTAssertFalse(m.contains(field), "generic copy must name no field, found: \(field)")
        }
    }
}
