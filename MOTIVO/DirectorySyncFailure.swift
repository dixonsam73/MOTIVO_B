//
//  DirectorySyncFailure.swift
//  MOTIVO
//
//  PHASE 5 · C-70(a) — WHAT TO TELL A MEMBER WHEN A DIRECTORY WRITE FAILS.
//
//  **THE DEFECT THIS EXISTS TO CORRECT.** `ProfileView` posts ONE
//  `account_directory` row carrying display name, Account ID, location and
//  instruments, and it has five entry points — the Account ID field's blur and
//  submit, plus a `name` edit, a `location` edit and the instrument manager
//  closing. Every non-collision failure used to report *"Couldn't update your
//  Account ID"*, so a failed NAME or LOCATION edit blamed a field the member
//  had not touched.
//
//  **THE RULE: attribute a failure to a field only when the SERVER attributed
//  it to that field.** A unique-constraint violation on `account_id` names
//  itself on the wire and is genuinely Account-ID-specific. Everything else —
//  auth, transport, an RLS refusal, the CP-1 band trigger, `enforcement_gate` —
//  is a whole-row failure the backend cannot attribute, and the only truthful
//  presentation is one that names no field.
//
//  **TWO FURTHER ATTRIBUTABLE ERRORS EXIST AND ARE DELIBERATELY NOT HANDLED.**
//  `account_id_format` and `account_id_lowercase` are CHECK constraints that
//  also name themselves. They are unreachable through the shipping UI, because
//  `normalizeAccountID` sanitises the field and the caller only sends
//  `account_id` at three characters or more. Writing copy for an unreachable
//  branch would be inventing handling for a case nobody has observed. Recorded
//  so the capability is known rather than rediscovered.
//
//  **C-70, PHASE 6 — TIGHTENED, AND THE TIGHTENING IS THE SAME RULE APPLIED
//  ONCE MORE.** `isAccountIDCollision` used to accept a BARE `23505` as proof
//  of a handle collision. `account_directory` carries TWO unique constraints —
//  `account_directory_account_id_key` on `account_id` and
//  `account_directory_pkey` on `user_id` — and both raise `23505`, so the code
//  alone would blame the Account ID for a primary-key conflict. That is exactly
//  the defect this file exists to prevent, surviving inside its own classifier.
//  The server must NAME the constraint or the column.
//
//  The generic copy also changed. It used to say "Please try again", which
//  invites a retry the member may not be able to make succeed and, worse,
//  asserts that the change did not reach Connected. What is actually known is
//  narrower: we could not CONFIRM that it did.
//
//  Pure and view-free so it can be tested directly.
//

import Foundation

enum DirectorySyncFailure {

    /// Shown when the server itself attributed the failure to `account_id`.
    static let accountIDTakenMessage = "That account ID is already taken."

    /// Shown for every failure the server did NOT attribute to a field.
    /// It names no field, because naming one would be a guess — and it claims
    /// no outcome beyond the one that is actually established.
    static let genericMessage = "We couldn’t confirm your profile changes were saved to Connected."

    /// True only for a unique-constraint violation on `account_directory.account_id`.
    ///
    /// Relocated from `ProfileView.isAccountIDCollision` rather than copied —
    /// a second implementation is a second thing to drift.
    static func isAccountIDCollision(_ error: Error) -> Bool {
        guard let net = error as? NetworkManager.NetworkError else { return false }
        switch net {
        case .httpError(let status, let body):
            guard status == 409, let body, !body.isEmpty else { return false }
            // The SERVER must name the account_id constraint or column. A bare
            // 23505 is a unique violation on SOME constraint, and this table has
            // two.
            return DirectoryWriteEvidence.namesAccountIDConstraint(body)
        default:
            return false
        }
    }

    /// The single decision this type exists to make.
    static func message(for error: Error) -> String {
        isAccountIDCollision(error) ? accountIDTakenMessage : genericMessage
    }

    /// What to tell the member about one directory write.
    ///
    /// `nil` means SAY NOTHING: either it is evidenced as saved, or the write
    /// belongs to an identity or an intent that is no longer the member's
    /// current one, and a message about it would be about nothing they did.
    ///
    /// **Every other case gets the same generic line, deliberately.** The
    /// distinctions between them — refused, unmatched, unevidenced, unknown —
    /// are real and worth keeping in the outcome type, but they are not
    /// distinctions the member can act on differently, and inventing four
    /// wordings would mean asserting four causes we have not established.
    static func message(for outcome: DirectoryWriteOutcome) -> String? {
        switch outcome {
        case .applied:
            return nil
        case .supersededIdentity, .superseded:
            return nil
        case .accountIDTaken:
            return accountIDTakenMessage
        case .notEvidenced, .noRowMatched, .refusedByPolicy, .rowConflict, .ambiguous, .failed:
            return genericMessage
        }
    }
}
