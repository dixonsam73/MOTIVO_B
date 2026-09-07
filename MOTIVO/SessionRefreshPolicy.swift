//
//  SessionRefreshPolicy.swift
//  MOTIVO
//
//  Pure session-refresh policy: no Keychain, no network, no Supabase types.
//  Everything here is a value-in / value-out decision so it can be tested
//  directly, which is the half of this subsystem that had ZERO coverage when
//  the token-rotation loop of 2026-09-07 was diagnosed.
//

import Foundation

/// The decisions a session refresh has to make, separated from the machinery
/// that performs one.
///
/// TWO DEFECTS ARE ADDRESSED HERE AND THEY ARE INDEPENDENT.
///
/// 1. `refreshSupabaseSession` rotated the refresh token **unconditionally**,
///    on every call, whether or not the access token it already held was still
///    valid. `shouldRefresh` is the gate that stops that.
///
/// 2. Its failure branch was a BOOLEAN — offline, or sign out — and that false
///    choice is what made a *superseded* refresh token destructive. A token
///    that a concurrent task has already spent is not a dead credential; it is
///    a race whose winner left a newer session behind. Answering it with
///    `signOut()` destroyed a live session, and `signOut()` in this codebase
///    additionally removes the per-user attachment TITLE mappings, which are
///    content the user typed. `refreshFailureDisposition` replaces the boolean
///    with a four-way outcome.
enum SessionRefreshPolicy {

    // MARK: - (A) Whether to rotate at all

    /// How long before expiry a token is treated as already stale. A refresh
    /// costs a round trip; using a token that expires mid-flight costs a 401.
    static let defaultExpirySkew: TimeInterval = 60

    /// True when the held access token is absent, unreadable, or close enough
    /// to expiry to be worth replacing.
    ///
    /// **An unknown expiry returns `true`.** We cannot show the token is good,
    /// so we refresh — the failure direction is a redundant round trip, never a
    /// request issued with a dead token.
    static func shouldRefresh(accessTokenExpiry: Date?,
                              now: Date,
                              skew: TimeInterval = defaultExpirySkew) -> Bool {
        guard let expiry = accessTokenExpiry else { return true }
        return expiry.timeIntervalSince(now) <= skew
    }

    /// The `exp` claim of a JWT, as a `Date`.
    ///
    /// Deliberately does no signature check: this decides whether to spend a
    /// round trip refreshing, and nothing is authorised on the strength of it.
    /// The server remains the only authority on whether a token is accepted.
    static func accessTokenExpiry(_ jwt: String?) -> Date? {
        guard let jwt, !jwt.isEmpty else { return nil }
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: payload),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = obj as? [String: Any] else { return nil }

