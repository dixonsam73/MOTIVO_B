//
//  C70DirectoryWriteCoordinatorTests.swift
//  MOTIVOTests
//
//  CHANGE-ID: 20260920_190500_C70_DirectoryWriteCoordinator
//  SCOPE: C-70 — dispatch order, stale intent and the identity clock.
//  Serialization is proven by OBSERVED ORDER rather than by waiting: if two
//  writes overlapped, the second's marker would appear before the first's end
//  marker. No test here depends on elapsed time.
//  SEARCH-TOKEN: 20260920_190500_C70_DirectoryWriteCoordinator
//

import XCTest
@testable import Etudes

@MainActor
final class C70DirectoryWriteCoordinatorTests: XCTestCase {

    private let owner = "11111111-1111-1111-1111-111111111111"
    private let other = "22222222-2222-2222-2222-222222222222"
    private var savedSupabaseUserID: String?

    private var coordinator: DirectoryWriteCoordinator { .shared }

    /// Wait until `n` writes have REGISTERED.
    ///
    /// `async let` creates a child task that does not run until the parent
    /// suspends, so releasing a blocker immediately after creating one races
    /// the registration — and a suppression test that loses that race passes
    /// VACUOUSLY, by observing the older write dispatch for the wrong reason.
    /// This either observes the state or fails loudly; it never passes blind.
    private func awaitRegistrations(_ n: Int, _ message: String = "") async {
        for _ in 0..<10_000 {
            if coordinator.submissionCountForTesting >= n { return }
            await Task.yield()
        }
        XCTFail("only \(coordinator.submissionCountForTesting) of \(n) writes registered \(message)")
    }

    override func setUp() async throws {
        try await super.setUp()
        savedSupabaseUserID = UserDefaults.standard.string(forKey: "supabaseUserID_v1")
        UserDefaults.standard.set(owner, forKey: "supabaseUserID_v1")
        coordinator.resetForTesting()
    }

    override func tearDown() async throws {
        if let savedSupabaseUserID {
            UserDefaults.standard.set(savedSupabaseUserID, forKey: "supabaseUserID_v1")
        } else {
            UserDefaults.standard.removeObject(forKey: "supabaseUserID_v1")
        }
        coordinator.resetForTesting()
        try await super.tearDown()
    }

    // MARK: - Dispatch order

    /// **Serialization is the only thing that prevents two of this device's
    /// writes reaching the server in an order nobody chose.** Filtering a stale
    /// RESPONSE cannot: by the time a response is filtered, both requests have
    /// already been sent.
    ///
    /// The second write is registered WHILE the first is in flight — asserted,
    /// not assumed — so the observed order is evidence of exclusion rather than
    /// of late scheduling.
    func testASecondWriteDoesNotBeginUntilTheFirstHasFinished() async {
        var order: [String] = []
        var releaseFirst: CheckedContinuation<Void, Never>?
        let firstStarted = expectation(description: "first started")

        async let first: Void = {
            _ = await coordinator.submit(kind: .profileEdit, owner: owner,
                                         payloadKeys: ["display_name"]) { _, _ in
                order.append("first-start")
                firstStarted.fulfill()
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in releaseFirst = c }
                order.append("first-end")
                return .noRowMatched
            }
        }()

        await fulfillment(of: [firstStarted], timeout: 5)

        async let second: Void = {
            _ = await coordinator.submit(kind: .generation, owner: owner,
                                         payloadKeys: ["account_id"]) { _, _ in
                order.append("second")
                return .noRowMatched
            }
        }()

        await awaitRegistrations(2, "— the second must be queued while the first is in flight")
        XCTAssertEqual(order, ["first-start"], "the second must not have run yet")

        releaseFirst?.resume()
        _ = await (first, second)

