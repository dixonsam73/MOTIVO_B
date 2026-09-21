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

    /// **CONVERTED — one assertion dropped, and it is the opposite of the one
    /// kept, so saying why matters.**
    ///
    /// This used to require `let capturedGeneration = …` in the source: the
    /// pre-write epoch capture that the SECOND await, handle generation, was
    /// re-checked against. That await is gone, and with it the only reader of
    /// that variable — `mayApplyEffects` consumes `result.generation` and
    /// `result.seq`, which the WRITE returned, not the pre-write capture. An
    /// unused `capturedGeneration` would warn.
    ///
    /// **The freshness protection itself is untouched** and is what the two
    /// surviving assertions pin. `testSetupPerformsNoSuspensionBetweenThe
    /// FreshnessDecisionAndCompletion` below asserts the absence of the removed
    /// DECLARATION and the presence of the retained parameter label, so this
    /// file states the same fact from both sides and cannot drift into
    /// contradicting itself.
    func testTheSetupTailConsumesFreshnessAndNotJustTheOutcome() {
        let s = source()
        XCTAssertTrue(s.contains("ConnectedSetupDecision.next(outcome: result.outcome, isFresh: isFresh)"),
                      "the decision must consume freshness, not the outcome alone")
        XCTAssertTrue(s.contains("mayApplyEffects("),
                      "freshness comes from the coordinator's own tokens")
    }

    /// **REPLACES `testHandleAdoptionAfterGenerationIsGuardedAgain`, retired with
    /// the feature.** That test pinned an ORDER — decision, generation, re-guard,
    /// adoption — across a second `await` that setup no longer performs.
    ///
    /// The protection it enforced was "no second suspension may reach an effect
    /// unguarded". With generation gone there is exactly ONE await on this path,
    /// so the way to keep that protection true is to assert the absence rather
    /// than the ordering: if a second suspension is ever reintroduced here, this
    /// fails and whoever adds it has to guard it and say so.
    /// **CORRECTED TWICE, and both corrections narrow an overclaim.**
    ///
    /// (1) An earlier revision asserted `capturedGeneration` appeared NOWHERE.
    /// That is false and would have been a wrong assertion passing for a wrong
    /// reason: what was removed is the LOCAL DECLARATION `let capturedGeneration
    /// = …`, while `mayApplyEffects(owner:capturedGeneration:seq:)` keeps it as
    /// a PARAMETER LABEL and must keep it — the label is the surviving guard's
    /// own argument, and deleting it would weaken setup rather than tidy it.
    ///
    /// (2) An earlier revision counted `await AccountDirectoryService.shared.`
    /// and called one occurrence proof of no later suspension. It is not: a
    /// suspension into any OTHER service or helper would escape that count
    /// entirely. The real question is whether anything suspends between the
    /// freshness decision and completion, so that is what is now inspected —
    /// the code TAIL from `ConnectedSetupDecision.next(` to `onComplete()`.
    ///
    /// **No stronger claim is made than that tail.** An `await` earlier in the
    /// function is fine and expected; one after the decision is what would need
    /// its own guard.
    func testSetupPerformsNoSuspensionBetweenTheFreshnessDecisionAndCompletion() {
        let s = source()
        XCTAssertFalse(s.contains("autoGenerateAccountIDIfMissing("),
                       "handle generation is removed from setup")
        XCTAssertFalse(s.contains("ProfileStore.setAccountID"),
                       "setup adopts no handle")

        // The removed LOCAL DECLARATION, not the retained parameter label.
        XCTAssertFalse(s.contains("let capturedGeneration"),
                       "the pre-write capture had no reader left once the second await went")
        XCTAssertTrue(s.contains("capturedGeneration: result.generation"),
                      "the surviving guard's own argument label must NOT be removed")

        guard let decision = s.range(of: "ConnectedSetupDecision.next("),
              let complete = s.range(of: "onComplete()") else {
            return XCTFail("setup tail not found")
        }
        XCTAssertLessThan(decision.lowerBound, complete.lowerBound)
        let tail = String(s[decision.upperBound..<complete.lowerBound])
        XCTAssertFalse(tail.contains("await"),
                       "nothing may suspend between the freshness decision and completion; "
                       + "a new await there needs its own guard and its own test")
    }

    /// **CONVERTED, NOT RETIRED, and the distinction is the point.** The
    /// protection — setup must not complete for a session that replaced the one
    /// that asked — is unchanged and still enforced. What changed is the guard
    /// that expresses it: this used to anchor on the explicit
    /// `identityGeneration == capturedGeneration` comparison that sat between
    /// generation and `onComplete()`. That comparison existed to re-establish
    /// freshness across the generation await, and both are gone together.
    ///
    /// `mayApplyEffects` now carries it alone, which is sufficient because only
    /// one await remains — pinned by
    /// `testSetupPerformsNoSuspensionBetweenTheFreshnessDecisionAndCompletion`
    /// above, so the two assertions together say what the single ordering
    /// assertion used to.
    func testOnCompleteIsReachedOnlyPastTheGuards() {
        let s = source()
        let completes = s.components(separatedBy: "onComplete()").count - 1
        XCTAssertEqual(completes, 1, "exactly one completion site")
        guard let freshness = s.range(of: "mayApplyEffects("),
              let decision = s.range(of: "ConnectedSetupDecision.next("),
              let complete = s.range(of: "onComplete()") else { return XCTFail("not found") }
        XCTAssertLessThan(freshness.lowerBound, decision.lowerBound,
                          "freshness must be established before the outcome is dispositioned")
        XCTAssertLessThan(decision.lowerBound, complete.lowerBound,
                          "setup must not complete for a session that replaced the one that asked")
    }
}
