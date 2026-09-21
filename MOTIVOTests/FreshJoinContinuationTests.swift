// CHANGE-ID: 20260921_FreshJoin_ContinuationAndReconciliation
// SCOPE: F1 (SIWA -> join continuation) and F2 (post-attestation directory
// reconciliation). Structural assertions for wiring, value tests for the pure
// policy, and coordinator-level behavioural tests for completion publication.
// SEARCH-TOKEN: 20260921_FreshJoin_ContinuationAndReconciliation

import XCTest
@testable import Etudes

// MARK: - F1, the SIWA -> join continuation

/// **These read SOURCE TEXT. They prove WIRING, not rendering.** Nothing in this
/// target renders a view, and no assertion here claims one was drawn.
final class FreshJoinContinuationStructureTests: XCTestCase {

    private func profileSource() -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return (try? String(contentsOf: root.appendingPathComponent("MOTIVO/ProfileView.swift"),
                            encoding: .utf8)) ?? ""
    }

    /// Comments stripped, so a comment EXPLAINING the ordering cannot satisfy a
    /// check FOR the ordering — U5d met that trap twice.
    private func code() -> String {
        profileSource()
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let r = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<r.lowerBound])
            }
            .joined(separator: "\n")
    }

    func testSourceWasFound() {
        XCTAssertFalse(profileSource().isEmpty, "every assertion below is vacuous without the source")
    }

    /// **T1.** The join branch must be reachable: it has to precede the gate
    /// branch that used to consume the event and return.
    func testTheJoinBranchPrecedesTheGateUnwind() {
        let s = code()
        guard let join = s.range(of: "if connectedSignInIntent == .join {"),
              let gate = s.range(of: "if signedOutGateWasVisible {") else {
            return XCTFail("expected both branches in the sign-in completion handler")
        }
        XCTAssertLessThan(join.lowerBound, gate.lowerBound,
                          "the gate branch returns, so a join test after it is unreachable")
    }

    /// **T1.** The join branch presents membership selection.
    func testTheJoinBranchContinuesIntoMembershipSelection() {
        let s = code()
        guard let join = s.range(of: "if connectedSignInIntent == .join {") else {
            return XCTFail("join branch not found")
        }
        let body = String(s[join.lowerBound...].prefix(400))
        XCTAssertTrue(body.contains("showMembershipSelection = true"),
                      "a joining member must continue into the flow they authenticated for")
        XCTAssertFalse(body.contains("onClose()"),
                       "the join branch must not dismiss Profile")
    }

    /// **T2.** Clearing the flag is part of the fix, not tidying:
    /// `shouldSuppressSignedInProfileAfterGateSignIn` renders `Color.clear` while
    /// it is set, so continuing into the join without clearing leaves a BLANK
    /// Profile underneath the membership screen.
    func testTheJoinBranchClearsTheGateFlag() {
        let s = code()
        guard let join = s.range(of: "if connectedSignInIntent == .join {") else {
            return XCTFail("join branch not found")
        }
        let body = String(s[join.lowerBound...].prefix(400))
        XCTAssertTrue(body.contains("signedOutGateWasVisible = false"),
                      "an unset flag blanks Profile through the suppression view")
        XCTAssertTrue(s.contains("signedOutGateWasVisible && auth.currentUserID != nil && onClose != nil"),
                      "the suppression condition this protects against must still be the one inspected")
    }

    /// **T3.** The returning/gate path is untouched — F1 narrowed nothing.
    func testTheGateUnwindIsUnchangedForEveryOtherCase() {
        let s = code()
        guard let gate = s.range(of: "if signedOutGateWasVisible {") else {
            return XCTFail("gate branch not found")
        }
        let body = String(s[gate.lowerBound...].prefix(500))
        XCTAssertTrue(body.contains("showConnectedSignInSheet = false"))
        XCTAssertTrue(body.contains("onClose()"), "a genuine gate sign-in still unwinds")
        XCTAssertTrue(s.contains("if showConnectedSignInSheet || showMembershipSelection || showConnectedIntroduction {"),
                      "the returning-member unwind is still present")
    }

    /// **T13.** The view consults exactly the policy, at BOTH sites, and makes no
    /// second decision inline — otherwise the decision drifts back into a place
    /// no test can reach.
    func testTheViewConsultsThePolicyAtBothEventsAndDecidesNothingItself() {
        let s = code()
        let calls = s.components(separatedBy: "reconcileDirectoryIfAttestationAllows()").count - 1
        XCTAssertEqual(calls, 4,
                       "one definition plus exactly three call sites: the combined input observer, "
                       + "the failure branch, and the post-load appearance re-evaluation")
        XCTAssertTrue(s.contains(".onChange(of: reconciliationInputs)"),
                      "events 1 and 3: one observer over both asynchronous inputs")
        guard let failure = s.range(of: "directorySyncMessage = DirectorySyncFailure.message(for: result.outcome)"),
              let afterFailure = s.range(of: "reconcileDirectoryIfAttestationAllows()", range: failure.upperBound..<s.endIndex) else {
            return XCTFail("event 2: the failure branch must ask too")
        }
        XCTAssertLessThan(failure.lowerBound, afterFailure.lowerBound)
        XCTAssertEqual(s.components(separatedBy: "reconciliation.evaluateAndConsume(").count - 1, 1,
                       "exactly one consultation, through the evaluator the view holds")
        // Declared as `static func shouldReconcile(` and called by its qualified
        // name exactly once, from the evaluator. A second qualified call would
        // mean the view decided something itself.
        XCTAssertEqual(s.components(separatedBy: "DirectoryReconciliationPolicy.shouldReconcile(").count - 1, 1,
                       "the policy is consulted once, from the evaluator -- never inline in the view")
    }

    /// **F3 WIRING — events 3 and 4.** The behavioural tests drive the production
    /// evaluator, which would keep passing with every observer deleted. THIS is
    /// what fails when an observer goes.
    func testBothAsynchronousInputsAreObservedAndAppearanceReevaluates() {
        let s = code()
        // Events 1 and 3 share one observer over BOTH inputs.
        XCTAssertTrue(s.contains(".onChange(of: reconciliationInputs)"),
                      "the combined observer must exist")
        guard let inputs = s.range(of: "private var reconciliationInputs: ReconciliationInputs {") else {
            return XCTFail("reconciliationInputs not found")
        }
        let body = String(s[inputs.lowerBound...].prefix(400))
        XCTAssertTrue(body.contains("attestation.lastCompletion"),
                      "event 1: the completion must be observed")
        XCTAssertTrue(body.contains("auth.directoryRowAbsence"),
                      "event 3: row absence must be observed, or completion-before-absence is missed")

        // Event 4: a remount, where both earlier events have already passed.
        guard let appear = s.range(of: "private func onAppearLoad() {") else {
            return XCTFail("onAppearLoad not found")
        }
        let appearBody = String(s[appear.lowerBound...].prefix(1400))
        XCTAssertTrue(appearBody.contains("reconcileDirectoryIfAttestationAllows()"),
                      "event 4: appearance must re-evaluate")
    }

    /// **The appearance re-evaluation must run AFTER local load and rehydration.**
    /// The snapshot a publish sends is read from the live screen, so evaluating
    /// first would publish the initial empty defaults over a real profile.
    func testTheAppearanceReevaluationRunsAfterLoadAndRehydration() {
        let s = code()
        guard let appear = s.range(of: "private func onAppearLoad() {") else {
            return XCTFail("not found")
        }
        let body = String(s[appear.lowerBound...].prefix(1400))
        guard let load = body.range(of: "load()"),
              let location = body.range(of: "self.locationText = ProfileStore.presentedLocation"),
              let evaluate = body.range(of: "reconcileDirectoryIfAttestationAllows()") else {
            return XCTFail("expected load, rehydration, then the re-evaluation")
        }
        XCTAssertLessThan(load.lowerBound, evaluate.lowerBound,
                          "evaluating before load() would publish empty defaults")
        XCTAssertLessThan(location.lowerBound, evaluate.lowerBound,
                          "evaluating before the location rehydration would publish a blank location")
    }

    /// Applied evidence must come from the accepted result's own epoch, after the
    /// acceptance guards — never from a fresh read of the coordinator.
    func testAppliedEvidenceUsesTheAcceptedResultsGeneration() {
        let s = code()
        XCTAssertTrue(s.contains("reconciliation.noteApplied(owner: backendID, generation: result.generation)"),
                      "the epoch must be the one the WRITE bound")
        guard let applied = s.range(of: "case .applied:"),
              let note = s.range(of: "reconciliation.noteApplied(") else {
            return XCTFail("not found")
        }
        XCTAssertLessThan(applied.lowerBound, note.lowerBound,
                          "evidence is recorded only on an accepted write")
    }

    /// Consumption must happen BEFORE the write is scheduled, or a refused retry
    /// finds the completion unspent and loops.
    func testTheCompletionIsConsumedBeforeTheWriteIsScheduled() {
        let s = code()
        XCTAssertTrue(s.contains("reconciliation.evaluateAndConsume("),
                      "the view must use the evaluator that consumes as it decides")
        guard let evaluate = s.range(of: "reconciliation.evaluateAndConsume("),
              let schedule = s.range(of: "scheduleDirectorySyncDebounced()", range: evaluate.upperBound..<s.endIndex) else {
            return XCTFail("expected evaluation then scheduling")
        }
        XCTAssertLessThan(evaluate.lowerBound, schedule.lowerBound)
    }

    /// F2 must not have acquired authority it is not allowed to have.
    func testTheCompletionIsNeverReadAsEntitlement() {
        let s = code()
        guard let start = s.range(of: "private func reconcileDirectoryIfAttestationAllows()") else {
            return XCTFail("not found")
        }
        let body = String(s[start.lowerBound...].prefix(1200))
        for banned in ["isEntitled", "canViewFeed", "AppMode", "connected_member"] {
            XCTAssertFalse(body.contains(banned), "\(banned) must not reach the reconciliation")
        }
    }
}