        XCTAssertEqual(order, ["first-start", "first-end", "second"],
                       "the second write must not overlap the first")
    }

    /// An active write is NEVER cancelled to make room for a newer edit: a
    /// cancelled request does not un-send itself, it only stops us learning
    /// what it did.
    func testAnActiveWriteIsAllowedToFinish() async {
        var finished = false
        _ = await coordinator.submit(kind: .profileEdit, owner: owner, payloadKeys: ["display_name"]) { _, _ in
            finished = true
            return .noRowMatched
        }
        XCTAssertTrue(finished)
    }

    // MARK: - Stale intent

    /// The suppression RULE, decided at dequeue by exactly this function.
    ///
    /// Tested directly rather than through a queued race: the race version
    /// depends on when a child task registers, and the two "must NOT be
    /// suppressed" cases pass vacuously whenever it loses that race — they
    /// observe the older write dispatch for the wrong reason. Dequeue ORDER is
    /// covered separately, above.
    func testTheSuppressionRuleIsNarrow() async {
        var newerSeq = 0
        _ = await coordinator.submit(kind: .profileEdit, owner: owner,
                                     payloadKeys: ["display_name", "location", "account_id"]) { seq, _ in
            newerSeq = seq
            return .noRowMatched
        }
        let older = newerSeq - 1

        // A newer edit carrying a SUPERSET subsumes the older one.
        XCTAssertTrue(coordinator.isSuperseded(kind: .profileEdit, owner: owner, seq: older,
                                               keys: ["display_name", "location"]))

        // **The superset half is load-bearing.** `upsertSelfRow` omits a blank
        // or invalid account_id to preserve an existing handle, so "newer" does
        // not imply "carries at least as much"; suppressing on sequence alone
        // would silently discard an explicitly supplied field.
        XCTAssertFalse(coordinator.isSuperseded(kind: .profileEdit, owner: owner, seq: older,
                                                keys: ["display_name", "instruments"]),
                       "an edit supplying a key the newer one omits must not be dropped")

        // A handle-only generation and a profile edit carry different intent
        // and neither subsumes the other.
        XCTAssertFalse(coordinator.isSuperseded(kind: .generation, owner: owner, seq: older,
                                                keys: ["account_id"]),
                       "a generation must never be discarded by a profile edit")
        XCTAssertFalse(coordinator.isSuperseded(kind: .creation, owner: owner, seq: older,
                                                keys: ["display_name"]))
    }

    /// A subsumed write is never dispatched, and its caller RESOLVES rather
    /// than hanging.
    func testASubsumedEditIsNeverSentAndItsCallerResolves() async {
        var releaseBlocker: CheckedContinuation<Void, Never>?
        let blocking = expectation(description: "blocker running")
        var olderDispatched = false

        async let blocker: Void = {
            _ = await coordinator.submit(kind: .creation, owner: owner, payloadKeys: ["display_name"]) { _, _ in
                blocking.fulfill()
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in releaseBlocker = c }
                return .noRowMatched
            }
        }()
        await fulfillment(of: [blocking], timeout: 5)

        // **`async let` does not register in source order.** Creating both and
        // then waiting for two registrations would leave which is "older"
        // undecided, and the suppression rule is directional — so the order is
        // established here rather than assumed.
        async let older: DirectoryWriteOutcome = coordinator.submit(
            kind: .profileEdit, owner: owner, payloadKeys: ["display_name", "location"]) { _, _ in
                olderDispatched = true
                return .noRowMatched
            }
        await awaitRegistrations(2, "— the older edit must register first")

        async let newer: DirectoryWriteOutcome = coordinator.submit(
            kind: .profileEdit, owner: owner,
            payloadKeys: ["display_name", "location", "account_id"]) { _, _ in .noRowMatched }
        await awaitRegistrations(3, "— both edits must be queued behind the blocker")

        releaseBlocker?.resume()
        let (olderOutcome, _) = await (older, newer)
        _ = await blocker

        XCTAssertFalse(olderDispatched, "a subsumed edit must never be sent")
        guard case .superseded = olderOutcome else {
            return XCTFail("a superseded caller must resolve typed, not hang: \(olderOutcome)")
        }
    }

    func testSuppressionIsPerOwner() {
        XCTAssertFalse(coordinator.isSuperseded(kind: .profileEdit, owner: other, seq: 1,
                                                keys: ["display_name"]),
                       "another owner's newer edit says nothing about this one")
    }

    // MARK: - Effects

    /// **FIFO stops two writes being in flight; it does not stop A, already in
    /// flight, from finishing after B was submitted.** A receipt that is stale
    /// against local intent must not reach the shared identity, even though the
    /// request that produced it was perfectly valid.
    func testEffectsAreRefusedOnceANewerWriteHasBeenSubmitted() async {
        var firstSeq = 0
        var firstGeneration = 0
        _ = await coordinator.submit(kind: .profileEdit, owner: owner,
                                     payloadKeys: ["display_name"]) { seq, generation in
            firstSeq = seq
            firstGeneration = generation
            return .noRowMatched
        }
        XCTAssertTrue(coordinator.mayApplyEffects(owner: owner,
                                                  capturedGeneration: firstGeneration,
                                                  seq: firstSeq),
                      "the newest write may apply its own result")

        var secondSeq = 0
        _ = await coordinator.submit(kind: .profileEdit, owner: owner,
                                     payloadKeys: ["display_name"]) { seq, _ in
            secondSeq = seq
            return .noRowMatched
        }
        XCTAssertGreaterThan(secondSeq, firstSeq)
        XCTAssertFalse(coordinator.mayApplyEffects(owner: owner,
                                                   capturedGeneration: firstGeneration,
                                                   seq: firstSeq),
                       "the older write must not publish values the newer one is about to replace")
        XCTAssertTrue(coordinator.mayApplyEffects(owner: owner,
                                                  capturedGeneration: firstGeneration,
                                                  seq: secondSeq))
    }

    // MARK: - The identity clock

    /// **A→B→A, with NO intervening submission.** Owner equality and token
    /// subject are both equal to A again, so only a generation captured before
    /// the excursion can tell that the session it belonged to is gone.
    func testAToBToAInvalidatesACapturedGenerationWithNoInterveningSubmission() {
        let captured = coordinator.identityGeneration
        XCTAssertTrue(coordinator.mayApplyEffects(owner: owner, capturedGeneration: captured, seq: 1))

        coordinator.noteIdentityTransition()   // A -> B
        coordinator.noteIdentityTransition()   // B -> A

        XCTAssertEqual(AuthManager.canonicalBackendUserID(), owner,
                       "the owner is A again, which is exactly why owner equality cannot decide this")
        XCTAssertFalse(coordinator.mayApplyEffects(owner: owner, capturedGeneration: captured, seq: 1),
                       "a write from before the excursion is stale though the owner matches")

        let binding = coordinator.binding(owner: owner, capturedGeneration: captured)
        XCTAssertNotNil(binding)
        XCTAssertFalse(binding?.isStillCurrent() ?? true,
                       "and the transport gate must refuse it too")
    }

    func testANewCaptureAfterTheTransitionIsCurrentAgain() {
        coordinator.noteIdentityTransition()
        let captured = coordinator.identityGeneration
        XCTAssertTrue(coordinator.mayApplyEffects(owner: owner, capturedGeneration: captured, seq: 1))
        XCTAssertTrue(coordinator.binding(owner: owner, capturedGeneration: captured)?.isStillCurrent() ?? false)
    }

    func testEffectsAreRefusedForADifferentOwner() {
        let captured = coordinator.identityGeneration
        XCTAssertFalse(coordinator.mayApplyEffects(owner: other, capturedGeneration: captured, seq: 1))
    }

    /// A write submitted under the old identity resolves typed rather than
    /// running under the new one.
    func testAWriteSubmittedBeforeATransitionDoesNotRunAfterIt() async {
        var releaseBlocker: CheckedContinuation<Void, Never>?
        let blocking = expectation(description: "blocker running")
        var laterDispatched = false

        async let blocker: Void = {
            _ = await coordinator.submit(kind: .creation, owner: owner, payloadKeys: ["display_name"]) { _, _ in
                blocking.fulfill()
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in releaseBlocker = c }
                return .noRowMatched
            }
        }()
        await fulfillment(of: [blocking], timeout: 5)

        // Deterministic, and it models the real shape: a caller captures its
        // epoch BEFORE an await of its own (generation reads the row first),
        // and the identity moves while that read is in flight. Relying on when
        // a child task happens to register would be a race in the TEST.
        let staleGeneration = coordinator.identityGeneration
        coordinator.noteIdentityTransition()

        async let queued: DirectoryWriteOutcome = coordinator.submit(
            kind: .profileEdit, owner: owner, payloadKeys: ["display_name"],
            capturedGeneration: staleGeneration) { _, _ in
                laterDispatched = true
                return .noRowMatched
            }

        releaseBlocker?.resume()
        let outcome = await queued
        _ = await blocker

        XCTAssertFalse(laterDispatched, "a write bound to the previous identity must not be sent")
        guard case .supersededIdentity = outcome else {
            return XCTFail("expected supersededIdentity, got \(outcome)")
        }
    }

    /// The `didSet` on `AuthManager.backendUserID` is what makes the clock
    /// unmissable: a future assignment site cannot forget to advance it.
    func testTheIdentityClockIsWiredToTheIdentityItself() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = C70ProfileViewEffectGuardTests.stripComments(
            (try? String(contentsOf: root.appendingPathComponent("MOTIVO/AuthManager.swift"), encoding: .utf8)) ?? "")
        XCTAssertTrue(source.contains("var backendUserID: String? {"),
                      "backendUserID must carry an observer")
        XCTAssertTrue(source.contains("DirectoryWriteCoordinator.shared.noteIdentityTransition()"),
                      "every identity transition must advance the write coordinator's clock")
    }
}

