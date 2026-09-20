//
//  C70DirectoryWriteEvidenceTests.swift
//  MOTIVOTests
//
//  CHANGE-ID: 20260920_190000_C70_DirectoryWriteEvidence
//  SCOPE: C-70 — what a directory write establishes, and what it does NOT.
//  The load-bearing assertions here are the NEGATIVE ones: that nothing but an
//  evidenced success is ever treated as saved, and that a receipt which is
//  stale against local intent is never published into the shared identity.
//  SEARCH-TOKEN: 20260920_190000_C70_DirectoryWriteEvidence
//

import XCTest
@testable import Etudes

// MARK: - Evidence

final class C70DirectoryWriteEvidenceTests: XCTestCase {

    private let owner = "11111111-1111-1111-1111-111111111111"

    private func rowJSON(userID: String,
                         displayName: String? = "Ada",
                         accountID: String?? = .some("ada"),
                         location: String?? = .some("London"),
                         instruments: [String]?? = .some(["piano"])) -> String {
        func lit(_ s: String?) -> String { s.map { "\"\($0)\"" } ?? "null" }
        var parts = ["\"user_id\":\"\(userID)\""]
        parts.append("\"display_name\":\(lit(displayName))")
        if let accountID { parts.append("\"account_id\":\(lit(accountID))") }
        if let location { parts.append("\"location\":\(lit(location))") }
        if let instruments {
            let arr = instruments.map { "[" + $0.map { "\"\($0)\"" }.joined(separator: ",") + "]" } ?? "null"
            parts.append("\"instruments\":\(arr)")
        }
        return "[{" + parts.joined(separator: ",") + "}]"
    }

    private func resolve(_ json: String, owner: String? = nil) -> DirectoryWriteEvidence.Resolution {
        DirectoryWriteEvidence.resolve(data: Data(json.utf8), owner: owner ?? self.owner)
    }

    // MARK: row-count and identity

    /// **The defect this whole unit exists for.** `return=minimal` made a write
    /// that matched NOTHING indistinguishable from one that changed the row.
    func testZeroRowsIsNotSuccess() {
        guard case .settled(let outcome) = resolve("[]") else { return XCTFail("expected settled") }
        guard case .noRowMatched = outcome else { return XCTFail("zero rows must be noRowMatched, got \(outcome)") }
        XCTAssertFalse(outcome.isApplied)
    }

    /// Taking `.first` is how a wrong row gets adopted.
    func testMoreThanOneRowIsAFailure() {
        let two = "[{\"user_id\":\"\(owner)\",\"display_name\":\"A\",\"account_id\":null,\"location\":null,\"instruments\":null},"
                + "{\"user_id\":\"\(owner)\",\"display_name\":\"B\",\"account_id\":null,\"location\":null,\"instruments\":null}]"
        guard case .settled(let outcome) = resolve(two) else { return XCTFail("expected settled") }
        guard case .failed = outcome else { return XCTFail("two rows must fail, got \(outcome)") }
    }

    func testReceiptForAnotherRowIsNeverAccepted() {
        let other = "22222222-2222-2222-2222-222222222222"
        guard case .settled(let outcome) = resolve(rowJSON(userID: other)) else { return XCTFail("expected settled") }
        guard case .failed = outcome else { return XCTFail("owner mismatch must fail, got \(outcome)") }
    }

    func testOwnerComparisonIsCaseInsensitiveOnUUIDs() {
        guard case .row = resolve(rowJSON(userID: owner.uppercased())) else {
            return XCTFail("a UUID is case-insensitive; the same row must be accepted")
        }
    }

    /// A key absent from the response is MALFORMED EVIDENCE, not a null — and
    /// the caches consume all four columns, so a missing one would silently
    /// clear a cached value the write never targeted.
    func testMissingSelectedColumnIsMalformedEvidence() {
        for json in [rowJSON(userID: owner, location: .none),
                     rowJSON(userID: owner, accountID: .none),
                     rowJSON(userID: owner, instruments: .none)] {
            guard case .settled(let outcome) = resolve(json) else {
                return XCTFail("a missing selected column must not resolve to a row")
            }
            guard case .failed = outcome else { return XCTFail("expected failed, got \(outcome)") }
        }
    }

