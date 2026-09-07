//
//  SessionRefreshPolicyTests.swift
//  MOTIVOTests
//
//  The session-management fix of 2026-09-07. Coverage here was ZERO when the
//  token-rotation loop was diagnosed, which is why a refresh path that could
//  destroy user-typed content survived unnoticed.
//

import XCTest
@testable import Etudes

final class SessionRefreshPolicyTests: XCTestCase {

    // MARK: - Fixtures

    /// A JWT with only the `exp` claim. Unsigned on purpose: `accessTokenExpiry`
    /// verifies nothing and authorises nothing, so a real signature would add
    /// no evidence to a test of the expiry read.
    private func jwt(expiring at: Date) -> String {
        let payload = try! JSONSerialization.data(
            withJSONObject: ["exp": Int(at.timeIntervalSince1970), "sub": UUID().uuidString])
        let b64 = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(b64).signature"
    }

    /// GoTrue's response when the presented refresh token has already been
    /// spent by another request. HTTP 400, and the discriminator is the
    /// message text -- it is an `invalid_grant` like a dead token is.
    private struct AlreadyUsedError: LocalizedError {
        var errorDescription: String? { "Invalid Refresh Token: Already Used" }
    }

    private struct RevokedTokenError: LocalizedError {
        var errorDescription: String? { "Invalid Refresh Token: Refresh Token Not Found" }
    }

    private struct UnrecognisedError: LocalizedError {
        var errorDescription: String? { "something nobody has modelled" }
    }

    private func reconciliation(attempted: String?,
                               persisted: String?,
                               accessExpiry: Date?,
                               now: Date = Date()) -> SessionRefreshPolicy.SessionReconciliation {
        .init(attemptedRefreshToken: attempted,
              persistedRefreshToken: persisted,
              persistedAccessTokenExpiry: accessExpiry,
              now: now)
    }

    // MARK: - §8 · the four-way disposition

    /// THE BUG. A superseded token is a lost race, not a dead credential, and
    /// answering it with `signOut()` destroyed a live session AND the user's
    /// attachment titles. Fails against the pre-fix code, which had no such
    /// outcome to return.
    func testAlreadyUsedWithNewerSessionRecovers() {
        let now = Date()
        let d = SessionRefreshPolicy.refreshFailureDisposition(
            AlreadyUsedError(),
            reconciliation: reconciliation(attempted: "TOKEN-WE-PRESENTED",
                                           persisted: "TOKEN-THE-WINNER-WROTE",
                                           accessExpiry: now.addingTimeInterval(3600),
                                           now: now))
        XCTAssertEqual(d, .recoverWithNewerSession)
    }

    /// The other half of the same condition, and the reason recovery may never
    /// be automatic: with nothing newer present, reporting success would leave
    /// the client believing it is authenticated with no valid session -- the
    /// zombie state `signOut()` was originally written to prevent.
    func testAlreadyUsedWithNothingNewerWithdrawsIdentity() {
        let now = Date()
        let d = SessionRefreshPolicy.refreshFailureDisposition(
            AlreadyUsedError(),
            reconciliation: reconciliation(attempted: "TOKEN-WE-PRESENTED",
                                           persisted: "TOKEN-WE-PRESENTED",
                                           accessExpiry: now.addingTimeInterval(3600),
                                           now: now))
        XCTAssertEqual(d, .withdrawIdentity)
    }

    /// A rotated token whose access token is ALREADY EXPIRED is not a usable
    /// session, so it is not recovery. Absence of evidence is never recovery.
    func testAlreadyUsedWithNewerButExpiredSessionWithdrawsIdentity() {
        let now = Date()
        let d = SessionRefreshPolicy.refreshFailureDisposition(
            AlreadyUsedError(),
            reconciliation: reconciliation(attempted: "OLD",
                                           persisted: "NEWER",
                                           accessExpiry: now.addingTimeInterval(-30),
                                           now: now))
        XCTAssertEqual(d, .withdrawIdentity)
    }

    /// An unreadable expiry cannot establish usability either.
    func testAlreadyUsedWithUnreadableExpiryWithdrawsIdentity() {
        let d = SessionRefreshPolicy.refreshFailureDisposition(
            AlreadyUsedError(),
            reconciliation: reconciliation(attempted: "OLD", persisted: "NEWER", accessExpiry: nil))
        XCTAssertEqual(d, .withdrawIdentity)
    }

    /// MUST STAY. This is correct behaviour today, and it is a DIFFERENT AXIS
    /// from the other three: they classify how terminal a credential failure
    /// is, while this says the credential was never reached. An implementer
    /// folding offline into `withdrawIdentity` would withdraw the Connected
    /// identity on every foreground in flight mode.
    func testOfflineIsIgnoredAndWithdrawsNothing() {
        for code in [URLError.notConnectedToInternet,
                     .timedOut,
                     .networkConnectionLost,
                     .cannotConnectToHost] {
            let d = SessionRefreshPolicy.refreshFailureDisposition(
                URLError(code),
                reconciliation: reconciliation(attempted: "OLD", persisted: "NEWER",
                                               accessExpiry: Date().addingTimeInterval(3600)))
            XCTAssertEqual(d, .ignore, "URLError.\(code) must not be treated as auth invalidation")
        }
    }