        if let exp = dict["exp"] as? Double { return Date(timeIntervalSince1970: exp) }
        if let exp = dict["exp"] as? Int { return Date(timeIntervalSince1970: TimeInterval(exp)) }
        return nil
    }

    // MARK: - (A2) What a SUCCESSFUL refresh owes the rest of the app

    /// How a session came to be usable.
    enum SessionUsableOutcome: Equatable {
        /// The refresh token was spent and a new session was issued.
        case rotated
        /// The held access token was still valid, so nothing was spent.
        case alreadyValid
        /// Our token was superseded and a newer persisted session was adopted.
        case recoveredNewerSession
    }

    /// Whether a usable session obliges the caller to schedule directory
    /// hydration.
    ///
    /// **THE ANSWER IS ALWAYS YES, AND THAT IS THE POINT.**
    ///
    /// The first version of the expiry gate returned early on `alreadyValid`
    /// **without** scheduling, reasoning that "nothing changed, so there is
    /// nothing new to hydrate from". **That was wrong, and it was measured
    /// wrong on hardware on 2026-09-07.** Hydration is not a consequence of the
    /// *token* changing; it is a consequence of the *client* needing its
    /// directory state, and the thing that changes is the app's ELIGIBILITY —
    /// Solo → Connected — which no token event reports.
    ///
    /// The lifecycle that broke: a member signs in while unentitled, later
    /// subscribes **without re-authenticating**, and their access token is still
    /// valid throughout. Nothing rotates, so nothing schedules, so no directory
    /// row is ever published and the member stays invisible until the token
    /// happens to age out — up to a full token lifetime later. That is exactly
    /// the lapsed-member-returns journey U5's self-healing invariant exists to
    /// serve. Measured on Device A: `posts` SELECT +3 (Connected and
    /// authenticated), directory SELECT +0 (hydration never began), refresh
    /// tokens +0 (the early return was taken).
    ///
    /// **Scheduling on every usable outcome is safe ONLY because of the
    /// re-entrancy guard** — see `shouldBeginDirectoryHydration`. Hydration
    /// preflights a session refresh, so a refresh that schedules hydration can
    /// be re-entered by it. The guard makes the re-entrant schedule a no-op
    /// instead of a cancel-and-restart spin. **That is what makes this a
    /// one-line fix rather than a reopening of the 34-rotations-in-20.5 s
    /// defect**, and it is why the guard is load-bearing rather than
    /// belt-and-braces.
    static func schedulesDirectoryHydration(after outcome: SessionUsableOutcome) -> Bool {
        switch outcome {
        case .rotated, .alreadyValid, .recoveredNewerSession:
            return true
        }
    }

    /// Whether a directory hydration may begin for `targetUserID`.
    ///
    /// **THE CYCLE'S EDGE.** Hydration reads `account_privacy`; that read
    /// preflights `ensureValidBackendSession`; a usable session schedules
    /// hydration. So hydration can re-enter its own scheduler, and before this
    /// guard the scheduler answered by **cancelling the running hydration and
    /// starting another**, which spun and produced the "Already Used" refresh
    /// collisions.
    ///
    /// Structural rather than incidental: it does not depend on which session
    /// helper the privacy preflight happens to call, so re-pointing that
    /// preflight cannot silently restore the loop.
    static func shouldBeginDirectoryHydration(inFlightUserID: String?, targetUserID: String) -> Bool {
        guard let inFlightUserID, !inFlightUserID.isEmpty else { return true }
        return inFlightUserID != targetUserID
    }

    // MARK: - (B) What a refresh FAILURE means

    /// What the client should do about a refresh that did not succeed.
    ///
    /// FOUR OUTCOMES, NOT THREE, AND NOT A BOOLEAN. `ignore` is a separate axis
    /// from the other three: they classify how terminal a *credential* failure
    /// is, while `ignore` says the credential was never reached. Folding
    /// offline into any of the others would withdraw the Connected identity on
    /// every foreground in flight mode — strictly worse than the behaviour
    /// being fixed.
    enum RefreshFailureDisposition: Equatable {
        /// Transport never reached the credential. Withdraw nothing, report
        /// no success. This is today's correct behaviour and is preserved.
        case ignore

        /// Our refresh token was superseded, and a newer usable session is
        /// actually present. Adopt it.
        case recoverWithNewerSession

        /// We could not confirm authentication and found nothing newer.
        /// Withdraw the Connected identity — without destroying user content.
        case withdrawIdentity

        /// The credential itself is dead.
        ///
        /// Behaviourally identical to `withdrawIdentity` today, and KEPT
        /// DISTINCT DELIBERATELY: they are different facts about the world
        /// ("we could not confirm" against "the credential is gone"), and
        /// collapsing them now would make any future divergence a rewrite.
        /// Do not invent a behavioural difference to justify the split.
        case terminal
    }

    /// Why a refresh failed, before the persisted state is consulted.
    enum RefreshFailureClass: Equatable {
        case offlineOrTransient
        case supersededRefreshToken
        case terminalCredential
        /// Recognised as neither. Dispositioned conservatively.
        case unrecognised
    }

    /// What the Keychain holds *after* the failed attempt, which is the only
    /// evidence that can distinguish a lost race from a dead credential.
    ///
    /// A concurrent refresh that won consumed our token and wrote its own in
    /// its place, so a persisted refresh token that is no longer the one we
    /// presented is positive evidence that somebody else succeeded.
    struct SessionReconciliation: Equatable {
        var attemptedRefreshToken: String?
        var persistedRefreshToken: String?
        var persistedAccessTokenExpiry: Date?
        var now: Date

        init(attemptedRefreshToken: String?,
             persistedRefreshToken: String?,
             persistedAccessTokenExpiry: Date?,
             now: Date) {
            self.attemptedRefreshToken = attemptedRefreshToken
            self.persistedRefreshToken = persistedRefreshToken
            self.persistedAccessTokenExpiry = persistedAccessTokenExpiry
            self.now = now
        }

        /// True only on POSITIVE evidence of a newer session. Absence of
        /// evidence is never recovery: reporting success with no valid session
        /// is the zombie state `signOut()` was originally written to prevent.
        var hasNewerUsableSession: Bool {
            let persisted = (persistedRefreshToken ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !persisted.isEmpty else { return false }

            let attempted = (attemptedRefreshToken ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Unchanged token means nobody rotated; our failure is the whole story.
            guard persisted != attempted else { return false }

            // And the session it belongs to must actually be usable now. An
            // unreadable expiry is not usable, by shouldRefresh's own rule.
            return !shouldRefresh(accessTokenExpiry: persistedAccessTokenExpiry,
                                  now: now,
                                  skew: 0)
        }
    }

    /// Classifies a refresh failure. Transport is checked FIRST and wins.
    static func classify(_ error: Error) -> RefreshFailureClass {
        if isOfflineOrTransientNetworkError(error) { return .offlineOrTransient }

        let haystack = (String(describing: error) + " " + error.localizedDescription).lowercased()

        // Checked before the terminal markers: GoTrue phrases a superseded
        // token as "Invalid Refresh Token: Already Used", which also matches
        // "invalid refresh token" below.
        if haystack.contains("already used") { return .supersededRefreshToken }

        let terminalMarkers = [
            "refresh token not found",
            "refresh_token_not_found",
            "invalid refresh token",
            "invalid_grant",
            "session not found",
            "sessionnotfound",
            "user_not_found",
            "user from sub claim in jwt does not exist",
            "revoked"
        ]
        for marker in terminalMarkers where haystack.contains(marker) {
            return .terminalCredential
        }

        return .unrecognised
    }

    /// The disposition of a failed refresh.
    static func refreshFailureDisposition(_ error: Error,
                                          reconciliation: SessionReconciliation) -> RefreshFailureDisposition {
        switch classify(error) {
        case .offlineOrTransient:
            return .ignore
        case .supersededRefreshToken:
            return reconciliation.hasNewerUsableSession ? .recoverWithNewerSession : .withdrawIdentity
        case .terminalCredential:
            return .terminal
        case .unrecognised:
            // Not confirmed authenticated, and not shown to be dead either.
            // Withdraw without destroying content — the conservative outcome,
            // and never `terminal`, which asserts more than we measured.
            return .withdrawIdentity
        }
    }
}

/// True for transport failures that never reached the credential.
///
/// MOVED HERE UNCHANGED from `AuthManager.swift`, so the `ignore` outcome is
/// testable with a real `URLError`. Same domain, same codes, same recursive
/// walk: we must not treat offline / transient transport failures as auth
/// invalidation.
func isOfflineOrTransientNetworkError(_ error: Error) -> Bool {
    // Supabase Swift may wrap URLError inside NSError userInfo; inspect recursively.
    func extractNSErrorChain(_ error: Error) -> [NSError] {
        var out: [NSError] = []
        var current: NSError? = error as NSError
        var seen = Set<ObjectIdentifier>()
        while let ns = current {
            let oid = ObjectIdentifier(ns)
            if seen.contains(oid) { break }
            seen.insert(oid)
            out.append(ns)
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                current = underlying
            } else {
                break
            }
        }
        return out
    }

    for ns in extractNSErrorChain(error) {
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorInternationalRoamingOff,
                 NSURLErrorCallIsActive,
                 NSURLErrorDataNotAllowed,
                 NSURLErrorSecureConnectionFailed:
                return true
            default:
                break
            }
        }
    }
    return false
}
