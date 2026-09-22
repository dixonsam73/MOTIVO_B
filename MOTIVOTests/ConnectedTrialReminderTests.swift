//
//  ConnectedTrialReminderTests.swift
//  MOTIVOTests
//
//  FOUNDING 500 — when the in-feed reminder appears, and when it must not.
//

import XCTest
@testable import Etudes

private typealias Reminder = ConnectedTrialReminder

final class ConnectedTrialReminderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let trial = "2000001234567890-1731536000"
    private let otherTrial = "2000009999999999-1763072000"

    private func daysFromNow(_ days: Double) -> Date {
        now.addingTimeInterval(days * 24 * 60 * 60)
    }

    private func isolatedDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        UserDefaults(suiteName: name)!
    }

    // MARK: - When it shows

    func testShowsInsideTheFinalWindow() {
        XCTAssertTrue(Reminder.shouldShow(
            trialIdentity: trial, periodEnd: daysFromNow(10),
            dismissedIdentities: [], now: now))
    }

    func testDoesNotShowLongBeforeTheEnd() {
        XCTAssertFalse(Reminder.shouldShow(
            trialIdentity: trial, periodEnd: daysFromNow(200),
            dismissedIdentities: [], now: now))
    }

    /// An elapsed date describes access that has already ended.
    func testDoesNotShowAfterTheEnd() {
        XCTAssertFalse(Reminder.shouldShow(
            trialIdentity: trial, periodEnd: daysFromNow(-1),
            dismissedIdentities: [], now: now))
    }

    /// The store sets an identity only inside a free trial, so its absence means
    /// there is no trial to warn about — a paid period must not show this card.
    func testDoesNotShowWithoutATrialIdentity() {
        XCTAssertFalse(Reminder.shouldShow(
            trialIdentity: nil, periodEnd: daysFromNow(10),
            dismissedIdentities: [], now: now))
        XCTAssertFalse(Reminder.shouldShow(
            trialIdentity: "", periodEnd: daysFromNow(10),
            dismissedIdentities: [], now: now))
    }

    func testDoesNotShowWithoutAPeriodEnd() {
        XCTAssertFalse(Reminder.shouldShow(
            trialIdentity: trial, periodEnd: nil,
            dismissedIdentities: [], now: now))
    }

    // MARK: - Dismissal

    func testDismissedTrialDoesNotShow() {
        XCTAssertFalse(Reminder.shouldShow(
            trialIdentity: trial, periodEnd: daysFromNow(10),
            dismissedIdentities: [trial], now: now))
    }

    /// **The one that matters.** Dismissing one trial must not silence a later,
    /// different one — somebody resubscribing a year on would otherwise never be
    /// warned.
    func testDismissalDoesNotCarryToADifferentTrial() {
        XCTAssertTrue(Reminder.shouldShow(
            trialIdentity: otherTrial, periodEnd: daysFromNow(10),
            dismissedIdentities: [trial], now: now))
    }

    // MARK: - Persistence

    func testDismissalPersists() {
        let defaults = isolatedDefaults()
        XCTAssertTrue(Reminder.dismissedIdentities(defaults: defaults).isEmpty)
        Reminder.recordDismissal(trialIdentity: trial, defaults: defaults)
        XCTAssertEqual(Reminder.dismissedIdentities(defaults: defaults), [trial])
    }

    func testDismissalIsIdempotent() {
        let defaults = isolatedDefaults()
        Reminder.recordDismissal(trialIdentity: trial, defaults: defaults)
        Reminder.recordDismissal(trialIdentity: trial, defaults: defaults)
        XCTAssertEqual(Reminder.dismissedIdentities(defaults: defaults), [trial])
    }

    func testEmptyIdentityIsNotRecorded() {
        let defaults = isolatedDefaults()
        Reminder.recordDismissal(trialIdentity: "", defaults: defaults)
        XCTAssertTrue(Reminder.dismissedIdentities(defaults: defaults).isEmpty)
    }

    /// Bounded, so repeated resubscription cannot grow a preference forever.
    /// The most recent are the ones that can still matter.
    func testDismissalListIsBoundedKeepingTheMostRecent() {
        let defaults = isolatedDefaults()
        for index in 0..<12 {
            Reminder.recordDismissal(trialIdentity: "trial-\(index)", defaults: defaults)
        }
        let stored = Reminder.dismissedIdentities(defaults: defaults)
        XCTAssertEqual(stored.count, 8)
        XCTAssertEqual(stored.last, "trial-11")
        XCTAssertFalse(stored.contains("trial-0"))
    }

    // MARK: - Wording

    /// Shares the Profile rules: neutral about renewal, and no plan change
    /// offered as a way to avoid payment.
    func testMessageNeverClaimsRenewalOrOffersAPlanChange() {
        let text = Reminder.message(
            periodEnd: daysFromNow(5),
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(identifier: "UTC")!).lowercased()
        XCTAssertFalse(text.contains("renews"))
        XCTAssertFalse(text.contains("change plan"))
        XCTAssertTrue(text.contains("standard price"))
    }

    /// **Q10's regression, as an assertion.** The card must not instruct a member
    /// to cancel — one who already has is then told their cancellation did not
    /// take. **"still active" is forbidden too**: a cancelled trial remains
    /// active until it expires.
    ///
    /// This test previously asserted `contains("unless you cancel")` and so
    /// locked in the defect it now guards against.
    func testMessageStatesTheRenewalConditionRatherThanInstructingCancellation() {
        let text = Reminder.message(
            periodEnd: daysFromNow(5),
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(identifier: "UTC")!).lowercased()
        XCTAssertTrue(text.contains("automatic renewal"))
        XCTAssertFalse(text.contains("unless you cancel"))
        XCTAssertFalse(text.contains("still active"))
    }

    /// **The identity is set for a free trial of ANY length**, so the copy must
    /// not name a duration the offer may not have. The Founding 500 offer being
    /// a year does not make every trial one.
    func testMessageDoesNotHardcodeAYear() {
        let text = Reminder.message(
            periodEnd: daysFromNow(5),
            locale: Locale(identifier: "en_GB"),
            timeZone: TimeZone(identifier: "UTC")!).lowercased()
        XCTAssertFalse(text.contains("free year"))
        XCTAssertTrue(text.contains("free trial"))
        XCTAssertFalse(Reminder.title.lowercased().contains("year"))
    }

    /// The failure notice must send the member somewhere that can actually help.
    func testManageFailureMessagePointsAtAppleSubscriptions() {
        let message = Reminder.manageFailureMessage.lowercased()
        XCTAssertTrue(message.contains("settings"))
        XCTAssertTrue(message.contains("subscriptions"))
    }

    /// The window must agree with Profile's, or the two notices would disagree
    /// about when "near expiry" begins.
    func testWindowMatchesTheProfileNotice() {
        XCTAssertEqual(Reminder.noticeWindow, ConnectedRenewalPresentation.noticeWindow)
    }
}
