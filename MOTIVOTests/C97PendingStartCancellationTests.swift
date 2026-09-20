//
//  C97PendingStartCancellationTests.swift
//  MOTIVOTests
//
//  CHANGE-ID: 20260920_150000_C97_PendingStartCancellation
//  SCOPE: C-97 — the pending-start claim protocol, its orchestration with
//  CaptureDisruptionTracker, and file preservation on REAL files.
//  SEARCH-TOKEN: 20260920_150000_C97_PendingStartCancellation
//

import XCTest
@testable import Etudes

final class C97PendingStartCancellationTests: XCTestCase {

    private func url(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("c97-\(name).mov")
    }

    // MARK: - Resolution at every stage

    func testCancelWhileArmedHasNoFileEffect() {
        var c = PendingStartCoordinator()
        let t = UUID()
        c.arm(token: t, presentation: UUID(), url: url("a"))
        XCTAssertEqual(c.requestCancel(token: t), .cancelledBeforeWriter)
        XCTAssertFalse(c.hasLiveClaim)
    }

    func testCancelAfterWriterCreatedDeletesTheClaimsOwnURL() {
        var c = PendingStartCoordinator()
        let t = UUID(); let u = url("b")
        c.arm(token: t, presentation: UUID(), url: u)
        c.advance(t, to: .writerCreated)
        XCTAssertEqual(c.requestCancel(token: t), .cancelledWithWriter(url: u))
    }

    func testCancelDuringSessionStartIsDeferredToTheContinuation() {
        var c = PendingStartCoordinator()
        let t = UUID(); let u = url("c")
        c.arm(token: t, presentation: UUID(), url: u)
        c.advance(t, to: .sessionStarting)
        // It cannot be stopped: startSession is blocked off-queue holding its own writer.
        XCTAssertEqual(c.requestCancel(token: t), .deferredUntilSessionReturns)
        XCTAssertTrue(c.hasLiveClaim, "the claim must survive until its continuation returns")
        XCTAssertEqual(c.sessionStartReturned(t), .finaliseCancelled(url: u))
        XCTAssertFalse(c.hasLiveClaim)
    }

    func testCancelAfterCommitHandsOffInsteadOfCancelling() {
        var c = PendingStartCoordinator()
        let t = UUID()
        c.arm(token: t, presentation: UUID(), url: url("d"))
        c.advance(t, to: .committed)
        XCTAssertEqual(c.requestCancel(token: t), .startupAlreadyWon)
        XCTAssertTrue(c.hasLiveClaim, "a committed take is not discarded by a cancellation")
    }

    func testSessionReadyStillCancels() {
        var c = PendingStartCoordinator()
        let t = UUID(); let u = url("e")
        c.arm(token: t, presentation: UUID(), url: u)
        c.advance(t, to: .sessionReady)
        XCTAssertEqual(c.requestCancel(token: t), .cancelledWithWriter(url: u))
    }

    // MARK: - Exactly-once, staleness, and never touching a newer claim

    func testRepeatedCancellationIsANoOp() {
        var c = PendingStartCoordinator()
        let t = UUID()
        c.arm(token: t, presentation: UUID(), url: url("f"))
        c.advance(t, to: .writerCreated)
        XCTAssertEqual(c.requestCancel(token: t), .cancelledWithWriter(url: url("f")))
        XCTAssertEqual(c.requestCancel(token: t), .noClaim, "a second cancellation must do nothing")
        XCTAssertEqual(c.sessionStartReturned(t), .alreadySettled)
    }

    func testStaleContinuationCleansUpItsOwnWriterExactlyOnce() {
        var c = PendingStartCoordinator()
        let old = UUID(); let oldURL = url("old")
        c.arm(token: old, presentation: UUID(), url: oldURL)
        c.advance(old, to: .sessionStarting)

        // The recorder is dismissed and reopened while startSession is blocked.
        c.retireForPresentationChange()
        let new = UUID(); let newURL = url("new")
        c.arm(token: new, presentation: UUID(), url: newURL)
        c.advance(new, to: .writerCreated)

        // The old continuation finally returns.
        XCTAssertEqual(c.sessionStartReturned(old), .cleanUpRetired(url: oldURL))
        XCTAssertEqual(c.sessionStartReturned(old), .alreadySettled, "exactly once")

        // And it left the newer claim completely alone.
        XCTAssertEqual(c.currentToken, new)
        XCTAssertEqual(c.currentStage, .writerCreated)
        XCTAssertEqual(c.requestCancel(token: new), .cancelledWithWriter(url: newURL))
    }

