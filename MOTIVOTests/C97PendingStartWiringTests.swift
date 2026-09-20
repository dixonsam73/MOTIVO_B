//
//  C97PendingStartWiringTests.swift
//  MOTIVOTests
//
//  CHANGE-ID: 20260920_150000_C97_PendingStartCancellation
//  SCOPE: C-97 — the REAL controller orchestration: a live VideoRecorderController, its
//  real queues, its real coordinator and tracker, with only the file effects doubled.
//  These are the tests the pure coordinator tests cannot stand in for.
//  SEARCH-TOKEN: 20260920_150000_C97_PendingStartCancellation
//

import XCTest
import AVFoundation
@testable import Etudes

final class C97PendingStartWiringTests: XCTestCase {

    private func makeController() -> (VideoRecorderController, Recorder) {
        let recorder = Recorder()
        let c = VideoRecorderController(onSave: { _ in })
        c.fileEffects = RecordingFileEffects(
            removeFile: { url in recorder.removed.append(url) },
            cancelWriting: { _ in recorder.cancelled += 1 }
        )
        return (c, recorder)
    }

    final class Recorder {
        var removed: [URL] = []
        var cancelled = 0
    }

    /// The controller's queues are private; settle by draining them in order.
    private func drain(_ c: VideoRecorderController) {
        let e = expectation(description: "writerQueue then main")
        c.writerQueue.async { DispatchQueue.main.async { e.fulfill() } }
        wait(for: [e], timeout: 5)
    }

    private func arm(_ c: VideoRecorderController, stage: PendingStartCoordinator.Stage,
                     url: URL) -> UUID {
        let token = UUID()
        c.currentStartToken = token
        let presentation = c.presentationID
        c.writerQueue.sync {
            c.startCoordinator.arm(token: token, presentation: presentation, url: url)
            if stage != .armed { c.startCoordinator.advance(token, to: stage) }
        }
        return token
    }

    private func url(_ n: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("c97w-\(n)-\(UUID().uuidString).mov")
    }

    // MARK: -

    @MainActor
    func testCancellingAnArmedStartTouchesNoFileAndClearsTheStart() {
        let (c, rec) = makeController()
        let u = url("armed")
        c.recordingURL = u
        _ = arm(c, stage: .armed, url: u)
        _ = c.disruption.handle(.audioServicesReset, .init(isCurrentSession: true, take: .startPending,
                                                           isAppActive: true, isShowingLivePreview: true))
        c.requestPendingStartCancellation(for: .audioServicesReset)
        drain(c)

        XCTAssertTrue(rec.removed.isEmpty, "nothing was written, so nothing is deleted")
        XCTAssertNil(c.currentStartToken)
        XCTAssertNil(c.recordingURL, "a cancelled start must not leave its url for the next claim")
        XCTAssertFalse(c.startCoordinator.hasLiveClaim)
    }

    @MainActor
    func testCancellingAfterWriterCreationDeletesExactlyTheClaimsURLOnce() {
        let (c, rec) = makeController()
        let u = url("written")
        c.recordingURL = u
        _ = arm(c, stage: .writerCreated, url: u)
        _ = c.disruption.handle(.audioServicesReset, .init(isCurrentSession: true, take: .startPending,
                                                           isAppActive: true, isShowingLivePreview: true))
        c.requestPendingStartCancellation(for: .audioServicesReset)
        drain(c)

        XCTAssertEqual(rec.removed, [u], "exactly the claim's own url, exactly once")
        XCTAssertNil(c.recordingURL)

        // A second request must do nothing at all.
        c.requestPendingStartCancellation(for: .audioServicesReset)
        drain(c)
        XCTAssertEqual(rec.removed, [u], "repeated cancellation is a no-op")
    }

    @MainActor
    func testACancellationNamesItsOwnClaimAndNeverANewerStart() {
        let (c, rec) = makeController()
        let older = url("older")
        _ = arm(c, stage: .writerCreated, url: older)
        // The event is handled, which names the OLDER claim on main and dispatches...
        _ = c.disruption.handle(.captureInterruptionBegan, .init(isCurrentSession: true, take: .startPending,
                                                                 isAppActive: true, isShowingLivePreview: true))
        c.requestPendingStartCancellation(for: .captureInterruptionBegan)

        // ...and before that request reaches writerQueue the member taps Record again.
        // An interruption does not set awaitingReopen, so a new start is permitted.
        let newer = url("newer")
        let newerToken = arm(c, stage: .writerCreated, url: newer)
        drain(c)

        XCTAssertFalse(rec.removed.contains(newer),
                       "the NEWER start must never be cancelled by an older event's request")
        XCTAssertTrue(c.startCoordinator.hasLiveClaim, "the newer claim is still live")
        XCTAssertEqual(c.currentStartToken, newerToken)
    }

