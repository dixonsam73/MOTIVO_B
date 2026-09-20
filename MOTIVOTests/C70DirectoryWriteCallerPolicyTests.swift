//
//  C70DirectoryWriteCallerPolicyTests.swift
//  MOTIVOTests
//
//  CHANGE-ID: 20260920_194500_C70_CallerPolicy
//  SCOPE: C-70 — the two caller decisions, both of which were wrong in ways an
//  end-of-response guard could not reach: a write SKIPPED before it ran, and a
//  setup tail that finished for the wrong session.
//  SEARCH-TOKEN: 20260920_194500_C70_CallerPolicy
//

import XCTest
@testable import Etudes

final class C70DirectorySyncLatchTests: XCTestCase {

    func testAConfirmedValueIsNotRepublished() {
        var latch = DirectorySyncLatch()
        latch.confirm("A")
        XCTAssertFalse(latch.shouldSubmit("A"), "an unchanged screen must not re-publish")
    }

    /// **THE REGRESSION.** A saved, then an edit held in flight, then a revert
    /// to the saved value.
    ///
    /// Under the old bare-`String?` token step 3 compared A against A and
    /// returned before sending anything, while B went on to land on the server
    /// and had its own UI result correctly suppressed. Server B, screen A,
    /// nothing left to re-publish it — permanent and silent.
    func testTheAToBToARevertIsRepublishedRatherThanSkipped() {
        var latch = DirectorySyncLatch()

        latch.confirm("A")                                   // 1. A is saved
        XCTAssertTrue(latch.shouldSubmit("B"))               // 2. B dispatched
        XCTAssertNil(latch.confirmed,
                     "the server's value is in flight and no longer known")
        XCTAssertTrue(latch.shouldSubmit("A"),               // 3. reverted to A
                      "the revert MUST be re-published; skipping it is the divergence")
    }

    /// B's result being suppressed must not silently re-confirm anything.
    func testASuppressedResultLeavesTheTokenInvalid() {
        var latch = DirectorySyncLatch()
        latch.confirm("A")
        _ = latch.shouldSubmit("B")
        // B's UI result is suppressed: no confirm call happens at all.
        XCTAssertNil(latch.confirmed)
        XCTAssertTrue(latch.shouldSubmit("A"))
    }

    func testConfirmingRestoresTheSkip() {
        var latch = DirectorySyncLatch()
        XCTAssertTrue(latch.shouldSubmit("A"))
        latch.confirm("A")
        XCTAssertFalse(latch.shouldSubmit("A"))
    }

    func testInvalidationForcesTheNextWrite() {
        var latch = DirectorySyncLatch()
        latch.confirm("A")
        latch.invalidate()
        XCTAssertTrue(latch.shouldSubmit("A"),
                      "adopting a generated handle changes the row under the token")
    }
}

final class C70ConnectedSetupDecisionTests: XCTestCase {

    private let receipt = DirectoryWriteReceipt(userID: "11111111-1111-1111-1111-111111111111",
                                                displayName: "Ada", displayNamePresent: true,
                                                accountID: nil, accountIDPresent: true,
                                                location: nil, locationPresent: true,
                                                instruments: nil, instrumentsPresent: true)

    func testAnEvidencedAndCurrentWriteFinishesSetup() {
        XCTAssertEqual(ConnectedSetupDecision.next(outcome: .applied(receipt), isFresh: true),
                       .completeSetup)
    }

    /// **THE REGRESSION.** An `.applied` that returns after an identity
    /// transition would otherwise run generation, write a handle into
    /// `ProfileStore` and call `onComplete()` for the session that REPLACED the
    /// one that asked.
    func testAnEvidencedWriteForAReplacedSessionFinishesNothing() {
        XCTAssertEqual(ConnectedSetupDecision.next(outcome: .applied(receipt), isFresh: false),
                       .abandonSilently)
    }

