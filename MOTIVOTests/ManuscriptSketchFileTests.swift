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

    /// Stroke for stroke: the same ink and the same points. (A drawing that has
    /// been stored and read encodes a few bytes differently from one made in
    /// memory, so the encoded bytes are not the comparison.)
    private func assertSame(_ a: ManuscriptSketch, _ b: ManuscriptSketch, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.paper, b.paper, file: file, line: line)
        XCTAssertEqual(a.drawing.strokes.count, b.drawing.strokes.count, file: file, line: line)
        for (x, y) in zip(a.drawing.strokes, b.drawing.strokes) {
            XCTAssertEqual(x.ink.inkType, y.ink.inkType, file: file, line: line)
            XCTAssertEqual(x.ink.color, y.ink.color, file: file, line: line)
            XCTAssertEqual(x.path.count, y.path.count, file: file, line: line)
            for (p, q) in zip(x.path, y.path) {
                XCTAssertEqual(p.location.x, q.location.x, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(p.location.y, q.location.y, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(p.size.width, q.size.width, accuracy: 0.01, file: file, line: line)
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

    func testAnEditReplacesTheSketchAndTheOldFileGoes() throws {
        let first = sketch(strokes: 4), second = sketch(strokes: 7, seed: 40)
        let old = try savedInDocuments(first, name: "Sketch \(UUID().uuidString)")
        var pointer = old
        let new = try ManuscriptSketchFile.saveEdit(second, replacing: old) { pointer = $0 }
        documentsMade.append(new)
        XCTAssertEqual(pointer, new)
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: pointer)), second)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old), "the replaced file is removed once the record points at the new one")
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

    func testARecordThatCannotBeSavedLeavesThePreviousSketchAndNoStray() throws {
        struct RecordNotSaved: Error {}
        let first = sketch(strokes: 4)
        let old = try savedInDocuments(first, name: "Sketch \(UUID().uuidString)")
        var offered: String?
        XCTAssertThrowsError(try ManuscriptSketchFile.saveEdit(sketch(strokes: 9, seed: 40), replacing: old) { path in
            offered = path
            // The new file is whole and in place before the record is asked to move.
            XCTAssertEqual(try ManuscriptSketchFile.read(URL(fileURLWithPath: path)).drawing.strokes.count, 9)
            XCTAssertTrue(FileManager.default.fileExists(atPath: old))
            throw RecordNotSaved()
        })
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: old)), first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(offered)), "the unused new file is taken away")
    }

    /// The app stops between the new file landing and the record being
    /// saved: the record still names the old file, and the old file is whole.
    func testAnInterruptionBeforeTheRecordMovesLeavesThePreviousSketch() throws {
        let first = sketch(strokes: 4)
        let old = try savedInDocuments(first, name: "Sketch \(UUID().uuidString)")
        let temp = try ManuscriptSketchFile.writeVerified(sketch(strokes: 9, seed: 40))
        let landed = try AttachmentStore.adoptTempExport(temp, suggestedName: "Sketch \(UUID().uuidString)", kind: .pdf)
        documentsMade.append(landed)
        // Nothing further runs. What the record names:
        assertSame(try ManuscriptSketchFile.read(URL(fileURLWithPath: old)), first)
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