    @MainActor
    func testACompletionFromAClosedPresentationMutatesNothing() {
        let (c, _) = makeController()
        let u = url("stale")
        c.recordingURL = u
        let token = arm(c, stage: .writerCreated, url: u)
        let stalePresentation = c.presentationID

        // The recorder is reopened before the completion lands.
        c.presentationID = UUID()
        c.currentStartToken = UUID()
        let keptURL = c.recordingURL

        c.completePendingStartCancellation(token: token, presentation: stalePresentation, generation: nil)
        XCTAssertEqual(c.recordingURL, keptURL, "the reopened recorder is untouched")
    }

    @MainActor
    func testStartupAlreadyWonStopsTheTakeAndExplainsIt() {
        let (c, rec) = makeController()
        let u = url("committed")
        c.recordingURL = u
        _ = arm(c, stage: .committed, url: u)
        _ = c.disruption.handle(.audioServicesReset, .init(isCurrentSession: true, take: .startPending,
                                                           isAppActive: true, isShowingLivePreview: true))
        XCTAssertFalse(c.disruption.takeDisrupted, "nothing is decided at the event")

        c.requestPendingStartCancellation(for: .audioServicesReset)

        // The matching main transition S5 dispatched lands BEFORE the resolution's own
        // main hop, which is the ordering that lets stopRecording see a real take.
        c.state = .recording
        drain(c)

        XCTAssertTrue(rec.removed.isEmpty, "a committed take is never deleted by a cancellation")
        XCTAssertTrue(c.disruption.takeDisrupted)
        XCTAssertTrue(c.disruption.tearDownAfterFinish)
        XCTAssertNotEqual(c.state, .recording, "stopRecording actually ran; it did not no-op")

        // And the finish path explains it, rather than stopping the take in silence.
        drain(c)
        c.disruptionWriterFinished(succeeded: false, url: nil, strongerMessage: nil)
        let message = c.recordingError ?? ""
        XCTAssertTrue(message.contains(CaptureDisruptionTracker.reopenMessage)
                        || message.contains(CaptureDisruptionTracker.reopenSuffix),
                      "the member is told what happened; got: '\(message)'")
        XCTAssertFalse(c.disruption.tearDownAfterFinish, "tear-down was consumed by the finish")
    }

    @MainActor
    func testDisappearLeavesAnInFlightSessionStartToItsOwnContinuation() {
        let (c, rec) = makeController()
        let u = url("inflight")
        c.recordingURL = u
        c.isRecordStartInProgress = true          // main's real state during a pending start
        let token = arm(c, stage: .sessionStarting, url: u)

        c.onDisappear()
        drain(c)

        XCTAssertEqual(rec.cancelled, 0,
                       "the teardown must not cancel a writer that startSession is still using")
        XCTAssertTrue(rec.removed.isEmpty,
                      "nor delete the file the continuation owns")
        XCTAssertNil(c.recordingURL, "but main stops pointing at it")

        // The continuation finally returns and cleans up exactly once.
        var outcome: PendingStartCoordinator.Continuation?
        c.writerQueue.sync { outcome = c.startCoordinator.sessionStartReturned(token) }
        XCTAssertEqual(outcome, .cleanUpRetired(url: u))
    }

    /// The rapid dismiss-reopen-record ordering. Without the synchronous detach at the
    /// lifecycle boundary, the queued main cleanup is skipped by the presentation guard,
    /// the next Record inherits the old `recordingURL`, and the old continuation later
    /// deletes what has become the new take's output.
    @MainActor
    func testARapidReopenDoesNotLetANewStartInheritAPendingURL() {
        let (c, rec) = makeController()
        let u = url("inherited")
        c.recordingURL = u
        c.isRecordStartInProgress = true
        _ = arm(c, stage: .sessionStarting, url: u)

        c.onDisappear()
        // The url is detached SYNCHRONOUSLY, before any queue hop and before any reopen.
        XCTAssertNil(c.recordingURL, "a pending start's url must not survive the boundary")
        XCTAssertNil(c.currentStartToken)

        // A quick reopen invalidates the queued main cleanup's presentation guard.
        c.presentationID = UUID()
        drain(c)
        XCTAssertNil(c.recordingURL, "and it is still detached after the queues settle")
        XCTAssertTrue(rec.removed.isEmpty, "the continuation owns that file, so nothing deleted it here")
    }

