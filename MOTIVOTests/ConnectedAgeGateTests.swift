//
//  ConnectedAgeGateTests.swift
//  MOTIVOTests
//
//  The adult-only gate: only an 18+ range that Apple reports as `.confirmed`
//  admits to Connected. Everything else is refused, with the reason the
//  anonymous refusal counter records.
//

import XCTest
@testable import Etudes

final class ConnectedAgeGateTests: XCTestCase {

    private typealias Gate = ConnectedAgeGate

    private static let allDeclarations: [Gate.Declaration?] =
        [nil, .confirmed, .selfDeclared, .guardianDeclared, .other]

    // MARK: - Admission

    func testOnlyAConfirmedAdultIsAdmitted() {
        XCTAssertEqual(Gate.evaluate(lowerBound: 18, upperBound: nil, declaration: .confirmed), .confirmedAdult)
        XCTAssertEqual(Gate.evaluate(lowerBound: 21, upperBound: 99, declaration: .confirmed), .confirmedAdult)
    }

    func testAnAdultThatIsNotConfirmedIsRefused() {
        for declaration in [nil, .selfDeclared, .guardianDeclared, .other] as [Gate.Declaration?] {
            XCTAssertEqual(Gate.evaluate(lowerBound: 18, upperBound: nil, declaration: declaration),
                           .refused(.unconfirmedAdult),
                           "18+ with declaration \(String(describing: declaration)) must be refused")
        }
    }

    // MARK: - Apple's sandbox ranges, against every declaration

    /// Apple's sandbox returns under-13, 13-15, 16-17 and 18+ as separate
    /// ranges. Every range below 18 is refused as under 18, whatever the
    /// declaration, including `.confirmed`.
    func testAppleSandboxRangesUnder18AreRefusedWhateverTheDeclaration() {
        let minorRanges: [(Int?, Int?)] = [(nil, 12), (13, 15), (16, 17)]
        for (lower, upper) in minorRanges {
            for declaration in Self.allDeclarations {
                XCTAssertEqual(Gate.evaluate(lowerBound: lower, upperBound: upper, declaration: declaration),
                               .refused(.under18),
                               "\(String(describing: lower))-\(String(describing: upper)) \(String(describing: declaration))")
            }
        }
    }

    func testBoundaries() {
        XCTAssertEqual(Gate.evaluate(lowerBound: 17, upperBound: 17, declaration: .confirmed), .refused(.under18))
        XCTAssertEqual(Gate.evaluate(lowerBound: 17, upperBound: nil, declaration: .confirmed), .refused(.under18))
        XCTAssertEqual(Gate.evaluate(lowerBound: 18, upperBound: 18, declaration: .confirmed), .confirmedAdult)
    }

    /// A nil lower bound is "below the lowest gate Apple used". It can never
    /// admit, whatever the upper bound or declaration says.
    func testNilLowerBoundNeverAdmits() {
        for upper in [5, 12, 17, 18, 99] as [Int?] {
            for declaration in Self.allDeclarations {
                XCTAssertEqual(Gate.evaluate(lowerBound: nil, upperBound: upper, declaration: declaration),
                               .refused(.under18))
            }
        }
    }

    /// No bounds at all is no answer, not an age.
    func testNoBoundsIsUnavailable() {
        for declaration in Self.allDeclarations {
            XCTAssertEqual(Gate.evaluate(lowerBound: nil, upperBound: nil, declaration: declaration),
                           .refused(.unavailable))
        }
    }

    /// Apple may raise the gate by region. A raised lower bound below 18 still
    /// refuses; only bounds decide, never the gate we asked for.
    func testRegionalGateOverrideStillDecidesByBounds() {
        XCTAssertEqual(Gate.evaluate(lowerBound: nil, upperBound: 20, declaration: .confirmed), .refused(.under18))
        XCTAssertEqual(Gate.evaluate(lowerBound: 21, upperBound: nil, declaration: .confirmed), .confirmedAdult)
    }

    // MARK: - Counter reasons and wording

    /// The raw values are the server counter's accepted reasons.
    func testRefusalReasonRawValuesMatchTheServerCounter() {
        XCTAssertEqual(Gate.RefusalReason.allCases.map(\.rawValue).sorted(),
                       ["declined", "ios_update_needed", "unavailable", "unconfirmed_adult", "under_18"])
    }