    func testAFailureIsReportedOnlyToTheSessionThatAskedForIt() {
        XCTAssertEqual(ConnectedSetupDecision.next(outcome: .refusedByPolicy, isFresh: true),
                       .reportFailure)
        XCTAssertEqual(ConnectedSetupDecision.next(outcome: .refusedByPolicy, isFresh: false),
                       .abandonSilently,
                       "a stale failure must not post a message to the replacement's screen")
    }

    func testEveryUnevidencedOutcomeIsReportedRatherThanCompleted() {
        for outcome: DirectoryWriteOutcome in [.notEvidenced(receipt), .noRowMatched,
                                               .accountIDTaken, .refusedByPolicy, .rowConflict,
                                               .ambiguous(NetworkManager.NetworkError.transportError("x")),
                                               .failed(NetworkManager.NetworkError.notConfigured)] {
            XCTAssertEqual(ConnectedSetupDecision.next(outcome: outcome, isFresh: true),
                           .reportFailure, "\(outcome) must not finish setup")
        }
    }

    func testASupersededWriteIsSilent() {
        XCTAssertEqual(ConnectedSetupDecision.next(outcome: .superseded, isFresh: true),
                       .abandonSilently)
        XCTAssertEqual(ConnectedSetupDecision.next(outcome: .supersededIdentity, isFresh: true),
                       .abandonSilently)
    }
}

/// `onComplete()` is the effect that cannot be taken back — it advances the
/// member out of setup. These pin that every path to it is guarded.
final class C70SetupCallerStructureTests: XCTestCase {

    private func source() -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        // Comments are stripped: an earlier revision of this very test counted
        // an `onComplete()` occurrence inside a COMMENT that explains the guard,
        // and reported two completion sites where the code has one.
        return C70ProfileViewEffectGuardTests.stripComments(
            (try? String(contentsOf: root.appendingPathComponent("MOTIVO/AppSetUpView.swift"), encoding: .utf8)) ?? "")
    }

    func testTheSetupTailConsumesFreshnessAndNotJustTheOutcome() {
        let s = source()
        XCTAssertTrue(s.contains("let capturedGeneration = DirectoryWriteCoordinator.shared.identityGeneration"),
                      "the epoch must be captured before the first await")
        XCTAssertTrue(s.contains("ConnectedSetupDecision.next(outcome: result.outcome, isFresh: isFresh)"),
                      "the decision must consume freshness, not the outcome alone")
        XCTAssertTrue(s.contains("mayApplyEffects("),
                      "freshness comes from the coordinator's own tokens")
    }

    /// Generation is a second await, so the first guard does not cover it.
    func testHandleAdoptionAfterGenerationIsGuardedAgain() {
        let s = source()
        guard let decision = s.range(of: "ConnectedSetupDecision.next("),
              let generation = s.range(of: "autoGenerateAccountIDIfMissing("),
              let reguard = s.range(of: "DirectoryWriteCoordinator.shared.identityGeneration == capturedGeneration"),
              let adopt = s.range(of: "ProfileStore.setAccountID(generated, for: backendID)") else {
            return XCTFail("expected a second guard between generation and adoption")
        }
        XCTAssertLessThan(decision.lowerBound, generation.lowerBound)
        XCTAssertLessThan(generation.lowerBound, reguard.lowerBound)
        XCTAssertLessThan(reguard.lowerBound, adopt.lowerBound)
        XCTAssertTrue(s.contains("ProfileStore.accountID(for: backendID).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty"),
                      "a handle typed while generation was in flight must win")
    }

    func testOnCompleteIsReachedOnlyPastTheGuards() {
        let s = source()
        let completes = s.components(separatedBy: "onComplete()").count - 1
        XCTAssertEqual(completes, 1, "exactly one completion site")
        guard let reguard = s.range(of: "DirectoryWriteCoordinator.shared.identityGeneration == capturedGeneration"),
              let complete = s.range(of: "onComplete()") else { return XCTFail("not found") }
        XCTAssertLessThan(reguard.lowerBound, complete.lowerBound,
                          "setup must not complete for a session that replaced the one that asked")
    }
}
