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
import CoreText
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
    /// Printed bar lines: 2 or 4 bars to a row; nil for none. Part of the
    /// paper, not the ink, so it can be switched while drawing without
    /// touching what has been drawn. Absent in sketches saved before it
    /// existed, which read as none.
    var barsPerRow: Int? = nil

    /// The choices offered, in the order the pad's switch steps through them.
    static let barChoices: [Int?] = [nil, 2, 4]

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
    /// are replacing a saved sketch go through `ManuscriptSketchEdits`, never here.
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
        // PDF space starts bottom-left; the pad and the paper count from the top.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        ManuscriptPaperRenderer.draw(paper, in: context)
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

    // MARK: Read

    /// The sketch a PDF carries. `noSketch` for anyone else's PDF.
    static func read(_ url: URL) throws -> ManuscriptSketch {
        try sketch(from: payload(in: try metadata(of: url)))
    }

    /// The same, for a PDF held in memory (an attachment not yet saved).
    static func read(data: Data) throws -> ManuscriptSketch {
        try sketch(from: payload(in: try metadata(of: data)))
    }

    /// Whether "Edit sketch" can be offered for this PDF.
    static func carriesSketch(_ url: URL) -> Bool {
        (try? metadata(of: url))?.contains(openTag) ?? false
    }

    static func carriesSketch(data: Data) -> Bool {
        (try? metadata(of: data))?.contains(openTag) ?? false
    }

    private static func sketch(from payload: Payload) throws -> ManuscriptSketch {
        guard let drawing = try? PKDrawing(data: payload.drawing) else { throw FileError.damagedSketch }
        return ManuscriptSketch(paper: payload.paper, drawing: drawing)
    }

    private static func payload(of url: URL) throws -> Payload {
        try payload(in: try metadata(of: url))
    }

    private static func payload(in metadata: String?) throws -> Payload {
        guard let text = metadata,
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
        guard let document = CGPDFDocument(url as CFURL) else { throw FileError.unreadable }
        return try metadata(of: document)
    }

    private static func metadata(of data: Data) throws -> String? {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else { throw FileError.unreadable }
        return try metadata(of: document)
    }

    private static func metadata(of document: CGPDFDocument) throws -> String? {
        guard let catalog = document.catalog else { throw FileError.unreadable }
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

/// Saved sketches that have been drawn on again in the entry editor and not
/// yet saved with the entry.
///
/// A saved sketch is never overwritten. The order, which is the whole point:
///
/// 1. `place` puts the edited sketch's file BESIDE the saved one and returns
///    its path for the editor to point at. The saved file is untouched and
///    the saved record still names it.
/// 2. The entry's own save repoints the record and saves it.
/// 3. `settleAfterSave` removes the previous file, and only where the saved
///    record really names another file now. `settleAfterCancel` removes the
///    unused new file instead.
///
/// So whenever the app stops, the saved record names a whole sketch: the
/// previous one until step 2 is durable, the new one after.
struct ManuscriptSketchEdits {
    struct Replaced: Equatable {
        /// The file the saved record named when editing began.
        let original: String
        /// The newest edit, beside it in Documents.
        var edited: String
    }

    private(set) var replaced: [UUID: Replaced] = [:]

    /// - Parameter currentPath: the file the editor points at for this
    ///   attachment now (the saved one, or an earlier edit made here).
    /// - Returns: the new file's path. Throws, changing nothing, if `data`
    ///   is not a readable sketch or the file cannot be put in place.
    mutating func place(_ data: Data, for id: UUID, currentPath: String) throws -> String {
        _ = try ManuscriptSketchFile.read(data: data)
        let pending = replaced[id]
        let original = pending?.original ?? currentPath
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("sketch-\(UUID().uuidString).pdf", isDirectory: false)
        try data.write(to: temp, options: .atomic)
        let base = URL(fileURLWithPath: original).deletingPathExtension().lastPathComponent
        let newPath: String
        do {
            newPath = try AttachmentStore.adoptTempExport(temp, suggestedName: base.isEmpty ? "Sketch" : base, kind: .pdf)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
        // An earlier edit made in this editor: no saved record ever named it.
        if let pending { AttachmentStore.deleteAttachmentFile(atPath: pending.edited) }
        replaced[id] = Replaced(original: original, edited: newPath)
        return newPath
    }

    /// What the SAVED record for an attachment says after the entry's save.
    enum SavedRecord: Equatable {
        /// The attachment no longer exists.
        case gone
        /// It names this file.
        case names(String)
        /// It exists and what it names could not be worked out.
        case unknown
    }

    /// Call once the entry's save is durable. The previous file of each
    /// edited sketch is removed only when nothing saved names it any more.
    mutating func settleAfterSave(record: (UUID) -> SavedRecord) {
        for (id, entry) in replaced {
            let original = URL(fileURLWithPath: entry.original).standardizedFileURL.path
            switch record(id) {
            case .gone:
                AttachmentStore.deleteAttachmentFile(atPath: entry.original)
            case .names(let path) where URL(fileURLWithPath: path).standardizedFileURL.path != original:
                AttachmentStore.deleteAttachmentFile(atPath: entry.original)
            case .names, .unknown:
                break   // the record still names the previous sketch, or may: it stays
            }
        }
        replaced = [:]
    }

    /// The editor was left without saving: the previous sketches stand.
    mutating func settleAfterCancel() {
        for (_, entry) in replaced { AttachmentStore.deleteAttachmentFile(atPath: entry.edited) }
        replaced = [:]
    }
}

/// The printed paper: staff lines, clefs and the piano brace. One drawing
/// routine for the pad and for the PDF, so what is drawn on is what is saved.
/// Fixed positions: the screen changes the view, never the staves.
enum ManuscriptPaperRenderer {
    static let inset: CGFloat = 48
    static let lineGap: CGFloat = 7
    private static var staffHeight: CGFloat { lineGap * 4 }

    struct Staff: Equatable {
        let top: CGFloat
        let clef: ManuscriptPaper.Clef
    }

    /// Every staff on the page, from the top, with the clef printed on it.
    static func staves(for paper: ManuscriptPaper) -> [Staff] {
        let height = ManuscriptPaper.pageSize.height
        switch paper.kind {
        case .plain:
            return []
        case .singleStaff:
            return stride(from: CGFloat(72), through: height - 72 - staffHeight, by: 70).map { Staff(top: $0, clef: paper.clef) }
        case .piano:
            return stride(from: CGFloat(72), through: height - 72 - 62 - staffHeight, by: 130).flatMap {
                [Staff(top: $0, clef: .treble), Staff(top: $0 + 62, clef: .bass)]
            }
        }
    }

    /// Draws into a context whose origin is the page's top-left corner, y down.
    static func draw(_ paper: ManuscriptPaper, in context: CGContext) {
        let size = ManuscriptPaper.pageSize
        let all = staves(for: paper)
        context.saveGState()
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setStrokeColor(CGColor(gray: 0.25, alpha: 1))
        context.setLineWidth(0.6)
        for staff in all {
            for line in 0..<5 {
                let y = staff.top + CGFloat(line) * lineGap
                context.move(to: CGPoint(x: inset, y: y))
                context.addLine(to: CGPoint(x: size.width - inset, y: y))
            }
        }
        if paper.kind == .piano {
            // Each pair is one system: joined at the left, with a brace.
            for index in stride(from: 0, to: all.count - 1, by: 2) {
                let top = all[index].top, bottom = all[index + 1].top + staffHeight
                context.move(to: CGPoint(x: inset, y: top))
                context.addLine(to: CGPoint(x: inset, y: bottom))
                context.addPath(bracePath(top: top, bottom: bottom))
            }
        }
        // Printed bar lines, through each row: a staff, or both staves of a piano system.
        let bars = barLineXs(for: paper)
        if !bars.isEmpty {
            for row in rows(for: paper) {
                for x in bars {
                    context.move(to: CGPoint(x: x, y: row.top))
                    context.addLine(to: CGPoint(x: x, y: row.bottom))
                }
            }
        }
        context.strokePath()
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        for staff in all {
            if let clef = clefPath(staff.clef, staffTop: staff.top) {
                context.addPath(clef)
                context.fillPath()
            }
        }
        context.restoreGState()
    }

    /// Room kept at the start of a row for its clef before the first bar begins.
    static let clefAllowance: CGFloat = 34

    /// The rows bar lines run through: each staff, or each piano system top to bottom.
    static func rows(for paper: ManuscriptPaper) -> [(top: CGFloat, bottom: CGFloat)] {
        let all = staves(for: paper)
        switch paper.kind {
        case .plain:
            return []
        case .singleStaff:
            return all.map { ($0.top, $0.top + staffHeight) }
        case .piano:
            return stride(from: 0, to: all.count - 1, by: 2).map { (all[$0].top, all[$0 + 1].top + staffHeight) }
        }
    }

    /// Where the printed bar lines fall across the page: the space after the
    /// clef divided evenly, the last line closing the row at its right end.
    /// Empty when the paper has no bars, or no staves to bar.
    static func barLineXs(for paper: ManuscriptPaper) -> [CGFloat] {
        guard paper.kind != .plain, let count = paper.barsPerRow, count == 2 || count == 4 else { return [] }
        let hasClef = paper.kind == .piano || paper.clef != .none
        let start = inset + (hasClef ? clefAllowance : 0)
        let end = ManuscriptPaper.pageSize.width - inset
        return (1...count).map { start + (end - start) * CGFloat($0) / CGFloat(count) }
    }

    private static func bracePath(top: CGFloat, bottom: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let x = inset - 4, half = x - 4, tip = x - 8
        let middle = (top + bottom) / 2, bend = (bottom - top) * 0.1
        path.move(to: CGPoint(x: x, y: top))
        path.addQuadCurve(to: CGPoint(x: half, y: top + bend), control: CGPoint(x: half, y: top))
        path.addLine(to: CGPoint(x: half, y: middle - bend))
        path.addQuadCurve(to: CGPoint(x: tip, y: middle), control: CGPoint(x: half, y: middle))
        path.addQuadCurve(to: CGPoint(x: half, y: middle + bend), control: CGPoint(x: half, y: middle))
        path.addLine(to: CGPoint(x: half, y: bottom - bend))
        path.addQuadCurve(to: CGPoint(x: x, y: bottom), control: CGPoint(x: half, y: bottom))
        return path
    }

    /// The clef's outline from the system's own music symbols, placed on its
    /// staff. Nil for "no clef", or if the system has no such symbol.
    static func clefPath(_ clef: ManuscriptPaper.Clef, staffTop: CGFloat) -> CGPath? {
        let scalar: UInt32, height: CGFloat, above: CGFloat
        switch clef {
        case .none: return nil
        // Sized and placed against printed music, by what each clef points at,
        // not by centring the symbol (staff spaces; checked 2026-11-20):
        // - treble: its loop circles the G line (second from the bottom),
        //   reaching the middle line above and the bottom line below; it
        //   stands about 1.2 spaces above the staff and 1.4 below.
        // - bass: its head sits on the F line (second from the top) under
        //   the top line, with the two dots in the spaces either side of it.
        // - alto: the height of the staff, its centre on the middle line.
        case .treble: scalar = 0x1D11E; height = lineGap * 6.66; above = lineGap * 1.16
        case .bass: scalar = 0x1D122; height = lineGap * 3.3; above = 0
        case .alto: scalar = 0x1D121; height = staffHeight; above = 0
        }
        guard let unicode = UnicodeScalar(scalar) else { return nil }
        let text = String(unicode) as NSString
        let base = CTFontCreateWithName("AppleSymbols" as CFString, 40, nil)
        let font = CTFontCreateForString(base, text, CFRange(location: 0, length: text.length))
        guard (CTFontCopyPostScriptName(font) as String) != "LastResort" else { return nil }
        var characters = Array((text as String).utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count),
              let outline = CTFontCreatePathForGlyph(font, glyphs[0], nil) else { return nil }
        let box = outline.boundingBoxOfPath
        guard box.height > 0 else { return nil }
        let scale = height / box.height
        // A glyph's outline counts upwards; the page counts down.
        var place = CGAffineTransform(translationX: inset + 6 - box.minX * scale, y: staffTop - above + box.maxY * scale)
            .scaledBy(x: scale, y: -scale)
        return outline.copy(using: &place)
    }
}
