//
//  AgeBandRecoveryTrigger.swift
//  MOTIVO
//
//  PHASE 5 · CP-3 — Finding A's recovery TRIGGERS, in a View.
//

import SwiftUI

#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif

/// Drives `AgeBandRecoveryCoordinator` at launch and on every foreground, and
/// supplies it with a `requestAgeRange` action read from a **View**.
///
/// ── WHY THIS IS A VIEW AND NOT THE APP ─────────────────────────────────────
///
/// **DEVICE-FOUND DEFECT, 2026-09-08.** The trigger previously lived on
/// `struct MOTIVOApp: App` and closed over an `@Environment(\.requestAgeRange)`
/// declared there. On a genuinely band-less identity, with the Sandbox fixture
/// set to 13-15 and Études listed as `Shared`, recovery **read and never
/// wrote**: `account_privacy_self_v1` moved `48 → 50` while
/// `account_privacy_upsert_v1` stayed at `2`, **no system sheet appeared**, and
/// no band was established. The same request from `ProfileView`'s View-scoped
/// action worked on the same device minutes earlier.
///
/// `requestAgeRange` presents system UI, so it needs a presentation context.
/// `@Environment(\.scenePhase)` resolving in `App` scope does **not** imply a
/// presentation-requiring action does. **The App-scope presentation context is
/// the leading source-level explanation; the thrown error itself was never
/// directly observed, because the `catch` is silent and the device runs
/// Release.** What is established is the behaviour, not the exception.
///
/// So the action is read **here**, in a View, and handed to the coordinator.
///
/// ── WHAT THIS DELIBERATELY DOES NOT DO ─────────────────────────────────────
///
/// It adds **no second age-range mechanism** — it reuses the same environment
/// action and the same `DeclaredAgeRangeService.outcome(for:)` mapping
/// `ProfileView` already uses. It **persists nothing**: no range, no band, no
/// declaration provenance. It renders **no UI** of its own. And it holds the
/// coordinator as a plain `let` rather than an `@ObservedObject`, because it
/// only calls a method — subscribing would add a re-render source to the root
/// view for no benefit, which is the shape of C-55.
///
/// All policy stays in the coordinator: the existing-band short-circuit,
/// single-flight, the 60-second cooldown, and fail-closed handling of
/// `ineligible` / `unavailable` / a thrown error.
struct AgeBandRecoveryTrigger: ViewModifier {
    let coordinator: AgeBandRecoveryCoordinator
    let auth: AuthManager

    #if canImport(DeclaredAgeRange)
    @Environment(\.requestAgeRange) private var requestAgeRange
    #endif
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            // AT LAUNCH, and deliberately NOT gated on Connected mode: the member
            // this rescues is precisely the one whose Connected state is
            // incomplete, exactly as U5f's attestation invariant reasons about
            // its own dormant case.
            .onAppear {
                Task { await recover(reason: "launch") }
            }
            // ON EVERY FOREGROUND. Single-flight plus a cooldown inside the
            // coordinator keeps a device Apple cannot serve from becoming a
            // prompt loop.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                // Delete Account v2: no liveness work during a factory reset.
                guard !LocalFactoryReset.isInProgress else { return }
                Task { await recover(reason: "foreground") }
            }
    }

    /// Bridges the View's environment action into the coordinator. Apple's
    /// answer is cached, so the usual case presents no UI; any thrown error is
    /// `.unavailable` and therefore establishes nothing.
    @MainActor
    private func recover(reason: String) async {
        await coordinator.recoverIfNeeded(auth: auth, reason: reason) {
            #if canImport(DeclaredAgeRange)
            do {
                let response = try await requestAgeRange(
                    ageGates: DeclaredAgeRangeService.minimumGate,
                    DeclaredAgeRangeService.adultGate
                )
                return DeclaredAgeRangeService.outcome(for: response)
            } catch {
                return .unavailable
            }
            #else
            return .unavailable
            #endif
        }
    }
}

extension View {
    /// Attaches CP-3 Finding A's recovery triggers. **Must be applied to a
    /// View** — that is the entire point; see `AgeBandRecoveryTrigger`.
    func ageBandRecovery(coordinator: AgeBandRecoveryCoordinator, auth: AuthManager) -> some View {
        modifier(AgeBandRecoveryTrigger(coordinator: coordinator, auth: auth))
    }
}
