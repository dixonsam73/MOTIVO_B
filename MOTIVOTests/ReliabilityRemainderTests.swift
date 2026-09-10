//
//  ReliabilityRemainderTests.swift
//  MOTIVOTests
//
//  PHASE 5 · P5-K′ remainder — C-66, C-68, C-69.
//
//  **CODE ONLY — COMMENTS ARE STRIPPED FIRST** (`U5c-34`). Each assertion
//  targets a function BODY or a call, never a declaration it could match on
//  its own (Unit 1b §4).
//

import XCTest
@testable import Etudes

final class ReliabilityRemainderTests: XCTestCase {

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

    /// The body after `signature`, up to the next member declaration at the
    /// four-space member indent.
    private func body(of signature: String, in file: String) -> String? {
        let s = code(file)
        guard let start = s.range(of: signature) else { return nil }
        let rest = s[start.upperBound...]
        let end = rest.range(of: #"\n    (@|(public |private |fileprivate |static )*(func|var|let) )"#,
                             options: .regularExpression)?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    // MARK: - C-66

    /// Every follow mutation refreshes on BOTH outcomes. `unfollow` alone
    /// logged and stopped on failure, so a `.notFound` (row already gone) left
    /// "Following" on screen until some other refresh happened to fire.
    func testEveryFollowMutationRefreshesOnFailure() {
        for fn in ["func declineFollow(", "func removeFollower(", "func unfollow("] {
            guard let b = body(of: fn, in: "FollowStore.swift") else {
                XCTFail("\(fn) not found"); continue
            }
            XCTAssertEqual(b.components(separatedBy: "refreshFromBackendIfPossible()").count - 1, 2,
                           "\(fn): must refresh on success AND on failure")
        }
    }

    // MARK: - C-68

    /// Teardown releases the review player explicitly rather than relying on
    /// the controller being deallocated. Lifecycle hardening only — this does
    /// not explain C-50 and no user-visible failure was reproduced.
    func testRecorderTeardownReleasesTheReviewPlayer() {
        guard let b = body(of: "func onDisappear()", in: "VideoRecorderView.swift") else {
            return XCTFail("VideoRecorderController.onDisappear not found")
        }
        XCTAssertTrue(b.contains("player?.pause()"), "onDisappear must pause the review player")
        XCTAssertTrue(b.contains("player = nil"), "onDisappear must release the review player")
    }

    // MARK: - C-69

    /// Starting remote playback cannot omit the viewer-session rate: the rate
    /// is a required argument, and the one caller passes the session's.
    func testRemotePlaybackRequiresTheSessionRate() {
        let s = code("AttachmentViewerView.swift")
        XCTAssertFalse(s.contains("func toggle(url: URL) {"),
                       "a rate-less toggle lets a freshly created page start at 1×")
        XCTAssertTrue(s.contains("func toggle(url: URL, rate: PlaybackRate)"))
        let calls = s.components(separatedBy: "remoteController.toggle(").count - 1
        let rated = s.components(separatedBy: "remoteController.toggle(url: url, rate: playbackRate)").count - 1
        XCTAssertGreaterThan(calls, 0, "the remote play call site must exist")
        XCTAssertEqual(rated, calls, "every remote play call must pass the session rate")
    }
}