    func testPresentAndNullIsNotMissing() {
        guard case .row(let r) = resolve(rowJSON(userID: owner, location: .some(nil))) else {
            return XCTFail("an explicit null is present evidence")
        }
        XCTAssertTrue(r.locationPresent)
        XCTAssertNil(r.location)
    }

    func testSelectListAndRequiredColumnsShareOneDefinition() {
        XCTAssertEqual(DirectoryWriteEvidence.selectList,
                       DirectoryWriteEvidence.selectedColumns.joined(separator: ","))
        XCTAssertTrue(DirectoryWriteEvidence.selectedColumns.contains("user_id"))
        // CP-3 and C-70 §5: neither privacy nor avatar columns are ever selected.
        for forbidden in ["lookup_enabled", "follow_requests_enabled", "avatar_key", "avatar_version"] {
            XCTAssertFalse(DirectoryWriteEvidence.selectedColumns.contains(forbidden),
                           "\(forbidden) must never be selected by a profile write")
        }
    }

    // MARK: value evidence

    private func receipt(displayName: String? = "Ada",
                         accountID: String? = "ada",
                         location: String? = "London",
                         instruments: [String]? = ["piano"]) -> DirectoryWriteReceipt {
        DirectoryWriteReceipt(userID: owner,
                              displayName: displayName, displayNamePresent: true,
                              accountID: accountID, accountIDPresent: true,
                              location: location, locationPresent: true,
                              instruments: instruments, instrumentsPresent: true)
    }

    func testEverySentFieldMatchingIsEvidenced() {
        let payload: [String: Any] = ["display_name": "Ada", "location": "London",
                                      "account_id": "ada", "instruments": ["piano"]]
        let e = DirectoryWriteEvidence.expectation(from: payload)
        XCTAssertEqual(e.count, 4)
        XCTAssertTrue(DirectoryWriteEvidence.matches(e, receipt()))
    }

    func testASingleDifferingFieldIsNotEvidenced() {
        let payload: [String: Any] = ["display_name": "Ada", "location": "London"]
        let e = DirectoryWriteEvidence.expectation(from: payload)
        XCTAssertFalse(DirectoryWriteEvidence.matches(e, receipt(displayName: "Grace")))
        XCTAssertFalse(DirectoryWriteEvidence.matches(e, receipt(location: "Paris")))
    }

    /// `upsertSelfRow` omits a blank or invalid handle so an existing one is
    /// preserved. An omitted key asserts NOTHING and comparing it would fail a
    /// write that behaved exactly as designed.
    func testOmittedKeysAreNotCompared() {
        let payload: [String: Any] = ["display_name": "Ada", "location": "London"]
        let e = DirectoryWriteEvidence.expectation(from: payload)
        XCTAssertTrue(DirectoryWriteEvidence.matches(e, receipt(accountID: "something_else",
                                                                instruments: ["cello"])))
    }

    func testExplicitNullLocationRequiresANullReceipt() {
        let payload: [String: Any] = ["display_name": "Ada", "location": NSNull()]
        let e = DirectoryWriteEvidence.expectation(from: payload)
        XCTAssertTrue(e.contains(.locationNull))
        XCTAssertTrue(DirectoryWriteEvidence.matches(e, receipt(location: nil)))
        XCTAssertFalse(DirectoryWriteEvidence.matches(e, receipt(location: "London")))
    }

    func testInstrumentsAreComparedExactly() {
        let payload: [String: Any] = ["instruments": ["cello", "piano"]]
        let e = DirectoryWriteEvidence.expectation(from: payload)
        XCTAssertTrue(DirectoryWriteEvidence.matches(e, receipt(instruments: ["cello", "piano"])))
        XCTAssertFalse(DirectoryWriteEvidence.matches(e, receipt(instruments: ["piano", "cello"])))
    }

    /// Generation sends `account_id` ALONE, so only that key is expected of it —
    /// it must not be held to a display name it never submitted.
    func testGenerationExpectsOnlyTheHandle() {
        let payload: [String: Any] = ["account_id": "ada2"]
        let e = DirectoryWriteEvidence.expectation(from: payload)
        XCTAssertEqual(e, [.accountID("ada2")])
        XCTAssertTrue(DirectoryWriteEvidence.matches(e, receipt(displayName: "anything",
                                                                accountID: "ada2",
                                                                location: "anywhere")))
    }

    func testUserIDIsNeverAValueExpectation() {
        let payload: [String: Any] = ["user_id": owner, "display_name": "Ada"]
        XCTAssertEqual(DirectoryWriteEvidence.expectation(from: payload), [.displayName("Ada")])
    }

