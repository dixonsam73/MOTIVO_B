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

    func testTheTimerIsSideBySideInARoomyWindowEitherWayUp() {
        // 11-inch and 13-inch iPad, landscape and portrait: the same
        // arrangement, so turning the iPad moves nothing.
        for (w, h) in [(1210.0, 790.0), (834.0, 1166.0), (1376.0, 990.0), (1032.0, 1332.0), (820.0, 1136.0)] {
            XCTAssertTrue(TimerPageArrangement.isSideBySide(CGSize(width: w, height: h), roomy: true), "\(w)x\(h)")
        }
        // An iPad mini in portrait, or a window made narrow: one column.
        XCTAssertFalse(TimerPageArrangement.isSideBySide(CGSize(width: 744, height: 1089), roomy: true))
        XCTAssertFalse(TimerPageArrangement.isSideBySide(CGSize(width: 600, height: 700), roomy: true))
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
        // Portrait, down to the narrowest window that is side by side: each
        // half holds the row of three timer buttons (about 360 pt, inside
        // 16 pt margins) and a card about as wide as a phone's.
        for window in [834.0, 820.0, TimerPageArrangement.sideBySideMinimumWidth] {
            let column = TimerPageArrangement.columnRegionWidth(window: window)
            XCTAssertGreaterThanOrEqual(column - 32, 360, "the timer's buttons fit at \(window)")
            XCTAssertGreaterThanOrEqual(window - column - 16, 380, "a card fits at \(window)")
        }
        // A held arrangement in a window since made narrow.
        XCTAssertLessThanOrEqual(TimerPageArrangement.columnRegionWidth(window: 400), 200)
    }

    func testTheButtonsSitInTheMiddleOfATallPageAndStayPutOnAShortOne() {
        // 11-inch iPad in landscape (834 less the status bar): already
        // centred, nothing added.
        XCTAssertEqual(TimerPageArrangement.centringInset(windowHeight: 810), 0)
        // 11-inch and 13-inch in portrait: half the spare height goes above.
        XCTAssertEqual(TimerPageArrangement.centringInset(windowHeight: 1186), 173)
        XCTAssertGreaterThan(TimerPageArrangement.centringInset(windowHeight: 1352),
                             TimerPageArrangement.centringInset(windowHeight: 1186))
    }

    func testTheCardsStartLevelWithTheButtonsInLandscapeAndHigherInPortrait() {
        // Landscape, 11-inch: nothing is added, the cards are level with
        // the first button, as Samuel signed off.
        let landscape11 = TimerPageArrangement.panelTopInset(pageHeight: 790, windowHeight: 810, landscape: true)
        XCTAssertEqual(landscape11, 790 * 0.024 + 95, accuracy: 0.001)
        // Landscape, 13-inch: the buttons sit lower, and the cards with them.
        XCTAssertEqual(TimerPageArrangement.panelTopInset(pageHeight: 988, windowHeight: 1008, landscape: true),
                       988 * 0.024 + 95 + TimerPageArrangement.centringInset(windowHeight: 1008), accuracy: 0.001)
        // Portrait: the buttons are in the middle of the page, the cards
        // are not held down with them.
        XCTAssertEqual(TimerPageArrangement.panelTopInset(pageHeight: 1166, windowHeight: 1186, landscape: false),
                       1166 * 0.024 + 95, accuracy: 0.001)
        // The keyboard coming up in portrait is not a turn to landscape.
        XCTAssertFalse(TimerPageArrangement.isLandscape(width: 834, windowHeight: 1186))
        XCTAssertTrue(TimerPageArrangement.isLandscape(width: 1210, windowHeight: 810))
    }

    /// The keyboard must not move the buttons: the centring is worked out
    /// from the height down to the window's bottom edge, which the page
    /// passes as its own height plus the bottom inset (the keyboard, when up).
    func testTheCentringIsWorkedOutFromTheWindowNotTheSpaceAboveTheKeyboard() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("MOTIVO/PracticeTimerView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("TimerPageArrangement.centringInset(windowHeight: proxy.size.height + proxy.safeAreaInsets.bottom)"))
        XCTAssertFalse(source.contains("centringInset(windowHeight: proxy.size.height)"))
    }

    func testAListMenuIgnoresTheKeyboardOnlyInARoomyWindow() {
        XCTAssertEqual(TaskLineMenuKeyboard.regions(horizontal: .regular, vertical: .regular), .keyboard)
        XCTAssertEqual(TaskLineMenuKeyboard.regions(horizontal: .compact, vertical: .regular), [])
        XCTAssertEqual(TaskLineMenuKeyboard.regions(horizontal: .regular, vertical: .compact), [])
        XCTAssertEqual(TaskLineMenuKeyboard.regions(horizontal: nil, vertical: nil), [])
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