    func testRefusalWording() {
        XCTAssertTrue(Gate.refusalMessage(for: .iosUpdateNeeded).contains("Update iOS"))
        for reason in [.under18, .unconfirmedAdult, .declined, .unavailable] as [Gate.RefusalReason] {
            XCTAssertTrue(Gate.refusalMessage(for: reason).contains("Personal Information → Age Confirmation"),
                          "\(reason) must tell the person how to confirm")
        }
    }

    // MARK: - The stored result

    func testStoredResultRoundTripsEveryValue() {
        let all: [Gate.StoredResult] = [.confirmed] + Gate.RefusalReason.allCases.map { .refused($0) }
        for result in all {
            XCTAssertEqual(Gate.StoredResult(rawValue: result.rawValue), result)
        }
        XCTAssertNil(Gate.StoredResult(rawValue: "band_18_plus"))
    }

    func testOnlyAStoredConfirmationAdmits() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ConnectedAgeGateTests"))
        defaults.removePersistentDomain(forName: "ConnectedAgeGateTests")
        XCTAssertFalse(Gate.isConfirmedOnThisDevice(in: defaults), "never checked must not admit")
        Gate.setStoredResult(.refused(.unconfirmedAdult), in: defaults)
        XCTAssertFalse(Gate.isConfirmedOnThisDevice(in: defaults))
        Gate.setStoredResult(.confirmed, in: defaults)
        XCTAssertTrue(Gate.isConfirmedOnThisDevice(in: defaults))
        Gate.setStoredResult(nil, in: defaults)
        XCTAssertFalse(Gate.isConfirmedOnThisDevice(in: defaults))
        defaults.removePersistentDomain(forName: "ConnectedAgeGateTests")
    }

    func testConfirmationIsStoredFromAnyStartingPoint() {
        for current in [nil, .confirmed, .refused(.declined)] as [Gate.StoredResult?] {
            XCTAssertEqual(Gate.nextStoredResult(current: current, outcome: .confirmedAdult), .confirmed)
        }
    }

    /// Choice 1: an error is not an answer, so it never pauses a confirmed
    /// member and never confirms anyone.
    func testUnavailableLeavesTheStoredResultAlone() {
        for current in [nil, .confirmed, .refused(.under18)] as [Gate.StoredResult?] {
            XCTAssertEqual(Gate.nextStoredResult(current: current, outcome: .refused(.unavailable)), current)
        }
    }

    func testADecisiveRefusalReplacesAConfirmation() {
        for reason in [.under18, .unconfirmedAdult, .declined, .iosUpdateNeeded] as [Gate.RefusalReason] {
            XCTAssertEqual(Gate.nextStoredResult(current: .confirmed, outcome: .refused(reason)), .refused(reason))
        }
    }

    func testAutomaticCheckRunsWhenUncheckedOrConfirmedButNotAfterARefusal() {
        XCTAssertTrue(Gate.shouldCheckAutomatically(stored: nil, osCanReportConfirmed: true))
        XCTAssertTrue(Gate.shouldCheckAutomatically(stored: .confirmed, osCanReportConfirmed: true))
        for reason in [.under18, .unconfirmedAdult, .declined, .unavailable] as [Gate.RefusalReason] {
            XCTAssertFalse(Gate.shouldCheckAutomatically(stored: .refused(reason), osCanReportConfirmed: true),
                           "\(reason) must wait for the person to retry")
        }
    }

    func testIOSUpdateRefusalIsRetriedOnceIOSCanAnswer() {
        XCTAssertFalse(Gate.shouldCheckAutomatically(stored: .refused(.iosUpdateNeeded), osCanReportConfirmed: false))
        XCTAssertTrue(Gate.shouldCheckAutomatically(stored: .refused(.iosUpdateNeeded), osCanReportConfirmed: true))
    }

    // MARK: - Profile's paused notice

    func testPausedNoticeShowsOnlyForAnEntitledIdentityWithADecisiveRefusal() {
        XCTAssertEqual(Gate.pauseReason(hasConnectedIdentity: true, isEntitled: true,
                                        stored: .refused(.unconfirmedAdult)), .unconfirmedAdult)
        XCTAssertNil(Gate.pauseReason(hasConnectedIdentity: true, isEntitled: true, stored: .confirmed))
        XCTAssertNil(Gate.pauseReason(hasConnectedIdentity: true, isEntitled: true, stored: nil),
                     "never checked: a check is under way")
        XCTAssertNil(Gate.pauseReason(hasConnectedIdentity: true, isEntitled: false, stored: .refused(.declined)),
                     "a lapsed member has nothing to unpause")
        XCTAssertNil(Gate.pauseReason(hasConnectedIdentity: false, isEntitled: true, stored: .refused(.declined)),
                     "Solo users see the normal Explore Connected")
    }

    // MARK: - The Share default

    /// D-1 must survive: a confirmed adult with no private-posts preference
    /// defaults to sharing ON, exactly the pre-CP-3 expression.
    func testConfirmedAdultShareDefaultIsTheSettledRule() {
        for defaultPrivacy in [true, false] {
            XCTAssertEqual(Gate.shareDefaultOn(adultConfirmed: true, defaultPostingIsPrivate: defaultPrivacy),
                           !defaultPrivacy)
        }
    }

    func testShareDefaultIsOffWithoutAConfirmedAdult() {
        XCTAssertFalse(Gate.shareDefaultOn(adultConfirmed: false, defaultPostingIsPrivate: false))
        XCTAssertFalse(Gate.shareDefaultOn(adultConfirmed: false, defaultPostingIsPrivate: true))
    }

    // MARK: - The resolver

    @MainActor
    func testConnectedNeedsAConfirmedAdultAsWellAsEverythingElse() {
        XCTAssertEqual(ProductionAppModeActivation.resolve(backendConfigured: true, isEntitled: true,
                                                           hasConnectedIdentity: true, adultConfirmed: true), .connected)
        XCTAssertEqual(ProductionAppModeActivation.resolve(backendConfigured: true, isEntitled: true,
                                                           hasConnectedIdentity: true, adultConfirmed: false), .solo,
                       "an entitled member with an identity but no confirmation stays Solo")
        XCTAssertEqual(ProductionAppModeActivation.resolve(backendConfigured: true, isEntitled: false,
                                                           hasConnectedIdentity: true, adultConfirmed: true), .solo)
        XCTAssertEqual(ProductionAppModeActivation.resolve(backendConfigured: true, isEntitled: true,
                                                           hasConnectedIdentity: false, adultConfirmed: true), .solo)
        XCTAssertEqual(ProductionAppModeActivation.resolve(backendConfigured: false, isEntitled: true,
                                                           hasConnectedIdentity: true, adultConfirmed: true), .solo)
    }

    // MARK: - The automatic check's gating

    @MainActor
    func testRecheckGating() {
        let now = Date()
        func attempt(identity: Bool = true, backend: Bool = true, stored: Gate.StoredResult? = nil,
                     inFlight: Bool = false, last: Date? = nil) -> Bool {
            ConnectedAgeRecheck.shouldAttempt(hasConnectedIdentity: identity, backendConfigured: backend,
                                              stored: stored, osCanReportConfirmed: true,
                                              inFlight: inFlight, lastAttemptAt: last, now: now)
        }
        XCTAssertTrue(attempt())
        XCTAssertTrue(attempt(stored: .confirmed))
        XCTAssertFalse(attempt(identity: false), "Solo users are never asked")
        XCTAssertFalse(attempt(backend: false))
        XCTAssertFalse(attempt(stored: .refused(.declined)))
        XCTAssertFalse(attempt(inFlight: true))
        XCTAssertFalse(attempt(last: now.addingTimeInterval(-10)), "cooldown")
        XCTAssertTrue(attempt(last: now.addingTimeInterval(-(ConnectedAgeRecheck.cooldown + 1))))
    }

    // MARK: - Apple mapping

    #if canImport(DeclaredAgeRange)
    func testAppleDeclarationsMapStrictly() throws {
        guard #available(iOS 26.5, *) else { throw XCTSkip("needs iOS 26.5") }
        XCTAssertEqual(Gate.declaration(for: .confirmed), .confirmed)
        XCTAssertEqual(Gate.declaration(for: .selfDeclared), .selfDeclared)
        XCTAssertEqual(Gate.declaration(for: .guardianDeclared), .guardianDeclared)
    }
    #endif
}
