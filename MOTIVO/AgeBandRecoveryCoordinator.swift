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
    /// Apple call, so the writer is not reached on that path.
    ///
    /// **The writer is NOT insert-if-absent** -- corrected P5-G, 2026-09-08.
    /// `account_privacy_upsert_v1` updates `age_band` on conflict and stamps
    /// `band_updated_at` only on a real change. A concurrent or repeated attempt
    /// therefore cannot create a second row, and cannot move `band_updated_at`
    /// while the band is unchanged -- which is what this call site relies on.
    func recoverIfNeeded(auth: AuthManager,
                         reason: String,
                         now: Date = Date(),
                         requestRange: () async -> DeclaredAgeRangeOutcome) async {
        guard Self.shouldAttempt(hasConnectedIdentity: auth.hasConnectedIdentity,
                                 backendConfigured: BackendConfig.isConfigured,
                                 inFlight: inFlight,
                                 lastAttemptAt: lastAttemptAt,
                                 now: now) else { return }

        // Already established? Then this is a REFRESH, not a recovery.
        //
        // A transport or session failure is NOT "no band" -- reading it as one
        // would re-ask Apple on every foreground during an outage. Only an
        // explicit `noBandEstablished` falls through to establishment.
        switch await AccountPrivacyService.fetchSelf(auth: auth, reason: "recovery-\(reason)") {
        case .success:
            // P5-G/D1. An established band is re-derived on the product cadence
            // so a reclassification is observed. Apple provides no change
            // signal, so asking is the only mechanism (register §E2).
            await refreshIfDue(auth: auth, reason: reason, now: now, requestRange: requestRange)
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

    // MARK: - P5-G / D1 — periodic re-derivation

    /// Re-derives an ALREADY-ESTABLISHED band when the automatic throttle says
    /// it is due, and applies the result asymmetrically.
    ///
    /// **NOT GATED ON `AppMode`, and that is load-bearing.** A withheld member
    /// is in Solo precisely because eligibility was withdrawn; gating refresh on
    /// Connected being active would make withholding PERMANENT and unrecoverable
    /// — the `C5f-12` failure, one unit later.
    func refreshIfDue(auth: AuthManager,
                      reason: String,
                      now: Date = Date(),
                      requestRange: () async -> DeclaredAgeRangeOutcome) async {
        guard let userID = auth.currentUserID else { return }
        guard AgeBandRefreshPolicy.isAutomaticRefreshDue(
                lastConclusiveAt: AgeBandRefreshPolicy.lastConclusive(userID: userID),
                lastAttemptAt: AgeBandRefreshPolicy.lastAttempt(userID: userID),
                now: now) else { return }
        await performRefresh(auth: auth, reason: "auto-\(reason)", now: now, requestRange: requestRange)
    }

    /// The member-initiated "Check Again". Bypasses BOTH automatic throttles;
    /// only the in-memory single-flight still applies, so a deliberate check is
    /// never refused because an earlier one failed.
    func refreshNow(auth: AuthManager,
                    reason: String,
                    now: Date = Date(),
                    requestRange: () async -> DeclaredAgeRangeOutcome) async {
        await performRefresh(auth: auth, reason: "explicit-\(reason)", now: now, requestRange: requestRange)
    }

    private func performRefresh(auth: AuthManager,
                                reason: String,
                                now: Date,
                                requestRange: () async -> DeclaredAgeRangeOutcome) async {
        guard let userID = auth.currentUserID else { return }
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        _ = userID
        // One policy, one application point — see `AuthManager.applyAgeRefresh`.
        await auth.applyAgeRefresh(outcome: await requestRange(), reason: reason, now: now)
    }
}
