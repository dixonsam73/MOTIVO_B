//
//  MembershipAttestationCoordinator.swift
//  MOTIVO
//
//  PHASE 3 · U5f — the attestation trigger, and the ONE place the invariant lives.
//
//  ── THE INVARIANT ─────────────────────────────────────────────────────────
//
//      locally entitled  ∧  hasConnectedIdentity  ∧  BackendConfig.isConfigured
//
//  and NOTHING ELSE. Not `canViewFeed`. Not `AppMode == .connected`. Not whether
//  a membership row already exists.
//
//  **THIS IS WHAT MAKES A DORMANT PRE-CUTOVER SUBSCRIBER'S RETURN SELF-HEALING
//  WITHIN A SINGLE LAUNCH** — G11's whole scenario. Gate it on Connected already
//  being active and the member who most needs it is precisely the member who
//  cannot reach it: they are in Solo because the server does not know them yet,
//  and they stay there because attestation never runs. Gate it on a row existing
//  and it can never create the first one.
//
//  The alternative — making activation AWAIT attestation — was considered and
//  rejected when the invariant was settled: it would put a network round trip on
//  a cold-launch path that is entirely local today, and would invert the split in
//  which the client governs UI reversibly and the server governs the API
//  authoritatively. **The worst case under this design is a few denied requests
//  in the first seconds of a cold launch. Not a lockout.**
//
//  ── DUPLICATE SUPPRESSION, AND ITS TWO DELIBERATE LIMITS ──────────────────
//
//  Six triggers can fire close together — launch, foreground, entitlement
//  resolving, identity arriving, purchase, restore — so without coordination a
//  single cold launch could attest four times.
//
//  Two mechanisms, both **IN MEMORY ONLY**:
//
//    single-flight  concurrent callers await the SAME task, exactly as
//                   AuthManager coalesces session refreshes.
//    cooldown       a repeat within `minimumInterval` is skipped, unless the
//                   caller passes `force` — which purchase and restore do,
//                   because those are user-initiated and must not be swallowed.
//
//  **NEITHER IS PERSISTED, AND THAT IS LOAD-BEARING RATHER THAN LAZY.** A stored
//  "already attested" flag would become client-held authority over server
//  membership, which invariant 3 forbids, and it would defeat G11: the dormant
//  returner's whole recovery depends on a cold launch attesting again. State
//  resets on every launch, deliberately.
//
//  **A PREVIOUS SUCCESS IS NEVER PERMANENT AUTHORITY.** `lastOutcome` is
//  diagnostics for the UI layer to read once; nothing here treats it as proof of
//  membership, and the server re-derives from Apple on every call.
//
//  ── WHAT IT DOES NOT DO ───────────────────────────────────────────────────
//
//  It does not switch app mode, does not touch entitlement, does not know what
//  Connected is. `AppMode` continues to resolve from local StoreKit exactly as
//  before. Attestation informs the SERVER; it does not decide the client's UI.
//

import Foundation

@MainActor
final class MembershipAttestationCoordinator: ObservableObject {

    /// The most recent result, for the UI to consult after a user-initiated
    /// action. **Diagnostics, never authority** — see the note above.
    @Published private(set) var lastOutcome: MembershipAttestationService.Outcome?
    @Published private(set) var isAttesting: Bool = false

    /// **A RECONCILIATION HINT, AND NOTHING ELSE. NEVER MEMBERSHIP AUTHORITY.**
    ///
    /// `lastOutcome` alone cannot drive a reconciliation, for two reasons that
    /// are easy to miss. It is a DIAGNOSTIC VALUE, so two genuinely distinct
    /// completions carrying the same outcome are indistinguishable and an
    /// `onChange` collapses them. And it carries no ownership, so a reader
    /// re-reading the CURRENT owner cannot tell whether the completion belongs
    /// to the session now on screen — an A→B→A cycle leaves the owner equal to A
    /// again.
    ///
    /// This token fixes both: `sequence` is unique per completion, and
    /// `owner` + `directoryGeneration` are captured BEFORE the attestation
    /// await, so a completion resting on a session that has since been torn down
    /// and rebuilt is stale by construction rather than by inspection.
    ///
    /// **A consumer may use it to decide whether to RETRY A WRITE. It may never
    /// be read as proof that the member is entitled** — the server decides that,
    /// on every request, and this type has never been in that path.
    @Published private(set) var lastCompletion: AttestationCompletion?