// MARK: - F2, the pure policy

/// Value tests. No view, no network, no coordinator.
@MainActor
final class DirectoryReconciliationPolicyTests: XCTestCase {

    private typealias Completion = MembershipAttestationCoordinator.AttestationCompletion
    private let owner = "11111111-1111-1111-1111-111111111111"

    private func completion(sequence: Int = 1,
                            owner: String? = nil,
                            generation: Int = 7,
                            establishes: Bool = true) -> Completion {
        Completion(sequence: sequence,
                   owner: owner ?? self.owner,
                   directoryGeneration: generation,
                   establishesMembership: establishes)
    }

    private func absence(owner: String? = nil, generation: Int = 7) -> AuthManager.DirectoryRowAbsence {
        .init(owner: owner ?? self.owner, directoryGeneration: generation)
    }

    private func applied(owner: String? = nil, generation: Int = 7) -> DirectoryReconciliationPolicy.AppliedEvidence {
        .init(owner: owner ?? self.owner, directoryGeneration: generation)
    }

    private func decide(_ c: Completion?,
                        failure: Bool = true,
                        rowAbsence: AuthManager.DirectoryRowAbsence? = nil,
                        appliedEvidence: DirectoryReconciliationPolicy.AppliedEvidence? = nil,
                        owner: String? = nil,
                        generation: Int = 7,
                        consumed: Int? = nil) -> Bool {
        DirectoryReconciliationPolicy.shouldReconcile(
            completion: c,
            hasOutstandingFailure: failure,
            rowAbsence: rowAbsence,
            appliedEvidence: appliedEvidence,
            currentOwner: owner ?? self.owner,
            currentDirectoryGeneration: generation,
            lastConsumedSequence: consumed)
    }

