import XCTest
@testable import Etudes

/// C-97 part (2). Event SEQUENCES through `CaptureDisruptionTracker`, the pure policy the
/// video recorder delegates to — including writer completion arriving later, stale sessions
/// and repeated resets.
///
/// Coverage, stated plainly: these exercise the decision and ordering logic only. The
/// recorder's wiring (observer registration, `sessionQueue` identity re-checks, the stop
/// path's completion hook) is NOT exercised here — that needs real capture — and remains
/// for review and device QA.
final class C97CaptureDisruptionTests: XCTestCase {
    typealias T = CaptureDisruptionTracker

    private func snap(_ take: T.TakeState, current: Bool = true, active: Bool = true, live: Bool = true) -> T.Snapshot {
        .init(isCurrentSession: current, take: take, isAppActive: active, isShowingLivePreview: live)
    }

    func testResetWhileRecordingStopsTakeThenTearsDownOnlyAfterVerifiedFinish() {
        var t = T()
        XCTAssertEqual(t.handle(.audioServicesReset, snap(.recording)), [.stopActiveTake],
                       "no tear-down and no message until the writer has finished")
        XCTAssertEqual(t.handle(.captureRuntimeError, snap(.finishing)), [], "repeated reset coalesces")
        XCTAssertEqual(t.writerFinished(succeeded: true, keptFileExists: true, existingMessage: nil),
                       [.tearDownCapture, .showMessage(T.keptMessage + " " + T.reopenSuffix)])
        XCTAssertEqual(t.handle(.captureInterruptionEnded, snap(.none)), [], "no automatic restart after a reset")
    }

    func testKeptClaimRequiresSuccessAndARetainedFile() {
        var failed = T()
        _ = failed.handle(.captureRuntimeError, snap(.recording))
        let stronger = "The recording could not be completed. Please try again."
        XCTAssertEqual(failed.writerFinished(succeeded: false, keptFileExists: false, existingMessage: stronger),
                       [.tearDownCapture, .showMessage(stronger + " " + T.reopenSuffix)], "the stronger message is kept")

        var missing = T()
        _ = missing.handle(.captureRuntimeError, snap(.recording))
        XCTAssertEqual(missing.writerFinished(succeeded: true, keptFileExists: false, existingMessage: nil),
                       [.tearDownCapture, .showMessage(T.reopenMessage)], "no kept claim without the file")

        var partialAudio = T()
        _ = partialAudio.handle(.captureInterruptionBegan, snap(.recording))
        let audio = "Recording stopped because some audio could not be saved. The available video has been kept; review its soundtrack before saving it."
        XCTAssertEqual(partialAudio.writerFinished(succeeded: true, keptFileExists: true, existingMessage: audio),
                       [.showMessage(audio)], "the partial-audio message wins over the disruption message")
    }

    func testInterruptionStopsTakeAndItsEndNeverRestartsDuringFinishOrReview() {
        var t = T()
        XCTAssertEqual(t.handle(.captureInterruptionBegan, snap(.recording)), [.stopActiveTake])
        XCTAssertTrue(t.isInterrupted)
        XCTAssertEqual(t.handle(.captureInterruptionEnded, snap(.finishing)), [], "still finalising")
        XCTAssertFalse(t.isInterrupted)
        XCTAssertEqual(t.writerFinished(succeeded: true, keptFileExists: true, existingMessage: nil),
                       [.showMessage(T.keptMessage)], "interruption: kept, and no tear-down")
        XCTAssertEqual(t.handle(.captureInterruptionEnded, snap(.underReview, live: false)), [], "reviewing a take")
        XCTAssertEqual(t.handle(.captureInterruptionEnded, snap(.none)), [], "narrowed: an end never restarts capture")
    }

    func testAnEndWithoutABeginNeverStopsOrFailsAHealthyTake() {
        var t = T()
        XCTAssertEqual(t.handle(.captureInterruptionEnded, snap(.recording)), [])
        XCTAssertEqual(t.writerFinished(succeeded: true, keptFileExists: true, existingMessage: nil), [],
                       "an ordinary stop afterwards carries no disruption message")
    }

    func testStaleSessionEventsAreIgnoredEntirely() {
        var t = T()
        for event in [T.Event.captureRuntimeError, .captureInterruptionBegan, .captureInterruptionEnded, .audioServicesReset] {
            XCTAssertEqual(t.handle(event, snap(.recording, current: false)), [], "\(event)")
        }
        XCTAssertEqual(t, T(), "no state change from a stale session")
    }

