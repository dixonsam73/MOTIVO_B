import Combine
import XCTest
@testable import Etudes

/// P6-I-05. Completion ownership in `MembershipAttestationCoordinator`: a run that
/// finishes after `reset()` publishes nothing, and the current run keeps
/// single-flight and its own result. Every operation is parked on a continuation the
/// test releases, and every wait is condition-checked with a bounded timeout. No
/// Apple, network, auth or device calls: tests drive `coordinate` directly.
@MainActor
final class P6I05AttestationOwnershipTests: XCTestCase {
    private typealias Outcome = MembershipAttestationService.Outcome

    /// Parks each started operation until the test resumes it, and records whether
    /// its task had been cancelled by the time it was released.
    private final class Gate {
        var parked: [CheckedContinuation<Outcome, Never>] = []
        var cancelledAtResume: [Bool] = []
        var started: Int { parked.count }

        func operation(cancelAware: Bool = false) -> @MainActor () async -> Outcome {
            // Strong capture: a parked operation keeps its Gate alive until resumed,
            // even if a failed test is torn down first. No cycle — the Gate holds
            // continuations, never this closure.
            { [gate = self] in
                let outcome = await withCheckedContinuation { gate.parked.append($0) }
                gate.cancelledAtResume.append(Task.isCancelled)
                return cancelAware && Task.isCancelled ? .transport("cancelled") : outcome
            }
        }

        func resume(_ index: Int, _ outcome: Outcome) { parked[index].resume(returning: outcome) }
    }

    /// One caller of `coordinate`, observable without awaiting its task.
    private final class Caller {
        var done = false
        var result: Outcome?
    }

    private var gate = Gate()
    private var resumed = Set<Int>()

    override func tearDown() {
        // Release anything a failed test left parked, so no continuation leaks.
        for i in gate.parked.indices where !resumed.contains(i) { gate.parked[i].resume(returning: .pending) }
        super.tearDown()
    }

    private func resume(_ index: Int, _ outcome: Outcome) {
        resumed.insert(index)
        gate.resume(index, outcome)
    }

    private func call(_ coordinator: MembershipAttestationCoordinator, force: Bool = false,
                      cancelAware: Bool = false) -> Caller {
        let caller = Caller()
        let operation = gate.operation(cancelAware: cancelAware)
        Task { @MainActor in
            caller.result = await coordinator.coordinate(force: force, operation: operation)
            caller.done = true
        }
        return caller
    }

    private struct WaitTimedOut: Error { let what: String }

