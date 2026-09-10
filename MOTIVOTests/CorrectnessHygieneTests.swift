//
//  CorrectnessHygieneTests.swift
//  MOTIVOTests
//
//  PHASE 5 · P5-J′ — C-16 and C-20.
//
//  **CODE ONLY — COMMENTS ARE STRIPPED FIRST** (`U5c-34`).
//

import XCTest
import CoreData
@testable import Etudes

final class CorrectnessHygieneTests: XCTestCase {

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MOTIVO")
    }

    private func code(_ file: String) -> String {
        let raw = (try? String(contentsOf: sourceRoot.appendingPathComponent(file), encoding: .utf8)) ?? ""
        return raw
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    // MARK: - C-16

    /// A launch-reachable `try!` turns a recoverable filesystem error into a
    /// crash. There was exactly one in app source (`SessionSyncQueue`).
    func testNoForceTryInAppSource() {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: sourceRoot.path)) ?? [])
            .filter { $0.hasSuffix(".swift") }
        let offenders = files.filter { code($0).contains("try!") }
        XCTAssertTrue(offenders.isEmpty, "try! in app source: \(offenders)")
    }

    // MARK: - C-20

    /// The body of `publishLocalProfileSnapshotToDirectoryIfPossible`, to the
    /// next member function.
    private func snapshotPublishBody() -> String? {
        let s = code("AuthManager.swift")
        guard let start = s.range(of: "func publishLocalProfileSnapshotToDirectoryIfPossible(") else { return nil }
        let rest = s[start.upperBound...]
        let end = rest.range(of: #"\n    (private |fileprivate |internal |public )?(static )?func "#,
                             options: .regularExpression)?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    /// `performAndWait` takes a `@Sendable` block, so main-actor state reached
    /// inside it is a static isolation crossing Swift 6 rejects. On the main
    /// actor with a main-queue context the wrapper is redundant — so the
    /// crossing should not exist at all, rather than be asserted away.
    func testProfileSnapshotPublishHasNoIsolationCrossing() {
        guard let body = snapshotPublishBody() else { return XCTFail("function not found") }
        XCTAssertFalse(body.contains("performAndWait"),
                       "the snapshot read runs on the main actor; the Sendable performAndWait wrapper is redundant")
    }

    /// PREMISE 1 of removing the wrapper: the function is main-actor isolated.
    func testAuthManagerIsMainActorIsolated() {
        XCTAssertTrue(code("AuthManager.swift").contains("@MainActor\nfinal class AuthManager"))
    }

    /// PREMISE 2: `viewContext` is the MAIN-QUEUE context, so direct access on
    /// the main actor is exactly what `performAndWait` would have done.
    /// Measured, because the SDK header does not state it.
    @MainActor
    func testViewContextIsMainQueue() {
        XCTAssertEqual(PersistenceController.shared.container.viewContext.concurrencyType,
                       .mainQueueConcurrencyType)
    }
}