    @MainActor
    func testDisappearDeletesAPendingFileItStillOwns() {
        let (c, rec) = makeController()
        let u = url("ownedhere")
        c.recordingURL = u
        c.isRecordStartInProgress = true
        _ = arm(c, stage: .writerCreated, url: u)   // no continuation in flight

        c.onDisappear()
        drain(c)
        XCTAssertEqual(rec.removed, [u], "this teardown owns the file, so it removes it")
        XCTAssertNil(c.recordingURL)
    }

    @MainActor
    func testAPreArmFrameRunsTheProductionDecisionAndMutatesNothing() {
        let (c, rec) = makeController()
        // Main has armed its flags; the writerQueue arm block has NOT run yet. This is
        // the exact interleaving that used to clear those flags and kill the start.
        c.isArmedToRecord = true
        c.isRecordStartInProgress = true
        let u = url("prearm")
        c.recordingURL = u

        var decision: PendingStartCoordinator.FrameDisposition?
        c.writerQueue.sync { decision = c.preWriterDecisionForFrame() }   // the production method
        XCTAssertEqual(decision, .noClaim)

        drain(c)
        XCTAssertTrue(c.isArmedToRecord, "a pre-arm frame must not kill a start about to be armed")
        XCTAssertTrue(c.isRecordStartInProgress)
        XCTAssertEqual(c.recordingURL, u)
        XCTAssertTrue(rec.removed.isEmpty)

        // Once the arm lands, the same production method admits the frame.
        let token = arm(c, stage: .armed, url: u)
        c.writerQueue.sync { decision = c.preWriterDecisionForFrame() }
        XCTAssertEqual(decision, .proceed(token: token, url: u))
    }

    // MARK: - Startup liveness after a retired claim

    /// A claim retired while `startSession` was blocked leaves `isStartingWriterSession`
    /// TRUE. The cadence gate returns on that flag for every frame, and the retired
    /// continuation deliberately touches no shared state — so without a reset at the
    /// claim boundary the NEXT start could never progress.
    @MainActor
    func testANewClaimClearsPipelineStateLeftByARetiredBlockedStart() {
        let (c, _) = makeController()
        let oldURL = url("blocked")
        let oldToken = UUID()
        let oldPresentation = c.presentationID
        c.writerQueue.sync {
            c.startCoordinator.arm(token: oldToken, presentation: oldPresentation, url: oldURL)
            c.startCoordinator.advance(oldToken, to: .sessionStarting)
            c.isStartingWriterSession = true          // as startSession leaves it
            c.startCoordinator.retireForPresentationChange()
        }

        // The recorder is reopened and a new start armed through the real arm path.
        c.presentationID = UUID()
        c.recordingURL = nil
        c.startRecordingForTesting()
        drain(c)

        var stuck = true
        var hasClaim = false
        c.writerQueue.sync {
            stuck = c.isStartingWriterSession
            hasClaim = c.startCoordinator.hasLiveClaim
        }
        XCTAssertFalse(stuck, "the new start must not inherit the blocked start's gate")
        XCTAssertTrue(hasClaim, "and it has its own claim")
    }

    /// And when the old continuation finally returns it cannot overwrite the new state.
    @MainActor
    func testARetiredReturnCannotOverwriteTheNewStartsState() {
        let (c, _) = makeController()
        let oldURL = url("blocked2")
        let oldToken = UUID()
        let oldPresentation = c.presentationID
        let newToken = UUID()
        c.writerQueue.sync {
            c.startCoordinator.arm(token: oldToken, presentation: oldPresentation, url: oldURL)
            c.startCoordinator.advance(oldToken, to: .sessionStarting)
            c.startCoordinator.retireForPresentationChange()
            c.startCoordinator.arm(token: newToken, presentation: UUID(), url: self.url("fresh"))
            c.isStartingWriterSession = false
            c.writerSessionReady = false
        }

        var proceeded = true
        var ready = true
        var starting = true
        c.writerQueue.sync {
            proceeded = c.handleSessionStartReturn(token: oldToken, writer: nil,
                                                   claimPresentation: oldPresentation)
            ready = c.writerSessionReady
            starting = c.isStartingWriterSession
        }
        XCTAssertFalse(proceeded)
        XCTAssertFalse(ready, "the retired return must not mark the NEW start session-ready")
        XCTAssertFalse(starting)
        var token: UUID?
        c.writerQueue.sync { token = c.startCoordinator.currentToken }
        XCTAssertEqual(token, newToken, "the new claim is intact")
    }

