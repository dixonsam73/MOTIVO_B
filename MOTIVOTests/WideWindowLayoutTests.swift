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

    // MARK: The Timer page

    func testTheTimerIsSideBySideOnlyInARoomyLandscapeWindow() {
        // 11-inch and 13-inch iPad in landscape.
        XCTAssertTrue(TimerPageArrangement.isSideBySide(CGSize(width: 1210, height: 790), roomy: true))
        XCTAssertTrue(TimerPageArrangement.isSideBySide(CGSize(width: 1376, height: 990), roomy: true))
        // Portrait: one column.
        XCTAssertFalse(TimerPageArrangement.isSideBySide(CGSize(width: 834, height: 1150), roomy: true))
        // A landscape window too narrow for two parts.
        XCTAssertFalse(TimerPageArrangement.isSideBySide(CGSize(width: 900, height: 700), roomy: true))
        // An iPhone on its side is wide, but it is never roomy.
        XCTAssertFalse(TimerPageArrangement.isSideBySide(CGSize(width: 956, height: 440), roomy: false))
        XCTAssertFalse(TimerPageArrangement.isSideBySide(CGSize(width: 1210, height: 790), roomy: false))
    }

    /// The audio recorder holds the take in its own view. Moving it between
    /// the column and the side panel would end the take, so while a take
    /// exists the arrangement it began in is the one shown.
    func testATakeHoldsTheArrangementItBeganIn() {
        // Begun in landscape, iPad turned to portrait: still side by side.
        XCTAssertTrue(TimerPageArrangement.sideBySide(fits: false, heldByRecorder: true))
        // Begun in portrait, iPad turned to landscape: still one column.
        XCTAssertFalse(TimerPageArrangement.sideBySide(fits: true, heldByRecorder: false))
        // No take: whatever the window fits.
        XCTAssertTrue(TimerPageArrangement.sideBySide(fits: true, heldByRecorder: nil))
        XCTAssertFalse(TimerPageArrangement.sideBySide(fits: false, heldByRecorder: nil))
    }

    func testTheTimerColumnLeavesRoomForThePanelAndNeverTakesMoreThanHalf() {
        for window in [1210.0, 1376.0] {
            let column = TimerPageArrangement.columnRegionWidth(window: window)
            XCTAssertGreaterThanOrEqual(column, 440)
            XCTAssertGreaterThanOrEqual(window - column, 600, "an opened section keeps a comfortable width at \(window)")
        }
        // A held arrangement in a window since turned or narrowed.
        for window in [834.0, 400.0] {
            XCTAssertLessThanOrEqual(TimerPageArrangement.columnRegionWidth(window: window), window / 2)
        }
    }

    /// Pins the one thing the arrangement must never do: build the recorder
    /// in a place that depends only on the window's shape.
    func testTheTimerPageHoldsItsArrangementWhileTheRecorderHoldsATake() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("MOTIVO/PracticeTimerView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("TimerPageArrangement.sideBySide(fits: fitsSideBySide, heldByRecorder: arrangementHeldByRecorder)"))
        XCTAssertTrue(source.contains("arrangementHeldByRecorder = holdsTake ? sideBySide : nil"))
        // The recorder says so itself, from the first moment a take has a file.
        let recorder = try String(contentsOf: root.appendingPathComponent("MOTIVO/AudioRecorderView.swift"), encoding: .utf8)
        XCTAssertTrue(recorder.contains(".preference(key: AudioRecorderHoldsTakeKey.self, value: recordingURL != nil)"))
        XCTAssertEqual(source.components(separatedBy: "TimerPageArrangement.isSideBySide(").count - 1, 1,
                       "the window's shape is read in one place, and only through the held arrangement")
    }
}
