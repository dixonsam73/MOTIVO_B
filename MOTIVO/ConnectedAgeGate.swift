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

    /// The user-facing reason. One place, so the join path, sign-in and the
    /// paused-member notice can't drift apart.
    static func refusalMessage(for reason: RefusalReason) -> String {
        switch reason {
        case .iosUpdateNeeded:
            return "Update iOS to join Études Connected. Études itself works as it does now."
        case .under18, .unconfirmedAdult, .declined, .unavailable:
            return "Études Connected is for adults. Confirm you’re 18+ in Settings → [your name] → Personal Information → Age Confirmation, then try again."
        }
    }

    #if canImport(DeclaredAgeRange)
    /// Maps Apple's response into the pure rule. A decline is never a range.
    @available(iOS 26.5, *)
    static func outcome(for response: AgeRangeService.Response) -> Outcome {
        switch response {
        case .declinedSharing:
            return .refused(.declined)
        case .sharing(let range):
            return evaluate(lowerBound: range.lowerBound,
                            upperBound: range.upperBound,
                            declaration: range.ageRangeDeclaration.map(declaration(for:)))
        @unknown default:
            return .refused(.unavailable)
        }
    }

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
