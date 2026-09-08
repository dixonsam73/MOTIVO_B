//
//  AgeBandRefreshPolicyTests.swift
//  MOTIVOTests
//
//  PHASE 5 · P5-G / D1. The PURE halves of the refresh policy, so the rules that
//  govern a child's treatment are testable without Apple, a network or a view.
//

import XCTest
@testable import Etudes

final class AgeBandRefreshPolicyTests: XCTestCase {

    // MARK: - The asymmetry. THIS IS THE DANGEROUS PART OF D1.

    /// Establishment collapses `.ineligible` and `.unavailable` in effect —
    /// both refuse Connected. **Refresh must not**, and these two cases are why.
    func testUnavailableRetainsSilently_neverErasesAnEstablishedBand() {
        XCTAssertEqual(AgeBandRefreshPolicy.decide(outcome: .unavailable), .retainSilently)
    }

    func testIneligibleWithholds_ratherThanBeingIgnored() {
        XCTAssertEqual(AgeBandRefreshPolicy.decide(outcome: .ineligible), .withhold)
    }

    func testValidBandsEstablish() {
        XCTAssertEqual(AgeBandRefreshPolicy.decide(outcome: .band(.band18Plus)), .establish(.band18Plus))
        XCTAssertEqual(AgeBandRefreshPolicy.decide(outcome: .band(.band13to17)), .establish(.band13to17))
    }

    /// No outcome may write a band except a conclusive valid one.
    func testOnlyAConclusiveBandEverWritesABand() {
        for outcome in [DeclaredAgeRangeOutcome.ineligible, .unavailable] {
            if case .establish = AgeBandRefreshPolicy.decide(outcome: outcome) {
                XCTFail("\(outcome) must never establish a band")
            }
        }
    }

    // MARK: - Which clocks a decision moves

    /// An unsuccessful check must never delay the next automatic refresh by a
    /// month.
    func testOnlyAConclusiveBandMovesTheThirtyDayClock() {
        XCTAssertTrue(AgeBandRefreshPolicy.stampsConclusive(.establish(.band18Plus)))
        XCTAssertFalse(AgeBandRefreshPolicy.stampsConclusive(.withhold))
        XCTAssertFalse(AgeBandRefreshPolicy.stampsConclusive(.retainSilently))
    }

    func testEveryOutcomeRecordsAnAttempt() {
        XCTAssertTrue(AgeBandRefreshPolicy.stampsAttempt(.establish(.band18Plus)))
        XCTAssertTrue(AgeBandRefreshPolicy.stampsAttempt(.withhold))
        XCTAssertTrue(AgeBandRefreshPolicy.stampsAttempt(.retainSilently))
    }

    // MARK: - Automatic throttle

    func testNeverRefreshedIsDue() {
        XCTAssertTrue(AgeBandRefreshPolicy.isAutomaticRefreshDue(
            lastConclusiveAt: nil, lastAttemptAt: nil, now: Date()))
    }

    func testWithinThirtyDaysOfAConclusiveResultIsNotDue() {
        let now = Date()
        XCTAssertFalse(AgeBandRefreshPolicy.isAutomaticRefreshDue(
            lastConclusiveAt: now.addingTimeInterval(-29 * 86_400),
            lastAttemptAt: nil, now: now))
    }

    func testAfterThirtyDaysIsDue() {
        let now = Date()
        XCTAssertTrue(AgeBandRefreshPolicy.isAutomaticRefreshDue(
            lastConclusiveAt: now.addingTimeInterval(-31 * 86_400),
            lastAttemptAt: now.addingTimeInterval(-25 * 3_600), now: now))
    }

    /// A failure must not be retried on essentially every foreground.
    func testWithinTwentyFourHoursOfAnAttemptIsNotDue() {
        let now = Date()
        XCTAssertFalse(AgeBandRefreshPolicy.isAutomaticRefreshDue(
            lastConclusiveAt: nil,
            lastAttemptAt: now.addingTimeInterval(-3_600), now: now))
    }

    func testAfterTwentyFourHoursAFailedAttemptRetries() {
        let now = Date()
        XCTAssertTrue(AgeBandRefreshPolicy.isAutomaticRefreshDue(
            lastConclusiveAt: nil,
            lastAttemptAt: now.addingTimeInterval(-25 * 3_600), now: now))
    }

    func testCadenceAndRetryValues() {
        XCTAssertEqual(AgeBandRefreshPolicy.cadence, 30 * 86_400)
        XCTAssertEqual(AgeBandRefreshPolicy.retryInterval, 86_400)
    }

    // MARK: - Storage: per identity, and swept

    private func defaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testTimestampsAreScopedPerIdentity() {
        let d = defaults("p5g.tests.scope")
        AgeBandRefreshPolicy.record(decision: .establish(.band18Plus), userID: "A", now: Date(), defaults: d)
        XCTAssertNotNil(AgeBandRefreshPolicy.lastConclusive(userID: "A", defaults: d))
        XCTAssertNil(AgeBandRefreshPolicy.lastConclusive(userID: "B", defaults: d),
                     "one identity must not inherit another's throttle on a shared device")
    }

    func testWithholdStampsOnlyTheAttemptClock() {
        let d = defaults("p5g.tests.stamp")
        AgeBandRefreshPolicy.record(decision: .withhold, userID: "A", now: Date(), defaults: d)
        XCTAssertNil(AgeBandRefreshPolicy.lastConclusive(userID: "A", defaults: d))
        XCTAssertNotNil(AgeBandRefreshPolicy.lastAttempt(userID: "A", defaults: d))
    }

    func testClearRemovesBothClocks() {
        let d = defaults("p5g.tests.clear")
        AgeBandRefreshPolicy.record(decision: .establish(.band18Plus), userID: "A", now: Date(), defaults: d)
        AgeBandRefreshPolicy.clear(userID: "A", defaults: d)
        XCTAssertNil(AgeBandRefreshPolicy.lastConclusive(userID: "A", defaults: d))
        XCTAssertNil(AgeBandRefreshPolicy.lastAttempt(userID: "A", defaults: d))
    }

    func testClearAllSweepsEveryIdentity() {
        let d = defaults("p5g.tests.clearall")
        AgeBandRefreshPolicy.record(decision: .establish(.band18Plus), userID: "A", now: Date(), defaults: d)
        AgeBandRefreshPolicy.record(decision: .withhold, userID: "B", now: Date(), defaults: d)
        AgeBandRefreshPolicy.clearAll(defaults: d)
        XCTAssertNil(AgeBandRefreshPolicy.lastConclusive(userID: "A", defaults: d))
        XCTAssertNil(AgeBandRefreshPolicy.lastAttempt(userID: "B", defaults: d))
    }
}