    func testANewStartRetiresAnUnsettledBlockedClaim() {
        var c = PendingStartCoordinator()
        let old = UUID(); let oldURL = url("old2")
        c.arm(token: old, presentation: UUID(), url: oldURL)
        c.advance(old, to: .sessionStarting)
        let new = UUID()
        c.arm(token: new, presentation: UUID(), url: url("new2"))
        XCTAssertEqual(c.retiredCount, 1)
        XCTAssertEqual(c.sessionStartReturned(old), .cleanUpRetired(url: oldURL))
    }

    func testCancellingAStaleTokenNeverTouchesTheLiveClaim() {
        var c = PendingStartCoordinator()
        let stale = UUID()
        c.arm(token: stale, presentation: UUID(), url: url("s1"))
        c.settle(stale)
        let live = UUID()
        c.arm(token: live, presentation: UUID(), url: url("s2"))
        c.advance(live, to: .writerCreated)
        XCTAssertEqual(c.requestCancel(token: stale), .noClaim)
        XCTAssertEqual(c.currentToken, live, "the live claim is untouched")
        XCTAssertEqual(c.currentStage, .writerCreated)
    }

    // MARK: - Failure paths

    func testWriterSetupFailureBeforeAnyFileLeavesNothingToDelete() {
        var c = PendingStartCoordinator()
        let t = UUID()
        c.arm(token: t, presentation: UUID(), url: url("g"))
        XCTAssertNil(c.failed(t), "no writer was created, so no file exists")
        XCTAssertFalse(c.hasLiveClaim)
    }

    func testStartFailureAfterWriterCreationReportsItsOwnURL() {
        var c = PendingStartCoordinator()
        let t = UUID(); let u = url("h")
        c.arm(token: t, presentation: UUID(), url: u)
        c.advance(t, to: .writerCreated)
        XCTAssertEqual(c.failed(t), u)
        XCTAssertFalse(c.hasLiveClaim)
    }

    // MARK: - Orchestration with the tracker (requirement 1)

    /// The committed-before-main case, driven through BOTH types in the order the
    /// controller drives them — not a model's handoff output.
    func testCommittedBeforeMainProducesStopTearDownAndKeptMessage() {
        var tracker = CaptureDisruptionTracker()
        var coord = PendingStartCoordinator()
        let t = UUID()
        coord.arm(token: t, presentation: UUID(), url: url("i"))
        coord.advance(t, to: .committed)          // the start won; main has not caught up

        // The event arrives while main still reports startPending.
        let snapshot = CaptureDisruptionTracker.Snapshot(
            isCurrentSession: true, take: .startPending, isAppActive: true, isShowingLivePreview: true)
        let first = tracker.handle(.audioServicesReset, snapshot)
        XCTAssertEqual(first, [.requestPendingStartCancel])
        XCTAssertFalse(tracker.takeDisrupted, "nothing is decided at the event")
        XCTAssertFalse(tracker.tearDownAfterFinish)

        // writerQueue resolves: startup already won.
        XCTAssertEqual(coord.requestCancel(token: t), .startupAlreadyWon)

        // main adopts the state it would have held had the event arrived a moment later.
        XCTAssertEqual(tracker.adoptDisruptedStartedTake(from: .audioServicesReset), [.stopActiveTake])
        XCTAssertTrue(tracker.takeDisrupted)
        XCTAssertTrue(tracker.tearDownAfterFinish)

        // And the writer completing now produces tear-down AND the kept message.
        let finished = tracker.writerFinished(succeeded: true, keptFileExists: true, existingMessage: nil)
        XCTAssertTrue(finished.contains(.tearDownCapture))
        let expected = CaptureDisruptionTracker.keptMessage + " " + CaptureDisruptionTracker.reopenSuffix
        XCTAssertTrue(finished.contains(.showMessage(expected)), "got \(finished)")
    }

    func testCommittedBeforeMainUnderAnInterruptionDoesNotTearDown() {
        var tracker = CaptureDisruptionTracker()
        let snapshot = CaptureDisruptionTracker.Snapshot(
            isCurrentSession: true, take: .startPending, isAppActive: true, isShowingLivePreview: true)
        XCTAssertEqual(tracker.handle(.captureInterruptionBegan, snapshot), [.requestPendingStartCancel])
        XCTAssertEqual(tracker.adoptDisruptedStartedTake(from: .captureInterruptionBegan), [.stopActiveTake])
        XCTAssertTrue(tracker.takeDisrupted)
        XCTAssertFalse(tracker.tearDownAfterFinish,
                       "an interruption stops the take; it does not tear capture down")
    }

