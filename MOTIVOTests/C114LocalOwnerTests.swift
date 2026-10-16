//
//  C114LocalOwnerTests.swift
//  MOTIVOTests
//
//  C-114 — the pure rules around the kept local owner. The withdrawal itself is
//  driven against the real `AuthManager` in `C27SignOutLocationTests`.
//

import XCTest
@testable import Etudes

final class C114LocalOwnerTests: XCTestCase {

    func testSameAppleAccountIsNeverRefused() {
        XCTAssertFalse(AuthManager.refusesSignIn(storedOwner: "A", incoming: "A", storedOwnerHasLocalJournal: true))
    }

    func testNoKeptOwnerIsNeverRefused() {
        XCTAssertFalse(AuthManager.refusesSignIn(storedOwner: nil, incoming: "B", storedOwnerHasLocalJournal: true))
        XCTAssertFalse(AuthManager.refusesSignIn(storedOwner: "  ", incoming: "B", storedOwnerHasLocalJournal: true))
    }

    func testAnotherAccountIsRefusedWhileTheJournalIsHere() {
        XCTAssertTrue(AuthManager.refusesSignIn(storedOwner: "A", incoming: "B", storedOwnerHasLocalJournal: true))
    }

    /// After a reinstall the Keychain outlives the app's data: nothing to protect.
    func testAnotherAccountMaySignInWhenTheKeptOwnerHasNoJournal() {
        XCTAssertFalse(AuthManager.refusesSignIn(storedOwner: "A", incoming: "B", storedOwnerHasLocalJournal: false))
    }

    func testCredentialMonitorActsOnlyWithASessionToWithdraw() {
        XCTAssertFalse(AppleCredentialStateMonitor.hasConnectedSessionToWithdraw(hasAccessToken: false, backendUserID: nil))
        XCTAssertFalse(AppleCredentialStateMonitor.hasConnectedSessionToWithdraw(hasAccessToken: false, backendUserID: " "))
        XCTAssertTrue(AppleCredentialStateMonitor.hasConnectedSessionToWithdraw(hasAccessToken: true, backendUserID: nil))
        XCTAssertTrue(AppleCredentialStateMonitor.hasConnectedSessionToWithdraw(hasAccessToken: false, backendUserID: "u"))
    }
}
