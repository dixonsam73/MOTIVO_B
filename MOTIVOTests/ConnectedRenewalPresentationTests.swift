//
//  ConnectedRenewalPresentationTests.swift
//  MOTIVOTests
//
//  FOUNDING 500 — the near-expiry notice, and what it must never claim.
//

import XCTest
@testable import Etudes

private typealias Renewal = ConnectedRenewalPresentation

final class ConnectedRenewalPresentationTests: XCTestCase {

    private let en = Locale(identifier: "en_GB")
    private let utc = TimeZone(identifier: "UTC")!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func daysFromNow(_ days: Double) -> Date {
        now.addingTimeInterval(days * 24 * 60 * 60)
    }

    // MARK: - When the notice appears

    func testNoNoticeWithoutAPeriodEnd() {
        XCTAssertEqual(
            Renewal.notice(periodEnd: nil, isFreeTrial: true, now: now, locale: en, timeZone: utc),
            .none)
    }

    /// A date far away is not something to warn about every launch.
    func testNoNoticeLongBeforeTheEnd() {
        XCTAssertEqual(
            Renewal.notice(periodEnd: daysFromNow(200), isFreeTrial: true, now: now, locale: en, timeZone: utc),
            .none)
    }

    /// An already-elapsed date describes access that has ended; warning that it
    /// "ends soon" would be false.
    func testNoNoticeAfterTheEnd() {
        XCTAssertEqual(
            Renewal.notice(periodEnd: daysFromNow(-1), isFreeTrial: true, now: now, locale: en, timeZone: utc),
            .none)
    }

    func testNoticeInsideTheWindow() {
        guard case .periodEnding = Renewal.notice(
            periodEnd: daysFromNow(10), isFreeTrial: true, now: now, locale: en, timeZone: utc)
        else { return XCTFail("expected a notice inside the window") }
    }

    // MARK: - What it must and must not say

    /// **The load-bearing one.** `expirationDate` is when the current period
    /// ends; after a cancellation it is when access stops. Nothing may call it a
    /// renewal, because we do not read verified auto-renew state.
    func testNoticeNeverClaimsTheMembershipRenews() {
        for isFreeTrial in [true, false] {
            guard case let .periodEnding(text) = Renewal.notice(
                periodEnd: daysFromNow(5), isFreeTrial: isFreeTrial, now: now, locale: en, timeZone: utc)
            else { return XCTFail("expected a notice") }
            XCTAssertFalse(text.lowercased().contains("renews"),
                           "notice must not claim renewal: \(text)")
        }
    }

    func testSummaryNeverClaimsTheMembershipRenews() {
        for isFreeTrial in [true, false] {
            let summary = Renewal.periodEndSummary(
                periodEnd: daysFromNow(5), isFreeTrial: isFreeTrial, locale: en, timeZone: utc)
            XCTAssertNotNil(summary)
            XCTAssertFalse(summary!.lowercased().contains("renews"),
                           "summary must not claim renewal: \(summary!)")
        }
    }

    /// Switching between monthly and annual does not avoid payment, so offering
    /// it as a way out would be a false escape route.
    func testFreeTrialNoticeDoesNotSuggestChangingPlanAvoidsPayment() {
        guard case let .periodEnding(text) = Renewal.notice(
            periodEnd: daysFromNow(5), isFreeTrial: true, now: now, locale: en, timeZone: utc)
        else { return XCTFail("expected a notice") }
        XCTAssertFalse(text.lowercased().contains("change plan"))
    }

    /// **Q10's regression, as an assertion.** The notice must not instruct a
    /// member to cancel: one who already has is then told their cancellation did
    /// not take. The condition is **automatic renewal**, which asserts nothing
    /// about what they have already done.
    ///
    /// **"still active" is also forbidden** — a cancelled trial remains active
    /// until it expires, so that phrasing would be wrong in the same case.
    ///
    /// This test previously asserted the opposite (`contains("unless you
    /// cancel")`). It was written to stop a different regression and locked in
    /// this one.
    func testFreeTrialNoticeStatesTheRenewalConditionRatherThanInstructingCancellation() {
        guard case let .periodEnding(text) = Renewal.notice(
            periodEnd: daysFromNow(5), isFreeTrial: true, now: now, locale: en, timeZone: utc)
        else { return XCTFail("expected a notice") }
        let lower = text.lowercased()
        XCTAssertTrue(lower.contains("automatic renewal"))
        XCTAssertFalse(lower.contains("unless you cancel"))
        XCTAssertFalse(lower.contains("still active"))
    }

    /// The feed card and Profile must say the same thing, or a member reading
    /// both is told two different stories about the same charge.
    func testCardAndProfileFreeTrialWordingAreIdentical() {
        guard case let .periodEnding(notice) = Renewal.notice(
            periodEnd: daysFromNow(5), isFreeTrial: true, now: now, locale: en, timeZone: utc)
        else { return XCTFail("expected a notice") }
        let card = ConnectedTrialReminder.message(
            periodEnd: daysFromNow(5), locale: en, timeZone: utc)
        XCTAssertEqual(notice, card)
    }

    /// A free period ending must say that payment follows — that is the whole
    /// point of the notice Samuel required.
    func testFreeTrialNoticeStatesPaymentFollows() {
        guard case let .periodEnding(text) = Renewal.notice(
            periodEnd: daysFromNow(5), isFreeTrial: true, now: now, locale: en, timeZone: utc)
        else { return XCTFail("expected a notice") }
        XCTAssertTrue(text.lowercased().contains("standard price"))
    }

    /// A paid period must NOT claim a free one is ending.
    func testPaidNoticeSaysNothingAboutFree() {
        guard case let .periodEnding(text) = Renewal.notice(
            periodEnd: daysFromNow(5), isFreeTrial: false, now: now, locale: en, timeZone: utc)
        else { return XCTFail("expected a notice") }
        XCTAssertFalse(text.lowercased().contains("free"))
    }

    // MARK: - Dates

    func testSummaryIsNilWithoutAPeriodEnd() {
        XCTAssertNil(Renewal.periodEndSummary(periodEnd: nil, isFreeTrial: true, locale: en, timeZone: utc))
    }

    /// Localized, not hardcoded — the same regression guard as the offer copy.
    func testDateIsLocalized() {
        let english = Renewal.formattedDate(daysFromNow(5), locale: Locale(identifier: "en_GB"), timeZone: utc)
        let french = Renewal.formattedDate(daysFromNow(5), locale: Locale(identifier: "fr_FR"), timeZone: utc)
        XCTAssertFalse(english.isEmpty)
        XCTAssertNotEqual(english, french, "date text is not being localized")
    }

    /// A renewal date shown in the wrong time zone can be a day out, which is a
    /// small wrongness on a page about money.
    func testDateRespectsTimeZone() {
        let instant = Date(timeIntervalSince1970: 1_700_000_000) // 22:13 UTC
        let utcText = Renewal.formattedDate(instant, locale: en, timeZone: utc)
        let aucklandText = Renewal.formattedDate(
            instant, locale: en, timeZone: TimeZone(identifier: "Pacific/Auckland")!)
        XCTAssertNotEqual(utcText, aucklandText)
    }
}