    /// Long enough to collapse a launch burst, short enough that a genuine retry
    /// after a propagation delay lands on the next foreground rather than much
    /// later. Attestation is cheap and idempotent server-side, so erring short
    /// costs little; erring long delays a legacy claim's second pass.
    private let minimumInterval: TimeInterval = 30

    private var inFlight: Task<MembershipAttestationService.Outcome?, Never>?
    private var lastAttemptAt: Date?

    /// The scope a completion is published under, captured before the run's
    /// await so it names the session that STARTED the attestation.
    struct Scope: Equatable {
        let owner: String
        let directoryGeneration: Int
    }

    /// A single completed attestation, uniquely identified.
    ///
    /// `sequence` is the coordinator's own run generation, so **two completions
    /// with identical outcomes still differ** — which is exactly what
    /// `lastOutcome` equality could not express.
    struct AttestationCompletion: Equatable {
        let sequence: Int
        let owner: String
        let directoryGeneration: Int
        /// Whether the server established or confirmed ownership on this run.
        /// Derived here so a consumer never re-derives it from the outcome and
        /// drifts; every other case is false.
        let establishesMembership: Bool
    }

    /// P6-I-05. Which run owns the published state. A start and a real `reset()`
    /// each advance it, so a run that finishes after a reset (cancelled or not)
    /// finds it has been superseded and publishes nothing. This suppresses the
    /// CLIENT's publication only: cancellation does not prove the request never
    /// reached the server, and the server remains the authority either way.
    private var generation = 0

    /// How many callers have joined an in-flight run. In memory, for tests to
    /// observe that a caller really reached the join path; never read as state.
    private(set) var joinCount = 0

    /// The single entry point. Every trigger routes here.
    ///
    /// `isLocallyEntitled` is passed IN rather than read, so this type has no
    /// dependency on the entitlement store and cannot quietly acquire one.
    @discardableResult
    func attestIfNeeded(
        auth: AuthManager,
        isLocallyEntitled: Bool,
        reason: String,
        force: Bool = false
    ) async -> MembershipAttestationService.Outcome? {
        // THE INVARIANT, and the whole of it.
        guard isLocallyEntitled,
              auth.hasConnectedIdentity,
              BackendConfig.isConfigured else { return nil }

        // Never run destructive-workflow-adjacent work during a local reset.
        guard !LocalFactoryReset.isInProgress else { return nil }

        // CAPTURED BEFORE THE AWAIT, and this is the whole point of the scope.
        // Read after the attestation returns, both values could describe a
        // session that replaced the one this run was started for — and an A→B→A
        // cycle would leave the owner looking correct. The same reasoning as
        // U5f's attestation epoch and C-70's write epoch.
        let scope = Self.scope(owner: auth.backendUserID,
                               directoryGeneration: DirectoryWriteCoordinator.shared.identityGeneration)

        return await coordinate(force: force, scope: scope) {
            await MembershipAttestationService.attest(
                auth: auth,
                isLocallyEntitled: isLocallyEntitled,
                reason: reason
            )
        }
    }