    func testTheHappyCaseReconciles() {
        XCTAssertTrue(decide(completion()))
    }

    func testNoCompletionNeverReconciles() {
        XCTAssertFalse(decide(nil))
    }

    /// **T9 / F3-3.** No failure AND no absence evidence — the returning member,
    /// whose row already exists. This is what keeps `alreadyEstablished` on every
    /// foreground from costing anything.
    func testAReturningMemberWithNoAbsenceEvidenceNeverReconciles() {
        XCTAssertFalse(decide(completion(), failure: false, rowAbsence: nil))
        XCTAssertFalse(decide(completion(sequence: 2), failure: false, rowAbsence: nil))
    }

    /// **F3-1 — THE FAILING DEVICE CASE.** A fresh join leaves NO message to
    /// repair, because with the join flow kept on screen nothing changed and
    /// nothing was ever scheduled. Absence evidence is what authorises it.
    func testAFreshJoinWithNoErrorReconcilesOnAbsenceEvidence() {
        XCTAssertTrue(decide(completion(), failure: false, rowAbsence: absence()))
    }

    /// **F3-2.** Once this screen has evidenced a write, no further publishes —
    /// even though absence evidence is still standing.
    func testAnEvidencedWriteSuppressesFurtherPublishes() {
        XCTAssertFalse(decide(completion(sequence: 2), failure: false,
                              rowAbsence: absence(), appliedEvidence: applied()))
    }

