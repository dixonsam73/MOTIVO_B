//
//  DeclaredAgeRangeService.swift
//  MOTIVO
//
//  PHASE 5 · CP-3 — Apple's Declared Age Range, and the minimal band derived from it.
//
//  ÉTUDES DOES NOT ASK ANYONE THEIR AGE. Apple presents its own system sheet and
//  returns a RANGE. This file requests that range and reduces it to the smallest
//  state the product needs. Nothing here, in the UI, or in the record may imply
//  Études asked the member a question about their age.
//
//  ── DERIVATION IS BOUNDS ARITHMETIC, NEVER GATE-SHAPE MATCHING ─────────────
//
//  Apple's reference states the system MAY OVERRIDE the requested gates for the
//  person's location. Its own sandbox proves it: the documented test cases return
//  13-15 and 16-17 as separate ranges, not the single 13-17 we ask for. A client
//  that pattern-matched on the numbers 13 and 18 would misclassify two of six
//  official fixtures -- and would do so PERMISSIVELY if it fell through to an
//  adult default. So the only input is the bounds.
//
//  ── AND IT FAILS CLOSED ON THE QUESTION THAT MATTERS ───────────────────────
//
//  A nil lowerBound means "below the lowest gate the system used", which cannot
//  affirmatively establish 13-or-over. It is therefore INELIGIBLE, not "probably
//  a teenager". Where a regulator requires a higher bottom gate this over-blocks,
//  which is the correct outcome in that jurisdiction anyway.
//
//  ── PROVENANCE IS NEVER READ ───────────────────────────────────────────────
//
//  `ageRangeDeclaration` is deliberately not inspected and never stored: it
//  changes no decision Études makes. A pleasant side effect is that its
//  availability surface (`.confirmed` is iOS 26.5, the granular cases are 26.2
//  and deprecated) is never touched at our 26.2 floor.
//

import Foundation

#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif

/// The complete persisted age state. There are exactly two values, and neither
/// is an age: absence of a row is the unknown state and is handled by the shape
/// of every server predicate rather than by a branch anyone can forget.
enum AgeBand: String, Equatable, CaseIterable {
    case band13to17 = "band_13_17"
    case band18Plus = "band_18_plus"

    /// Under-18 members receive the protective defaults.
    var isMinor: Bool { self == .band13to17 }
}

/// What a request resolved to. `ineligible` and `unavailable` are kept apart
/// because they are different facts, even though both refuse Connected: one is
/// "Apple told us, and the answer is below our minimum", the other is "we were
/// not told".
enum DeclaredAgeRangeOutcome: Equatable {
    case band(AgeBand)
    case ineligible
    case unavailable
}

enum DeclaredAgeRangeService {

    /// The gates Études requests. 13 is the product minimum for Connected; 18
    /// separates the adult defaults from the protective ones.
    static let minimumGate = 13
    static let adultGate = 18

    /// PURE. No Apple types, no I/O, no state — so the rule that decides a
    /// child's treatment is unit-testable on its own.
    static func derive(lowerBound: Int?, upperBound: Int?) -> DeclaredAgeRangeOutcome {
        guard let lower = lowerBound else { return .ineligible }
        if lower >= adultGate { return .band(.band18Plus) }
        if lower >= minimumGate { return .band(.band13to17) }
        return .ineligible
    }

    /// THE SINGLE SHARE-DEFAULT RULE. Pure, so the decision that governs a
    /// child's default exposure is unit-testable without a view or a network.
    ///
    /// Share defaults ON only for a CONFIRMED adult band. `band_13_17`, and every
    /// unknown -- not fetched, fetch failed, no band established -- default OFF.
    /// The failure direction is the protective one, which is the inverse of what
    /// this code did before: `fetchDefaultPostingIsPrivate()` returns false on a
    /// missing profile AND on a fetch error, so every unknown used to resolve ON.
    ///
    /// This governs the DEFAULT only. The per-session Share toggle is unchanged
    /// and a 13-17 member may still deliberately share.
    static func shareDefaultOn(band: AgeBand?, defaultPostingIsPrivate: Bool) -> Bool {
        guard band == .band18Plus else { return false }
        return !defaultPostingIsPrivate
    }

    #if canImport(DeclaredAgeRange)
    /// Maps Apple's response. A decline is `unavailable`, never a band.
    static func outcome(for response: AgeRangeService.Response) -> DeclaredAgeRangeOutcome {
        switch response {
        case .declinedSharing:
            return .unavailable
        case .sharing(let range):
            return derive(lowerBound: range.lowerBound, upperBound: range.upperBound)
        @unknown default:
            // A response shape we do not recognise cannot establish eligibility.
            return .unavailable
        }
    }
    #endif
}
