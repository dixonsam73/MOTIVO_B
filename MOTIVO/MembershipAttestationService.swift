//
//  MembershipAttestationService.swift
//  MOTIVO
//
//  PHASE 3 · U5e — client half of B-24's ownership attestation.
//
//  ONE JOB: collect an Apple-signed transaction JWS from local StoreKit, POST it
//  to `membership_attest_v1`, and report what the server decided.
//
//  **IT DECIDES NOTHING ABOUT PRODUCT MODE.** It does not read `AppMode`, does
//  not consult `canViewFeed`, does not know whether a membership row exists, and
//  does not switch the app into or out of Connected. It returns an outcome;
//  orchestrating that outcome is U5f/U5g's job. Keeping those separate is what
//  lets the settled invariant hold — attestation fires on
//  `(locally entitled ∧ hasConnectedIdentity ∧ BackendConfig.isConfigured)` and
//  is NEVER gated on Connected already being active or on a row already existing.
//
//  ── THE JWS IS A LONG-LIVED BEARER OWNERSHIP ARTEFACT ─────────────────────
//
//  NEVER LOGGED. NEVER PERSISTED. NEVER CACHED. NEVER ECHOED.
//
//  This is not caution, it is a consequence of measurement. The F3b gate ran on
//  Device A against a genuine Sandbox entitlement on 2026-08-20 and returned P2:
//  `Transaction.currentEntitlements` serves a STORED HISTORICAL representation
//  whose `signedDate` is fixed at approximately the purchase instant and does not
//  move across cold launches. **So a leaked JWS stays valid for the life of the
//  transaction** rather than expiring in minutes, and anyone holding those bytes
//  holds the ownership proof.
//
//  Consequently there is no property, no `UserDefaults` key, no Keychain item and
//  no log statement in this file that touches it. It exists as a local `let`,
//  travels straight into the request body, and goes out of scope.
//
//  ── AND IT IS NEVER EVIDENCE OF CURRENT ENTITLEMENT ───────────────────────
//
//  The same P2 result is why the JWS answers **who** and never **now**. The
//  server re-reads Apple live for current state; this client never asserts
//  entitlement, and nothing it sends is authoritative for membership.
//
//  ── WHAT IS DELIBERATELY ABSENT ───────────────────────────────────────────
//
//  No freshness window and no one-time consumption — D3, settled from F3b. A
//  window would refuse G11's dormant pre-cutover subscriber, whose JWS is signed
//  months or years earlier and who is exactly the case U5 exists to rescue.
//
//  No user id, no environment, no originalTransactionId is sent. The server
//  derives identity from the verified JWT and the Apple facts from the verified
//  claims; sending our own would be the bare-identifier bypass B-24 forbids.
//

import Foundation
import StoreKit

@MainActor
enum MembershipAttestationService {

    /// Why an attempt never reached the network. Local conditions only.
    enum Ineligible: Equatable {
        case notLocallyEntitled
        case noConnectedIdentity
        case notConfigured
        case sessionUnavailable
        /// StoreKit produced no `.verified` transaction for a Connected product.
        case noVerifiedTransaction
    }

    /// The server's decision, modelled closely enough for U5f/U5g to orchestrate
    /// and no more. **No case here implies a UI action** — that mapping is later
    /// work, deliberately not this service's business.
    enum Outcome: Equatable {
        /// Ownership established for the first time.
        case established
        /// A row already existed; state was refreshed through the canonical path.
        case alreadyEstablished
        /// The subscription belongs to another live binding. Recorded server-side
        /// for operator disposition. **Not retryable by the client.**
        case conflict
        /// Apple accepted the binding and has not surfaced it yet. Nothing was
        /// written. **Retry on a later attestation** — this is propagation, not
        /// failure.
        case pending
        /// Apple refused permanently (Family Sharing, wrong id shape). Stop.
        case terminalRefusal(reason: String)
        /// The JWS itself was refused by the server's claim boundary.
        case claimRefused(category: String, terminal: Bool)
        /// Apple was unreachable or ambiguous. Nothing written; retry later.
        case appleUnavailable
        /// Local preconditions were not met; no request was made.
        case ineligible(Ineligible)
        case serverError(status: Int)
        case transport(String)
    }

    // MARK: - Entry point