    /// **F3-6 — SAME OWNER, CHANGED GENERATION.** Both scopes must describe THIS
    /// session: stale applied evidence must not suppress, and stale absence
    /// evidence must not authorise.
    func testEvidenceFromAnotherGenerationNeitherAuthorisesNorSuppresses() {
        // Stale applied evidence does not suppress a current absence.
        XCTAssertTrue(decide(completion(generation: 8), failure: false,
                             rowAbsence: absence(generation: 8),
                             appliedEvidence: applied(generation: 7), generation: 8))
        // Stale absence evidence authorises nothing.
        XCTAssertFalse(decide(completion(generation: 8), failure: false,
                              rowAbsence: absence(generation: 7), generation: 8))
    }

    /// **F3-7 — A→B→A.** Neither kind of evidence from the first A session is
    /// honoured, although the owner is equal again.
    func testEvidenceFromAPreviousSessionOfTheSameOwnerIsNotHonoured() {
        XCTAssertFalse(decide(completion(generation: 9), failure: false,
                              rowAbsence: absence(generation: 7), generation: 9),
                       "an A->B->A cycle leaves the owner equal; only the generation differs")
    }

    /// Absence belonging to somebody else authorises nothing.
    func testAbsenceEvidenceForAnotherOwnerAuthorisesNothing() {
        XCTAssertFalse(decide(completion(), failure: false,
                              rowAbsence: absence(owner: "22222222-2222-2222-2222-222222222222")))
    }

    /// **F3-4/5 — PENDING, THEN LATER CONFIRMATION.** Propagation writes nothing;
    /// EITHER establishing outcome afterwards publishes, because the row is still
    /// unevidenced.
    func testPendingWritesNothingAndEitherLaterEstablishingOutcomePublishes() {
        XCTAssertFalse(decide(completion(establishes: false), failure: false, rowAbsence: absence()))
        for seq in [2, 3] {
            XCTAssertTrue(decide(completion(sequence: seq), failure: false, rowAbsence: absence()),
                          "both .established and .alreadyEstablished reach here as establishesMembership")
        }
    }

    /// **F3-9.** The repair path is unchanged, including with no absence
    /// evidence at all — a returning member whose edit was refused.
    func testTheRepairPathIsUnchangedWithoutAbsenceEvidence() {
        XCTAssertTrue(decide(completion(), failure: true, rowAbsence: nil))
    }

    /// **T10.** Exhaustive over every outcome the service can report.
    func testOnlyEstablishingOutcomesReconcile() {
        let establishing: [MembershipAttestationService.Outcome] = [.established, .alreadyEstablished]
        let notEstablishing: [MembershipAttestationService.Outcome] = [
            .conflict, .pending, .terminalRefusal(reason: "family"),
            .claimRefused(category: "bundle", terminal: true),
            .appleUnavailable, .ineligible(.notLocallyEntitled), .serverError(status: 500),
            .transport("offline")
        ]
        for o in establishing {
            XCTAssertTrue(MembershipAttestationCoordinator.establishesMembership(o), "\(o)")
        }
        for o in notEstablishing {
            XCTAssertFalse(MembershipAttestationCoordinator.establishesMembership(o), "\(o)")
            XCTAssertFalse(decide(completion(establishes: false)), "\(o) must not reconcile")
        }
    }

    /// **T8.** An A→B→A cycle leaves the OWNER equal to A again. Only the
    /// generation shows the completion belongs to the previous A.
    func testAMatchingOwnerWithAChangedGenerationDoesNotReconcile() {
        XCTAssertFalse(decide(completion(generation: 7), generation: 8),
                       "owner alone cannot establish event ownership")
    }