    /// Offline wins even when the reconciliation evidence would otherwise
    /// support recovery -- transport is checked first, deliberately.
    func testOfflineWrappedInsideAnNSErrorChainIsStillIgnored() {
        let wrapped = NSError(domain: "Supabase", code: 1,
                              userInfo: [NSUnderlyingErrorKey: URLError(.notConnectedToInternet)])
        XCTAssertEqual(SessionRefreshPolicy.classify(wrapped), .offlineOrTransient)
    }

    /// A genuinely dead credential.
    func testRevokedTokenIsTerminal() {
        let d = SessionRefreshPolicy.refreshFailureDisposition(
            RevokedTokenError(),
            reconciliation: reconciliation(attempted: "OLD", persisted: "OLD", accessExpiry: nil))
        XCTAssertEqual(d, .terminal)
    }

    /// "Already Used" also contains "invalid refresh token", so ordering inside
    /// `classify` is load-bearing: were the terminal markers checked first,
    /// every lost race would be reported as a dead credential.
    func testAlreadyUsedIsNotMisclassifiedAsTerminal() {
        XCTAssertEqual(SessionRefreshPolicy.classify(AlreadyUsedError()), .supersededRefreshToken)
        XCTAssertEqual(SessionRefreshPolicy.classify(RevokedTokenError()), .terminalCredential)
    }

    /// An unmodelled failure is not confirmed authenticated and not shown to be
    /// dead. It withdraws -- never `terminal`, which would assert more than was
    /// measured, and never success.
    func testUnrecognisedFailureWithdrawsIdentity() {
        let d = SessionRefreshPolicy.refreshFailureDisposition(
            UnrecognisedError(),
            reconciliation: reconciliation(attempted: "OLD", persisted: "NEWER",
                                           accessExpiry: Date().addingTimeInterval(3600)))
        XCTAssertEqual(d, .withdrawIdentity)
    }

    /// The disposition has FOUR cases and never reports success except on
    /// positive evidence. Pinned as a set so a future third state cannot be
    /// added silently.
    func testDispositionNeverReportsSuccessWithoutPositiveEvidence() {
        let noEvidence = reconciliation(attempted: "OLD", persisted: nil, accessExpiry: nil)
        for error in [AlreadyUsedError() as Error, RevokedTokenError(), UnrecognisedError()] {
            XCTAssertNotEqual(
                SessionRefreshPolicy.refreshFailureDisposition(error, reconciliation: noEvidence),
                .recoverWithNewerSession)
        }
    }

    // MARK: - §8 · the expiry gate

    /// A still-valid token needs no rotation. This is what starves the
    /// refresh/hydration feedback loop of its 34-rotations-in-20.5s burst.
    func testStillValidTokenDoesNotRefresh() {
        let now = Date()
        XCTAssertFalse(SessionRefreshPolicy.shouldRefresh(
            accessTokenExpiry: now.addingTimeInterval(3600), now: now))
    }

    func testExpiredOrNearlyExpiredTokenRefreshes() {
        let now = Date()
        XCTAssertTrue(SessionRefreshPolicy.shouldRefresh(accessTokenExpiry: now.addingTimeInterval(-1), now: now))
        XCTAssertTrue(SessionRefreshPolicy.shouldRefresh(accessTokenExpiry: now.addingTimeInterval(30), now: now),
                      "inside the default skew")
        XCTAssertFalse(SessionRefreshPolicy.shouldRefresh(accessTokenExpiry: now.addingTimeInterval(90), now: now),
                       "outside the default skew")
    }

    /// Unknown expiry refreshes. The failure direction is a redundant round
    /// trip, never a request issued with a dead token.
    func testUnknownExpiryRefreshes() {
        XCTAssertTrue(SessionRefreshPolicy.shouldRefresh(accessTokenExpiry: nil, now: Date()))
    }

    func testAccessTokenExpiryReadsTheExpClaim() {
        let expiry = Date(timeIntervalSince1970: 2_000_000_000)
        let read = SessionRefreshPolicy.accessTokenExpiry(jwt(expiring: expiry))
        XCTAssertEqual(read?.timeIntervalSince1970 ?? 0, expiry.timeIntervalSince1970, accuracy: 1)
    }

    func testAccessTokenExpiryRejectsMalformedInput() {
        for bad in [nil, "", "not-a-jwt", "only.two", "a.!!!not-base64!!!.c"] as [String?] {
            XCTAssertNil(SessionRefreshPolicy.accessTokenExpiry(bad), "should not read an expiry from \(bad ?? "nil")")
        }
    }

    /// End to end through the gate: a token read from a real JWT is honoured.
    func testFreshJWTIsNotRefreshedAndStaleJWTIs() {
        let now = Date()
        let fresh = SessionRefreshPolicy.accessTokenExpiry(jwt(expiring: now.addingTimeInterval(3600)))
        let stale = SessionRefreshPolicy.accessTokenExpiry(jwt(expiring: now.addingTimeInterval(-3600)))
        XCTAssertFalse(SessionRefreshPolicy.shouldRefresh(accessTokenExpiry: fresh, now: now))
        XCTAssertTrue(SessionRefreshPolicy.shouldRefresh(accessTokenExpiry: stale, now: now))
    }
}
