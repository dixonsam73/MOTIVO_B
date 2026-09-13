import XCTest
@testable import Etudes

final class MetronomeLifecycleTests: XCTestCase {
    func testFailedAudioStartCannotReportRunning() {
        var lifecycle = MetronomeLifecycle(); let token = lifecycle.begin()
        XCTAssertFalse(lifecycle.started(token, audioRunning: false))
        XCTAssertEqual(lifecycle.availability, .unavailable(.start))
    }
    func testSuccessfulStartAndExplicitStop() {
        var lifecycle = MetronomeLifecycle(); let token = lifecycle.begin()
        XCTAssertTrue(lifecycle.started(token, audioRunning: true))
        XCTAssertEqual(lifecycle.availability, .running)
        lifecycle.stop(); XCTAssertNil(lifecycle.token); XCTAssertEqual(lifecycle.availability, .stopped)
    }
    func testAllFailuresWithdrawRunningStateAndRequireNewRun() {
        for reason in [MetronomeFailure.resources, .setup, .start, .interrupted, .routeChanged, .mediaReset, .stoppedAudio] {
            var lifecycle = MetronomeLifecycle(); let token = lifecycle.begin()
            _ = lifecycle.started(token, audioRunning: true)
            XCTAssertTrue(lifecycle.fail(reason, token: token))
            XCTAssertEqual(lifecycle.availability, .unavailable(reason))
            XCTAssertFalse(lifecycle.started(token, audioRunning: true))
        }
    }
    func testQueuedOldRouteEventCannotInvalidateRetry() {
        var lifecycle = MetronomeLifecycle(); let old = lifecycle.begin()
        _ = lifecycle.started(old, audioRunning: true)
        let current = lifecycle.begin(); _ = lifecycle.started(current, audioRunning: true)
        XCTAssertFalse(lifecycle.fail(.routeChanged, token: old))
        XCTAssertFalse(lifecycle.started(old, audioRunning: true))
        XCTAssertEqual(lifecycle.availability, .running)
    }
    func testStopRejectsLateStartFailureAndInterruption() {
        var lifecycle = MetronomeLifecycle(); let token = lifecycle.begin(); lifecycle.stop()
        XCTAssertFalse(lifecycle.fail(.interrupted, token: token))
        XCTAssertFalse(lifecycle.started(token, audioRunning: true))
        XCTAssertEqual(lifecycle.availability, .stopped)
    }
}