    func testADifferentOwnerNeverReconciles() {
        XCTAssertFalse(decide(completion(owner: "22222222-2222-2222-2222-222222222222")))
    }

    func testOwnerComparisonIsCaseAndWhitespaceInsensitive() {
        XCTAssertTrue(decide(completion(owner: owner.lowercased()),
                             owner: "  \(owner.uppercased())  "))
    }

    func testNoCurrentOwnerNeverReconciles() {
        XCTAssertFalse(decide(completion(), owner: ""))
        XCTAssertFalse(decide(completion(), owner: "   "))
    }

    /// **T6 / boundedness.** A consumed completion cannot drive a second write,
    /// so a persistently-refused retry cannot re-trigger itself.
    func testAConsumedCompletionCannotReconcileAgain() {
        XCTAssertFalse(decide(completion(sequence: 4), consumed: 4))
    }

    /// **T7.** Two completions carrying the SAME outcome are still distinct, which
    /// is exactly what `lastOutcome` equality could not express — and each is
    /// eligible at most once.
    func testRepeatedEqualOutcomesAreDistinctCompletionsAndEachIsEligibleOnce() {
        let first = completion(sequence: 1)
        let second = completion(sequence: 2)
        XCTAssertNotEqual(first, second, "equal outcomes must not collapse into one completion")
        XCTAssertTrue(decide(first, consumed: nil))
        XCTAssertFalse(decide(first, consumed: 1))
        XCTAssertTrue(decide(second, consumed: 1), "a NEW completion is new information")
        XCTAssertFalse(decide(second, consumed: 2))
    }
}

// MARK: - F2, the coordinator publishes completions it actually owns

/// **Behavioural, not structural.** Every operation parks on a continuation the
/// test releases, so publication ownership is observed rather than reasoned
/// about. No Apple, network, auth or device calls.
@MainActor
final class AttestationCompletionPublicationTests: XCTestCase {

    private typealias Outcome = MembershipAttestationService.Outcome
    private typealias Scope = MembershipAttestationCoordinator.Scope

    private let ownerA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    private let ownerB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

    private final class Gate {
        var parked: [CheckedContinuation<Outcome, Never>] = []
        var started: Int { parked.count }
        func operation() -> @MainActor () async -> Outcome {
            { [gate = self] in await withCheckedContinuation { gate.parked.append($0) } }
        }
    }

    private final class Caller {
        var done = false
        var result: Outcome?
    }

    private var gate = Gate()
    private var resumed = Set<Int>()

    override func tearDown() {
        for i in gate.parked.indices where !resumed.contains(i) { gate.parked[i].resume(returning: .pending) }
        super.tearDown()
    }

    private func resume(_ index: Int, _ outcome: Outcome) {
        resumed.insert(index)
        gate.parked[index].resume(returning: outcome)
    }

    private func call(_ c: MembershipAttestationCoordinator,
                      scope: Scope?, force: Bool = true) -> Caller {
        let caller = Caller()
        let op = gate.operation()
        Task { @MainActor in
            caller.result = await c.coordinate(force: force, scope: scope, operation: op)
            caller.done = true
        }
        return caller
    }

    private struct WaitTimedOut: Error { let what: String }

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

    // MARK: publication ownership

    func testAnEstablishingRunPublishesItsOwnScope() async throws {
        let c = MembershipAttestationCoordinator()
        let a = call(c, scope: Scope(owner: ownerA, directoryGeneration: 3))
        try await waitUntil("started") { self.gate.started == 1 }
        resume(0, .established)
        try await waitUntil("returned") { a.done }

        let completion = try XCTUnwrap(c.lastCompletion)
        XCTAssertEqual(completion.owner, ownerA)
        XCTAssertEqual(completion.directoryGeneration, 3)
        XCTAssertTrue(completion.establishesMembership)
    }

