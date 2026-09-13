import XCTest
@testable import Etudes

final class TunerLifecycleTests: XCTestCase {
    func testOutputIsAcceptedOnlyAfterSuccessfulStartup() {
        var lifecycle = TunerLifecycle()
        let token = lifecycle.begin(needsPermission: false)
        XCTAssertFalse(lifecycle.acceptsOutput(token: token))
        XCTAssertTrue(lifecycle.started(token: token))
        XCTAssertTrue(lifecycle.acceptsOutput(token: token))
    }

    func testDeniedPermissionDoesNotStartListening() {
        var lifecycle = TunerLifecycle()
        let token = lifecycle.begin(needsPermission: true)
        XCTAssertFalse(lifecycle.resolvePermission(granted: false, token: token))
        XCTAssertEqual(lifecycle.availability, .permissionDenied)
        XCTAssertFalse(lifecycle.started(token: token))
        XCTAssertFalse(lifecycle.acceptsOutput(token: token))
    }

    func testStoppingWhilePermissionIsPendingCannotReviveTuner() {
        var lifecycle = TunerLifecycle()
        let token = lifecycle.begin(needsPermission: true)
        lifecycle.stop()
        XCTAssertFalse(lifecycle.resolvePermission(granted: true, token: token))
        XCTAssertEqual(lifecycle.availability, .stopped)
    }

    func testRetryRejectsEveryCallbackFromPreviousRun() {
        var lifecycle = TunerLifecycle()
        let old = lifecycle.begin(needsPermission: true)
        let current = lifecycle.begin(needsPermission: false)
        XCTAssertFalse(lifecycle.resolvePermission(granted: true, token: old))
        XCTAssertFalse(lifecycle.started(token: old))
        lifecycle.fail(.engineStart, token: old)
        XCTAssertEqual(lifecycle.availability, .starting)
        XCTAssertTrue(lifecycle.started(token: current))
        XCTAssertFalse(lifecycle.acceptsOutput(token: old))
        XCTAssertTrue(lifecycle.acceptsOutput(token: current))
    }

    func testFailureWithdrawsReadinessUntilExplicitRetry() {
        for failure in [TunerFailure.inputUnavailable, .engineStart, .interrupted, .routeChanged, .mediaReset] {
            var lifecycle = TunerLifecycle()
            let token = lifecycle.begin(needsPermission: false)
            XCTAssertTrue(lifecycle.started(token: token))
            lifecycle.fail(failure, token: token)
            XCTAssertFalse(lifecycle.acceptsOutput(token: token))
            XCTAssertFalse(lifecycle.started(token: token))
            XCTAssertEqual(lifecycle.availability, .unavailable(failure))
        }
    }

    func testLateFailureCannotChangeStoppedState() {
        var lifecycle = TunerLifecycle()
        let token = lifecycle.begin(needsPermission: false)
        lifecycle.stop()
        lifecycle.fail(.mediaReset, token: token)
        XCTAssertEqual(lifecycle.availability, .stopped)
        XCTAssertNil(lifecycle.token)
    }

    func testGrantedPermissionMovesToStartingBeforeListening() {
        var lifecycle = TunerLifecycle()
        let token = lifecycle.begin(needsPermission: true)
        XCTAssertTrue(lifecycle.resolvePermission(granted: true, token: token))
        XCTAssertEqual(lifecycle.availability, .starting)
        XCTAssertFalse(lifecycle.acceptsOutput(token: token))
        XCTAssertTrue(lifecycle.started(token: token))
    }
}
