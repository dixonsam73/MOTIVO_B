//
//  DeclaredAgeRangeDerivationTests.swift
//  MOTIVOTests
//
//  PHASE 5 · CP-3 — the two rules that decide a child's treatment, tested pure.
//

import XCTest
@testable import Etudes

final class DeclaredAgeRangeDerivationTests: XCTestCase {

    // MARK: - C1 · Apple's own six sandbox fixtures

    /// The sandbox returns 13-15 and 16-17 as SEPARATE ranges, not the single
    /// 13-17 Études requests. A client matching on the numbers 13 and 18 would
    /// misclassify two of six official fixtures -- permissively, if it fell
    /// through to an adult default.
    func testAppleSandboxFixturesDeriveCorrectly() {
        XCTAssertEqual(DeclaredAgeRangeService.derive(lowerBound: nil, upperBound: 12), .ineligible)
        XCTAssertEqual(DeclaredAgeRangeService.derive(lowerBound: 13, upperBound: 15), .band(.band13to17))
        XCTAssertEqual(DeclaredAgeRangeService.derive(lowerBound: 16, upperBound: 17), .band(.band13to17))
        XCTAssertEqual(DeclaredAgeRangeService.derive(lowerBound: 18, upperBound: nil), .band(.band18Plus))
    }

    /// A nil lowerBound cannot affirmatively establish 13-or-over, whatever the
    /// upper bound says, so it is ineligible rather than "probably a teenager".
    func testNilLowerBoundIsAlwaysIneligible() {
        for upper in [nil, 5, 12, 17, 18, 99] as [Int?] {
            XCTAssertEqual(DeclaredAgeRangeService.derive(lowerBound: nil, upperBound: upper), .ineligible,
                           "nil lowerBound must fail closed regardless of upperBound \(String(describing: upper))")
        }
    }

    func testBoundaryValues() {
        XCTAssertEqual(DeclaredAgeRangeService.derive(lowerBound: 12, upperBound: 12), .ineligible)
        XCTAssertEqual(DeclaredAgeRangeService.derive(lowerBound: 13, upperBound: nil), .band(.band13to17))
        XCTAssertEqual(DeclaredAgeRangeService.derive(lowerBound: 17, upperBound: 17), .band(.band13to17))
        XCTAssertEqual(DeclaredAgeRangeService.derive(lowerBound: 18, upperBound: 20), .band(.band18Plus))
        XCTAssertEqual(DeclaredAgeRangeService.derive(lowerBound: 99, upperBound: nil), .band(.band18Plus))
    }

    /// A regulatory override raising the bottom gate over-blocks, which is the
    /// correct outcome in that jurisdiction and is asserted so it is deliberate.
    func testRegulatoryOverrideOverBlocksRatherThanGuessing() {
        XCTAssertEqual(DeclaredAgeRangeService.derive(lowerBound: nil, upperBound: 15), .ineligible)
        XCTAssertEqual(DeclaredAgeRangeService.derive(lowerBound: 16, upperBound: nil), .band(.band13to17))
    }

    // MARK: - C7 · the single Share-default rule

    func testShareDefaultsOnOnlyForAConfirmedAdultBand() {
        XCTAssertTrue(DeclaredAgeRangeService.shareDefaultOn(band: .band18Plus, defaultPostingIsPrivate: false))
        XCTAssertFalse(DeclaredAgeRangeService.shareDefaultOn(band: .band18Plus, defaultPostingIsPrivate: true),
                       "an adult's own Default to Private Posts still wins")
    }

    /// Teen, and every UNKNOWN, default OFF. This is the inverse of the previous
    /// behaviour: fetchDefaultPostingIsPrivate() returns false on a missing
    /// profile AND on a fetch error, so every unknown used to resolve ON.
    func testTeenAndUnknownDefaultOff() {
        XCTAssertFalse(DeclaredAgeRangeService.shareDefaultOn(band: .band13to17, defaultPostingIsPrivate: false))
        XCTAssertFalse(DeclaredAgeRangeService.shareDefaultOn(band: .band13to17, defaultPostingIsPrivate: true))
        XCTAssertFalse(DeclaredAgeRangeService.shareDefaultOn(band: nil, defaultPostingIsPrivate: false),
                       "unknown band must default OFF")
        XCTAssertFalse(DeclaredAgeRangeService.shareDefaultOn(band: nil, defaultPostingIsPrivate: true))
    }

    // MARK: - Band vocabulary

    func testBandRawValuesMatchTheServerCheckConstraint() {
        XCTAssertEqual(AgeBand.band13to17.rawValue, "band_13_17")
        XCTAssertEqual(AgeBand.band18Plus.rawValue, "band_18_plus")
        XCTAssertEqual(AgeBand.allCases.count, 2, "there is no unknown band: absence is the unknown state")
        XCTAssertTrue(AgeBand.band13to17.isMinor)
        XCTAssertFalse(AgeBand.band18Plus.isMinor)
    }

    // MARK: - C2 · decoding refuses rather than defaults

    func testSelfStateDecodingRefusesUnknownShapes() {
        XCTAssertNil(AccountPrivacyService.decodeSelfState(Data("[]".utf8)))
        XCTAssertNil(AccountPrivacyService.decodeSelfState(Data("{}".utf8)))
        XCTAssertNil(AccountPrivacyService.decodeSelfState(Data(#"[{"o_age_band":"nonsense"}]"#.utf8)))
        XCTAssertTrue(AccountPrivacyService.isEmptyRowSet(Data("[]".utf8)))
        XCTAssertFalse(AccountPrivacyService.isEmptyRowSet(Data(#"[{"a":1}]"#.utf8)))
    }

    func testSelfStateDecodesEffectiveValuesSeparatelyFromStored() {
        let json = #"[{"o_age_band":"band_13_17","o_lookup_enabled":true,"o_lookup_effective":false,"o_follow_requests_enabled":true,"o_follow_requests_effective":false}]"#
        let state = AccountPrivacyService.decodeSelfState(Data(json.utf8))
        XCTAssertNotNil(state)
        // Stored preference survives; effective value is protective. That is the
        // adult-preference-under-a-teen-band override, read not recomputed.
        XCTAssertEqual(state?.lookupEnabled, true)
        XCTAssertEqual(state?.lookupEffective, false)
        XCTAssertEqual(state?.followRequestsEnabled, true)
        XCTAssertEqual(state?.followRequestsEffective, false)
    }
}