    /// **A JOINER NEVER OWNS THE COMPLETION.** The starter's scope was captured
    /// before its own await and is the only one describing the run; publishing
    /// under the joiner's would attribute one run to another caller's session.
    func testAJoiningCallerDoesNotPublishItsOwnScope() async throws {
        let c = MembershipAttestationCoordinator()
        let starter = call(c, scope: Scope(owner: ownerA, directoryGeneration: 1))
        try await waitUntil("starter started") { self.gate.started == 1 }

        let joiner = call(c, scope: Scope(owner: ownerB, directoryGeneration: 99))
        try await waitUntil("joiner joined") { c.joinCount == 1 }
        XCTAssertEqual(gate.started, 1, "the joiner must not start a second run")

        resume(0, .established)
        try await waitUntil("both returned") { starter.done && joiner.done }

        let completion = try XCTUnwrap(c.lastCompletion)
        XCTAssertEqual(completion.owner, ownerA, "the STARTER owns the completion")
        XCTAssertEqual(completion.directoryGeneration, 1)
        XCTAssertEqual(joiner.result, .established, "the joiner still receives the outcome")
    }

    /// **T8 / same-owner reset during an in-flight run.** The identity does not
    /// change, so an owner comparison would be satisfied; only supersession
    /// suppresses the publication.
    func testASameOwnerResetDuringAnInFlightRunPublishesNoCompletion() async throws {
        let c = MembershipAttestationCoordinator()
        let scope = Scope(owner: ownerA, directoryGeneration: 4)
        let a = call(c, scope: scope)
        try await waitUntil("started") { self.gate.started == 1 }

        c.reset()
        resume(0, .established)
        try await waitUntil("returned") { a.done }

        XCTAssertNil(a.result)
        XCTAssertNil(c.lastOutcome)
        XCTAssertNil(c.lastCompletion, "a superseded run publishes NO completion, not merely no outcome")
    }

    /// `reset()` must clear the completion even when it is the only populated
    /// field — otherwise a consumer keeps a hint for an identity that has gone.
    func testResetClearsTheCompletionEvenWhenItIsTheOnlyThingLeft() async throws {
        let c = MembershipAttestationCoordinator()
        let a = call(c, scope: Scope(owner: ownerA, directoryGeneration: 2))
        try await waitUntil("started") { self.gate.started == 1 }
        resume(0, .established)
        try await waitUntil("returned") { a.done }
        XCTAssertNotNil(c.lastCompletion)

        c.reset()
        XCTAssertNil(c.lastCompletion)
        XCTAssertNil(c.lastOutcome)
    }

    /// **T7 at the coordinator.** Two runs returning the SAME outcome must still
    /// produce distinct completions, and the sequence must be monotonic.
    func testRepeatedEqualOutcomesProduceDistinctMonotonicSequences() async throws {
        let c = MembershipAttestationCoordinator()
        let scope = Scope(owner: ownerA, directoryGeneration: 5)

        let first = call(c, scope: scope)
        try await waitUntil("first started") { self.gate.started == 1 }
        resume(0, .established)
        try await waitUntil("first returned") { first.done }
        let one = try XCTUnwrap(c.lastCompletion)

        let second = call(c, scope: scope)
        try await waitUntil("second started") { self.gate.started == 2 }
        resume(1, .established)
        try await waitUntil("second returned") { second.done }
        let two = try XCTUnwrap(c.lastCompletion)

        XCTAssertEqual(c.lastOutcome, .established, "the diagnostic value is identical")
        XCTAssertNotEqual(one, two, "yet the completions are distinct")
        XCTAssertGreaterThan(two.sequence, one.sequence, "sequence is monotonic")
    }

    /// A reset between runs must not make the sequence go backwards: a consumer
    /// comparing against a consumed sequence would then skip a genuine retry.
    func testTheSequenceStaysMonotonicAcrossAReset() async throws {
        let c = MembershipAttestationCoordinator()
        let scope = Scope(owner: ownerA, directoryGeneration: 6)

        let first = call(c, scope: scope)
        try await waitUntil("first started") { self.gate.started == 1 }
        resume(0, .established)
        try await waitUntil("first returned") { first.done }
        let one = try XCTUnwrap(c.lastCompletion).sequence

        c.reset()

        let second = call(c, scope: scope)
        try await waitUntil("second started") { self.gate.started == 2 }
        resume(1, .established)
        try await waitUntil("second returned") { second.done }
        XCTAssertGreaterThan(try XCTUnwrap(c.lastCompletion).sequence, one)
    }