    /// Attempts one attestation.
    ///
    /// `isLocallyEntitled` is a PARAMETER rather than something this service
    /// reads, so the service has no dependency on `ConnectedMembershipStore`, on
    /// `AppMode`, or on anything that could reintroduce a mode gate. The caller
    /// supplies the local StoreKit answer; the server remains the authority.
    static func attest(
        auth: AuthManager,
        isLocallyEntitled: Bool,
        reason: String
    ) async -> Outcome {
        guard isLocallyEntitled else { return .ineligible(.notLocallyEntitled) }
        guard auth.hasConnectedIdentity else { return .ineligible(.noConnectedIdentity) }
        guard BackendConfig.isConfigured,
              let baseURL = BackendConfig.apiBaseURL,
              let anonKey = BackendConfig.apiToken else {
            return .ineligible(.notConfigured)
        }

        // F6: mode-independent, and it never signs anybody out.
        guard await auth.ensureValidBackendSession(reason: "attest:\(reason)") else {
            return .ineligible(.sessionUnavailable)
        }
        guard let accessToken = Keychain.get("supabaseAccessToken_v1"),
              !accessToken.isEmpty else {
            return .ineligible(.sessionUnavailable)
        }

        guard let jws = await currentVerifiedJWS() else {
            return .ineligible(.noVerifiedTransaction)
        }

        var request = URLRequest(url: endpointURL(baseURL: baseURL))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = requestBody(jws: jws)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            return parseOutcome(status: status, data: data)
        } catch {
            // The error is stringified WITHOUT the request body. URLError does not
            // carry it, but this is stated because "log the error" is exactly how
            // a bearer artefact reaches a log file.
            return .transport(String(describing: error))
        }
    }

    // MARK: - Pure pieces, split out so they are testable without a network

    /// **The entire request body.** One field, and the unit test asserts exactly
    /// that: no user id, no environment, no originalTransactionId, no product.
    static func requestBody(jws: String) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["jws": jws])
    }

    static func endpointURL(baseURL: URL) -> URL {
        // Same construction as ConnectedAccountDeletionService and
        // AppleRevocationService, so all three agree about where functions live.
        if let host = baseURL.host, host.hasSuffix(".supabase.co") {
            let ref = host.replacingOccurrences(of: ".supabase.co", with: "")
            if let url = URL(string: "https://\(ref).functions.supabase.co/membership_attest_v1") {
                return url
            }
        }
        return baseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("membership_attest_v1")
    }

    /// Maps the server's answer onto `Outcome`. Pure, so every branch is unit
    /// testable against a recorded body rather than against a live endpoint.
    ///
    /// **An unrecognised 200 is `serverError`, not success.** Guessing that an
    /// unknown outcome means "established" is how a client starts believing it is
    /// a member on evidence nobody produced.
    static func parseOutcome(status: Int, data: Data) -> Outcome {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let outcome = json?["outcome"] as? String

        switch status {
        case 200:
            switch outcome {
            case "established":         return .established
            case "already_established": return .alreadyEstablished
            case "conflict":            return .conflict
            case "pending":             return .pending
            case "terminal_refusal":
                return .terminalRefusal(reason: (json?["reason"] as? String) ?? "unspecified")
            default:                    return .serverError(status: status)
            }
        case 422:
            return .claimRefused(
                category: (json?["category"] as? String) ?? "unspecified",
                terminal: (json?["terminal"] as? Bool) ?? false
            )
        case 502:
            return .appleUnavailable
        default:
            return .serverError(status: status)
        }
    }

    // MARK: - StoreKit

    /// The newest `.verified` entitlement for a Connected product, as its
    /// Apple-signed JWS.
    ///
    /// **`.verified` ONLY — decision D8.** The server re-verifies regardless, so
    /// filtering locally costs nothing real; sending bytes the client already
    /// knows are unverifiable would only widen what we transmit.
    ///
    /// **`Xcode` transactions can never reach the server as authoritative
    /// membership**, and that holds three times over: the server's claim boundary
    /// refuses the environment, `membership_environment_check` excludes `'Xcode'`,
    /// and a locally-pinned StoreKit configuration is signed by Xcode's test
    /// certificate rather than Apple's root so it fails signature verification
    /// first. Nothing is filtered here on that basis — defence belongs where the
    /// authority is, and a client-side filter would only hide the refusal.
    static func currentVerifiedJWS() async -> String? {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard ConnectedMembershipStore.ProductID.all.contains(transaction.productID) else {
                continue
            }
            return result.jwsRepresentation
        }
        return nil
    }
}