// MARK: - The caller's own guards

/// `ProfileView` owns UI effects the writer cannot reach — the message, the
/// skip-token latch and handle adoption. Two of the three kinds of staleness
/// are behavioural and covered elsewhere; the third, **a newer edit already on
/// screen but not yet submitted**, lives in `@State` inside a SwiftUI view and
/// is asserted structurally here. Recorded as structural coverage, NOT as a
/// behavioural observation.
@MainActor
final class C70ProfileViewEffectGuardTests: XCTestCase {

    private func source() -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let raw = (try? String(contentsOf: root.appendingPathComponent("MOTIVO/ProfileView.swift"), encoding: .utf8)) ?? ""
        return Self.stripComments(raw)
    }

    /// A source-text assertion must target CODE. This project has met the
    /// inverse twice: a file whose own comment explains a rule defeats the
    /// check FOR that rule.
    nonisolated static func stripComments(_ raw: String) -> String {
        raw.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func syncBody() -> String {
        let s = source()
        guard let start = s.range(of: "private func syncDirectoryFromCurrentState() async {"),
              let end = s.range(of: "private func attemptAccountIDAutoGenerationIfNeeded") else { return "" }
        return String(s[start.lowerBound..<end.lowerBound])
    }

    /// Both guards must precede the `switch`, so they cover the ERROR branch
    /// too — guarding only the latch was the earlier, narrower shape.
    func testEveryUIEffectSitsBehindBothFreshnessGuards() {
        let body = syncBody()
        XCTAssertFalse(body.isEmpty, "syncDirectoryFromCurrentState not found")

        guard let identityGuard = body.range(of: "mayApplyEffects("),
              let screenGuard = body.range(of: "currentDirectorySnapshot(backendID: backendID).fingerprint == snapshot.fingerprint"),
              let decision = body.range(of: "switch result.outcome {") else {
            return XCTFail("expected both freshness guards ahead of the outcome switch")
        }
        XCTAssertLessThan(identityGuard.lowerBound, decision.lowerBound,
                          "the identity/sequence guard must cover the error branch, not just the latch")
        XCTAssertLessThan(screenGuard.lowerBound, decision.lowerBound,
                          "an edit made during the debounce must suppress the stale message too")
    }

    /// The latch is a SKIP token: latching it wrongly means the next identical
    /// attempt never reaches the server at all.
    func testTheSkipTokenIsConfirmedOnlyOnAnEvidencedWrite() {
        let body = syncBody()
        let latches = body.components(separatedBy: "directorySyncLatch.confirm(snapshot.fingerprint)").count - 1
        XCTAssertEqual(latches, 1, "exactly one confirm site")
        guard let applied = body.range(of: "case .applied:"),
              let latch = body.range(of: "directorySyncLatch.confirm(snapshot.fingerprint)"),
              let superseded = body.range(of: "case .superseded, .supersededIdentity:") else {
            return XCTFail("expected the confirm inside the applied branch")
        }
        XCTAssertLessThan(applied.lowerBound, latch.lowerBound)
        XCTAssertLessThan(latch.lowerBound, superseded.lowerBound)
    }

    /// The token must be invalidated at SUBMISSION, not merely written on
    /// success — a write skipped before it runs cannot be repaired by any
    /// guard at the end of a response.
    func testTheSkipTokenIsInvalidatedWhenADifferingWriteIsSubmitted() {
        let body = syncBody()
        guard let submit = body.range(of: "directorySyncLatch.shouldSubmit(snapshot.fingerprint)"),
              let request = body.range(of: "await AccountDirectoryService.shared.upsertSelfRow(") else {
            return XCTFail("expected the skip decision to gate the request")
        }
        XCTAssertLessThan(submit.lowerBound, request.lowerBound,
                          "the decision that invalidates the token must precede the request")
        XCTAssertFalse(body.contains("lastDirectorySyncFingerprint"),
                       "the bare-String token is gone; it could not express an outstanding write")
    }

    /// Adoption is a UI effect and carries its own captured epoch.
    func testHandleAdoptionIsGuardedAgainstNewerIntentAndIdentity() {
        let s = source()
        guard let start = s.range(of: "private func attemptAccountIDAutoGenerationIfNeeded") else {
            return XCTFail("not found")
        }
        let body = String(s[start.lowerBound...].prefix(3000))
        XCTAssertTrue(body.contains("let capturedGeneration = DirectoryWriteCoordinator.shared.identityGeneration"),
                      "the epoch must be captured before the await")
        XCTAssertTrue(body.contains("DirectoryWriteCoordinator.shared.identityGeneration == capturedGeneration"),
                      "and checked after it")
        XCTAssertTrue(body.contains("guard storedNow.isEmpty else { return }"),
                      "a manual handle typed while generation was in flight must win")
    }
}

