import XCTest
import SwiftUI
@testable import Etudes

/// The manuscript button's icon is a drawing, so its legibility is a matter
/// of its measurements. These pin the ones that matter at the button's size.
final class ManuscriptIconTests: XCTestCase {

    private typealias G = ManuscriptIconGeometry

    func testThereAreFiveStaveLinesEvenlySpaced() {
        XCTAssertEqual(G.lineYs.count, 5)
        XCTAssertEqual(G.lineEndXs.count, 5)
        let pitches = zip(G.lineYs.dropFirst(), G.lineYs).map { $0 - $1 }
        for pitch in pitches { XCTAssertEqual(pitch, pitches[0], accuracy: 0.001) }
    }

    /// The five lines must read as five at the button's real size. With
    /// less than a point and a half between them they begin to close up on
    /// an iPad, whose screen has two device pixels to the point.
    func testTheStaveLinesStayDistinctAtTheButtonsSize() {
        XCTAssertGreaterThanOrEqual(G.clearSpaceBetweenLines, 1.5)
        XCTAssertGreaterThanOrEqual(G.clearSpaceBetweenLines * 2, 3, "at least three clear device pixels on an iPad")
        // And the lines themselves are not hairlines beside the SF Symbols.
        XCTAssertGreaterThanOrEqual(G.stroke, 1.7)
    }

    /// The lines shorten down the stave, and each stops short of the pencil
    /// with clear space, round cap and both strokes allowed for.
    func testEachStaveLineStopsShortOfThePencil() {
        XCTAssertEqual(G.lineEndXs, G.lineEndXs.sorted(by: >), "longest at the top")

        let dx = G.pencilEnd.x - G.pencilTip.x, dy = G.pencilEnd.y - G.pencilTip.y
        let length = (dx * dx + dy * dy).squareRoot()
        let ux = dx / length, uy = dy / length
        // The pencil's stave-side edge: the axis moved half a width across.
        let edgeOrigin = CGPoint(x: G.pencilTip.x + uy * G.pencilHalfWidth, y: G.pencilTip.y - ux * G.pencilHalfWidth)

        for (y, endX) in zip(G.lineYs, G.lineEndXs) {
            let along = (y - edgeOrigin.y) / uy
            guard along >= 0, along <= length else { continue }   // above the pencil's far end
            let edgeX = edgeOrigin.x + ux * along
            let clear = (edgeX - G.stroke / 2) - (endX + G.stroke / 2)
            XCTAssertGreaterThanOrEqual(clear, 0.9, "the line at y \(y) keeps clear of the pencil")
        }
    }

    func testEverythingDrawnIsInsideTheIconsBox() {
        let half = G.stroke / 2
        XCTAssertGreaterThanOrEqual(G.lineStartX - half, 0)
        XCTAssertGreaterThanOrEqual((G.lineYs.min() ?? 0) - half, 0)
        XCTAssertLessThanOrEqual(G.pencilTip.y + half, G.box.height)
        // The pencil's far corner on the right.
        let dx = G.pencilEnd.x - G.pencilTip.x, dy = G.pencilEnd.y - G.pencilTip.y
        let length = (dx * dx + dy * dy).squareRoot()
        let rightmost = G.pencilEnd.x + (-dy / length) * G.pencilHalfWidth + half
        XCTAssertLessThanOrEqual(rightmost, G.box.width + 0.05)
    }

    /// About the size of the SF Symbols it sits beside at 22 pt.
    func testTheIconIsTheSizeOfItsNeighbours() {
        XCTAssertEqual(G.referencePointSize, 22)
        XCTAssertEqual(G.box.width, 26, accuracy: 2)
        XCTAssertEqual(G.box.height, 21, accuracy: 2)
    }

