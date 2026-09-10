//
//  PrivacyLogHygieneTests.swift
//  MOTIVOTests
//
//  PHASE 5 · P5-L / C-62 — A SESSION TITLE IS USER CONTENT, NOT A DIAGNOSTIC.
//
//  `PublishService`'s enqueue line wrote the session title to the unified log
//  in Release. Whether `%@` renders it private was never measured, and was
//  deliberately not measured: the post id already identifies the publish, so
//  the title adds nothing a diagnosis needs. The same line already logs notes
//  only as present/nil — this makes the title follow the rule notes follow.
//
//  **CODE ONLY — COMMENTS ARE STRIPPED FIRST** (`U5c-34`).
//

import XCTest
@testable import Etudes

final class PrivacyLogHygieneTests: XCTestCase {

    private func code(_ file: String) -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let raw = (try? String(contentsOf: root.appendingPathComponent("MOTIVO/\(file)"), encoding: .utf8)) ?? ""
        return raw
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The enqueue log statement, from its format string to the end of its
    /// argument list.
    private func enqueueLogStatement() -> String? {
        let s = code("PublishService.swift")
        guard let start = s.range(of: "enqueue payload keys") else { return nil }
        let rest = s[start.lowerBound...]
        guard let end = rest.range(of: "SessionSyncQueue.shared.enqueue") else { return nil }
        return String(rest[..<end.lowerBound])
    }

    func testPublishEnqueueLogCarriesNoSessionTitle() {
        guard let stmt = enqueueLogStatement() else { return XCTFail("enqueue log line not found") }
        XCTAssertFalse(stmt.contains("title="), "the format string must not log the title")
        XCTAssertFalse(stmt.contains("effectivePayload.title"), "the title must not be passed to the log")
    }

    /// The useful, non-content identifiers stay.
    func testPublishEnqueueLogKeepsItsNonContentDiagnostics() {
        guard let stmt = enqueueLogStatement() else { return XCTFail("enqueue log line not found") }
        for kept in ["postID=", "effectivePayload.id.uuidString", "notes=", "notesPrivate="] {
            XCTAssertTrue(stmt.contains(kept), "must keep \(kept)")
        }
    }
}
