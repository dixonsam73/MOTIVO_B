//
//  WideWindowLayoutTests.swift
//  MOTIVOTests
//
//  The iPad adaptations are decided by the space a window has, never by the
//  kind of device, and must leave a phone-sized space exactly as it was. The
//  rule for "has room to spare" is one pure function; this pins what it
//  says for the sizes that matter.
//

import XCTest
@testable import Etudes

final class WideWindowLayoutTests: XCTestCase {

    func testAnIPhoneIsNeverRoomyInEitherOrientation() {
        // iPhone 16e, 17, 17 Pro, 17 Pro Max: portrait and landscape.
        for (w, h) in [(390.0, 844.0), (393.0, 852.0), (402.0, 874.0), (440.0, 956.0)] {
            XCTAssertFalse(WideWindow.isRoomy(CGSize(width: w, height: h)), "\(w)x\(h)")
            XCTAssertFalse(WideWindow.isRoomy(CGSize(width: h, height: w)), "\(h)x\(w): wide, but not tall")
        }
    }

    func testAnIPadWindowWithRoomIsRoomyAndANarrowOneIsNot() {
        // 11-inch and 13-inch, both ways round.
        for (w, h) in [(834.0, 1210.0), (1210.0, 834.0), (1032.0, 1376.0), (1376.0, 1032.0)] {
            XCTAssertTrue(WideWindow.isRoomy(CGSize(width: w, height: h)), "\(w)x\(h)")
        }
        // A narrow iPad window is a phone-sized space and is treated as one.
        XCTAssertFalse(WideWindow.isRoomy(CGSize(width: 375, height: 800)))
        // So is a wide, shallow one.
        XCTAssertFalse(WideWindow.isRoomy(CGSize(width: 1000, height: 420)))
    }

    func testTheColumnLeavesAMarginOnAnElevenInchIPadInPortrait() {
        XCTAssertLessThan(WideWindow.columnWidth, 834)
        XCTAssertGreaterThan(WideWindow.columnWidth, 440, "wider than any iPhone, so a phone's page is never narrowed")
    }
}
