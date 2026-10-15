//
//  ConnectedAgeRecheck.swift
//  MOTIVO
//
//  The adult-only gate's automatic check, at launch, on every return to the
//  app and on sign-in. It replaces CP-3's AgeBandRecoveryCoordinator and
//  AgeBandRecoveryTrigger, and keeps their two lessons:
//
//  - Apple's request is read from a VIEW. Read from `App` scope it presented
//    nothing and established nothing on device (2026-09-08).
//  - Single-flight plus an in-memory cooldown, so a device Apple can't serve
//    never becomes a prompt loop.
//
//  It also keeps recovery's job: a confirmed adult whose identity has no
//  `account_privacy` row gets one (`band_18_plus`), because the directory
//  trigger refuses a directory row without it.
//
//  Apple caches its answer, so the usual check shows nothing.
//

import SwiftUI

#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif

@MainActor
final class ConnectedAgeRecheck: ObservableObject {

    nonisolated static let cooldown: TimeInterval = 60

    /// Mirrors the stored result, so Profile can explain a paused Connected.
    @Published private(set) var stored: ConnectedAgeGate.StoredResult? = ConnectedAgeGate.storedResult()

    private var inFlight = false
    private var lastAttemptAt: Date?

    /// PURE. When the automatic check runs.
    static func shouldAttempt(hasConnectedIdentity: Bool,
                              backendConfigured: Bool,
                              stored: ConnectedAgeGate.StoredResult?,
                              osCanReportConfirmed: Bool,
                              inFlight: Bool,
                              lastAttemptAt: Date?,
                              now: Date,
                              cooldown: TimeInterval = ConnectedAgeRecheck.cooldown) -> Bool {
        guard hasConnectedIdentity, backendConfigured, !inFlight else { return false }
        guard ConnectedAgeGate.shouldCheckAutomatically(stored: stored,
                                                        osCanReportConfirmed: osCanReportConfirmed) else { return false }
        guard let last = lastAttemptAt else { return true }
        return now.timeIntervalSince(last) >= cooldown
    }

    /// A different identity must not inherit this one's cooldown.
    func resetCooldown() {
        lastAttemptAt = nil
    }

    func checkIfNeeded(auth: AuthManager,
                       reason: String,
                       now: Date = Date(),
                       check: () async -> ConnectedAgeGate.Outcome,
                       onRecorded: () -> Void) async {
        guard Self.shouldAttempt(hasConnectedIdentity: auth.hasConnectedIdentity,
                                 backendConfigured: BackendConfig.isConfigured,
                                 stored: ConnectedAgeGate.storedResult(),
                                 osCanReportConfirmed: ConnectedAgeGate.osCanReportConfirmed,
                                 inFlight: inFlight,
                                 lastAttemptAt: lastAttemptAt,
                                 now: now) else { return }
        inFlight = true
        lastAttemptAt = now
        defer { inFlight = false }

        await record(await check(), auth: auth, reason: reason)
        onRecorded()
    }

    /// A check the person asked for: Continue on the join path, or Try Again
    /// on a paused Connected. Bypasses the cooldown and the "don't re-ask
    /// after a refusal" rule, but not single-flight.
    func checkNow(auth: AuthManager,
                  reason: String,
                  check: () async -> ConnectedAgeGate.Outcome) async -> ConnectedAgeGate.Outcome? {
        guard !inFlight else { return nil }
        inFlight = true
        defer { inFlight = false }
        let outcome = await check()
        await record(outcome, auth: auth, reason: reason)
        return outcome
    }

    /// Stores the outcome and, for a confirmed adult with an identity, makes
    /// sure the server holds the adult row.
    func record(_ outcome: ConnectedAgeGate.Outcome, auth: AuthManager, reason: String) async {
        let next = ConnectedAgeGate.nextStoredResult(current: ConnectedAgeGate.storedResult(), outcome: outcome)
        ConnectedAgeGate.setStoredResult(next)
        stored = next

        guard outcome == .confirmedAdult, auth.hasConnectedIdentity else { return }
        auth.pendingAgeBand = .band18Plus
        _ = await auth.ensureAgeBandEstablished(reason: "age-\(reason)")
    }
}

/// Runs `ConnectedAgeRecheck` at launch, on every foreground and on sign-in,
/// with Apple's request action read here, in a View.
struct ConnectedAgeRecheckTrigger: ViewModifier {
    let recheck: ConnectedAgeRecheck
    let auth: AuthManager
    /// Re-resolves the app mode after a check, so a change takes effect now.
    let onRecorded: () -> Void

    #if canImport(DeclaredAgeRange)
    @Environment(\.requestAgeRange) private var requestAgeRange
    #endif
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear {
                Task { await run(reason: "launch") }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                guard !LocalFactoryReset.isInProgress else { return }
                Task { await run(reason: "foreground") }
            }
            .onReceive(auth.$backendUserID.removeDuplicates()) { backendUserID in
                recheck.resetCooldown()
                guard backendUserID != nil else { return }
                Task { await run(reason: "signIn") }
            }
    }

    @MainActor
    private func run(reason: String) async {
        guard !UnitTestHost.isActive else { return }
        await recheck.checkIfNeeded(auth: auth, reason: reason, check: {
            #if canImport(DeclaredAgeRange)
            return await ConnectedAgeGate.check(using: requestAgeRange)
            #else
            return .refused(.unavailable)
            #endif
        }, onRecorded: onRecorded)
    }
}

extension View {
    func connectedAgeRecheck(_ recheck: ConnectedAgeRecheck,
                             auth: AuthManager,
                             onRecorded: @escaping () -> Void) -> some View {
        modifier(ConnectedAgeRecheckTrigger(recheck: recheck, auth: auth, onRecorded: onRecorded))
    }
}