    /// A non-establishing outcome still publishes a completion — the consumer,
    /// not the coordinator, decides what to do with it — but it must be marked
    /// honestly.
    func testAPendingOutcomePublishesANonEstablishingCompletion() async throws {
        let c = MembershipAttestationCoordinator()
        let a = call(c, scope: Scope(owner: ownerA, directoryGeneration: 8))
        try await waitUntil("started") { self.gate.started == 1 }
        resume(0, .pending)
        try await waitUntil("returned") { a.done }

        let completion = try XCTUnwrap(c.lastCompletion)
        XCTAssertFalse(completion.establishesMembership,
                       "propagation is not success and must never authorise a retry")
    }

    /// A run with no identity to name publishes no completion claiming one.
    func testARunWithNoScopePublishesAnOutcomeButNoCompletion() async throws {
        let c = MembershipAttestationCoordinator()
        let a = call(c, scope: nil)
        try await waitUntil("started") { self.gate.started == 1 }
        resume(0, .established)
        try await waitUntil("returned") { a.done }

        XCTAssertEqual(c.lastOutcome, .established)
        XCTAssertNil(c.lastCompletion)
    }

    func testScopeRefusesAnEmptyOwnerAndNormalisesTheRest() {
        XCTAssertNil(MembershipAttestationCoordinator.scope(owner: nil, directoryGeneration: 1))
        XCTAssertNil(MembershipAttestationCoordinator.scope(owner: "   ", directoryGeneration: 1))
        XCTAssertEqual(MembershipAttestationCoordinator.scope(owner: "  \(ownerA.uppercased()) ",
                                                              directoryGeneration: 2),
                       Scope(owner: ownerA, directoryGeneration: 2))
    }
}

// MARK: - F3-8, the guarded publication of row-absence evidence

/// **Behavioural at the `AuthManager` level.** `applyDirectoryRowAbsence` is the
/// one place a fetch result reaches `directoryRowAbsence`, and it must drop a
/// result whose session is no longer current — in BOTH directions.
///
/// **WHAT THESE DO AND DO NOT ESTABLISH.** They drive the real guarded method on
/// a real `AuthManager`, so the GUARD is exercised as production runs it. They
/// do **not** exercise an actual delayed network fetch: no `fetchSelfRow` runs,
/// and no identity really changes mid-await. What makes the guard reach real
/// hydration is the *wiring* — the scope captured BEFORE the await and the two
/// call sites — which the structural assertions below pin. Neither half proves
/// the other, and hydration itself is unchanged and unexercised.
@MainActor
final class DirectoryRowAbsenceGuardTests: XCTestCase {

    private let ownerA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    private let ownerB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    private var savedUserID: String?

    /// The identity is seeded the way `AuthManager.init` reads it, so no
    /// test-only mutation surface is added to production for this.
    private func auth(as owner: String) -> AuthManager {
        UserDefaults.standard.set(owner, forKey: "supabaseUserID_v1")
        return AuthManager()
    }

    private func scope(_ owner: String, _ generation: Int) -> AuthManager.DirectoryRowAbsence {
        .init(owner: owner, directoryGeneration: generation)
    }

    private var generation: Int { DirectoryWriteCoordinator.shared.identityGeneration }

    override func setUp() async throws {
        try await super.setUp()
        savedUserID = UserDefaults.standard.string(forKey: "supabaseUserID_v1")
        DirectoryWriteCoordinator.shared.resetForTesting()
    }

    override func tearDown() async throws {
        if let savedUserID {
            UserDefaults.standard.set(savedUserID, forKey: "supabaseUserID_v1")
        } else {
            UserDefaults.standard.removeObject(forKey: "supabaseUserID_v1")
        }
        DirectoryWriteCoordinator.shared.resetForTesting()
        try await super.tearDown()
    }

    /// A fetch whose scope is still current publishes its absence.
    func testACurrentNoRowResultPublishesAbsence() {
        let a = auth(as: ownerA)
        let s = scope(ownerA, generation)
        a.applyDirectoryRowAbsence(s, absent: true)
        XCTAssertEqual(a.directoryRowAbsence, s)
    }

    /// **A stale fetch asserts nothing.** The owner changed across the await.
    func testANoRowResultForAReplacedOwnerPublishesNothing() {
        let a = auth(as: ownerB)
        a.applyDirectoryRowAbsence(scope(ownerA, generation), absent: true)
        XCTAssertNil(a.directoryRowAbsence)
    }

