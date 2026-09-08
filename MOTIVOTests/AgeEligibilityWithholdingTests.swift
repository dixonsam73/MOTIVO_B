//
//  AgeEligibilityWithholdingTests.swift
//  MOTIVOTests
//
//  PHASE 5 · P5-G / D1 — decoding and the structural guarantees.
//

import XCTest
@testable import Etudes

final class AgeEligibilityWithholdingTests: XCTestCase {

    private func row(_ withheld: Bool) -> Data {
        Data("""
        [{"o_age_band":"band_18_plus","o_lookup_enabled":true,"o_lookup_effective":\(!withheld),
          "o_follow_requests_enabled":true,"o_follow_requests_effective":\(!withheld),
          "o_band_updated_at":"2026-09-08T00:00:00Z","o_age_eligibility_withheld":\(withheld)}]
        """.utf8)
    }

    func testDecodesWithholdingTrue() {
        let state = AccountPrivacyService.decodeSelfState(row(true))
        XCTAssertEqual(state?.ageEligibilityWithheld, true)
        XCTAssertEqual(state?.lookupEffective, false)
        XCTAssertEqual(state?.lookupEnabled, true, "the underlying preference must be preserved, not rewritten")
    }

    func testDecodesWithholdingFalse() {
        let state = AccountPrivacyService.decodeSelfState(row(false))
        XCTAssertEqual(state?.ageEligibilityWithheld, false)
        XCTAssertEqual(state?.lookupEffective, true)
    }

    /// A response missing the column is a shape we do not recognise. Defaulting
    /// it to `false` would silently grant eligibility — so it is REFUSED.
    func testAResponseWithoutTheColumnIsRefusedRatherThanDefaulted() {
        let legacy = Data("""
        [{"o_age_band":"band_18_plus","o_lookup_enabled":true,"o_lookup_effective":true,
          "o_follow_requests_enabled":true,"o_follow_requests_effective":true,
          "o_band_updated_at":"2026-09-08T00:00:00Z"}]
        """.utf8)
        XCTAssertNil(AccountPrivacyService.decodeSelfState(legacy))
    }

    func testEmptyRowSetIsStillTheUnknownState() {
        XCTAssertTrue(AccountPrivacyService.isEmptyRowSet(Data("[]".utf8)))
        XCTAssertNil(AccountPrivacyService.decodeSelfState(Data("[]".utf8)))
    }

    // MARK: - Structural guarantees, asserted against source

    private func source(_ name: String) -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
        return (try? String(contentsOf: root.appendingPathComponent("MOTIVO/\(name)"), encoding: .utf8)) ?? ""
    }

    /// The mode guard must sit BEFORE the entitlement guard, so a withheld
    /// member is never routed into purchase copy.
    func testAgeGuardPrecedesEntitlementGuard() {
        let s = source("AppModeManager.swift")
        guard let age = s.range(of: "guard !auth.ageEligibilityWithheld"),
              let ent = s.range(of: "guard isEntitled else") else {
            return XCTFail("guards not found")
        }
        XCTAssertTrue(age.lowerBound < ent.lowerBound,
                      "the age term must precede entitlement so the age reason is operative")
    }

    /// There must be no way for a client to ask the server to CLEAR withholding.
    func testNoClientPathClearsWithholdingDirectly() {
        let s = source("AccountPrivacyService.swift")
        XCTAssertTrue(s.contains("account_privacy_withhold_age_eligibility_v1"))
        XCTAssertFalse(s.contains("p_withheld"),
                       "the withhold RPC must stay parameterless: no way to pass false")
    }

    /// Account deletion must never be gated on AppMode — C-35, sprung twice.
    func testDeletionRemainsGatedOnIdentityNotMode() {
        let s = source("ProfileView.swift")
        XCTAssertTrue(s.contains("guard auth.hasConnectedIdentity else {"),
                      "deletion must remain identity-gated while withheld")
    }

    /// Hiding the promo section would remove the erase button with it.
    func testEraseButtonSurvivesTheWithheldBranch() {
        let s = source("ProfileView.swift")
        guard let section = s.range(of: "private var connectedPromoSection") else {
            return XCTFail("section not found")
        }
        let tail = String(s[section.lowerBound...])
        XCTAssertTrue(tail.contains("ageEligibilityWithheldRow"))
        XCTAssertTrue(tail.contains("eraseAllEtudesDataButton"),
                      "the erase button must remain inside the section that the withheld branch edits")
    }

    /// The static copy is not the retry path; "Check Again" is a separate action.
    func testCheckAgainIsADistinctControlAndCannotReachPurchase() {
        let s = source("ProfileView.swift")
        guard let row = s.range(of: "private var ageEligibilityWithheldRow") ,
              let end = s.range(of: "private var connectedPromoSection") else {
            return XCTFail("row not found")
        }
        let body = String(s[row.lowerBound..<end.lowerBound])
        XCTAssertTrue(body.contains("Études Connected is for ages 13 and over."))
        XCTAssertTrue(body.contains("Check Again"))
        XCTAssertFalse(body.contains("showConnectedIntroduction"),
                       "the withheld row must never route into the purchase flow")
        XCTAssertFalse(body.contains("showMembershipSelection"))
    }
}
