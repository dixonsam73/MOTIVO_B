//
//  ImportPathParityTests.swift
//  MOTIVOTests
//
//  PHASE 5 · C-77 — PARITY ACROSS BOTH PRODUCTION IMPORT PATHS.
//
//  **THIS IS THE TEST THAT WOULD HAVE CAUGHT IT.** Unit 1a fixed
//  `AddEditSessionView` and left `PostRecordDetailsView`'s duplicate machinery
//  untouched, so every C-63 and C-74 protection was absent from the second path.
//  Nothing asserted the two behaved alike, and a device import found it instead.
//
//  **THE INVENTORY IS PART OF THE ASSERTION.** `testOnlyTwoImportPathsExist`
//  fails if a third appears, because the real defect was a one-of-N miss rather
//  than any particular line.
//
//  **CODE ONLY — COMMENTS ARE STRIPPED FIRST** (`U5c-34`, six times now).
//

import XCTest
@testable import Etudes

final class ImportPathParityTests: XCTestCase {

    private func code(_ file: String) -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let raw = (try? String(contentsOf: root.appendingPathComponent("MOTIVO/\(file)"), encoding: .utf8)) ?? ""
        return raw
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// Both views, each as (view, its attachments extension).
    private let paths = [("AddEditSessionView.swift", "AddEditSessionView+Attachments.swift"),
                         ("PostRecordDetailsView.swift", "PostRecordDetailsView+Attachments.swift")]

    private func allSource() -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("MOTIVO")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasSuffix(".swift") }.map { code($0) }.joined(separator: "\n")
    }

    /// **THE ONE-OF-N GUARD.** If a third session-attachment import path
    /// appears, this fails and the next person checks parity deliberately.
    func testOnlyTwoImportPathsExist() {
        let s = allSource()
        XCTAssertEqual(s.components(separatedBy: "func stageData(").count - 1, 2,
                       "a new stageData means a new import path — assert its parity here")
        XCTAssertEqual(s.components(separatedBy: "func handleFileImport(").count - 1, 2,
                       "a new handleFileImport means a new import path")
        XCTAssertEqual(s.components(separatedBy: "func kindForURL(").count - 1, 2,
                       "a new kindForURL means a new classifier to keep in step")
    }

    /// Both paths carry the validated format into staging.
    func testBothPathsPropagateSourceFormat() {
        for (_, ext) in paths {
            let s = code(ext)
            XCTAssertTrue(s.contains("sourceFormat: MediaFormat? = nil"),
                          "\(ext): stageData must accept a validated format")
            XCTAssertTrue(s.contains("sourceFormat:") && s.contains("StagedAttachment(id: id, data:"),
                          "\(ext): the staged attachment must carry it")
            XCTAssertTrue(s.contains("AttachmentImportPolicy.classify(fileURL: url)"),
                          "\(ext): import must classify through the shared policy")
        }
    }

    /// Both paths refuse rather than manufacturing a `.file`.
    func testNeitherPathManufacturesAFileAttachment() {
        for (view, ext) in paths {
            let s = code(view) + code(ext)
            XCTAssertFalse(s.contains("stageData(data, kind: .file)"),
                           "\(view): must refuse an unsupported item, not stage it as .file")
            XCTAssertTrue(s.contains("AttachmentImportPolicy.unsupportedFileMessage")
                          || s.contains("AttachmentImportPolicy.unsupportedItemMessage"),
                          "\(view): must present a refusal")
        }
    }

    /// Neither importer may accept arbitrary items.
    func testNeitherImporterAcceptsAnyItem() {
        for (view, _) in paths {
            let s = code(view)
            XCTAssertFalse(s.contains("allowedContentTypes: [.item]"),
                           "\(view): the importer must be narrowed to the deliberate set")
            XCTAssertTrue(s.contains("allowedContentTypes: AttachmentImportPolicy.importerContentTypes"),
                          "\(view): must use the shared allowed set")
        }
    }

    /// Neither classifier may keep its own extension list.
    func testNeitherPathKeepsItsOwnExtensionList() {
        for (_, ext) in paths {
            let s = code(ext)
            XCTAssertTrue(s.contains("AttachmentImportPolicy.kind(forFileURL: url)"),
                          "\(ext): kindForURL must defer to the shared policy")
            for accidental in ["\"gif\"", "\"bmp\"", "\"tiff\"", "\"caf\"", "\"avi\"", "\"m4v\""] {
                XCTAssertFalse(s.contains(accidental),
                               "\(ext): accidental breadth \(accidental) must not survive")
            }
        }
    }

    /// The clamp re-encodes to JPEG, so the declared format must follow the
    /// bytes — otherwise C-74 is reintroduced in a new place.
    func testClampingViewDeclaresJPEGWhenItReencodes() {
        let s = code("PostRecordDetailsView+Attachments.swift")
        XCTAssertTrue(s.contains("wasReencoded"),
                      "a re-encoded image must be declared JPEG, not its original format")
    }
}
