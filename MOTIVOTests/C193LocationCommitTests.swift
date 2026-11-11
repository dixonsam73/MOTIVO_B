//
//  C193LocationCommitTests.swift
//  MOTIVOTests
//
//  C-193 — A LOCATION THE PERSON COMMITS IS NOT PUT BACK BY THE BACKGROUND
//  PUBLISH. Sync off: nothing here touches the private sync (the same rule
//  with a sync import and a Connected identity is in
//  `SyncTestConnectedIsolationTests`).
//
//  The location lives under two keys: the identity's and the local Études one.
//  The background snapshot publish prefers the local key and adopts it under
//  the identity's, which is how a location edited while signed out reaches the
//  account. The Profile screen used to write only the identity's key, so the
//  local key kept the older value and the publish, which runs after any
//  validated request, restored it and sent it to the directory. Seen on Device
//  A, 2026-11-11: "Alpha Two" became "Alpha", "Gamma" became "Delta".
//
//  WHAT THIS DOES NOT SHOW: the SwiftUI commit points, the request that
//  triggers the publish, or the directory row. Those are the device run.
//
//  ISOLATION: as C-36 — a fresh random user id per case, its key removed, the
//  shared local key snapshotted raw and restored exactly.
//

import XCTest
@testable import Etudes

final class C193LocationCommitTests: XCTestCase {

    private static let localKey = "profile.__local_etudes_profile__.location"
    private var savedLocal: Any?
    private var uid = ""
    private var scopedKey: String { "profile.\(uid).location" }

    override func setUp() {
        super.setUp()
        savedLocal = UserDefaults.standard.object(forKey: Self.localKey)
        uid = "c193-" + UUID().uuidString
        UserDefaults.standard.removeObject(forKey: scopedKey)
        UserDefaults.standard.removeObject(forKey: Self.localKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: scopedKey)
        if let savedLocal { UserDefaults.standard.set(savedLocal, forKey: Self.localKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.localKey) }
        super.tearDown()
    }

    /// The device case: both keys hold "Delta", the member types "Gamma".
    func testACommittedLocationSurvivesTheBackgroundPublish() {
        ProfileStore.commitLocation("Delta", for: uid)
        ProfileStore.commitLocation("Gamma", for: uid)
        XCTAssertEqual(ProfileStore.locationForBackgroundPublish(for: uid), "Gamma", "the publish sends what was typed")
        XCTAssertEqual(ProfileStore.presentedLocation(for: uid), "Gamma", "and leaves it on the screen")
        XCTAssertEqual(ProfileStore.location(for: nil), "Gamma", "one profile: the local Études location follows")
        // Foreground, reopen, relaunch: every later publish reads the same stores.
        XCTAssertEqual(ProfileStore.locationForBackgroundPublish(for: uid), "Gamma")
        XCTAssertEqual(ProfileStore.presentedLocation(for: uid), "Gamma")
    }

    /// The same defect undid a deliberate clear (C-36's third case, published).
    func testAClearedLocationStaysClearedThroughTheBackgroundPublish() {
        ProfileStore.commitLocation("London", for: uid)
        ProfileStore.commitLocation("", for: uid)
        XCTAssertEqual(ProfileStore.locationForBackgroundPublish(for: uid), "")
        XCTAssertEqual(ProfileStore.presentedLocation(for: uid), "")
        XCTAssertNotNil(UserDefaults.standard.object(forKey: scopedKey), "a clear is a written value, not an absent one")
    }

    /// What the screen did before: the identity's key alone. Kept as the
    /// statement of WHY the commit writes both keys — the publish's preference
    /// for the local key is deliberate (next case) and is not what changed.
    func testWritingOnlyTheIdentityKeyIsWhatLostTheEdit() {
        ProfileStore.commitLocation("Delta", for: uid)
        ProfileStore.setLocation("Gamma", for: uid)
        XCTAssertEqual(ProfileStore.locationForBackgroundPublish(for: uid), "Delta")
        XCTAssertEqual(ProfileStore.presentedLocation(for: uid), "Delta", "the typed value was replaced on screen too")
    }

    /// The reason the publish prefers the local key: an edit made signed out.
    func testALocationEditedWhileSignedOutReachesTheAccountAtSignIn() {
        ProfileStore.commitLocation("Old", for: uid)
        ProfileStore.commitLocation("New", for: nil)          // no identity: the local key only
        XCTAssertEqual(ProfileStore.location(for: uid), "Old")
        XCTAssertEqual(ProfileStore.locationForBackgroundPublish(for: uid), "New")
        XCTAssertEqual(ProfileStore.location(for: uid), "New", "adopted under the identity's key")
    }

    /// First join: the identity's key has never been written.
    func testFirstJoinPublishesTheLocalLocationAndSeedsTheIdentityKey() {
        ProfileStore.commitLocation("London", for: nil)
        XCTAssertNil(UserDefaults.standard.object(forKey: scopedKey))
        XCTAssertEqual(ProfileStore.locationForBackgroundPublish(for: uid), "London")
        XCTAssertEqual(ProfileStore.location(for: uid), "London")
    }

    /// A second device with no local location publishes the account's value.
    func testWithNoLocalLocationTheAccountValueIsPublishedUnchanged() {
        ProfileStore.setLocation("Paris", for: uid)           // what backend hydration writes
        XCTAssertEqual(ProfileStore.locationForBackgroundPublish(for: uid), "Paris")
        XCTAssertEqual(ProfileStore.location(for: nil), "", "hydration is not a commit: the local key is left alone")
    }

    func testACommitWithoutAnIdentityWritesOnlyTheLocalKey() {
        ProfileStore.commitLocation("  Leeds ", for: nil)
        XCTAssertEqual(ProfileStore.location(for: nil), "Leeds")
        XCTAssertNil(UserDefaults.standard.object(forKey: scopedKey))
    }

    /// The Profile screen's one commit point uses the two-key write.
    func testTheProfileScreenCommitsThroughTheTwoKeyWrite() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("MOTIVO/ProfileView.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private func persistProfileEdits() -> Result<Void, Error> {"))
        let body = String(source[start.lowerBound...].prefix(1_200))
        XCTAssertTrue(body.contains("ProfileStore.commitLocation(locationText, for: auth.backendUserID)"))
        XCTAssertFalse(body.contains("ProfileStore.setLocation("), "the identity-only write is what lost the edit")
    }
}
