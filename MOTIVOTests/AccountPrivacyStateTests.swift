//
//  AccountPrivacyStateTests.swift
//  MOTIVOTests
//
//  The client half of `account_privacy`: the server's band vocabulary, and
//  decoding that refuses rather than defaults. (The 13+ derivation and the
//  band-keyed Share default were removed with the adult-only gate; see
//  ConnectedAgeGateTests.)
//

import XCTest
@testable import Etudes

final class AccountPrivacyStateTests: XCTestCase {

    // MARK: - Band vocabulary

    func testBandRawValuesMatchTheServerCheckConstraint() {
        XCTAssertEqual(AgeBand.band13to17.rawValue, "band_13_17")
        XCTAssertEqual(AgeBand.band18Plus.rawValue, "band_18_plus")
        XCTAssertEqual(AgeBand.allCases.count, 2, "there is no unknown band: absence is the unknown state")
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