// MARK: - The freshness token's mutual exclusion

/// **A barrier test.** `isCurrent` releases its lock before returning, so a
/// check followed by a mutation is not atomic even with no `await` between
/// them — the cache actor and the main actor are different isolation domains
/// and run genuinely concurrently. `withCurrent` holds the lock across the
/// mutation, and this proves it by ORDER rather than by timing.
final class C70DirectoryWriteValidityBarrierTests: XCTestCase {

    private let owner = "33333333-3333-3333-3333-333333333333"

    /// While `withCurrent`'s body is running, an invalidation arriving from
    /// another thread MUST NOT complete.
    ///
    /// The discrimination is exact. If the lock did not exclude, the transition
    /// would finish and signal, the body's wait would return early, and the
    /// order would be `["transition", "body-end"]`. Because it does exclude,
    /// the transition blocks, the body's bounded wait expires, and the order is
    /// `["body-end", "transition"]`. Both paths terminate; only one is correct.
    func testAnInvalidationCannotInterleaveWithAGuardedMutation() {
        let validity = DirectoryWriteValidity()
        let lock = NSLock()
        var events: [String] = []
        func record(_ s: String) { lock.lock(); events.append(s); lock.unlock() }

        let bodyStarted = DispatchSemaphore(value: 0)
        let transitionDone = DispatchSemaphore(value: 0)
        let finished = expectation(description: "both finished")
        finished.expectedFulfillmentCount = 2

        DispatchQueue.global().async {
            let ran = validity.withCurrent(owner: self.owner, generation: 0, seq: 1) {
                bodyStarted.signal()
                // If mutual exclusion is broken, the transition completes and
                // releases this immediately.
                _ = transitionDone.wait(timeout: .now() + 0.5)
                record("body-end")
            }
            XCTAssertTrue(ran, "the write was current when the body began")
            finished.fulfill()
        }

        bodyStarted.wait()

        DispatchQueue.global().async {
            validity.noteIdentityTransition()
            record("transition")
            transitionDone.signal()
            finished.fulfill()
        }

        wait(for: [finished], timeout: 5)

        lock.lock(); let observed = events; lock.unlock()
        XCTAssertEqual(observed, ["body-end", "transition"],
                       "an invalidation must not land inside a guarded mutation")
    }

    /// And once it has landed, the same write is refused.
    func testAWriteIsRefusedAfterTheInvalidationCompletes() {
        let validity = DirectoryWriteValidity()
        XCTAssertTrue(validity.withCurrent(owner: owner, generation: 0, seq: 1) {})
        validity.noteIdentityTransition()
        XCTAssertFalse(validity.withCurrent(owner: owner, generation: 0, seq: 1) {},
                       "a stale generation may not mutate")
    }

    func testANewerSubmissionRefusesAnOlderGuardedMutation() {
        let validity = DirectoryWriteValidity()
        validity.noteSubmission(owner: owner, seq: 5)
        XCTAssertFalse(validity.withCurrent(owner: owner, generation: 0, seq: 4) {},
                       "an older write may not publish over a newer intent")
        XCTAssertTrue(validity.withCurrent(owner: owner, generation: 0, seq: 5) {})
    }
}
