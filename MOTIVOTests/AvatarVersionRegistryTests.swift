//
//  AvatarVersionRegistryTests.swift
//  MOTIVOTests
//
//  PHASE 4 · P4-U5 / C-34 — the avatar version decision function.
//
//  PURE AND NETWORK-FREE, so these belong in this target's stated scope. The
//  registry answers one question — "must the caches be dropped before I fetch
//  this key?" — and every C-34 acceptance claim about churn and refetch reduces
//  to that answer.
//

import XCTest
@testable import Etudes

final class AvatarVersionRegistryTests: XCTestCase {

    /// Acceptance 1: same key + same version must NOT cause repeated refetch churn.
    func testSameKeySameVersionNeverInvalidatesTwice() async {
        let r = RemoteAvatarVersionRegistry()
        let key = "users/u1/avatar.jpg"

        // First sight is deliberately false: nothing is cached under a key this
        // process has never fetched, so invalidating would be a no-op that
        // merely looked meaningful.
        let first = await r.shouldInvalidate(key: key, version: "v1")
        XCTAssertFalse(first, "first sight must not report an invalidation")

        for _ in 0..<5 {
            let again = await r.shouldInvalidate(key: key, version: "v1")
            XCTAssertFalse(again, "an unchanged version must never invalidate — that would be churn")
        }
    }

    /// Acceptance 2: same key + newer version causes EXACTLY ONE new fetch path.
    func testNewerVersionInvalidatesExactlyOnce() async {
        let r = RemoteAvatarVersionRegistry()
        let key = "users/u1/avatar.jpg"

        _ = await r.shouldInvalidate(key: key, version: "v1")

        let onChange = await r.shouldInvalidate(key: key, version: "v2")
        XCTAssertTrue(onChange, "a new version must invalidate")

        for _ in 0..<5 {
            let after = await r.shouldInvalidate(key: key, version: "v2")
            XCTAssertFalse(after, "…and exactly once; the entry is now current")
        }
    }

    /// Acceptance 6: NULL version stays backward-compatible — every one of the
    /// 17 production rows carries NULL today, and none of them may thrash.
    func testNilVersionIsStableAndBackwardCompatible() async {
        let r = RemoteAvatarVersionRegistry()
        let key = "users/legacy/avatar.jpg"

        let first = await r.shouldInvalidate(key: key, version: nil)
        XCTAssertFalse(first, "a NULL version on first sight must not invalidate")

        for _ in 0..<5 {
            let again = await r.shouldInvalidate(key: key, version: nil)
            XCTAssertFalse(again, "NULL -> NULL must be stable, not a repeated invalidation")
        }

        // And the first real stamp after the legacy state DOES invalidate.
        let stamped = await r.shouldInvalidate(key: key, version: "2026-09-05T07:00:00Z")
        XCTAssertTrue(stamped, "the first stamp after NULL must invalidate once")
    }

    /// Keys are independent: one member's replacement must not invalidate another's.
    func testKeysAreIndependent() async {
        let r = RemoteAvatarVersionRegistry()
        _ = await r.shouldInvalidate(key: "users/a/avatar.jpg", version: "v1")
        _ = await r.shouldInvalidate(key: "users/b/avatar.jpg", version: "v1")

        let aChanged = await r.shouldInvalidate(key: "users/a/avatar.jpg", version: "v2")
        let bUnchanged = await r.shouldInvalidate(key: "users/b/avatar.jpg", version: "v1")

        XCTAssertTrue(aChanged, "a's replacement invalidates a")
        XCTAssertFalse(bUnchanged, "…and must not invalidate b")
    }

    /// A version that goes backwards is still a CHANGE. The client is not the
    /// authority on ordering, and refusing to invalidate on a decrease would
    /// serve a stale image after any server-side correction.
    func testAnyDifferenceInvalidatesIncludingGoingBackwards() async {
        let r = RemoteAvatarVersionRegistry()
        let key = "users/u1/avatar.jpg"
        _ = await r.shouldInvalidate(key: key, version: "v2")
        let backwards = await r.shouldInvalidate(key: key, version: "v1")
        XCTAssertTrue(backwards, "any difference invalidates; the client does not adjudicate ordering")
    }
}
