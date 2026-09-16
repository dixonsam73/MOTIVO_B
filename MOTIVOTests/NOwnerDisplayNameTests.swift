//
//  NOwnerDisplayNameTests.swift
//  MOTIVOTests
//
//  UNIT N — THE CONNECTED FEED DETAIL SHOWS THE OWNER'S PUBLISHED ÉTUDES NAME.
//
//  Observed on device (build d2f4a15): the Feed card read "DeviceA release"
//  while the SAME post's opened detail read "Sam Dixon". The card reads Core
//  Data `Profile.name`; the detail preferred `auth.displayName`, which Apple
//  supplies only at the FIRST authorization, which lives in the Keychain, and
//  which `ProfileView.save()` cannot reach — so renaming in Profile could never
//  change it, and the old name persisted across relaunches.
//
//  The rule these cases pin: the member's PUBLISHED identity
//  (`account_directory.display_name`) wins. It is the name they chose, and the
//  name every other member already sees on this very screen. The Apple name is
//  kept as a FALLBACK, not removed, so an owner whose directory row has not
//  resolved yet still sees a name instead of "You".
//
//  WHAT THIS DOES NOT SHOW: device behaviour, the identity header's layout, the
//  avatar (scope A, separate and open), or which screen a Feed tap opens
//  (scope F). It tests the precedence only.
//
//  PURE: no network, no Keychain, no defaults, no Core Data, no identity. The
//  function under test takes its three inputs as parameters, so nothing is
//  snapshotted and nothing needs restoring.
//

import XCTest
@testable import Etudes

final class NOwnerDisplayNameTests: XCTestCase {

    private func resolved(owner: Bool, directory: String?, auth: String?) -> String {
        BackendSessionDetailView.resolvedDisplayName(viewerIsOwner: owner,
                                                     directoryName: directory,
                                                     authName: auth)
    }

    // MARK: - Owner: the published name wins

    /// The reported defect, as an assertion. Divergent names, owner viewing
    /// their own post: the published name is shown, NOT the retained Apple one.
    func testOwnerDivergentNamesPrefersPublishedDirectoryName() {
        XCTAssertEqual(resolved(owner: true, directory: "DeviceA release", auth: "Sam Dixon"),
                       "DeviceA release",
                       "the owner's published display_name must outrank a retained Apple credential name")
    }

    /// Order is not an accident of the inputs: swapping which side holds which
    /// name still yields the directory's value.
    func testOwnerPrecedenceIsDirectoryRegardlessOfWhichNameIsWhere() {
        XCTAssertEqual(resolved(owner: true, directory: "Sam Dixon", auth: "DeviceA release"),
                       "Sam Dixon")
    }

    // MARK: - Owner: fallbacks are retained

    func testOwnerFallsBackToAuthNameWhenDirectoryIsAbsent() {
        XCTAssertEqual(resolved(owner: true, directory: nil, auth: "Sam Dixon"), "Sam Dixon")
    }

    func testOwnerFallsBackToAuthNameWhenDirectoryIsEmpty() {
        XCTAssertEqual(resolved(owner: true, directory: "", auth: "Sam Dixon"), "Sam Dixon")
    }

    /// A blank is a blank however it is spelled: whitespace must not win over a
    /// real fallback, or the header would render an empty name.
    func testOwnerTreatsWhitespaceOnlyDirectoryAsAbsent() {
        XCTAssertEqual(resolved(owner: true, directory: "   \n ", auth: "Sam Dixon"), "Sam Dixon")
    }

    func testOwnerWithNothingResolvableSaysYou() {
        XCTAssertEqual(resolved(owner: true, directory: nil, auth: nil), "You")
        XCTAssertEqual(resolved(owner: true, directory: "", auth: "  "), "You")
    }

    // MARK: - Non-owner controls: unchanged by this unit

    func testNonOwnerUsesDirectoryName() {
        XCTAssertEqual(resolved(owner: false, directory: "DeviceB release", auth: nil),
                       "DeviceB release")
    }

    func testNonOwnerWithoutDirectorySaysUser() {
        XCTAssertEqual(resolved(owner: false, directory: nil, auth: nil), "User")
        XCTAssertEqual(resolved(owner: false, directory: "  ", auth: nil), "User")
    }

    /// The owner's fallbacks must never leak into another member's row: an
    /// unresolved stranger is "User", and NEVER this device's Apple name.
    func testNonOwnerNeverShowsTheViewersOwnAuthName() {
        XCTAssertEqual(resolved(owner: false, directory: nil, auth: "Sam Dixon"), "User",
                       "a viewer's own Apple name must never be attributed to another member")
        XCTAssertEqual(resolved(owner: false, directory: "", auth: "Sam Dixon"), "User")
    }
}
