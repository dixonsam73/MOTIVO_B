//
//  AvatarFreshnessTests.swift
//  MOTIVOTests
//
//  PHASE 5 · P5-I / C-34 — THE VERSION SIGNAL MUST ACTUALLY ARRIVE.
//
//  Phase 4 made the image cache version-aware, but the version travels in a
//  directory row, and that row was cached for the whole process: other members'
//  devices only saw a replacement after relaunch (R1). And the owner's own
//  second device never saw it at all — a local file won before the backend was
//  consulted, keyed on an avatar key that never changes (R2).
//
//  **CODE ONLY — COMMENTS ARE STRIPPED FIRST** (`U5c-34`). Each assertion is
//  scoped to the function or struct it is about: `DirectoryAccount` already
//  decodes `avatar_version`, so a file-wide search would pass on nothing.
//

import XCTest
@testable import Etudes

final class AvatarFreshnessTests: XCTestCase {

    private func code(_ file: String) -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let raw = (try? String(contentsOf: root.appendingPathComponent("MOTIVO/\(file)"), encoding: .utf8)) ?? ""
        return raw.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func slice(_ file: String, from start: String, length: Int) -> String? {
        let s = code(file)
        guard let r = s.range(of: start) else { return nil }
        return String(s[r.lowerBound...].prefix(length))
    }

    // MARK: - R1

    /// Directory rows expire, so a new `avatar_version` reaches every site.
    func testDirectoryCacheExpires() {
        let s = code("AccountDirectoryService.swift")
        XCTAssertTrue(s.contains("directoryCacheTTL"), "the directory cache needs an expiry")
        guard let body = slice("AccountDirectoryService.swift", from: "func resolveAccounts(", length: 2500) else {
            return XCTFail("resolveAccounts not found")
        }
        XCTAssertTrue(body.contains("idsNeedingFetch("), "expired rows must be refetched, not only absent ones")
    }

    // MARK: - R2 / B1

    /// The owner's own row carries the version — scoped, because `DirectoryAccount`
    /// already decodes it.
    func testSelfRowReadsAvatarVersion() {
        guard let row = slice("AccountDirectoryService.swift", from: "public struct SelfDirectoryRow", length: 1200),
              let fetch = slice("AccountDirectoryService.swift", from: "func fetchSelfRow(", length: 700) else {
            return XCTFail("SelfDirectoryRow / fetchSelfRow not found")
        }
        XCTAssertTrue(row.contains("case avatarVersion = \"avatar_version\""), "the self row must decode avatar_version")
        XCTAssertTrue(fetch.contains("avatar_version"), "fetchSelfRow must select avatar_version")
    }

    /// Hydration hands the self row's version to the own-avatar sync — a CALL,
    /// not merely the declaration.
    func testHydrationSyncsOwnAvatarFromBackend() {
        let calls = code("AuthManager.swift").components(separatedBy: .newlines)
            .filter { $0.contains("syncOwnAvatarFromBackend(") && !$0.contains("func syncOwnAvatarFromBackend(") }
        XCTAssertFalse(calls.isEmpty, "self-row hydration must reconcile the owner's local avatar copy")
    }

    /// The Profile redraws when the local copy is replaced — its trigger used to
    /// be keyed only on an avatar key that never changes.
    func testProfileAvatarRedrawsWhenOwnAvatarIsReplaced() {
        guard let trigger = slice("ProfileView.swift", from: "private var avatarRefreshTrigger: String {", length: 400) else {
            return XCTFail("avatarRefreshTrigger not found")
        }
        XCTAssertTrue(trigger.contains("ownAvatarRevision"), "the Profile must redraw when the own avatar is replaced")
    }

    // MARK: - Behavioural

    /// Absent and expired rows are fetched; fresh rows are not; forcing fetches all.
    func testExpiredDirectoryRowsAreRefetched() {
        let now = Date()
        let ttl = AccountDirectoryService.directoryCacheTTL
        XCTAssertEqual(ttl, 20 * 60, "consistent with CommentPresenceStore's comparable cache")
        let fetchedAt: [String: Date] = [
            "fresh": now.addingTimeInterval(-(ttl - 60)),
            "expired": now.addingTimeInterval(-(ttl + 60))
        ]
        let requested = ["fresh", "expired", "absent"]
        XCTAssertEqual(AccountDirectoryService.idsNeedingFetch(requested: requested, fetchedAt: fetchedAt,
                                                               now: now, ttl: ttl, forceRefresh: false),
                       ["expired", "absent"])
        XCTAssertEqual(AccountDirectoryService.idsNeedingFetch(requested: requested, fetchedAt: fetchedAt,
                                                               now: now, ttl: ttl, forceRefresh: true),
                       requested)
    }

    /// B1's whole rule, row by row.
    func testOwnAvatarSyncDecisionTable() {
        typealias S = OwnAvatarSync
        // An unsynced local change is never overwritten, whatever the backend says.
        XCTAssertEqual(S.decide(lastApplied: "v1", backendVersion: "v2", backendHasAvatar: true, hasPendingLocalChange: true), .none)
        XCTAssertEqual(S.decide(lastApplied: nil, backendVersion: nil, backendHasAvatar: false, hasPendingLocalChange: true), .none)
        // First sight: refresh a present avatar; never delete on an absent one.
        XCTAssertEqual(S.decide(lastApplied: nil, backendVersion: "v1", backendHasAvatar: true, hasPendingLocalChange: false), .refresh)
        XCTAssertEqual(S.decide(lastApplied: nil, backendVersion: nil, backendHasAvatar: true, hasPendingLocalChange: false), .refresh)
        XCTAssertEqual(S.decide(lastApplied: nil, backendVersion: nil, backendHasAvatar: false, hasPendingLocalChange: false), .recordOnly)
        // Unchanged: nothing.
        XCTAssertEqual(S.decide(lastApplied: "v1", backendVersion: "v1", backendHasAvatar: true, hasPendingLocalChange: false), .none)
        XCTAssertEqual(S.decide(lastApplied: "", backendVersion: nil, backendHasAvatar: true, hasPendingLocalChange: false), .none)
        // Changed: follow the backend — replace, or remove if it was removed.
        XCTAssertEqual(S.decide(lastApplied: "v1", backendVersion: "v2", backendHasAvatar: true, hasPendingLocalChange: false), .refresh)
        XCTAssertEqual(S.decide(lastApplied: "v1", backendVersion: "v2", backendHasAvatar: false, hasPendingLocalChange: false), .remove)
    }
}