    func testBothManuscriptButtonsUseTheIconAndTheTimerLabelsItManuscript() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let row = try String(contentsOf: root.appendingPathComponent("MOTIVO/MediaRecorderRowCard.swift"), encoding: .utf8)
        XCTAssertTrue(row.contains("ManuscriptIcon(pointSize: 22)"))
        XCTAssertTrue(row.contains("if !hasUsedSketchCapture { captureCaption(\"Manuscript\") }"), "the first-use label, like Audio, Photo and Video")
        XCTAssertTrue(row.contains(".accessibilityLabel(\"Manuscript\")"))
        let editor = try String(contentsOf: root.appendingPathComponent("MOTIVO/AddEditSessionView.swift"), encoding: .utf8)
        XCTAssertTrue(editor.contains("ManuscriptIcon(pointSize: 24)"))
        XCTAssertFalse(row.contains("pencil.and.scribble"))
        XCTAssertFalse(editor.contains("pencil.and.scribble"))
    }

    // MARK: - First-use names on the Timer's buttons

    /// Samuel, 2026-11-21: every icon button on the Timer is named until it
    /// has been used once, then the name goes. The titles are his. The plus
    /// has none: a tap shows "+ Add session" and "+ Add thought".
    func testEveryTimerIconButtonHasItsFirstUseNameAndThePlusHasNone() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let timer = try String(contentsOf: root.appendingPathComponent("MOTIVO/PracticeTimerView.swift"), encoding: .utf8)
        for (flag, title) in [("hasUsedSessionButton", "Session"), ("hasUsedDroneButton", "Drone"),
                              ("hasUsedMetronomeButton", "Metronome"), ("hasUsedTunerButton", "Tuner"),
                              ("hasUsedAttachmentsButton", "Attachments"), ("hasUsedListButton", "List"),
                              ("hasUsedScoresButton", "Scores")] {
            XCTAssertTrue(timer.contains("if !\(flag) { timerButtonCaption(\"\(title)\") }"), title)
            XCTAssertTrue(timer.contains("\(flag) = true"), "\(title) is marked used when its button is used")
        }
        XCTAssertFalse(timer.contains("timerButtonCaption(\"Add\")"))

        let row = try String(contentsOf: root.appendingPathComponent("MOTIVO/MediaRecorderRowCard.swift"), encoding: .utf8)
        for title in ["Audio", "Photo", "Video", "Manuscript"] {
            XCTAssertTrue(row.contains("captureCaption(\"\(title)\")"), title)
        }
    }

    // MARK: - Show Manuscript (Profile → Settings)

    /// Samuel, 2026-11-22: a setting like the Timer's other tool settings.
    /// On by default; off hides only the button that starts a NEW sketch on
    /// the Timer, and its first-use name.
    func testShowManuscriptIsATimerToolSettingAndIsOnByDefault() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let profile = try String(contentsOf: root.appendingPathComponent("MOTIVO/ProfileView.swift"), encoding: .utf8)
        XCTAssertTrue(profile.contains("@AppStorage(\"appSettings_showManuscript\") private var showManuscript: Bool = true"))
        XCTAssertTrue(profile.contains("Toggle(isOn: $showManuscript) {\n                     Text(\"Show Manuscript\")"))

        let timer = try String(contentsOf: root.appendingPathComponent("MOTIVO/PracticeTimerView.swift"), encoding: .utf8)
        XCTAssertTrue(timer.contains("@AppStorage(\"appSettings_showManuscript\") private var showManuscriptButton: Bool = true"))
        // Hidden means no action is given to the row, and the row draws no
        // button and no name for an action it has not got.
        XCTAssertTrue(timer.contains("onSketch: showManuscriptButton ? {"))
        let row = try String(contentsOf: root.appendingPathComponent("MOTIVO/MediaRecorderRowCard.swift"), encoding: .utf8)
        XCTAssertTrue(row.contains("if let onSketch {"))
    }

    /// Off touches nothing else: staged sketches stay on the Timer and open
    /// in the pad, the entry editor and the review page keep their own
    /// manuscript button, and the first-use name is neither set nor reset.
    func testHidingTheButtonHidesNothingElse() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("MOTIVO")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        var readers: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            if source.contains("appSettings_showManuscript") { readers.append(file.lastPathComponent) }
        }
        XCTAssertEqual(readers.sorted(), ["PracticeTimerView.swift", "ProfileView.swift"])

        let timer = try String(contentsOf: folder.appendingPathComponent("PracticeTimerView.swift"), encoding: .utf8)
        XCTAssertEqual(timer.components(separatedBy: "showManuscriptButton").count - 1, 2,
                       "declared once and read once, for the button alone")
        // The first-use flag belongs to the row and changes only when the
        // button is used.
        let row = try String(contentsOf: folder.appendingPathComponent("MediaRecorderRowCard.swift"), encoding: .utf8)
        XCTAssertEqual(row.components(separatedBy: "hasUsedSketchCapture = true").count - 1, 1)
        XCTAssertEqual(row.components(separatedBy: "hasUsedSketchCapture = false").count - 1, 1, "only where it is declared")
        XCTAssertFalse(timer.contains("hasUsedSketchCapture"))
    }
}