    // MARK: classification

    private func http(_ status: Int, _ body: String?) -> Error {
        NetworkManager.NetworkError.httpError(status: status, body: body)
    }

    func testPolicyRefusalIsTyped() {
        guard case .refusedByPolicy = DirectoryWriteEvidence.classify(
            http(403, #"{"code":"42501","message":"new row violates row-level security policy"}"#)) else {
            return XCTFail("403 + 42501 must classify as a policy refusal")
        }
    }

    /// **A BARE 23505 IS NOT ENOUGH.** `account_directory` carries two unique
    /// constraints and both raise it; asserting a handle collision from the code
    /// alone would blame the Account ID for a primary-key conflict.
    func testUniquenessIsClassifiedByConstraintNotByCode() {
        guard case .accountIDTaken = DirectoryWriteEvidence.classify(
            http(409, #"{"code":"23505","message":"duplicate key value violates unique constraint \"account_directory_account_id_key\""}"#)) else {
            return XCTFail("the named account_id constraint is a handle collision")
        }
        guard case .accountIDTaken = DirectoryWriteEvidence.classify(
            http(409, #"{"code":"23505","details":"Key (account_id)=(ada) already exists."}"#)) else {
            return XCTFail("the named account_id COLUMN is a handle collision")
        }
        guard case .rowConflict = DirectoryWriteEvidence.classify(
            http(409, #"{"code":"23505","message":"duplicate key value violates unique constraint \"account_directory_pkey\""}"#)) else {
            return XCTFail("the primary key is NOT a handle collision")
        }
        guard case .failed = DirectoryWriteEvidence.classify(http(409, #"{"code":"23505"}"#)) else {
            return XCTFail("a bare 23505 names no constraint and must not assert a handle collision")
        }
    }

    func testTransportFailureIsAmbiguousAndNeverSuccess() {
        guard case .ambiguous = DirectoryWriteEvidence.classify(
            NetworkManager.NetworkError.transportError("offline")) else {
            return XCTFail("a sent request with an unknown outcome is ambiguous")
        }
    }

    func testIdentityErrorsAreSuperseded() {
        for e in [TransportIdentityError.identityChanged,
                  TransportIdentityError.subjectMismatch,
                  TransportIdentityError.authorizationHeaderOverride] {
            guard case .supersededIdentity = DirectoryWriteEvidence.classify(e) else {
                return XCTFail("\(e) must never be reported as a write outcome")
            }
        }
    }

    // MARK: copy

    func testOnlyAnEvidencedWriteSaysNothingAndOnlyACollisionNamesTheField() {
        let r = receipt()
        XCTAssertNil(DirectorySyncFailure.message(for: .applied(r)))
        XCTAssertNil(DirectorySyncFailure.message(for: .superseded))
        XCTAssertNil(DirectorySyncFailure.message(for: .supersededIdentity))
        XCTAssertEqual(DirectorySyncFailure.message(for: .accountIDTaken),
                       DirectorySyncFailure.accountIDTakenMessage)
        for outcome: DirectoryWriteOutcome in [.notEvidenced(r), .noRowMatched, .refusedByPolicy,
                                               .rowConflict,
                                               .ambiguous(NetworkManager.NetworkError.transportError("x")),
                                               .failed(NetworkManager.NetworkError.notConfigured)] {
            XCTAssertEqual(DirectorySyncFailure.message(for: outcome), DirectorySyncFailure.genericMessage)
        }
    }

    /// The generic copy must claim only what is established. It may not assert
    /// that the change did not reach Connected, only that we could not confirm
    /// it did — and it must not promise local persistence it has not observed.
    func testGenericCopyClaimsOnlyWhatIsEstablished() {
        let m = DirectorySyncFailure.genericMessage.lowercased()
        XCTAssertTrue(m.contains("couldn’t confirm") || m.contains("couldn't confirm"))
        XCTAssertFalse(m.contains("saved on this device"),
                       "local persistence is not observed here and must not be promised")
        XCTAssertFalse(m.contains("try again"),
                       "a retry may be futile or unnecessary; the copy must not direct one")
        for field in ["account id", "account_id", "display name", "location", "instrument"] {
            XCTAssertFalse(m.contains(field), "generic copy must name no field, found: \(field)")
        }
    }
}
