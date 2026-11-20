//
//  ManuscriptSketchFile.swift
//  MOTIVO
//
//  A manuscript sketch is ONE file: a PDF that also carries the drawing and
//  the paper it was drawn on, so the pad can reopen it for editing.
//
//  Why one file (decided 2026-11-20): the private sync treats an attachment
//  as one file with one hash, and every data-safety step is built on that
//  (the upload decision, replaced-file detection, keeping a displaced file,
//  keeping before a first-merge deletion, Restore). A second file beside
//  the PDF would have to be threaded through all of them. With the drawing
//  inside the PDF, a sketch that syncs, is displaced, restored or brought
//  back from a backup is editable wherever it lands, and none of that code
//  changes.
//
//  The drawing travels in the PDF's document metadata (an XMP packet, which
//  is what the format provides for an application's own properties). Anyone
//  else's PDF reader shows the page and ignores it.
//
//  What leaves for ANOTHER PERSON is never this file: `shareableURL` hands
//  out a copy re-drawn without the metadata.
//

import Foundation
import CoreGraphics
import PencilKit
#if canImport(UIKit)
import UIKit
#endif

/// The paper a sketch is drawn on. Chosen before drawing; part of the sketch.
struct ManuscriptPaper: Codable, Equatable {
    enum Kind: String, Codable { case singleStaff, piano, plain }
    enum Clef: String, Codable { case treble, bass, alto, none }

    var kind: Kind
    var clef: Clef

    /// Fixed for every sketch: the screen changes the view, never the page.
    static let pageSize = CGSize(width: 595, height: 842)
}

struct ManuscriptSketch {
    var paper: ManuscriptPaper
    var drawing: PKDrawing
}

enum ManuscriptSketchFile {

    enum FileError: Error, Equatable {
        /// The PDF could not be created at the given place.
        case cannotCreate
        /// Not a readable PDF.
        case unreadable
        /// A PDF, but not one of our sketches.
        case noSketch
        /// It says it is a sketch and its drawing cannot be read.
        case damagedSketch
        /// What was written did not read back as what was meant.
        case verificationFailed
        /// The copy made for sharing still held a drawing.
        case copyNotClean
    }

    static let payloadVersion = 1
    /// Names the property in the metadata; also what a clean copy must not contain.
    static let namespace = "https://etudes.app/ns/sketch/1.0/"
    private static let openTag = "<etudes:sketch>"
    private static let closeTag = "</etudes:sketch>"

    private struct Payload: Codable {
        var version: Int
        var paper: ManuscriptPaper
        var drawing: Data
    }

    // MARK: Write

    /// Draws the page and embeds the drawing. Overwrites `url`; callers that
    /// are replacing a saved sketch go through `saveEdit`, never here.
    static func write(_ sketch: ManuscriptSketch, to url: URL) throws {
        try write(paper: sketch.paper, drawingData: sketch.drawing.dataRepresentation(), drawing: sketch.drawing, to: url)
    }

