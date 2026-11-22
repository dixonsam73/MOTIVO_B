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

    func testTheCardsStartLevelWithTheButtonsWhicheverWayUp() {
        // 11-inch landscape: nothing is added. Portrait and 13-inch
        // landscape: the buttons sit lower, and the cards with them.
        XCTAssertEqual(TimerPageArrangement.panelTopInset(pageHeight: 790, windowHeight: 810), 790 * 0.024 + 95, accuracy: 0.001)
        XCTAssertEqual(TimerPageArrangement.panelTopInset(pageHeight: 1166, windowHeight: 1186),
                       1166 * 0.024 + 95 + 173, accuracy: 0.001)
        XCTAssertEqual(TimerPageArrangement.panelTopInset(pageHeight: 988, windowHeight: 1008),
                       988 * 0.024 + 95 + TimerPageArrangement.centringInset(windowHeight: 1008), accuracy: 0.001)
        // The keyboard coming up in portrait is not a turn to landscape.
        XCTAssertFalse(TimerPageArrangement.isLandscape(width: 834, windowHeight: 1186))
        XCTAssertTrue(TimerPageArrangement.isLandscape(width: 1210, windowHeight: 810))
    }

    func testTheListGoesBesideTheButtonsInLandscapeAndBeneathBothColumnsInPortrait() {
        XCTAssertEqual(TimerPageArrangement.listPlace(sideBySide: true, landscape: true), .panel)
        XCTAssertEqual(TimerPageArrangement.listPlace(sideBySide: true, landscape: false), .beneath)
        // A single column has no panel and no area beneath, whichever way up.
        XCTAssertEqual(TimerPageArrangement.listPlace(sideBySide: false, landscape: true), .column)
        XCTAssertEqual(TimerPageArrangement.listPlace(sideBySide: false, landscape: false), .column)
    }

    func testTheListStartsStraightUnderTheButtonsAndKeepsItsMinimumAboveTheKeyboard() {
        // Portrait, no keyboard: the columns are as tall as the buttons need.
        XCTAssertEqual(TimerPageArrangement.columnsHeight(columnContent: 800, pageHeight: 1102), 800)
        // Keyboard up: the columns give way, the list keeps its minimum.
        XCTAssertEqual(TimerPageArrangement.columnsHeight(columnContent: 800, pageHeight: 700),
                       700 - TimerPageArrangement.minimumListHeight)
        // Not measured yet: no height is imposed.
        XCTAssertNil(TimerPageArrangement.columnsHeight(columnContent: 0, pageHeight: 1102))
    }

    /// The keyboard must not move the buttons: the centring is worked out
    /// from the height down to the window's bottom edge, which the page
    /// passes as its own height plus the bottom inset (the keyboard, when up).
    func testTheCentringIsWorkedOutFromTheWindowNotTheSpaceAboveTheKeyboard() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("MOTIVO/PracticeTimerView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("let windowHeight = proxy.size.height + proxy.safeAreaInsets.bottom"))
        XCTAssertTrue(source.contains("TimerPageArrangement.centringInset(windowHeight: windowHeight)"))
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

    // MARK: - The system's window controls

    /// In an iPad window that is not full screen the system's window
    /// controls sit on the top leading corner. A bar the app draws moves
    /// its first button clear of them, and does nothing where there are
    /// none (a full-screen window, an iPhone).
    func testABarMovesClearOfTheWindowControlsOnlyWhereThereAreSome() {
        XCTAssertEqual(WindowControls.extraLeading(controls: 0, existing: 16), 0)
        // 66 pt of controls (measured on the 11-inch iPad simulator), a gap,
        // less the padding the bar already has.
        XCTAssertEqual(WindowControls.extraLeading(controls: 66, existing: 16), 66 + WindowControls.gap - 16)
        // Padding already wider than the controls: nothing to add.
        XCTAssertEqual(WindowControls.extraLeading(controls: 20, existing: 40), 0)
    }

    /// The Timer's bar scrolls with the page in a narrow window, where the
    /// system's own modifier has no effect, so it takes the measurement
    /// from the page's root. The bars that do not scroll use the system's.
    func testEveryBarTheAppDrawsWithALeadingButtonKeepsClearOfTheWindowControls() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        func source(_ name: String) throws -> String {
            try String(contentsOf: root.appendingPathComponent("MOTIVO/\(name)"), encoding: .utf8)
        }
        let timer = try source("PracticeTimerView.swift")
        XCTAssertTrue(timer.contains("let windowControls = proxy.containerCornerInsets.topLeading.width"))
        XCTAssertTrue(timer.contains(".padding(.leading, WindowControls.extraLeading(controls: windowControls, existing: Theme.Spacing.l))"))
        XCTAssertEqual(timer.components(separatedBy: "homeTopBar(windowControls: windowControls)").count - 1, 2,
                       "the bar in the scrolling column and the bar above both columns")
        for file in ["ContentView.swift", "AttachmentViewerView.swift", "ManuscriptPadView.swift", "VideoRecorderView.swift"] {
            XCTAssertTrue(try source(file).contains(".clearOfWindowControls()"), file)
        }
        // The score viewer's own top row, which is in the Timer's file.
        let overlay = try XCTUnwrap(timer.range(of: "private func scoreViewerDestinationOverlay"))
        let nextMember = try XCTUnwrap(timer.range(of: "private func scoreViewerDestinationControl", range: overlay.upperBound..<timer.endIndex))
        XCTAssertTrue(timer[overlay.lowerBound..<nextMember.lowerBound].contains(".clearOfWindowControls()"))
        XCTAssertTrue(try source("WideWindowLayout.swift").contains("containerCornerOffset(.leading, sizeToFit: true)"))
    }

    /// A list of choices opened from inside a sheet gets the whole panel in
    /// a roomy window, in the Lists manager as in the entry editor.
    func testTheListsManagersPickersUseTheSharedPickerHeight() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let manager = try String(contentsOf: root.appendingPathComponent("MOTIVO/TasksManagerView.swift"), encoding: .utf8)
        XCTAssertEqual(manager.components(separatedBy: ".pickerSheetHeight()").count - 1, 2)
        XCTAssertFalse(manager.contains(".presentationDetents([.medium])"))
    }

    // MARK: - The score viewer and the Scores library on iPad (2026-11-22)

    /// On an iPad the library sheet takes longer to leave than the fixed
    /// 0.15 s the Timer used to wait, and the score viewer, a full-screen
    /// cover, came up the size of the sheet. The score is opened when the
    /// sheet HAS gone.
    func testAScoreChosenInTheLibraryOpensOnceTheLibrarySheetHasGone() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let timer = try String(contentsOf: root.appendingPathComponent("MOTIVO/PracticeTimerView.swift"), encoding: .utf8)
        XCTAssertTrue(timer.contains(".sheet(isPresented: $showScoresLibrary, onDismiss: {"))
        XCTAssertTrue(timer.contains("guard let item = scoreToOpenAfterLibrary else { return }"))
        XCTAssertTrue(timer.contains("scoreToOpenAfterLibrary = item\n                    showScoresLibrary = false"))
        // Not on a timer any more.
        let sheet = try XCTUnwrap(timer.range(of: ".sheet(isPresented: $showScoresLibrary, onDismiss: {"))
        let next = try XCTUnwrap(timer.range(of: ".sheet(item: $connectedScoreShareRequest", range: sheet.upperBound..<timer.endIndex))
        XCTAssertFalse(timer[sheet.lowerBound..<next.lowerBound].contains("asyncAfter"))
    }

    /// The Add Score choices hang on the + button, so on an iPad they open
    /// from it and not from the middle of the sheet.
    func testTheAddScoreChoicesOpenFromTheirButton() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let library = try String(contentsOf: root.appendingPathComponent("MOTIVO/ScoresLibraryView.swift"), encoding: .utf8)
        let label = try XCTUnwrap(library.range(of: ".accessibilityLabel(\"Add score\")"))
        let dialog = try XCTUnwrap(library.range(of: ".confirmationDialog(\"Add Score\""))
        XCTAssertGreaterThan(dialog.lowerBound, label.upperBound)
        XCTAssertFalse(library[label.upperBound..<dialog.lowerBound].contains("}"), "nothing closes between the button and its dialog")
    }

    // MARK: - The sign-in sheet on iPad (2026-11-22)

    /// A small panel, not the system's large one with a single button in
    /// it: narrower and shorter, never less than its base height, taller
    /// with larger text, and never larger than the system's own sheet.
    func testTheSignInPanelIsSmallButLeavesRoom() {
        typealias Panel = CompactPanelSizing
        let usual = Panel.size(formWidth: 580, formHeight: 650, height: Panel.baseHeight)
        XCTAssertEqual(usual, CGSize(width: 440, height: 340))
        XCTAssertGreaterThanOrEqual(usual.height, 52 * 4, "room above and below a 52 pt button for a line of text")
        // Larger text: taller.
        XCTAssertEqual(Panel.size(formWidth: 580, formHeight: 650, height: 510).height, 510)
        // Never shorter than the base, never beyond the system's sheet.
        XCTAssertEqual(Panel.size(formWidth: 580, formHeight: 650, height: 100).height, Panel.baseHeight)
        XCTAssertEqual(Panel.size(formWidth: 400, formHeight: 300, height: 900), CGSize(width: 400, height: 300))
        // No size from the system: its own.
        XCTAssertEqual(Panel.size(formWidth: nil, formHeight: nil, height: 340), CGSize(width: 440, height: 340))
    }

    /// Only the presentation changed: the sheet's content, and so the
    /// sign-in itself, is the same view as before.
    func testTheSignInSheetKeepsItsContentAndGainsOnlyItsSize() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let profile = try String(contentsOf: root.appendingPathComponent("MOTIVO/ProfileView.swift"), encoding: .utf8)
        XCTAssertTrue(profile.contains("signedOutGateView\n                        // A small panel on an iPad; unchanged on a phone.\n                        .presentationSizing(CompactPanelSizing(height: signInPanelHeight, roomy: WideWindow.isRoomy))"))
        // In a phone-sized space the system's own sizing is handed back.
        let layout = try String(contentsOf: root.appendingPathComponent("MOTIVO/WideWindowLayout.swift"), encoding: .utf8)
        XCTAssertTrue(layout.contains("guard roomy else {\n            let unchanged: AutomaticPresentationSizing = .automatic\n            return unchanged.proposedSize(for: root, context: context)"))
        XCTAssertEqual(profile.components(separatedBy: "SignInWithAppleButton(.signIn)").count - 1, 1)
        XCTAssertTrue(profile.contains("Spacer().frame(height: geo.size.height * 0.30)"), "the button is where it was within the sheet")
    }
}
