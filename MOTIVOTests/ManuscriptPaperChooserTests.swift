import XCTest
@testable import Etudes

/// The Paper page: six sheets, in Samuel's order, sharing out the screen.
final class ManuscriptPaperChooserTests: XCTestCase {

    private typealias Layout = ManuscriptPaperChooserLayout

    /// Samuel, 2026-11-21: staves with no clef, treble, bass, piano, alto,
    /// then a page with nothing printed on it.
    func testTheSixPapersAreInTheAgreedOrderWithTheAgreedNames() {
        let choices = ManuscriptPaperChooser.choices
        XCTAssertEqual(choices.map(\.id), ["No clef", "Treble", "Bass", "Piano", "Alto", "Blank page"])
        XCTAssertEqual(choices.map(\.paper), [
            ManuscriptPaper(kind: .singleStaff, clef: .none),
            ManuscriptPaper(kind: .singleStaff, clef: .treble),
            ManuscriptPaper(kind: .singleStaff, clef: .bass),
            ManuscriptPaper(kind: .piano, clef: .none),
            ManuscriptPaper(kind: .singleStaff, clef: .alto),
            ManuscriptPaper(kind: .plain, clef: .none),
        ])
    }

    /// Two across on a phone, three across on an iPad either way up, so six
    /// papers always make complete rows.
    func testSixPapersAlwaysMakeCompleteRows() {
        let spaces: [(CGSize, Int, Int)] = [
            (CGSize(width: 402, height: 760), 2, 3),    // iPhone 17 Pro, under the pad's top bar
            (CGSize(width: 390, height: 730), 2, 3),    // iPhone 16e
            (CGSize(width: 834, height: 1110), 3, 2),   // 11-inch iPad, portrait
            (CGSize(width: 1210, height: 734), 3, 2),   // 11-inch iPad, landscape
            (CGSize(width: 1376, height: 932), 3, 2),   // 13-inch iPad, landscape
        ]
        for (space, columns, rows) in spaces {
            let layout = Layout(space: space, count: 6)
            XCTAssertEqual(layout.columns, columns, "\(space)")
            XCTAssertEqual(layout.rows, rows, "\(space)")
            XCTAssertEqual((0..<layout.rows).flatMap { layout.indices(inRow: $0) }, Array(0..<6))
            for row in 0..<layout.rows { XCTAssertEqual(layout.indices(inRow: row).count, columns) }
        }
    }

    /// The sheets fill the space they are given and never run past it.
    func testTheSheetsFillTheScreenWithoutRunningPastIt() {
        for space in [CGSize(width: 402, height: 760), CGSize(width: 834, height: 1110), CGSize(width: 1210, height: 734)] {
            let layout = Layout(space: space, count: 6)
            let usedWidth = CGFloat(layout.columns) * layout.sheet.width
                + CGFloat(layout.columns - 1) * Layout.spacing + 2 * Layout.margin
            let usedHeight = CGFloat(layout.rows) * (layout.sheet.height + Layout.labelHeight)
                + CGFloat(layout.rows - 1) * Layout.spacing + 2 * Layout.margin
            XCTAssertLessThanOrEqual(usedWidth, space.width + 0.5, "\(space)")
            XCTAssertLessThanOrEqual(usedHeight, space.height + 0.5, "\(space)")
            XCTAssertGreaterThanOrEqual(usedHeight, space.height * 0.95, "the page is filled top to bottom at \(space)")
            XCTAssertLessThanOrEqual(layout.sheet.width, layout.sheet.height * Layout.widestAspect + 0.5, "a sheet, not a slab")
        }
    }

    /// In a space too short for six sheets the sheets keep a usable size and
    /// the page scrolls.
    func testAVeryShortSpaceKeepsTheSheetsUsable() {
        let layout = Layout(space: CGSize(width: 874, height: 300), count: 6)
        XCTAssertEqual(layout.sheet.height, Layout.smallestSheetHeight)
    }

    /// A sheet shows whole staves only. A staff the tile would cut through
    /// is blanked from just below the last one that fits.
    func testASheetShowsWholeStavesOnly() {
        let treble = ManuscriptPaper(kind: .singleStaff, clef: .treble)
        let rows = ManuscriptPaperRenderer.rows(for: treble)
        // Tall enough to cut through the fourth staff.
        let visible = rows[3].top + 10 - ManuscriptPaperSheetPreview.pageOrigin.y
        let blankFrom = ManuscriptPaperSheetPreview.blankFromY(paper: treble, visiblePageHeight: visible)
        XCTAssertEqual(blankFrom, rows[2].bottom + ManuscriptPaperSheetPreview.clefTail)
        XCTAssertLessThan(try XCTUnwrap(blankFrom), rows[3].top, "none of the fourth staff is left showing")

        // A piano system is kept or left off as a whole: never the treble staff alone.
        let piano = ManuscriptPaper(kind: .piano, clef: .none)
        let systems = ManuscriptPaperRenderer.rows(for: piano)
        let cutsSecondSystem = systems[1].top + 40 - ManuscriptPaperSheetPreview.pageOrigin.y
        XCTAssertEqual(ManuscriptPaperSheetPreview.blankFromY(paper: piano, visiblePageHeight: cutsSecondSystem),
                       systems[0].bottom + ManuscriptPaperSheetPreview.clefTail)

        // A blank page has nothing to blank.
        XCTAssertNil(ManuscriptPaperSheetPreview.blankFromY(paper: ManuscriptPaper(kind: .plain, clef: .none), visiblePageHeight: 300))
    }
}
