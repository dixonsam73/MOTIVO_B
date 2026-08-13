import AuthenticationServices
import Foundation
import UIKit

/// C-44 — Sign in with Apple revocation at account-deletion time.
///
/// Apple's account-deletion guidance expects an app offering Sign in with Apple
/// to revoke the user's authorization as part of deleting their account.
/// Deleting the backend row and clearing the Keychain is not equivalent: without
/// revocation the user still sees Études under Settings → Apple Account → Sign
/// in with Apple, and signing in again silently re-creates an account.
///
/// STORE-NOTHING DESIGN. No Apple refresh token is held at rest, anywhere, ever.
/// A *fresh* authorization is obtained at deletion time and exchanged
/// server-side immediately. Verified on device 2026-08-13: a repeat
/// authorization for an already-authorized identity still carries a code
/// (gate a), and a real native code exchanges at `/auth/token` with **no**
/// `redirect_uri` (gate b2, `apple_status=200 sent_redirect_uri=false`).
///
/// REVOCATION FAILURE MUST NEVER BLOCK DELETION.
/// TN3194: "If you don't have the user's refresh token, access token, or
/// authorization code, you must still fulfill the user's account deletion
/// request and meet the account deletion requirement."
///
/// That guarantee lives in the SIGNATURE below — `attemptRevocation` cannot
/// throw, so it cannot propagate into the deletion path's `do`/`catch` however
/// carelessly it is called. This is deliberate and load-bearing: the neighbouring
/// `ConnectedAccountDeletionService.deleteCurrentConnectedAccount` *does* throw,
/// and copying its shape is the obvious mistake. The server reports failure
/// truthfully with real HTTP statuses; it is this type that makes the failure
/// unable to block anything.
enum AppleRevocationOutcome {
    /// Apple confirmed revocation (or the token was already invalid — the
    /// endpoint returns 200 for both, so it is idempotent).
    case revoked
    /// No attempt was made: no Connected identity, the user dismissed Apple's
    /// sheet, no code was issued, or the authorizing Apple Account was not the
    /// one being deleted.
    case notAttempted(String)
    /// An attempt was made and did not succeed.
    case failed(String)

    var didRevoke: Bool {
        if case .revoked = self { return true }
        return false
    }

    /// For logging. Carries no token material.
    var summary: String {
        switch self {
        case .revoked: return "revoked"
        case .notAttempted(let why): return "notAttempted(\(why))"
        case .failed(let why): return "failed(\(why))"
        }
    }
}

/// Transient, in-memory presentation state for TN3194's manual-revocation
/// fallback ("Direct the user to manually revoke access for your client").
///
/// DELIBERATELY NOT `UserDefaults`: `LocalFactoryReset` wipes the entire
/// persistent domain, so anything stored there would be destroyed by the very
/// operation whose outcome this reports.
///
/// Presented from the root `ZStack` in `MOTIVOApp.body`, NOT from `ProfileView`.
/// `ProfileView` is a conditional overlay driven by `appRoute.isProfilePresented`
/// and can legitimately be gone by the time the notice is due; the root
/// `WindowGroup` content is never destroyed while the app runs.
@MainActor
final class AppleRevocationNotice: ObservableObject {
    static let shared = AppleRevocationNotice()
    private init() {}

    @Published var isPending: Bool = false
}

@MainActor
enum AppleRevocationService {

    /// Attempts revocation. **Cannot throw, by design — see the note above.**
    ///
    /// Gated on identity, never on entitlement. A lapsed member deleting their
    /// account must not be asked to re-subscribe in order to revoke, which is
    /// C-35's rule and the reason that finding had to be fixed twice.
    static func attemptRevocation(auth: AuthManager, reason: String) async -> AppleRevocationOutcome {
        guard auth.hasConnectedIdentity else {
            return .notAttempted("noConnectedIdentity")
        }
        guard let baseURL = BackendConfig.apiBaseURL,
              let anonKey = BackendConfig.apiToken else {
            return .failed("backendNotConfigured")
        }
        guard let accessToken = Keychain.get("supabaseAccessToken_v1"),
              !accessToken.isEmpty else {
            return .failed("noSupabaseSession")
        }

        let request = DeletionAuthorizationRequest()
        guard let credential = await request.requestCredential() else {
            // Cancelled, failed, or no code issued. Deletion proceeds regardless.
            return .notAttempted("authorizationUnavailable")
        }

        // Client-side identity check, in addition to the server's `sub` binding.
        // Native Sign in with Apple authorizes the device's signed-in iCloud
        // account, which is not necessarily the account being deleted. Revoking
        // a bystander's authorization would be worse than revoking nothing.
        if let stored = Keychain.get("appleUserID"), !stored.isEmpty,
           credential.user != stored {
            return .notAttempted("identityMismatch")
        }
        guard let codeData = credential.authorizationCode,
              let code = String(data: codeData, encoding: .utf8), !code.isEmpty else {
            return .notAttempted("noAuthorizationCode")
        }

        // Same URL construction as ConnectedAccountDeletionService.
        let functionURL: URL = {
            if let host = baseURL.host, host.hasSuffix(".supabase.co") {
                let ref = host.replacingOccurrences(of: ".supabase.co", with: "")
                if let url = URL(string: "https://\(ref).functions.supabase.co/revoke_apple_identity_v1") {
                    return url
                }
            }
            return baseURL
                .appendingPathComponent("functions")
                .appendingPathComponent("v1")
                .appendingPathComponent("revoke_apple_identity_v1")
        }()

        var urlRequest = URLRequest(url: functionURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try? JSONSerialization.data(
            withJSONObject: ["authorization_code": code]
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

            if status == 200, let revoked = object?["revoked"] as? Bool, revoked {
                return .revoked
            }
            let stage = (object?["stage"] as? String) ?? "unknown"
            let why = (object?["reason"] as? String) ?? "unknown"
            return .failed("http\(status)/\(stage)/\(why)")
        } catch {
            return .failed("transport/\((error as NSError).domain)/\((error as NSError).code)")
        }
    }
}

/// Bridges `ASAuthorizationController`'s delegate callbacks to `async`.
///
/// The continuation is resumed exactly once: `finish` clears it before
/// resuming, so whichever delegate method fires second is a no-op. The object
/// retains itself for the duration because `ASAuthorizationController` holds its
/// delegate weakly and nothing else would keep it alive across the await.
private final class DeletionAuthorizationRequest: NSObject {

    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential?, Never>?
    private var controller: ASAuthorizationController?
    private var selfRetain: DeletionAuthorizationRequest?

    @MainActor
    func requestCredential() async -> ASAuthorizationAppleIDCredential? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.selfRetain = self

            // Scopes empty: this gesture wants the authorization code, not the
            // user's name. Apple suppresses name and email for an already-
            // authorized user in any case.
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = []

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            self.controller = controller
            controller.performRequests()
        }
    }

    private func finish(_ credential: ASAuthorizationAppleIDCredential?) {
        let pending = continuation
        continuation = nil
        controller = nil
        pending?.resume(returning: credential)
        selfRetain = nil
    }
}

extension DeletionAuthorizationRequest: ASAuthorizationControllerDelegate {

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        finish(authorization.credential as? ASAuthorizationAppleIDCredential)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        // Includes the user cancelling Apple's sheet. Deletion proceeds anyway.
        finish(nil)
    }
}

extension DeletionAuthorizationRequest: ASAuthorizationControllerPresentationContextProviding {

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .keyWindow
        return window ?? ASPresentationAnchor()
    }
}
