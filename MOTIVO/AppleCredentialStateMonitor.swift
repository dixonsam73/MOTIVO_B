import AuthenticationServices
import Foundation

/// C-45 — react to Apple revoking, or losing, the Sign in with Apple credential.
///
/// WHY THIS IS RELEASE-BLOCKING RATHER THAN TIDYING.
///
/// Sign in with Apple is Études' **only** authentication mechanism. There is no
/// email/password and no second identity provider. So when Apple reports
/// `.revoked` — "The given user's authorization has been revoked and they should
/// be signed out" — or `.notFound` — "The user hasn't established a relationship
/// with Sign in with Apple" — there is **no independent credential left that
/// could justify retaining the authenticated state.** Before this existed, a
/// user who revoked Études in Settings left the app holding a live Supabase
/// session, a Keychain `appleUserID` and a bearer token, still believing they
/// were signed in.
///
/// It is also step 3 of TN3194's mandatory manual-revocation fallback: "Respond
/// to the credential revoked notification to revert the client to an
/// unauthenticated state." C-44 is not TN3194-compliant without it.
///
/// WHY BOTH A NOTIFICATION AND A POLL.
///
/// Apple is explicit that the notification alone is insufficient: "When a user
/// permanently deletes their Apple Account, Sign in with Apple invalidates all
/// user tokens and disables email forwarding for all associated apps. For native
/// apps, the system doesn't send a `credentialRevokedNotification`. Use
/// `getCredentialState(forUserID:completion:)` to respond to account deletion
/// events." So the polled check is required, not belt-and-braces.
///
/// WHAT IT DOES ON EACH STATE — deliberately narrow.
///
///   `.revoked`, `.notFound`  → `auth.clearConnectedIdentity` and nothing else.
///   `.authorized`            → nothing.
///   `.transferred`           → nothing. Out of scope; belongs with any future
///                              app-transfer work (TN3159).
///   lookup error             → **nothing.** A failed lookup is not evidence.
///                              State is retained and the next lifecycle event
///                              retries.
///   unknown future case      → nothing. Unknown is not authority to withdraw.
///
/// WHY NOT `signOut()`.
///
/// `signOut()` is identical to `clearConnectedIdentity` except that it also
/// deletes the per-user attachment *title* mappings (`AuthManager:880-883`).
/// Those titles are content the user typed. Destroying them because Apple sent
/// a signal would be silent data loss the user never asked for, and it would
/// make this path something other than authentication-state withdrawal.
/// Invariant 1 — the local journal is never deleted by any Connected action —
/// is the reason this distinction is worth the extra primitive.
///
/// STRUCTURALLY, THIS PATH CANNOT DESTROY ANYTHING. It calls exactly one
/// function on `AuthManager`, which touches only Keychain items, three
/// `UserDefaults` keys and in-memory published properties. It does not reference
/// `LocalFactoryReset`, `ConnectedAccountDeletionService`, `PersistenceController`,
/// `ScoreLibraryStore`, `AttachmentStore` or any storage API — verifiable by
/// grep over this file.
@MainActor
final class AppleCredentialStateMonitor {

    static let shared = AppleCredentialStateMonitor()
    private init() {}

    private var observer: NSObjectProtocol?
    private var checkInFlight = false

    /// Idempotent; safe to call on every appearance.
    func start(auth: AuthManager) {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await AppleCredentialStateMonitor.shared.check(auth: auth, reason: "credentialRevokedNotification")
            }
        }
    }

    func check(auth: AuthManager, reason: String) async {
        // C-44: a SUCCESSFUL revocation makes Apple report `.revoked`, so without
        // this guard the deletion workflow would sign itself out between revoking
        // and calling delete_account_v1 — destroying the Supabase session that
        // deletion still needs. Deferral, not a drop: the next foreground
        // re-checks, so a genuine revocation is still caught.
        guard !AccountDeletionTransaction.isInProgress else { return }

        // During a factory reset the identity is legitimately being torn down, so
        // `.notFound` here would be our own doing rather than external
        // revocation. Same precedent as `ensureBackendIdentityIfNeeded`.
        guard !LocalFactoryReset.isInProgress else { return }

        guard let appleUserID = Keychain.get("appleUserID"), !appleUserID.isEmpty else { return }

        guard !checkInFlight else { return }
        checkInFlight = true
        defer { checkInFlight = false }

        let state: ASAuthorizationAppleIDProvider.CredentialState
        do {
            state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: appleUserID)
        } catch {
            // A lookup failure is not evidence of revocation. Retain state and
            // let a later lifecycle event retry. Never act destructively here.
            #if DEBUG
            NSLog("[C-45] credentialState lookup failed reason=%@ — no action", reason)
            #endif
            return
        }

        // The lookup is asynchronous, so re-check the guards: a deletion may have
        // begun while it was in flight. Cheap, and closes the exact window this
        // monitor exists to avoid widening.
        guard !AccountDeletionTransaction.isInProgress, !LocalFactoryReset.isInProgress else { return }

        switch state {
        case .revoked:
            auth.clearConnectedIdentity(reason: "appleCredentialRevoked/\(reason)")
        case .notFound:
            auth.clearConnectedIdentity(reason: "appleCredentialNotFound/\(reason)")
        case .authorized:
            break
        case .transferred:
            break
        @unknown default:
            break
        }
    }
}
