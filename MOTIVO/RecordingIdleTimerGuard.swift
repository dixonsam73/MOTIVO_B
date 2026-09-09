//
//  RecordingIdleTimerGuard.swift
//  MOTIVO
//
//  PHASE 5 · P5-K / C-50 — HOLD OFF AUTO-LOCK WHILE A RECORDING IS ACTIVE.
//
//  Device-observed 2026-08-14 on Device A with a controlled discriminator:
//  Auto-Lock at 30 s interrupted a recording; Auto-Lock at Never did not. No
//  idle-timer management existed anywhere in the app — a gap, not a broken
//  implementation.
//
//  ── WHY THIS IS REFERENCE-COUNTED AND NOT A BARE ASSIGNMENT ────────────────
//
//  `UIApplication.shared.isIdleTimerDisabled` is ONE GLOBAL FLAG, and Études has
//  TWO INDEPENDENT RECORDERS. If each wrote the flag directly, one recorder's
//  restore would clear the other's hold. Counting holders makes the last release
//  win rather than the last writer.
//
//  ── WHAT THIS DELIBERATELY IS NOT ─────────────────────────────────────────
//
//  Not an app-wide "activity" framework, not injected into the environment, not
//  observed by anything, and not a place to hang unrelated lifecycle. One type,
//  two methods. **If a third caller ever appears, that is the moment to ask
//  whether the abstraction is still the right shape — not a reason to widen it
//  quietly.**
//
//  ── THE FAILURE THIS MUST NOT CAUSE ───────────────────────────────────────
//
//  An app that permanently prevents Auto-Lock after an abnormal path is a worse
//  defect than the one being fixed: it flattens the battery silently. Every exit
//  from recording releases, including cancel, failure and teardown, and
//  `release` is idempotent so a double release cannot drive the count negative
//  and strand the flag.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Holds off device Auto-Lock while at least one recorder says it is recording.
@MainActor
enum RecordingIdleTimerGuard {

    /// Owner tokens currently holding the timer. A SET, not a counter: a
    /// repeated `hold` from the same owner must not require a matching number of
    /// releases, because the owners here are lifecycle callbacks that can fire
    /// more than once for one recording.
    private(set) static var holders: Set<String> = []

    /// Called when an owner genuinely begins recording.
    static func hold(_ owner: String) {
        let wasEmpty = holders.isEmpty
        holders.insert(owner)
        if wasEmpty { apply(true) }
    }

    /// Called on every exit — success, cancel, failure and teardown.
    /// **Idempotent**: releasing an owner that is not holding does nothing.
    static func release(_ owner: String) {
        guard holders.remove(owner) != nil else { return }
        if holders.isEmpty { apply(false) }
    }

    /// Convenience for the common "state changed, recompute" call shape, so a
    /// caller cannot forget one side of the pair.
    static func setHolding(_ holding: Bool, owner: String) {
        holding ? hold(owner) : release(owner)
    }

    /// PURE except for the UIKit write, so the lifecycle above is testable.
    private static func apply(_ disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }

    /// Test seam only. Not called by product code.
    static func resetForTesting() {
        holders.removeAll()
        apply(false)
    }
}
