// CHANGE-ID: 20260920_HandleRemoval_StructureAndCompatibility
// SCOPE: Structural guards that the handle stays removed, plus the compatibility
// assertion that a server payload still carrying `account_id` decodes.
// SEARCH-TOKEN: 20260920_HandleRemoval_StructureAndCompatibility

import XCTest
@testable import Etudes

/// **These read SOURCE TEXT. They prove WIRING, not rendering.**
///
/// A passing assertion here establishes that a call site passes — or does not
/// pass — a particular value. It establishes nothing about what SwiftUI drew;
/// no test in this target renders a view. Described that way deliberately,
/// because a structural test that is described as a rendering test is a claim
/// nobody made.
final class AccountIDRemovalStructureTests: XCTestCase {

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MOTIVO")
    }

    private func swiftSources() -> [(name: String, text: String)] {
        let root = sourceRoot()
        let urls = (try? FileManager.default.contentsOfDirectory(at: root,
                                                                 includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "swift" }
            .compactMap { url in
                guard let t = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return (url.lastPathComponent, t)
            }
    }

    /// Strips `//` line comments so a comment EXPLAINING the removal cannot
    /// satisfy a check FOR the removal. U5d met this exact trap twice: the file
    /// documenting a rule defeated the assertion for the rule.
    private func stripComments(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let r = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<r.lowerBound])
            }
            .joined(separator: "\n")
    }

    func testSourcesWereFound() {
        XCTAssertGreaterThan(swiftSources().count, 50,
                             "the sweep below is vacuous if it reads no files")
    }

    // MARK: - Generation cannot be reintroduced quietly

    func testNoHandleGenerationEntryPointSurvives() {
        for (name, text) in swiftSources() {
            let code = stripComments(text)
            for banned in ["autoGenerateAccountIDIfMissing",
                           "autoAccountIDBase",
                           "autoAccountIDCandidate",
                           "scheduleAccountIDBackfillIfNeeded",
                           "attemptAccountIDAutoGenerationIfNeeded",
                           "performGenerationWrite"] {
                XCTAssertFalse(code.contains(banned), "\(banned) survives in \(name)")
            }
        }
    }

    func testNothingWritesTheLocalHandleStore() {
        for (name, text) in swiftSources() {
            let code = stripComments(text)
            XCTAssertFalse(code.contains("ProfileStore.setAccountID"),
                           "the local handle store must have no writer (\(name))")
            XCTAssertFalse(code.contains("ProfileStore.accountID("),
                           "the local handle store must have no reader (\(name))")
        }
    }

    // MARK: - No handle reaches a member's screen

    /// The `@handle` render sites were `Text("@\(handle)")` and
    /// `overrideSubtitle: …accountID.map { "@\($0)" }`. Neither shape may return.
    func testNoHandleIsRenderedAnywhere() {
        for (name, text) in swiftSources() {
            let code = stripComments(text)
            XCTAssertFalse(code.contains("accountID.map"),
                           "a handle is being mapped into display text in \(name)")
            XCTAssertFalse(code.contains("directoryAccountID"),
                           "the handle display parameter survives in \(name)")
        }
    }

    /// `DirectorySubtitle` is the only thing allowed to compose that line, and
    /// it has no access to `accountID`.
    func testTheSubtitleFormatterCannotSeeAHandle() {
        let root = sourceRoot().appendingPathComponent("PeopleUserRow.swift")
        let text = (try? String(contentsOf: root, encoding: .utf8)) ?? ""
        XCTAssertFalse(text.isEmpty, "PeopleUserRow.swift not found")
        guard let start = text.range(of: "public enum DirectorySubtitle {"),
              let end = text.range(of: "/// Shared row for People hub:") else {
            return XCTFail("DirectorySubtitle not found where expected")
        }
        let body = stripComments(String(text[start.lowerBound..<end.lowerBound]))
        XCTAssertFalse(body.contains("accountID"),
                       "the subtitle formatter must not read the handle")
    }

    // MARK: - The five non-handle subtitles are not swept up

    /// Each of these is a DIFFERENT caller's own string, not an identity line.
    /// A sweep that replaced every `overrideSubtitle:` would have silently
    /// replaced them too, and each names something the row genuinely is.
    func testTheNonHandleSubtitleOverridesStillPassTheirOwnStrings() {
        let expected: [(file: String, needle: String)] = [
            ("PeopleView.swift", "overrideSubtitle: attachment.attachmentName ?? attachment.filename,"),
            ("PeopleView.swift", "overrideSubtitle: \"Shared a post\","),
            ("PeopleView.swift", "overrideSubtitle: subtitle,"),
            ("FollowingListView.swift", "overrideSubtitle: \"\\(ensemble.memberUserIDs.count) \""),
            ("ConnectedAttachmentShareUI.swift", "overrideSubtitle: \"\\(recipients.count) \""),
        ]
        for (file, needle) in expected {
            let text = (try? String(contentsOf: sourceRoot().appendingPathComponent(file),
                                    encoding: .utf8)) ?? ""
            XCTAssertTrue(text.contains(needle),
                          "\(file) lost a non-handle subtitle: \(needle)")
        }
    }

    /// And every identity row now passes the formatter — eight of them.
    func testEveryIdentityRowPassesTheFormatter() {
        var total = 0
        for (_, text) in swiftSources() {
            total += stripComments(text).components(separatedBy: "DirectorySubtitle.text(for:").count - 1
        }
        XCTAssertEqual(total, 8, "the eight identity rows must all pass the formatter")
    }

    // MARK: - C-70's maintenance feedback surface survives

    /// **The single most likely mistake in this change.** The Account ID field
    /// and the directory-sync failure message sat behind the SAME
    /// `mayShowMaintenanceSurface` flag in two SEPARATE blocks. Removing the
    /// wrong one would take C-70's whole reason for existing with it: a lapsed
    /// member maintaining an existing Connected profile must still be able to
    /// see that the publish failed.
    func testTheDirectorySyncFailureSurfaceStillExists() {
        let text = (try? String(contentsOf: sourceRoot().appendingPathComponent("ProfileView.swift"),
                                encoding: .utf8)) ?? ""
        let code = stripComments(text)
        XCTAssertTrue(code.contains("if mayShowMaintenanceSurface, let msg = directorySyncMessage {"),
                      "C-70's maintenance feedback surface must survive the field's removal")
        XCTAssertTrue(code.contains("ensureValidBackendSession(reason: \"profile-maintenance\", force: true)"),
                      "the scoped 401 handler is owner maintenance's, not the handle's")
        XCTAssertTrue(code.contains("localStorageIsUsable"),
                      "the local-storage guard is unrelated to the handle and must remain")
        XCTAssertTrue(code.contains("Retry saving your profile"),
                      "the local-save retry is unrelated to the handle and must remain")
    }

    // MARK: - The placeholder mention affordance

    func testTheMentionPlaceholderIsGone() {
        let text = (try? String(contentsOf: sourceRoot().appendingPathComponent("CommentsView.swift"),
                                encoding: .utf8)) ?? ""
        let code = stripComments(text)
        for banned in ["tokenizeMentions", "MentionSpan", "tappedMention", "mentionStyledText"] {
            XCTAssertFalse(code.contains(banned), "\(banned) survives in CommentsView")
        }
        XCTAssertTrue(code.contains("Text(comment.text)"),
                      "comment TEXT is untouched and still rendered verbatim")
        XCTAssertTrue(code.contains("Text(row.body)"),
                      "response body text is untouched and still rendered verbatim")
    }
}

