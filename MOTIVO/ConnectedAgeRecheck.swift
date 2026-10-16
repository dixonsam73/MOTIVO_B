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

    private var hasSeenIdentity = false
    private var lastSeenBackendUserID: String?

    enum IdentityDelivery: Equatable {
        /// The first delivery, at launch. The launch check covers it; it is
        /// not a sign-in and must not be counted as one.
        case initial
        /// The same identity again: SwiftUI re-delivers it on every redraw.
        case unchanged
        /// A real sign-in, sign-out or switch.
        case changed
    }

    /// PURE. What a delivery of the backend user id means.
    ///
    /// DEVICE-FOUND DEFECT, 2026-10-16 (Device B, Release): SwiftUI re-delivers
    /// the CURRENT id whenever the root view redraws, and every check redraws
    /// it (the stored result, the privacy state). Treating each delivery as a
    /// sign-in cleared the cooldown and re-ran the check, in a tight loop that
    /// froze the app and repeatedly called Apple and the server. Only a real
    /// change of identity is a sign-in.
    static func identityDelivery(hasSeen: Bool, previous: String?, current: String?) -> IdentityDelivery {
        guard hasSeen else { return .initial }
        return previous == current ? .unchanged : .changed
    }

    /// Notes a delivered identity. On a real change the cooldown is cleared,
    /// so a different identity doesn't inherit this one's.
    func noteIdentity(_ backendUserID: String?) -> IdentityDelivery {
        let delivery = Self.identityDelivery(hasSeen: hasSeenIdentity,
                                             previous: lastSeenBackendUserID,
                                             current: backendUserID)
        hasSeenIdentity = true
        lastSeenBackendUserID = backendUserID
        if delivery == .changed { lastAttemptAt = nil }
        return delivery
    }

    /// `countsRefusal`: true only for the sign-in check, which is a join
    /// attempt. Launch and foreground re-checks are never counted.
    func checkIfNeeded(auth: AuthManager,
                       reason: String,
                       countsRefusal: Bool = false,
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

        let outcome = await check()
        await record(outcome, auth: auth, reason: reason)
        if countsRefusal, case .refused(let refusal) = outcome { ConnectedAgeRefusalReport.send(refusal) }
        onRecorded()
    }

    /// A check the person asked for: Continue on the join path, or Try Again
    /// on a paused Connected. Bypasses the cooldown and the "don't re-ask
    /// after a refusal" rule, but not single-flight. A refusal here is a join
    /// attempt, so it is counted anonymously.
    func checkNow(auth: AuthManager,
                  reason: String,
                  check: () async -> ConnectedAgeGate.Outcome) async -> ConnectedAgeGate.Outcome? {
        guard !inFlight else { return nil }
        inFlight = true
        defer { inFlight = false }
        let outcome = await check()
        await record(outcome, auth: auth, reason: reason)
        if case .refused(let refusal) = outcome { ConnectedAgeRefusalReport.send(refusal) }
        return outcome
    }

    /// Stores the outcome and, for a confirmed adult with an identity, makes
    /// sure the server holds the adult row.
    func record(_ outcome: ConnectedAgeGate.Outcome, auth: AuthManager, reason: String) async {
        let next = ConnectedAgeGate.nextStoredResult(current: ConnectedAgeGate.storedResult(), outcome: outcome)
        ConnectedAgeGate.setStoredResult(next)
        // Publish only a change: an unchanged result must not redraw the app.
        if stored != next { stored = next }

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
                // Re-delivered on every redraw: act on a real sign-in only.
                guard recheck.noteIdentity(backendUserID) == .changed, backendUserID != nil else { return }
                Task { await run(reason: "signIn", countsRefusal: true) }
            }
    }

    @MainActor
    private func run(reason: String, countsRefusal: Bool = false) async {
        guard !UnitTestHost.isActive else { return }
        await recheck.checkIfNeeded(auth: auth, reason: reason, countsRefusal: countsRefusal, check: {
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