    /// **The A->B->A case an owner check alone cannot see.** The owner is equal
    /// again; only the generation shows the fetch belongs to a previous session.
    func testANoRowResultFromASupersededGenerationPublishesNothing() {
        let a = auth(as: ownerA)
        let stale = scope(ownerA, generation)
        DirectoryWriteCoordinator.shared.noteIdentityTransition()
        a.applyDirectoryRowAbsence(stale, absent: true)
        XCTAssertNil(a.directoryRowAbsence)
    }

    /// **THE CLEAR IS GUARDED THE SAME WAY — a stale ROW-FOUND must not clear a
    /// newer identity's absence evidence.**
    func testAStaleRowFoundDoesNotClearANewerIdentitysAbsence() {
        let a = auth(as: ownerA)
        let current = scope(ownerA, generation)
        a.applyDirectoryRowAbsence(current, absent: true)
        XCTAssertEqual(a.directoryRowAbsence, current)

        // A row-found result from a DIFFERENT owner's fetch arrives late.
        a.applyDirectoryRowAbsence(scope(ownerB, generation), absent: false)
        XCTAssertEqual(a.directoryRowAbsence, current, "the newer identity's absence must survive")

        // And one from a superseded generation of the SAME owner.
        a.applyDirectoryRowAbsence(scope(ownerA, generation - 1), absent: false)
        XCTAssertEqual(a.directoryRowAbsence, current)
    }

    /// **WIRING — the capture must happen BEFORE the await**, or the guard has
    /// nothing honest to compare against: the owner check in hydration runs
    /// before the suspension, so a value read afterwards proves nothing.
    func testTheAbsenceScopeIsCapturedBeforeTheFetch() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let src = (try? String(contentsOf: root.appendingPathComponent("MOTIVO/AuthManager.swift"),
                               encoding: .utf8)) ?? ""
        XCTAssertFalse(src.isEmpty, "AuthManager.swift not found")

        guard let capture = src.range(of: "let absenceScope = DirectoryRowAbsence("),
              let fetch = src.range(of: "await AccountDirectoryService.shared.fetchSelfRow(userID: userID)") else {
            return XCTFail("expected the scope to be captured before the fetch")
        }
        XCTAssertLessThan(capture.lowerBound, fetch.lowerBound,
                          "capturing after the await would describe a session that may have been replaced")
    }

    /// **WIRING — both call sites exist**, so the guard is reached on a no-row
    /// result and on a row-found result alike.
    func testBothHydrationOutcomesReachTheGuardedApplier() {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let src = (try? String(contentsOf: root.appendingPathComponent("MOTIVO/AuthManager.swift"),
                               encoding: .utf8)) ?? ""
        XCTAssertTrue(src.contains("self.applyDirectoryRowAbsence(absenceScope, absent: true)"),
                      "the no-row branch must publish absence through the guard")
        XCTAssertTrue(src.contains("self.applyDirectoryRowAbsence(absenceScope, absent: false)"),
                      "the row-found branch must clear through the SAME guard")
        // ONE assignment from a fetch result, inside the guarded applier, plus
        // the two identity-teardown clears that sit beside the existing
        // `backendBootstrapState` resets. Counted separately so a new unguarded
        // assignment cannot hide among them.
        XCTAssertEqual(src.components(separatedBy: "directoryRowAbsence = absent ? scope : nil").count - 1, 1,
                       "exactly one result-driven assignment, and it is inside the guard")
        XCTAssertEqual(src.components(separatedBy: "self.directoryRowAbsence = nil").count - 1, 2,
                       "the two identity-teardown clears")
        XCTAssertEqual(src.components(separatedBy: "directoryRowAbsence = ").count - 1, 3,
                       "and NO other assignment anywhere")
    }

    /// A current row-found result does clear it.
    func testACurrentRowFoundClearsAbsence() {
        let a = auth(as: ownerA)
        let s = scope(ownerA, generation)
        a.applyDirectoryRowAbsence(s, absent: true)
        a.applyDirectoryRowAbsence(s, absent: false)
        XCTAssertNil(a.directoryRowAbsence)
    }
}
