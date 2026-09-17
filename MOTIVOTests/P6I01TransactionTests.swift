//
//  P6I01TransactionTests.swift
//  MOTIVOTests
//
//  PHASE 6 · BATCH 1 · P6-I-01 — THE CALLER CONTRACT, EXECUTED.
//
//  `AttachmentCommitTransaction` is the ONE implementation of the
//  commit → save → finalise order, and both editors call it. These tests drive
//  it directly with recording steps, so the ordering rules are observed rather
//  than read out of source text.
//
//  They deliberately do NOT restate the algorithm: each case supplies steps,
//  runs the real `run(_:)`, and asserts what did and did not happen.
//

import XCTest
@testable import Etudes

@MainActor
final class P6I01TransactionTests: XCTestCase {

    private struct Recorder {
        var events: [String] = []
    }

    private func attempt(files: Int, rolledBack: @escaping () -> Void = {}) -> AttachmentCommitAttempt {
        AttachmentCommitAttempt(stagedToFinalID: [:], stagedToFinalURL: [:],
                                committedStagedIDs: (0..<files).map { _ in UUID() },
                                fileRollbacks: (0..<files).map { _ in rolledBack })
    }

    private enum Boom: Error { case write, save }

    // MARK: - A commit failure never reaches the save, and never finalises

    func testCommitFailureSkipsSaveAndFinaliseAndDiscardsTheAttempt() {
        var events: [String] = []
        let outcome = AttachmentCommitTransaction.run(.init(
            commit: { events.append("commit"); throw Boom.write },
            save: { events.append("save") },
            finalise: { _ in events.append("finalise") },
            discardAttempt: { events.append("discard") }
        ))

        XCTAssertEqual(events, ["commit", "discard"],
                       "a failed commit must not reach the save and must not finalise")
        guard case .commitFailed = outcome else { return XCTFail("expected .commitFailed, got \(outcome)") }
    }

    // MARK: - A save failure rolls the attempt's files back, and never finalises

    func testSaveFailureRollsBackFilesAndSkipsFinalise() {
        var events: [String] = []
        var rollbacks = 0
        let a = attempt(files: 3) { rollbacks += 1 }

        let outcome = AttachmentCommitTransaction.run(.init(
            commit: { events.append("commit"); return a },
            save: { events.append("save"); throw Boom.save },
            finalise: { _ in events.append("finalise") },
            discardAttempt: { events.append("discard") }
        ))

        XCTAssertEqual(events, ["commit", "save", "discard"],
                       "a failed save must discard the attempt and must NOT finalise")
        XCTAssertEqual(rollbacks, 3, "every file this attempt wrote must be rolled back")
        guard case .saveFailed = outcome else { return XCTFail("expected .saveFailed, got \(outcome)") }
    }

    // MARK: - Success finalises exactly once and discards nothing

    func testSuccessFinalisesOnceAndNeverDiscards() {
        var events: [String] = []
        var rollbacks = 0
        let a = attempt(files: 2) { rollbacks += 1 }

        let outcome = AttachmentCommitTransaction.run(.init(
            commit: { events.append("commit"); return a },
            save: { events.append("save") },
            finalise: { _ in events.append("finalise") },
            discardAttempt: { events.append("discard") }
        ))

        XCTAssertEqual(events, ["commit", "save", "finalise"],
                       "finalise runs only after a successful save, and nothing is discarded")
        XCTAssertEqual(rollbacks, 0, "a successful save must not delete the media it just saved")
        guard case .committed = outcome else { return XCTFail("expected .committed, got \(outcome)") }
    }

    /// The finalise step receives the attempt the commit produced — this is what
    /// carries `committedStagedIDs`, which the callers use to remove staging.
    func testFinaliseReceivesTheCommittedAttempt() {
        let a = attempt(files: 1)
        var seen: [UUID]?
        _ = AttachmentCommitTransaction.run(.init(
            commit: { a },
            save: {},
            finalise: { seen = $0.committedStagedIDs },
            discardAttempt: {}
        ))
        XCTAssertEqual(seen, a.committedStagedIDs)
    }

    // MARK: - The rollback list is exact and idempotent

    func testRollBackFilesRunsEachRollbackExactlyOnceAcrossRepeatedCalls() {
        var count = 0
        let a = attempt(files: 4) { count += 1 }
        a.rollBackFiles()
        a.rollBackFiles()
        a.rollBackFiles()
        XCTAssertEqual(count, 4, "rollback must be idempotent — a second call must not delete anything again")
    }

    func testEmptyAttemptRollsBackNothing() {
        var count = 0
        let a = attempt(files: 0) { count += 1 }
        a.rollBackFiles()
        XCTAssertEqual(count, 0)
        XCTAssertTrue(a.committedStagedIDs.isEmpty,
                      "an empty attempt must not name any staged id for removal")
    }
}