    /// Bounded. On timeout it records the failure AND throws, so the test stops
    /// there and never indexes a continuation that was not parked.
    private func waitUntil(_ what: String, timeout: TimeInterval = 2,
                           file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("timed out waiting for \(what)", file: file, line: line)
                throw WaitTimedOut(what: what)
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    // T1
    func testLateCompletionAfterResetPublishesNothing() async throws {
        let coordinator = MembershipAttestationCoordinator()
        let a = call(coordinator)
        try await waitUntil("A started") { gate.started == 1 }
        XCTAssertTrue(coordinator.isAttesting)

        coordinator.reset()
        resume(0, .established)
        try await waitUntil("A returned") { a.done }

        XCTAssertNil(a.result)
        XCTAssertNil(coordinator.lastOutcome)
        XCTAssertFalse(coordinator.isAttesting)
        XCTAssertEqual(gate.cancelledAtResume, [true], "reset cancels the superseded run")

        // Cooldown was cleared by the reset: the next ordinary trigger runs at once.
        let next = call(coordinator)
        try await waitUntil("next started") { gate.started == 2 }
        resume(1, .alreadyEstablished)
        try await waitUntil("next returned") { next.done }
        XCTAssertEqual(next.result, .alreadyEstablished)
        XCTAssertEqual(coordinator.lastOutcome, .alreadyEstablished)
    }

    // T2, late A while B is still pending
    func testLateSupersededRunDoesNotDisturbAPendingNewRun() async throws {
        let coordinator = MembershipAttestationCoordinator()
        let a = call(coordinator)
        try await waitUntil("A started") { gate.started == 1 }
        coordinator.reset()
        let b = call(coordinator)
        try await waitUntil("B started") { gate.started == 2 }

        resume(0, .established)
        try await waitUntil("A returned") { a.done }
        XCTAssertNil(a.result)
        XCTAssertTrue(coordinator.isAttesting, "B is still running")
        XCTAssertNil(coordinator.lastOutcome)

        // Single-flight still belongs to B: both an ordinary and a forced caller join it.
        let joinedOrdinary = call(coordinator)
        let joinedForced = call(coordinator, force: true)
        try await waitUntil("both joined B") { coordinator.joinCount == 2 }
        XCTAssertEqual(gate.started, 2, "no duplicate run was started")

        resume(1, .alreadyEstablished)
        try await waitUntil("B and joiners returned") { b.done && joinedOrdinary.done && joinedForced.done }
        XCTAssertEqual([b.result, joinedOrdinary.result, joinedForced.result], Array(repeating: .alreadyEstablished, count: 3))
        XCTAssertEqual(coordinator.lastOutcome, .alreadyEstablished)
        XCTAssertFalse(coordinator.isAttesting)
    }

    // T2, late A after B has already completed
    func testLateSupersededRunDoesNotOverwriteANewerCompletedResult() async throws {
        let coordinator = MembershipAttestationCoordinator()
        let a = call(coordinator)
        try await waitUntil("A started") { gate.started == 1 }
        coordinator.reset()
        let b = call(coordinator)
        try await waitUntil("B started") { gate.started == 2 }

        resume(1, .established)
        try await waitUntil("B returned") { b.done }
        XCTAssertEqual(coordinator.lastOutcome, .established)

        resume(0, .conflict)
        try await waitUntil("A returned") { a.done }
        XCTAssertNil(a.result)
        XCTAssertEqual(coordinator.lastOutcome, .established, "the latest result is retained")
        XCTAssertFalse(coordinator.isAttesting)
    }

    // T3
    func testCancelledRunReturningLateIsDiscarded() async throws {
        let coordinator = MembershipAttestationCoordinator()
        let a = call(coordinator, cancelAware: true)
        try await waitUntil("A started") { gate.started == 1 }
        coordinator.reset()
        resume(0, .established)
        try await waitUntil("A returned") { a.done }
        XCTAssertEqual(gate.cancelledAtResume, [true])
        XCTAssertNil(a.result, "the cancellation result is not handed to the caller")
        XCTAssertNil(coordinator.lastOutcome)
        XCTAssertFalse(coordinator.isAttesting)
    }

    // T4
    func testConcurrentForcedCallersShareOneRun() async throws {
        let coordinator = MembershipAttestationCoordinator()
        let first = call(coordinator, force: true)
        try await waitUntil("first started") { gate.started == 1 }
        let second = call(coordinator, force: true)
        try await waitUntil("second joined") { coordinator.joinCount == 1 }
        XCTAssertEqual(gate.started, 1)

        resume(0, .pending)
        try await waitUntil("both returned") { first.done && second.done }
        XCTAssertEqual(first.result, .pending)
        XCTAssertEqual(second.result, .pending)
        XCTAssertEqual(coordinator.lastOutcome, .pending)
    }

    func testCallersThatJoinedASupersededRunGetNothing() async throws {
        let coordinator = MembershipAttestationCoordinator()
        let a = call(coordinator)
        try await waitUntil("A started") { gate.started == 1 }
        let joined = call(coordinator, force: true)
        try await waitUntil("joined A") { coordinator.joinCount == 1 }

        coordinator.reset()
        resume(0, .established)
        try await waitUntil("A and joiner returned") { a.done && joined.done }
        XCTAssertNil(a.result)
        XCTAssertNil(joined.result)
        XCTAssertNil(coordinator.lastOutcome)
    }

    // T5
    func testCooldownAndForceAreUnchanged() async throws {
        let coordinator = MembershipAttestationCoordinator()
        let first = call(coordinator)
        try await waitUntil("first started") { gate.started == 1 }
        resume(0, .established)
        try await waitUntil("first returned") { first.done }

        let throttled = call(coordinator)
        try await waitUntil("throttled returned") { throttled.done }
        XCTAssertNil(throttled.result)
        XCTAssertEqual(gate.started, 1, "a repeat inside the cooldown does not run")

        let forced = call(coordinator, force: true)
        try await waitUntil("forced started") { gate.started == 2 }
        resume(1, .alreadyEstablished)
        try await waitUntil("forced returned") { forced.done }
        XCTAssertEqual(forced.result, .alreadyEstablished)
    }

    // T6
    func testResetWithNothingToClearPublishesNothing() async throws {
        let coordinator = MembershipAttestationCoordinator()
        var changes = 0
        let sink = coordinator.objectWillChange.sink { _ in changes += 1 }
        defer { sink.cancel() }

        coordinator.reset()
        XCTAssertEqual(changes, 0, "C-55: an idle reset is a no-op")

        let run = call(coordinator)
        try await waitUntil("run started") { gate.started == 1 }
        resume(0, .established)
        try await waitUntil("run returned") { run.done }

        let beforeReset = changes
        coordinator.reset()
        XCTAssertGreaterThan(changes, beforeReset, "a real reset still clears and publishes")
        let afterReset = changes
        coordinator.reset()
        XCTAssertEqual(changes, afterReset, "C-55: a second reset is a no-op")
    }
}
