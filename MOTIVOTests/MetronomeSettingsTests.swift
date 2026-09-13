import XCTest
@testable import Etudes

final class MetronomeSettingsTests: XCTestCase {
    func testDefaultsPreserveExistingUnaccentedPulse() {
        let settings = MetronomeSettings()
        XCTAssertEqual(settings.bpm, 80); XCTAssertEqual(settings.meter, .simple(4))
        XCTAssertFalse(settings.accent); XCTAssertEqual(settings.volume, 0.7)
        XCTAssertEqual(settings.subdivision, .beat)
    }
    func testMeterChangesPreserveCompatibleNotationAndTempo() {
        var settings = MetronomeSettings(); settings.bpm = 93; settings.subdivision = .quavers
        settings.selectMeter(.compound(6))
        XCTAssertEqual(settings.subdivision, .quavers); XCTAssertEqual(settings.bpm, 93)
        XCTAssertEqual(settings.subdivision.count(in: settings.meter), 3)
        XCTAssertFalse(settings.accent)
        settings.subdivision = .semiquavers; settings.selectMeter(.simple(3))
        XCTAssertEqual(settings.subdivision, .semiquavers)
        XCTAssertEqual(settings.subdivision.count(in: settings.meter), 4)
    }
    func testCompoundMeterDoesNotMislabelTriplets() {
        var settings = MetronomeSettings(); settings.subdivision = .triplets
        settings.selectMeter(.compound(6))
        XCTAssertEqual(settings.subdivision, .beat)
        XCTAssertFalse(MetronomeSubdivision.choices(in: settings.meter).contains(.triplets))
        XCTAssertEqual(MetronomeSubdivision.quavers.label(in: settings.meter), "Quavers")
    }
    func testAsymmetricMetersUseQuaversWithoutEnablingAccent() {
        for numerator in [5, 7, 11] {
            var settings = MetronomeSettings(); settings.bpm = 93
            settings.selectMeter(.asymmetric(numerator))
            XCTAssertFalse(settings.accent); XCTAssertEqual(settings.bpm, 93)
            XCTAssertEqual(settings.meter.beats, numerator)
            XCTAssertEqual(settings.meter.denominator, 8)
            XCTAssertEqual(settings.meter.beatUnit, .quaver)
            XCTAssertEqual(settings.meter.beatLabel, "Quaver")
            XCTAssertEqual(MetronomeSubdivision.quavers.count(in: settings.meter), 2)
            XCTAssertEqual(MetronomeSubdivision.quavers.label(in: settings.meter), "Semiquavers")
            XCTAssertEqual(MetronomeSubdivision.triplets.label(in: settings.meter), "Semiquaver triplets")
            XCTAssertEqual(MetronomeSubdivision.semiquavers.label(in: settings.meter), "Demisemiquavers")
        }
    }
    func testPackedControlRoundTripsEverySupportedCombination() {
        for meter in MetronomeMeter.standard {
            for subdivision in MetronomeSubdivision.choices(in: meter) {
                var settings = MetronomeSettings(); settings.meter = meter; settings.subdivision = subdivision
                settings.bpm = 137; settings.accent = true; settings.volume = 0.123
                let decoded = MetronomeRenderSettings(command: settings.command(running: true))
                XCTAssertEqual(decoded.bpm, 137); XCTAssertEqual(decoded.beats, meter.beats)
                XCTAssertEqual(decoded.divisions, subdivision.count(in: meter))
                XCTAssertEqual(decoded.volume, 0.123, accuracy: 0.0001)
                XCTAssertTrue(decoded.accent); XCTAssertTrue(decoded.running); XCTAssertEqual(decoded.meterCode, meter.code)
            }
        }
    }
    func testMeterIdentitiesIncludeSixFourAndRemainDistinctAcrossBeatUnits() {
        XCTAssertEqual(MetronomeMeter.standard.map(\.label),
                       ["2/4", "3/4", "4/4", "5/4", "6/4", "7/4", "2/8", "3/8", "4/8", "5/8", "6/8", "7/8", "8/8", "9/8", "10/8", "11/8", "12/8"])
        XCTAssertEqual(Set(MetronomeMeter.standard.map(\.code)).count, MetronomeMeter.standard.count)
        XCTAssertEqual(MetronomeMeter.simple(6).beats, 6)
        XCTAssertEqual(MetronomeMeter.compound(6).beats, 2)
        XCTAssertNotEqual(MetronomeMeter.simple(5).code, MetronomeMeter.asymmetric(5).code)
    }
    func testInvalidControlValuesAreBoundedAndCannotTurnOnPlayback() {
        var settings = MetronomeSettings(); settings.bpm = -1; settings.volume = .nan
        var decoded = MetronomeRenderSettings(command: settings.command(running: false))
        XCTAssertEqual(decoded.bpm, 20); XCTAssertEqual(decoded.volume, 0); XCTAssertFalse(decoded.running)
        settings.bpm = 9999; settings.volume = 3
        decoded = .init(command: settings.command(running: true))
        XCTAssertEqual(decoded.bpm, 400); XCTAssertEqual(decoded.volume, 1)
    }
    func testSlowTapTempoIncludesTwentyBPM() {
        for bpm in [20, 25, 29, 30, 80, 400] {
            var tap = MetronomeTapTempo()
            XCTAssertNil(tap.tap(at: 100))
            XCTAssertEqual(tap.tap(at: 100 + 60 / Double(bpm)), bpm)
            XCTAssertEqual(tap.tap(at: 100 + 120 / Double(bpm)), bpm)
        }
    }
    func testAbandonedTapSequenceStartsAgain() {
        var tap = MetronomeTapTempo()
        _ = tap.tap(at: 1); XCTAssertEqual(tap.tap(at: 2), 60)
        XCTAssertNil(tap.tap(at: 6)); XCTAssertEqual(tap.tap(at: 6.5), 120)
    }
    func testTapRejectsDuplicateNonmonotonicAndNonfiniteInput() {
        var tap = MetronomeTapTempo(); _ = tap.tap(at: 10)
        XCTAssertNil(tap.tap(at: 10)); XCTAssertNil(tap.tap(at: 9))
        XCTAssertNil(tap.tap(at: .nan)); XCTAssertNil(tap.tap(at: 10.01))
        XCTAssertEqual(tap.tap(at: 11), 60)
    }
    func testTapHistoryIsBoundedAndCanBeResetForBeatUnitChange() {
        var tap = MetronomeTapTempo()
        for i in 0..<20 { _ = tap.tap(at: Double(i)) }
        for i in 1...5 { _ = tap.tap(at: 19 + Double(i) * 0.5) }
        XCTAssertEqual(tap.tap(at: 22), 120)
        tap.reset(); XCTAssertNil(tap.tap(at: 23))
    }
}