    /// Single-flight, cooldown and completion ownership, without the trigger
    /// guards (which stay in `attestIfNeeded`, the only production caller).
    ///
    /// The run's own task does the bookkeeping, so exactly one place publishes,
    /// whichever awaiter resumes first. A run superseded by `reset()` returns nil
    /// to its starter and to every caller that joined it, and changes nothing.
    /// - Parameter scope: the STARTER's owner and directory generation. Defaulted
    ///   so existing callers are unaffected; `nil` publishes an outcome and no
    ///   completion, which is what a caller with no identity to name should do.
    func coordinate(
        force: Bool,
        scope: Scope? = nil,
        operation: @escaping @MainActor () async -> MembershipAttestationService.Outcome
    ) async -> MembershipAttestationService.Outcome? {
        if let existing = inFlight {
            // A JOINER NEVER OWNS THE COMPLETION. It awaits the starter's run and
            // receives the starter's outcome; publishing under the joiner's scope
            // would attribute one run's completion to a different caller's
            // session. The starter's scope was captured before its own await and
            // is the only one that describes this run.
            joinCount += 1
            return await existing.value
        }
        if !force, let last = lastAttemptAt,
           Date().timeIntervalSince(last) < minimumInterval {
            return nil
        }

        lastAttemptAt = Date()
        isAttesting = true
        generation += 1
        let mine = generation

        let task = Task<MembershipAttestationService.Outcome?, Never> { @MainActor in
            let outcome = await operation()
            // SUPERSEDED RUNS PUBLISH NOTHING — outcome and completion alike. A
            // completion from a run a `reset()` has already disowned would name a
            // session that no longer exists, which is precisely the staleness the
            // token is for.
            guard self.generation == mine else { return nil }   // superseded by reset()
            self.inFlight = nil
            self.isAttesting = false
            self.lastOutcome = outcome
            if let scope {
                self.lastCompletion = AttestationCompletion(
                    sequence: mine,
                    owner: scope.owner,
                    directoryGeneration: scope.directoryGeneration,
                    establishesMembership: Self.establishesMembership(outcome))
            }
            return outcome
        }
        inFlight = task
        return await task.value
    }

    /// Clears the in-memory coordination so the next trigger runs immediately.
    /// Used after account deletion and sign-out, where the next attestation
    /// concerns a different identity and must not be throttled by this one's.
    func reset() {
        // C-55: publish ONLY when there is something to clear. `@Published`
        // has no equality check, so `lastOutcome = nil` over an already-nil
        // value still sends `objectWillChange` on a root `@StateObject` —
        // which invalidated the root body, re-delivered the publisher feeding
        // the `.onReceive` that calls this, and re-entered on the next frame.
        // The guard changes nothing about a real reset: whenever any value is
        // non-default the full clear runs exactly as before.
        //
        // `lastCompletion` JOINS THE CONDITION rather than being cleared outside
        // it: a reset that left a completion standing because every other field
        // happened to be default would leave a consumer holding a hint for an
        // identity that has just gone.
        if inFlight == nil, lastAttemptAt == nil, lastOutcome == nil,
           lastCompletion == nil, !isAttesting { return }

        generation += 1   // any run still in flight no longer owns the state
        inFlight?.cancel()
        inFlight = nil
        lastAttemptAt = nil
        lastOutcome = nil
        lastCompletion = nil
        isAttesting = false
    }

    /// `nil` owner yields no scope: a run with no identity to name must not
    /// publish a completion that claims one.
    static func scope(owner: String?, directoryGeneration: Int) -> Scope? {
        guard let owner = owner?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !owner.isEmpty else { return nil }
        return Scope(owner: owner, directoryGeneration: directoryGeneration)
    }

    /// The ONLY place an outcome is mapped to "the server now knows this member".
    ///
    /// `alreadyEstablished` counts: the row exists and was refreshed through the
    /// canonical path, which is the same standing as a first establishment for
    /// anything downstream. Every other case — including `pending`, which is
    /// propagation rather than failure — is false.
    static func establishesMembership(_ outcome: MembershipAttestationService.Outcome) -> Bool {
        switch outcome {
        case .established, .alreadyEstablished:
            return true
        case .conflict, .pending, .terminalRefusal, .claimRefused,
             .appleUnavailable, .ineligible, .serverError, .transport:
            return false
        }
    }
}
