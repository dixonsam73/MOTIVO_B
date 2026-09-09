//
//  AppSetUpGateFetchCostTests.swift
//  MOTIVOTests
//
//  PHASE 5 · C-56 — MEASUREMENT ONLY, BEFORE ANY IMPLEMENTATION.
//
//  **WHAT THIS IS.** A faithful reproduction of the Core Data statements that
//  `PracticeTimerView.body` issues on ONE evaluation, timed on an in-memory
//  store. The statements are copied from the three body-reachable sites named
//  in the C-56 census.
//
//  **WHAT THIS IS NOT, AND MUST NEVER BE DESCRIBED AS.** It is NOT an
//  observation of the view. It does not evaluate `body`, it does not count how
//  often `body` is evaluated, and it is not device evidence. It measures the
//  COST OF ONE EVALUATION'S READS and nothing else. The frequency term — the
//  one C-55 showed can be unbounded — is deliberately absent, because nothing
//  offline can supply it.
//
//  It asserts the SHAPE of the read set (so the measurement cannot go vacuous
//  if the fixture stops being seeded) and never asserts a duration.
//

import XCTest
import CoreData
@testable import Etudes

@MainActor
final class AppSetUpGateFetchCostTests: XCTestCase {

    /// The read set of ONE `PracticeTimerView.body` evaluation in the worst
    /// reachable case — Solo (early return not taken), home presentation, no
    /// avatar image — transcribed from:
    ///   * `PracticeTimerView:1244` + `:3618`  (`requiresAppSetUpNow`)
    ///   * `PracticeTimerView:1222` + `:3618`  (`appSetUpCompletenessKey`, via `.task(id:)`)
    ///   * `PracticeTimerView:1357`            (`homeTopBar` initials fallback)
    @discardableResult
    private func oneBodyEvaluationReadSet(_ ctx: NSManagedObjectContext) -> (profiles: Int, instruments: Int) {
        var profileReads = 0
        var instrumentReads = 0

        func fetchProfile() -> Profile? {
            let req: NSFetchRequest<Profile> = Profile.fetchRequest()
            req.fetchLimit = 1
            profileReads += 1
            return try? ctx.fetch(req).first
        }

        func fetchInstruments() -> [Instrument] {
            let req: NSFetchRequest<Instrument> = Instrument.fetchRequest()
            req.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            instrumentReads += 1
            return (try? ctx.fetch(req)) ?? []
        }

        // Site 1 — requiresAppSetUpNow()
        if let p = fetchProfile() {
            let hasName = !(p.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            if hasName { _ = fetchInstruments().contains(where: { $0.profile == p }) }
        }

        // Site 2 — appSetUpCompletenessKey, evaluated as the `.task(id:)` key
        if let p = fetchProfile() {
            let hasName = !(p.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            if hasName { _ = fetchInstruments().contains(where: { $0.profile == p }) }
        }

        // Site 3 — homeTopBar initials fallback
        _ = fetchProfile()?.name

        return (profileReads, instrumentReads)
    }

    private func seededContext(instrumentCount: Int) -> NSManagedObjectContext {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let profile = Profile(context: ctx)
        profile.name = "Samuel Dixon"
        for i in 0..<instrumentCount {
            let inst = Instrument(context: ctx)
            inst.name = String(format: "Instrument %03d", i)
            inst.profile = profile
        }
        try? ctx.save()
        return ctx
    }

    /// NON-VACUITY: the fixture really is populated, and one body evaluation
    /// really does issue three Profile fetches and two unbounded Instrument
    /// fetches. If a future change removes a site, this fails rather than
    /// silently measuring less.
    func testOneBodyEvaluationIssuesThreeProfileAndTwoInstrumentFetches() {
        let ctx = seededContext(instrumentCount: 8)
        let counts = oneBodyEvaluationReadSet(ctx)
        XCTAssertEqual(counts.profiles, 3, "body-time Profile fetches per evaluation")
        XCTAssertEqual(counts.instruments, 2, "body-time unbounded Instrument fetches per evaluation")

        let req: NSFetchRequest<Instrument> = Instrument.fetchRequest()
        XCTAssertEqual((try? ctx.count(for: req)) ?? 0, 8, "fixture must be populated or the timing is meaningless")
    }

    // MARK: - Measurement
    //
    // Each of these runs exactly `iterations` reproductions of one body
    // evaluation's read set. The number to read is the XCTest-reported
    // DURATION of the test, against `testCostControlNoFetches` as the
    // baseline — the loop, the store construction and the timing harness are
    // identical in all four, so the difference is the Core Data work.

    private static let iterations = 2000

    private func runLoop(instrumentCount: Int, fetching: Bool) {
        let ctx = seededContext(instrumentCount: instrumentCount)
        for _ in 0..<Self.iterations {
            if fetching {
                oneBodyEvaluationReadSet(ctx)
            } else {
                _ = ctx.name
            }
        }
    }

    func testCostControlNoFetches() { runLoop(instrumentCount: 8, fetching: false) }
    func testCostInstruments01()    { runLoop(instrumentCount: 1, fetching: true) }
    func testCostInstruments08()    { runLoop(instrumentCount: 8, fetching: true) }
    func testCostInstruments40()    { runLoop(instrumentCount: 40, fetching: true) }
}
