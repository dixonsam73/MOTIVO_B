//
//  AppSetUpGateBodyFetchTests.swift
//  MOTIVOTests
//
//  PHASE 5 · C-56 — the durable control.
//
//  **IT ASSERTS THE ABSENCE OF THE DEFECT, NOT THE PRESENCE OF THE FIX.**
//  P5-M's lesson: a test that checks the fix is there passes while a second
//  unfixed path ships. So this asserts that the AppSetUp-gate declarations
//  evaluated during `PracticeTimerView.body` issue NO Core Data read at all.
//
//  **CODE ONLY — COMMENTS ARE STRIPPED FIRST.** `U5c-34`, and twice since: a
//  file that explains its own rule in a comment is exactly the file most
//  likely to defeat a source-text assertion for that rule.
//
//  **STATED LIMITATION.** The scope is the six named declarations below, which
//  are the ones the C-56 census found reachable as value expressions during a
//  body evaluation. It will NOT catch a body-time fetch introduced through some
//  new helper, and it must not be described as proving `body` is fetch-free in
//  general. `testBodyItselfContainsNoDirectFetch` covers the inline case only.
//

import XCTest
@testable import Etudes

final class AppSetUpGateBodyFetchTests: XCTestCase {

    /// The declarations the C-56 census found to be evaluated DURING a body
    /// evaluation — the two gate predicates, the two key strings, the
    /// `.task(id:)` key they compose, and the home top bar.
    ///
    /// `fetchInstruments()` is deliberately NOT in this set: it is legitimate
    /// from event handlers such as `refreshInstrumentSelectionFromStore()`, and
    /// what this unit forbids is reaching it from a body-time expression.
    private static let bodyTimeDeclarations = [
        "private func requiresAppSetUpNow() -> Bool {",
        "private var appSetUpCompletenessKey: String {",
        "private var appSetUpBootstrapStateKey: String {",
        "private var shouldRenderAppSetUpRoot: Bool {",
        "private var launchGateEvaluationKey: String {",
        "private var homeTopBar: some View {",
    ]

    private func timerViewCode() -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let raw = (try? String(contentsOf: root.appendingPathComponent("MOTIVO/PracticeTimerView.swift"), encoding: .utf8)) ?? ""
        return raw
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The text of one member declaration: from its signature to the next
    /// member declaration at the same indentation.
    private func declarationBody(_ signature: String, in source: String) -> String? {
        guard let start = source.range(of: signature) else { return nil }
        let rest = source[start.upperBound...]
        let terminators = ["\n    private func ", "\n    private var ", "\n    func ", "\n    var ",
                           "\n    @ViewBuilder", "\n    @MainActor", "\n    private static ", "\n    static "]
        var end = rest.endIndex
        for t in terminators {
            if let r = rest.range(of: t), r.lowerBound < end { end = r.lowerBound }
        }
        return String(rest[rest.startIndex..<end])
    }

    /// NON-VACUITY: every declaration this test scopes itself to must still
    /// exist. If one is renamed away, the test fails rather than quietly
    /// scanning nothing.
    func testEveryScopedDeclarationStillExists() {
        let source = timerViewCode()
        XCTAssertFalse(source.isEmpty, "PracticeTimerView.swift must be readable")
        for signature in Self.bodyTimeDeclarations {
            XCTAssertNotNil(declarationBody(signature, in: source),
                            "scoped declaration has moved or been renamed: \(signature)")
        }
    }

    /// THE CONTROL. Zero Core Data reads from any body-time declaration —
    /// neither a direct `viewContext.fetch` nor a call to a helper that fetches.
    func testNoBodyTimeDeclarationReadsCoreData() {
        let source = timerViewCode()
        var offenders: [String] = []

        for signature in Self.bodyTimeDeclarations {
            guard let decl = declarationBody(signature, in: source) else { continue }
            for probe in ["viewContext.fetch", "fetchInstruments(", "fetchPrimaryInstrumentName(", "NSFetchRequest"] {
                if decl.contains(probe) {
                    offenders.append("\(signature.trimmingCharacters(in: .whitespaces)) → \(probe)")
                }
            }
        }

        XCTAssertTrue(offenders.isEmpty,
                      "body-time Core Data reads must be zero; found:\n" + offenders.joined(separator: "\n"))
    }

    /// `body`'s own inline expressions must not fetch either.
    func testBodyItselfContainsNoDirectFetch() {
        let source = timerViewCode()
        guard let start = source.range(of: "\n    var body: some View {") else {
            return XCTFail("PracticeTimerView.body not found")
        }
        let rest = source[start.upperBound...]
        let end = rest.range(of: "\n    private func ")?.lowerBound ?? rest.endIndex
        let body = String(rest[rest.startIndex..<end])
        XCTAssertFalse(body.contains("viewContext.fetch"), "body must issue no Core Data fetch inline")
    }
}