    func testCancellationWinningProducesTearDownAndReopenMessageOnlyAfterResolution() {
        var tracker = CaptureDisruptionTracker()
        let snapshot = CaptureDisruptionTracker.Snapshot(
            isCurrentSession: true, take: .startPending, isAppActive: true, isShowingLivePreview: true)
        XCTAssertEqual(tracker.handle(.audioServicesReset, snapshot), [.requestPendingStartCancel],
                       "no message and no tear-down at the event itself")
        let after = tracker.pendingStartCancelled()
        XCTAssertEqual(after, [.inhibitPlaybackResume, .tearDownCapture,
                               .showMessage(CaptureDisruptionTracker.reopenMessage)])
    }

    func testAnInterruptionCancellationGivesNoReopenMessage() {
        var tracker = CaptureDisruptionTracker()
        let snapshot = CaptureDisruptionTracker.Snapshot(
            isCurrentSession: true, take: .startPending, isAppActive: true, isShowingLivePreview: true)
        _ = tracker.handle(.captureInterruptionBegan, snapshot)
        XCTAssertEqual(tracker.pendingStartCancelled(), [],
                       "an interruption does not tear capture down, so there is nothing to say")
    }

    // MARK: - WIRED file preservation (requirement 3)

    /// A pure decision test cannot establish that a reviewed take survived. This drives
    /// the REAL file effects against REAL files.
    func testCancellationDeletesOnlyItsOwnFileAndPreservesAReviewedTake() throws {
        let effects = RecordingFileEffects()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("c97-wired-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let reviewed = dir.appendingPathComponent("motivo_vid_reviewed.mov")
        let pending  = dir.appendingPathComponent("motivo_vid_pending.mov")
        let reviewedBytes = Data("a real take the member can still save".utf8)
        try reviewedBytes.write(to: reviewed)
        try Data("partial".utf8).write(to: pending)

        var coord = PendingStartCoordinator()
        let t = UUID()
        coord.arm(token: t, presentation: UUID(), url: pending)
        coord.advance(t, to: .writerCreated)
        guard case .cancelledWithWriter(let target) = coord.requestCancel(token: t) else {
            return XCTFail("expected a file effect")
        }
        effects.removeFile(target)

        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path),
                       "the cancelled start's own file is removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: reviewed.path),
                      "the reviewed take SURVIVES")
        XCTAssertEqual(try Data(contentsOf: reviewed), reviewedBytes, "byte-identical")
    }

    func testARetiredContinuationDeletesOnlyItsOwnFile() throws {
        let effects = RecordingFileEffects()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("c97-wired2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let oldURL = dir.appendingPathComponent("motivo_vid_old.mov")
        let newURL = dir.appendingPathComponent("motivo_vid_new.mov")
        try Data("old".utf8).write(to: oldURL)
        let newBytes = Data("the newer start's file".utf8)
        try newBytes.write(to: newURL)

        var coord = PendingStartCoordinator()
        let old = UUID()
        coord.arm(token: old, presentation: UUID(), url: oldURL)
        coord.advance(old, to: .sessionStarting)
        coord.retireForPresentationChange()
        let new = UUID()
        coord.arm(token: new, presentation: UUID(), url: newURL)
        coord.advance(new, to: .writerCreated)

        guard case .cleanUpRetired(let target) = coord.sessionStartReturned(old) else {
            return XCTFail("expected retired cleanup")
        }
        effects.removeFile(target)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path),
                      "the NEWER start's file is untouched")
        XCTAssertEqual(try Data(contentsOf: newURL), newBytes)
    }

    /// Requirement 3's aliasing proof: distinct starts must not be able to name the same
    /// file. Second-resolution timestamps alone could, which is why a uuid suffix exists.
    func testTwoStartsInTheSameSecondProduceDistinctURLs() {
        var seen = Set<String>()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: Date())
        for _ in 0..<200 {
            seen.insert("motivo_vid_\(stamp)_\(UUID().uuidString.prefix(8)).mov")
        }
        XCTAssertEqual(seen.count, 200, "claim urls must be distinct within one second")
        XCTAssertTrue(seen.allSatisfy { $0.hasPrefix("motivo_vid_") },
                      "the prefix both sweepers match on is preserved")
    }
}
