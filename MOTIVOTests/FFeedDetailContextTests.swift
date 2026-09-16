//
//  FFeedDetailContextTests.swift
//  MOTIVOTests
//
//  UNIT F — THE IDENTITY ROW BELONGS TO THE SURFACE, NOT TO OWNERSHIP.
//
//  Observed on device (build d2f4a15): two of the member's OWN posts, both
//  opened from the Connected Feed, presented differently — one with an identity
//  row and no Edit (it had routed to `BackendSessionDetailView`), one with Edit
//  and no identity row (it had routed to `SessionDetailView`). Which one you got
//  depended on whether a matching local session was in the filtered set, which
//  is invisible to the member and reads as two different products.
//
//  F gives the local path an explicit tap-origin. These cases exercise
//  `SessionDetailView.showsFeedIdentityHeader(origin:canViewFeed:)` — the SAME
//  expression the view body evaluates, not a restatement of it — across the
//  whole origin x live-gate matrix, plus the name sourcing the header depends on.
//
//  WHAT THIS DOES NOT SHOW, and must not be read as showing: rendering. XCTest
//  cannot drive this view's body, so nothing here proves a row appeared, that
//  Edit is still on screen, or that the Journal stayed header-free ON DEVICE.
//  Those are held device QA. The call sites and the retained Edit affordance are
//  established by DIFF REVIEW, recorded in the unit F report.
//
//  THE DEFAULT (`origin` = `.journal`) IS DELIBERATELY NOT SIMULATED HERE.
//  `SessionDetailView.session` is a non-optional Core Data `Session`, so
//  constructing one needs the full model loaded — a harness out of proportion to
//  the claim. The default is carried by the declaration
//  (`var origin: SessionDetailOrigin = .journal`) and by the call sites:
//  `MeView` passes no origin and is unmodified, and all three Journal tap sites
//  now assign `.journal` EXPLICITLY rather than relying on a dismissal to reset
//  it. Reviewed in the diff, not faked here.
//
//  PURE: no network, no Keychain, no defaults, no Core Data, no identity.
//

import XCTest
@testable import Etudes

final class FFeedDetailContextTests: XCTestCase {

    private func shows(_ origin: SessionDetailOrigin, canViewFeed: Bool) -> Bool {
        SessionDetailView.showsFeedIdentityHeader(origin: origin, canViewFeed: canViewFeed)
    }

    // MARK: - The rendering rule: origin x live Connected gate

    /// The reported inconsistency, as an assertion: a local post opened from the
    /// Connected Feed gets the identity row, exactly as a remote one already did.
    func testConnectedFeedOriginShowsTheHeader() {
        XCTAssertTrue(shows(.connectedFeed, canViewFeed: true))
    }

    /// C-71 preserved: the Journal is the member's own local sessions, so it
    /// stays header-free even with Connected fully active.
    func testJournalOriginStaysHeaderFreeWhileConnected() {
        XCTAssertFalse(shows(.journal, canViewFeed: true))
    }

    /// The live half of the gate. If Connected ends while the screen is open the
    /// row must go with it, rather than stranding an identity on a Solo surface.
    func testConnectedFeedOriginHidesTheHeaderWhenTheFeedIsNotAvailable() {
        XCTAssertFalse(shows(.connectedFeed, canViewFeed: false))
    }

    func testJournalOriginInSoloShowsNothing() {
        XCTAssertFalse(shows(.journal, canViewFeed: false))
    }

    /// Both terms are load-bearing: neither alone decides the row. Stated as a
    /// property so a future change that drops one fails here.
    func testTheHeaderRequiresBOTHTheFeedOriginAndTheLiveGate() {
        let matrix: [(SessionDetailOrigin, Bool, Bool)] = [
            (.connectedFeed, true,  true),
            (.connectedFeed, false, false),
            (.journal,       true,  false),
            (.journal,       false, false)
        ]
        for (origin, gate, expected) in matrix {
            XCTAssertEqual(shows(origin, canViewFeed: gate), expected,
                           "origin=\(origin) canViewFeed=\(gate)")
        }
    }

    // MARK: - Name sourcing the header depends on

    /// F's header shares N's precedence rather than duplicating it, so the
    /// Feed's two detail screens cannot drift apart. For the owner it passes the
    /// local `Profile.name` — the value the Feed CARD shows — as the fallback,
    /// so an owner whose directory row has not resolved sees the same name on
    /// the card and in the detail instead of "You".
    func testOwnerHeaderFallsBackToTheNameTheFeedCardShows() {
        XCTAssertEqual(
            BackendSessionDetailView.resolvedDisplayName(viewerIsOwner: true,
                                                         directoryName: nil,
                                                         authName: "DeviceA release"),
            "DeviceA release")
    }

    /// The control Codex asked for: a local row belonging to someone else must
    /// never borrow this device's profile name. The header passes a local name
    /// ONLY when `viewerIsOwner`, and the precedence refuses it regardless.
    func testNonOwnerHeaderNeverShowsTheViewersOwnLocalName() {
        XCTAssertEqual(
            BackendSessionDetailView.resolvedDisplayName(viewerIsOwner: false,
                                                         directoryName: nil,
                                                         authName: "Sam Dixon"),
            "User")
    }
}