    /// An unidentifiable continuation must refuse, as S5 does.
    @MainActor
    func testAContinuationWithNoClaimIdentityRefusesToMutateSharedState() {
        let (c, _) = makeController()
        var proceeded = true
        var ready = true
        c.writerQueue.sync {
            c.writerSessionReady = false
            proceeded = c.handleSessionStartReturn(token: nil, writer: nil, claimPresentation: nil)
            ready = c.writerSessionReady
        }
        XCTAssertFalse(proceeded, "absence is a refusal, not a fall-through")
        XCTAssertFalse(ready)
    }

    // MARK: - Real file effects through the real controller

    /// The controller's DEFAULT file effects, on real files, with an unrelated file
    /// present that must survive.
    @MainActor
    func testControllerCancellationWithRealFileEffectsPreservesUnrelatedFiles() throws {
        let c = VideoRecorderController(onSave: { _ in })   // default RecordingFileEffects
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("c97-real-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let unrelated = dir.appendingPathComponent("motivo_vid_unrelated.mov")
        let unrelatedBytes = Data("another take entirely".utf8)
        try unrelatedBytes.write(to: unrelated)
        let pending = dir.appendingPathComponent("motivo_vid_pending.mov")
        try Data("partial".utf8).write(to: pending)

        c.recordingURL = pending
        let token = UUID()
        c.currentStartToken = token
        let presentation = c.presentationID
        c.writerQueue.sync {
            c.startCoordinator.arm(token: token, presentation: presentation, url: pending)
            c.startCoordinator.advance(token, to: .writerCreated)
        }
        _ = c.disruption.handle(.audioServicesReset, .init(isCurrentSession: true, take: .startPending,
                                                           isAppActive: true, isShowingLivePreview: true))
        c.requestPendingStartCancellation(for: .audioServicesReset)
        let e = expectation(description: "settle")
        c.writerQueue.async { DispatchQueue.main.async { e.fulfill() } }
        wait(for: [e], timeout: 5)

        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path),
                       "the cancelled start's own file is really gone")
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path),
                      "an unrelated file SURVIVES")
        XCTAssertEqual(try Data(contentsOf: unrelated), unrelatedBytes, "byte-identical")
        XCTAssertNil(c.recordingURL)
    }

    /// The retired-continuation path, through the production seam, with real files.
    @MainActor
    func testControllerRetiredContinuationDeletesOnlyItsOwnFile() throws {
        let c = VideoRecorderController(onSave: { _ in })   // default file effects
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("c97-real2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let oldURL = dir.appendingPathComponent("motivo_vid_old.mov")
        let newURL = dir.appendingPathComponent("motivo_vid_new.mov")
        try Data("old partial".utf8).write(to: oldURL)
        let newBytes = Data("the newer start".utf8)
        try newBytes.write(to: newURL)

        let oldToken = UUID()
        let oldPresentation = c.presentationID
        c.writerQueue.sync {
            c.startCoordinator.arm(token: oldToken, presentation: oldPresentation, url: oldURL)
            c.startCoordinator.advance(oldToken, to: .sessionStarting)
            c.startCoordinator.retireForPresentationChange()
            // the recorder is reopened and a new start armed
            c.startCoordinator.arm(token: UUID(), presentation: UUID(), url: newURL)
        }

        // The blocked startSession finally returns, through the production seam.
        var proceeded = true
        c.writerQueue.sync {
            proceeded = c.handleSessionStartReturn(token: oldToken, writer: nil,
                                                   claimPresentation: oldPresentation)
        }
        XCTAssertFalse(proceeded, "a retired continuation must not run the session-ready path")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path),
                      "the NEWER start's file is untouched")
        XCTAssertEqual(try Data(contentsOf: newURL), newBytes)

        // Exactly once: a second delivery does nothing.
        c.writerQueue.sync { _ = c.handleSessionStartReturn(token: oldToken, writer: nil,
                                                            claimPresentation: oldPresentation) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
    }
}
