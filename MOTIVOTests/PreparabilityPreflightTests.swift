//
//  PreparabilityPreflightTests.swift
//  MOTIVOTests
//
//  C-73 TYPE 1 — A SHARE-ENABLED ATTACHMENT THAT CAN NEVER BE PREPARED MUST NOT
//  BE QUEUED INTO A PUBLISH THAT CAN NEVER SUCCEED.
//
//  Before this, a locked or page-less PDF, or audio that cannot be decoded,
//  passed the Save-time preflight (it only weighed SIZE), was queued, and failed
//  preparation on every flush forever — with nothing shown to the member. The
//  Save-time check now asks the SAME question the upload asks, and routes a
//  failure through the existing omission consent.
//

import XCTest
import PDFKit
import UIKit
@testable import Etudes

final class PreparabilityPreflightTests: XCTestCase {

    private let limit = AddEditSessionView.publishUploadLimitBytesInt

    private func verdict(_ data: Data, _ kind: AttachmentKind, ext: String) -> ConnectedSharePreflight.Verdict {
        let c = ConnectedSharePreflight.candidate(forStaged: UUID(), data: data, kind: kind,
                                                  sourceFormat: MediaFormat.from(fileExtension: ext))
        return ConnectedSharePreflight.verdict(for: c, limitBytes: limit)
    }

    // MARK: - Fixtures

    private func onePagePDF() -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200)).pdfData { ctx in
            ctx.beginPage()
            UIColor.black.setFill()
            UIRectFill(CGRect(x: 20, y: 20, width: 60, height: 60))
        }
    }

    /// Structurally valid, zero pages — C-65's fixture shape. No page can render.
    private func zeroPagePDF() -> Data {
        Data("%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[]/Count 0>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n".utf8)
    }

    private func lockedPDF() throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("C73-locked-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let doc = try XCTUnwrap(PDFDocument(data: onePagePDF()))
        XCTAssertTrue(doc.write(to: url, withOptions: [.userPasswordOption: "c73-user", .ownerPasswordOption: "c73-owner"]))
        return try Data(contentsOf: url)
    }

    /// A tiny valid PCM WAV: 0.25 s of silence, 8 kHz, 16-bit mono.
    private func validWAV() -> Data {
        let samples = 2000
        var d = Data()
        func le32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func le16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append(Data("RIFF".utf8)); le32(UInt32(36 + samples * 2)); d.append(Data("WAVE".utf8))
        d.append(Data("fmt ".utf8)); le32(16); le16(1); le16(1); le32(8000); le32(16000); le16(2); le16(16)
        d.append(Data("data".utf8)); le32(UInt32(samples * 2)); d.append(Data(count: samples * 2))
        return d
    }

    // MARK: - Tests

    func testZeroPagePDFNeedsConsent() {
        XCTAssertEqual(verdict(zeroPagePDF(), .pdf, ext: "pdf"), .needsConsent,
                       "a PDF with no renderable page can never be prepared for upload")
    }

    /// PARITY, not a guess about PDFKit: the Save verdict must agree with the
    /// renderer the upload uses. Whichever way PDFKit treats a locked page,
    /// the two must never disagree.
    func testLockedPDFVerdictMatchesUploadRendering() throws {
        let data = try lockedPDF()
        let uploadWouldRender = AttachmentStore.generatePDFThumbnail(data: data, cacheKey: "C73-\(UUID().uuidString)") != nil
        XCTAssertEqual(verdict(data, .pdf, ext: "pdf") == .canShare, uploadWouldRender,
                       "the Save-time verdict must match what the upload renderer would do")
    }

    func testUndecodableDerivativeAudioNeedsConsent() {
        XCTAssertEqual(verdict(Data(repeating: 0x42, count: 4096), .audio, ext: "wav"), .needsConsent,
                       "audio that cannot be opened can never be converted for Connected")
    }

    /// Control: ordinary attachments are not caught by the new check.
    func testPreparableAttachmentsStillShare() {
        XCTAssertEqual(verdict(onePagePDF(), .pdf, ext: "pdf"), .canShare)
        XCTAssertEqual(verdict(validWAV(), .audio, ext: "wav"), .canShare)
    }

    /// One place builds candidates, for staged AND persisted attachments.
    func testBothEditorsBuildCandidatesThroughSharedHelpers() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let raw = (try? String(contentsOf: root.appendingPathComponent("MOTIVO/AddEditSessionView+Attachments.swift"),
                               encoding: .utf8)) ?? ""
        let s = raw.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        XCTAssertFalse(s.contains("out.append(.init(id:"),
                       "persisted candidates must not be built inline — that is a second copy of the rules")
        XCTAssertTrue(s.contains("ConnectedSharePreflight.candidate(forPersisted:"))
    }

    /// The dialog now covers more than size, so its title names no cause.
    func testConsentTitleNamesNoCause() {
        for n in [1, 2] {
            XCTAssertFalse(ConnectedSharePreflight.consentTitle(count: n).lowercased().contains("large"),
                           "a locked PDF is not 'too large' — the title must be cause-neutral")
        }
    }
}
