import Foundation

/// C-44 — the authoritative "a destructive account workflow is running" flag.
///
/// WHY THIS EXISTS RATHER THAN REUSING `LocalFactoryReset.isInProgress`.
///
/// That flag becomes true at the first statement of `LocalFactoryReset.perform`
/// — which runs only *after* `delete_account_v1` has already succeeded — and is
/// cleared by `defer` when `perform` returns. It covers the local-reset phase
/// alone, so it cannot protect the Apple authorization, the revocation call, or
/// the backend deletion that precede it.
///
/// **It also must not be widened to cover them.**
/// `AuthManager.ensureValidSessionForConnectedAccountCleanup` is itself guarded
/// by `!LocalFactoryReset.isInProgress` and returns `false` when it is set. That
/// function is the first thing `ConnectedAccountDeletionService` calls, and a
/// `false` result throws `.sessionInvalid`. Widening the flag would therefore
/// make every account deletion fail with "Session is not valid" — C-35's exact
/// signature, a non-authoritative condition blocking deletion, for the third
/// time in this project. Two further guards (`ensureValidSession`,
/// `refreshSupabaseSession`) sit on the same session-refresh path.
///
/// `ProfileView.deleteAccountInFlight` was considered and rejected for a
/// different reason: its span is nearly right, but it is view-local `@State`
/// and therefore invisible to C-45's credential-state observer, which is the
/// one caller that needs to read it.
///
/// WHAT IT GUARDS.
///
/// C-45 will observe `ASAuthorizationAppleIDProvider.credentialRevokedNotification`
/// and poll `getCredentialState`. A *successful* revocation makes Apple report
/// `.revoked` — so without this flag, C-45 would sign the user out in the window
/// between revocation and `delete_account_v1`, destroying the Supabase session
/// deletion still needs. C-45 must read this and return early; that is a
/// deferral rather than a drop, because C-45 re-checks on every foreground and
/// so catches a genuinely revoked credential on the next pass.
@MainActor
enum AccountDeletionTransaction {

    private static var depth = 0

    /// True from before the deletion-time Apple authorization begins until the
    /// local factory reset has finished — the whole workflow, not a phase.
    static var isInProgress: Bool { depth > 0 }

    /// Scoped so the flag cannot leak: `defer` clears it on every exit path —
    /// normal return, early return, a thrown error, or task cancellation.
    ///
    /// Counted rather than boolean so that a nested call can never clear an
    /// outer one. Nothing nests today; this costs one integer and removes a
    /// class of bug from anything added later.
    static func run<T>(reason: String, _ body: () async throws -> T) async rethrows -> T {
        depth += 1
        defer { depth -= 1 }
        return try await body()
    }
}
