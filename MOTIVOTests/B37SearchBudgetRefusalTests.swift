//
//  B37SearchBudgetRefusalTests.swift
//  MOTIVOTests
//
//  CHANGE-ID: 20260920_130000_B37_SearchBudgetRefusal
//  SCOPE: B-37 — the client's mapping of the server's search-budget refusal, and
//  the copy it produces. Pure functions only; no network, no database.
//  SEARCH-TOKEN: 20260920_130000_B37_SearchBudgetRefusal
//

import XCTest
@testable import Etudes

final class B37SearchBudgetRefusalTests: XCTestCase {

    // The body shape below is the one the LOCAL function produces, copied from a
    // local run rather than imagined: `details` is a JSON *string* containing
    // JSON, which is why parsing it takes two steps. Nothing here has been
    // observed against production.
    private func refusalBody(seconds: Int) -> String {
        "{\"code\":\"PT429\",\"details\":\"{\\\"retry_after_seconds\\\":\(seconds)}\",\"hint\":null,\"message\":\"search_rate_limited\"}"
    }

    // MARK: - mapping

    func testRefusalBecomesTypedRateLimitedWithDuration() {
        let err = NetworkManager.NetworkError.httpError(status: 429, body: refusalBody(seconds: 42))
        let mapped = AccountDirectoryService.mapSearchFailure(err)
        XCTAssertEqual(mapped as? DirectorySearchError, .rateLimited(retryAfterSeconds: 42))
    }

    func testMalformedDetailYieldsRefusalWithNoDuration() {
        // A refusal we cannot parse must still be a refusal — and must NOT
        // acquire an invented duration.
        let err = NetworkManager.NetworkError.httpError(status: 429, body: "{\"code\":\"PT429\",\"details\":\"not json\"}")
        XCTAssertEqual(AccountDirectoryService.mapSearchFailure(err) as? DirectorySearchError,
                       .rateLimited(retryAfterSeconds: nil))
    }

    func testMissingBodyYieldsRefusalWithNoDuration() {
        let err = NetworkManager.NetworkError.httpError(status: 429, body: nil)
        XCTAssertEqual(AccountDirectoryService.mapSearchFailure(err) as? DirectorySearchError,
                       .rateLimited(retryAfterSeconds: nil))
    }

    func testOtherFailuresAreLeftAlone() {
        // The counter-fault path: fail-closed arrives as an ordinary error and
        // must NOT be dressed up as a throttle.
        let fault = NetworkManager.NetworkError.httpError(
            status: 400, body: "{\"code\":\"P0001\",\"message\":\"b37 induced counter fault\"}")
        XCTAssertNil(AccountDirectoryService.mapSearchFailure(fault) as? DirectorySearchError)

        let transport = NetworkManager.NetworkError.transportError("offline")
        XCTAssertNil(AccountDirectoryService.mapSearchFailure(transport) as? DirectorySearchError)
    }

    func testA401IsNeverAThrottle() {
        // Load-bearing: NetworkManager refreshes the session and retries on 401
        // only. If a throttle were ever mapped from a 401 the client would sign
        // the member's session around in circles. Tested with OUR OWN refusal
        // body, because the first revision matched on the code as well as the
        // status and would have thrown a 401 carrying PT429 down this path.
        let err = NetworkManager.NetworkError.httpError(status: 401, body: self.refusalBody(seconds: 42))
        XCTAssertNil(AccountDirectoryService.mapSearchFailure(err) as? DirectorySearchError)

        let serverFault = NetworkManager.NetworkError.httpError(status: 500, body: self.refusalBody(seconds: 42))
        XCTAssertNil(AccountDirectoryService.mapSearchFailure(serverFault) as? DirectorySearchError)
    }

