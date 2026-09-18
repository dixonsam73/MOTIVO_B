//
//  P6I02OwnershipTests.swift
//  MOTIVOTests
//
//  PHASE 6 · BATCH 2 · UNIT 2a — OWNERSHIP AND THE DISPATCH BOUNDARY.
//
//  THE OWNERSHIP BEHAVIOUR IS IN `P6I02OwnershipBehaviourTests`, executed
//  against the real queue, the real producer and the held URLProtocol stub. An
//  earlier revision of this file asserted that behaviour by SEARCHING PRODUCTION
//  SOURCE for fragments, which proves only that the fragment is present.
//
//  What is left here is the payload's own ownership semantics — executed — plus
//  the two things source is the right instrument for: an ABSENCE (the swallowing
//  load) and a PRESERVATION rule (no symbol deleted by count).
//
//  **CODE ONLY — COMMENT LINES ARE STRIPPED FIRST** (`U5c-34`).
//

import XCTest
@testable import Etudes

final class P6I02OwnershipTests: XCTestCase {

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MOTIVO")
    }
    private func code(_ file: String) -> String {
        let raw = (try? String(contentsOf: sourceRoot.appendingPathComponent(file), encoding: .utf8)) ?? ""
        return raw.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    // MARK: - Behavioural: the payload's ownership semantics

    func testOwnerIsNormalisedAndAbsenceMeansUnknown() {
        let mixed = SessionSyncQueue.PostPublishPayload(
            id: UUID(), sessionID: nil, sessionTimestamp: nil, title: nil, durationSeconds: nil,
            activityType: nil, activityDetail: nil, instrumentLabel: nil, mood: nil, effort: nil,
            ownerUserID: "  AB-CD-Ef  ")
        XCTAssertEqual(mixed.ownerUserID, "ab-cd-ef", "owner ids are compared, so they are normalised once")

        let legacy = SessionSyncQueue.PostPublishPayload(
            id: UUID(), sessionID: nil, sessionTimestamp: nil, title: nil, durationSeconds: nil,
            activityType: nil, activityDetail: nil, instrumentLabel: nil, mood: nil, effort: nil)
        XCTAssertNil(legacy.ownerUserID, "absent must mean UNKNOWN, never the current identity")
    }

    func testWithOwnerBindsACopyAndNormalises() {
        let base = SessionSyncQueue.PostPublishPayload(
            id: UUID(), sessionID: nil, sessionTimestamp: nil, title: nil, durationSeconds: nil,
            activityType: nil, activityDetail: nil, instrumentLabel: nil, mood: nil, effort: nil)
        let bound = base.withOwner("  A-B  ")
        XCTAssertEqual(bound.ownerUserID, "a-b")
        XCTAssertNil(base.ownerUserID, "the original is unchanged")
        XCTAssertEqual(bound.id, base.id)
        XCTAssertEqual(bound.op, base.op)
    }

    /// A legacy file decodes with no owner, and an item written by this build
    /// round-trips its owner. Both directions of the payload format.
    func testOwnerSurvivesEncodeDecodeAndLegacyDecodesAsUnknown() throws {
        let owned = SessionSyncQueue.PostPublishPayload(
            id: UUID(), sessionID: UUID(), sessionTimestamp: Date(timeIntervalSince1970: 1),
            title: "t", durationSeconds: 1, activityType: "core:0", activityDetail: "d",
            instrumentLabel: "i", mood: 1, effort: 1, isPublic: false,
            notes: "n", areNotesPrivate: true, authorisedOmissions: [UUID()], ownerUserID: "owner-a")
        let round = try JSONDecoder().decode(SessionSyncQueue.PostPublishPayload.self,
                                             from: JSONEncoder().encode(owned))
        XCTAssertEqual(round.ownerUserID, "owner-a")
        XCTAssertEqual(round.op, .unshare)
        XCTAssertEqual(round.authorisedOmissions, owned.authorisedOmissions)

        let legacyJSON = #"{"id":"\#(UUID().uuidString)","isPublic":true}"#
        let legacy = try JSONDecoder().decode(SessionSyncQueue.PostPublishPayload.self,
                                              from: Data(legacyJSON.utf8))
        XCTAssertNil(legacy.ownerUserID)
    }

    func testQueueKeyIsolatesOwners() {
        let post = UUID()
        let a = SessionSyncQueue.QueueKey(owner: "a", postID: post)
        let b = SessionSyncQueue.QueueKey(owner: "b", postID: post)
        let unknown = SessionSyncQueue.QueueKey(owner: nil, postID: post)
        XCTAssertNotEqual(a, b, "two identities must not share a revision slot for one post")
        XCTAssertNotEqual(a, unknown)
        XCTAssertEqual(Set([a, b, unknown]).count, 3)
    }

    // MARK: - Structural: only where behaviour cannot reach

    // THE OWNERSHIP AND DISPATCH CASES THAT USED TO LIVE HERE ARE GONE, AND
    // THAT IS THE POINT. Eight of them searched production source for a
    // fragment — capture-before-Task, the dispatch filter, the held item, the
    // quarantine, the acknowledgement rule. A fragment's presence is not the
    // behaviour, and those cases would have passed unchanged against wrong
    // logic around them. They are executed in
    // `P6I02OwnershipBehaviourTests`, against the real queue and the real
    // producer. What remains here is what reading source is the RIGHT
    // instrument for: two absences, and a preservation rule.

    /// No symbol is deleted to satisfy this unit. Each of these is named by an
    /// existing test's assertions, so removing one would change what that test
    /// means — the "no deletion by count" rule.
    func testPreservedEnqueueEntryPointsAreNotDeleted() {
        for symbol in ["func publishIfNeeded(", "func publish(objectID:", "func unpublish(objectID:"] {
            XCTAssertTrue(code("PublishService.swift").contains(symbol),
                          "\(symbol) must be PRESERVED — existing assertions name it")
        }
        XCTAssertTrue(code("FeedInteractionStore.swift").contains("static func markForPublish("),
                      "markForPublish must be preserved")
    }

    /// AN ABSENCE, which no passing behaviour can demonstrate: the swallowing
    /// load is gone. `(try? load) ?? []` read a damaged store as "no pending
    /// work", silently discarding queued publishes and owed withdrawals.
    func testTheSwallowingLoadIsGoneEntirely() {
        let s = code("SessionSyncQueue.swift")
        XCTAssertFalse(s.contains("(try? Self.load(from: fileURL)) ?? []"),
                       "a damaged store must never read as an empty queue")
        XCTAssertFalse(s.contains("try? Self.load"),
                       "the swallowing load must be gone entirely")
        XCTAssertFalse(s.contains("items.removeAll { $0.id == postID }"),
                       "an ownerless removal would cross identities")
    }

    /// The two sign-out paths are wired to the queue. Reaching them
    /// behaviourally would mean driving a real Connected sign-out, which needs
    /// an account; the effect of the call itself is executed in the behavioural
    /// suite.
    func testBothIdentityClearPathsNotifyTheQueue() {
        let auth = code("AuthManager.swift")
        XCTAssertTrue(auth.contains("SessionSyncQueue.shared.noteIdentityChanged(reason: \"signOut\")"))
        XCTAssertTrue(auth.contains("noteIdentityChanged(reason: \"clearConnectedIdentity:"))
    }
}
