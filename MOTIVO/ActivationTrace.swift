//
//  ActivationTrace.swift
//  MOTIVO
//
//  TEMPORARY INSTRUMENTATION — C-38 DIAGNOSIS ONLY.
//
//  Standing condition, recorded in CLAUDE.md: this file and every call site are
//  removed once C-38 is diagnosed, fixed and verified. It must not ship.
//
//  Why it exists: a fresh onboard, purchase and Sign in with Apple left the app
//  permanently in Solo with a live entitlement, and the observable evidence was
//  only "stayed Solo". Activation depends on five gates (AppModeManager:119-129)
//  and is re-evaluated only on removeDuplicates'd transitions, so a single
//  boolean is the difference between a correct fix and a third guess.
//
//  Release-readable BY DESIGN, and that is the whole point. The previous
//  instrumentation effort used NSLog with %@ arguments, which the system
//  redacts to <private> when read back from a device — so every line arrived
//  empty on TestFlight. os.Logger with an explicit `privacy: .public` on the
//  interpolation is the fix, and it is why every emit below funnels through one
//  function that applies it.
//
//  PRIVACY: booleans, enum case names and stage labels only. No user
//  identifiers, no tokens, no handles, no email addresses, no product
//  identifiers. Presence is logged, never a value.
//

import Foundation
import os

enum ActivationTrace {

    private static let log = Logger(subsystem: "com.sdsongs.etudes", category: "C38")

    /// Every line goes through here so `privacy: .public` cannot be forgotten
    /// at an individual call site.
    private static func emit(_ message: String) {
        log.notice("\(message, privacy: .public)")
    }

    // MARK: - The five activation gates

    /// Logged on every `applyActivation`, whichever trigger caused it. The
    /// resolved mode and the previous mode are both included so a no-op
    /// re-evaluation is distinguishable from a real transition.
    static func gates(
        reason: String,
        backendConfigured: Bool,
        isEntitled: Bool,
        isSignedIn: Bool,
        hasToken: Bool,
        hasBackendUserID: Bool,
        resolved: String,
        previous: String
    ) {
        emit(
            "activation reason=\(reason) "
            + "configured=\(backendConfigured) entitled=\(isEntitled) "
            + "signedIn=\(isSignedIn) token=\(hasToken) backendID=\(hasBackendUserID) "
            + "resolved=\(resolved) previous=\(previous)"
        )
    }

    // MARK: - Membership state

    /// Every write, including same-value writes. `changed=false` is the
    /// interesting case: those are exactly the publications that
    /// `$membershipState.removeDuplicates()` swallows in MOTIVOApp:281.
    static func membershipState(from old: String, to new: String, changed: Bool) {
        emit("membershipState \(old) -> \(new) changed=\(changed)")
    }

    /// The result of one `Transaction.currentEntitlements` read, with the
    /// conditions it ran under. A `.notEntitled` here immediately after a
    /// verified purchase is C-38's stale read.
    static func entitlementRead(resolved: String, forced: Bool, wasInFlight: Bool) {
        emit("entitlementRead resolved=\(resolved) forced=\(forced) wasInFlight=\(wasInFlight)")
    }

    /// The value `purchase()` gates on after a verified transaction.
    static func purchaseGuard(isEntitled: Bool) {
        emit("purchaseGuard isEntitled=\(isEntitled)")
    }

    // MARK: - Sign in with Apple

    /// Stage labels only — never the Supabase user id or the Apple user id.
    /// The early-return branches in `signInToSupabaseIfPossible` are all
    /// `#if DEBUG` today, so on a TestFlight build a silent sign-in failure is
    /// currently invisible.
    static func signIn(stage: String, signedIn: Bool, hasToken: Bool, hasBackendUserID: Bool) {
        emit("signIn stage=\(stage) signedIn=\(signedIn) token=\(hasToken) backendID=\(hasBackendUserID)")
    }

    static func signInFailed(stage: String) {
        emit("signIn FAILED stage=\(stage)")
    }
}