    func testAnUnrecognised429IsAThrottleWithNoDuration() {
        // A gateway's 429 is still a throttle; its body is not ours, so no
        // duration may be taken from it.
        let gateway = NetworkManager.NetworkError.httpError(
            status: 429, body: "{\"code\":\"EDGE_RATE\",\"details\":\"{\\\"retry_after_seconds\\\":9999}\"}")
        XCTAssertEqual(AccountDirectoryService.mapSearchFailure(gateway) as? DirectorySearchError,
                       .rateLimited(retryAfterSeconds: nil))
    }

    func testMalformedDurationsAreRejectedRatherThanCoerced() {
        // JSONSerialization bridges JSON `true` to NSNumber, so `as? Int` would
        // have turned it into a one-second wait. Each of these must yield NO
        // duration rather than a coerced one.
        for detail in ["{\"retry_after_seconds\":true}",
                       "{\"retry_after_seconds\":42.5}",
                       "{\"retry_after_seconds\":\"42\"}",
                       "{\"retry_after_seconds\":null}",
                       "{}"] {
            let escaped = detail.replacingOccurrences(of: "\"", with: "\\\"")
            let body = "{\"code\":\"PT429\",\"message\":\"search_rate_limited\",\"details\":\"\(escaped)\"}"
            let mapped = AccountDirectoryService.mapSearchFailure(
                NetworkManager.NetworkError.httpError(status: 429, body: body))
            XCTAssertEqual(mapped as? DirectorySearchError, .rateLimited(retryAfterSeconds: nil),
                           "detail \(detail) must not produce a duration")
        }
    }

    // MARK: - copy

    func testCopyNamesNoTimeWhenTheServerGaveNone() {
        let text = DirectorySearchThrottleCopy.message(retryAfterSeconds: nil)
        XCTAssertFalse(text.contains("minute"))
        XCTAssertFalse(text.contains("hour"))
        XCTAssertTrue(text.contains("later"))
    }

    func testCopyRejectsImplausibleDurations() {
        for bad in [0, -1, 24 * 60 * 60 + 1] {
            let text = DirectorySearchThrottleCopy.message(retryAfterSeconds: bad)
            XCTAssertTrue(text.contains("later"), "durations like \(bad) must not be printed")
        }
    }

    func testRoundedDurations() {
        XCTAssertEqual(DirectorySearchThrottleCopy.roundedDuration(seconds: 1), "about a minute")
        XCTAssertEqual(DirectorySearchThrottleCopy.roundedDuration(seconds: 60), "about a minute")
        XCTAssertEqual(DirectorySearchThrottleCopy.roundedDuration(seconds: 61), "about 2 minutes")
        XCTAssertEqual(DirectorySearchThrottleCopy.roundedDuration(seconds: 90), "about 2 minutes")
        XCTAssertEqual(DirectorySearchThrottleCopy.roundedDuration(seconds: 120), "about 2 minutes")
        XCTAssertEqual(DirectorySearchThrottleCopy.roundedDuration(seconds: 3000), "about 50 minutes")
        XCTAssertEqual(DirectorySearchThrottleCopy.roundedDuration(seconds: 3600), "about an hour")
        XCTAssertEqual(DirectorySearchThrottleCopy.roundedDuration(seconds: 7200), "about 2 hours")
    }

    func testThrottleCopyIsDistinctFromTheOtherTwoOutcomes() {
        // The whole point of the unit: three outcomes, three messages.
        let throttle = DirectorySearchThrottleCopy.message(retryAfterSeconds: 42)
        XCTAssertNotEqual(throttle, "No results.")
        XCTAssertNotEqual(throttle, "Search unavailable.")
        XCTAssertFalse(throttle.lowercased().contains("no results"))
        XCTAssertFalse(throttle.lowercased().contains("unavailable"))
    }

    func testThrottleCopyDoesNotBlameTheMemberOrSuggestAFault() {
        let throttle = DirectorySearchThrottleCopy.message(retryAfterSeconds: 42)
        for forbidden in ["error", "failed", "unavailable", "problem", "wrong"] {
            XCTAssertFalse(throttle.lowercased().contains(forbidden),
                           "throttle copy must not read as a fault: '\(forbidden)'")
        }
    }
}
