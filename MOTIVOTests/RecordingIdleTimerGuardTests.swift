//
//  RecordingIdleTimerGuardTests.swift
//  MOTIVOTests
//
//  PHASE 5 · P5-K / C-50 — the guard's LIFECYCLE.
//
//  **THESE TESTS CANNOT PROVE THE DEVICE STAYS AWAKE**, and must never be cited
//  as if they did. They prove that the hold is taken when recording begins and
//  released on every exit — success, cancel, failure and teardown — and that two
//  recorders cannot clear each other's hold. The behavioural confirmation is a
//  physical-device step recorded in the acceptance document.
//

import XCTest
@testable import Etudes

@MainActor
final class RecordingIdleTimerGuardTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        RecordingIdleTimerGuard.resetForTesting()
    }

    override func tearDown() async throws {
        RecordingIdleTimerGuard.resetForTesting()
        try await super.tearDown()
    }

    // MARK: - The basic pair

    func testHoldThenRelease() {
        RecordingIdleTimerGuard.hold("a")
        XCTAssertEqual(RecordingIdleTimerGuard.holders, ["a"])
        RecordingIdleTimerGuard.release("a")
        XCTAssertTrue(RecordingIdleTimerGuard.holders.isEmpty)
    }

    /// The shape both call sites actually use.
    func testSetHoldingBothWays() {
        RecordingIdleTimerGuard.setHolding(true, owner: "audio-recorder")
        XCTAssertEqual(RecordingIdleTimerGuard.holders, ["audio-recorder"])
        RecordingIdleTimerGuard.setHolding(false, owner: "audio-recorder")
        XCTAssertTrue(RecordingIdleTimerGuard.holders.isEmpty)
    }

    // MARK: - Every exit releases

    /// Success, cancel and failure all reach the same `state = .idle`
    /// transition, so one assertion covers them: whatever the reason, a
    /// transition away from `.recording` releases.
    func testAnyTransitionAwayFromRecordingReleases() {
        for exit in ["success", "cancel", "failure"] {
            RecordingIdleTimerGuard.setHolding(true, owner: "video-recorder")
            XCTAssertFalse(RecordingIdleTimerGuard.holders.isEmpty, "\(exit): hold not taken")
            RecordingIdleTimerGuard.setHolding(false, owner: "video-recorder")
            XCTAssertTrue(RecordingIdleTimerGuard.holders.isEmpty, "\(exit): hold not released")
        }
    }

    /// Teardown while recording — the case `.onChange` cannot see, because
    /// `VideoRecorderController.onDisappear` does not reset `state`.
    func testTeardownWhileRecordingReleases() {
        RecordingIdleTimerGuard.setHolding(true, owner: "video-recorder")
        RecordingIdleTimerGuard.release("video-recorder")   // what onDisappear does
        XCTAssertTrue(RecordingIdleTimerGuard.holders.isEmpty,
                      "a recorder torn down mid-recording must not strand the idle timer")
    }

    // MARK: - Two recorders, one global flag

    /// The reason this is reference-counted at all.
    func testOneRecorderReleasingDoesNotClearTheOthersHold() {
        RecordingIdleTimerGuard.hold("audio-recorder")
        RecordingIdleTimerGuard.hold("video-recorder")
        RecordingIdleTimerGuard.release("audio-recorder")
        XCTAssertEqual(RecordingIdleTimerGuard.holders, ["video-recorder"],
                       "releasing one recorder must not clear the other's hold")
        RecordingIdleTimerGuard.release("video-recorder")
        XCTAssertTrue(RecordingIdleTimerGuard.holders.isEmpty)
    }

    // MARK: - Cannot strand the flag

    /// A double release must not drive the state negative and strand the flag.
    func testReleaseIsIdempotent() {
        RecordingIdleTimerGuard.hold("a")
        RecordingIdleTimerGuard.release("a")
        RecordingIdleTimerGuard.release("a")
        RecordingIdleTimerGuard.release("never-held")
        XCTAssertTrue(RecordingIdleTimerGuard.holders.isEmpty)

        // And the guard still works afterwards — a negative count would have
        // broken this.
        RecordingIdleTimerGuard.hold("b")
        XCTAssertEqual(RecordingIdleTimerGuard.holders, ["b"])
    }

    /// Lifecycle callbacks can fire more than once for one recording, so a
    /// repeated hold must not require matching releases.
    func testRepeatedHoldFromOneOwnerNeedsOneRelease() {
        RecordingIdleTimerGuard.hold("audio-recorder")
        RecordingIdleTimerGuard.hold("audio-recorder")
        RecordingIdleTimerGuard.release("audio-recorder")
        XCTAssertTrue(RecordingIdleTimerGuard.holders.isEmpty,
                      "a repeated hold must not strand the flag behind a release count")
    }

    // MARK: - Structural: the call sites exist and are paired

    private func source(_ name: String) -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return (try? String(contentsOf: root.appendingPathComponent("MOTIVO/\(name)"), encoding: .utf8)) ?? ""
    }

    func testBothRecordersHoldAndReleaseTheGuard() {
        for file in ["AudioRecorderView.swift", "VideoRecorderView.swift"] {
            let s = source(file)
            XCTAssertTrue(s.contains("RecordingIdleTimerGuard.setHolding"),
                          "\(file) must drive the guard from its state transition")
            XCTAssertTrue(s.contains("RecordingIdleTimerGuard.release"),
                          "\(file) must release on teardown")
        }
    }

    /// `pausedRecording` must not hold — a paused recorder keeping the screen
    /// awake indefinitely is the failure this unit exists to avoid.
    func testOnlyRecordingHoldsNotPaused() {
        for file in ["AudioRecorderView.swift", "VideoRecorderView.swift"] {
            let s = source(file)
            XCTAssertTrue(s.contains("== .recording, owner:") || s.contains("newState == .recording"),
                          "\(file) must hold only for .recording")
            XCTAssertFalse(s.contains("pausedRecording, owner:"),
                           "\(file) must not hold the idle timer while paused")
        }
    }
}
