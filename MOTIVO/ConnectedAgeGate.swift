//
//  ConnectedAgeGate.swift
//  MOTIVO
//
//  The adult-only gate for Études Connected (RELEASE.md, decided 2026-10-15).
//
//  Connected accepts only adults Apple reports as CONFIRMED through Declared Age
//  Range. Everything else is a refusal with a reason, and every refusal fails
//  closed to Solo. Études never asks anyone their age: Apple presents its own
//  sheet and returns a range plus how that range was set.
//
//  The rule is pure, so the decision that keeps children out of Connected is
//  unit-testable without Apple, a network or a view. Apple's types are mapped
//  into `Declaration` at the edge, in `outcome(for:)`.
//
//  Bounds arithmetic only, never gate-shape matching: Apple may override the
//  requested gate by region, and its sandbox returns ranges such as 13-15.
//

import Foundation
import os

#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif

enum ConnectedAgeGate {

    /// The single gate Études requests. Nothing below 18 changes any decision,
    /// so nothing finer is asked for.
    static let adultGate = 18

    /// How Apple says the range was set. Only `.confirmed` admits.
    ///
    /// `.other` covers Apple's deprecated granular cases (`paymentChecked`,
    /// `checkedByOtherMethod`, the guardian variants and so on) and any value
    /// added later. They are refused, deliberately: the decision names
    /// `.confirmed` alone, and a value we don't recognise can't establish it.
    enum Declaration: Equatable {
        case confirmed
        case selfDeclared
        case guardianDeclared
        case other
    }

    /// Why Connected was refused. The raw values are the reasons the server's
    /// anonymous refusal counter accepts, so they must not be renamed.
    enum RefusalReason: String, Equatable, CaseIterable {
        case under18 = "under_18"
        /// 18+, but self-declared, guardian-declared or not stated.
        case unconfirmedAdult = "unconfirmed_adult"
        case declined = "declined"
        /// An error, or a response shape we don't recognise.
        case unavailable = "unavailable"
        /// The device runs iOS 26.4, which can't report `.confirmed`.
        case iosUpdateNeeded = "ios_update_needed"
    }

    enum Outcome: Equatable {
        case confirmedAdult
        case refused(RefusalReason)
    }

    /// THE RULE. PURE.
    ///
    /// - A nil lowerBound means "below the lowest gate Apple used", so it is
    ///   under 18, whatever the upper bound says. Both bounds nil is no answer.
    /// - Under 18 is refused as under 18 whatever the declaration, so the
    ///   counter records the fact that matters most.
    /// - 18+ admits only when Apple says `.confirmed`.
    static func evaluate(lowerBound: Int?, upperBound: Int?, declaration: Declaration?) -> Outcome {
        guard let lower = lowerBound else {
            return upperBound == nil ? .refused(.unavailable) : .refused(.under18)
        }
        guard lower >= adultGate else { return .refused(.under18) }
        guard declaration == .confirmed else { return .refused(.unconfirmedAdult) }
        return .confirmedAdult
    }

    // MARK: - The result held on this device

    /// The last decisive answer from Apple on this device. Absent means never
    /// checked. Per device, not per identity: Apple answers for the Apple
    /// Account signed in to the device. Erase All wipes it with the rest of
    /// UserDefaults.
    ///
    /// Persisting it is allowed because access is a reversible decision
    /// (invariant 3): it is set only by a live Apple check, a later decisive
    /// refusal clears it, and the server row never depends on it.
    enum StoredResult: Equatable {
        case confirmed
        case refused(RefusalReason)

        var rawValue: String {
            switch self {
            case .confirmed: return "confirmed"
            case .refused(let reason): return reason.rawValue
            }
        }

        init?(rawValue: String) {
            if rawValue == "confirmed" { self = .confirmed }
            else if let reason = RefusalReason(rawValue: rawValue) { self = .refused(reason) }
            else { return nil }
        }
    }

    static let storedResultKey = "connectedAgeGate.result_v1"

    static func storedResult(in defaults: UserDefaults = .standard) -> StoredResult? {
        defaults.string(forKey: storedResultKey).flatMap(StoredResult.init(rawValue:))
    }

    static func setStoredResult(_ result: StoredResult?, in defaults: UserDefaults = .standard) {
        if let result { defaults.set(result.rawValue, forKey: storedResultKey) }
        else { defaults.removeObject(forKey: storedResultKey) }
    }

    /// The resolver's age condition. Only a stored confirmation admits.
    static func isConfirmedOnThisDevice(in defaults: UserDefaults = .standard) -> Bool {
        storedResult(in: defaults) == .confirmed
    }

    /// PURE. What to store after a check.
    ///
    /// `.unavailable` is an error, not an answer, so it leaves the stored
    /// result alone: a confirmed member isn't paused by a glitch, and a member
    /// never checked stays unchecked and is retried (Samuel, choice 1,
    /// 2026-10-15). Every other refusal is decisive and replaces it.
    static func nextStoredResult(current: StoredResult?, outcome: Outcome) -> StoredResult? {
        switch outcome {
        case .confirmedAdult: return .confirmed
        case .refused(.unavailable): return current
        case .refused(let reason): return .refused(reason)
        }
    }