    /// Pending-start cancellation was removed: it would race writer setup on another queue.
    /// SUPERSEDED BY C-97's pending-start cancellation, and re-expressed rather than
    /// weakened. It used to assert that a reset during a pending start produced only a
    /// message, and an interruption nothing at all -- the behaviour of the unit that
    /// deliberately left the start running on unusable capture.
    ///
    /// Both now REQUEST A CANCELLATION and decide nothing at the event, because the
    /// answer depends on a race this type cannot see: the start may already have
    /// committed. What follows is asserted by the resolution paths below and, on the real
    /// controller, by C97PendingStartWiringTests.
    func testPendingStartRequestsCancellationAndDecidesNothingAtTheEvent() {
        var reset = T()
        XCTAssertEqual(reset.handle(.audioServicesReset, snap(.startPending)), [.requestPendingStartCancel])
        XCTAssertFalse(reset.takeDisrupted)
        XCTAssertFalse(reset.tearDownAfterFinish)

        var interrupted = T()
        XCTAssertEqual(interrupted.handle(.captureInterruptionBegan, snap(.startPending)),
                       [.requestPendingStartCancel])

        // The cancellation winning tears capture down for a reset...
        XCTAssertEqual(reset.pendingStartCancelled(),
                       [.inhibitPlaybackResume, .tearDownCapture, .showMessage(T.reopenMessage)])
        // ...and says nothing for an interruption, which does not kill capture.
        XCTAssertEqual(interrupted.pendingStartCancelled(), [])
    }

    // MARK: - Execution-time eligibility (queued actions)

    func testQueuedTearDownFromAnEarlierPresentationOrStateNeverRuns() {
        XCTAssertFalse(T.mayExecute(.tearDownCapture, sameGeneration: false, snap(.none), awaitingReopen: true), "dismissed or reopened since")
        XCTAssertFalse(T.mayExecute(.tearDownCapture, sameGeneration: true, snap(.none, current: false), awaitingReopen: true), "a different session")
        for take in [T.TakeState.startPending, .recording, .finishing] {
            XCTAssertFalse(T.mayExecute(.tearDownCapture, sameGeneration: true, snap(take), awaitingReopen: true), "\(take) since the decision")
        }
        XCTAssertTrue(T.mayExecute(.tearDownCapture, sameGeneration: true, snap(.underReview, live: false), awaitingReopen: true))
    }

    /// Reset during review, then the app returns to the foreground or the interruption ends:
    /// playback resume is inhibited and nothing restarts.
    func testResetThenForegroundOrInterruptionEndedRestartsNothing() {
        var t = T()
        XCTAssertEqual(t.handle(.audioServicesReset, snap(.underReview, live: false)),
                       [.inhibitPlaybackResume, .tearDownCapture, .showMessage(T.reviewReopenMessage)])
        XCTAssertEqual(t.handle(.captureInterruptionEnded, snap(.underReview, live: false)), [])
        XCTAssertEqual(t.handle(.captureInterruptionEnded, snap(.none)), [])
    }

    /// While capture is being torn down after a reset, a new Record or flip is refused
    /// until the recorder is reopened.
    func testNewCaptureIsRejectedUntilReopen() {
        var t = T()
        XCTAssertFalse(t.blocksNewCapture)
        _ = t.handle(.captureRuntimeError, snap(.none))
        XCTAssertTrue(t.blocksNewCapture, "pending tear-down: no new start")
        _ = t.handle(.captureInterruptionEnded, snap(.none))
        XCTAssertTrue(t.blocksNewCapture, "an interruption ending does not lift it")
        t.reset()
        XCTAssertFalse(t.blocksNewCapture, "a new presentation lifts it")
    }

    func testResetDuringReviewOrFinishingNeverDiscardsTheTake() {
        var review = T()
        XCTAssertEqual(review.handle(.audioServicesReset, snap(.underReview, live: false)),
                       [.inhibitPlaybackResume, .tearDownCapture, .showMessage(T.reviewReopenMessage)], "no stop, no discard")
        var finishing = T()
        XCTAssertEqual(finishing.handle(.captureRuntimeError, snap(.finishing)), [], "nothing until the writer finishes")
        XCTAssertEqual(finishing.writerFinished(succeeded: true, keptFileExists: true, existingMessage: nil),
                       [.tearDownCapture, .showMessage(T.reopenMessage)],
                       "not stopped by the disruption, so no kept claim; tear-down after the finish")
    }

    func testRepeatedResetsCoalesceAndANewPresentationStartsClean() {
        var t = T()
        XCTAssertEqual(t.handle(.audioServicesReset, snap(.none)),
                       [.inhibitPlaybackResume, .tearDownCapture, .showMessage(T.reopenMessage)])
        XCTAssertEqual(t.handle(.audioServicesReset, snap(.none)), [], "coalesced")
        t.reset()
        XCTAssertEqual(t, T())
    }

    func testOrdinaryStopWithoutDisruptionIsUnaffected() {
        var t = T()
        XCTAssertEqual(t.writerFinished(succeeded: true, keptFileExists: true, existingMessage: nil), [])
        XCTAssertEqual(t.writerFinished(succeeded: false, keptFileExists: false, existingMessage: "x"), [])
    }
}
