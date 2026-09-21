//
//  C70WiringPinTests.swift
//  MOTIVOTests
//
//  C-70 remaining gaps — the TWO structural pins the scope promised, and no more.
//
//  **These are supporting evidence, never the proof of behaviour.** Behaviour is
//  proved by `C70OwnerMaintenanceTests` (the real gate, storage gate and
//  pre-submit token, driven with counted effects), by
//  `C70DirectoryWriteTransportTests` (the real 401/403 routes against the
//  transport) and by `C70LocalSaveFailureMeasurementTests` (measured Core Data).
//
//  An earlier draft of this file mirrored the implementation in a dozen
//  assertions. Those were trimmed once real coverage existed: a pin that merely
//  restates the code it guards rots into a rename-detector and tells no one
//  anything. What survives is the pair the scope named — the two properties that
//  no value test can reach, because each is about a guard being ABSENT or a
//  global staying UNCHANGED.
//

import XCTest

final class C70WiringPinTests: XCTestCase {

    private func source(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MOTIVO")
        return try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
    }

    /// **Code only.** The sync function's comments deliberately NAME both banned
    /// identifiers, to explain why they are banned — so a raw-text scan would
    /// fail on a correct file. That is the exact trap this project has already
    /// met twice: *a source-text assertion must target code, and a well-commented
    /// file is the one most likely to defeat it.* Same shape as the existing
    /// stripper in `ListsExplicitDefaultTests`.
    private func stripComments(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") || t.hasPrefix("///") { return "" }
                if let r = line.range(of: " //") { return String(line[..<r.lowerBound]) }
                return String(line)
            }.joined(separator: "\n")
    }

    /// The NEAREST following declaration, not the first pattern that happens to
    /// match.
    ///
    /// An earlier version used `?? `, which preferred the five-space spelling
    /// wherever it occurred — even when a four-space one came thousands of
    /// characters sooner. The extracted "body" then over-ran into later
    /// functions, and the pin failed on a correct file because the GENERATION
    /// path legitimately keeps its own `BackendEnvironment` guard. **A source
    /// assertion is only as good as its extraction**, and a false failure here
    /// would have been read as a defect in the code.
    private func body(_ src: String, from: String) throws -> String {
        let start = try XCTUnwrap(src.range(of: from), "missing \(from)")
        let rest = src[start.upperBound...]
        let ends = ["\n     private func ", "\n    private func ", "\n     private var ", "\n    private var "]
            .compactMap { rest.range(of: $0)?.lowerBound }
        guard let nearest = ends.min() else { return String(rest) }
        return String(rest[..<nearest])
    }

    /// **PIN 1 — C-35's shape must not return to the write path under any name.**
    ///
    /// Unreachable by a value test: this asserts the ABSENCE of a guard. The
    /// entitlement dependency arrived here three times without ever appearing as
    /// `isEntitled` — as `canShowConnectedAccountManagement`, as
    /// `BackendEnvironment.isConnected` (which is `AppMode` laundered through the
    /// `backendMode_v1` UserDefaults key), and through `ensureValidSession`.
    func testTheWritePathCarriesNoModeDerivedGuard() throws {
        let raw = try body(try source("ProfileView.swift"),
                           from: "private func syncDirectoryFromCurrentState() async {")
        let code = stripComments(raw)

        // Non-vacuous: the comments DO name both, so a raw scan would fail here
        // on a correct file. If this ever stops holding, the pin below has become
        // a test of nothing and should be re-read rather than trusted.
        XCTAssertTrue(raw.contains("canShowConnectedAccountManagement"),
                      "the explanatory comment should still name what it bans")

        XCTAssertFalse(code.contains("canShowConnectedAccountManagement"),
                       "owner maintenance must gate on identity, never on AppMode")
        XCTAssertFalse(code.contains("BackendEnvironment.shared.isConnected"),
                       "backendMode_v1 is AppMode laundered through UserDefaults — C-35")
    }

    /// **PIN 2 — the blast radius of the C-70 refresh seam stays at zero.**
    ///
    /// Unreachable by a value test: it asserts that something OTHER callers
    /// depend on is unchanged. The global challenge must remain forced.
    ///
    /// **CONVERTED when the handle was removed, and this file was NOT in the
    /// reviewed test boundary — it was found by the full suite, which is the
    /// honest way round.** A second assertion here required
    /// `guard BackendEnvironment.shared.isConnected else { return nil }` in
    /// `AccountDirectoryService`, pinning that automatic handle generation
    /// stayed Connected-only. That guard lived inside
    /// `autoGenerateAccountIDIfMissing`, so it went with the function.
    ///
    /// **The boundary it protected is now stronger, not weaker, and is stated
    /// as what it is:** there is no automatic handle generation left to gate,
    /// anywhere, which `AccountIDRemovalStructureTests` asserts across the whole
    /// source tree. Restated here in this file's own terms so a reader of PIN 2
    /// is not left with a dangling reference to a gate that no longer exists.
    func testTheGlobalChallengeIsUnchangedAndNoGenerationGateRemainsToPin() throws {
        XCTAssertTrue(try source("AuthManager.swift")
            .contains("self.ensureValidSession(reason: \"network-auth-challenge\", force: true)"),
            "the global onAuthChallenge must remain exactly as it was, and forced")
        XCTAssertFalse(try source("AccountDirectoryService.swift")
            .contains("autoGenerateAccountIDIfMissing"),
            "there is no automatic handle generation left for a Connected-only gate to cover")
    }
}
