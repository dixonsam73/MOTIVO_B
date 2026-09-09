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
//  Pure and view-free so it can be tested directly.
//

import Foundation

enum DirectorySyncFailure {

    /// Shown when the server itself attributed the failure to `account_id`.
    static let accountIDTakenMessage = "That account ID is already taken."

    /// Shown for every failure the server did NOT attribute to a field.
    /// It names no field, because naming one would be a guess.
    static let genericMessage = "Couldn’t update your profile. Please try again."

    /// True only for a unique-constraint violation on `account_directory.account_id`.
    ///
    /// Relocated from `ProfileView.isAccountIDCollision` rather than copied —
    /// a second implementation is a second thing to drift.
    static func isAccountIDCollision(_ error: Error) -> Bool {
        guard let net = error as? NetworkManager.NetworkError else { return false }
        switch net {
        case .httpError(let status, let body):
            guard status == 409, let body, !body.isEmpty else { return false }
            // Supabase/Postgres unique violation on account_directory.account_id.
            if body.contains("\"code\":\"23505\"") { return true }
            if body.contains("account_directory_account_id_key") { return true }
            return false
        default:
            return false
        }
    }

    /// The single decision this type exists to make.
    static func message(for error: Error) -> String {
        isAccountIDCollision(error) ? accountIDTakenMessage : genericMessage
    }
}
