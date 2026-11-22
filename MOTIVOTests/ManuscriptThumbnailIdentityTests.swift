import XCTest
import PencilKit
import PDFKit
@testable import Etudes

/// A sketch drawn on again keeps its id and its page, and its file can come
/// out the same length. Its thumbnail must still be the new drawing (found
/// in review, 2026-11-22: the task and the cache both went by length).
final class ManuscriptThumbnailIdentityTests: XCTestCase {

    private func sketchPDF(lineAtY y: CGFloat) throws -> Data {
        let points = [CGPoint(x: 60, y: y), CGPoint(x: 500, y: y)].map {
            PKStrokePoint(location: $0, timeOffset: 0, size: CGSize(width: 6, height: 6),
                          opacity: 1, force: 1, azimuth: 0, altitude: 0)
        }
        let stroke = PKStroke(ink: PKInk(.monoline, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        let sketch = ManuscriptSketch(paper: ManuscriptPaper(kind: .plain, clef: .none), drawing: PKDrawing(strokes: [stroke]))
        let file = try ManuscriptSketchFile.writeVerified(sketch)
        defer { try? FileManager.default.removeItem(at: file) }
        return try Data(contentsOf: file)
    }

    /// Two different drawings whose PDFs are exactly the same length. The
    /// shorter is padded after its end-of-file marker, which a PDF allows.
    private func twoDrawingsOfEqualLength() throws -> (Data, Data) {
        var first = try sketchPDF(lineAtY: 150)
        var second = try sketchPDF(lineAtY: 650)
        let length = max(first.count, second.count)
        first.append(Data(repeating: 0x0A, count: length - first.count))
        second.append(Data(repeating: 0x0A, count: length - second.count))
        XCTAssertEqual(first.count, second.count)
        XCTAssertNotEqual(first, second)
        XCTAssertNotNil(PDFDocument(data: first)?.page(at: 0), "still a PDF")
        XCTAssertNotNil(PDFDocument(data: second)?.page(at: 0), "still a PDF")
        return (first, second)
    }

    /// The view task that draws a sketch's thumbnail is identified by the
    /// sketch's content, so it runs again for a redrawn sketch of the same
    /// length.
    func testASketchsThumbnailTaskIsIdentifiedByItsContent() throws {
        let (first, second) = try twoDrawingsOfEqualLength()
        XCTAssertNotEqual(AttachmentStore.stagedPDFContentIdentity(first, isSketch: true),
                          AttachmentStore.stagedPDFContentIdentity(second, isSketch: true))
        XCTAssertEqual(AttachmentStore.stagedPDFContentIdentity(first, isSketch: true),
                       AttachmentStore.stagedPDFContentIdentity(first, isSketch: true))
        // Any other staged PDF never changes under its id: its length is
        // enough, and a large score is not hashed at every layout.
        XCTAssertEqual(AttachmentStore.stagedPDFContentIdentity(first, isSketch: false), String(first.count))
    }

    /// The thumbnail cache gives each drawing its own picture under the one
    /// attachment id, and gives the same drawing the same picture again.
    func testTheThumbnailCacheDoesNotGiveARedrawnSketchItsOldPicture() throws {
        let (first, second) = try twoDrawingsOfEqualLength()
        let id = UUID().uuidString

        let firstImage = try XCTUnwrap(AttachmentStore.generatePDFThumbnail(data: first, cacheKey: id))
        let secondImage = try XCTUnwrap(AttachmentStore.generatePDFThumbnail(data: second, cacheKey: id))
        XCTAssertFalse(firstImage === secondImage, "the same id and length used to return the cached first picture")
        XCTAssertNotEqual(firstImage.pngData(), secondImage.pngData(), "and it is a picture of the new drawing")

        let again = try XCTUnwrap(AttachmentStore.generatePDFThumbnail(data: first, cacheKey: id))
        XCTAssertTrue(again === firstImage, "an unchanged sketch is still served from the cache")
    }

    func testEqualBytesHaveEqualFingerprintsAndDifferentBytesOfOneLengthDoNot() {
        let one = Data("manuscript-one".utf8), two = Data("manuscript-two".utf8)
        XCTAssertEqual(one.count, two.count)
        XCTAssertEqual(ContentFingerprint.of(one), ContentFingerprint.of(Data("manuscript-one".utf8)))
        XCTAssertNotEqual(ContentFingerprint.of(one), ContentFingerprint.of(two))
    }

    /// Both editors' sketch thumbnails go through the one identity, and a
    /// sketch not saved yet is drawn from its bytes in the entry editor.
    func testBothEditorsUseTheSharedIdentityForASketch() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for file in ["PostRecordDetailsView+Attachments.swift", "AddEditSessionView+Attachments.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent("MOTIVO/\(file)"), encoding: .utf8)
            XCTAssertTrue(source.contains("AttachmentStore.stagedPDFContentIdentity(att.data, isSketch: isSketch)"), file)
            XCTAssertFalse(source.contains("-\\(att.data.count)\""), "\(file) no longer goes by length")
        }
    }
}
