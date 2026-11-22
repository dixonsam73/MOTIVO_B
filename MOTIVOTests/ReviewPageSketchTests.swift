import XCTest
@testable import Etudes

/// The manuscript sketch on the review page (after a timed session). The
/// Timer holds every sketch, so one drawn or changed on the review page is
/// staged there at the pad's Save and Back to Timer loses nothing.
final class ReviewPageSketchTests: XCTestCase {

    private func source(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("MOTIVO/\(name)"), encoding: .utf8)
    }

    func testTheReviewPageHasTheManuscriptButtonWithTheSameIconAsTheEditor() throws {
        let page = try source("PostRecordDetailsView.swift")
        XCTAssertTrue(page.contains("Button(action: { showSketchPad_PRDV = true })"))
        XCTAssertTrue(page.contains("ManuscriptIcon(pointSize: 24)"))
        XCTAssertTrue(page.contains(".accessibilityLabel(\"Add manuscript sketch\")"))
        // Only where the Timer is behind the page to hold the sketch.
        XCTAssertTrue(page.contains("if sketchStaging != nil {"))
    }

    func testTheTimerGivesTheReviewPageItsSketchStaging() throws {
        let sheets = try source("PracticeTimerView+Sheets.swift")
        XCTAssertTrue(sheets.contains("sketchStaging: reviewSketchStaging,"))
        let timer = try source("PracticeTimerView+Sketch.swift")
        XCTAssertTrue(timer.contains("stageNew: { stageNewSketch($0) }"))
        XCTAssertTrue(timer.contains("applyEdit: { applyEditedStagedSketch($0, id: $1) }"))
        XCTAssertTrue(timer.contains("remove: { deleteStagedSketch($0) }"))
    }

    /// A new sketch is staged on the Timer FIRST, and shown here under the
    /// id the Timer gave it; an edit goes to the Timer too.
    func testASketchDrawnOrChangedOnTheReviewPageIsStagedOnTheTimer() throws {
        let sketch = try source("PostRecordDetailsView+Sketch.swift")
        let stage = try XCTUnwrap(sketch.range(of: "let id = staging.stageNew(result)"))
        let append = try XCTUnwrap(sketch.range(of: "stagedAttachments.append(StagedAttachment(id: id, data: result.data, kind: .pdf))"))
        XCTAssertLessThan(stage.lowerBound, append.lowerBound)
        XCTAssertTrue(sketch.contains("sketchStaging?.applyEdit(result, id)"))
        XCTAssertTrue(sketch.contains("sketchStaging?.rename(id, title)"))
        // The pad reopens on the Timer's recovery copy for that sketch.
        XCTAssertTrue(sketch.contains("TimerSketchEditRequest.recoveryKey(for: request.id)"))
    }

    /// Binned on the review page: only a sketch first drawn there leaves the
    /// Timer as well.
    func testOnlyASketchDrawnOnTheReviewPageIsRemovedFromTheTimerWithIt() throws {
        let sketch = try source("PostRecordDetailsView+Sketch.swift")
        XCTAssertTrue(sketch.contains("if sketchesDrawnHere_PRDV.remove(id) != nil { sketchStaging?.remove(id) }"))
        let attachments = try source("PostRecordDetailsView+Attachments.swift")
        XCTAssertTrue(attachments.contains("sketchRemoved_PRDV(a.id)"))
    }

    /// A sketch's tile opens the pad, as in the entry editor; it has the
    /// star and no page controls.
    func testASketchTileOpensThePad() throws {
        let attachments = try source("PostRecordDetailsView+Attachments.swift")
        XCTAssertTrue(attachments.contains("if sketchAttachmentIDs_PRDV.contains(att.id) {\n                                        openSketch_PRDV(att)\n                                        return"))
        XCTAssertTrue(attachments.contains("if att.kind == .pdf, !sketchAttachmentIDs_PRDV.contains(att.id) {"))
        XCTAssertTrue(attachments.contains("|| isSketch {"))
    }

    func testTheTimersRecoveryKeyForASketchIsOnePerSketch() {
        let id = UUID()
        XCTAssertEqual(TimerSketchEditRequest.recoveryKey(for: id), "timer-" + id.uuidString)
        XCTAssertNotEqual(TimerSketchEditRequest.recoveryKey(for: id), TimerSketchEditRequest.recoveryKey(for: UUID()))
    }
}
