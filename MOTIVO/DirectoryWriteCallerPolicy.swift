//
//  DirectoryWriteCallerPolicy.swift
//  MOTIVO
//
//  PHASE 6 · C-70 — THE TWO DECISIONS A CALLER MAKES AROUND A DIRECTORY WRITE.
//
//  Both live here, pure, because both were wrong in a way no end-of-response
//  guard could have caught and neither was reachable by a test while it was
//  embedded in a SwiftUI view.
//

import Foundation

// MARK: - The skip token

/// Records the fingerprint the server is KNOWN to hold, so an unchanged screen
/// does not re-publish on every trigger.
///
/// **THE RACE THIS EXISTS TO CLOSE.** The token used to be a bare `String?`
/// compared at the top of the sync and written on success. That loses an edit
/// outright:
///
///   1. a save of **A** is accepted, so the token is A;
///   2. the member edits to **B** and that write is dispatched and held;
///   3. the member reverts the screen to **A**;
///   4. the next sync compares A against the token, finds A, and **returns
///      before sending anything**;
///   5. B lands on the server, and its own UI result is correctly suppressed
///      because the screen no longer describes it.
///
/// The server now holds B, the screen shows A, and **nothing will ever
/// re-publish A** — the divergence is permanent and silent. A guard at the end
/// of a response cannot repair it, because the repairing write was skipped
/// before it ran.
///
/// The fix is to treat the token as what it actually claims: knowledge of the
/// server's value. Submitting a DIFFERENT value destroys that knowledge the
/// moment it is dispatched, so the token is invalidated at submission and
/// re-established only by an evidenced result.
public struct DirectorySyncLatch: Equatable {

    /// The fingerprint last evidenced as held by the server, if any.
    public private(set) var confirmed: String?

    public init() {}

    /// Should a write be submitted for `fingerprint`?
    ///
    /// Invalidates the token whenever it answers `true`: from that moment the
    /// server's value is in flight and unknown, so a later revert to the old
    /// value must be re-published rather than skipped.
    public mutating func shouldSubmit(_ fingerprint: String) -> Bool {
        if confirmed == fingerprint { return false }
        confirmed = nil
        return true
    }

    /// The server is evidenced to hold this value.
    public mutating func confirm(_ fingerprint: String) { confirmed = fingerprint }

    /// Forget what the server holds — used after adopting a generated handle,
    /// which changes the row underneath the token.
    public mutating func invalidate() { confirmed = nil }
}

// MARK: - Finishing Connected setup

public enum ConnectedSetupStep: Equatable {
    /// Evidenced, and still this session's business: finish setup.
    case completeSetup
    /// Tell the member setup did not finish.
    case reportFailure
    /// Say nothing and do nothing. The screen belongs to a different identity
    /// or a superseding intent.
    case abandonSilently
}

public enum ConnectedSetupDecision {

    /// **`isFresh` is not optional and is not an optimisation.** Without it an
    /// `.applied` that returned after an identity transition would run
    /// generation, write a handle into `ProfileStore`, and call `onComplete()`
    /// for the session that REPLACED the one that asked — and a stale failure
    /// would post its message to that replacement's screen.
    public static func next(outcome: DirectoryWriteOutcome, isFresh: Bool) -> ConnectedSetupStep {
        guard isFresh else { return .abandonSilently }
        switch outcome {
        case .applied:
            return .completeSetup
        case .superseded, .supersededIdentity:
            return .abandonSilently
        case .accountIDTaken, .notEvidenced, .noRowMatched, .refusedByPolicy,
             .rowConflict, .ambiguous, .failed:
            // Setup sends no account_id, so a collision is not reachable from
            // here — it is enumerated rather than defaulted so that a new
            // outcome cannot silently fall into "finish setup".
            return .reportFailure
        }
    }
}
