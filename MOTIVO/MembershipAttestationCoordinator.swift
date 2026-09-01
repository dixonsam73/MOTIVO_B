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

    /// Long enough to collapse a launch burst, short enough that a genuine retry
    /// after a propagation delay lands on the next foreground rather than much
    /// later. Attestation is cheap and idempotent server-side, so erring short
    /// costs little; erring long delays a legacy claim's second pass.
    private let minimumInterval: TimeInterval = 30

    private var inFlight: Task<MembershipAttestationService.Outcome, Never>?
    private var lastAttemptAt: Date?

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

        if let existing = inFlight {
            return await existing.value
        }
        if !force, let last = lastAttemptAt,
           Date().timeIntervalSince(last) < minimumInterval {
            return nil
        }

        lastAttemptAt = Date()
        isAttesting = true

        let task = Task<MembershipAttestationService.Outcome, Never> {
            await MembershipAttestationService.attest(
                auth: auth,
                isLocallyEntitled: isLocallyEntitled,
                reason: reason
            )
        }
        inFlight = task
        let outcome = await task.value
        inFlight = nil
        isAttesting = false
        lastOutcome = outcome
        return outcome
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
        if inFlight == nil, lastAttemptAt == nil, lastOutcome == nil, !isAttesting { return }

        inFlight?.cancel()
        inFlight = nil
        lastAttemptAt = nil
        lastOutcome = nil
        isAttesting = false
    }
}
