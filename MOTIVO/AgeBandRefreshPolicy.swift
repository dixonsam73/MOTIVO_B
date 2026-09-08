//
//  AgeBandRefreshPolicy.swift
//  MOTIVO
//
//  PHASE 5 · P5-G / D1 — periodic re-derivation of Apple's declared age range.
//
//  WHY THIS EXISTS. Apple provides NO event, notification, publisher or
//  changed-value signal of any kind for the declared age range — established by
//  reading the whole framework interface, not by searching for one. The value
//  is cached and changes only on the anniversary of the person's original
//  declaration, or when they clear it in Settings. So the ONLY way to learn
//  about a change is to ask again, and Apple designs for exactly that:
//  "the API will be called often ... apps won't need to worry that calling the
//  API will prompt the user too many times."
//
//  ── THE CADENCE IS A LAG BOUND, NOT A MODEL OF APPLE'S CLOCK ───────────────
//
//  30 days. Its purpose is NOT to approximate the declaration anniversary,
//  which we cannot know and must never try to store. It bounds the lag between
//  Apple beginning to return a changed range and Études observing it.
//
//  ── WHAT IS STORED, AND WHAT IS NOT ───────────────────────────────────────
//
//  Two local timestamps per Études identity, and nothing else. NO date of
//  birth, NO declaration anniversary, NO `ageRangeDeclaration` provenance, NO
//  refusal counter and no history. Each records only WHEN ÉTUDES LAST ASKED,
//  which is neither an age nor provenance.
//

import Foundation

/// What a refresh concluded, from the point of view of what may be written.
///
/// Establishment collapses `.ineligible` and `.unavailable` **in effect**,
/// because both refuse Connected. **REFRESH MUST NOT**, and keeping them apart
/// is the whole point of this type: one is "Apple told us, and the answer is
/// below our minimum", the other is "we were not told".
enum AgeBandRefreshDecision: Equatable {
    /// A conclusive, eligible band. Upsert it and clear any withholding.
    case establish(AgeBand)
    /// Apple told us, and the answer is below the minimum gate. Withhold
    /// eligibility. **Never writes a band and never erases one.**
    case withhold
    /// We were not told — declined, unavailable, unknown shape, or transport
    /// failure. **Change nothing at all.**
    case retainSilently
}

enum AgeBandRefreshPolicy {

    /// The product cadence, after a CONCLUSIVE ELIGIBLE result.
    static let cadence: TimeInterval = 30 * 24 * 60 * 60

    /// The coarse retry after an inconclusive or ineligible result. Deliberately
    /// far longer than the in-memory 60-second cooldown, which exists to stop
    /// re-entrancy within a session and is NOT a throttle for repeated automatic
    /// Apple requests.
    static let retryInterval: TimeInterval = 24 * 60 * 60

    // MARK: - Pure decision

    /// PURE. Maps an Apple outcome to what may be written, for an identity that
    /// ALREADY has an established band.
    ///
    /// **`.unavailable` NEVER erases or downgrades an established band.** Apple
    /// being temporarily unavailable, or a person declining to share, is not
    /// evidence about anybody's age.
    static func decide(outcome: DeclaredAgeRangeOutcome) -> AgeBandRefreshDecision {
        switch outcome {
        case .band(let band): return .establish(band)
        case .ineligible:     return .withhold
        case .unavailable:    return .retainSilently
        }
    }

    /// PURE. Is an AUTOMATIC refresh due?
    ///
    /// Both clocks must be due. An explicit member-initiated check does not call
    /// this at all — see `ProfileView`'s Check Again action.
    static func isAutomaticRefreshDue(lastConclusiveAt: Date?,
                                      lastAttemptAt: Date?,
                                      now: Date) -> Bool {
        if let conclusive = lastConclusiveAt,
           now.timeIntervalSince(conclusive) < cadence { return false }
        if let attempt = lastAttemptAt,
           now.timeIntervalSince(attempt) < retryInterval { return false }
        return true
    }

    /// PURE. Which clocks a decision stamps.
    ///
    /// **Only a conclusive eligible band moves the 30-day clock**, so an
    /// unsuccessful explicit check can never delay the next automatic refresh by
    /// a month. Everything else moves only the 24-hour attempt clock.
    static func stampsConclusive(_ decision: AgeBandRefreshDecision) -> Bool {
        if case .establish = decision { return true }
        return false
    }

    static func stampsAttempt(_ decision: AgeBandRefreshDecision) -> Bool {
        // Every outcome records an attempt, including success — a successful
        // refresh is also the most recent attempt, and recording it keeps the
        // two clocks consistent.
        true
    }

    // MARK: - Storage (per identity, local, minimal)

    private static func conclusiveKey(_ userID: String) -> String { "p5g.ageBand.refreshedAt.\(userID)" }
    private static func attemptKey(_ userID: String) -> String { "p5g.ageBand.attemptedAt.\(userID)" }

    static func lastConclusive(userID: String, defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: conclusiveKey(userID)) as? Date
    }

    static func lastAttempt(userID: String, defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: attemptKey(userID)) as? Date
    }

    static func record(decision: AgeBandRefreshDecision,
                       userID: String,
                       now: Date = Date(),
                       defaults: UserDefaults = .standard) {
        if stampsAttempt(decision) { defaults.set(now, forKey: attemptKey(userID)) }
        if stampsConclusive(decision) { defaults.set(now, forKey: conclusiveKey(userID)) }
    }

    /// Cleared by account deletion and Erase All. These are operational
    /// timestamps carrying no age data, but a key that outlives an erase is
    /// exactly the C-28/C-48 class of defect, so they are swept deliberately
    /// rather than left behind as harmless.
    static func clear(userID: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: conclusiveKey(userID))
        defaults.removeObject(forKey: attemptKey(userID))
    }

    /// Sweeps every identity's keys, for the erase path where the identity may
    /// already have been withdrawn before the sweep runs.
    static func clearAll(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("p5g.ageBand.refreshedAt.") || key.hasPrefix("p5g.ageBand.attemptedAt.") {
            defaults.removeObject(forKey: key)
        }
    }
}
