//
//  ConnectedOfferPresentationTests.swift
//  MOTIVOTests
//
//  FOUNDING 500 — the copy a member sees before being charged.
//
//  These drive the PRODUCTION decision function. An earlier draft constructed
//  `OfferCopy` values by hand and asserted they were non-empty, which tested the
//  test and exercised no branch of the thing shipping.
//
//  No StoreKit types are used: the pure function takes plain values, which is
//  what makes the eligibility and offer branches reachable at all.
//

import XCTest
@testable import Etudes

private typealias Presentation = ConnectedOfferPresentation
private typealias Offer = ConnectedOfferPresentation.IntroductoryOffer

final class ConnectedOfferPresentationTests: XCTestCase {

    private let freeYear = Offer(unit: .month, value: 12, periodCount: 1, isFreeTrial: true)

    /// Duration text is localized, so every assertion on it pins a locale.
    /// Without this the suite would pass or fail according to the machine's
    /// region, which is the classic way a localisation change goes unnoticed.
    private let en = Locale(identifier: "en_GB")

    // MARK: - The branches that decide whether trial language appears

    func testEligibleFreeTrialProducesTrialCopy() {
        let copy = Presentation.copy(
            isEligible: true, offer: freeYear, displayPrice: "£49.99", cadence: "per year")
        guard case .freeTrial = copy else { return XCTFail("expected freeTrial, got \(copy)") }
    }

    /// Apple says this customer is not eligible, so no trial may be shown even
    /// though the product carries one.
    func testIneligibleFallsBackToStandard() {
        let copy = Presentation.copy(
            isEligible: false, offer: freeYear, displayPrice: "£49.99", cadence: "per year")
        XCTAssertEqual(copy, .standard(price: "£49.99", cadence: "per year"))
    }

    /// No offer configured on the product.
    func testNoOfferFallsBackToStandard() {
        let copy = Presentation.copy(
            isEligible: true, offer: nil, displayPrice: "£4.99", cadence: "per month")
        XCTAssertEqual(copy, .standard(price: "£4.99", cadence: "per month"))
    }

    /// **A discounted introductory price is NOT a free trial**, and describing it
    /// as free would be a false statement about money.
    func testNonFreeIntroductoryOfferIsNotPresentedAsFree() {
        let discounted = Offer(unit: .month, value: 3, periodCount: 1, isFreeTrial: false)
        let copy = Presentation.copy(
            isEligible: true, offer: discounted, displayPrice: "£4.99", cadence: "per month")
        XCTAssertEqual(copy, .standard(price: "£4.99", cadence: "per month"))
    }

    // MARK: - What the trial copy must contain

    /// The disclosure guarantee, asserted on the FUNCTION'S OUTPUT rather than on
    /// the type — empty strings compile, so the type cannot carry this.
    func testTrialCopyCarriesPriceCadenceRenewalAndCancellation() {
        let copy = Presentation.copy(
            isEligible: true, offer: freeYear, displayPrice: "£49.99",
            cadence: "per year", locale: en)
        guard case let .freeTrial(duration, thenPrice, cadence, renewal, cancellation) = copy else {
            return XCTFail("expected freeTrial")
        }
        XCTAssertEqual(duration, "1 year")
        XCTAssertEqual(thenPrice, "£49.99")
        XCTAssertEqual(cadence, "per year")
        XCTAssertEqual(renewal, Presentation.renewalNotice)
        XCTAssertEqual(cancellation, Presentation.cancellationNotice)
        XCTAssertFalse(renewal.isEmpty)
        XCTAssertFalse(cancellation.isEmpty)
    }

    func testRenewalNoticeStatesAutomaticRenewalAndCancellation() {
        let notice = Presentation.renewalNotice.lowercased()
        XCTAssertTrue(notice.contains("renews automatically"))
        XCTAssertTrue(notice.contains("unless you cancel"))
    }

    func testCancellationNoticePointsAtAppleSubscriptions() {
        let notice = Presentation.cancellationNotice.lowercased()
        XCTAssertTrue(notice.contains("settings"))
        XCTAssertTrue(notice.contains("subscriptions"))
    }

    /// The inverse, and the one that misleads in the more damaging direction:
    /// standard copy must contain no trial language at all.
    func testStandardCopyContainsNoTrialLanguage() {
        let copy = Presentation.copy(
            isEligible: false, offer: freeYear, displayPrice: "£4.99", cadence: "per month")
        guard case let .standard(price, cadence) = copy else { return XCTFail("expected standard") }
        let combined = (price + " " + cadence).lowercased()
        for forbidden in ["free", "trial", "introductory"] {
            XCTAssertFalse(combined.contains(forbidden), "standard copy must not say '\(forbidden)'")
        }
    }

    // MARK: - Duration

    func testTwelveMonthsReadsAsOneYear() {
        XCTAssertEqual(Presentation.durationText(freeYear, locale: en), "1 year")
    }

    func testOneYearUnitReadsAsOneYear() {
        XCTAssertEqual(
            Presentation.durationText(
                Offer(unit: .year, value: 1, periodCount: 1, isFreeTrial: true), locale: en),
            "1 year")
    }

    /// `periodCount` multiplies the period — Apple expresses three months either
    /// way, and reading only the unit would understate the offer.
    func testPeriodCountMultipliesThePeriod() {
        XCTAssertEqual(
            Presentation.durationText(
                Offer(unit: .month, value: 1, periodCount: 3, isFreeTrial: true), locale: en),
            "3 months")
        XCTAssertEqual(
            Presentation.durationText(
                Offer(unit: .month, value: 3, periodCount: 1, isFreeTrial: true), locale: en),
            "3 months")
    }

    func testSingularAndPluralUnits() {
        XCTAssertEqual(
            Presentation.durationText(
                Offer(unit: .week, value: 1, periodCount: 1, isFreeTrial: true), locale: en),
            "1 week")
        XCTAssertEqual(
            Presentation.durationText(
                Offer(unit: .week, value: 2, periodCount: 1, isFreeTrial: true), locale: en),
            "2 weeks")
        XCTAssertEqual(
            Presentation.durationText(
                Offer(unit: .day, value: 3, periodCount: 1, isFreeTrial: true), locale: en),
            "3 days")
    }

    func testZeroPeriodCountIsTreatedAsOne() {
        XCTAssertEqual(
            Presentation.durationText(
                Offer(unit: .month, value: 1, periodCount: 0, isFreeTrial: true), locale: en),
            "1 month")
    }

    /// **Proves localisation actually happens.** Asserting a specific French
    /// string would pin a translation we do not own; asserting only that the
    /// text DIFFERS from English catches the real regression — someone
    /// reintroducing hand-built English plurals, which would return the same
    /// string for every locale.
    func testDurationIsLocalizedRatherThanHardcodedEnglish() {
        let english = Presentation.durationText(freeYear, locale: Locale(identifier: "en_GB"))
        let french = Presentation.durationText(freeYear, locale: Locale(identifier: "fr_FR"))
        XCTAssertFalse(french.isEmpty)
        XCTAssertNotEqual(english, french, "duration text is not being localized")
    }
}
