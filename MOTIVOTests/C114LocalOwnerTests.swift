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

    // MARK: - Sign-in sheet suppression (Codex finding 2)

    func testCancelledOrRefusedSignInClearsTheSuppressionWhileTheOwnerIsKept() {
        XCTAssertTrue(ProfileView.gateSuppressionClearsOnDismiss(currentUserID: "A", completionsAtAppear: 3, completionsNow: 3))
    }

    func testCompletedSignInKeepsTheSuppression() {
        XCTAssertFalse(ProfileView.gateSuppressionClearsOnDismiss(currentUserID: "A", completionsAtAppear: 3, completionsNow: 4))
    }

    func testNoOwnerAlwaysClearsTheSuppression() {
        XCTAssertTrue(ProfileView.gateSuppressionClearsOnDismiss(currentUserID: nil, completionsAtAppear: 3, completionsNow: 4))
    }

    // MARK: - List ownership (Codex finding 1). Isolated suites, synthetic owners.

    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        suites = []
        super.tearDown()
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "C114Lists." + UUID().uuidString
        suites.append(suite)
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    private func legacyKey(_ owner: String) -> String { "practiceTasks_v1::" + owner + "::core:0::saved_sets_v1" }
    private func list(_ name: String) -> SavedList { SavedList(id: UUID(), name: name, items: [SavedListLine(text: "x")]) }

    @MainActor
    func testNoListsAnywhereIsNoContent() throws {
        let defaults = try makeDefaults()
        XCTAssertFalse(SavedListLibrary.hasContent(ownerScope: "c114-" + UUID().uuidString, defaults: defaults))
    }

    @MainActor
    func testUnmigratedLegacyListCountsAsContent() throws {
        let defaults = try makeDefaults()
        let owner = "c114-" + UUID().uuidString
        defaults.set(try JSONEncoder().encode([list("Scales")]), forKey: legacyKey(owner))
        XCTAssertTrue(SavedListLibrary.hasContent(ownerScope: owner, defaults: defaults))
        XCTAssertEqual(SavedListLibrary.stored(ownerScope: owner, defaults: defaults), .absent, "the check must not migrate")
    }

    @MainActor
    func testUnreadableLegacyValueCountsAsContent() throws {
        let defaults = try makeDefaults()
        let owner = "c114-" + UUID().uuidString
        defaults.set(Data("not json".utf8), forKey: legacyKey(owner))
        XCTAssertTrue(SavedListLibrary.hasContent(ownerScope: owner, defaults: defaults))
    }

    @MainActor
    func testEmptyLegacyArrayIsNoContent() throws {
        let defaults = try makeDefaults()
        let owner = "c114-" + UUID().uuidString
        defaults.set(try JSONEncoder().encode([SavedList]()), forKey: legacyKey(owner))
        XCTAssertFalse(SavedListLibrary.hasContent(ownerScope: owner, defaults: defaults))
    }

    /// Once migrated, a legacy copy of a List the person deleted must not count.
    @MainActor
    func testAfterMigrationOnlyTheCanonicalLibraryCounts() throws {
        let defaults = try makeDefaults()
        let owner = "c114-" + UUID().uuidString
        let scales = list("Scales")
        defaults.set(try JSONEncoder().encode([scales]), forKey: legacyKey(owner))
        guard case .lists(let migrated) = SavedListLibrary.load(ownerScope: owner, defaults: defaults) else {
            return XCTFail("library unexpectedly damaged")
        }
        XCTAssertTrue(SavedListLibrary.hasContent(ownerScope: owner, defaults: defaults))
        try SavedListLibrary.commit(snapshot: migrated, updated: [], ownerScope: owner, defaults: defaults)
        XCTAssertNotNil(defaults.data(forKey: legacyKey(owner)), "legacy keys are left in place")
        XCTAssertFalse(SavedListLibrary.hasContent(ownerScope: owner, defaults: defaults))
    }

    func testCredentialMonitorActsOnlyWithASessionToWithdraw() {
        XCTAssertFalse(AppleCredentialStateMonitor.hasConnectedSessionToWithdraw(hasAccessToken: false, backendUserID: nil))
        XCTAssertFalse(AppleCredentialStateMonitor.hasConnectedSessionToWithdraw(hasAccessToken: false, backendUserID: " "))
        XCTAssertTrue(AppleCredentialStateMonitor.hasConnectedSessionToWithdraw(hasAccessToken: true, backendUserID: nil))
        XCTAssertTrue(AppleCredentialStateMonitor.hasConnectedSessionToWithdraw(hasAccessToken: false, backendUserID: "u"))
    }
}
