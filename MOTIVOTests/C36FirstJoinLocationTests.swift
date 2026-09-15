//
//  C36FirstJoinLocationTests.swift
//  MOTIVOTests
//
//  C-36 — THE LOCATION A CONNECTED PROFILE PRESENTS WHEN ITS USER-SCOPED VALUE
//  HAS NEVER BEEN WRITTEN.
//
//  `ProfileView` presents the location through one read. When the identity's
//  scoped key `profile.<uid>.location` has never been written — a first join,
//  before any writer has run — that read must fall back to the member's local
//  Études location instead of presenting a blank, because a blank is synced to
//  the directory as NULL. An existing scoped value, including an explicit ""
//  (a deliberate clear), must still win.
//
//  WHAT THIS DOES NOT SHOW: the SwiftUI observer → debounced sync → network
//  ordering, the backend row, or that every first join loses the location. That
//  is device QA B7.
//
//  ISOLATION: each case uses a fresh random user id and removes its own key; the
//  shared local-scope key is snapshotted raw and restored exactly. UserDefaults
//  is the process-wide store of the disposable hosted test process.
//

import XCTest
@testable import Etudes

final class C36FirstJoinLocationTests: XCTestCase {

    private static let localKey = "profile.__local_etudes_profile__.location"

    private var savedLocal: Any?
    private var uid = ""

    /// The read under test — the value `ProfileView` presents for a user id.
    /// Before the fix this shim called `ProfileStore.location(for:)`, the view's
    /// read at the time; both `ProfileView` sites now call this helper.
    private func presented(for userID: String?) -> String {
        ProfileStore.presentedLocation(for: userID)
    }

    override func setUp() {
        super.setUp()
        savedLocal = UserDefaults.standard.object(forKey: Self.localKey)
        uid = "c36-" + UUID().uuidString
        UserDefaults.standard.removeObject(forKey: "profile.\(uid).location")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "profile.\(uid).location")
        if let savedLocal {
            UserDefaults.standard.set(savedLocal, forKey: Self.localKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.localKey)
        }
        super.tearDown()
    }

    /// 1 — first join: the scoped key has never been written.
    func testFirstJoinPresentsTheLocalLocation() {
        ProfileStore.setLocation("London", for: nil)
        XCTAssertNil(UserDefaults.standard.object(forKey: "profile.\(uid).location"))
        XCTAssertEqual(presented(for: uid), "London",
                       "with no scoped value yet, the member's local location must be presented, not a blank that syncs as NULL")
    }

    /// 2 — an existing scoped value wins over the local one.
    func testExistingScopedLocationWins() {
        ProfileStore.setLocation("London", for: nil)
        ProfileStore.setLocation("Paris", for: uid)
        XCTAssertEqual(presented(for: uid), "Paris")
    }

    /// 3 — a deliberate clear (explicit "") stays cleared.
    func testDeliberatelyClearedLocationStaysCleared() {
        ProfileStore.setLocation("London", for: nil)
        ProfileStore.setLocation("", for: uid)
        XCTAssertNotNil(UserDefaults.standard.object(forKey: "profile.\(uid).location"))
        XCTAssertEqual(presented(for: uid), "")
    }

    /// 4 — nothing set anywhere presents nothing.
    func testNothingSetPresentsBlank() {
        UserDefaults.standard.removeObject(forKey: Self.localKey)
        XCTAssertEqual(presented(for: uid), "")
    }
}
