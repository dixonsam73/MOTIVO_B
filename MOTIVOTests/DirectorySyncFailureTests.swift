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

    /// **RE-EXPRESSED when the handle was removed: the CLASSIFICATION is kept
    /// and the COPY is not.**
    ///
    /// `isAccountIDCollision` above still proves the server attributed the
    /// failure to `account_id` — that half of C-70(a)'s rule is untouched. What
    /// went is the other half: a member with no Account ID field cannot act on
    /// being told one is taken, so naming it would be the same false attribution
    /// pointing the other way.
    ///
    /// Asserted against `genericMessage` DIRECTLY rather than through
    /// `accountIDTakenMessage`, so this still fails if the alias is ever pointed
    /// back at a field-naming string.
    func testACollisionIsStillClassifiedButItsCopyNamesNoField() {
        let err = http(409, #"{"code":"23505","message":"violates unique constraint \"account_directory_account_id_key\""}"#)
        XCTAssertTrue(DirectorySyncFailure.isAccountIDCollision(err),
                      "the server named the constraint; that classification is still established")
        XCTAssertEqual(DirectorySyncFailure.message(for: err),
                       DirectorySyncFailure.genericMessage,
                       "but a member with no Account ID field must not be told one is taken")
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

    /// **STRENGTHENED: now NO failure names the Account ID, collision included.**
    ///
    /// C-70(a) filed this because three of the five triggers — a `name` edit, a
    /// `location` edit and the instrument manager closing — never touched the
    /// Account ID, yet every one of them could render a message blaming it. With
    /// the field removed there is no trigger left that could act on such a
    /// message, so the collision case joins the list rather than being excepted
    /// from it.
    func testNoFailureAtAllNamesTheAccountID() {
        let nonCollisions: [Error] = [
            // The collision itself, now held to the same rule as the rest.
            http(409, #"{"code":"23505","message":"violates unique constraint \"account_directory_account_id_key\""}"#),
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