    /// PURE. Whether to ask Apple without the person tapping anything.
    ///
    /// Never checked, or confirmed (to notice a withdrawal or a changed
    /// Apple Account): yes. A decisive refusal: no, so the person isn't shown
    /// Apple's sheet on every return to the app; they retry from Profile.
    /// The exception is iOS 26.4, retried automatically once iOS can answer.
    static func shouldCheckAutomatically(stored: StoredResult?, osCanReportConfirmed: Bool) -> Bool {
        switch stored {
        case nil, .confirmed?: return true
        case .refused(.iosUpdateNeeded)?: return osCanReportConfirmed
        case .refused?: return false
        }
    }

    static var osCanReportConfirmed: Bool {
        if #available(iOS 26.5, *) { return true }
        return false
    }

    /// PURE. Why Connected is paused on this device, for Profile's notice: an
    /// entitled member with an identity whose last decisive answer wasn't a
    /// confirmed adult. Never checked shows nothing, because a check is under
    /// way; a lapsed member has nothing to unpause.
    static func pauseReason(hasConnectedIdentity: Bool, isEntitled: Bool,
                            stored: StoredResult?) -> RefusalReason? {
        guard hasConnectedIdentity, isEntitled else { return nil }
        if case .refused(let reason)? = stored { return reason }
        return nil
    }

    /// PURE. THE SINGLE SHARE-DEFAULT RULE for a new session or post.
    ///
    /// Settled: Share defaults ON, unless the member chose Default to Private
    /// Posts. It is OFF while Apple hasn't confirmed an adult on this device,
    /// the protective direction for every unknown (formerly keyed on the 13-17
    /// band). The per-session toggle is unchanged.
    static func shareDefaultOn(adultConfirmed: Bool, defaultPostingIsPrivate: Bool) -> Bool {
        adultConfirmed && !defaultPostingIsPrivate
    }

    /// The user-facing reason. One place, so the join path, sign-in and the
    /// paused-member notice can't drift apart.
    static func refusalMessage(for reason: RefusalReason) -> String {
        switch reason {
        case .iosUpdateNeeded:
            return "Update iOS to join Études Connected. Études itself works as it does now."
        case .under18, .unconfirmedAdult, .declined, .unavailable:
            // Doesn't promise "try again" works at once: Apple can keep serving an
            // answer shared before the person confirmed (device QA 2026-10-16).
            return "Études Connected is for adults whose age Apple has confirmed. Confirm yours in Settings → [your name] → Personal Information → Age Confirmation, then try again. If you’ve already confirmed and still see this, Apple can take a while to update your answer for Études; if it doesn’t change, contact Support."
        }
    }

    #if canImport(DeclaredAgeRange)
    /// Maps Apple's response into the pure rule. A decline is never a range.
    @available(iOS 26.5, *)
    static func outcome(for response: AgeRangeService.Response) -> Outcome {
        switch response {
        case .declinedSharing:
            diagnosticLog.notice("age answer: declinedSharing")
            return .refused(.declined)
        case .sharing(let range):
            // DIAGNOSTIC, device QA 2026-10-16: what Apple actually returned,
            // to tell a cached self-declared answer from a deprecated "checked"
            // label on iOS 26.x. On-device console only; nothing is sent.
            diagnosticLog.notice("age answer: lower=\(String(describing: range.lowerBound), privacy: .public) upper=\(String(describing: range.upperBound), privacy: .public) declaration=\(String(describing: range.ageRangeDeclaration), privacy: .public)")
            return evaluate(lowerBound: range.lowerBound,
                            upperBound: range.upperBound,
                            declaration: range.ageRangeDeclaration.map(declaration(for:)))
        @unknown default:
            return .refused(.unavailable)
        }
    }

    private static let diagnosticLog = Logger(subsystem: "com.sdsongs.etudes", category: "ageGate")

    @available(iOS 26.5, *)
    static func declaration(for apple: AgeRangeService.AgeRangeDeclaration) -> Declaration {
        switch apple {
        case .confirmed: return .confirmed
        case .selfDeclared: return .selfDeclared
        case .guardianDeclared: return .guardianDeclared
        default: return .other
        }
    }
    #endif

    /// Asks Apple, once, and reduces the answer to an outcome. Any thrown error
    /// is `.unavailable`; iOS 26.4 is `.iosUpdateNeeded` without asking.
    #if canImport(DeclaredAgeRange)
    @MainActor
    static func check(using requestAgeRange: DeclaredAgeRangeAction) async -> Outcome {
        guard #available(iOS 26.5, *) else { return .refused(.iosUpdateNeeded) }
        do {
            return outcome(for: try await requestAgeRange(ageGates: adultGate))
        } catch {
            return .refused(.unavailable)
        }
    }
    #endif
}
