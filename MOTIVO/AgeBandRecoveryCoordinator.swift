//
//  AgeBandRecoveryCoordinator.swift
//  MOTIVO
//
//  PHASE 5 · CP-3 — recovery from `identityWithoutBand`.
//
//  THE STATE THIS EXISTS FOR IS REAL AND WAS OBSERVED ON HARDWARE (2026-09-07):
//  Sign in with Apple minted an identity, the band write did not happen, and the
//  identity outlived the failure. Directory publication was correctly suppressed,
//  so nothing unsafe existed -- but nothing recovered it either, because the
//  derived band lives in memory and does not survive process death.
//
//  ── WHY IT RE-ASKS APPLE RATHER THAN PERSISTING THE BAND ───────────────────
//
//  Persisting the derived band locally would make recovery trivial and would be
//  WRONG: after process death the client would be asserting an age it can no
//  longer justify, from storage rather than from Apple. **No band may be invented
//  after process death.** So recovery re-acquires the range from Apple, which is
//  cheap -- Apple caches its answer and re-prompts only on the declaration
//  anniversary, so the usual case presents no UI at all.
//
//  ── THE U5f PATTERN, DELIBERATELY COPIED ───────────────────────────────────
//
//  Single-flight plus an in-memory cooldown, and NOT gated on Connected mode
//  already being active: the member this rescues is precisely the one whose
//  Connected state is incomplete. Persisting the cooldown would make a previous
//  failure permanent authority, which is the mistake U5f's record calls out.
//

import Foundation

@MainActor
final class AgeBandRecoveryCoordinator: ObservableObject {

    /// Long enough that a device Apple cannot serve never becomes a prompt loop;
    /// short enough that an ordinary relaunch recovers. In memory only.
    static let cooldown: TimeInterval = 60

    private var inFlight = false
    private var lastAttemptAt: Date?

    /// PURE. The gate, so "when do we even try" is testable without Apple,
    /// a network, or a view.
    static func shouldAttempt(hasConnectedIdentity: Bool,
                              backendConfigured: Bool,
                              inFlight: Bool,
                              lastAttemptAt: Date?,
                              now: Date,
                              cooldown: TimeInterval = AgeBandRecoveryCoordinator.cooldown) -> Bool {
        guard hasConnectedIdentity else { return false }
        guard backendConfigured else { return false }
        guard !inFlight else { return false }
        guard let last = lastAttemptAt else { return true }
        return now.timeIntervalSince(last) >= cooldown
    }

    /// PURE. Only a derived band may be written. `ineligible` and `unavailable`
    /// stay non-eligible, so a decline or an error can never establish a band.
    static func bandToEstablish(from outcome: DeclaredAgeRangeOutcome) -> AgeBand? {
        if case .band(let band) = outcome { return band }
        return nil
    }

    /// Re-acquires the range and retries establishment, once.
    ///
    /// Idempotent: an identity that already has a band short-circuits before any
    /// Apple call, and the server writer is insert-if-absent, so a concurrent or
    /// repeated attempt cannot create a second row or move `band_updated_at`.
    func recoverIfNeeded(auth: AuthManager,
                         reason: String,
                         now: Date = Date(),
                         requestRange: () async -> DeclaredAgeRangeOutcome) async {
        guard Self.shouldAttempt(hasConnectedIdentity: auth.hasConnectedIdentity,
                                 backendConfigured: BackendConfig.isConfigured,
                                 inFlight: inFlight,
                                 lastAttemptAt: lastAttemptAt,
                                 now: now) else { return }

        // Already established? Short-circuit BEFORE asking Apple.
        //
        // A transport or session failure is NOT "no band" -- reading it as one
        // would re-ask Apple on every foreground during an outage. Only an
        // explicit `noBandEstablished` proceeds.
        switch await AccountPrivacyService.fetchSelf(auth: auth, reason: "recovery-\(reason)") {
        case .success:
            return
        case .failure(.noBandEstablished):
            break
        case .failure:
            return
        }

        inFlight = true
        lastAttemptAt = now
        defer { inFlight = false }

        guard let band = Self.bandToEstablish(from: await requestRange()) else { return }

        // The band reaches authenticated server state here, and ONLY here does
        // directory publication become permissible again -- CP-1's trigger
        // enforces that independently.
        auth.pendingAgeBand = band
        _ = await auth.ensureAgeBandEstablished(reason: "recovery-\(reason)")
    }
}