    private static func write(paper: ManuscriptPaper, drawingData: Data, drawing: PKDrawing, to url: URL) throws {
        let payload = Payload(version: payloadVersion, paper: paper, drawing: drawingData)
        let encoded = try JSONEncoder().encode(payload).base64EncodedString()
        let packet = """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:etudes="\(namespace)">
        \(openTag)\(encoded)\(closeTag)
        </rdf:Description>
        </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
        var box = CGRect(origin: .zero, size: ManuscriptPaper.pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw FileError.cannotCreate }
        context.addDocumentMetadata(Data(packet.utf8) as CFData)
        context.beginPDFPage(nil)
        drawPage(paper: paper, drawing: drawing, in: context)
        context.endPDFPage()
        context.closePDF()
        guard FileManager.default.fileExists(atPath: url.path) else { throw FileError.cannotCreate }
    }

    /// The page as anyone sees it: the paper in vector lines, the ink over it.
    private static func drawPage(paper: ManuscriptPaper, drawing: PKDrawing, in context: CGContext) {
        let size = ManuscriptPaper.pageSize
        context.saveGState()
        // PDF space starts bottom-left; the pad and the staves count from the top.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setStrokeColor(CGColor(gray: 0.25, alpha: 1))
        context.setLineWidth(0.6)
        for y in staffLineOffsets(for: paper) {
            context.move(to: CGPoint(x: 48, y: y))
            context.addLine(to: CGPoint(x: size.width - 48, y: y))
        }
        context.strokePath()
        #if canImport(UIKit)
        if !drawing.strokes.isEmpty {
            var image: UIImage?
            // Ink colours follow the appearance; the page is always the light one.
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                image = drawing.image(from: CGRect(origin: .zero, size: size), scale: inkScale)
            }
            if let image {
                UIGraphicsPushContext(context)
                image.draw(in: CGRect(origin: .zero, size: size))
                UIGraphicsPopContext()
            }
        }
        #endif
        context.restoreGState()
    }

    /// Pixels per point for the ink in the PDF.
    static let inkScale: CGFloat = 2

    /// Distances from the top of the page to each staff line. Printed clefs
    /// and braces are part of the paper and are drawn with it once their
    /// source is settled; the positions here do not move when they arrive.
    static func staffLineOffsets(for paper: ManuscriptPaper) -> [CGFloat] {
        let lineGap: CGFloat = 7
        func staff(top: CGFloat) -> [CGFloat] { (0..<5).map { top + CGFloat($0) * lineGap } }
        switch paper.kind {
        case .plain:
            return []
        case .singleStaff:
            return stride(from: CGFloat(72), through: 842 - 72 - 4 * lineGap, by: 70).flatMap(staff)
        case .piano:
            return stride(from: CGFloat(72), through: 842 - 72 - 90, by: 130).flatMap { staff(top: $0) + staff(top: $0 + 62) }
        }
    }

    // MARK: Read

    /// The sketch a PDF carries. `noSketch` for anyone else's PDF.
    static func read(_ url: URL) throws -> ManuscriptSketch {
        let payload = try payload(of: url)
        guard let drawing = try? PKDrawing(data: payload.drawing) else { throw FileError.damagedSketch }
        return ManuscriptSketch(paper: payload.paper, drawing: drawing)
    }

    /// Whether "Edit sketch" can be offered for this PDF.
    static func carriesSketch(_ url: URL) -> Bool {
        (try? metadata(of: url))?.contains(openTag) ?? false
    }

    private static func payload(of url: URL) throws -> Payload {
        guard let text = try metadata(of: url),
              let open = text.range(of: openTag),
              let close = text.range(of: closeTag, range: open.upperBound..<text.endIndex) else { throw FileError.noSketch }
        let encoded = text[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let json = Data(base64Encoded: encoded),
              let payload = try? JSONDecoder().decode(Payload.self, from: json),
              payload.version == payloadVersion else { throw FileError.damagedSketch }
        return payload
    }

    /// The document's metadata packet as text; nil when it has none.
    private static func metadata(of url: URL) throws -> String? {
        guard let document = CGPDFDocument(url as CFURL), let catalog = document.catalog else { throw FileError.unreadable }
        var stream: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(catalog, "Metadata", &stream), let stream else { return nil }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream, &format) as Data? else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Save

    /// A complete, checked sketch file in a temporary place. Nothing the
    /// journal points at has been touched when this returns or throws.
    static func writeVerified(_ sketch: ManuscriptSketch, in directory: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let temp = directory.appendingPathComponent("sketch-\(UUID().uuidString).pdf", isDirectory: false)
        let data = sketch.drawing.dataRepresentation()
        do {
            try write(paper: sketch.paper, drawingData: data, drawing: sketch.drawing, to: temp)
            let back = try payload(of: temp)
            guard back.paper == sketch.paper, back.drawing == data, (try? PKDrawing(data: back.drawing)) != nil else {
                throw FileError.verificationFailed
            }
            return temp
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    /// Replaces a saved sketch so that an interruption at any point leaves
    /// the journal pointing at a whole file: the new sketch is written and
    /// checked, placed beside the old one, the caller repoints and saves its
    /// record in `commit`, and only then is the old file removed. If `commit`
    /// throws, the new file is taken away and the old sketch stands.
    /// - Returns: the new file's path.
    @discardableResult
    static func saveEdit(_ sketch: ManuscriptSketch, replacing existingPath: String, commit: (String) throws -> Void) throws -> String {
        let temp = try writeVerified(sketch)
        let base = URL(fileURLWithPath: existingPath).deletingPathExtension().lastPathComponent
        let newPath: String
        do {
            newPath = try AttachmentStore.adoptTempExport(temp, suggestedName: base.isEmpty ? "Sketch" : base, kind: .pdf)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        do {
            try commit(newPath)
        } catch {
            AttachmentStore.deleteAttachmentFile(atPath: newPath)
            throw error
        }
        AttachmentStore.deleteAttachmentFile(atPath: existingPath)
        return newPath
    }

    // MARK: Sharing with other people

    /// What may be handed to another person: the file itself for an ordinary
    /// PDF, and for a sketch a copy without the drawing. Throws rather than
    /// return a sketch as it is.
    ///
    /// A file that cannot be read as a PDF at all (not a PDF, or one locked
    /// with a password) is not one of ours, which are never locked, and is
    /// returned as it is, so sharing such a file behaves as it always has.
    static func shareableURL(for url: URL) throws -> (url: URL, isTemporary: Bool) {
        let text: String?
        do { text = try metadata(of: url) } catch FileError.unreadable { return (url, false) }
        guard let text, text.contains(namespace) || text.contains(openTag) else { return (url, false) }
        return (try cleanCopy(of: url), true)
    }

    /// The one call the sharing screens make, for any attachment: a PDF goes
    /// through `shareableURL`; every other kind of file is returned as it is.
    static func urlForAnotherPerson(_ url: URL) throws -> URL {
        guard url.pathExtension.lowercased() == "pdf" else { return url }
        return try shareableURL(for: url).url
    }

    /// The same pages, drawn again into a new PDF that has no metadata.
    static func cleanCopy(of url: URL) throws -> URL {
        guard let source = CGPDFDocument(url as CFURL), source.numberOfPages > 0 else { throw FileError.unreadable }
        let name = url.deletingPathExtension().lastPathComponent
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent(name.isEmpty ? "Sketch" : name).appendingPathExtension("pdf")
        guard let context = CGContext(output as CFURL, mediaBox: nil, nil) else { throw FileError.cannotCreate }
        for number in 1...source.numberOfPages {
            guard let page = source.page(at: number) else { continue }
            var box = page.getBoxRect(.mediaBox)
            context.beginPage(mediaBox: &box)
            context.drawPDFPage(page)
            context.endPage()
        }
        context.closePDF()
        guard isClean(output) else {
            try? FileManager.default.removeItem(at: folder)
            throw FileError.copyNotClean
        }
        return output
    }

    /// No sketch property in the document's metadata, read the way the pad
    /// reads it. That is the check that counts: the metadata is stored
    /// compressed, so the plain scan of the bytes only catches a file that
    /// stored it uncompressed.
    static func isClean(_ url: URL) -> Bool {
        guard let bytes = try? Data(contentsOf: url) else { return false }
        let text: String?
        do { text = try metadata(of: url) } catch { return false }
        if let text, text.contains(openTag) || text.contains(namespace) { return false }
        return bytes.range(of: Data(namespace.utf8)) == nil && bytes.range(of: Data(openTag.utf8)) == nil
    }
}
