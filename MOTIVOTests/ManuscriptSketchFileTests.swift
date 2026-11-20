//
//  ManuscriptSketchFileTests.swift
//  MOTIVOTests
//
//  The feasibility proofs for a manuscript sketch kept as ONE file, a PDF
//  that carries its own drawing and paper (RELEASE.md, section B, step 3):
//
//  1. the drawing and the paper survive save, reopen and the app's own PDF
//     handling;
//  2. a save that fails or is interrupted leaves the previous sketch;
//  3. what is handed to another person holds no drawing, whether one page
//     is shared or the whole document.
//

import XCTest
import PencilKit
import PDFKit
import CryptoKit
@testable import Etudes

final class ManuscriptSketchFileTests: XCTestCase {

    private var scratch: URL!
    private var documentsMade: [String] = []

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("sketch-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        for path in documentsMade { try? FileManager.default.removeItem(atPath: path) }
        documentsMade = []
    }

    // MARK: Fixtures

    private func drawing(strokes: Int, seed: Double = 0) -> PKDrawing {
        let ink = PKInk(.pen, color: .black)
        let made: [PKStroke] = (0..<strokes).map { s in
            let points: [PKStrokePoint] = (0..<24).map { i in
                let x: Double = 60 + Double(i) * 18
                let wave: Double = sin(Double(i) / 2) * 9
                let y: Double = 90 + seed + Double(s) * 22 + wave
                return PKStrokePoint(location: CGPoint(x: x, y: y), timeOffset: Double(i) * 0.01,
                                     size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0)))
        }
        return PKDrawing(strokes: made)
    }

    private func sketch(strokes: Int = 6, kind: ManuscriptPaper.Kind = .singleStaff, clef: ManuscriptPaper.Clef = .bass, seed: Double = 0) -> ManuscriptSketch {
        ManuscriptSketch(paper: ManuscriptPaper(kind: kind, clef: clef), drawing: drawing(strokes: strokes, seed: seed))
    }

    private func file(_ name: String = UUID().uuidString) -> URL { scratch.appendingPathComponent(name).appendingPathExtension("pdf") }

    private func size(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    private func hash(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    /// A sketch saved into Documents the way an attachment's file is.
    private func savedInDocuments(_ sketch: ManuscriptSketch, name: String) throws -> String {
        let temp = try ManuscriptSketchFile.writeVerified(sketch)
        let path = try AttachmentStore.adoptTempExport(temp, suggestedName: name, kind: .pdf)
        documentsMade.append(path)
        return path
    }

    /// What this compares, and no more: the paper; the number of strokes; and
    /// for each stroke its ink type and colour, its transform, the number of
    /// points, and each point's position, size, opacity, force, azimuth,
    /// altitude and time offset (to 0.01). It does NOT compare a stroke's
    /// mask or random seed, nor anything PencilKit keeps beside the strokes.
    ///
    /// It is the tests' way of saying "the same drawing came back"; the
    /// app's own save check is stricter and separate: `writeVerified` reads
    /// the file back and requires the stored drawing bytes to be exactly the
    /// bytes it was given. (The encoded bytes are not compared here because a
    /// drawing that has been stored and read encodes a few bytes differently
    /// from one made in memory.)
    private func assertSame(_ a: ManuscriptSketch, _ b: ManuscriptSketch, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.paper, b.paper, file: file, line: line)
        XCTAssertEqual(a.drawing.strokes.count, b.drawing.strokes.count, file: file, line: line)
        for (x, y) in zip(a.drawing.strokes, b.drawing.strokes) {
            XCTAssertEqual(x.ink.inkType, y.ink.inkType, file: file, line: line)
            XCTAssertEqual(x.ink.color, y.ink.color, file: file, line: line)
            XCTAssertEqual(x.transform, y.transform, file: file, line: line)
            XCTAssertEqual(x.path.count, y.path.count, file: file, line: line)
            for (p, q) in zip(x.path, y.path) {
                XCTAssertEqual(p.location.x, q.location.x, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(p.location.y, q.location.y, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(p.size.width, q.size.width, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(p.size.height, q.size.height, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(p.opacity, q.opacity, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(p.force, q.force, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(p.azimuth, q.azimuth, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(p.altitude, q.altitude, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(p.timeOffset, q.timeOffset, accuracy: 0.01, file: file, line: line)
            }
        }
    }

    // MARK: 1. Save, reopen, and the app's PDF handling

    func testASavedSketchReopensWithItsDrawingAndPaper() throws {
        for paper in [ManuscriptPaper(kind: .singleStaff, clef: .treble), ManuscriptPaper(kind: .piano, clef: .none), ManuscriptPaper(kind: .plain, clef: .none)] {
            let original = ManuscriptSketch(paper: paper, drawing: drawing(strokes: 9))
            let url = file()
            try ManuscriptSketchFile.write(original, to: url)
            XCTAssertTrue(ManuscriptSketchFile.carriesSketch(url))
            assertSame(try ManuscriptSketchFile.read(url), original)
        }
    }

    func testAnEmptyPageIsStillASketch() throws {
        let original = ManuscriptSketch(paper: ManuscriptPaper(kind: .piano, clef: .none), drawing: PKDrawing())
        let url = file()
        try ManuscriptSketchFile.write(original, to: url)
        XCTAssertEqual(try ManuscriptSketchFile.read(url).drawing.strokes.count, 0)
        XCTAssertEqual(try ManuscriptSketchFile.read(url).paper, original.paper)
    }

    func testItIsAnOrdinaryOnePagePDFToEverythingElse() throws {
        let url = file()
        try ManuscriptSketchFile.write(sketch(), to: url)
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).size, ManuscriptPaper.pageSize)
        // The app's own thumbnail path reads it, shows ink, and changes nothing.
        let before = try hash(url)
        let thumbnail = try XCTUnwrap(AttachmentStore.generatePDFThumbnail(url: url, size: CGSize(width: 1024, height: 1024)))
        XCTAssertTrue(hasInk(thumbnail), "the page as others see it shows the drawing")
        XCTAssertEqual(try hash(url), before, "viewing a sketch does not rewrite it")
    }

    /// Sync, backup and the attachment store move bytes; the drawing is in the bytes.
    func testTheDrawingGoesWhereverTheFileGoes() throws {
        let original = sketch(strokes: 12)
        let url = file()
        try ManuscriptSketchFile.write(original, to: url)
        // A byte copy: what a device receives through sync or a restore.
        let copy = file()
        try FileManager.default.copyItem(at: url, to: copy)
        XCTAssertEqual(try hash(copy), try hash(url))
        assertSame(try ManuscriptSketchFile.read(copy), original)
        // Into Documents under another name: the staged-to-final move.
        let adopted = try AttachmentStore.adoptTempExport(copy, suggestedName: "Sketch \(UUID().uuidString)", kind: .pdf)
        documentsMade.append(adopted)
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: adopted)), original)
        // Replaced as a trimmed recording is: still the same sketch.
        let again = file()
        try FileManager.default.copyItem(at: url, to: again)
        let replaced = try AttachmentStore.replaceAttachmentFile(withTempURL: again, forExistingPath: adopted, kind: .pdf)
        documentsMade.append(replaced)
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: replaced)), original)
    }

    /// What the private sync goes by, unchanged: one file, one hash. The copy
    /// another device holds needs no upload; an edit is a different file and
    /// is sent, drawing and page together.
    func testSyncSeesAnEditedSketchAsOneReplacedFile() throws {
        let url = file()
        try ManuscriptSketchFile.write(sketch(strokes: 5), to: url)
        let received = file()
        try FileManager.default.copyItem(at: url, to: received)
        let saved = try XCTUnwrap(JournalAssetHash.hash(of: url))
        XCTAssertEqual(JournalAssetHash.hash(of: received), saved)
        XCTAssertFalse(JournalAssetPolicy.includeAsset(hasServerCopy: true, serverHash: saved, localHash: JournalAssetHash.hash(of: received)))
        let edited = try ManuscriptSketchFile.writeVerified(sketch(strokes: 6), in: scratch)
        let after = try XCTUnwrap(JournalAssetHash.hash(of: edited))
        XCTAssertNotEqual(after, saved)
        XCTAssertTrue(JournalAssetPolicy.includeAsset(hasServerCopy: true, serverHash: saved, localHash: after))
    }

    func testSomeoneElsesPDFIsNotASketch() throws {
        let url = file()
        var box = CGRect(x: 0, y: 0, width: 300, height: 400)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()
        XCTAssertFalse(ManuscriptSketchFile.carriesSketch(url))
        XCTAssertThrowsError(try ManuscriptSketchFile.read(url)) { XCTAssertEqual($0 as? ManuscriptSketchFile.FileError, .noSketch) }
        let shareable = try ManuscriptSketchFile.shareableURL(for: url)
        XCTAssertEqual(shareable.url, url, "an ordinary PDF is shared as it is")
        XCTAssertFalse(shareable.isTemporary)
    }

    func testADamagedDrawingIsReportedNotReadAsEmpty() throws {
        // A PDF that names the sketch property and holds nothing readable in it.
        let url = file()
        var box = CGRect(origin: .zero, size: ManuscriptPaper.pageSize)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        let packet = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:etudes="\(ManuscriptSketchFile.namespace)"><etudes:sketch>bm90IGEgc2tldGNo</etudes:sketch>
        </rdf:Description></rdf:RDF></x:xmpmeta>
        """
        context.addDocumentMetadata(Data(packet.utf8) as CFData)
        context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()
        XCTAssertTrue(ManuscriptSketchFile.carriesSketch(url))
        XCTAssertThrowsError(try ManuscriptSketchFile.read(url)) { XCTAssertEqual($0 as? ManuscriptSketchFile.FileError, .damagedSketch) }
        XCTAssertNotNil(PDFDocument(url: url), "it still opens as a PDF")
        // It names the property, so it is never handed out as it is.
        let shareable = try ManuscriptSketchFile.shareableURL(for: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: shareable.url.deletingLastPathComponent()) }
        XCTAssertTrue(shareable.isTemporary)
        XCTAssertTrue(ManuscriptSketchFile.isClean(shareable.url))
    }

    // MARK: The printed paper

    func testEachPaperHasItsStavesAndClefs() {
        let page = ManuscriptPaper.pageSize
        XCTAssertTrue(ManuscriptPaperRenderer.staves(for: ManuscriptPaper(kind: .plain, clef: .none)).isEmpty)
        let single = ManuscriptPaperRenderer.staves(for: ManuscriptPaper(kind: .singleStaff, clef: .alto))
        XCTAssertEqual(single.count, 10)
        XCTAssertTrue(single.allSatisfy { $0.clef == .alto })
        let piano = ManuscriptPaperRenderer.staves(for: ManuscriptPaper(kind: .piano, clef: .none))
        XCTAssertEqual(piano.count, 10, "five systems of two staves")
        XCTAssertEqual(piano.map(\.clef), Array(repeating: [ManuscriptPaper.Clef.treble, .bass], count: 5).flatMap { $0 })
        XCTAssertTrue((single + piano).allSatisfy { $0.top > 40 && $0.top + 28 < page.height - 40 }, "every staff is on the page")
        // The clefs come from the system's music symbols and sit on their staff.
        for clef in [ManuscriptPaper.Clef.treble, .bass, .alto] {
            let box = ManuscriptPaperRenderer.clefPath(clef, staffTop: 200)?.boundingBoxOfPath
            XCTAssertNotNil(box, "\(clef)")
            if let box {
                XCTAssertGreaterThan(box.minX, ManuscriptPaperRenderer.inset)
                XCTAssertLessThan(box.maxX, ManuscriptPaperRenderer.inset + 40)
                XCTAssertGreaterThan(box.minY, 200 - 20)
                XCTAssertLessThan(box.maxY, 228 + 20)
            }
        }
        XCTAssertNil(ManuscriptPaperRenderer.clefPath(.none, staffTop: 200))
    }

    // MARK: 2. A failed or interrupted save keeps the previous sketch
    //
    // `ManuscriptSketchEdits` is what the entry editor runs when a saved
    // sketch is drawn on again. These follow its three steps: the new file
    // placed beside the old, the record repointed and saved by the editor,
    // the old file removed only after.

    private func data(_ sketch: ManuscriptSketch) throws -> Data {
        let temp = try ManuscriptSketchFile.writeVerified(sketch, in: scratch)
        return try Data(contentsOf: temp)
    }

    func testAnEditIsPlacedBesideTheSavedSketchWhichIsNotTouched() throws {
        let first = sketch(strokes: 4), second = sketch(strokes: 7, seed: 40)
        let old = try savedInDocuments(first, name: "Sketch \(UUID().uuidString)")
        let before = try hash(URL(fileURLWithPath: old))
        var edits = ManuscriptSketchEdits()
        let id = UUID()
        let new = try edits.place(try data(second), for: id, currentPath: old)
        documentsMade.append(new)
        XCTAssertNotEqual(new, old)
        XCTAssertEqual(edits.replaced[id], .init(original: old, edited: new))
        // Until the entry is saved the record names the old file, and it is whole.
        XCTAssertEqual(try hash(URL(fileURLWithPath: old)), before)
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: old)), first)
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: new)), second)
    }

    func testAfterTheEntryIsSavedThePreviousFileGoes() throws {
        let old = try savedInDocuments(sketch(strokes: 4), name: "Sketch \(UUID().uuidString)")
        var edits = ManuscriptSketchEdits()
        let id = UUID(), second = sketch(strokes: 7, seed: 40)
        let new = try edits.place(try data(second), for: id, currentPath: old)
        documentsMade.append(new)
        edits.settleAfterSave { _ in .names(new) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: old))
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: new)), second)
        XCTAssertTrue(edits.replaced.isEmpty)
    }

    /// The app stops, or the save fails, after the new file landed and before
    /// the record was saved: the record names the old file, which is whole.
    /// Then the editor is left without saving, and the unused file goes.
    func testAnInterruptionOrCancelLeavesThePreviousSketch() throws {
        let first = sketch(strokes: 4)
        let old = try savedInDocuments(first, name: "Sketch \(UUID().uuidString)")
        var edits = ManuscriptSketchEdits()
        let new = try edits.place(try data(sketch(strokes: 9, seed: 40)), for: UUID(), currentPath: old)
        documentsMade.append(new)
        // Stopped here: nothing else has run.
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: old)), first)
        // Left without saving.
        edits.settleAfterCancel()
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: old)), first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: new), "the unused new file is taken away")
    }

    /// The save reported success but the record still names the old file, or
    /// what it names cannot be told: the old file is not removed.
    func testThePreviousFileStaysUnlessTheSavedRecordNamesAnother() throws {
        for stillNamesTheOldFile in [true, false] {
            let first = sketch(strokes: 4)
            let old = try savedInDocuments(first, name: "Sketch \(UUID().uuidString)")
            var edits = ManuscriptSketchEdits()
            let new = try edits.place(try data(sketch(strokes: 9, seed: 40)), for: UUID(), currentPath: old)
            documentsMade.append(new)
            edits.settleAfterSave { _ in stillNamesTheOldFile ? .names(old) : .unknown }
            assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: old)), first)
        }
    }

    func testASecondEditBeforeSavingReplacesTheFirstAndKeepsTheOriginal() throws {
        let first = sketch(strokes: 4)
        let old = try savedInDocuments(first, name: "Sketch \(UUID().uuidString)")
        var edits = ManuscriptSketchEdits()
        let id = UUID(), third = sketch(strokes: 11, seed: 80)
        let second = try edits.place(try data(sketch(strokes: 7, seed: 40)), for: id, currentPath: old)
        let newest = try edits.place(try data(third), for: id, currentPath: second)
        documentsMade.append(contentsOf: [second, newest])
        XCTAssertFalse(FileManager.default.fileExists(atPath: second), "the earlier edit was never named by a saved record")
        XCTAssertEqual(edits.replaced[id], .init(original: old, edited: newest))
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: old)), first)
        edits.settleAfterSave { _ in .names(newest) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: old))
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: newest)), third)
    }

    func testAnAttachmentRemovedInTheSameSaveLeavesNoPreviousFile() throws {
        let old = try savedInDocuments(sketch(strokes: 4), name: "Sketch \(UUID().uuidString)")
        var edits = ManuscriptSketchEdits()
        let new = try edits.place(try data(sketch(strokes: 7, seed: 40)), for: UUID(), currentPath: old)
        documentsMade.append(new)
        edits.settleAfterSave { _ in .gone }
        XCTAssertFalse(FileManager.default.fileExists(atPath: old))
    }

    func testSomethingThatIsNotASketchIsRefusedAndNothingChanges() throws {
        let first = sketch(strokes: 4)
        let old = try savedInDocuments(first, name: "Sketch \(UUID().uuidString)")
        var edits = ManuscriptSketchEdits()
        XCTAssertThrowsError(try edits.place(Data("not a sketch".utf8), for: UUID(), currentPath: old))
        XCTAssertTrue(edits.replaced.isEmpty)
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: old)), first)
    }

    func testASketchThatCannotBeWrittenLeavesThePreviousOne() throws {
        let first = sketch(strokes: 4)
        let old = try savedInDocuments(first, name: "Sketch \(UUID().uuidString)")
        let before = try hash(URL(fileURLWithPath: old))
        let nowhere = scratch.appendingPathComponent("no-such-folder", isDirectory: true)
        XCTAssertThrowsError(try ManuscriptSketchFile.writeVerified(sketch(strokes: 9), in: nowhere))
        XCTAssertEqual(try hash(URL(fileURLWithPath: old)), before)
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: old)), first)
    }

    // MARK: Unfinished work, and the hand-off from the pad to the entry
    //
    // The pad's Save does not make a sketch durable: the entry's save does.
    // In between, the finished sketch is only in the editor's memory, so its
    // recovery copy must still be there. "The app stops" is modelled as the
    // editor's state (its ledger, its `ManuscriptSketchEdits`) being thrown
    // away while the files stay, which is what a termination leaves.

    private typealias Recovery = ManuscriptSketchRecovery

    private func clearRecoveryFolder() { Recovery.wipeForFactoryReset() }

    /// The pad's Save, as the pad does it: the copy is handed over, not removed.
    private func padSaves(_ sketch: ManuscriptSketch, _ opening: Recovery.Opening) {
        XCTAssertTrue(Recovery.handOver(sketch, opening: opening))
    }

    func testWhileDrawingTheSketchIsKeptAndADiscardRemovesIt() throws {
        clearRecoveryFolder(); addTeardownBlock { Recovery.wipeForFactoryReset() }
        let opening = Recovery.Opening.new()
        XCTAssertNil(Recovery.offer(for: opening))
        let unfinished = sketch(strokes: 5, kind: .piano, clef: .none)
        XCTAssertTrue(Recovery.keep(unfinished, key: opening.key))
        // The app stops. The next new sketch is offered it.
        let offered = try XCTUnwrap(Recovery.offer(for: .new()))
        XCTAssertEqual(offered.key, opening.key)
        XCTAssertFalse(offered.handedOver)
        assertSame(offered.sketch, unfinished)
        // Left on purpose without saving: nothing to offer back.
        Recovery.leftWithoutSaving(opening: opening, heldSketch: nil)
        XCTAssertNil(Recovery.offer(for: .new()))
        // Device-only: the folder is kept out of backups.
        XCTAssertEqual(try Recovery.directory().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    /// Codex's finding, case 1. Pad Save, then the app stops before the
    /// entry is saved: the new sketch is still there to recover.
    func testANewSketchSavedInThePadSurvivesUntilTheEntryIsSaved() throws {
        clearRecoveryFolder(); addTeardownBlock { Recovery.wipeForFactoryReset() }
        var ledger = ManuscriptSketchRecoveryLedger()
        let opening = Recovery.Opening.new(excluding: ledger.held)
        let drawn = sketch(strokes: 6)
        padSaves(drawn, opening)
        ledger.handedOver(key: opening.key, for: UUID())
        // The editor holds it, so another new sketch in the same editor is not offered it.
        XCTAssertNil(Recovery.offer(for: .new(excluding: ledger.held)))
        // The app stops before Save Thought. Nothing of the editor is left.
        ledger = ManuscriptSketchRecoveryLedger()
        let offered = try XCTUnwrap(Recovery.offer(for: .new(excluding: ledger.held)))
        XCTAssertTrue(offered.handedOver)
        assertSame(offered.sketch, drawn)
        // Restored, saved in the pad again, and this time the entry is saved.
        let again = Recovery.Opening(key: offered.key, attachment: nil, held: false, excluding: [], isNew: true)
        padSaves(offered.sketch, again)
        ledger.handedOver(key: again.key, for: UUID())
        ledger.entrySaved()
        XCTAssertNil(Recovery.offer(for: .new()))
        XCTAssertTrue(ledger.held.isEmpty)
    }

    /// Case 2. An edit of a SAVED sketch, pad Save, the app stops before
    /// the entry is saved: the original is whole and the edit is recoverable.
    func testAnEditSavedInThePadSurvivesAndTheOriginalStands() throws {
        clearRecoveryFolder(); addTeardownBlock { Recovery.wipeForFactoryReset() }
        let original = sketch(strokes: 4), edit = sketch(strokes: 9, seed: 40)
        let savedPath = try savedInDocuments(original, name: "Sketch \(UUID().uuidString)")
        let attachment = UUID()
        var edits = ManuscriptSketchEdits()
        var ledger = ManuscriptSketchRecoveryLedger()
        let opening = Recovery.Opening.reopening(key: Recovery.key(forSaved: attachment), attachment: attachment, held: false)
        XCTAssertNil(Recovery.offer(for: opening))
        padSaves(edit, opening)
        documentsMade.append(try edits.place(try data(edit), for: attachment, currentPath: savedPath))
        ledger.handedOver(key: opening.key, for: attachment)
        // The app stops before the entry is saved.
        edits = ManuscriptSketchEdits(); ledger = ManuscriptSketchRecoveryLedger()
        // The saved record still names the original, and it is whole.
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: savedPath)), original)
        // Opening that sketch again offers the edit.
        let reopened = Recovery.Opening.reopening(key: Recovery.key(forSaved: attachment), attachment: attachment, held: ledger.key(for: attachment) != nil)
        let offered = try XCTUnwrap(Recovery.offer(for: reopened))
        XCTAssertEqual(offered.attachment, attachment)
        assertSame(offered.sketch, edit)
        // An edit of a saved sketch is never offered to a brand-new sketch.
        XCTAssertNil(Recovery.offer(for: .new()))
    }

    /// Case 3. Several unsaved sketches: each has its own copy, and each is
    /// recovered or discarded without touching the others.
    func testSeveralUnsavedSketchesAreRecoverableIndependently() throws {
        clearRecoveryFolder(); addTeardownBlock { Recovery.wipeForFactoryReset() }
        var ledger = ManuscriptSketchRecoveryLedger()
        let first = sketch(strokes: 3), second = sketch(strokes: 5, seed: 30), third = sketch(strokes: 7, seed: 60)
        var keys: [String] = []
        for drawn in [first, second, third] {
            let opening = Recovery.Opening.new(excluding: ledger.held)
            XCTAssertNil(Recovery.offer(for: opening), "a sketch the editor holds is not offered to the next new one")
            padSaves(drawn, opening)
            ledger.handedOver(key: opening.key, for: UUID())
            keys.append(opening.key)
        }
        XCTAssertEqual(Set(keys).count, 3, "no shared slot")
        // The app stops with all three unsaved.
        ledger = ManuscriptSketchRecoveryLedger()
        let waiting = Recovery.unattached()
        XCTAssertEqual(Set(waiting.map(\.key)), Set(keys))
        for (key, drawn) in zip(keys, [first, second, third]) { assertSame(try XCTUnwrap(Recovery.copy(key: key)).sketch, drawn) }
        // One is restored and held again; the next new sketch is offered another, not that one.
        let restored = try XCTUnwrap(Recovery.offer(for: .new()))
        ledger.handedOver(key: restored.key, for: UUID())
        let next = try XCTUnwrap(Recovery.offer(for: .new(excluding: ledger.held)))
        XCTAssertNotEqual(next.key, restored.key)
        // That one is discarded at the offer: the third is still there, the restored one untouched.
        Recovery.clear(key: next.key)
        let last = try XCTUnwrap(Recovery.offer(for: .new(excluding: ledger.held)))
        XCTAssertFalse([restored.key, next.key].contains(last.key))
        XCTAssertNotNil(Recovery.copy(key: restored.key))
    }

    /// Case 4. A durable entry save, and each explicit discard, remove the
    /// copies they should and no others.
    func testSavingTheEntryOrDiscardingClearsTheRightCopies() throws {
        clearRecoveryFolder(); addTeardownBlock { Recovery.wipeForFactoryReset() }
        // Someone else's unsaved sketch, from an earlier stop: not this editor's to clear.
        let stranger = Recovery.Opening.new()
        Recovery.keep(sketch(strokes: 2), key: stranger.key)

        var ledger = ManuscriptSketchRecoveryLedger()
        let keptID = UUID(), removedID = UUID()
        let kept = Recovery.Opening.new(excluding: ledger.held)
        padSaves(sketch(strokes: 4), kept); ledger.handedOver(key: kept.key, for: keptID)
        let removed = Recovery.Opening.new(excluding: ledger.held)
        padSaves(sketch(strokes: 5, seed: 30), removed); ledger.handedOver(key: removed.key, for: removedID)

        // The tile is removed in the editor: that sketch's copy goes, the other stays.
        ledger.discarded(removedID)
        XCTAssertNil(Recovery.copy(key: removed.key))
        XCTAssertNotNil(Recovery.copy(key: kept.key))

        // A held sketch is reopened, drawn on, and the changes discarded in the
        // pad: the copy goes back to what the editor holds, it is not removed.
        let heldSketch = sketch(strokes: 4)
        let reopened = Recovery.Opening.reopening(key: kept.key, attachment: nil, held: true)
        XCTAssertNil(Recovery.offer(for: reopened), "what the editor holds is not offered back to it")
        Recovery.keep(sketch(strokes: 12, seed: 70), key: reopened.key)
        Recovery.leftWithoutSaving(opening: reopened, heldSketch: heldSketch)
        let after = try XCTUnwrap(Recovery.copy(key: kept.key))
        assertSame(after.sketch, heldSketch)
        XCTAssertTrue(after.handedOver)

        // The entry is saved: this editor's copies go, the stranger's stays.
        ledger.entrySaved()
        XCTAssertNil(Recovery.copy(key: kept.key))
        XCTAssertNotNil(Recovery.copy(key: stranger.key))

        // Leaving an editor without saving discards what it held.
        var other = ManuscriptSketchRecoveryLedger()
        let abandoned = Recovery.Opening.new(excluding: other.held)
        Recovery.clear(key: stranger.key)
        padSaves(sketch(strokes: 6), abandoned); other.handedOver(key: abandoned.key, for: UUID())
        other.editorCancelled()
        XCTAssertNil(Recovery.copy(key: abandoned.key))
        XCTAssertTrue(Recovery.unattached().isEmpty)
    }

    /// Case 5. The entry's save fails: nothing is cleared, in the editor or
    /// after the app stops.
    func testAFailedEntrySaveKeepsTheWorkRecoverable() throws {
        clearRecoveryFolder(); addTeardownBlock { Recovery.wipeForFactoryReset() }
        var ledger = ManuscriptSketchRecoveryLedger()
        let newOne = sketch(strokes: 6), edit = sketch(strokes: 9, seed: 40)
        let original = sketch(strokes: 4)
        let savedPath = try savedInDocuments(original, name: "Sketch \(UUID().uuidString)")
        let attachment = UUID()
        var edits = ManuscriptSketchEdits()

        let a = Recovery.Opening.new(excluding: ledger.held)
        padSaves(newOne, a); ledger.handedOver(key: a.key, for: UUID())
        let b = Recovery.Opening.reopening(key: Recovery.key(forSaved: attachment), attachment: attachment, held: false)
        padSaves(edit, b); ledger.handedOver(key: b.key, for: attachment)
        let placed = try edits.place(try data(edit), for: attachment, currentPath: savedPath)
        documentsMade.append(placed)

        // The save throws. The editor's "after a durable save" steps do not run:
        // neither `entrySaved` nor `settleAfterSave` is called.
        XCTAssertEqual(ledger.held, [a.key, b.key])
        assertSame(try XCTUnwrap(Recovery.copy(key: a.key)).sketch, newOne)
        assertSame(try XCTUnwrap(Recovery.copy(key: b.key)).sketch, edit)
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: savedPath)), original)
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: placed)), edit)
        // And if the app then stops, both are still offered.
        ledger = ManuscriptSketchRecoveryLedger()
        assertSame(try XCTUnwrap(Recovery.offer(for: .new())).sketch, newOne)
        assertSame(try XCTUnwrap(Recovery.offer(for: .reopening(key: Recovery.key(forSaved: attachment), attachment: attachment, held: false))).sketch, edit)
    }

    func testASketchHeldInMemoryReadsLikeOneOnDisk() throws {
        let original = sketch(strokes: 8)
        let bytes = try data(original)
        XCTAssertTrue(ManuscriptSketchFile.carriesSketch(data: bytes))
        assertSame(try ManuscriptSketchFile.read(data: bytes), original)
        XCTAssertFalse(ManuscriptSketchFile.carriesSketch(data: Data("%PDF-1.4 nothing".utf8)))
    }

    // MARK: 3. What another person receives holds no drawing

    func testTheCopyForSharingShowsThePageAndHoldsNoDrawing() throws {
        let url = file("Evening idea")
        try ManuscriptSketchFile.write(sketch(strokes: 10), to: url)
        XCTAssertFalse(ManuscriptSketchFile.isClean(url), "the saved sketch does hold its drawing")
        let shareable = try ManuscriptSketchFile.shareableURL(for: url)
        defer { try? FileManager.default.removeItem(at: shareable.url.deletingLastPathComponent()) }
        XCTAssertTrue(shareable.isTemporary)
        XCTAssertNotEqual(shareable.url, url)
        XCTAssertEqual(shareable.url.lastPathComponent, "Evening idea.pdf", "the copy keeps the sketch's name")
        XCTAssertTrue(ManuscriptSketchFile.isClean(shareable.url))
        XCTAssertFalse(ManuscriptSketchFile.carriesSketch(shareable.url))
        XCTAssertThrowsError(try ManuscriptSketchFile.read(shareable.url)) { XCTAssertEqual($0 as? ManuscriptSketchFile.FileError, .noSketch) }
        XCTAssertLessThan(try size(shareable.url), try size(url), "the copy is the page without the drawing's data")
        // And it is the same page to look at.
        let document = try XCTUnwrap(PDFDocument(url: shareable.url))
        XCTAssertEqual(document.pageCount, 1)
        XCTAssertEqual(document.page(at: 0)?.bounds(for: .mediaBox).size, ManuscriptPaper.pageSize)
        XCTAssertTrue(hasInk(try XCTUnwrap(AttachmentStore.generatePDFThumbnail(url: shareable.url, size: CGSize(width: 1024, height: 1024)))))
        // The saved sketch is untouched by being shared.
        XCTAssertTrue(ManuscriptSketchFile.carriesSketch(url))
    }

    /// The route a share with selected pages takes today. Whatever PDFKit
    /// does with the metadata, the copy made from its output is clean.
    func testTheSelectedPagesRouteEndsCleanToo() throws {
        let url = file()
        try ManuscriptSketchFile.write(sketch(strokes: 10), to: url)
        let exported = try PDFSubsetExporter.export(from: url, selectedPages: [1])
        defer { try? FileManager.default.removeItem(at: exported) }
        print("[sketch-spike] PDFKit's page export keeps the drawing: \(ManuscriptSketchFile.carriesSketch(exported))")
        let shareable = try ManuscriptSketchFile.shareableURL(for: exported)
        if shareable.isTemporary { addTeardownBlock { try? FileManager.default.removeItem(at: shareable.url.deletingLastPathComponent()) } }
        XCTAssertTrue(ManuscriptSketchFile.isClean(shareable.url))
    }

    /// What the sharing screens call, for any attachment.
    func testOnlyASketchIsCopiedForAnotherPerson() throws {
        let sketchURL = file("Idea")
        try ManuscriptSketchFile.write(sketch(), to: sketchURL)
        let out = try ManuscriptSketchFile.urlForAnotherPerson(sketchURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
        XCTAssertNotEqual(out, sketchURL)
        XCTAssertTrue(ManuscriptSketchFile.isClean(out))
        // A recording, and a file that is not a PDF whatever its name: untouched.
        let audio = scratch.appendingPathComponent("take.m4a")
        try Data("not audio either".utf8).write(to: audio)
        XCTAssertEqual(try ManuscriptSketchFile.urlForAnotherPerson(audio), audio)
        let notAPDF = file("scan")
        try Data("%PDF-nothing readable".utf8).write(to: notAPDF)
        XCTAssertEqual(try ManuscriptSketchFile.urlForAnotherPerson(notAPDF), notAPDF, "shared as it always was")
    }

    // MARK: Measurements (printed, for the record)

    func testSizes() throws {
        for strokes in [0, 20, 200] {
            let s = sketch(strokes: strokes)
            let url = file()
            try ManuscriptSketchFile.write(s, to: url)
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let shareable = try ManuscriptSketchFile.cleanCopy(of: url)
            let clean = (try FileManager.default.attributesOfItem(atPath: shareable.path)[.size] as? Int) ?? 0
            print("[sketch-spike] strokes=\(strokes) drawing=\(s.drawing.dataRepresentation().count) B  sketch.pdf=\(size) B  clean.pdf=\(clean) B")
            try? FileManager.default.removeItem(at: shareable.deletingLastPathComponent())
            XCTAssertLessThan(size, 5_000_000)
        }
    }

    // MARK: Helpers

    /// True when the image has pixels that are clearly darker than paper and
    /// staff lines alone would give in the area the test strokes cover.
    private func hasInk(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var dark = 0
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i] < 60 && pixels[i + 1] < 60 && pixels[i + 2] < 60 { dark += 1 }
        return dark > 20
    }
}