/// Compatibility with what the SERVER still sends.
///
/// `account_id` is still a deployed column and both directory RPCs still return
/// it. Nothing in this change may make a payload carrying it fail to decode.
final class AccountIDCompatibilityTests: XCTestCase {

    private func decode(_ json: String) throws -> [DirectoryAccount] {
        try JSONDecoder().decode([DirectoryAccount].self, from: Data(json.utf8))
    }

    func testAPayloadCarryingAHandleStillDecodes() throws {
        let rows = try decode("""
        [{"user_id":"11111111-1111-1111-1111-111111111111","account_id":"adalovelace",
          "display_name":"Ada","location":"London","avatar_key":null,
          "avatar_version":null,"instruments":["Cello"]}]
        """)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].accountID, "adalovelace",
                       "the column is still decoded; it is simply never rendered or written")
        XCTAssertEqual(DirectorySubtitle.text(for: rows[0]), "Cello · London")
    }

    func testAPayloadWithANullHandleStillDecodes() throws {
        let rows = try decode("""
        [{"user_id":"11111111-1111-1111-1111-111111111111","account_id":null,
          "display_name":"Ada","location":null,"avatar_key":null,
          "avatar_version":null,"instruments":null}]
        """)
        XCTAssertNil(rows[0].accountID)
        XCTAssertNil(DirectorySubtitle.text(for: rows[0]))
    }

    /// The owner's own row comes back through a different type on a different
    /// path, and it must tolerate the column too.
    func testTheOwnerSelfRowStillDecodesAHandle() throws {
        let rows = try JSONDecoder().decode([SelfDirectoryRow].self, from: Data("""
        [{"user_id":"11111111-1111-1111-1111-111111111111","account_id":"adalovelace",
          "display_name":"Ada","location":"London","instruments":["Cello"],
          "lookup_enabled":true,"follow_requests_enabled":true,
          "avatar_key":null,"avatar_version":null}]
        """.utf8))
        XCTAssertEqual(rows[0].accountID, "adalovelace")
    }

    /// The response-shape contract is deliberately UNCHANGED: one list builds
    /// `select=` and requires the response keys, so churning it would move
    /// C-70's evidence machinery for no behavioural gain.
    func testTheWriteStillSelectsBackTheHandleColumn() {
        XCTAssertTrue(DirectoryWriteEvidence.selectedColumns.contains("account_id"),
                      "the select list is unchanged; the PAYLOAD is what stopped carrying it")
    }

    /// And a payload that does not carry the key derives no expectation for it,
    /// which is why `DirectoryWriteOutcome` needed no change at all.
    func testAPayloadWithoutTheKeyDerivesNoHandleExpectation() {
        let e = DirectoryWriteEvidence.expectation(from: ["display_name": "Ada"])
        XCTAssertEqual(e, [.displayName("Ada")])
    }
}
